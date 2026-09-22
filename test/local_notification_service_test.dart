import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/models/gateway_notification_delivery.dart';
import 'package:hermes_android/core/services/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String resultRef(String character) =>
      'urn:hermes:android-delivery:${List.filled(64, character).join()}';

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalNotificationService.channel, null);
  });

  test(
    'requests Android notification permission and preserves denial',
    () async {
      var granted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalNotificationService.channel, (
            call,
          ) async {
            expect(call.method, 'requestPermission');
            return granted;
          });
      final service = LocalNotificationService();
      expect(
        await service.requestPermission(),
        LocalNotificationPermissionState.denied,
      );
      granted = true;
      expect(
        await service.requestPermission(),
        LocalNotificationPermissionState.granted,
      );
    },
  );

  test('returns the native factual delivery result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalNotificationService.channel, (
          call,
        ) async {
          expect(call.method, 'show');
          expect((call.arguments as Map)['notification_id'], 'notice-7');
          expect((call.arguments as Map)['version'], 4);
          expect((call.arguments as Map)['title'], 'Hermes task complete');
          return {'outcome': 'DELIVERED', 'result_ref': resultRef('b')};
        });
    const notification = GatewayNotification(
      key: 'notice-7',
      text: 'The task completed.',
      level: GatewayNotificationLevel.success,
      delivery: GatewayNotificationDeliveryProjection(
        notificationId: 'notice-7',
        version: 4,
        title: 'Hermes task complete',
      ),
    );
    final result = await LocalNotificationService().show(notification);
    expect(result.outcome, GatewayNotificationDeliveryOutcome.delivered);
    expect(result.resultRef, resultRef('b'));
  });

  test('preserves native permission denial as a factual outcome', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalNotificationService.channel, (_) async {
          return {'outcome': 'PERMISSION_DENIED', 'result_ref': resultRef('c')};
        });
    const notification = GatewayNotification(
      key: 'notice-8',
      text: 'Permission is disabled.',
      level: GatewayNotificationLevel.warning,
      delivery: GatewayNotificationDeliveryProjection(
        notificationId: 'notice-8',
        version: 1,
        title: 'Hermes notification',
      ),
    );
    final result = await LocalNotificationService().show(notification);
    expect(result.outcome, GatewayNotificationDeliveryOutcome.permissionDenied);
  });

  test(
    'rejects malformed native results instead of inventing delivery',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LocalNotificationService.channel, (
            _,
          ) async {
            return {'outcome': 'DELIVERED', 'result_ref': 'wrong-authority'};
          });
      const notification = GatewayNotification(
        key: 'notice-9',
        text: 'Test',
        level: GatewayNotificationLevel.info,
        delivery: GatewayNotificationDeliveryProjection(
          notificationId: 'notice-9',
          version: 1,
          title: 'Hermes',
        ),
      );
      expect(
        LocalNotificationService().show(notification),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
