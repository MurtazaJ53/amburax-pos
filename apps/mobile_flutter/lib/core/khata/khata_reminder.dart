import '../pos/upi_qr.dart';

/// Build a friendly WhatsApp khata (credit) reminder. When the customer owes
/// money and a merchant UPI id is configured, it appends a **tappable UPI pay
/// link** pre-filled with the exact balance — so the customer can clear their
/// due in one tap from the message. Pure + testable.
String buildKhataReminder({
  required String shopName,
  required String customerName,
  required double balance,
  String upiVpa = '',
  String note = 'Khata payment',

  /// Absolute URL of the customer's own statement page. Included so they can
  /// check the figure instead of taking it on trust, which is the usual
  /// reason a khata reminder turns into an argument.
  String statementUrl = '',
}) {
  final shop = shopName.trim().isEmpty ? 'our shop' : shopName.trim();
  final name = customerName.trim().isEmpty ? 'there' : customerName.trim();

  if (balance <= 0) {
    return 'Hello $name, thank you for shopping with $shop!';
  }

  final amount = balance.toStringAsFixed(2);
  final buffer = StringBuffer()
    ..write('Hello $name, this is a friendly reminder from $shop. ')
    ..write('Your pending balance is ₹$amount.');

  final vpa = upiVpa.trim();
  if (vpa.isNotEmpty) {
    try {
      final uri = buildUpiUri(
        payeeVpa: vpa,
        payeeName: shop,
        amount: balance,
        note: note,
      );
      buffer.write('\n\nPay instantly on any UPI app:\n$uri');
    } on UpiRequestError {
      // Misconfigured VPA — send the reminder without a pay link.
    }
  }

  final statement = statementUrl.trim();
  if (statement.isNotEmpty) {
    buffer.write('\n\nSee your full khata:\n$statement');
  }

  buffer.write('\n\nThank you!');
  return buffer.toString();
}
