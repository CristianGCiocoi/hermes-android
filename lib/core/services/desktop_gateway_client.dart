import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/gateway_interaction_mode.dart';
import 'connection_manager.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'ws_client.dart';

typedef DesktopAsyncEventCallback =
    void Function(String mobileSessionId, StreamEvent event);
typedef DesktopConnectionCallback =
    void Function(DesktopConnectionState connectionState);
typedef DesktopSessionPermissionCallback =
    void Function(String mobileSessionId, bool effectiveFullControl);
typedef DesktopInteractionModeCallback =
    void Function(String mobileSessionId, GatewayInteractionModeState state);

enum DesktopConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Authenticated JSON-RPC transport for a Hermes Desktop remote gateway.
///
/// The mobile OpenAI-compatible endpoint remains available for legacy
/// profiles. When a connection supplies [SavedConnection.desktopGatewayUrl],
/// chat writes and interactive events use this one Desktop session transport.
class DesktopGatewayClient {
  final String _connectionId;
  final String _baseUrl;
  final DashboardClient _dashboard;
  final String _documentProfile;
  final String? _atlasProfile;
  WsClient? _ws;
  final Map<String, String> _gatewaySessionIds = {};
  final Map<String, bool> _effectiveFullControl = {};
  final Map<String, GatewayInteractionModeState> _interactionModeStates = {};
  GatewayInteractionModeCapability? _interactionModeCapability;
  DesktopAsyncEventCallback? _asyncEventListener;
  DesktopConnectionCallback? _connectionListener;
  DesktopSessionPermissionCallback? _sessionPermissionListener;
  DesktopInteractionModeCallback? _interactionModeListener;
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;

  static const _asyncEventTypes = {
    'background.complete',
    'review.summary',
    'notification.show',
    'notification.clear',
    'subagent.spawn_requested',
    'subagent.start',
    'subagent.thinking',
    'subagent.tool',
    'subagent.progress',
    'subagent.complete',
    'session.info',
  };

  DesktopGatewayClient._({
    required this._connectionId,
    required this._baseUrl,
    required this._dashboard,
    required this._documentProfile,
    required this._atlasProfile,
  });

  factory DesktopGatewayClient.fromConnection(SavedConnection connection) {
    final raw = connection.desktopGatewayUrl?.trim() ?? '';
    if (raw.isEmpty) {
      throw ArgumentError('A Desktop Gateway URL is required for this feature');
    }
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Desktop Gateway URL must be an http(s) URL');
    }
    final baseUri = uri.replace(query: '', fragment: '');
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    final port = baseUri.hasPort
        ? baseUri.port
        : baseUri.scheme == 'https'
        ? 443
        : 80;
    final baseUrl = SavedConnection.joinBaseUrl(
      '${baseUri.scheme}://${baseUri.host}:$port',
      pathPrefix,
    );
    final requestedPrefix = connection.gatewayPrefix?.trim() ?? '';
    final atlasProfile = connection.atlasOwnerEnabled
        ? (requestedPrefix.isEmpty
              ? 'organizator'
              : requestedPrefix.substring(1))
        : null;
    return DesktopGatewayClient._(
      connectionId: connection.id,
      baseUrl: baseUrl,
      dashboard: DashboardClient(
        host: baseUri.host,
        port: port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: pathPrefix,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
      ),
      documentProfile: documentIntakeProfileForConnection(connection),
      atlasProfile: atlasProfile,
    );
  }

  Future<_DesktopGatewaySession> _connect(String mobileSessionId) async {
    final client = await _connectSocket();
    final mappedSessionId = _gatewaySessionIds[mobileSessionId];
    if (mappedSessionId != null) {
      return _DesktopGatewaySession(client, mappedSessionId);
    }
    final opened = await _resumeOrCreate(client, mobileSessionId);
    _gatewaySessionIds[mobileSessionId] = opened.sessionId;
    final effective = opened.effectiveFullControl;
    if (effective != null) {
      _recordEffectiveFullControl(mobileSessionId, effective);
    }
    return _DesktopGatewaySession(client, opened.sessionId);
  }

  Future<WsClient> _connectSocket() async {
    final existing = _ws;
    if (existing != null && existing.isConnected) return existing;

    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    _effectiveFullControl.clear();
    _interactionModeStates.clear();
    _interactionModeCapability = null;
    final ticket = await _dashboard.mintWebSocketTicket();
    final client = WsClient(_baseUrl, ticket: ticket);
    _installAsyncEventBridge(client);
    client.onConnectionChanged = (connected) {
      if (connected) {
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _effectiveFullControl.clear();
        _interactionModeStates.clear();
        _interactionModeCapability = null;
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
    };
    try {
      await client.connect();
      _ws = client;
      return client;
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  Future<GatewaySessionOpenResult> _resumeOrCreate(
    WsClient client,
    String mobileSessionId,
  ) async {
    try {
      return await client.resumeSessionWithInfo(
        mobileSessionId,
        profile: _atlasProfile,
      );
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // New mobile chats do not exist in Hermes yet. Create them with the
      // mobile-generated ID so REST history and the Desktop runtime share one
      // stable identity. Existing sessions always take the resume path.
      return client.createOrResumeSessionWithInfo(
        mobileSessionId,
        profile: _atlasProfile,
      );
    }
  }

  Future<bool?> ensureSession(String sessionId) async {
    await _connect(sessionId);
    return _effectiveFullControl[sessionId];
  }

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??= GatewayTurnCoordinatorRegistry(
      connectionId: _connectionId,
      endpointDigest: sha256.convert(utf8.encode(_baseUrl)).toString(),
      journal: journal ?? GatewayTurnJournal(),
      freshSocketFactory: () async {
        final ticket = await _dashboard.mintWebSocketTicket();
        return WsClient(_baseUrl, ticket: ticket);
      },
    );
  }

  void setConnectionListener(DesktopConnectionCallback? listener) {
    _connectionListener = listener;
  }

  void setSessionPermissionListener(
    DesktopSessionPermissionCallback? listener,
  ) {
    _sessionPermissionListener = listener;
  }

  void setInteractionModeListener(DesktopInteractionModeCallback? listener) {
    _interactionModeListener = listener;
  }

  Future<GatewayInteractionModeState> getInteractionModeState({
    required String sessionId,
  }) async {
    final gateway = await _connect(sessionId);
    final capability = await _interactionCapabilityFor(gateway.client);
    if (!capability.supported) {
      const state = GatewayInteractionModeState.standardOnly();
      _recordInteractionMode(sessionId, state);
      return state;
    }
    final receipt = await gateway.client.getInteractionMode(
      sessionId: gateway.sessionId,
    );
    final state = GatewayInteractionModeState(
      supported: true,
      mode: receipt.effectiveMode,
      revision: receipt.revision,
    );
    _recordInteractionMode(sessionId, state);
    return state;
  }

  Future<GatewayInteractionModeState> setInteractionMode({
    required String sessionId,
    required GatewayInteractionMode mode,
    required int expectedRevision,
  }) async {
    final gateway = await _connect(sessionId);
    final capability = await _interactionCapabilityFor(gateway.client);
    if (!capability.supported) {
      const state = GatewayInteractionModeState.standardOnly();
      _recordInteractionMode(sessionId, state);
      return state;
    }
    final current = _interactionModeStates[sessionId];
    if (current != null &&
        current.supported &&
        current.mode == mode &&
        current.revision == expectedRevision) {
      return current;
    }

    final readback = Completer<GatewayInteractionModeState>();
    void listener(StreamEvent event) {
      if (event.type != 'session.info') return;
      final state = GatewayInteractionModeState.fromSessionInfo(event.data);
      if (state != null && !readback.isCompleted) readback.complete(state);
    }

    gateway.client.addSessionEventListener(gateway.sessionId, listener);
    try {
      final receipt = await gateway.client.setInteractionMode(
        sessionId: gateway.sessionId,
        mode: mode,
        expectedRevision: expectedRevision,
      );
      if (receipt.revision != expectedRevision + 1) {
        throw JsonRpcError(
          'interaction_mode.set',
          'Gateway did not advance the interaction mode revision',
        );
      }
      final reported = await readback.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw JsonRpcError(
          'session.info',
          'Gateway did not confirm the effective interaction mode',
        ),
      );
      if (reported.mode != receipt.effectiveMode ||
          reported.revision != receipt.revision) {
        throw JsonRpcError(
          'session.info',
          'Gateway interaction mode readback did not match its receipt',
        );
      }
      _recordInteractionMode(sessionId, reported);
      return reported;
    } finally {
      gateway.client.removeSessionEventListener(gateway.sessionId, listener);
    }
  }

  Future<GatewayInteractionModeCapability> _interactionCapabilityFor(
    WsClient client,
  ) async {
    final cached = _interactionModeCapability;
    if (cached != null) return cached;
    final capability = GatewayInteractionModeCapability.fromGatewayReady(
      await client.waitForGatewayReady(),
    );
    _interactionModeCapability = capability;
    return capability;
  }

  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
    required String clientAttachmentId,
    required String mediaType,
    String? projectId,
  }) async {
    final gateway = await _connect(sessionId);
    final atlasProfile = _atlasProfile;
    if (atlasProfile != null) {
      final ready = await gateway.client.waitForGatewayReady();
      final capability = AtlasTemporaryAttachmentCapability.fromGatewayReady(
        ready,
      );
      if (!capability.supported) {
        throw StateError(
          'This Gateway does not advertise ATLAS Temporary Content.',
        );
      }
    }
    return gateway.client.attachFile(
      sessionId: gateway.sessionId,
      name: name,
      dataUrl: dataUrl,
      sourceChannel: 'hermes_mobile',
      sourceProfile: _documentProfile,
      atlasConversationId: atlasProfile == null ? null : sessionId,
      atlasProfileId: atlasProfile,
      atlasIdempotencyKey: atlasProfile == null
          ? null
          : 'attach-$clientAttachmentId',
      atlasMimeType: atlasProfile == null ? null : mediaType,
      atlasProjectId: atlasProfile == null ? null : projectId,
    );
  }

  Future<Map<String, dynamic>> promoteTemporaryAttachment({
    required String sessionId,
    required String temporaryContentId,
    required String clientAttachmentId,
  }) async {
    final profile = _atlasProfile;
    if (profile == null) {
      throw StateError('ATLAS Temporary Content is not enabled.');
    }
    final gateway = await _connect(sessionId);
    final capability = AtlasTemporaryAttachmentCapability.fromGatewayReady(
      await gateway.client.waitForGatewayReady(),
    );
    if (!capability.supported) {
      throw StateError(
        'This Gateway does not advertise ATLAS Temporary Content.',
      );
    }
    return gateway.client.promoteFile(
      sessionId: gateway.sessionId,
      temporaryContentId: temporaryContentId,
      conversationId: sessionId,
      profileId: profile,
      idempotencyKey: 'promote-$clientAttachmentId',
    );
  }

  Future<void> submitPrompt({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.submitPrompt(
      text,
      sessionId: gateway.sessionId,
      onEvent: onEvent,
    );
  }

  /// Receives only durable, session-scoped events that may arrive after a
  /// prompt's terminal event. Active-turn events continue through [submitPrompt]
  /// so they are never delivered twice.
  void setAsyncEventListener(DesktopAsyncEventCallback? listener) {
    _asyncEventListener = listener;
  }

  void _installAsyncEventBridge(WsClient client) {
    client.onStreamEvent = (event) {
      if (!_asyncEventTypes.contains(event.type)) return;
      final gatewaySessionId = event.data['session_id']?.toString();
      String? mobileSessionId;
      if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
        for (final entry in _gatewaySessionIds.entries) {
          if (entry.value == gatewaySessionId) {
            mobileSessionId = entry.key;
            break;
          }
        }
      } else if (_gatewaySessionIds.length == 1) {
        mobileSessionId = _gatewaySessionIds.keys.single;
      }
      if (mobileSessionId == null) return;
      if (event.type == 'session.info') {
        final yolo = event.data['yolo'];
        if (yolo is bool) {
          _recordEffectiveFullControl(mobileSessionId, yolo);
        }
        final interaction = GatewayInteractionModeState.fromSessionInfo(
          event.data,
        );
        if (interaction != null) {
          _recordInteractionMode(mobileSessionId, interaction);
        }
        return;
      }
      _asyncEventListener?.call(mobileSessionId, event);
    };
  }

  void _recordEffectiveFullControl(String mobileSessionId, bool enabled) {
    _effectiveFullControl[mobileSessionId] = enabled;
    _sessionPermissionListener?.call(mobileSessionId, enabled);
  }

  void _recordInteractionMode(
    String mobileSessionId,
    GatewayInteractionModeState state,
  ) {
    _interactionModeStates[mobileSessionId] = state;
    _interactionModeListener?.call(mobileSessionId, state);
  }

  /// Interrupts the active turn in the Desktop gateway runtime.
  Future<bool> interruptPrompt({required String sessionId}) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      return false;
    }
    await client.interruptSession(gatewaySessionId);
    return true;
  }

  /// Resolves an approval against the gateway session mapped to this mobile
  /// chat. Approval requests are session-keyed and do not carry a request ID.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
  }) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await client.respondToApproval(sessionId: gatewaySessionId, choice: choice);
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) async {
    final client = _connectedClient();
    await client.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) async {
    final client = _connectedClient();
    await client.respondToSecret(requestId: requestId, value: value);
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
  }) async {
    final client = _connectedClient();
    await client.respondToClarify(requestId: requestId, answer: answer);
  }

  WsClient _connectedClient() {
    final client = _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    return client;
  }

  /// The profile-scoped catalog and default shown by Hermes Desktop.  Keeping
  /// these reads on the Dashboard endpoint means Android never guesses model
  /// names or providers from the OpenAI-compatible API.
  Future<Map<String, dynamic>> getModelInfo() => _dashboard.getModelInfo();

  Future<Map<String, dynamic>> getModelOptions() =>
      _dashboard.getModelOptions();

  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionModel(
      sessionId: gateway.sessionId,
      provider: provider,
      model: model,
    );
  }

  Future<String> getSessionReasoning(String sessionId) async {
    final gateway = await _connect(sessionId);
    return gateway.client.getSessionReasoning(gateway.sessionId);
  }

  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionReasoning(
      sessionId: gateway.sessionId,
      effort: effort,
    );
  }

  /// Changes approval bypass for one mapped chat and waits for the gateway's
  /// authoritative effective state. A global server policy can keep effective
  /// Full control enabled even after the per-session override is disabled.
  Future<bool> setSessionFullControl({
    required String sessionId,
    required bool enabled,
  }) async {
    final gateway = await _connect(sessionId);
    final effective = Completer<bool>();
    void listener(StreamEvent event) {
      if (event.type != 'session.info') return;
      final yolo = event.data['yolo'];
      if (yolo is bool && !effective.isCompleted) effective.complete(yolo);
    }

    gateway.client.addSessionEventListener(gateway.sessionId, listener);
    try {
      await gateway.client.setSessionFullControl(
        sessionId: gateway.sessionId,
        enabled: enabled,
      );
      final reported = await effective.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw JsonRpcError(
          'session.info',
          'Gateway did not confirm the effective permission level',
        ),
      );
      _recordEffectiveFullControl(sessionId, reported);
      return reported;
    } finally {
      gateway.client.removeSessionEventListener(gateway.sessionId, listener);
    }
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionTitle(gateway.sessionId, title);
  }

  Future<Map<String, dynamic>> branchSession({
    required String sessionId,
    required String name,
  }) async {
    final gateway = await _connect(sessionId);
    return gateway.client.branchSession(gateway.sessionId, name: name);
  }

  /// Reads the upstream Hermes per-profile Projects store through its native
  /// JSON-RPC surface. No ATLAS service or identity is involved.
  Future<Map<String, dynamic>> listProjects() async {
    final client = await _connectSocket();
    return client.listProjects();
  }

  /// Creates one upstream Hermes Project in the current profile. ATLAS
  /// identity and ProjectProjection are deliberately not created by mobile.
  Future<Map<String, dynamic>> createProject({
    required String name,
    String? description,
    String? primaryPath,
    required bool use,
  }) async {
    final client = await _connectSocket();
    return client.createProject(
      name: name,
      description: description,
      primaryPath: primaryPath,
      use: use,
    );
  }

  /// Selects an existing upstream Hermes runtime Project. The identifier is
  /// Hermes-owned projection metadata, never canonical ATLAS Project identity.
  Future<Map<String, dynamic>> setActiveProject(String hermesProjectId) async {
    final client = await _connectSocket();
    return client.setActiveProject(hermesProjectId);
  }

  void close() {
    _asyncEventListener = null;
    _connectionListener = null;
    _sessionPermissionListener = null;
    _interactionModeListener = null;
    _ws?.close();
    _ws = null;
    _gatewaySessionIds.clear();
    _effectiveFullControl.clear();
    _interactionModeStates.clear();
    _interactionModeCapability = null;
    final turnCoordinatorRegistry = _turnCoordinatorRegistry;
    _turnCoordinatorRegistry = null;
    if (turnCoordinatorRegistry != null) {
      final closing = turnCoordinatorRegistry.closeAll();
      unawaited(closing.then<void>((_) {}, onError: (_, _) {}));
    }
    _dashboard.close();
  }
}

String documentIntakeProfileForConnection(SavedConnection connection) {
  final candidates = <String>[
    connection.gatewayPrefix ?? '',
    Uri.tryParse(connection.desktopGatewayUrl ?? '')?.path ?? '',
  ];
  final segments = candidates
      .expand((value) => value.toLowerCase().split('/'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (segments.contains('personal')) return 'personal';
  if (segments.contains('pro') || segments.contains('professional')) {
    return 'pro';
  }
  return 'organizator';
}

class _DesktopGatewaySession {
  final WsClient client;
  final String sessionId;

  const _DesktopGatewaySession(this.client, this.sessionId);
}
