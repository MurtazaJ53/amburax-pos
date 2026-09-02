import 'package:business_hub_mobile/features/reports/presentation/day_book_screen.dart';
import 'package:business_hub_mobile/features/settings/presentation/notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two counter-app screens that closed the web-only gap.
///
/// Both are mostly presentation, so only the parts that decide what a
/// shopkeeper actually sees are pinned here: which Jama lines appear, and
/// which alert reaches the top of the feed.
void main() {
  group('jamaLines', () {
    test('drops zero rows and puts the largest first', () {
      // A day book listing every payment method the software supports, most of
      // them at zero, is a form. The paper one lists what actually came in.
      final rows = jamaLines(<String, dynamic>{
        'CASH': '1200.00',
        'UPI': '3400.00',
        'CARD': '0.00',
        'BANK': '0.00',
        'other': '0.00',
        'khata_repayments': '500.00',
        'total': '5100.00',
      });

      expect(rows.map((r) => r.key), <String>['UPI', 'Cash', 'Khata repaid']);
      expect(rows.first.value, 3400.0);
    });

    test('excludes the total, which is the sum and not a line', () {
      final rows = jamaLines(<String, dynamic>{
        'CASH': '100.00',
        'total': '100.00',
      });
      expect(rows, hasLength(1));
      expect(rows.single.key, 'Cash');
    });

    test(
      'shows an unrecognised mode under its own key rather than hiding it',
      () {
        // A payment method added on the server must not silently vanish from the
        // day book, which would make Jama lines stop summing to the total.
        final rows = jamaLines(<String, dynamic>{'WALLET': '50.00'});
        expect(rows.single.key, 'WALLET');
      },
    );

    test('a day with nothing received lists nothing', () {
      expect(
        jamaLines(<String, dynamic>{'CASH': '0.00', 'total': '0.00'}),
        isEmpty,
      );
    });
  });

  group('parseMoney', () {
    test('reads the JSON strings DRF sends for decimals', () {
      expect(parseMoney('1234.50'), 1234.5);
      expect(parseMoney(12), 12.0);
      expect(parseMoney(null), 0);
      expect(parseMoney('n/a'), 0);
    });
  });

  group('sortForReading', () {
    ShopNotification note(
      String id, {
      required bool read,
      required int daysAgo,
    }) => ShopNotification(
      id: id,
      title: id,
      message: '',
      type: 'stock',
      isRead: read,
      createdAt: DateTime(2026, 8, 16).subtract(Duration(days: daysAgo)),
    );

    test('unread comes before read, however old', () {
      // Straight reverse-chronological buries an unread stock warning under a
      // week of read summaries, which is how a feed stops being read.
      final sorted = sortForReading(<ShopNotification>[
        note('read-today', read: true, daysAgo: 0),
        note('unread-old', read: false, daysAgo: 7),
      ]);
      expect(sorted.map((n) => n.id), <String>['unread-old', 'read-today']);
    });

    test('newest first within each group', () {
      final sorted = sortForReading(<ShopNotification>[
        note('unread-old', read: false, daysAgo: 3),
        note('unread-new', read: false, daysAgo: 1),
        note('read-old', read: true, daysAgo: 9),
        note('read-new', read: true, daysAgo: 2),
      ]);
      expect(sorted.map((n) => n.id), <String>[
        'unread-new',
        'unread-old',
        'read-new',
        'read-old',
      ]);
    });

    test('an alert with no timestamp sinks rather than throwing', () {
      final sorted = sortForReading(<ShopNotification>[
        const ShopNotification(
          id: 'undated',
          title: '',
          message: '',
          type: '',
          isRead: false,
          createdAt: null,
        ),
        note('dated', read: false, daysAgo: 5),
      ]);
      expect(sorted.first.id, 'dated');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 8, 16, 12, 0);

    test('reads the way somebody would say it', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 20)), now: now),
        'just now',
      );
      expect(
        relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3 hr ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 1)), now: now),
        'yesterday',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 4)), now: now),
        '4 days ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 15)), now: now),
        '2 wk ago',
      );
    });

    test('a clock skewed into the future reads as just now, not a negative', () {
      // Device clocks drift. "-3 min ago" on an alert would look like a bug in
      // the alert rather than in the clock.
      expect(
        relativeTime(now.add(const Duration(minutes: 3)), now: now),
        'just now',
      );
    });

    test('no timestamp shows nothing rather than a placeholder', () {
      expect(relativeTime(null, now: now), '');
    });
  });
}
