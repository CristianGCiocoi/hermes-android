import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';

void main() {
  test('user bubble foreground passes WCAG AA in light and dark themes', () {
    final ratio = _contrastRatio(
      hermesUserMessageForeground,
      hermesUserMessageBubbleBackground,
    );

    expect(ratio, greaterThanOrEqualTo(4.5));
    // The pair is theme-independent, so the verified ratio applies to both.
    expect(hermesUserMessageBubbleBackground, const Color(0xFFD4AF37));
    expect(hermesUserMessageForeground, const Color(0xFF1C1B1F));
  });

  testWidgets('message bubble copies its original Markdown content', (
    WidgetTester tester,
  ) async {
    const message = 'Use `Hermes` from a **remote gateway**.';
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return {'text': clipboardText};
        default:
          return null;
      }
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MessageBubble(content: message, isUser: false)),
      ),
    );

    expect(find.byTooltip('Message actions'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);

    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-copy')));
    await tester.pumpAndSettle();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, message);
    expect(find.text('Message copied'), findsOneWidget);
  });

  testWidgets('assistant message exposes a read aloud action', (
    WidgetTester tester,
  ) async {
    var readAloudCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            content: 'Răspuns Hermes.',
            isUser: false,
            onReadAloud: () async {
              readAloudCalls++;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    expect(find.text('Read aloud'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message-action-read-aloud')));
    await tester.pumpAndSettle();
    expect(readAloudCalls, 1);
  });

  testWidgets('user message does not expose read aloud', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(content: 'Mesaj utilizator.', isUser: true),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select text'), findsOneWidget);
    expect(find.text('Read aloud'), findsNothing);
  });

  testWidgets('message menu retains semantics at font scale 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();

    for (final width in [320.0, 360.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: MessageBubble(
              content: 'A compact action layout.',
              isUser: false,
              onReadAloud: () async {},
              onShare: () async {},
              onEdit: () {},
              onRetry: () async {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Message actions'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('message-actions-button'))),
        const Size(48, 48),
      );
      await tester.tap(find.byTooltip('Message actions'));
      await tester.pumpAndSettle();
      for (final label in const [
        'Copy',
        'Select text',
        'Read aloud',
        'Share',
        'Edit and resend',
        'Regenerate response',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
    }
    semantics.dispose();
  });

  testWidgets('select text opens a focused selectable surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            content: 'Select **this exact** message.',
            isUser: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-select-text')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-selectable-text')), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    expect(find.text('Select **this exact** message.'), findsOneWidget);
  });

  testWidgets('share action uses the injected per-message callback', (
    tester,
  ) async {
    var shareCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            content: 'Share this response.',
            isUser: false,
            onShare: () async => shareCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Message actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-action-share')));
    await tester.pumpAndSettle();

    expect(shareCalls, 1);
  });

  testWidgets('role-specific edit and regenerate actions route once', (
    tester,
  ) async {
    var editCalls = 0;
    var regenerateCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MessageBubble(
                content: 'User prompt',
                isUser: true,
                onEdit: () => editCalls++,
              ),
              MessageBubble(
                content: 'Hermes response',
                isUser: false,
                onRetry: () async => regenerateCalls++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Message actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Regenerate response'), findsNothing);
    await tester.tap(find.byKey(const Key('message-action-edit')));
    await tester.pumpAndSettle();
    expect(editCalls, 1);

    await tester.tap(find.byTooltip('Message actions').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit and resend'), findsNothing);
    await tester.tap(find.byKey(const Key('message-action-regenerate')));
    await tester.pumpAndSettle();
    expect(regenerateCalls, 1);
  });
}

double _contrastRatio(Color first, Color second) {
  final light = _relativeLuminance(first);
  final dark = _relativeLuminance(second);
  final lighter = light > dark ? light : dark;
  final darker = light > dark ? dark : light;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double linearize(double channel) {
    final value = channel;
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}
