import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/accessibility/hermes_semantics_ids.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'cold start and complete connection form expose stable value-free semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(HermesSemanticsId.addConnection),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier(HermesSemanticsId.addConnection),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(HermesSemanticsId.addConnectionDialog),
        findsOneWidget,
      );
      for (final identifier in <String>[
        HermesSemanticsId.connectionLabel,
        HermesSemanticsId.connectionHost,
        HermesSemanticsId.connectionPort,
        HermesSemanticsId.connectionApiKey,
        HermesSemanticsId.connectionAdvanced,
        HermesSemanticsId.connectionCancel,
        HermesSemanticsId.connectionConnect,
      ]) {
        expect(find.bySemanticsIdentifier(identifier), findsOneWidget);
      }

      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier(HermesSemanticsId.connectionApiKey),
          matching: find.byType(TextField),
        ),
        'synthetic-secret-api-value',
      );
      final apiKeyNode = tester.getSemantics(
        find.bySemanticsIdentifier(HermesSemanticsId.connectionApiKey),
      );
      expect(apiKeyNode.flagsCollection.isObscured, isTrue);
      expect(apiKeyNode.value, isNot(contains('synthetic-secret-api-value')));
      expect(apiKeyNode.identifier, HermesSemanticsId.connectionApiKey);

      await tester.tap(
        find.bySemanticsIdentifier(HermesSemanticsId.connectionAdvanced),
      );
      await tester.pumpAndSettle();
      for (final identifier in <String>[
        HermesSemanticsId.connectionGatewayPrefix,
        HermesSemanticsId.connectionAtlasOwner,
        HermesSemanticsId.connectionDashboardPrefix,
        HermesSemanticsId.connectionDashboardProxied,
        HermesSemanticsId.connectionDashboardPort,
        HermesSemanticsId.connectionDashboardUsername,
        HermesSemanticsId.connectionDashboardPassword,
        HermesSemanticsId.connectionDesktopGatewayUrl,
      ]) {
        expect(
          find.bySemanticsIdentifier(identifier, skipOffstage: false),
          findsOneWidget,
        );
      }

      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier(
            HermesSemanticsId.connectionDashboardPassword,
            skipOffstage: false,
          ),
          matching: find.byType(TextField),
        ),
        'synthetic-secret-dashboard-value',
      );
      final passwordNode = tester.getSemantics(
        find.bySemanticsIdentifier(
          HermesSemanticsId.connectionDashboardPassword,
          skipOffstage: false,
        ),
      );
      expect(passwordNode.flagsCollection.isObscured, isTrue);
      expect(
        passwordNode.value,
        isNot(contains('synthetic-secret-dashboard-value')),
      );
      expect(
        passwordNode.identifier,
        HermesSemanticsId.connectionDashboardPassword,
      );
      semantics.dispose();
    },
  );

  testWidgets('saved connection uses its opaque id, never displayed values', (
    tester,
  ) async {
    const opaqueId = 'a11y-fixture-id';
    const visibleLabel = 'Sensitive visible label';
    const visibleHost = 'private.example.test';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_connections': <String>[
        jsonEncode(<String, Object>{
          'id': opaqueId,
          'label': visibleLabel,
          'host': visibleHost,
          'port': 8642,
          'use_https': false,
        }),
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();

    final identifier = HermesSemanticsId.savedConnection(opaqueId);
    expect(find.bySemanticsIdentifier(identifier), findsOneWidget);
    expect(identifier, isNot(contains(visibleLabel)));
    expect(identifier, isNot(contains(visibleHost)));
    semantics.dispose();
  });

  testWidgets('session list exposes a stable New Chat action', (tester) async {
    final semantics = tester.ensureSemantics();
    final connection = SavedConnection(
      id: 'session-list-fixture',
      label: 'Fixture',
      host: 'example.test',
      port: 443,
      apiKey: 'synthetic-test-only',
      useHttps: true,
    );
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/health')) {
        return http.Response('{}', 200);
      }
      if (request.url.path.endsWith('/api/sessions')) {
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SessionListScreen(
          connection: connection,
          turnApplicationController: GatewayTurnApplicationController(),
          apiClient: ApiClient(
            baseUrl: connection.baseUrl,
            apiKey: connection.apiKey,
            httpClient: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(HermesSemanticsId.newChat),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
