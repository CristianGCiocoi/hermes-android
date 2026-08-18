import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';

abstract interface class GatewayActivityDismissalStore {
  Future<Set<String>> read(String sessionIdentity);

  Future<void> write(String sessionIdentity, Set<String> dismissedIds);
}

class SharedPreferencesGatewayActivityDismissalStore
    implements GatewayActivityDismissalStore {
  static const _storageKey = 'gateway_activity_dismissals_v1';
  static const _maxSessions = 100;
  static const _maxDismissalsPerSession = 100;

  const SharedPreferencesGatewayActivityDismissalStore();

  String _sessionKey(String identity) =>
      sha256.convert(utf8.encode(identity)).toString();

  @override
  Future<Set<String>> read(String sessionIdentity) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String>{};
      final values = decoded[_sessionKey(sessionIdentity)];
      if (values is! List) return <String>{};
      return values
          .whereType<String>()
          .where((value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
          .take(_maxDismissalsPerSession)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<void> write(String sessionIdentity, Set<String> dismissedIds) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = <String, dynamic>{};
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
                entry.value is! List) {
              continue;
            }
            stored[entry.key] = (entry.value as List)
                .whereType<String>()
                .where((value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
                .take(_maxDismissalsPerSession)
                .toList(growable: false);
          }
        }
      } catch (_) {
        // Replace malformed local preference state with a bounded clean map.
      }
    }
    stored[_sessionKey(sessionIdentity)] = dismissedIds
        .where((value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
        .take(_maxDismissalsPerSession)
        .toList(growable: false);
    while (stored.length > _maxSessions) {
      stored.remove(stored.keys.first);
    }
    final saved = await prefs.setString(_storageKey, jsonEncode(stored));
    if (!saved) throw StateError('Could not persist Activity dismissals');
  }
}

class GatewayActivityNoticeEntry {
  final GatewayNotice notice;
  final bool dismissed;

  const GatewayActivityNoticeEntry({
    required this.notice,
    required this.dismissed,
  });
}

/// The single session-scoped source of truth for Gateway operational UI.
///
/// Transcript cards and the Activity Center consume distinct projections of
/// this controller. Foreground tools and delegated work stay in the transcript;
/// the center is reserved for attention, recovery, errors, and durable notices.
/// It intentionally stores only dismissal digests on disk; review/background
/// text remains memory-only and authoritative Gateway events remain server-owned.
class GatewayActivityCenterController extends ChangeNotifier {
  static const _maxNotices = 20;
  static const _maxCachedSessions = 100;
  static final Map<String, List<GatewayNotice>> _memoryNoticeCache = {};

  final String sessionIdentity;
  final GatewayActivityDismissalStore dismissalStore;
  final List<GatewayToolActivity> _tools = [];
  final List<GatewaySubagentActivity> _subagents = [];
  final Map<String, GatewayNotification> _notifications = {};
  final Map<String, Timer> _notificationTimers = {};
  final List<GatewayNotice> _notices;
  final Set<String> _dismissedNoticeIds = {};
  Future<void> _persistTail = Future<void>.value();
  Future<void>? _initialization;
  GatewayTurnStatus? _turnStatus;
  bool _legacyTransportFallback = false;
  bool _needsInput = false;
  bool _disposed = false;

  GatewayActivityCenterController({
    required this.sessionIdentity,
    this.dismissalStore =
        const SharedPreferencesGatewayActivityDismissalStore(),
  }) : _notices = List<GatewayNotice>.from(
         _memoryNoticeCache[sessionIdentity] ?? const <GatewayNotice>[],
       );

  List<GatewayToolActivity> get tools => List.unmodifiable(_tools);
  List<GatewaySubagentActivity> get subagents => List.unmodifiable(_subagents);
  List<GatewayNotification> get notifications =>
      List.unmodifiable(_notifications.values);
  GatewayTurnStatus? get turnStatus => _turnStatus;
  bool get legacyTransportFallback => _legacyTransportFallback;
  bool get needsInput => _needsInput;

  List<GatewayActivityNoticeEntry> get notices => _notices
      .map(
        (notice) => GatewayActivityNoticeEntry(
          notice: notice,
          dismissed: _dismissedNoticeIds.contains(notice.identity),
        ),
      )
      .toList(growable: false);

  List<GatewayNotice> get transcriptNotices => _notices
      .where((notice) => !_dismissedNoticeIds.contains(notice.identity))
      .toList(growable: false);

  int get runningCount =>
      _tools.where((activity) => !activity.isTerminal).length +
      _subagents.where((activity) => !activity.isComplete).length;

  int get failedCount => _tools.where((activity) => activity.isFailed).length;

  int get attentionCount =>
      (_needsInput ? 1 : 0) +
      failedCount +
      _notifications.values
          .where(
            (notice) =>
                notice.level == GatewayNotificationLevel.warning ||
                notice.level == GatewayNotificationLevel.error,
          )
          .length +
      transcriptNotices.length;

  Future<void> initialize() => _initialization ??= _restoreDismissals();

  Future<void> _restoreDismissals() async {
    try {
      final restored = await dismissalStore.read(sessionIdentity);
      if (_disposed) return;
      _dismissedNoticeIds.addAll(restored);
      notifyListeners();
    } catch (_) {
      // A malformed or unavailable local preference must not break chat.
    }
  }

  void replaceTools(Iterable<GatewayToolActivity> activities) {
    _tools
      ..clear()
      ..addAll(activities);
    _notify();
  }

  void upsertTool(GatewayToolActivity update) {
    var index = update.toolId == null
        ? -1
        : _tools.indexWhere((activity) => activity.toolId == update.toolId);
    if (index < 0) {
      index = _tools.lastIndexWhere(
        (activity) =>
            !activity.isTerminal &&
            activity.name.toLowerCase() == update.name.toLowerCase(),
      );
    }
    if (index < 0) {
      _tools.add(update);
    } else {
      _tools[index] = _tools[index].merge(update);
    }
    _notify();
  }

  void upsertSubagent(GatewaySubagentActivity update) {
    final index = _subagents.indexWhere((activity) => activity.id == update.id);
    if (index < 0) {
      _subagents.add(update);
    } else {
      _subagents[index] = _subagents[index].merge(update);
    }
    _notify();
  }

  void showNotification(GatewayNotification notification) {
    _notificationTimers.remove(notification.key)?.cancel();
    _notifications[notification.key] = notification;
    if (notification.ttl case final ttl?) {
      _notificationTimers[notification.key] = Timer(ttl, () {
        if (_disposed) return;
        _notifications.remove(notification.key);
        _notificationTimers.remove(notification.key);
        _notify();
      });
    }
    _notify();
  }

  void clearNotification([String? key]) {
    if (key == null || key.trim().isEmpty) {
      _notifications.clear();
      for (final timer in _notificationTimers.values) {
        timer.cancel();
      }
      _notificationTimers.clear();
    } else {
      _notifications.remove(key);
      _notificationTimers.remove(key)?.cancel();
    }
    _notify();
  }

  bool addNotice(GatewayNotice notice) {
    if (_notices.any((item) => item.identity == notice.identity)) return false;
    _notices.add(notice);
    if (_notices.length > _maxNotices) _notices.removeAt(0);
    _syncMemoryCache();
    _notify();
    return true;
  }

  Future<void> dismissNotice(String identity) async {
    await initialize();
    if (_disposed) return;
    if (!_notices.any((notice) => notice.identity == identity)) return;
    if (!_dismissedNoticeIds.add(identity)) return;
    _notify();
    final snapshot = Set<String>.from(_dismissedNoticeIds);
    _persistTail = _persistTail
        .catchError((_) {})
        .then((_) => dismissalStore.write(sessionIdentity, snapshot));
    try {
      await _persistTail;
    } catch (_) {
      if (!_disposed) {
        _dismissedNoticeIds.remove(identity);
        _notify();
      }
      rethrow;
    }
  }

  void setTurnStatus(GatewayTurnStatus? status) {
    if (_turnStatus?.kind == status?.kind &&
        _turnStatus?.text == status?.text) {
      return;
    }
    _turnStatus = status;
    _notify();
  }

  void setLegacyTransportFallback(bool enabled) {
    if (_legacyTransportFallback == enabled) return;
    _legacyTransportFallback = enabled;
    _notify();
  }

  void setNeedsInput(bool enabled) {
    if (_needsInput == enabled) return;
    _needsInput = enabled;
    _notify();
  }

  void _syncMemoryCache() {
    if (!_memoryNoticeCache.containsKey(sessionIdentity) &&
        _memoryNoticeCache.length >= _maxCachedSessions) {
      _memoryNoticeCache.remove(_memoryNoticeCache.keys.first);
    }
    _memoryNoticeCache[sessionIdentity] = List<GatewayNotice>.unmodifiable(
      _notices,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncMemoryCache();
    for (final timer in _notificationTimers.values) {
      timer.cancel();
    }
    _notificationTimers.clear();
    super.dispose();
  }
}
