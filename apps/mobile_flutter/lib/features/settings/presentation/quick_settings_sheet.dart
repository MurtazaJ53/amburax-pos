import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../shell/presentation/mobile_surface.dart';

/// Language and day/night, one tap from any screen.
///
/// Asked for in review as a floating button. It is a sheet opened from the
/// header instead, deliberately: a floating control sits on top of the product
/// grid, which is the busiest screen in the app and the one where an
/// accidental tap costs the most — a mis-tap mid-sale with a customer waiting.
/// The header button is always in the same place, never covers the grid, and
/// reaches the same two settings in the same number of taps.
Future<void> showQuickSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _QuickSettingsSheet(),
  );
}

class _QuickSettingsSheet extends ConsumerWidget {
  const _QuickSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final localeController = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final deviceLocale = Localizations.localeOf(context);
    final active = localeController.effectiveCode(deviceLocale);
    final followingDevice = localeController.locale == null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const MobileSheetHeader(
              title: 'Quick settings',
              subtitle: 'Language and display, without leaving this screen.',
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: 18),

            _Label(text: 'Language'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final option in _languages)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: !followingDevice && active == option.code,
                    onSelected: (_) =>
                        localeController.setLocale(Locale(option.code)),
                  ),
                // Following the device is the right default — a phone already
                // set to Gujarati should open the app in Gujarati — so it stays
                // reachable rather than being a one-way door.
                ChoiceChip(
                  label: const Text('Device'),
                  selected: followingDevice,
                  onSelected: (_) => localeController.setLocale(null),
                ),
              ],
            ),

            const SizedBox(height: 22),
            _Label(text: 'Display'),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Day'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Night'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  icon: Icon(Icons.smartphone_rounded),
                  label: Text('Auto'),
                ),
              ],
              selected: <ThemeMode>{themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).set(selection.first),
            ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/settings');
                },
                icon: const Icon(Icons.settings_rounded),
                label: const Text('All settings'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Language applies immediately. Anything else lives in Settings.',
              style: TextStyle(fontSize: 11, color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
        color: colors.textTertiary,
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption(this.code, this.label);

  final String code;
  final String label;
}

/// Labelled in each language's own script: a shopkeeper looking for Gujarati
/// is looking for "ગુજરાતી", not for the word "Gujarati".
const List<_LanguageOption> _languages = <_LanguageOption>[
  _LanguageOption('en', 'English'),
  _LanguageOption('hi', 'हिंदी'),
  _LanguageOption('gu', 'ગુજરાતી'),
];
