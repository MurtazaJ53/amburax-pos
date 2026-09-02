import 'package:business_hub_mobile/core/khata/khata_reminder.dart';
import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collection rules decide who a shopkeeper chases for money, so getting them
/// wrong either nags a customer twice in a day or lets a debt go quiet.
KhataDebtor _debtor({
  String name = 'Ayaan',
  String phone = '9876543210',
  double balance = 500,
  DateTime? remindedAt,
}) => KhataDebtor(
  id: 'c1',
  name: name,
  phone: phone,
  balance: balance,
  lastRemindedAt: remindedAt,
);

void main() {
  group('who can be reminded', () {
    test('a customer without a usable mobile cannot be reminded', () {
      expect(_debtor(phone: '').hasPhone, isFalse);
      expect(_debtor(phone: '12345').hasPhone, isFalse);
      expect(_debtor(phone: '9876543210').hasPhone, isTrue);
    });
  });

  group('overdue rules', () {
    test('never reminded counts as overdue', () {
      final d = _debtor();
      expect(d.daysSinceReminder, isNull);
      expect(d.isOverdue, isTrue);
      expect(d.reminderStatus, 'Never reminded');
    });

    test('reminded today is not overdue and is flagged', () {
      final d = _debtor(remindedAt: DateTime.now());
      expect(d.remindedToday, isTrue);
      expect(d.isOverdue, isFalse);
      expect(d.reminderStatus, 'Reminded today');
    });

    test('becomes overdue again after a week', () {
      final six = _debtor(
        remindedAt: DateTime.now().subtract(const Duration(days: 6)),
      );
      final seven = _debtor(
        remindedAt: DateTime.now().subtract(const Duration(days: 7)),
      );
      expect(six.isOverdue, isFalse);
      expect(seven.isOverdue, isTrue);
    });

    test('yesterday reads as yesterday, not "1 days ago"', () {
      final d = _debtor(
        remindedAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
      );
      expect(d.reminderStatus, 'Reminded yesterday');
      expect(d.remindedToday, isFalse);
    });

    test('a reminder late yesterday is not counted as today', () {
      final now = DateTime.now();
      final lateYesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(minutes: 5));
      expect(_debtor(remindedAt: lateYesterday).remindedToday, isFalse);
    });
  });

  group('reminder message', () {
    test('includes the balance and a tappable UPI pay link', () {
      final message = buildKhataReminder(
        shopName: 'T. N',
        customerName: 'Ayaan',
        balance: 1250.5,
        upiVpa: 'shop@okhdfcbank',
      );
      expect(message, contains('Ayaan'));
      expect(message, contains('T. N'));
      expect(message, contains('1250.50'));
      expect(message, contains('upi://pay'));
      // The exact balance must be pre-filled, not left for the customer.
      expect(message, contains('am=1250.50'));
    });

    test('still sends without a UPI id, just without the link', () {
      final message = buildKhataReminder(
        shopName: 'T. N',
        customerName: 'Ayaan',
        balance: 300,
      );
      expect(message, contains('300.00'));
      expect(message, isNot(contains('upi://pay')));
    });

    test('a misconfigured UPI id does not break the reminder', () {
      final message = buildKhataReminder(
        shopName: 'T. N',
        customerName: 'Ayaan',
        balance: 300,
        upiVpa: 'not-a-valid-vpa',
      );
      expect(message, contains('300.00'));
      expect(message, isNot(contains('upi://pay')));
    });

    test('a settled customer gets a thank-you, never a demand', () {
      final message = buildKhataReminder(
        shopName: 'T. N',
        customerName: 'Ayaan',
        balance: 0,
        upiVpa: 'shop@okhdfcbank',
      );
      expect(message, isNot(contains('pending balance')));
      expect(message, isNot(contains('upi://pay')));
      expect(message, contains('thank you'));
    });
  });
}
