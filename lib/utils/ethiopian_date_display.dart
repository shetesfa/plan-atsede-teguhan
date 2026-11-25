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

/// "መስ (10-30), የካ (6-28)" -> "መስከረም 10–30, የካቲት 6–28".
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
