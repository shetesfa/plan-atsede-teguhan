/// Display helpers for Ethiopian plan dates (2026-11-25).
///
/// The Excel stores a plan's date as 12 month columns, and the server
/// stores them as text like "መስ (10-30), የካ (6-28)" — short month
/// names that are hard to read at a glance. The plan table/cards show
/// the expanded form instead: "መስከረም 10–30, የካቲት 6–28".
/// The due date itself comes from the server as `due_date_ethiopian`
/// (e.g. "የካቲት 28, 2019") — see PlanItem.dueDateEthiopian.

const Map<String, String> _fullMonthNames = {
  'መስ': 'መስከረም',
  'ጥቅ': 'ጥቅምት',
  'ህዳር': 'ህዳር',
  'ታህ': 'ታህሳስ',
  'ጥር': 'ጥር',
  'የካ': 'የካቲት',
  'መጋ': 'መጋቢት',
  'ሚያ': 'ሚያዝያ',
  'ግን': 'ግንቦት',
  'ሰኔ': 'ሰኔ',
  'ሐም': 'ሐምሌ',
  'ነሐ': 'ነሐሴ',
};

/// The 13 Ethiopian months, full names (ጳጉሜ included — a plan can
/// be due in Pagume, e.g. "ነሐ (10), ጳጉሜ (3)").
const List<String> ethiopianMonths13 = [
  'መስከረም', 'ጥቅምት', 'ህዳር', 'ታህሳስ', 'ጥር', 'የካቲት',
  'መጋቢት', 'ሚያዝያ', 'ግንቦት', 'ሰኔ', 'ሐምሌ', 'ነሐሴ', 'ጳጉሜ',
];

/// Gregorian date -> Ethiopian (year, month index 0-12, day).
/// Port of api/ethiopian_date.php gregorianToEthiopian: the Ethiopian
/// new year falls on Sep 11 (Sep 12 when the Ethiopian year is a leap
/// year, ethYear % 4 == 0); months are 30 days, Pagume is the 13th.
({int year, int monthIndex, int day}) ethiopianDateParts(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  var ethYear = d.year - 7;
  var start = DateTime(d.year, 9, (ethYear % 4 == 0) ? 12 : 11);
  if (d.isBefore(start)) {
    ethYear -= 1;
    start = DateTime(d.year - 1, 9, ((d.year - 8) % 4 == 0) ? 12 : 11);
  }
  final days = d.difference(start).inDays;
  return (
    year: ethYear,
    monthIndex: (days ~/ 30).clamp(0, 12),
    day: (days % 30) + 1,
  );
}

/// A Gregorian date as an Ethiopian date string, e.g. "ህዳር 16, 2019".
String formatEthiopianDate(DateTime date) {
  final p = ethiopianDateParts(date);
  return '${ethiopianMonths13[p.monthIndex]} ${p.day}, ${p.year}';
}

/// Today's date in Ethiopian, e.g. "ህዳር 16, 2019".
String formatEthiopianToday() => formatEthiopianDate(DateTime.now());

/// The current Ethiopian year (2019 until Sep 10, 2027).
int currentEthiopianYear() => ethiopianDateParts(DateTime.now()).year;

/// A server timestamp ("2026-11-25 12:35:38", Gregorian) -> Ethiopian
/// date string. Used for report dates, which must show the Ethiopian
/// calendar — never the raw Gregorian date.
String formatGregorianDateStringEthiopian(String value) {
  final first = value.trim().split(RegExp(r'\s+')).first;
  final parsed = DateTime.tryParse(first);
  if (parsed == null) return first;
  return formatEthiopianDate(parsed);
}

/// Gregorian date -> Ethiopian month index (0 = መስከረም … 12 = ጳጉሜ).
/// Port of api/ethiopian_date.php gregorianToEthiopian: the Ethiopian
/// new year falls on Sep 11 (Sep 12 when the Ethiopian year is a leap
/// year, ethYear % 4 == 0); months are 30 days, Pagume is the 13th.
int ethiopianMonthIndexOfDate(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final ethYear = d.year - 7;
  final newYearDay = (ethYear % 4 == 0) ? 12 : 11;
  var start = DateTime(d.year, 9, newYearDay);
  if (d.isBefore(start)) {
    start = DateTime(d.year - 1, 9, ((d.year - 8) % 4 == 0) ? 12 : 11);
  }
  final days = d.difference(start).inDays;
  return (days ~/ 30).clamp(0, 12);
}

/// Index (0-12) of the current Ethiopian month, for defaulting a
/// month filter to the month we are in.
int currentEthiopianMonthIndex() =>
    ethiopianMonthIndexOfDate(DateTime.now());

/// The Ethiopian month name a plan is DUE in, for the month filter.
/// Prefers the server's `due_date_ethiopian` ("የካቲት 28, 2019" — the
/// first word is the month); falls back to converting `dueDate`.
/// Returns null when the plan has no real due date.
String? dueEthiopianMonthName({String? dueDateEthiopian, DateTime? dueDate}) {
  if (dueDateEthiopian != null && dueDateEthiopian.trim().isNotEmpty) {
    final first = dueDateEthiopian.trim().split(RegExp(r'\s+')).first;
    if (ethiopianMonths13.contains(first)) return first;
  }
  if (dueDate != null) {
    return ethiopianMonths13[ethiopianMonthIndexOfDate(dueDate)];
  }
  return null;
}
/// Gregorian (year, month, day) as a YYYY-MM-DD string for the API
/// (`occurrence_date`).
String formatGregorianDateYmd(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Ethiopian (year, month 1-13, day) -> Gregorian date.
/// Inverse of [ethiopianDateParts]: Ethiopian year N starts on 11 Sep
/// of Gregorian year N+7 (12 Sep when N % 4 == 0).
DateTime ethiopianToGregorianDate(int ethYear, int month, int day) {
  final start = DateTime(ethYear + 7, 9, (ethYear % 4 == 0) ? 12 : 11);
  return start.add(Duration(days: (month - 1) * 30 + (day - 1)));
}

/// Short Ethiopian month names, 12 months (no Pagume — the calendar
/// shows 12 months).
const List<String> ethiopianShortMonths12 = [
  'መስ', 'ጥቅ', 'ህዳር', 'ታህ', 'ጥር', 'የካ',
  'መጋ', 'ሚያ', 'ግን', 'ሰኔ', 'ሐም', 'ነሐ',
];

/// The Gregorian date of a plan's occurrence in one Ethiopian month
/// (monthIndex 0 = መስከረም … 11 = ነሐሴ), in the current Ethiopian year.
///
/// Reads the plan's months map (e.g. {'ጥቅ': '29'}): the LAST day
/// number in the value wins (ranges "10-30" -> 30, lists -> last);
/// no number means the end of that month (day 30). A year-round plan
/// ("ዓመቱን ሙሉ") occurs at the end of every month. Returns null when
/// the plan has no occurrence in that month.
DateTime? occurrenceDateForMonth({
  required Map<String, String> months,
  required int monthIndex,
  String? executionTime,
}) {
  if (monthIndex < 0 || monthIndex > 11) return null;
  final shortName = ethiopianShortMonths12[monthIndex];
  final value = (months[shortName] ?? '').trim();
  final isYearRound = (executionTime ?? '').contains('ዓመቱን ሙሉ');
  if ((value.isEmpty || value == '-') && !isYearRound) return null;
  var day = 30;
  final nums = RegExp(r'(\d{1,2})')
      .allMatches(value)
      .map((m) => int.tryParse(m.group(1)!))
      .whereType<int>()
      .toList();
  if (nums.isNotEmpty) day = nums.last.clamp(1, 30);
  return ethiopianToGregorianDate(currentEthiopianYear(), monthIndex + 1, day);
}

/// A value that repeats its own month ("ጥቅ (ጥቅ 5)", "ግን (ግን 1)")
/// is shortened to just the day. "ዓመቱን ሙሉ" and other bare words
/// pass through unchanged.
String readableExecutionTime(String executionTime) {
  final text = executionTime.trim();
  if (text.isEmpty) return text;
  final pattern =
      RegExp(r'(መስ|ጥቅ|ህዳር|ታህ|ጥር|የካ|መጋ|ሚያ|ግን|ሰኔ|ሐም|ነሐ)\s*\(([^)]*)\)');
  return text.replaceAllMapped(pattern, (m) {
    final monthShort = m.group(1)!;
    final full = _fullMonthNames[monthShort] ?? monthShort;
    var value = (m.group(2) ?? '').trim();
    if (value.startsWith(monthShort)) {
      value = value.substring(monthShort.length).trim();
    }
    value = value.replaceAll('-', '–');
    return value.isEmpty ? full : '$full $value';
  });
}
