import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/gateway_notification_delivery.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

Map<String, dynamic> _ready(Object? capability) => {
  'jsonrpc': '2.0',
  'method': 'event',
  'params': {
    'type': 'gateway.ready',
    'payload': {
      'capabilities': {'notification_delivery': ?capability},
    },
  },
};

Map<String, dynamic> _capability() => {
  'contract': 'hermes.notification.delivery.v1',
  'version': 1,
  'channel': 'android-local',
  'methods': ['notification.pull', 'notification.delivery_result'],
};

SavedConnection _connection(int port) => SavedConnection(
  id: 'notification-test',
  label: 'Notification test',
  host: '127.0.0.1',
  port: port,
  apiKey: '',
  desktopGatewayUrl: 'http://127.0.0.1:$port',
  dashboardUsername: 'test',
  dashboardPassword: 'test',
);

String _resultRef(String character) =>
    'urn:hermes:android-delivery:${List.filled(64, character).join()}';

void main() {
  group('GatewayNotificationDeliveryCapability', () {
    test('accepts only the exact Hermes-owned contract', () {
      expect(
        GatewayNotificationDeliveryCapability.fromGatewayReady(
          _ready(_capability()),
        ).supported,
        isTrue,
      );
    });

    test('rejects absent, expanded, malformed, and ATLAS-only contracts', () {
      for (final malformed in [
        null,
        <String, dynamic>{},
        {..._capability(), 'version': '1'},
        {..._capability(), 'channel': 'ios-local'},
        {
          ..._capability(),
          'methods': ['notification.delivery_result', 'notification.pull'],
        },
        {..._capability(), 'authority': 'another-system'},
      ]) {
        expect(
          GatewayNotificationDeliveryCapability.fromGatewayReady(
            _ready(malformed),
          ).supported,
          isFalse,
        );
      }
      expect(
        GatewayNotificationDeliveryCapability.fromGatewayReady({
          'params': {
            'payload': {
              'capabilities': {
                'atlas_notification_delivery': {
                  'contract': 'atlas.notification.delivery.v1',
                },
              },
            },
          },
        }).supported,
        isFalse,
      );
    });
  });

  group('GatewayNotificationDeliveryProjection', () {
    test('parses a bounded generic presentation', () {
      final projection = GatewayNotificationDeliveryProjection.fromJson({
        'contract': 'hermes.notification.presentation.v1',
        'notification_id': 'notice-42',
        'version': 2,
        'title': 'Hermes task complete',
      });
      expect(projection, isNotNull);
      expect(projection!.notificationId, 'notice-42');
      expect(projection.version, 2);
    });

    test('rejects unsafe, expanded, and authority-specific presentations', () {
      final base = <String, dynamic>{
        'contract': 'hermes.notification.presentation.v1',
        'notification_id': 'notice-42',
        'version': 2,
        'title': 'Hermes task complete',
      };
      for (final malformed in [
        {...base, 'notification_id': ' notice-42'},
        {...base, 'title': 'bad\nline'},
        {...base, 'version': true},
        {...base, 'extra': true},
        {...base, 'contract': 'atlas.notification.presentation.v1'},
      ]) {
        expect(
          GatewayNotificationDeliveryProjection.fromJson(malformed),
          isNull,
        );
      }
    });
  });

  test('generic Gateway sends zero notification RPCs', () async {
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
      } else if (request.uri.path == '/auth/password-login') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.add('set-cookie', 'hermes_session_at=test; Path=/')
          ..write('{}');
        await request.response.close();
      } else if (request.uri.path == '/api/auth/ws-ticket') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'ticket': 'test-ticket'}));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final client = DesktopGatewayClient.fromConnection(
      _connection(server.port),
    );

    try {
      expect(
        await client.supportsNotificationDelivery(sessionId: 'mobile-1'),
        isFalse,
      );
      expect(
        await client.pullPendingNotification(sessionId: 'mobile-1'),
        isFalse,
      );
      expect(methods, ['session.resume']);
    } finally {
      client.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test(
    'capable Gateway gets one pull and one factual result callback',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      final eventSeen = Completer<void>();
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
                    'session_id': 'live-1',
                    'info': <String, dynamic>{},
                  },
                }),
              );
            } else if (method == 'notification.pull') {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'event',
                  'params': {
                    'type': 'notification.show',
                    'session_id': 'live-1',
                    'payload': {
                      'key': 'notice-1',
                      'level': 'info',
                      'text': 'A Hermes task completed.',
                      'delivery': {
                        'contract': 'hermes.notification.presentation.v1',
                        'notification_id': 'notice-1',
                        'version': 2,
                        'title': 'Hermes task complete',
                      },
                    },
                  },
                }),
              );
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {'notification_id': 'notice-1', 'version': 2},
                }),
              );
            } else if (method == 'notification.delivery_result') {
              final params = message['params'] as Map<String, dynamic>;
              expect(params['session_id'], 'live-1');
              expect(params['notification_id'], 'notice-1');
              expect(params['expected_version'], 2);
              expect(params['outcome'], 'DELIVERED');
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {
                    'notification_id': 'notice-1',
                    'version': 3,
                    'state': 'DELIVERED',
                  },
                }),
              );
            }
          });
        } else if (request.uri.path == '/auth/password-login') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.add('set-cookie', 'hermes_session_at=test; Path=/')
            ..write('{}');
          await request.response.close();
        } else if (request.uri.path == '/api/auth/ws-ticket') {
          request.response
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode({'ticket': 'test-ticket'}));
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
      final client =
          DesktopGatewayClient.fromConnection(_connection(server.port))
            ..setAsyncEventListener((mobileSessionId, event) {
              expect(mobileSessionId, 'mobile-1');
              expect(event.type, 'notification.show');
              if (!eventSeen.isCompleted) eventSeen.complete();
            });

      try {
        expect(
          await client.supportsNotificationDelivery(sessionId: 'mobile-1'),
          isTrue,
        );
        expect(
          await client.pullPendingNotification(sessionId: 'mobile-1'),
          isTrue,
        );
        expect(
          await client.pullPendingNotification(sessionId: 'mobile-1'),
          isTrue,
        );
        await eventSeen.future;
        final receipt = await client.recordNotificationDeliveryResult(
          sessionId: 'mobile-1',
          notificationId: 'notice-1',
          expectedVersion: 2,
          resultRef: _resultRef('a'),
          outcome: GatewayNotificationDeliveryOutcome.delivered,
        );
        expect(receipt.version, 3);
        expect(methods, [
          'session.resume',
          'notification.pull',
          'notification.delivery_result',
        ]);
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
