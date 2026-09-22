import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/hermes_brand_style.dart';
import 'package:hermes_android/main.dart';

void main() {
  test('startup and wordmarks have no runtime font provider dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();
    final productionSources = [
      File('lib/main.dart').readAsStringSync(),
      File('lib/core/screens/session_list_screen.dart').readAsStringSync(),
      File('lib/core/widgets/hermes_brand_style.dart').readAsStringSync(),
    ].join('\n');

    expect(pubspec, isNot(contains('google_fonts:')));
    expect(lockfile, isNot(contains('google_fonts:')));
    expect(productionSources, isNot(contains('GoogleFonts')));
    expect(productionSources, isNot(contains('fonts.gstatic.com')));
    expect(productionSources, isNot(contains('allowRuntimeFetching')));
    expect(productionSources, contains("fontFamily: 'serif'"));
  });

  testWidgets('Hermes wordmark paints with the packaged system font', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HermesHeader())),
    );
    await tester.pumpAndSettle();

    expect(find.text('HERMES'), findsOneWidget);
    final text = tester.widget<Text>(find.text('HERMES'));
    expect(text.style?.fontFamily, 'serif');
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(tester.takeException(), isNull);
  });

  test('brand style is synchronous and offline-safe', () {
    final style = hermesBrandStyle(fontSize: 22, letterSpacing: 6);
    expect(style.fontFamily, 'serif');
    expect(style.fontWeight, FontWeight.w700);
  });
}
