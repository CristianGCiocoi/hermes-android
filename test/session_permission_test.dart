import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

void main() {
  group('GatewaySessionOpenResult', () {
    test('accepts only a boolean effective yolo value', () {
      final enabled = GatewaySessionOpenResult.fromResponse({
        'result': {
          'session_id': 'live-1',
          'info': {'yolo': true},
        },
      }, fallbackSessionId: 'stored-1');
      final malformed = GatewaySessionOpenResult.fromResponse({
        'result': {
          'session_id': 'live-2',
          'info': {'yolo': 'true'},
        },
      }, fallbackSessionId: 'stored-2');

      expect(enabled.sessionId, 'live-1');
      expect(enabled.effectiveFullControl, isTrue);
      expect(malformed.effectiveFullControl, isNull);
    });

    test('falls back to the requested session without inventing state', () {
      final opened = GatewaySessionOpenResult.fromResponse({
        'result': <String, dynamic>{'session_id': ' live\u0001'},
      }, fallbackSessionId: 'stored-1');

      expect(opened.sessionId, 'stored-1');
      expect(opened.effectiveFullControl, isNull);
    });
  });

  test(
    'sets yolo with explicit session scope and receives effective state',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'event',
                  'params': {
                    'type': 'session.info',
                    'session_id': 'runtime-123',
                    'payload': {'yolo': true},
                  },
                }),
              );
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'key': 'yolo', 'value': '1', 'scope': 'session'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');
      final effective = Completer<bool>();

      try {
        await client.connect();
        void listener(StreamEvent event) {
          final yolo = event.data['yolo'];
          if (event.type == 'session.info' && yolo is bool) {
            effective.complete(yolo);
          }
        }

        client.addSessionEventListener('runtime-123', listener);
        expect(
          await client.setSessionFullControl(
            sessionId: 'runtime-123',
            enabled: true,
          ),
          isTrue,
        );
        expect(await effective.future, isTrue);
        client.removeSessionEventListener('runtime-123', listener);

        final request = await requestSeen.future;
        expect(request['method'], 'config.set');
        expect(request['params'], {
          'session_id': 'runtime-123',
          'key': 'yolo',
          'value': '1',
          'scope': 'session',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('rejects a global or malformed permission receipt', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final socketSubscription = server.transform(WebSocketTransformer()).listen((
      socket,
    ) {
      socket.listen((raw) {
        final request = jsonDecode(raw as String) as Map<String, dynamic>;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': {'key': 'yolo', 'value': '0', 'scope': 'global'},
          }),
        );
      });
    });
    final client = WsClient('http://127.0.0.1:${server.port}');

    try {
      await client.connect();
      await expectLater(
        client.setSessionFullControl(sessionId: 'runtime-123', enabled: false),
        throwsA(
          isA<JsonRpcError>().having(
            (error) => error.message,
            'message',
            contains('invalid session permission receipt'),
          ),
        ),
      );
    } finally {
      client.close();
      await socketSubscription.cancel();
      await server.close(force: true);
    }
  });
}
