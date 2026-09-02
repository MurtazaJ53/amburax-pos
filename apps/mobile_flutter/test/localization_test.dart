import 'dart:convert';
import 'dart:io';

import 'package:business_hub_mobile/core/i18n/locale_controller.dart';
import 'package:business_hub_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A half-translated app is worse than an English one: the user hits a wall of
/// English mid-flow and loses trust. These tests fail if a language falls
/// behind the English template, or if a translation was left in English.
Map<String, dynamic> _arb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('missing lib/l10n/app_$locale.arb');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final en = _arb('en');
  final enKeys = _keys(en);

  group('translation completeness', () {
    for (final locale in <String>['hi', 'gu']) {
      test('$locale covers every English key', () {
        final missing = enKeys.difference(_keys(_arb(locale)));
        expect(
          missing,
          isEmpty,
          reason: '$locale is missing: ${missing.join(', ')}',
        );
      });

      test('$locale has no extra keys the template lacks', () {
        final extra = _keys(_arb(locale)).difference(enKeys);
        expect(extra, isEmpty, reason: '$locale has stale keys: $extra');
      });

      test('$locale actually translated the user-facing strings', () {
        // Brand names and protocol names stay as-is on purpose.
        const allowedIdentical = <String>{
          'appName',
          'payUpi',
          'payCard',
          'langEnglish',
          'langHindi',
          'langGujarati',
          'actionPrint',
          'actionRefresh',
        };
        final target = _arb(locale);
        final untranslated = <String>[];
        for (final key in enKeys) {
          if (allowedIdentical.contains(key)) continue;
          if (target[key] == en[key]) untranslated.add(key);
        }
        expect(
          untranslated,
          isEmpty,
          reason: '$locale left these in English: ${untranslated.join(', ')}',
        );
      });
    }
  });

  group('placeholders', () {
    test('every locale keeps the {amount} / {name} placeholders', () {
      final placeholderKeys = <String, String>{
        'posSaveWithDue': '{amount}',
        'posDiscountOff': '{amount}',
        'posSaleSaved': '{amount}',
        'invItemSaved': '{name}',
      };
      for (final locale in <String>['en', 'hi', 'gu']) {
        final arb = _arb(locale);
        placeholderKeys.forEach((key, token) {
          expect(
            arb[key].toString(),
            contains(token),
            reason: '$locale/$key dropped $token — it would render literally',
          );
        });
      }
    });
  });

  group('runtime delegate', () {
    test('supports exactly the locales we ship', () {
      final supported = kSupportedLocales.map((l) => l.languageCode).toSet();
      expect(supported, <String>{'en', 'hi', 'gu'});
      for (final locale in kSupportedLocales) {
        expect(L.delegate.isSupported(locale), isTrue);
      }
    });

    test('loads each language with real translated values', () async {
      final english = await L.delegate.load(const Locale('en'));
      final hindi = await L.delegate.load(const Locale('hi'));
      final gujarati = await L.delegate.load(const Locale('gu'));

      expect(english.navStock, 'Stock');
      expect(hindi.navStock, isNot('Stock'));
      expect(gujarati.navStock, isNot('Stock'));
      // Sanity: the scripts really are Devanagari / Gujarati.
      expect(hindi.navClients, matches(RegExp(r'[ऀ-ॿ]')));
      expect(gujarati.navClients, matches(RegExp(r'[઀-૿]')));
    });

    test('an unsupported language is not claimed', () {
      expect(L.delegate.isSupported(const Locale('fr')), isFalse);
    });
  });
}
