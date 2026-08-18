import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/gateway_activity_center_controller.dart';
import 'package:hermes_android/core/widgets/gateway_activity_center_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDismissalStore implements GatewayActivityDismissalStore {
  final Map<String, Set<String>> values = {};

  @override
  Future<Set<String>> read(String sessionIdentity) async =>
      Set<String>.from(values[sessionIdentity] ?? const <String>{});

  @override
  Future<void> write(String sessionIdentity, Set<String> dismissedIds) async {
    values[sessionIdentity] = Set<String>.from(dismissedIds);
  }
}

class _DelayedDismissalStore extends _FakeDismissalStore {
  final readReady = Completer<void>();

  @override
  Future<Set<String>> read(String sessionIdentity) async {
    await readReady.future;
    return super.read(sessionIdentity);
  }
}

void main() {
  test('notice identity is a content-safe stable digest', () {
    const notice = GatewayNotice(
      kind: GatewayNoticeKind.review,
      text: 'Sensitive review summary that must not enter preferences.',
    );

    expect(notice.identity, hasLength(64));
    expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(notice.identity), isTrue);
    expect(notice.identity, isNot(contains('Sensitive')));
  });

  test('SharedPreferences store keeps only bounded digest metadata', () async {
    SharedPreferences.setMockInitialValues({
      'gateway_activity_dismissals_v1':
          '{"malformed-session":["raw review text"]}',
    });
    const store = SharedPreferencesGatewayActivityDismissalStore();
    final dismissalId = 'b' * 64;
    await store.write('https://gateway.invalid/profile|session-private', {
      dismissalId,
    });
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('gateway_activity_dismissals_v1')!;

    expect(raw, contains(dismissalId));
    expect(raw, isNot(contains('gateway.invalid')));
    expect(raw, isNot(contains('session-private')));
    expect(raw, isNot(contains('raw review text')));
    expect(
      await store.read('https://gateway.invalid/profile|session-private'),
      {dismissalId},
    );
  });

  test(
    'dismissal survives controller recreation without persisting text',
    () async {
      final store = _FakeDismissalStore();
      const identity = 'connection-a|session-dismissal';
      const notice = GatewayNotice(
        kind: GatewayNoticeKind.review,
        text: 'Self-improvement review completed.',
      );
      final first = GatewayActivityCenterController(
        sessionIdentity: identity,
        dismissalStore: store,
      );
      await first.initialize();
      expect(first.addNotice(notice), isTrue);
      expect(first.addNotice(notice), isFalse);
      expect(first.transcriptNotices, hasLength(1));

      await first.dismissNotice(notice.identity);
      expect(first.transcriptNotices, isEmpty);
      expect(first.notices.single.dismissed, isTrue);
      expect(store.values[identity], {notice.identity});
      expect(store.values.toString(), isNot(contains(notice.text)));
      first.dispose();

      final second = GatewayActivityCenterController(
        sessionIdentity: identity,
        dismissalStore: store,
      );
      await second.initialize();
      expect(second.transcriptNotices, isEmpty);
      expect(second.notices.single.dismissed, isTrue);
      second.dispose();
    },
  );

  test('dismiss waits for restore and preserves older tombstones', () async {
    final store = _DelayedDismissalStore();
    const identity = 'connection-a|session-race';
    final olderId = 'a' * 64;
    store.values[identity] = {olderId};
    const notice = GatewayNotice(
      kind: GatewayNoticeKind.review,
      text: 'A newer review summary.',
    );
    final controller = GatewayActivityCenterController(
      sessionIdentity: identity,
      dismissalStore: store,
    );
    final initialization = controller.initialize();
    controller.addNotice(notice);
    final dismissal = controller.dismissNotice(notice.identity);

    expect(store.values[identity], {olderId});
    store.readReady.complete();
    await initialization;
    await dismissal;

    expect(store.values[identity], {olderId, notice.identity});
    controller.dispose();
  });

  test('tools, subagents, notices, and status share one projection', () async {
    final controller = GatewayActivityCenterController(
      sessionIdentity: 'connection-a|session-projection',
      dismissalStore: _FakeDismissalStore(),
    );
    await controller.initialize();
    controller.upsertTool(
      const GatewayToolActivity(
        toolId: 'tool-1',
        name: 'search_files',
        phase: GatewayToolActivityPhase.running,
      ),
    );
    controller.upsertTool(
      const GatewayToolActivity(
        toolId: 'tool-1',
        name: 'search_files',
        phase: GatewayToolActivityPhase.completed,
      ),
    );
    controller.upsertSubagent(
      const GatewaySubagentActivity(
        id: 'subagent-1',
        goal: 'Inspect activity events',
        phase: GatewaySubagentPhase.running,
      ),
    );
    controller.setNeedsInput(true);
    controller.setLegacyTransportFallback(true);
    controller.setTurnStatus(
      const GatewayTurnStatus(kind: 'clarify', text: 'Waiting for input'),
    );

    expect(controller.tools, hasLength(1));
    expect(controller.tools.single.isTerminal, isTrue);
    expect(controller.subagents, hasLength(1));
    expect(controller.runningCount, 1);
    expect(controller.needsInput, isTrue);
    expect(controller.legacyTransportFallback, isTrue);
    expect(controller.turnStatus?.text, 'Waiting for input');
    controller.dispose();
  });

  test('notice history is deduplicated and bounded per session', () async {
    final controller = GatewayActivityCenterController(
      sessionIdentity: 'connection-a|session-bounded',
      dismissalStore: _FakeDismissalStore(),
    );
    await controller.initialize();
    for (var index = 0; index < 25; index++) {
      controller.addNotice(
        GatewayNotice(
          kind: GatewayNoticeKind.background,
          taskId: 'task-$index',
          text: 'Completed task $index.',
        ),
      );
    }

    expect(controller.notices, hasLength(20));
    expect(controller.notices.first.notice.taskId, 'task-5');
    controller.dispose();
  });

  testWidgets('Activity Center renders shared status and archived review', (
    tester,
  ) async {
    final controller = GatewayActivityCenterController(
      sessionIdentity: 'connection-a|session-widget',
      dismissalStore: _FakeDismissalStore(),
    );
    await controller.initialize();
    controller.setLegacyTransportFallback(true);
    controller.setNeedsInput(true);
    controller.addNotice(
      const GatewayNotice(
        kind: GatewayNoticeKind.review,
        text: 'Skill atlas-document-synthesis created.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    GatewayActivityCenterSheet(controller: controller),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Hermes activity'), findsOneWidget);
    expect(find.byKey(const Key('activity-legacy-status')), findsOneWidget);
    expect(find.byKey(const Key('activity-needs-input')), findsOneWidget);
    expect(find.text('Hermes review'), findsOneWidget);
    expect(find.textContaining('atlas-document-synthesis'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'Activity Center excludes foreground work and keeps only tool failures',
    (tester) async {
      final controller = GatewayActivityCenterController(
        sessionIdentity: 'connection-a|session-distinct-projections',
        dismissalStore: _FakeDismissalStore(),
      );
      await controller.initialize();
      controller.upsertTool(
        const GatewayToolActivity(
          toolId: 'tool-complete',
          name: 'search_files',
          phase: GatewayToolActivityPhase.completed,
        ),
      );
      controller.upsertTool(
        const GatewayToolActivity(
          toolId: 'tool-failed',
          name: 'read_file',
          phase: GatewayToolActivityPhase.failed,
          detail: 'Synthetic failure',
        ),
      );
      controller.upsertSubagent(
        const GatewaySubagentActivity(
          id: 'subagent-running',
          goal: 'Foreground delegated task',
          phase: GatewaySubagentPhase.running,
        ),
      );
      controller.setTurnStatus(
        const GatewayTurnStatus(kind: 'working', text: 'Foreground status'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      GatewayActivityCenterSheet(controller: controller),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Errors'), findsOneWidget);
      expect(find.text('Read file'), findsOneWidget);
      expect(find.text('Search files'), findsNothing);
      expect(find.text('Foreground delegated task'), findsNothing);
      expect(find.text('Foreground status'), findsNothing);
      expect(find.text('Delegated tasks'), findsNothing);
      controller.dispose();
    },
  );
}
