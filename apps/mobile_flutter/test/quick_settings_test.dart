import 'package:business_hub_mobile/core/i18n/locale_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Quick settings offers exactly the languages the app can actually render.
///
/// The failure this guards against is quiet: a chip offering a language with
/// no translations behind it switches the app to a locale that falls back to
/// English everywhere, and the shopkeeper concludes the feature is broken.
void main() {
  test('every offered language is one the app supports', () {
    // The sheet offers en, hi, gu. Anything it offers must exist in the
    // supported list, or selecting it silently does nothing useful.
    const offered = <String>['en', 'hi', 'gu'];
    final supported = kSupportedLocales.map((l) => l.languageCode).toSet();

    for (final code in offered) {
      expect(
        supported.contains(code),
        isTrue,
        reason: 'Quick settings offers "$code" but the app does not support it',
      );
    }
  });

  test('the app supports no language the sheet hides', () {
    // The other direction: a language added to the app but not to the sheet is
    // unreachable from the one place a shopkeeper looks for it.
    const offered = <String>{'en', 'hi', 'gu'};
    final supported = kSupportedLocales.map((l) => l.languageCode).toSet();

    expect(
      supported.difference(offered),
      isEmpty,
      reason: 'A supported language is missing from quick settings',
    );
  });
}
