import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/gateway_interaction_mode.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';

Map<String, dynamic> _ready(Object? capability) => {
  'jsonrpc': '2.0',
  'method': 'event',
  'params': {
    'type': 'gateway.ready',
    'payload': {
      'capabilities': {'interaction_modes': ?capability},
    },
  },
};

Map<String, dynamic> _capability() => {
  'version': 1,
  'methods': ['interaction_mode.get', 'interaction_mode.set'],
  'modes': ['standard', 'interview', 'grill'],
  'scope': 'session',
  'default_mode': 'standard',
  'readback': 'session.info',
  'clarify_transport': 'clarify.request/respond',
};

void main() {
  group('GatewayInteractionModeCapability', () {
    test('accepts only the exact versioned Gateway contract', () {
      expect(
        GatewayInteractionModeCapability.fromGatewayReady(
          _ready(_capability()),
        ).supported,
        isTrue,
      );
    });

    test('keeps absent and malformed capabilities Standard-only', () {
      expect(
        GatewayInteractionModeCapability.fromGatewayReady(
          _ready(null),
        ).supported,
        isFalse,
      );
      for (final malformed in [
        <String, dynamic>{},
        {..._capability(), 'version': '1'},
        {
          ..._capability(),
          'methods': ['interaction_mode.get'],
        },
        {
          ..._capability(),
          'modes': ['standard', 'grill', 'interview'],
        },
        {..._capability(), 'extra': true},
      ]) {
        expect(
          GatewayInteractionModeCapability.fromGatewayReady(
            _ready(malformed),
          ).supported,
          isFalse,
        );
      }
    });
  });

  group('GatewayInteractionModeReceipt', () {
    test('binds the live session, requested mode and exact revision', () {
      final receipt = GatewayInteractionModeReceipt.fromResult(
        {
          'session_id': 'live-1',
          'stored_session_id': 'stored-1',
          'requested_mode': 'interview',
          'effective_mode': 'interview',
          'revision': 3,
        },
        expectedSessionId: 'live-1',
        expectedRequestedMode: GatewayInteractionMode.interview,
      );

      expect(receipt, isNotNull);
      expect(receipt!.effectiveMode, GatewayInteractionMode.interview);
      expect(receipt.revision, 3);
    });

    test('rejects cross-session, mismatched and expanded receipts', () {
      final base = <String, dynamic>{
        'session_id': 'live-1',
        'stored_session_id': 'stored-1',
        'requested_mode': 'grill',
        'effective_mode': 'grill',
        'revision': 1,
      };
      for (final malformed in [
        {...base, 'session_id': 'other'},
        {...base, 'effective_mode': 'standard'},
        {...base, 'revision': true},
        {...base, 'extra': 'drift'},
      ]) {
        expect(
          GatewayInteractionModeReceipt.fromResult(
            malformed,
            expectedSessionId: 'live-1',
            expectedRequestedMode: GatewayInteractionMode.grill,
          ),
          isNull,
        );
      }
    });
  });

  test(
    'sends a revision-bound mode change and validates its receipt',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final subscription = server.transform(WebSocketTransformer()).listen((
        socket,
      ) {
        socket.listen((raw) {
          final request = jsonDecode(raw as String) as Map<String, dynamic>;
          requestSeen.complete(request);
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'session.info',
                'session_id': 'live-1',
                'payload': {
                  'interaction_mode': 'grill',
                  'interaction_mode_revision': 5,
                },
              },
            }),
          );
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'session_id': 'live-1',
                'stored_session_id': 'stored-1',
                'requested_mode': 'grill',
                'effective_mode': 'grill',
                'revision': 5,
              },
            }),
          );
        });
      });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        final receipt = await client.setInteractionMode(
          sessionId: 'live-1',
          mode: GatewayInteractionMode.grill,
          expectedRevision: 4,
        );
        expect(receipt.revision, 5);
        expect(await requestSeen.future, {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'interaction_mode.set',
          'params': {
            'session_id': 'live-1',
            'mode': 'grill',
            'expected_revision': 4,
          },
        });
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('generic Gateway stays Standard and receives zero mode RPCs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final methods = <String>[];
    final subscription = server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode(_ready(null)));
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          final method = message['method'] as String;
          methods.add(method);
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              'result': {
                'session_id': 'live-generic',
                'info': <String, dynamic>{},
              },
            }),
          );
        });
        return;
      }
      if (request.uri.path == '/auth/password-login') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.add('set-cookie', 'hermes_session_at=test; Path=/')
          ..write('{}');
      } else if (request.uri.path == '/api/auth/ws-ticket') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'ticket': 'single-use-test-ticket'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final client = DesktopGatewayClient.fromConnection(
      SavedConnection(
        id: 'generic',
        label: 'Generic',
        host: '127.0.0.1',
        port: server.port,
        apiKey: '',
        desktopGatewayUrl: 'http://127.0.0.1:${server.port}',
        dashboardUsername: 'test',
        dashboardPassword: 'test',
      ),
    );

    try {
      final state = await client.getInteractionModeState(
        sessionId: 'mobile-generic',
      );
      expect(state.supported, isFalse);
      expect(state.mode, GatewayInteractionMode.standard);
      expect(state.revision, 0);
      expect(methods, ['session.resume']);
      expect(methods, isNot(contains('interaction_mode.get')));
      expect(methods, isNot(contains('interaction_mode.set')));
    } finally {
      client.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test(
    'upgraded Gateway confirms get and set with session.info readback',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      final subscription = server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.add(jsonEncode(_ready(_capability())));
          socket.listen((raw) {
            final message = jsonDecode(raw as String) as Map<String, dynamic>;
            final method = message['method'] as String;
            methods.add(method);
            if (method == 'session.resume') {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {
                    'session_id': 'live-upgraded',
                    'info': <String, dynamic>{},
                  },
                }),
              );
            } else if (method == 'interaction_mode.get') {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {
                    'session_id': 'live-upgraded',
                    'stored_session_id': 'stored-upgraded',
                    'requested_mode': 'standard',
                    'effective_mode': 'standard',
                    'revision': 0,
                  },
                }),
              );
            } else if (method == 'interaction_mode.set') {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'event',
                  'params': {
                    'type': 'session.info',
                    'session_id': 'live-upgraded',
                    'payload': {
                      'interaction_mode': 'interview',
                      'interaction_mode_revision': 1,
                    },
                  },
                }),
              );
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {
                    'session_id': 'live-upgraded',
                    'stored_session_id': 'stored-upgraded',
                    'requested_mode': 'interview',
                    'effective_mode': 'interview',
                    'revision': 1,
                  },
                }),
              );
            }
          });
          return;
        }
        if (request.uri.path == '/auth/password-login') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.add('set-cookie', 'hermes_session_at=test; Path=/')
            ..write('{}');
        } else if (request.uri.path == '/api/auth/ws-ticket') {
          request.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode({'ticket': 'single-use-test-ticket'}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final client = DesktopGatewayClient.fromConnection(
        SavedConnection(
          id: 'upgraded',
          label: 'Upgraded',
          host: '127.0.0.1',
          port: server.port,
          apiKey: '',
          desktopGatewayUrl: 'http://127.0.0.1:${server.port}',
          dashboardUsername: 'test',
          dashboardPassword: 'test',
        ),
      );

      try {
        final initial = await client.getInteractionModeState(
          sessionId: 'mobile-upgraded',
        );
        expect(initial.supported, isTrue);
        expect(initial.mode, GatewayInteractionMode.standard);
        final changed = await client.setInteractionMode(
          sessionId: 'mobile-upgraded',
          mode: GatewayInteractionMode.interview,
          expectedRevision: initial.revision,
        );
        expect(changed.mode, GatewayInteractionMode.interview);
        expect(changed.revision, 1);
        expect(methods, [
          'session.resume',
          'interaction_mode.get',
          'interaction_mode.set',
        ]);
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
