import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/department.dart';
import 'api_service.dart';

class AuthService {
  static Department? currentDepartment;
  static Map<String, dynamic>? currentUserProfile;

  static bool get isLoggedIn => currentDepartment != null && currentUserProfile != null;
  static bool get isSuperAdmin => currentUserProfile?['is_super_admin'] == true;

  static const String _prefDeptKey = 'atsede_current_dept_id';
  static const String _prefProfileKey = 'atsede_current_user_profile';
  static const String _prefSessionExpiryKey = 'atsede_session_expiry';

  /// App ሲከፈት ቀድሞ የተረጋገጠ ክፍለ-ጊዜ (Verified Session) መኖሩን እና ጊዜው እንዳላለፈ ያረጋግጣል
  static Future<bool> initSession() async {
    try {
      await ApiService.init();
      final prefs = await SharedPreferences.getInstance();
      final savedDeptId = prefs.getString(_prefDeptKey);
      final savedProfile = prefs.getString(_prefProfileKey);
      final expiryMs = prefs.getInt(_prefSessionExpiryKey) ?? 0;
      final hasToken = ApiService.authToken != null && ApiService.authToken!.isNotEmpty;

      // የክፍለ-ጊዜ ፖሊሲ ፍተሻ (ከ 7 ቀናት በላይ ከሆነ ወይም ጊዜው ካለፈ ውድቅ ማድረግ)
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (expiryMs > 0 && nowMs > expiryMs) {
        await logout();
        return false;
      }

      if (hasToken && savedDeptId != null && savedProfile != null) {
        final profile = jsonDecode(savedProfile);
        for (final dept in Department.allDepartments) {
          if (dept.id == savedDeptId) {
            currentDepartment = dept;
            break;
          }
        }
        currentUserProfile = profile;

        // ኦንላይን ከተገኘ የተጠቃሚውን የቀጥታ ሁኔታ ማረጋገጥ (ዳታቤዝ ላይ ንቁ መሆኑን)
        _validateLiveSessionAsync();

        return true;
      }
    } catch (e) {
      debugPrint('AuthService initSession error: $e');
    }
    return false;
  }

  /// ከአገልጋዩ ጋር በቀጥታ በመገናኘት ተጠቃሚው አሁንም ንቁ መሆኑን ያረጋግጣል
  static void _validateLiveSessionAsync() {
    ApiService().getCurrentUser().then((user) {
      if (user == null) {
        // ተጠቃሚው ተሰርዟል ወይም ታግዷል
        logout();
      } else {
        currentUserProfile = user;
      }
    }).catchError((_) {});
  }

  /// የተጠቃሚ መግቢያ (ከአገልጋዩ ጋር ብቻ — ምንም hardcoded bypass የለም!)
  static Future<String?> attemptLogin(Department dept, String password) async {
    if (password.isEmpty) {
      return 'እባክዎ የይለፍ ቃል ያስገቡ።';
    }

    try {
      final res = await ApiService().login(dept.id, password); // Never trim password!
      if (res['success'] == true && res['user'] != null) {
        currentDepartment = dept;
        currentUserProfile = res['user'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefDeptKey, dept.id);
        await prefs.setString(_prefProfileKey, jsonEncode(currentUserProfile));
        // የ 7 ቀናት የክፍለ-ጊዜ ገደብ መመዝገብ
        final expiryMs = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
        await prefs.setInt(_prefSessionExpiryKey, expiryMs);
        return null; // ስኬታማ መግቢያ
      } else {
        return res['message'] ?? 'የተሳሳተ የተጠቃሚ ስም ወይም የይለፍ ቃል!';
      }
    } catch (e) {
      // አገልጋዩ ካልተገኘ
      return 'ከአገልጋዩ ጋር መገናኘት አልተቻለም። እባክዎ የበይነ-መረብ ወይም የአገልጋዩን ዝግጁነት ያረጋግጡ።';
    }
  }

  /// ደህንነቱ የተጠበቀ መውጫ (Logout — አገልጋይ ላይ ቶከን ማሰናከል እና የአካባቢ ካሽ ማጽዳት)
  static Future<void> logout() async {
    final oldDeptId = currentDepartment?.id;
    try {
      await ApiService.logout();
    } catch (_) {}

    currentDepartment = null;
    currentUserProfile = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefDeptKey);
      await prefs.remove(_prefProfileKey);
      await prefs.remove(_prefSessionExpiryKey);
      await prefs.remove('atsede_chat_cache');
      if (oldDeptId != null) {
        await prefs.remove('atsede_cached_plans_$oldDeptId');
        await prefs.remove('atsede_cached_reports_$oldDeptId');
      }
    } catch (_) {}
  }
}
