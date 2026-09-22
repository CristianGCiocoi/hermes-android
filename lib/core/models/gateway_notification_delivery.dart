enum GatewayNotificationDeliveryOutcome {
  delivered('DELIVERED'),
  permissionDenied('PERMISSION_DENIED'),
  deliveryFailed('DELIVERY_FAILED');

  final String wireValue;

  const GatewayNotificationDeliveryOutcome(this.wireValue);

  static GatewayNotificationDeliveryOutcome? fromWire(Object? value) {
    for (final outcome in values) {
      if (value == outcome.wireValue) return outcome;
    }
    return null;
  }
}

/// Optional, Hermes-owned notification delivery contract.
///
/// A missing or malformed declaration is treated as unsupported. Android must
/// not send notification RPCs unless this exact contract was advertised by the
/// authenticated Desktop Gateway connection.
class GatewayNotificationDeliveryCapability {
  static const contract = 'hermes.notification.delivery.v1';

  final bool supported;

  const GatewayNotificationDeliveryCapability._(this.supported);
  const GatewayNotificationDeliveryCapability.unsupported() : this._(false);

  factory GatewayNotificationDeliveryCapability.fromGatewayReady(
    Map<String, dynamic> frame,
  ) {
    final params = frame['params'];
    final payload = params is Map<String, dynamic> ? params['payload'] : null;
    final capabilities = payload is Map<String, dynamic>
        ? payload['capabilities']
        : null;
    final raw = capabilities is Map<String, dynamic>
        ? capabilities['notification_delivery']
        : null;
    const exactKeys = <String>{'contract', 'version', 'channel', 'methods'};
    if (raw is! Map<String, dynamic> ||
        raw.length != exactKeys.length ||
        !exactKeys.containsAll(raw.keys) ||
        raw['contract'] != contract ||
        raw['version'] != 1 ||
        raw['version'] is bool ||
        raw['channel'] != 'android-local' ||
        !_isExactStringList(raw['methods'], const [
          'notification.pull',
          'notification.delivery_result',
        ])) {
      return const GatewayNotificationDeliveryCapability.unsupported();
    }
    return const GatewayNotificationDeliveryCapability._(true);
  }

  static bool _isExactStringList(Object? value, List<String> expected) {
    if (value is! List || value.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (value[index] is! String || value[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }
}

/// Safe presentation metadata attached to a regular `notification.show`
/// event. The visible body remains the existing, bounded event `text` field.
class GatewayNotificationDeliveryProjection {
  static const contract = 'hermes.notification.presentation.v1';

  final String notificationId;
  final int version;
  final String title;

  const GatewayNotificationDeliveryProjection({
    required this.notificationId,
    required this.version,
    required this.title,
  });

  static GatewayNotificationDeliveryProjection? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    const exactKeys = <String>{
      'contract',
      'notification_id',
      'version',
      'title',
    };
    final notificationId = value['notification_id'];
    final version = value['version'];
    final title = value['title'];
    if (value.length != exactKeys.length ||
        !exactKeys.containsAll(value.keys) ||
        value['contract'] != contract ||
        notificationId is! String ||
        !_isSafeWireText(notificationId, maxLength: 200) ||
        version is! int ||
        version is bool ||
        version < 1 ||
        title is! String ||
        !_isSafeWireText(title, maxLength: 80)) {
      return null;
    }
    return GatewayNotificationDeliveryProjection(
      notificationId: notificationId,
      version: version,
      title: title,
    );
  }
}

class GatewayNotificationDeliveryReceipt {
  final String notificationId;
  final int version;
  final String state;

  const GatewayNotificationDeliveryReceipt({
    required this.notificationId,
    required this.version,
    required this.state,
  });

  static GatewayNotificationDeliveryReceipt? fromResult(
    Object? value, {
    required String expectedNotificationId,
    required int minimumVersion,
    required GatewayNotificationDeliveryOutcome expectedOutcome,
  }) {
    if (value is! Map<String, dynamic>) return null;
    const exactKeys = <String>{'notification_id', 'version', 'state'};
    final version = value['version'];
    final state = value['state'];
    final expectedState =
        expectedOutcome == GatewayNotificationDeliveryOutcome.delivered
        ? 'DELIVERED'
        : 'DELIVERY_FAILED';
    if (value.length != exactKeys.length ||
        !exactKeys.containsAll(value.keys) ||
        value['notification_id'] != expectedNotificationId ||
        version is! int ||
        version is bool ||
        version < minimumVersion ||
        state != expectedState) {
      return null;
    }
    return GatewayNotificationDeliveryReceipt(
      notificationId: expectedNotificationId,
      version: version,
      state: state as String,
    );
  }
}

bool _isSafeWireText(String value, {required int maxLength}) {
  if (value.isEmpty || value.length > maxLength || value.trim() != value) {
    return false;
  }
  return !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
}
