import 'package:flutter/services.dart';

import '../models/gateway_insight.dart';
import '../models/gateway_notification_delivery.dart';

enum LocalNotificationPermissionState { granted, denied }

class LocalNotificationDeliveryResult {
  final GatewayNotificationDeliveryOutcome outcome;
  final String resultRef;

  const LocalNotificationDeliveryResult({
    required this.outcome,
    required this.resultRef,
  });
}

/// Thin Android presentation adapter. Gateway identity and credentials never
/// cross this channel; only bounded presentation data is sent to the OS.
class LocalNotificationService {
  static const MethodChannel channel = MethodChannel(
    'hermes.notification/local',
  );

  Future<LocalNotificationPermissionState> requestPermission() async {
    final granted = await channel.invokeMethod<bool>('requestPermission');
    return granted == true
        ? LocalNotificationPermissionState.granted
        : LocalNotificationPermissionState.denied;
  }

  Future<LocalNotificationDeliveryResult> show(
    GatewayNotification notification,
  ) async {
    final delivery = notification.delivery;
    if (delivery == null) {
      throw StateError('The Gateway notification has no delivery projection');
    }
    final response = await channel.invokeMapMethod<String, dynamic>('show', {
      'notification_id': delivery.notificationId,
      'version': delivery.version,
      'title': delivery.title,
      'body': notification.text,
    });
    final outcome = GatewayNotificationDeliveryOutcome.fromWire(
      response?['outcome'],
    );
    final resultRef = response?['result_ref'];
    if (outcome == null ||
        resultRef is! String ||
        !resultRef.startsWith('urn:hermes:android-delivery:') ||
        resultRef.length != 92) {
      throw PlatformException(
        code: 'invalid_delivery_result',
        message: 'Android returned an invalid delivery result',
      );
    }
    return LocalNotificationDeliveryResult(
      outcome: outcome,
      resultRef: resultRef,
    );
  }
}
