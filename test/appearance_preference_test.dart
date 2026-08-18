import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/appearance_preference.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults malformed local values to Hermes Gold', () async {
    SharedPreferences.setMockInitialValues({
      AppearancePreferenceStore.paletteKey: 'unknown',
      AppearancePreferenceStore.highContrastKey: 'yes',
    });
    final prefs = await SharedPreferences.getInstance();

    final appearance = AppearancePreferenceStore(prefs).read();

    expect(appearance.palette, HermesColorPalette.gold);
    expect(appearance.highContrast, isFalse);
  });

  test('persists palette and high contrast together', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppearancePreferenceStore(prefs);

    await store.save(
      const AppearancePreference(
        palette: HermesColorPalette.amethyst,
        highContrast: true,
      ),
    );

    final restored = store.read();
    expect(restored.palette, HermesColorPalette.amethyst);
    expect(restored.highContrast, isTrue);
  });

  testWidgets('HermesApp applies a palette change immediately', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final appKey = GlobalKey<HermesAppState>();
    await tester.pumpWidget(
      HermesApp(key: appKey, connManager: ConnectionManager(prefs)),
    );
    await tester.pumpAndSettle();

    final home = find.text('No connections');
    final gold = Theme.of(tester.element(home)).colorScheme;

    await appKey.currentState!.setAppearancePreference(
      const AppearancePreference(
        palette: HermesColorPalette.sapphire,
        highContrast: true,
      ),
    );
    await tester.pumpAndSettle();

    final sapphire = Theme.of(tester.element(home)).colorScheme;
    final expected = ColorScheme.fromSeed(
      seedColor: HermesColorPalette.sapphire.seed,
      brightness: Brightness.light,
      contrastLevel: 1,
    );
    expect(sapphire.primary, expected.primary);
    expect(sapphire.primary, isNot(gold.primary));
    expect(
      AppearancePreferenceStore(prefs).read().palette,
      HermesColorPalette.sapphire,
    );
  });
}
