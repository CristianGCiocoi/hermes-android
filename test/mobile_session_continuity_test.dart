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

SavedConnection ownerConnection() => SavedConnection(
  id: 'trusted-owner-profile-route',
  label: 'Owner verified Pro route',
  host: 'owner.example.test',
  port: 443,
  apiKey: 'test-owner-route',
  useHttps: true,
);

class FakeContinuityPort implements HermesSessionContinuityPort {
  Map<String, dynamic> result;
  Object? failure;
  Object? loadFailure;
  HermesSessionVerification? scopedVerification;
  String scopedSessionId;
  SavedConnection? scopedConnection;
  int calls = 0;
  int loadCalls = 0;
  String? profileId;
  String? id;
  String? request;

  FakeContinuityPort(
    this.result, {
    this.failure,
    this.loadFailure,
    this.scopedVerification,
    this.scopedSessionId = sessionId,
    this.scopedConnection,
  });

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

  @override
  Future<ProfileScopedSession> loadVerifiedSession({
    required HermesSessionVerification verification,
  }) async {
    loadCalls++;
    if (loadFailure != null) throw loadFailure!;
    return ProfileScopedSession(
      verification: scopedVerification ?? verification,
      connection: scopedConnection ?? ownerConnection(),
      session: visibleSession(scopedSessionId),
    );
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
    final valid = MobileSessionOpenRequest.fromLink(
      'hermes://session/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
    );
    expect(valid.sessionId, sessionId);

    for (final raw in [
      'hermes://session/open/$sessionId?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://sessions/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://session/%6fpen?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://session/open?profile_id=personal&session_id=$sessionId&request_id=$requestId&token=x',
      'hermes://user@session/open?profile_id=pro&session_id=$sessionId&request_id=$requestId',
      'hermes://session/open?profile_id=pro&profile_id=personal&session_id=$sessionId&request_id=$requestId',
    ]) {
      expect(
        () => MobileSessionOpenRequest.fromLink(raw),
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
    );
    expect(result.session.id, sessionId);
    expect(result.connection.id, 'trusted-owner-profile-route');
    expect(port.calls, 1);
    expect(port.profileId, 'pro');
    expect(port.id, sessionId);
    expect(port.request, requestId);
    expect(port.loadCalls, 1);
  });

  test('cross-profile request fails before the owner is queried', () async {
    final port = FakeContinuityPort(verification());
    await expectLater(
      controller(port).authorizeOpen(
        request: MobileSessionOpenRequest.fromJson(openRequest()),
        selectedProfileId: 'personal',
      ),
      throwsA(isA<SessionContinuityDenied>()),
    );
    expect(port.calls, 0);
    expect(port.loadCalls, 0);
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
          ),
          throwsA(isA<SessionContinuityDenied>()),
        );
      }
    },
  );

  test('owner error and mismatched scoped session have one denial', () async {
    for (final port in [
      FakeContinuityPort(
        verification(),
        scopedVerification: HermesSessionVerification.fromJson(
          verification(profileId: 'personal'),
        ),
      ),
      FakeContinuityPort(verification(), scopedSessionId: 'another-session'),
      FakeContinuityPort(verification(), loadFailure: StateError('not found')),
    ]) {
      await expectLater(
        controller(port).authorizeOpen(
          request: MobileSessionOpenRequest.fromJson(openRequest()),
          selectedProfileId: 'pro',
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
      ),
      throwsA(isA<SessionContinuityDenied>()),
    );
  });

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

  test('mandatory application validator closes schema-only invariants', () {
    for (final invalid in [
      {...openRequest(), 'session_id': 'token:hidden'},
      verification(verifiedAt: '2026-04-31T00:00:00Z'),
      verification(
        verifiedAt: '2026-08-14T12:01:00Z',
        expiresAt: '2026-08-14T12:00:00Z',
      ),
      verification(
        verifiedAt: '2026-08-14T12:00:00Z',
        expiresAt: '2026-08-14T12:06:00Z',
      ),
    ]) {
      expect(validateMobileSessionContinuityPayload(invalid), isFalse);
    }
    expect(validateMobileSessionContinuityPayload(openRequest()), isTrue);
    expect(validateMobileSessionContinuityPayload(verification()), isTrue);
  });

  testWidgets('optional UI opens only the owner-verified remote session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final port = FakeContinuityPort(verification());
    ProfileScopedSession? authorized;
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
          onContinuitySessionAuthorized: (scoped) async {
            authorized = scoped;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(authorized?.session.id, sessionId);
    expect(authorized?.connection.id, 'trusted-owner-profile-route');
    expect(authorized?.connection.id, isNot('local-label-not-authority'));
    expect(port.calls, 1);
    expect(find.text('Shared session could not be opened.'), findsNothing);
  });

  testWidgets(
    'real ATLAS route exposes native Projects without an injected profile',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final mock = MockClient((request) async {
        if (request.url.path == '/personal/health') {
          return http.Response('{}', 200);
        }
        if (request.url.path == '/personal/api/sessions') {
          return http.Response(jsonEncode({'data': <Object>[]}), 200);
        }
        return http.Response('{}', 404);
      });
      final connection = SavedConnection(
        id: 'atlas-personal-route',
        label: 'ATLAS Personal',
        host: 'example.test',
        port: 443,
        apiKey: 'test-only',
        useHttps: true,
        gatewayPrefix: '/personal',
        atlasOwnerEnabled: true,
        desktopGatewayUrl: 'https://desktop.example.test',
      );
      final api = ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        pathPrefix: connection.gatewayPrefix ?? '',
        httpClient: mock,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SessionListScreen(
            connection: connection,
            turnApplicationController: GatewayTurnApplicationController(),
            apiClient: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsNothing);

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffold.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('ATLAS Projects'), findsNothing);
    },
  );
}
