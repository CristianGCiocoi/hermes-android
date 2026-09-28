class NotificationDeliveryDeduplicator {
  final int capacity;
  final Map<String, Future<void>> _deliveries = {};

  NotificationDeliveryDeduplicator({this.capacity = 64}) : assert(capacity > 0);

  /// Coalesces the same presentation revision while retaining a bounded set of
  /// completed revisions. A failed attempt is removed so the Gateway can retry
  /// it later with the same deterministic native result reference.
  Future<void> deliver({
    required String notificationId,
    required int version,
    required Future<void> Function() operation,
  }) async {
    final key = '$notificationId:$version';
    final pending = _deliveries[key];
    if (pending != null) return pending;

    final delivery = operation();
    _deliveries[key] = delivery;
    try {
      await delivery;
      while (_deliveries.length > capacity) {
        _deliveries.remove(_deliveries.keys.first);
      }
    } catch (_) {
      if (identical(_deliveries[key], delivery)) _deliveries.remove(key);
      rethrow;
    }
  }
}
