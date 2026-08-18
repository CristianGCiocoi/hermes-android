import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HermesColorPalette { gold, sapphire, emerald, amethyst, rose }

extension HermesColorPaletteDefinition on HermesColorPalette {
  String get storageKey => name;

  String get label => switch (this) {
    HermesColorPalette.gold => 'Hermes Gold',
    HermesColorPalette.sapphire => 'Sapphire',
    HermesColorPalette.emerald => 'Emerald',
    HermesColorPalette.amethyst => 'Amethyst',
    HermesColorPalette.rose => 'Rose',
  };

  Color get seed => switch (this) {
    HermesColorPalette.gold => const Color(0xFFD4AF37),
    HermesColorPalette.sapphire => const Color(0xFF246BCE),
    HermesColorPalette.emerald => const Color(0xFF168568),
    HermesColorPalette.amethyst => const Color(0xFF8054B8),
    HermesColorPalette.rose => const Color(0xFFB84E72),
  };
}

class AppearancePreference {
  final HermesColorPalette palette;
  final bool highContrast;

  const AppearancePreference({
    this.palette = HermesColorPalette.gold,
    this.highContrast = false,
  });

  AppearancePreference copyWith({
    HermesColorPalette? palette,
    bool? highContrast,
  }) {
    return AppearancePreference(
      palette: palette ?? this.palette,
      highContrast: highContrast ?? this.highContrast,
    );
  }
}

class AppearancePreferenceStore {
  static const paletteKey = 'color_palette';
  static const highContrastKey = 'high_contrast';

  final SharedPreferences _preferences;

  const AppearancePreferenceStore(this._preferences);

  AppearancePreference read() {
    final raw = _preferences.getString(paletteKey)?.trim().toLowerCase();
    final rawHighContrast = _preferences.get(highContrastKey);
    final palette = HermesColorPalette.values.where(
      (candidate) => candidate.storageKey == raw,
    );
    return AppearancePreference(
      palette: palette.isEmpty ? HermesColorPalette.gold : palette.first,
      highContrast: rawHighContrast is bool ? rawHighContrast : false,
    );
  }

  Future<void> save(AppearancePreference preference) async {
    await _preferences.setString(paletteKey, preference.palette.storageKey);
    await _preferences.setBool(highContrastKey, preference.highContrast);
  }
}
