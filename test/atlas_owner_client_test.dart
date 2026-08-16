import 'dart:convert';

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
