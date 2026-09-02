/// Builds a UPI deep-link / QR payload for collecting a payment.
///
/// Format (NPCI UPI spec):
///   `upi://pay?pa=<vpa>&pn=<name>&am=<amount>&cu=INR&tn=<note>&tr=<ref>`
///
/// Any UPI app (GPay/PhonePe/Paytm/BHIM) scanning the QR pre-fills the merchant
/// VPA and the exact amount, so the cashier never has to ask "did you pay?".
library;

/// Thrown when a UPI request can't be built (e.g. a missing/invalid VPA).
class UpiRequestError implements Exception {
  const UpiRequestError(this.message);
  final String message;
  @override
  String toString() => 'UpiRequestError: $message';
}

final RegExp _vpaPattern = RegExp(r'^[a-zA-Z0-9.\-_]{1,256}@[a-zA-Z]{2,64}$');

/// Format an amount as a UPI-legal 2-decimal string (`am` must be `0.00` style).
String formatUpiAmount(double amount) => amount.toStringAsFixed(2);

/// Build a `upi://pay` URI. Throws [UpiRequestError] for a bad VPA or a
/// non-positive amount.
String buildUpiUri({
  required String payeeVpa,
  required String payeeName,
  required double amount,
  String note = '',
  String? transactionRef,
  String currency = 'INR',
}) {
  final vpa = payeeVpa.trim();
  if (!_vpaPattern.hasMatch(vpa)) {
    throw UpiRequestError('Enter a valid UPI ID (e.g. name@bank).');
  }
  if (amount <= 0) {
    throw UpiRequestError('Amount must be greater than zero.');
  }

  final params = <String, String>{
    'pa': vpa,
    'pn': payeeName.trim().isEmpty ? 'Merchant' : payeeName.trim(),
    'am': formatUpiAmount(amount),
    'cu': currency,
  };
  if (note.trim().isNotEmpty) params['tn'] = note.trim();
  if (transactionRef != null && transactionRef.trim().isNotEmpty) {
    params['tr'] = transactionRef.trim();
  }

  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return 'upi://pay?$query';
}

/// Merchant UPI id configured at build time
/// (`--dart-define BUSINESS_HUB_UPI_VPA=shop@bank`).
const String configuredMerchantVpa = String.fromEnvironment(
  'BUSINESS_HUB_UPI_VPA',
);

/// UPI pay link to print on a receipt, so a customer can clear the bill straight
/// from the paper/PDF. Returns null when nothing is due or no merchant VPA is
/// configured — the receipt then simply omits the QR.
String? receiptUpiUri({
  required String shopName,
  required double amountDue,
  String? vpa,
}) {
  final payee = (vpa ?? configuredMerchantVpa).trim();
  if (payee.isEmpty || amountDue <= 0) return null;
  try {
    return buildUpiUri(
      payeeVpa: payee,
      payeeName: shopName,
      amount: amountDue,
      note: 'Bill payment',
    );
  } on UpiRequestError {
    return null; // misconfigured VPA -> print the receipt without a QR
  }
}
