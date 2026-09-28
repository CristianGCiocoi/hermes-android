import '../models/gateway_interaction_mode.dart';

class DesktopSessionFeatureReconciliation {
  final bool? effectiveFullControl;
  final GatewayInteractionModeState? interactionMode;
  final bool notificationPullCompleted;

  const DesktopSessionFeatureReconciliation({
    required this.effectiveFullControl,
    required this.interactionMode,
    required this.notificationPullCompleted,
  });
}

/// Reconciles optional Desktop features after one authenticated session is
/// available. Each optional capability fails independently so a generic or
/// partially upgraded Gateway cannot suppress another advertised feature.
Future<DesktopSessionFeatureReconciliation?> reconcileDesktopSessionFeatures({
  required Future<bool?> Function() ensureSession,
  required Future<GatewayInteractionModeState> Function() readInteractionMode,
  required Future<bool> Function() supportsNotificationDelivery,
  required Future<void> Function() requestNotificationPermission,
  required Future<bool> Function() pullNotification,
}) async {
  final bool? effectiveFullControl;
  try {
    effectiveFullControl = await ensureSession();
  } catch (_) {
    return null;
  }

  GatewayInteractionModeState? interactionMode;
  try {
    interactionMode = await readInteractionMode();
  } catch (_) {
    // Standard chat remains usable while this optional capability recovers.
  }

  var notificationPullCompleted = false;
  try {
    if (await supportsNotificationDelivery()) {
      try {
        await requestNotificationPermission();
      } catch (_) {
        // The native presentation adapter still provides the factual denied or
        // failed result if the permission prompt itself cannot be displayed.
      }
      notificationPullCompleted = await pullNotification();
    }
  } catch (_) {
    // The retained Gateway item remains available for a later lifecycle pull.
  }

  return DesktopSessionFeatureReconciliation(
    effectiveFullControl: effectiveFullControl,
    interactionMode: interactionMode,
    notificationPullCompleted: notificationPullCompleted,
  );
}
