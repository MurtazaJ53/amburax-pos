import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/reports/day_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// The daily summary is often the only thing an absent owner reads about their
/// shop, so a wrong or missing figure here is worse than no message at all.
ZReportSnapshot _z({
  int salesCount = 12,
  double gross = 12400,
  double collected = 10300,
  double due = 2100,
  double discount = 0,
  Map<String, double>? tenders,
  DateTime? first,
  DateTime? last,
}) => ZReportSnapshot(
  salesCount: salesCount,
  grossSales: gross,
  discountTotal: discount,
  taxCollected: 0,
  collected: collected,
  due: due,
  tenderBreakdown: tenders ?? <String, double>{'CASH': 7300, 'UPI': 3000},
  firstBillAt: first,
  lastBillAt: last,
);

void main() {
  group('trading day', () {
    test('leads with the shop, date and the money', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(),
      );
      expect(text, contains('T. N'));
      expect(text, contains('04 Aug 2026'));
      expect(text, contains('Bills: 12'));
      expect(text, contains('12,400'));
      expect(text, contains('10,300'));
    });

    test('reports udhaar given today', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(due: 2100),
      );
      expect(text, contains('Udhaar given today'));
      expect(text, contains('2,100'));
    });

    test('omits udhaar and discount lines when there are none', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(due: 0, discount: 0),
      );
      expect(text, isNot(contains('Udhaar given today')));
      expect(text, isNot(contains('Discount given')));
    });

    test('lists payment modes biggest first', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(tenders: <String, double>{'CASH': 1000, 'UPI': 5000, 'CARD': 0}),
      );
      expect(text.indexOf('UPI'), lessThan(text.indexOf('CASH')));
      // A tender with nothing collected is noise on a phone screen.
      expect(text, isNot(contains('CARD')));
    });

    test('surfaces what needs attention', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(),
        lowStockCount: 3,
        outstandingUdhaar: 45000,
      );
      expect(text, contains('Needs attention'));
      expect(text, contains('3 item(s) need restocking'));
      expect(text, contains('45,000'));
    });

    test('shows trading hours in 12-hour time', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(
          first: DateTime(2026, 8, 4, 9, 5),
          last: DateTime(2026, 8, 4, 20, 45),
        ),
      );
      expect(text, contains('9:05am'));
      expect(text, contains('8:45pm'));
    });

    test('midnight and noon are not rendered as 0 o clock', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(
          first: DateTime(2026, 8, 4, 0, 30),
          last: DateTime(2026, 8, 4, 12, 15),
        ),
      );
      expect(text, contains('12:30am'));
      expect(text, contains('12:15pm'));
    });
  });

  group('quiet day', () {
    test('says so plainly instead of printing a wall of zeroes', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(salesCount: 0, gross: 0, collected: 0, due: 0),
      );
      expect(text, contains('No sales recorded today'));
      expect(text, isNot(contains('Bills: 0')));
      expect(text, isNot(contains('Payments')));
    });

    test('still flags outstanding udhaar and low stock', () {
      final text = buildDaySummary(
        shopName: 'T. N',
        date: DateTime(2026, 8, 4),
        z: _z(salesCount: 0, gross: 0, collected: 0, due: 0),
        lowStockCount: 2,
        outstandingUdhaar: 8000,
      );
      expect(text, contains('8,000'));
      expect(text, contains('2 item(s)'));
    });
  });

  test('an unnamed shop still produces a sensible message', () {
    final text = buildDaySummary(
      shopName: '   ',
      date: DateTime(2026, 8, 4),
      z: _z(),
    );
    expect(text, startsWith('*Your shop*'));
  });
}
