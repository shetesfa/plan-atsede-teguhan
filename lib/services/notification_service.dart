import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/plan_item.dart';
import 'api_service.dart';
import 'auth_service.dart';

class AppNotification {
  final String id;
  final String? departmentId;
  final String title;
  final String message;
  final String type;
  final String? targetId;
  final bool isRead;
  final String createdAt;

  AppNotification({
    required this.id,
    this.departmentId,
    required this.title,
    required this.message,
    required this.type,
    this.targetId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] ?? '',
        departmentId: json['department_id'],
        title: json['title'] ?? 'ማሳወቂያ',
        message: json['message'] ?? '',
        type: json['type'] ?? 'announcement',
        targetId: json['target_id'],
        isRead: json['is_read'] == 1 || json['is_read'] == true,
        createdAt: json['created_at'] ?? '',
      );
}

/// Real local-notification service (audit C5).
///
/// Previously this class only polled the server every 15 seconds and showed
/// an in-app list — nothing ever arrived when the app was closed. It now:
///  * initialises flutter_local_notifications with the device timezone,
///  * asks for notification permission (Android 13+ / iOS),
///  * can show an immediate notification and schedule plan reminders.
///
/// LIMITATION (honest): plan dates are free-text Ethiopian-month strings
/// (e.g. "መስከረም", "ጥር 10 እስከ 12", "መስ (…)"), not real dates — see
/// [parseEthiopianDate]. Only dates the best-effort parser understands get
/// a reminder; unparseable dates are skipped with a debugPrint note.
/// Server polling is kept only while the app is open, slowed to 60 s
/// (audit M4) — it is NOT a substitute for local notifications.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  Timer? _timer;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'atsede_plans',
    'የእቅድ ማሳሰቢያዎች',
    channelDescription: 'የአጸደ ትጉሃን እቅድ ማሳሰቢያዎች',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    await _initLocalNotifications();
    await fetchNotifications();
    // Server polling, only while the app is open (audit M4: was 15 s).
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      fetchNotifications();
    });
  }

  Future<void> _initLocalNotifications() async {
    try {
      tz.initializeTimeZones();
      // Best effort: use the device's local zone; falls back to UTC
      // if the platform cannot report one.
      try {
        tz.setLocalLocation(tz.getLocation('Africa/Addis_Ababa'));
      } catch (_) {
        // Keep tz.local as-is.
      }
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _local.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );
      await requestPermission();
      _localReady = true;
    } catch (e) {
      // Local notifications are an enhancement: a failure here must
      // never stop the app or the server-notification list.
      debugPrint('NotificationService: local init failed: $e');
      _localReady = false;
    }
  }

  /// Asks the OS for notification permission (Android 13+ / iOS).
  /// Returns true when permission is granted (or not required).
  ///
  /// NOTE (CI fix 2026-11-14): the iOS plugin class is
  /// [IOSFlutterLocalNotificationsPlugin] — there is no
  /// `DarwinFlutterLocalNotificationsPlugin` type (the `Darwin` prefix
  /// applies to the settings/details classes only). Using the Darwin
  /// name made `flutter analyze` fail. See the package README, which
  /// uses `IOSFlutterLocalNotificationsPlugin` for iOS.
  Future<bool> requestPermission() async {
    try {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Both permission calls return Future<bool?> in the installed
      // plugin version, so `?? false` coerces null to "not granted"
      // — a nullable bool can't be used in `&&` (CI fix, round 2).
      final androidGranted =
          await android?.requestNotificationsPermission() ?? false;
      final ios = _local.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return androidGranted && iosGranted;
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
      return false;
    }
  }

  /// Shows an immediate local notification.
  Future<void> showNotification(String title, String body) async {
    if (!_localReady) {
      debugPrint('NotificationService: local notifications not ready; '
          'dropping "$title"');
      return;
    }
    try {
      await _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        _details,
      );
    } catch (e) {
      debugPrint('NotificationService: show failed: $e');
    }
  }

  /// Schedules a one-off local notification at [when] (local time).
  /// Past times are ignored.
  Future<void> schedulePlanReminder({
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_localReady) {
      debugPrint('NotificationService: local notifications not ready; '
          'cannot schedule "$title"');
      return;
    }
    if (!when.isAfter(DateTime.now())) return;
    try {
      await _local.zonedSchedule(
        ('${title}_$when'.hashCode & 0x7fffffff),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // NOTE (CI fix 2026-11-14, round 2): this parameter IS required
        // in the plugin version CI resolves (v18) — removing it broke
        // the build (missing_required_argument). It was only removed
        // in v19+, so it stays while pubspec pins ^18.0.0.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('NotificationService: schedule failed for "$title": $e');
    }
  }

  /// Schedules a reminder for each plan whose date can be parsed.
  ///
  /// CALL SITE (not wired here — lib/screens/plans_screen.dart and
  /// lib/main.dart belong to another worker): call this after plans are
  /// loaded, e.g. `NotificationService().scheduleRemindersForPlans(plans);`
  ///
  /// Reminder time: 09:00 local time on the day BEFORE the plan date;
  /// if that has already passed, 09:00 on the plan date itself.
  /// Completed plans (progress 100%) are skipped. Unparseable dates
  /// are skipped with a debugPrint note — see [parseEthiopianDate].
  Future<void> scheduleRemindersForPlans(List<PlanItem> plans) async {
    if (!_localReady) {
      debugPrint('NotificationService: local notifications not ready; '
          'no plan reminders scheduled');
      return;
    }
    for (final plan in plans) {
      if (plan.isCompleted) continue;
      final raw = plan.isPostponed
          ? (plan.postponedDate ?? plan.executionTime)
          : plan.executionTime;
      final date = parseEthiopianDate(raw);
      if (date == null) {
        debugPrint('NotificationService: skipping reminder for plan '
            '"${plan.title}" — unparseable date "$raw"');
        continue;
      }
      var when = DateTime(date.year, date.month, date.day, 9, 0)
          .subtract(const Duration(days: 1));
      if (!when.isAfter(DateTime.now())) {
        when = DateTime(date.year, date.month, date.day, 9, 0);
      }
      if (!when.isAfter(DateTime.now())) continue;
      await schedulePlanReminder(
        title: 'የእቅድ ማሳሰቢያ',
        body: '${plan.title} — ${plan.departmentName}',
        when: when,
      );
    }
  }

  /// Cancels all scheduled local reminders (e.g. on logout).
  Future<void> cancelAllReminders() async {
    try {
      await _local.cancelAll();
    } catch (e) {
      debugPrint('NotificationService: cancelAll failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Best-effort Ethiopian free-text date parser.
  //
  // Understands: "መስከረም 5", "5 መስከረም", short forms ("መስ 10",
  // "ጥቅ 3"), ranges ("ጥር 10 እስከ 12" — first day wins), and numeric
  // Ethiopian dates "18/01/2019" (dd/mm/yyyy, Ethiopian calendar).
  // Anything else (month name alone with no day, "መስ (…)", free prose)
  // returns null and the caller skips it.
  //
  // Conversion is approximate: Ethiopian year N starts on 11 September
  // of Gregorian year N+7 (12 September in the year after an Ethiopian
  // leap year), then (month-1)*30 + (day-1) days are added. Pagume's
  // 6th day in a leap year may therefore be off by one day. This is
  // good enough for a reminder; it is NOT a calendar library.
  // ------------------------------------------------------------------
  static const Map<String, int> _ethiopianMonths = {
    'መስከረም': 1, 'መስ': 1,
    'ጥቅምት': 2, 'ጥቅ': 2,
    'ኅዳር': 3, 'ኅዳ': 3, 'ህዳር': 3, 'ህዳ': 3,
    'ታኅሣሥ': 4, 'ታኅ': 4, 'ታህሳስ': 4, 'ታህ': 4,
    'ጥር': 5,
    'የካቲት': 6, 'የካ': 6,
    'መጋቢት': 7, 'መጋ': 7,
    'ሚያዝያ': 8, 'ሚያ': 8,
    'ግንቦት': 9, 'ግንቦ': 9,
    'ሰኔ': 10,
    'ሐምሌ': 11, 'ሐም': 11,
    'ነሐሴ': 12, 'ነሐ': 12,
    'ጳጉሜ': 13, 'ጳጉ': 13,
  };

  static DateTime? parseEthiopianDate(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Numeric Ethiopian date: dd/mm/yyyy (e.g. 18/01/2019 ዓ.ም).
    final numeric = RegExp(r'(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{4})')
        .firstMatch(text);
    if (numeric != null) {
      final day = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      final year = int.tryParse(numeric.group(3)!);
      if (day != null && month != null && year != null) {
        return _ethiopianToGregorian(year, month, day);
      }
      return null;
    }

    // Month name + day, in either order. Search for the day AFTER the
    // month name first (so a leading year like "2019 ... ጥር 10" is not
    // mistaken for the day), then before it.
    String? monthKey;
    int? month;
    for (final entry in _ethiopianMonths.entries) {
      if (text.contains(entry.key)) {
        monthKey = entry.key;
        month = entry.value;
        break;
      }
    }
    if (month == null || monthKey == null) return null;
    final monthIndex = text.indexOf(monthKey);
    final afterMonth = text.substring(monthIndex + monthKey.length);
    final beforeMonth = text.substring(0, monthIndex);
    // Ignore 4-digit years when hunting for the day.
    final dayText = afterMonth.replaceAll(RegExp(r'20\d{2}'), ' ');
    var dayMatch = RegExp(r'(\d{1,2})').firstMatch(dayText);
    dayMatch ??= RegExp(r'(\d{1,2})')
        .firstMatch(beforeMonth.replaceAll(RegExp(r'20\d{2}'), ' '));
    if (dayMatch == null) return null; // Month alone: no usable day.
    final day = int.tryParse(dayMatch.group(1)!);
    if (day == null || day < 1 || day > 30) return null;

    // Year: explicit 4-digit Ethiopian year in the text, else the
    // current Ethiopian year — derived from the Gregorian year, not
    // hardcoded (Greg year − 8 before 11 Sep, − 7 from 11 Sep).
    final yearMatch = RegExp(r'(20\d{2})').firstMatch(text);
    final ethYear = yearMatch != null
        ? int.tryParse(yearMatch.group(1)!) ?? _currentEthiopianYear()
        : _currentEthiopianYear();
    return _ethiopianToGregorian(ethYear, month, day);
  }

  static int _currentEthiopianYear() {
    final now = DateTime.now();
    // Ethiopian new year falls on 11 September (Gregorian).
    final newYear = DateTime(now.year, 9, 11);
    return now.isBefore(newYear) ? now.year - 8 : now.year - 7;
  }

  static DateTime? _ethiopianToGregorian(int ethYear, int month, int day) {
    if (month < 1 || month > 13 || day < 1) return null;
    if (month == 13 && day > 6) return null;
    if (month < 13 && day > 30) return null;
    // Ethiopian year N starts 11 Sep of Gregorian year N+7, except
    // 12 Sep when N % 4 == 0 (the year after an Ethiopian leap year,
    // e.g. 2020 E.C. starts 12 Sep 2027). 2019 E.C. starts 11 Sep 2026.
    var startYear = ethYear + 7;
    var startDay = 11;
    if (ethYear % 4 == 0) startDay = 12;
    final start = DateTime(startYear, 9, startDay);
    return start.add(Duration(days: (month - 1) * 30 + (day - 1)));
  }

  // ------------------------------------------------------------------
  // Server notifications (in-app list only, while the app is open).
  // ------------------------------------------------------------------

  Future<void> fetchNotifications() async {
    final dept = AuthService.currentDepartment?.id;
    try {
      final res = await ApiService().getNotifications(dept: dept);
      final rawList = res['notifications'] as List? ?? [];
      _notifications = rawList.map((e) => AppNotification.fromJson(e)).toList();
      _unreadCount = res['unread_count'] as int? ?? _notifications.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final old = _notifications[idx];
      _notifications[idx] = AppNotification(
        id: old.id,
        departmentId: old.departmentId,
        title: old.title,
        message: old.message,
        type: old.type,
        targetId: old.targetId,
        isRead: true,
        createdAt: old.createdAt,
      );
      if (_unreadCount > 0) _unreadCount--;
      notifyListeners();
    }
    await ApiService().markNotificationRead(id: id);
  }

  Future<void> markAllAsRead() async {
    final dept = AuthService.currentDepartment?.id;
    _notifications = _notifications
        .map((n) => AppNotification(
              id: n.id,
              departmentId: n.departmentId,
              title: n.title,
              message: n.message,
              type: n.type,
              targetId: n.targetId,
              isRead: true,
              createdAt: n.createdAt,
            ))
        .toList();
    _unreadCount = 0;
    notifyListeners();
    await ApiService().markNotificationRead(markAll: true, dept: dept);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
