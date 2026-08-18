import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/atlas_project_context.dart';
import '../models/mobile_session_continuity.dart';
import 'atlas_project_port.dart';
import 'connection_manager.dart';
import 'session_continuity_port.dart';

/// Returns the requested server Profile carried by an exact gateway prefix.
/// This is request metadata; owner authentication remains server authority.
String? atlasOwnerProfileRequest(SavedConnection connection) {
  final prefix = connection.gatewayPrefix?.trim();
  if (!isAtlasOwnerGatewayPrefix(prefix)) return null;
  if (prefix == null || prefix.isEmpty) {
    return connection.atlasOwnerEnabled ? 'organizator' : null;
  }
  final match = RegExp(r'^/([a-z][a-z0-9_-]{1,63})$').firstMatch(prefix);
  final profile = match?.group(1);
  return profile != null && isCanonicalProfileId(profile) ? profile : null;
}

/// Same-origin optional ATLAS owner adapter.
///
/// Generic Hermes never constructs this adapter. Once explicitly enabled,
/// missing routes, authentication failures and receipt failures all close.
class AtlasOwnerClient
    implements AtlasProjectEnrichmentPort, HermesSessionContinuityPort {
  static const _maxJsonBytes = 1024 * 1024;
  static const _timeout = Duration(seconds: 8);

  final SavedConnection _connection;
  final String canonicalProfileId;
  final String _ownerBaseUrl;
  final http.Client _http;
  final ApiClient _gateway;
  final Duration _requestTimeout;

  AtlasOwnerClient._(
    this._connection,
    this.canonicalProfileId,
    this._ownerBaseUrl,
    this._http,
    this._gateway,
    this._requestTimeout,
  );

  factory AtlasOwnerClient.fromConnection(
    SavedConnection connection, {
    http.Client? httpClient,
    @visibleForTesting Duration requestTimeout = _timeout,
  }) {
    final profile = atlasOwnerProfileRequest(connection);
    if (!connection.atlasOwnerEnabled ||
        profile == null ||
        connection.apiKey.isEmpty) {
      throw const FormatException('ATLAS owner route request is invalid');
    }
    final client = httpClient ?? http.Client();
    final gatewayBase = SavedConnection.joinBaseUrl(
      connection.baseUrl,
      connection.gatewayPrefix ?? '',
    );
    return AtlasOwnerClient._(
      connection,
      profile,
      '$gatewayBase/owner/v1',
      client,
      ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        pathPrefix: connection.gatewayPrefix ?? '',
        httpClient: client,
      ),
      requestTimeout,
    );
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${_connection.apiKey}',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  @override
  Future<List<Map<String, dynamic>>> listProjectContexts({
    required String canonicalProfileId,
  }) async {
    if (canonicalProfileId != this.canonicalProfileId) {
      throw const FormatException('ATLAS owner Profile request mismatched');
    }
    final value = await _json('GET', '/projects');
    if (value.keys.length != 2 ||
        value['authority'] != 'document-service' ||
        value['items'] is! List) {
      throw const FormatException('ATLAS owner Project catalog drifted');
    }
    final items = value['items'] as List;
    if (items.length > 500) {
      throw const FormatException('ATLAS owner Project catalog is too large');
    }
    return items
        .map((item) {
          if (item is! Map) {
            throw const FormatException('ATLAS owner Project is not an object');
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> requestConversationBinding({
    required String canonicalProfileId,
    required String conversationId,
    required String projectId,
    required String idempotencyKey,
  }) {
    if (canonicalProfileId != this.canonicalProfileId) {
      throw const FormatException('ATLAS owner Profile request mismatched');
    }
    return _json(
      'PUT',
      '/conversations/${Uri.encodeComponent(conversationId)}/project',
      body: {'project_id': projectId},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
  }

  @override
  Future<Map<String, dynamic>> verifyExistingSession({
    required String canonicalProfileId,
    required String sessionId,
    required String requestId,
  }) {
    if (canonicalProfileId != this.canonicalProfileId) {
      throw const FormatException('ATLAS owner Profile request mismatched');
    }
    return _json(
      'POST',
      '/conversations/${Uri.encodeComponent(sessionId)}/verify',
      body: {'request_id': requestId},
    );
  }

  @override
  Future<ProfileScopedSession> loadVerifiedSession({
    required HermesSessionVerification verification,
  }) async {
    if (verification.profileId != canonicalProfileId) {
      throw const FormatException('Verified session Profile mismatched');
    }
    final sessions = await _gateway.getSessions();
    final matching = sessions
        .where((session) => session.id == verification.sessionId)
        .toList(growable: false);
    if (matching.length != 1) {
      throw const FormatException('Verified Hermes session is unavailable');
    }
    return ProfileScopedSession(
      verification: verification,
      connection: _connection,
      session: matching.single,
    );
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? rawBody,
    String? contentType,
    Map<String, String> extraHeaders = const {},
  }) async {
    if (body != null && rawBody != null) {
      throw const FormatException('ATLAS owner request body is ambiguous');
    }
    final request = http.Request(method, Uri.parse('$_ownerBaseUrl$path'));
    request.headers.addAll({..._headers, ...extraHeaders});
    if (body != null) {
      request.body = jsonEncode(body);
    } else if (rawBody != null) {
      request.bodyBytes = rawBody;
      request.headers['Content-Type'] = contentType!;
    }
    return (() async {
      final response = await _http.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw const FormatException('ATLAS owner request was rejected');
      }
      final declared = response.contentLength;
      if (declared != null && declared > _maxJsonBytes) {
        await response.stream.drain<void>();
        throw const FormatException('ATLAS owner response is too large');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > _maxJsonBytes) {
          throw const FormatException('ATLAS owner response is too large');
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('ATLAS owner response is not an object');
      }
      return Map<String, dynamic>.from(decoded);
    })().timeout(
      _requestTimeout,
      onTimeout: () =>
          throw const FormatException('ATLAS owner request timed out'),
    );
  }

  void close() => _gateway.close();
}
