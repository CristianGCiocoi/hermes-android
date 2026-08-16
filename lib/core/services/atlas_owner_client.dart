import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final RegExp _mimeType = RegExp(
    r'^[a-z0-9][a-z0-9!#$&^_.+-]{0,126}/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,126}$',
  );

  static bool _exactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length && expected.containsAll(value.keys);

  static DateTime? _timestamp(Object? value) {
    if (value is! String || value != value.trim()) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !value.contains('T')) return null;
    return parsed;
  }

  static bool _uuidValue(Object? value) =>
      value is String && _uuid.hasMatch(value);

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

  /// Registers bytes with Temporary Content Core. This does not create a
  /// durable Document and does not grant Mobile any lifecycle authority.
  Future<Map<String, dynamic>> uploadTemporaryContent({
    required String canonicalProfileId,
    required String conversationId,
    required String filename,
    required String mimeType,
    required List<int> bytes,
    required String idempotencyKey,
    String? projectId,
  }) async {
    if (canonicalProfileId != this.canonicalProfileId ||
        !isCanonicalConversationId(conversationId) ||
        filename != filename.trim() ||
        filename.isEmpty ||
        filename.length > 200 ||
        filename.contains('/') ||
        filename.contains('\\') ||
        !isSecretFreeProjectValue(filename) ||
        !_mimeType.hasMatch(mimeType) ||
        !isSafeIdempotencyKey(idempotencyKey) ||
        bytes.isEmpty ||
        bytes.length > 64 * 1024 * 1024 ||
        (projectId != null && !_uuid.hasMatch(projectId))) {
      throw const FormatException('Temporary Content upload is invalid');
    }
    final query = <String, String>{
      'conversation_id': conversationId,
      'filename': filename,
      'mime_type': mimeType,
      'project_id': ?projectId,
    };
    final raw = await _json(
      'POST',
      '/temporary-content?${Uri(queryParameters: query).query}',
      rawBody: bytes,
      contentType: mimeType,
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final uploadKeys = <String>{
      'authority',
      'storage_authority',
      'document_id',
      'temporary_content_id',
      'content_kind',
      'mime_type',
      'size_bytes',
      'content_hash',
      'storage_reference',
      'origin_type',
      'origin_profile_id',
      'origin_session_id',
      'origin_project_id',
      'origin_channel',
      'origin_producer_ref',
      'parent_temporary_content_id',
      'created_at',
      'updated_at',
      'expires_at',
      'retention_class',
      'lifecycle_status',
      'processing_status',
      'promotion_status',
      'storage_status',
      'retention_status',
      'revision',
      'provenance',
      'failure_metadata',
      if (raw.containsKey('idempotent_replay')) 'idempotent_replay',
    };
    final temporaryContentId = raw['temporary_content_id'];
    final createdAt = _timestamp(raw['created_at']);
    final updatedAt = _timestamp(raw['updated_at']);
    final expiresAt = _timestamp(raw['expires_at']);
    final provenance = raw['provenance'];
    final expectedProvenance = <String>{
      'actor_profile_id',
      'conversation_ref',
      'correlation_id',
      'evidence_ref',
    };
    final expectedStorage = temporaryContentId is String
        ? 'workspace://0x_Temp/$canonicalProfileId/$temporaryContentId/$filename'
        : null;
    final expectedContentHash = 'sha256:${sha256.convert(bytes)}';
    final expectedEvidenceRef =
        'storage-receipt://workspace-storage/$temporaryContentId/'
        '$expectedContentHash';
    if (!_exactKeys(raw, uploadKeys) ||
        raw['authority'] != 'temporary-content-core' ||
        raw['storage_authority'] != 'workspace-storage' ||
        raw['document_id'] != null ||
        !_uuidValue(temporaryContentId) ||
        raw['content_kind'] != 'ATTACHMENT' ||
        raw['origin_type'] != 'UPLOAD' ||
        raw['origin_profile_id'] != canonicalProfileId ||
        raw['origin_session_id'] != conversationId ||
        raw['origin_project_id'] != projectId ||
        raw['origin_channel'] != 'hermes-mobile' ||
        raw['origin_producer_ref'] != 'hermes-mobile://owner-provider/upload' ||
        raw['parent_temporary_content_id'] != null ||
        raw['mime_type'] != mimeType ||
        raw['size_bytes'] != bytes.length ||
        raw['content_hash'] != expectedContentHash ||
        raw['storage_reference'] != expectedStorage ||
        createdAt == null ||
        updatedAt == null ||
        expiresAt == null ||
        updatedAt.isBefore(createdAt) ||
        !expiresAt.isAfter(updatedAt) ||
        raw['retention_class'] != 'SHORT' ||
        raw['lifecycle_status'] != 'AVAILABLE' ||
        raw['processing_status'] != 'NOT_REQUESTED' ||
        raw['storage_status'] != 'AVAILABLE' ||
        raw['promotion_status'] != 'NOT_REQUESTED' ||
        raw['retention_status'] != 'ACTIVE' ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 1 ||
        provenance is! Map ||
        !_exactKeys(
          Map<String, dynamic>.from(provenance),
          expectedProvenance,
        ) ||
        provenance['actor_profile_id'] != canonicalProfileId ||
        provenance['conversation_ref'] != 'hermes://session/$conversationId' ||
        provenance['correlation_id'] != idempotencyKey ||
        provenance['evidence_ref'] != expectedEvidenceRef ||
        raw['failure_metadata'] != null ||
        (raw.containsKey('idempotent_replay') &&
            raw['idempotent_replay'] is! bool) ||
        (raw.containsKey('idempotent_replay') &&
            raw['idempotent_replay'] != true)) {
      throw const FormatException('Temporary Content receipt drifted');
    }
    return raw;
  }

  /// Executes only the explicit governed Temporary Content promotion path.
  Future<Map<String, dynamic>> promoteTemporaryContent({
    required String canonicalProfileId,
    required String conversationId,
    required String temporaryContentId,
    required String idempotencyKey,
    required String authorizationRef,
    required String authorizationDigest,
  }) async {
    if (canonicalProfileId != this.canonicalProfileId ||
        !isCanonicalConversationId(conversationId) ||
        !_uuid.hasMatch(temporaryContentId) ||
        !isSafeIdempotencyKey(idempotencyKey) ||
        !RegExp(
          r'^approval://temporary-content/[A-Za-z0-9._:/-]{1,400}$',
        ).hasMatch(authorizationRef) ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(authorizationDigest)) {
      throw const FormatException('Temporary Content promotion is invalid');
    }
    final raw = await _json(
      'POST',
      '/temporary-content/${Uri.encodeComponent(temporaryContentId)}/promote',
      body: {
        'conversation_id': conversationId,
        'authorization_ref': authorizationRef,
        'authorization_digest': authorizationDigest,
      },
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final documentId = raw['document_id'];
    final versionId = raw['document_version_id'];
    final promotionKeys = <String>{
      'authority',
      'durable_authority',
      'promotion_status',
      'receipt_id',
      'attempt_id',
      'temporary_content_id',
      'document_id',
      'document_version_id',
      'idempotency_key',
      'request_digest',
      'promoted_at',
      'document_service_receipt_ref',
      if (raw.containsKey('idempotent_replay')) 'idempotent_replay',
    };
    final receiptId = raw['receipt_id'];
    final attemptId = raw['attempt_id'];
    final expectedRequestDigest =
        'sha256:${sha256.convert(utf8.encode(jsonEncode({'authorization_digest': authorizationDigest, 'authorization_ref': authorizationRef, 'idempotency_key': idempotencyKey, 'temporary_content_id': temporaryContentId})))}';
    final expectedDocumentReceipt = documentId is String && versionId is String
        ? 'document-service://promotion/$documentId/$versionId'
        : null;
    if (!_exactKeys(raw, promotionKeys) ||
        raw['authority'] != 'temporary-content-core' ||
        raw['durable_authority'] != 'document-service' ||
        raw['promotion_status'] != 'PROMOTED' ||
        raw['temporary_content_id'] != temporaryContentId ||
        !_uuidValue(receiptId) ||
        !_uuidValue(attemptId) ||
        !_uuidValue(documentId) ||
        !_uuidValue(versionId) ||
        {
              receiptId,
              attemptId,
              temporaryContentId,
              documentId,
              versionId,
            }.length !=
            5 ||
        raw['idempotency_key'] != idempotencyKey ||
        raw['request_digest'] != expectedRequestDigest ||
        _timestamp(raw['promoted_at']) == null ||
        raw['document_service_receipt_ref'] != expectedDocumentReceipt ||
        (raw.containsKey('idempotent_replay') &&
            raw['idempotent_replay'] is! bool)) {
      throw const FormatException(
        'Temporary Content promotion receipt drifted',
      );
    }
    return raw;
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
