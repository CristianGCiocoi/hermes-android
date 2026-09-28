import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_interaction_mode.dart';
import 'package:hermes_android/core/services/desktop_session_feature_reconciler.dart';

void main() {
  test('notification pull survives an interaction-mode failure', () async {
    var permissionRequested = false;
    var notificationPulled = false;

    final result = await reconcileDesktopSessionFeatures(
      ensureSession: () async => true,
      readInteractionMode: () async => throw StateError('mode unavailable'),
      supportsNotificationDelivery: () async => true,
      requestNotificationPermission: () async {
        permissionRequested = true;
      },
      pullNotification: () async {
        notificationPulled = true;
        return true;
      },
    );

    expect(result, isNotNull);
    expect(result!.effectiveFullControl, isTrue);
    expect(result.interactionMode, isNull);
    expect(result.notificationPullCompleted, isTrue);
    expect(permissionRequested, isTrue);
    expect(notificationPulled, isTrue);
  });

  test(
    'permission prompt failure still permits factual delivery attempt',
    () async {
      var notificationPulled = false;
      final result = await reconcileDesktopSessionFeatures(
        ensureSession: () async => null,
        readInteractionMode: () async =>
            const GatewayInteractionModeState.standardOnly(),
        supportsNotificationDelivery: () async => true,
        requestNotificationPermission: () async =>
            throw StateError('permission prompt unavailable'),
        pullNotification: () async {
          notificationPulled = true;
          return true;
        },
      );

      expect(result, isNotNull);
      expect(result!.notificationPullCompleted, isTrue);
      expect(notificationPulled, isTrue);
    },
  );

  test('generic Gateway performs zero notification actions', () async {
    var permissionRequested = false;
    var notificationPulled = false;
    final result = await reconcileDesktopSessionFeatures(
      ensureSession: () async => false,
      readInteractionMode: () async =>
          const GatewayInteractionModeState.standardOnly(),
      supportsNotificationDelivery: () async => false,
      requestNotificationPermission: () async {
        permissionRequested = true;
      },
      pullNotification: () async {
        notificationPulled = true;
        return true;
      },
    );

    expect(result, isNotNull);
    expect(result!.notificationPullCompleted, isFalse);
    expect(permissionRequested, isFalse);
    expect(notificationPulled, isFalse);
  });

  test('session failure stops all optional reconciliation', () async {
    var optionalCallCount = 0;
    final result = await reconcileDesktopSessionFeatures(
      ensureSession: () async => throw StateError('connection unavailable'),
      readInteractionMode: () async {
        optionalCallCount++;
        return const GatewayInteractionModeState.standardOnly();
      },
      supportsNotificationDelivery: () async {
        optionalCallCount++;
        return true;
      },
      requestNotificationPermission: () async => optionalCallCount++,
      pullNotification: () async {
        optionalCallCount++;
        return true;
      },
    );

    expect(result, isNull);
    expect(optionalCallCount, 0);
  });
}
