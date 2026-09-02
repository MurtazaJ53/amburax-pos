import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/ui.dart';

/// Language options. The label is deliberately written *in* the language
/// itself: someone who can't read English still has to recognise their own
/// option, so "Gujarati" would be useless where "ગુજરાતી" is obvious.
class _LanguageOption {
  const _LanguageOption({
    required this.code,
    required this.nativeName,
    required this.englishName,
  });

  /// null = follow the device language.
  final String? code;
  final String nativeName;
  final String englishName;
}

const List<_LanguageOption> _options = <_LanguageOption>[
  _LanguageOption(
    code: null,
    nativeName: 'Automatic',
    englishName: 'Use the phone language',
  ),
  _LanguageOption(code: 'en', nativeName: 'English', englishName: 'English'),
  _LanguageOption(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi'),
  _LanguageOption(code: 'gu', nativeName: 'ગુજરાતી', englishName: 'Gujarati'),
];

class SettingsLanguageScreen extends ConsumerWidget {
  const SettingsLanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final colors = AppColors.of(context);
    final controller = ref.watch(localeControllerProvider);
    final selected = controller.locale?.languageCode;

    return AppScreen(
      scrollable: false,
      title: l.settingsLanguage,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          Text(
            l.settingsLanguageSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final option in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LanguageTile(
                option: option,
                selected: selected == option.code,
                onTap: () async {
                  await ref
                      .read(localeControllerProvider)
                      .setLocale(
                        option.code == null ? null : Locale(option.code!),
                      );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    // Read the *new* localisations so the confirmation itself
                    // appears in the language just chosen.
                    SnackBar(content: Text(L.of(context).langChanged)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _LanguageOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected
          ? AppPalette.primary.withValues(alpha: 0.10)
          : colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppPalette.primary : colors.borderSoft,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      option.nativeName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.englishName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppPalette.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
