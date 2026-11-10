import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // በነባሪ የአካባቢው PHP ሰርቨር አድራሻ (ወይም በ Render/Cloud ሊቀየር ይችላል)
  static String baseUrl = 'http://127.0.0.1:8000/api';
  static const String _prefApiBaseKey = 'atsede_api_base_url';
  static const String _prefTokenKey = 'atsede_auth_token';
  static const String _prefUserDataKey = 'atsede_user_data';

  static String? authToken;
  static Map<String, dynamic>? currentUser;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedBase = prefs.getString(_prefApiBaseKey);
      if (savedBase != null && savedBase.isNotEmpty) {
        baseUrl = savedBase;
      }
      authToken = prefs.getString(_prefTokenKey);
      final savedUser = prefs.getString(_prefUserDataKey);
      if (savedUser != null) {
        currentUser = jsonDecode(savedUser);
      }
    } catch (e) {
      debugPrint('ApiService init error: $e');
    }
  }

  static Future<void> setBaseUrl(String newUrl) async {
    baseUrl = newUrl.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiBaseKey, baseUrl);
  }

  static Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  // 1. መግቢያ (Login)
  Future<Map<String, dynamic>> login(String usernameOrDept, String password) async {
    final url = Uri.parse('$baseUrl/auth.php?action=login');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'department_id': usernameOrDept.trim(),
          'password': password.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        final token = data['data']['token'];
        final user = data['data']['user'];
        authToken = token;
        currentUser = user;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefTokenKey, token);
        await prefs.setString(_prefUserDataKey, jsonEncode(user));

        return {'success': true, 'user': user};
      } else {
        return {'success': false, 'message': data['message'] ?? 'የመግቢያ ስህተት'};
      }
    } catch (e) {
      return {'success': false, 'message': 'የአገልጋይ ግንኙነት አልተሳካም፦ $e'};
    }
  }

  static Future<void> logout() async {
    authToken = null;
    currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
      await prefs.remove(_prefUserDataKey);
    } catch (_) {}
  }

  // 2. እቅዶችን ማምጣት (Get Plans)
  Future<List<Map<String, dynamic>>> getPlans({String? dept, String? status, String? search}) async {
    final queryParams = <String, String>{};
    if (dept != null && dept.isNotEmpty && dept != 'all') queryParams['dept'] = dept;
    if (status != null && status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final uri = Uri.parse('$baseUrl/plans.php').replace(queryParameters: queryParams);
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success' && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getPlans network error: $e');
    }
    return [];
  }

  // 3. እቅድ መፍጠር ወይም ማሻሻል (Create or Update Plan)
  Future<Map<String, dynamic>> savePlan(Map<String, dynamic> planData) async {
    final url = Uri.parse('$baseUrl/plans.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(planData),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'እቅዱን ማስቀመጥ አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }

  // 4. እቅድ መሰረዝ (Delete Plan)
  Future<bool> deletePlan(String planId) async {
    final url = Uri.parse('$baseUrl/plans.php?id=$planId');
    try {
      final res = await http.delete(url, headers: _headers).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return res.statusCode == 200 && data['status'] == 'success';
    } catch (e) {
      debugPrint('deletePlan error: $e');
      return false;
    }
  }

  // 5. ሪፖርቶችን ማምጣት (Get Reports)
  Future<List<Map<String, dynamic>>> getReports({String? dept, String? status, String? planId}) async {
    final queryParams = <String, String>{};
    if (dept != null && dept.isNotEmpty && dept != 'all') queryParams['dept'] = dept;
    if (status != null && status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (planId != null && planId.isNotEmpty) queryParams['plan_id'] = planId;

    final uri = Uri.parse('$baseUrl/reports.php').replace(queryParameters: queryParams);
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success' && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getReports error: $e');
    }
    return [];
  }

  // 6. ሪፖርት ማቅረብ (Submit Report)
  Future<Map<String, dynamic>> submitReport(Map<String, dynamic> reportData) async {
    final url = Uri.parse('$baseUrl/reports.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(reportData),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'ሪፖርቱን ማስገባት አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }

  // 7. የፅ/ቤት ግምገማ (Review Report)
  Future<Map<String, dynamic>> reviewReport({
    required String reportId,
    required String action, // approved, revision_requested, rejected, under_review
    String? comment,
    String? reviewerName,
  }) async {
    final url = Uri.parse('$baseUrl/reports.php?action=review');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'report_id': reportId,
          'action': action,
          'comment': comment ?? '',
          'reviewer_name': reviewerName ?? (currentUser?['full_name'] ?? 'ፅ/ቤት'),
        }),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'ግምገማውን መመዝገብ አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }

  // 8. ማሳወቂያዎችን ማምጣት (Get Notifications)
  Future<Map<String, dynamic>> getNotifications({String? dept, bool unreadOnly = false}) async {
    final queryParams = <String, String>{};
    if (dept != null && dept.isNotEmpty && dept != 'all') queryParams['dept'] = dept;
    if (unreadOnly) queryParams['unread_only'] = '1';

    final uri = Uri.parse('$baseUrl/notifications.php').replace(queryParameters: queryParams);
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          return data['data'];
        }
      }
    } catch (e) {
      debugPrint('getNotifications error: $e');
    }
    return {'unread_count': 0, 'notifications': []};
  }

  // 9. ማሳወቂያ የተነበበ ማድረግ (Mark Notification Read)
  Future<bool> markNotificationRead({String? id, bool markAll = false, String? dept}) async {
    final url = Uri.parse('$baseUrl/notifications.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          if (id != null) 'id': id,
          if (markAll) 'mark_all': true,
          if (dept != null) 'department_id': dept,
        }),
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 10. የውስጥ ውይይት መልእክቶች ማምጣት (Get Chat Messages)
  Future<List<Map<String, dynamic>>> getChatMessages(String channel, {String? since}) async {
    final queryParams = {'channel': channel};
    if (since != null) queryParams['since'] = since;

    final uri = Uri.parse('$baseUrl/chat.php').replace(queryParameters: queryParams);
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success' && data['data'] is List) {
          return List<Map<String, dynamic>>.from(data['data']);
        }
      }
    } catch (e) {
      debugPrint('getChatMessages error: $e');
    }
    return [];
  }

  // 11. የውይይት መልእክት መላክ (Send Chat Message)
  Future<Map<String, dynamic>> sendChatMessage(Map<String, dynamic> messageData) async {
    final url = Uri.parse('$baseUrl/chat.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(messageData),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'መልእክቱን መላክ አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }

  // 12. ከመስመር ውጭ የገቡ ለውጦችን ማመሳከር (Sync Offline Queue)
  Future<Map<String, dynamic>> syncOfflineQueue(List<Map<String, dynamic>> changes, String deviceId) async {
    final url = Uri.parse('$baseUrl/sync.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'device_id': deviceId,
          'changes': changes,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'ማመሳከር አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የማመሳከር አውታረ-መረብ ስህተት፦ $e'};
    }
  }
}
