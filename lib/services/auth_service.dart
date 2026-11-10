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

  /// App ሲከፈት ቀድሞ የተረጋገጠ ክፍለ-ጊዜ (Verified Session) መኖሩን ያረጋግጣል
  static Future<bool> initSession() async {
    try {
      await ApiService.init();
      final prefs = await SharedPreferences.getInstance();
      final savedDeptId = prefs.getString(_prefDeptKey);
      final savedProfile = prefs.getString(_prefProfileKey);
      final hasToken = ApiService.authToken != null && ApiService.authToken!.isNotEmpty;

      if (hasToken && savedDeptId != null && savedProfile != null) {
        final profile = jsonDecode(savedProfile);
        // ክፍሉን መፈለግ
        for (final dept in Department.allDepartments) {
          if (dept.id == savedDeptId) {
            currentDepartment = dept;
            break;
          }
        }
        currentUserProfile = profile;
        return true; // ቀድሞ የተረጋገጠ ክፍለ-ጊዜ አለ
      }
    } catch (e) {
      debugPrint('AuthService initSession error: $e');
    }
    return false;
  }

  /// የተጠቃሚ መግቢያ (ከአገልጋዩ ጋር ብቻ — ምንም hardcoded bypass የለም!)
  static Future<String?> attemptLogin(Department dept, String password) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      return 'እባክዎ የይለፍ ቃል ያስገቡ።';
    }

    try {
      final res = await ApiService().login(dept.id, trimmed);
      if (res['success'] == true && res['user'] != null) {
        currentDepartment = dept;
        currentUserProfile = res['user'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefDeptKey, dept.id);
        await prefs.setString(_prefProfileKey, jsonEncode(currentUserProfile));
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
    try {
      await ApiService.logout();
    } catch (_) {}

    currentDepartment = null;
    currentUserProfile = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefDeptKey);
      await prefs.remove(_prefProfileKey);
      await prefs.remove('atsede_chat_cache');
    } catch (_) {}
  }
}
