import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/mobile_session_continuity.dart';
import 'package:hermes_android/core/services/atlas_owner_client.dart';

SavedConnection connection({String? prefix = '/personal'}) => SavedConnection(
  id: 'connection-1',
  label: 'Fixture',
  host: 'gateway.example.test',
  port: 443,
  apiKey: 'synthetic-test-bearer-value',
  useHttps: true,
  gatewayPrefix: prefix,
  atlasOwnerEnabled: true,
);

Map<String, dynamic> temporaryUploadReceipt({
  String? originProjectId,
  bool idempotentReplay = false,
}) {
  const temporary = '51111111-1111-4111-8111-111111111111';
  final receipt = <String, dynamic>{
    'authority': 'temporary-content-core',
    'storage_authority': 'workspace-storage',
    'document_id': null,
    'temporary_content_id': temporary,
    'content_kind': 'ATTACHMENT',
    'mime_type': 'text/plain',
    'size_bytes': 17,
    'content_hash':
        'sha256:${sha256.convert(utf8.encode('temporary fixture'))}',
    'storage_reference': 'workspace://0x_Temp/personal/$temporary/note.txt',
    'origin_type': 'UPLOAD',
    'origin_profile_id': 'personal',
    'origin_session_id': 'conversation-1',
    'origin_project_id': originProjectId,
    'origin_channel': 'hermes-mobile',
    'origin_producer_ref': 'hermes-mobile://owner-provider/upload',
    'parent_temporary_content_id': null,
    'created_at': '2026-08-16T10:00:00Z',
    'updated_at': '2026-08-16T10:00:00Z',
    'expires_at': '2026-08-23T10:00:00Z',
    'retention_class': 'SHORT',
    'lifecycle_status': 'AVAILABLE',
    'processing_status': 'NOT_REQUESTED',
    'promotion_status': 'NOT_REQUESTED',
    'storage_status': 'AVAILABLE',
    'retention_status': 'ACTIVE',
    'revision': 2,
    'provenance': {
      'actor_profile_id': 'personal',
      'conversation_ref': 'hermes://session/conversation-1',
      'correlation_id': 'mobile-temp:test-1',
      'evidence_ref':
          'storage-receipt://workspace-storage/$temporary/'
          'sha256:${sha256.convert(utf8.encode('temporary fixture'))}',
    },
    'failure_metadata': null,
  };
  if (idempotentReplay) receipt['idempotent_replay'] = true;
  return receipt;
}

Map<String, dynamic> temporaryPromotionReceipt({bool idempotentReplay = true}) {
  final authorizationDigest = 'sha256:${List.filled(64, 'a').join()}';
  final requestDigest = sha256.convert(
    utf8.encode(
      jsonEncode({
        'authorization_digest': authorizationDigest,
        'authorization_ref': 'approval://temporary-content/mobile/test-1',
        'idempotency_key': 'mobile-promote:test-1',
        'temporary_content_id': '51111111-1111-4111-8111-111111111111',
      }),
    ),
  );
  final receipt = <String, dynamic>{
    'authority': 'temporary-content-core',
    'durable_authority': 'document-service',
    'promotion_status': 'PROMOTED',
    'receipt_id': '81111111-1111-4111-8111-111111111111',
    'attempt_id': '91111111-1111-4111-8111-111111111111',
    'temporary_content_id': '51111111-1111-4111-8111-111111111111',
    'document_id': '61111111-1111-4111-8111-111111111111',
    'document_version_id': '71111111-1111-4111-8111-111111111111',
    'idempotency_key': 'mobile-promote:test-1',
    'request_digest': 'sha256:$requestDigest',
    'promoted_at': '2026-08-16T10:01:00Z',
    'document_service_receipt_ref':
        'document-service://promotion/61111111-1111-4111-8111-111111111111/71111111-1111-4111-8111-111111111111',
  };
  if (idempotentReplay) receipt['idempotent_replay'] = true;
  return receipt;
}

void main() {
  test('profile request matches live owner route shapes only', () {
    expect(
      atlasOwnerProfileRequest(
        connection(prefix: null).copyWith(atlasOwnerEnabled: false),
      ),
      isNull,
    );
    expect(atlasOwnerProfileRequest(connection(prefix: '/nested/a/b')), isNull);
    expect(atlasOwnerProfileRequest(connection()), 'personal');
    expect(atlasOwnerProfileRequest(connection(prefix: '/pro')), 'pro');
    expect(
      atlasOwnerProfileRequest(connection(prefix: '/profile/pro')),
      isNull,
    );
    expect(atlasOwnerProfileRequest(connection(prefix: null)), 'organizator');
  });

  test('adapter construction requires explicit ATLAS opt-in', () {
    final generic = connection().copyWith(atlasOwnerEnabled: false);
    expect(
      () => AtlasOwnerClient.fromConnection(generic),
      throwsFormatException,
    );
  });

  test('owner Project list uses exact same-origin route and bearer', () async {
    final client = AtlasOwnerClient.fromConnection(
      connection(),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://gateway.example.test/personal/owner/v1/projects',
        );
        expect(
          request.headers['authorization'],
          'Bearer synthetic-test-bearer-value',
        );
        return http.Response(
          jsonEncode({'items': <Object>[], 'authority': 'document-service'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    expect(
      await client.listProjectContexts(canonicalProfileId: 'personal'),
      isEmpty,
    );
  });

  test(
    'explicit ATLAS mode fails closed when owner capability is absent',
    () async {
      final owner = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(owner.close);
      await expectLater(
        owner.listProjectContexts(canonicalProfileId: 'personal'),
        throwsFormatException,
      );
    },
  );

  test(
    'owner response has one absolute deadline, not a chunk-gap timeout',
    () async {
      final owner = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: _DripClient(),
        requestTimeout: const Duration(milliseconds: 35),
      );
      addTearDown(owner.close);

      await expectLater(
        owner.listProjectContexts(canonicalProfileId: 'personal'),
        throwsFormatException,
      );
    },
  );

  test(
    'binding request is exact and carries deterministic caller key',
    () async {
      final client = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(
            request.url.path,
            '/personal/owner/v1/conversations/conversation-1/project',
          );
          expect(
            request.headers['idempotency-key'],
            'mobile-project-bind:test',
          );
          expect(jsonDecode(request.body), {'project_id': 'project-1'});
          return http.Response(jsonEncode({'receipt': 'fixture'}), 200);
        }),
      );
      addTearDown(client.close);

      expect(
        await client.requestConversationBinding(
          canonicalProfileId: 'personal',
          conversationId: 'conversation-1',
          projectId: 'project-1',
          idempotencyKey: 'mobile-project-bind:test',
        ),
        {'receipt': 'fixture'},
      );
    },
  );

  test(
    'Temporary upload stays non-durable and uses the owner contract',
    () async {
      const temporary = '51111111-1111-4111-8111-111111111111';
      final client = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/personal/owner/v1/temporary-content');
          expect(request.url.queryParameters, {
            'conversation_id': 'conversation-1',
            'filename': 'note.txt',
            'mime_type': 'text/plain',
          });
          expect(request.headers['idempotency-key'], 'mobile-temp:test-1');
          expect(request.bodyBytes, utf8.encode('temporary fixture'));
          return http.Response(jsonEncode(temporaryUploadReceipt()), 200);
        }),
      );
      addTearDown(client.close);

      final receipt = await client.uploadTemporaryContent(
        canonicalProfileId: 'personal',
        conversationId: 'conversation-1',
        filename: 'note.txt',
        mimeType: 'text/plain',
        bytes: utf8.encode('temporary fixture'),
        idempotencyKey: 'mobile-temp:test-1',
      );
      expect(receipt['temporary_content_id'], temporary);
      expect(receipt['document_id'], isNull);
    },
  );

  test('explicit Promote accepts one exact durable owner receipt', () async {
    const temporary = '51111111-1111-4111-8111-111111111111';
    const document = '61111111-1111-4111-8111-111111111111';
    const version = '71111111-1111-4111-8111-111111111111';
    final authorizationDigest = 'sha256:${List.filled(64, 'a').join()}';
    final client = AtlasOwnerClient.fromConnection(
      connection(),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/personal/owner/v1/temporary-content/$temporary/promote',
        );
        expect(request.headers['idempotency-key'], 'mobile-promote:test-1');
        expect(jsonDecode(request.body), {
          'conversation_id': 'conversation-1',
          'authorization_ref': 'approval://temporary-content/mobile/test-1',
          'authorization_digest': authorizationDigest,
        });
        return http.Response(jsonEncode(temporaryPromotionReceipt()), 200);
      }),
    );
    addTearDown(client.close);

    final receipt = await client.promoteTemporaryContent(
      canonicalProfileId: 'personal',
      conversationId: 'conversation-1',
      temporaryContentId: temporary,
      idempotencyKey: 'mobile-promote:test-1',
      authorizationRef: 'approval://temporary-content/mobile/test-1',
      authorizationDigest: authorizationDigest,
    );
    expect(receipt['document_id'], document);
    expect(receipt['document_version_id'], version);
    expect(receipt['idempotent_replay'], isTrue);
  });

  test(
    'Temporary receipts reject missing or mismatched owner fields',
    () async {
      final invalidUpload = temporaryUploadReceipt()
        ..remove('storage_reference');
      final uploadClient = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(invalidUpload), 200),
        ),
      );
      addTearDown(uploadClient.close);
      await expectLater(
        uploadClient.uploadTemporaryContent(
          canonicalProfileId: 'personal',
          conversationId: 'conversation-1',
          filename: 'note.txt',
          mimeType: 'text/plain',
          bytes: utf8.encode('temporary fixture'),
          idempotencyKey: 'mobile-temp:test-1',
        ),
        throwsFormatException,
      );

      final invalidPromotion = temporaryPromotionReceipt()
        ..['idempotency_key'] = 'mobile-promote:other';
      final promotionClient = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(invalidPromotion), 200),
        ),
      );
      addTearDown(promotionClient.close);
      await expectLater(
        promotionClient.promoteTemporaryContent(
          canonicalProfileId: 'personal',
          conversationId: 'conversation-1',
          temporaryContentId: '51111111-1111-4111-8111-111111111111',
          idempotencyKey: 'mobile-promote:test-1',
          authorizationRef: 'approval://temporary-content/mobile/test-1',
          authorizationDigest: 'sha256:${List.filled(64, 'a').join()}',
        ),
        throwsFormatException,
      );
    },
  );

  test('Temporary receipts bind exact bytes, request, and durable URI', () async {
    Future<void> expectUploadRejected(Map<String, dynamic> receipt) async {
      final client = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(receipt), 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.uploadTemporaryContent(
          canonicalProfileId: 'personal',
          conversationId: 'conversation-1',
          filename: 'note.txt',
          mimeType: 'text/plain',
          bytes: utf8.encode('temporary fixture'),
          idempotencyKey: 'mobile-temp:test-1',
        ),
        throwsFormatException,
      );
    }

    Future<void> expectPromotionRejected(Map<String, dynamic> receipt) async {
      final client = AtlasOwnerClient.fromConnection(
        connection(),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(receipt), 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.promoteTemporaryContent(
          canonicalProfileId: 'personal',
          conversationId: 'conversation-1',
          temporaryContentId: '51111111-1111-4111-8111-111111111111',
          idempotencyKey: 'mobile-promote:test-1',
          authorizationRef: 'approval://temporary-content/mobile/test-1',
          authorizationDigest: 'sha256:${List.filled(64, 'a').join()}',
        ),
        throwsFormatException,
      );
    }

    await expectUploadRejected(
      temporaryUploadReceipt()
        ..['content_hash'] = 'sha256:${List.filled(64, 'c').join()}',
    );
    await expectUploadRejected(
      temporaryUploadReceipt()
        ..['provenance']['evidence_ref'] =
            'storage-receipt://workspace-storage/'
            '51111111-1111-4111-8111-111111111111/fixture',
    );
    await expectUploadRejected(
      temporaryUploadReceipt()..['idempotent_replay'] = false,
    );
    await expectPromotionRejected(
      temporaryPromotionReceipt()
        ..['request_digest'] = 'sha256:${List.filled(64, 'd').join()}',
    );
    await expectPromotionRejected(
      temporaryPromotionReceipt()
        ..['document_service_receipt_ref'] =
            'other-service://promotion/61111111-1111-4111-8111-111111111111/71111111-1111-4111-8111-111111111111',
    );
    await expectPromotionRejected(
      temporaryPromotionReceipt()..['idempotent_replay'] = false,
    );
  });

  test('verified session loads from the same profile-scoped gateway', () async {
    final rawVerification = {
      'contract': 'atlas.hermes-session-verification.v1',
      'profile_identity_authority': 'profile-service',
      'session_authority': 'hermes-profile-state',
      'profile_id': 'personal',
      'session_id': 'conversation-1',
      'request_id': '123e4567-e89b-42d3-a456-426614174000',
      'verification_status': 'VERIFIED',
      'verified_at': '2026-08-16T00:00:00Z',
      'expires_at': '2026-08-16T00:02:00Z',
    };
    final client = AtlasOwnerClient.fromConnection(
      connection(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/owner/v1/conversations/conversation-1/verify',
        )) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'request_id': '123e4567-e89b-42d3-a456-426614174000',
          });
          return http.Response(jsonEncode(rawVerification), 200);
        }
        expect(request.url.path, '/personal/api/sessions');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'conversation-1',
                'title': 'Fixture',
                'model': 'hermes-agent',
                'source': 'mobile',
                'message_count': 2,
                'preview': 'safe fixture',
                'started_at': 1,
                'ended_at': null,
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final raw = await client.verifyExistingSession(
      canonicalProfileId: 'personal',
      sessionId: 'conversation-1',
      requestId: '123e4567-e89b-42d3-a456-426614174000',
    );
    final verification = HermesSessionVerification.fromJson(raw);
    final scoped = await client.loadVerifiedSession(verification: verification);

    expect(scoped.verification.profileId, 'personal');
    expect(scoped.session.id, 'conversation-1');
    expect(scoped.connection.gatewayPrefix, '/personal');
  });

  test('profile mismatch rejects before any owner request', () async {
    var calls = 0;
    final client = AtlasOwnerClient.fromConnection(
      connection(),
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.listProjectContexts(canonicalProfileId: 'pro'),
      throwsFormatException,
    );
    expect(calls, 0);
  });
}

class _DripClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.periodic(
      const Duration(milliseconds: 20),
      (_) => utf8.encode(' '),
    ).take(10);
    return http.StreamedResponse(stream, 200);
  }
}
