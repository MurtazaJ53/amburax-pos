import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../database/mobile_repository.dart';

/// Languages the app ships with. Kept small and deliberate: English plus the
/// two languages our shopkeepers actually read.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('en'),
  Locale('hi'),
  Locale('gu'),
];

const String _kLocaleKey = 'app_locale';

/// Remembers the chosen app language across restarts.
///
/// A null state means "follow the device", which is the right default: a phone
/// already set to Gujarati should open the app in Gujarati without the owner
/// hunting through settings.
class LocaleController extends ChangeNotifier {
  LocaleController(this._shopRepository) {
    _load();
  }

  final ShopRepository _shopRepository;

  Locale? _locale;
  bool _loaded = false;

  Locale? get locale => _locale;
  bool get isLoaded => _loaded;

  /// The language code actually in effect, resolving "follow device" against
  /// what we support (falling back to English).
  String effectiveCode(Locale deviceLocale) {
    final code = _locale?.languageCode ?? deviceLocale.languageCode;
    return kSupportedLocales.any((l) => l.languageCode == code) ? code : 'en';
  }

  Future<void> _load() async {
    final stored = (await _shopRepository.readSetting(_kLocaleKey))?.trim();
    if (stored != null &&
        stored.isNotEmpty &&
        kSupportedLocales.any((l) => l.languageCode == stored)) {
      _locale = Locale(stored);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Pass null to go back to following the device language.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    await _shopRepository.writeSetting(_kLocaleKey, locale?.languageCode ?? '');
    notifyListeners();
  }
}

final localeControllerProvider = ChangeNotifierProvider<LocaleController>((
  ref,
) {
  return LocaleController(ref.watch(shopRepositoryProvider));
});
