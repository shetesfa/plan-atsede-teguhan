import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/department.dart';
import 'api_service.dart';

class AuthService {
  static Department? currentDepartment;
  static Map<String, dynamic>? currentUserProfile;
  static int failedAttempts = 0;
  static DateTime? lockUntil;

  static const int maxFailedAttempts = 16;
  static const int lockDurationMinutes = 30;

  static bool get isLoggedIn => currentDepartment != null;
  static bool get isSuperAdmin => currentDepartment?.isSuperAdmin ?? (currentUserProfile?['is_super_admin'] == true);

  static const String _prefDeptKey = 'atsede_current_dept_id';
  static const String _prefProfileKey = 'atsede_current_user_profile';

  /// App ሲከፈት የተቀመጠውን ክፍለ-ጊዜ (Session) ያረጋግጣል
  static Future<void> initSession() async {
    try {
      await ApiService.init();
      final prefs = await SharedPreferences.getInstance();
      final savedDeptId = prefs.getString(_prefDeptKey);
      final savedProfile = prefs.getString(_prefProfileKey);

      if (savedDeptId != null && savedDeptId.isNotEmpty) {
        for (final dept in Department.allDepartments) {
          if (dept.id == savedDeptId) {
            currentDepartment = dept;
            break;
          }
        }
      }

      if (savedProfile != null) {
        currentUserProfile = jsonDecode(savedProfile);
      }
    } catch (e) {
      debugPrint('AuthService initSession error: $e');
    }
  }

  static bool get isLocked {
    if (lockUntil == null) return false;
    if (DateTime.now().isAfter(lockUntil!)) {
      lockUntil = null;
      failedAttempts = 0;
      return false;
    }
    return true;
  }

  static int get remainingLockMinutes {
    if (lockUntil == null) return 0;
    final diff = lockUntil!.difference(DateTime.now()).inMinutes;
    return diff > 0 ? diff : 1;
  }

  /// የተጠቃሚ መግቢያ ሙከራ (ከባክኤንድ API ጋር እና ከመስመር ውጭ አማራጭ ጋር)
  static Future<String?> attemptLogin(Department dept, String password) async {
    if (isLocked) {
      return 'ስርዓቱ ተቆልፏል! ቀሪ ጊዜ፡ $remainingLockMinutes ደቂቃ';
    }

    final trimmed = password.trim();

    // 1. መጀመሪያ ከአገልጋዩ (Backend REST API) ጋር መሞከር
    try {
      final res = await ApiService().login(dept.id, trimmed);
      if (res['success'] == true) {
        failedAttempts = 0;
        lockUntil = null;
        currentDepartment = dept;
        currentUserProfile = res['user'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefDeptKey, dept.id);
        if (currentUserProfile != null) {
          await prefs.setString(_prefProfileKey, jsonEncode(currentUserProfile));
        }
        return null; // ስኬታማ
      }
    } catch (_) {
      // አገልጋይ ካልተገኘ ወደ ከመስመር ውጭ አማራጭ (Offline fallback) ያልፋል
    }

    // 2. ከመስመር ውጭ (Offline Fallback) ለተለመዱ አስተዳዳሪዎችና ክፍሎች
    final isOfflineValid = trimmed == '1234' ||
        trimmed == 'admin' ||
        trimmed == '123456' ||
        trimmed == dept.id ||
        trimmed == 'atsede';

    if (isOfflineValid) {
      failedAttempts = 0;
      lockUntil = null;
      currentDepartment = dept;
      currentUserProfile = {
        'id': 1,
        'department_id': dept.id,
        'department_name': dept.name,
        'full_name': '${dept.name} ተወካይ',
        'is_super_admin': dept.isSuperAdmin
      };

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefDeptKey, dept.id);
        await prefs.setString(_prefProfileKey, jsonEncode(currentUserProfile));
      } catch (_) {}

      return null; // ስኬታማ
    } else {
      failedAttempts++;
      if (failedAttempts >= maxFailedAttempts) {
        lockUntil = DateTime.now().add(const Duration(minutes: lockDurationMinutes));
        return 'የይለፍ ቃል 16 ጊዜ ተሳስቷል! ስርዓቱ ለ 30 ደቂቃ ተቆልፏል!';
      }
      final remaining = maxFailedAttempts - failedAttempts;
      return 'የተሳሳተ የይለፍ ቃል! ቀሪ ሙከራዎች፡ $remaining (ነባሪ፡ 1234)';
    }
  }

  static Future<void> logout() async {
    currentDepartment = null;
    currentUserProfile = null;
    failedAttempts = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefDeptKey);
      await prefs.remove(_prefProfileKey);
      await ApiService.logout();
    } catch (_) {}
  }
}
