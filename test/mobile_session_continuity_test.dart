import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/mobile_session_continuity.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_continuity_port.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const requestId = '11111111-1111-4111-8111-111111111111';
const sessionId = 'shared-session-1';

Map<String, dynamic> openRequest({
  String profileId = 'pro',
  String id = sessionId,
}) => {
  'contract': mobileSessionContinuityContract,
  'profile_identity_authority': profileIdentityAuthority,
  'session_authority': hermesSessionAuthority,
  'profile_id': profileId,
  'session_id': id,
  'request_id': requestId,
};

Map<String, dynamic> verification({
  String profileId = 'pro',
  String id = sessionId,
  String verifiedAt = '2026-08-14T12:00:00Z',
  String expiresAt = '2026-08-14T12:01:00Z',
}) => {
  'contract': hermesSessionVerificationContract,
  'profile_identity_authority': profileIdentityAuthority,
  'session_authority': hermesSessionAuthority,
  'profile_id': profileId,
  'session_id': id,
  'request_id': requestId,
  'verification_status': 'VERIFIED',
  'verified_at': verifiedAt,
  'expires_at': expiresAt,
};

Session visibleSession([String id = sessionId]) => Session(
  id: id,
  title: 'Shared project chat',
  model: 'hermes-agent',
  source: 'desktop',
  messageCount: 4,
  isActive: true,
  preview: 'Existing remote preview',
  startedAt: 1,
);

class FakeContinuityPort implements HermesSessionContinuityPort {
  Map<String, dynamic> result;
  Object? failure;
  int calls = 0;
  String? profileId;
  String? id;
  String? request;

  FakeContinuityPort(this.result, {this.failure});

  @override
  Future<Map<String, dynamic>> verifyExistingSession({
    required String canonicalProfileId,
    required String sessionId,
    required String requestId,
  }) async {
    calls++;
    profileId = canonicalProfileId;
    id = sessionId;
    request = requestId;
    if (failure != null) throw failure!;
    return result;
  }
}

SessionContinuityController controller(FakeContinuityPort port) =>
    SessionContinuityController(
      port,
      now: () => DateTime.parse('2026-08-14T12:00:30Z'),
    );

void main() {
  test('strict request carries only canonical endpoint references', () {
    final request = MobileSessionOpenRequest.fromJson(openRequest());
    expect(request.profileId, 'pro');
    expect(request.sessionId, sessionId);
    expect(request.toJson(), openRequest());

    for (final mutation in [
      {'session_id': 'bad/session'},
      {'session_id': ' token=hidden'},
      {'profile_id': 'Local Phone'},
      {'request_id': 'not-a-uuid'},
      {'session_authority': 'mobile'},
      {'transcript': 'forbidden'},
    ]) {
      expect(
        () =>
            MobileSessionOpenRequest.fromJson({...openRequest(), ...mutation}),
        throwsFormatException,
        reason: '$mutation',
      );
    }
  });

  test('deep link parser accepts one exact route and rejects aliases', () {
    final valid = MobileSessionOpenRequest.fromUri(
      Uri.parse(
        'hermes://session/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      ),
    );
    expect(valid.sessionId, sessionId);

    for (final raw in [
      'hermes://session/open/$sessionId?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://sessions/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://session/open?profile_id=personal&session_id=$sessionId&request_id=$requestId&token=x',
      'hermes://user@session/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://session/open?profile_id=pro&profile_id=personal&session_id=$sessionId&request_id=$requestId',
    ]) {
      expect(
        () => MobileSessionOpenRequest.fromUri(Uri.parse(raw)),
        throwsFormatException,
        reason: raw,
      );
    }
  });

  test('owner verification precedes the exact existing session open', () async {
    final port = FakeContinuityPort(verification());
    final result = await controller(port).authorizeOpen(
      request: MobileSessionOpenRequest.fromJson(openRequest()),
      selectedProfileId: 'pro',
      visibleSessions: [visibleSession()],
    );
    expect(result.id, sessionId);
    expect(port.calls, 1);
    expect(port.profileId, 'pro');
    expect(port.id, sessionId);
    expect(port.request, requestId);
  });

  test('cross-profile request fails before the owner is queried', () async {
    final port = FakeContinuityPort(verification());
    await expectLater(
      controller(port).authorizeOpen(
        request: MobileSessionOpenRequest.fromJson(openRequest()),
        selectedProfileId: 'personal',
        visibleSessions: [visibleSession()],
      ),
      throwsA(isA<SessionContinuityDenied>()),
    );
    expect(port.calls, 0);
  });

  test('receipt must bind exact Profile, session and request', () async {
    for (final receipt in [
      verification(profileId: 'personal'),
      verification(id: 'another-session'),
      {...verification(), 'request_id': '22222222-2222-4222-8222-222222222222'},
      {...verification(), 'verification_status': 'MISSING'},
      {...verification(), 'transcript': 'forbidden'},
    ]) {
      final port = FakeContinuityPort(receipt);
      await expectLater(
        controller(port).authorizeOpen(
          request: MobileSessionOpenRequest.fromJson(openRequest()),
          selectedProfileId: 'pro',
          visibleSessions: [visibleSession()],
        ),
        throwsA(isA<SessionContinuityDenied>()),
        reason: '$receipt',
      );
    }
  });

  test(
    'expired, future and overlong verification windows fail closed',
    () async {
      for (final receipt in [
        verification(
          verifiedAt: '2026-08-14T11:59:00Z',
          expiresAt: '2026-08-14T12:00:30Z',
        ),
        verification(
          verifiedAt: '2026-08-14T12:01:00Z',
          expiresAt: '2026-08-14T12:02:00Z',
        ),
        verification(
          verifiedAt: '2026-08-14T12:00:00Z',
          expiresAt: '2026-08-14T12:06:00Z',
        ),
      ]) {
        await expectLater(
          controller(FakeContinuityPort(receipt)).authorizeOpen(
            request: MobileSessionOpenRequest.fromJson(openRequest()),
            selectedProfileId: 'pro',
            visibleSessions: [visibleSession()],
          ),
          throwsA(isA<SessionContinuityDenied>()),
        );
      }
    },
  );

  test(
    'owner error and unknown or duplicate session have one denial',
    () async {
      for (final sessions in <List<Session>>[
        [],
        [visibleSession(), visibleSession()],
      ]) {
        await expectLater(
          controller(FakeContinuityPort(verification())).authorizeOpen(
            request: MobileSessionOpenRequest.fromJson(openRequest()),
            selectedProfileId: 'pro',
            visibleSessions: sessions,
          ),
          throwsA(
            isA<SessionContinuityDenied>().having(
              (error) => error.toString(),
              'generic message',
              'Shared session could not be opened.',
            ),
          ),
        );
      }
      await expectLater(
        controller(
          FakeContinuityPort(verification(), failure: StateError('not found')),
        ).authorizeOpen(
          request: MobileSessionOpenRequest.fromJson(openRequest()),
          selectedProfileId: 'pro',
          visibleSessions: [visibleSession()],
        ),
        throwsA(isA<SessionContinuityDenied>()),
      );
    },
  );

  test('calendar-invalid owner timestamps are rejected', () {
    for (final raw in [
      '0000-01-01T00:00:00Z',
      '2025-02-29T00:00:00Z',
      '2026-04-31T00:00:00Z',
      '2026-08-14T12:00:00+99:99',
      '2026-08-14T12:00:00+14:01',
    ]) {
      expect(
        () => HermesSessionVerification.fromJson(verification(verifiedAt: raw)),
        throwsFormatException,
      );
    }
  });

  testWidgets('optional UI opens only the owner-verified remote session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final port = FakeContinuityPort(verification());
    Session? authorized;
    final mock = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/api/sessions') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': sessionId,
                'title': 'Shared project chat',
                'model': 'hermes-agent',
                'source': 'desktop',
                'message_count': 4,
                'preview': 'Existing remote preview',
                'started_at': 1,
                'ended_at': null,
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final api = ApiClient(
      baseUrl: 'https://example.test',
      apiKey: 'test-only',
      httpClient: mock,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SessionListScreen(
          connection: SavedConnection(
            id: 'local-label-not-authority',
            label: 'Pro',
            host: 'example.test',
            port: 443,
            apiKey: 'test-only',
            useHttps: true,
          ),
          turnApplicationController: GatewayTurnApplicationController(),
          sessionContinuityController: controller(port),
          canonicalSessionProfileId: 'pro',
          initialSessionOpenRequest: MobileSessionOpenRequest.fromJson(
            openRequest(),
          ),
          apiClient: api,
          onContinuitySessionAuthorized: (session) async {
            authorized = session;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(authorized?.id, sessionId);
    expect(port.calls, 1);
    expect(find.text('Shared session could not be opened.'), findsNothing);
  });
}
