/// Date parsing for imported spreadsheets.
///
/// `DateTime.tryParse` only understands ISO-8601, so every real-world export
/// format ("15/03/2024", "15-Mar-2024", an Excel serial number) came back null
/// and the importer quietly stamped the row with DateTime.now() - silently
/// rewriting a shop's entire trading history to today.
///
/// Day-first is the default for ambiguous "a/b/y" input because this app is
/// India-first, where dd/MM/yyyy is the norm. Unambiguous input still wins:
/// 03/15/2024 is read month-first because 15 cannot be a month.
library;

const List<String> _monthNames = <String>[
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// Excel/Sheets serial dates count days from 1899-12-30 (the offset already
/// absorbs Excel's fictional 1900 leap day).
final DateTime _excelEpoch = DateTime(1899, 12, 30);

/// Serials outside this range are far more likely to be a quantity or an
/// amount that landed in a date column than a real date.
const int _minExcelSerial = 1; // 1899-12-31
const int _maxExcelSerial = 80000; // ~2119

DateTime? _build(
  int year,
  int month,
  int day, [
  int h = 0,
  int m = 0,
  int s = 0,
]) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final dt = DateTime(year, month, day, h, m, s);
  // DateTime rolls overflow forward (Feb 31 -> Mar 3); reject instead of
  // inventing a date the sheet never contained.
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return dt;
}

int _expandYear(int year) {
  if (year >= 100) return year;
  // Two-digit years: 70-99 -> 1970s-90s, 00-69 -> 2000s-2060s.
  return year >= 70 ? 1900 + year : 2000 + year;
}

/// Parses a spreadsheet date cell. Returns null when the value cannot be read
/// as a date, so callers can count and report those rows rather than guessing.
DateTime? parseImportDate(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;

  // 1. Bare numbers: Excel serial, or a unix timestamp.
  //
  // This MUST come before DateTime.tryParse. Dart happily reads a bare digit
  // run as its "basic format" calendar date, so tryParse('1710460800') returns
  // year 171046 instead of March 2024 - a wrong answer is worse than no answer.
  final numeric = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value);
  final asNumber = numeric ? num.tryParse(value) : null;
  if (asNumber != null) {
    // Epoch milliseconds (13 digits) and seconds (10 digits) are well clear of
    // the Excel serial range, so the magnitude tells them apart safely.
    if (asNumber >= 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(asNumber.toInt());
    }
    if (asNumber >= 100000000) {
      return DateTime.fromMillisecondsSinceEpoch(asNumber.toInt() * 1000);
    }
    if (asNumber >= _minExcelSerial && asNumber <= _maxExcelSerial) {
      final whole = asNumber.floor();
      final fraction = asNumber - whole; // time of day
      return _excelEpoch
          .add(Duration(days: whole))
          .add(Duration(milliseconds: (fraction * 86400000).round()));
    }
    return null;
  }
  if (numeric) return null;

  // 2. ISO-8601 and anything else Dart natively understands.
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso;

  // Split off a trailing time component so "15/03/2024 14:30" works.
  var datePart = value;
  var hour = 0, minute = 0, second = 0;
  final timeMatch = RegExp(
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$',
  ).firstMatch(value);
  if (timeMatch != null) {
    hour = int.parse(timeMatch.group(1)!);
    minute = int.parse(timeMatch.group(2)!);
    second = int.tryParse(timeMatch.group(3) ?? '0') ?? 0;
    final meridiem = timeMatch.group(4)?.toLowerCase();
    if (meridiem == 'pm' && hour < 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59 || second > 59) return null;
    datePart = value.substring(0, timeMatch.start).trim();
  }
  if (datePart.isEmpty) return null;

  // 3. Named months: "15 Mar 2024", "Mar 15, 2024", "15-March-2024".
  final named = RegExp(r'^([A-Za-z]+)$');
  final tokens = datePart
      .split(RegExp(r'[\s,\-/.]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length == 3) {
    final monthToken = tokens.firstWhere(
      (t) => named.hasMatch(t),
      orElse: () => '',
    );
    if (monthToken.isNotEmpty) {
      final monthIndex = _monthNames.indexOf(
        monthToken.toLowerCase().substring(0, 3).toString(),
      );
      if (monthIndex < 0) return null;
      final numbers = tokens
          .where((t) => t != monthToken)
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      if (numbers.length != 2) return null;
      // The larger / 4-digit token is the year.
      final year = numbers[0] > 31 || numbers[0] > numbers[1]
          ? numbers[0]
          : numbers[1];
      final day = year == numbers[0] ? numbers[1] : numbers[0];
      return _build(
        _expandYear(year),
        monthIndex + 1,
        day,
        hour,
        minute,
        second,
      );
    }
  }

  // 4. Numeric triples: a/b/c with / - or . separators.
  final parts = datePart
      .split(RegExp(r'[\-/.]'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (parts.length != 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  final a = nums[0]!, b = nums[1]!, c = nums[2]!;

  // yyyy-MM-dd style (4-digit year leading).
  if (parts[0].length == 4) return _build(a, b, c, hour, minute, second);

  final year = _expandYear(c);
  // Disambiguate: a value above 12 can only be the day.
  if (a > 12 && b <= 12) return _build(year, b, a, hour, minute, second);
  if (b > 12 && a <= 12) return _build(year, a, b, hour, minute, second);
  // Genuinely ambiguous - day-first, per the India-first default.
  return _build(year, b, a, hour, minute, second);
}
