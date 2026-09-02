import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/mobile_repository.dart';

const String _kThemeModeKey = 'app_theme_mode';

/// Controls the app's light/dark presentation, and remembers the choice.
///
/// Two things were wrong here and both are fixed together, because either one
/// alone still leaves the setting looking broken.
///
/// The switch had nothing to switch to: `app.dart` passed `AppTheme.light` as
/// both `theme` and `darkTheme`, so choosing Night rendered the light theme
/// and the control appeared dead. `AppTheme.dark` existed the whole time and
/// was simply never wired up.
///
/// And the choice did not survive a restart. The doc on the old version said
/// persistence was "a follow-up"; a display preference that resets every time
/// the app is opened is not a preference, so it now goes to the same settings
/// store the language uses.
///
/// The default is [ThemeMode.system]. A shop floor at midday and a back office
/// at closing are different rooms, and the phone already knows which one it is
/// in. The old default pinned light with a comment saying the app was
/// "light only" — it is not, and its own dark palette has tests.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Loads in the background; the app starts on the device setting and
    // corrects itself a frame later if a choice was stored. Blocking startup
    // on a settings read to avoid one repaint is the worse trade.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final stored =
        (await ref.read(shopRepositoryProvider).readSetting(_kThemeModeKey))
            ?.trim();
    final restored = _parse(stored);
    if (restored != null) state = restored;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(shopRepositoryProvider)
        .writeSetting(_kThemeModeKey, mode.name);
  }

  Future<void> toggle() => set(switch (state) {
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.light,
    // From "follow the device", one tap should visibly change something, so
    // it lands on the opposite of whatever the device is currently showing.
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? ThemeMode.light
          : ThemeMode.dark,
  });

  static ThemeMode? _parse(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}
