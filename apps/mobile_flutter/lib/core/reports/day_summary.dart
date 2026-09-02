import '../models/mobile_models.dart';
import '../utils/formatters.dart';

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// "04 Aug 2026" — unambiguous for an Indian reader, unlike 04/08 vs 08/04.
String _dayLabel(DateTime date) =>
    '${_two(date.day)} ${_months[date.month - 1]} ${date.year}';

/// 12-hour clock, which is how shop hours are actually spoken.
String _timeLabel(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final suffix = at.hour < 12 ? 'am' : 'pm';
  return '$hour:${_two(at.minute)}$suffix';
}

/// Build the end-of-day WhatsApp summary an owner reads on their phone.
///
/// Written for someone glancing at a notification, not studying a report: the
/// money first, then what still needs attention. Pure + testable so the numbers
/// can be trusted without launching the app.
String buildDaySummary({
  required String shopName,
  required DateTime date,
  required ZReportSnapshot z,
  int lowStockCount = 0,
  double outstandingUdhaar = 0,
}) {
  final shop = shopName.trim().isEmpty ? 'Your shop' : shopName.trim();
  final buffer = StringBuffer()
    ..writeln('*$shop* - ${_dayLabel(date)}')
    ..writeln();

  if (z.salesCount == 0) {
    buffer
      ..writeln('No sales recorded today.')
      ..writeln();
    if (outstandingUdhaar > 0.009) {
      buffer.writeln('Udhaar pending: ${formatCurrency(outstandingUdhaar)}');
    }
    if (lowStockCount > 0) {
      buffer.writeln('$lowStockCount item(s) need restocking.');
    }
    return buffer.toString().trimRight();
  }

  buffer
    ..writeln('Sales: ${formatCurrency(z.grossSales)}')
    ..writeln('Bills: ${z.salesCount}')
    ..writeln('Collected: ${formatCurrency(z.collected)}');

  // Money handed out on credit today is the number owners most want to see.
  if (z.due > 0.009) {
    buffer.writeln('Udhaar given today: ${formatCurrency(z.due)}');
  }
  if (z.discountTotal > 0.009) {
    buffer.writeln('Discount given: ${formatCurrency(z.discountTotal)}');
  }

  final tenders =
      z.tenderBreakdown.entries.where((e) => e.value > 0.009).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  if (tenders.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('*Payments*');
    for (final tender in tenders) {
      buffer.writeln('${tender.key}: ${formatCurrency(tender.value)}');
    }
  }

  final needsAttention = <String>[];
  if (outstandingUdhaar > 0.009) {
    needsAttention.add(
      'Total udhaar pending: ${formatCurrency(outstandingUdhaar)}',
    );
  }
  if (lowStockCount > 0) {
    needsAttention.add('$lowStockCount item(s) need restocking');
  }
  if (needsAttention.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('*Needs attention*');
    for (final line in needsAttention) {
      buffer.writeln(line);
    }
  }

  if (z.firstBillAt != null && z.lastBillAt != null) {
    buffer
      ..writeln()
      ..writeln(
        'First bill ${_timeLabel(z.firstBillAt!)}, '
        'last ${_timeLabel(z.lastBillAt!)}',
      );
  }

  return buffer.toString().trimRight();
}
