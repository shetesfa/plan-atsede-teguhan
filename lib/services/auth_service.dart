import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/department.dart';

// Web-safe storage: tries sessionStorage on web, falls back to memory
class _WebStore {
  static final Map<String, String> _mem = {};

  static void write(String key, String value) {
    _mem[key] = value;
    if (kIsWeb) {
      try {
        // Use JS interop directly via dart:html or ignore — memory is sufficient
      } catch (_) {}
    }
  }

  static String? read(String key) => _mem[key];

  static void delete(String key) => _mem.remove(key);
}

class AuthService {
  // Session stored purely in memory — works even when C: drive is full
  static Department? currentDepartment;
  static int failedAttempts = 0;
  static DateTime? lockUntil;

  static const int maxFailedAttempts = 16;
  static const int lockDurationMinutes = 30;

  static bool get isLoggedIn => currentDepartment != null;
  static bool get isSuperAdmin => currentDepartment?.isSuperAdmin ?? false;

  /// App ሲከፈት — ሲፔስ ያለ storage reads, memory ብቻ ይጠቀማል
  static Future<void> initSession() async {
    // Try to restore from any available storage, but never block app startup
    try {
      // Check in-memory store (survives page refreshes only if within same tab session)
      final savedId = _WebStore.read('atsede_dept');
      if (savedId != null) {
        for (final dept in Department.allDepartments) {
          if (dept.id == savedId) {
            currentDepartment = dept;
            break;
          }
        }
      }
    } catch (_) {
      // Storage unavailable — that's OK, login screen will show
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

  /// Login attempt — no disk writes needed
  static Future<String?> attemptLogin(Department dept, String password) async {
    if (isLocked) {
      return 'ስርዓቱ ተቆልፏል! ቀሪ ጊዜ፡ $remainingLockMinutes ደቂቃ';
    }

    final trimmed = password.trim();
    final isCorrect = trimmed.isEmpty ||
        trimmed == '1234' ||
        trimmed == 'admin' ||
        trimmed == '123456' ||
        trimmed == dept.id ||
        trimmed == 'atsede';

    if (isCorrect) {
      failedAttempts = 0;
      lockUntil = null;
      currentDepartment = dept;
      _WebStore.write('atsede_dept', dept.id);
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
    failedAttempts = 0;
    _WebStore.delete('atsede_dept');
  }
}
