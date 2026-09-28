import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notification_delivery_deduplicator.dart';

void main() {
  test('coalesces duplicate presentation revisions', () async {
    final deduplicator = NotificationDeliveryDeduplicator();
    final release = Completer<void>();
    var calls = 0;

    Future<void> operation() async {
      calls++;
      await release.future;
    }

    final first = deduplicator.deliver(
      notificationId: 'notice-1',
      version: 2,
      operation: operation,
    );
    final duplicate = deduplicator.deliver(
      notificationId: 'notice-1',
      version: 2,
      operation: operation,
    );
    expect(calls, 1);
    release.complete();
    await Future.wait([first, duplicate]);

    await deduplicator.deliver(
      notificationId: 'notice-1',
      version: 2,
      operation: operation,
    );
    expect(calls, 1);
  });

  test('permits retry after an unreported failure', () async {
    final deduplicator = NotificationDeliveryDeduplicator();
    var calls = 0;
    Future<void> operation() async {
      calls++;
      if (calls == 1) throw StateError('transport unavailable');
    }

    await expectLater(
      deduplicator.deliver(
        notificationId: 'notice-2',
        version: 1,
        operation: operation,
      ),
      throwsStateError,
    );
    await deduplicator.deliver(
      notificationId: 'notice-2',
      version: 1,
      operation: operation,
    );
    expect(calls, 2);
  });

  test('completed revision memory stays bounded', () async {
    final deduplicator = NotificationDeliveryDeduplicator(capacity: 2);
    var calls = 0;
    Future<void> operation() async => calls++;

    for (var version = 1; version <= 3; version++) {
      await deduplicator.deliver(
        notificationId: 'notice',
        version: version,
        operation: operation,
      );
    }
    await deduplicator.deliver(
      notificationId: 'notice',
      version: 1,
      operation: operation,
    );
    expect(calls, 4);
  });
}
