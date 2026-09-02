import 'package:business_hub_mobile/core/import/date_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseImportDate', () {
    test('reads ISO-8601 unchanged', () {
      expect(parseImportDate('2024-03-15'), DateTime(2024, 3, 15));
      expect(
        parseImportDate('2024-03-15T14:30:00'),
        DateTime(2024, 3, 15, 14, 30),
      );
    });

    test('reads Indian day-first formats', () {
      final expected = DateTime(2024, 3, 15);
      expect(parseImportDate('15/03/2024'), expected);
      expect(parseImportDate('15-03-2024'), expected);
      expect(parseImportDate('15.03.2024'), expected);
      expect(parseImportDate('15/3/2024'), expected);
    });

    test(
      'lets an unambiguous month-first date win over the day-first default',
      () {
        // 15 cannot be a month, so this must be March 15 - not "the 3rd of
        // month 15", and not silently mangled into some other day.
        expect(parseImportDate('03/15/2024'), DateTime(2024, 3, 15));
      },
    );

    test('falls back to day-first only when genuinely ambiguous', () {
      // Both <= 12: India-first means 5 March, not 3 May.
      expect(parseImportDate('05/03/2024'), DateTime(2024, 3, 5));
    });

    test('reads named months in either order', () {
      final expected = DateTime(2024, 3, 15);
      expect(parseImportDate('15 Mar 2024'), expected);
      expect(parseImportDate('15-March-2024'), expected);
      expect(parseImportDate('Mar 15, 2024'), expected);
      expect(parseImportDate('15 MARCH 2024'), expected);
    });

    test('reads Excel serial numbers', () {
      // 45366 is 2024-03-15 in Excel's 1900 date system.
      expect(parseImportDate('45366'), DateTime(2024, 3, 15));
      // Fractional part carries the time of day.
      final noon = parseImportDate('45366.5')!;
      expect(noon.hour, 12);
    });

    test('reads unix timestamps in seconds and milliseconds', () {
      final ms = parseImportDate('1710460800000');
      final s = parseImportDate('1710460800');
      expect(ms, isNotNull);
      expect(s, isNotNull);
      expect(ms!.millisecondsSinceEpoch, s!.millisecondsSinceEpoch);
    });

    test('reads a trailing time component', () {
      expect(
        parseImportDate('15/03/2024 14:30'),
        DateTime(2024, 3, 15, 14, 30),
      );
      expect(
        parseImportDate('15/03/2024 2:30 PM'),
        DateTime(2024, 3, 15, 14, 30),
      );
      expect(
        parseImportDate('15/03/2024 12:15 AM'),
        DateTime(2024, 3, 15, 0, 15),
      );
    });

    test('expands two-digit years', () {
      expect(parseImportDate('15/03/24'), DateTime(2024, 3, 15));
      expect(parseImportDate('15/03/98'), DateTime(1998, 3, 15));
    });

    test('returns null rather than guessing at unreadable input', () {
      // The whole point of the fix: a bad cell must NOT become "today".
      expect(parseImportDate(''), isNull);
      expect(parseImportDate(null), isNull);
      expect(parseImportDate('not a date'), isNull);
      expect(parseImportDate('15/03'), isNull);
      expect(parseImportDate('32/01/2024'), isNull); // no 32nd day
      expect(parseImportDate('15/13/2024'), isNull); // no 13th month
    });

    test('rejects overflow dates instead of rolling them forward', () {
      // DateTime(2024, 2, 31) silently becomes 2 March; that would invent a
      // date the spreadsheet never contained.
      expect(parseImportDate('31/02/2024'), isNull);
    });

    test('ignores a quantity that landed in a date column', () {
      expect(parseImportDate('0'), isNull);
      expect(parseImportDate('-5'), isNull);
      expect(parseImportDate('999999'), isNull);
    });
  });
}
