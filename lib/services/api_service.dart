import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// የአገልጋይ ጥሪ ሲወድቅ የሚጣል ስህተት — ከ "እቅድ የለም" (ባዶ ዝርዝር) ጋር
/// እንዳይደባለቅ ይጠቅማል። ይሄን የሚጠቀምበት UI "server አልተገኘም" ብሎ መለየት
/// ይችላል (M10)።
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() =>
      'ApiException${statusCode != null ? ' (HTTP $statusCode)' : ''}: $message';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // ── የአገልጋይ አድራሻ (Base URL) ──────────────────────────────────────────
  // ማስታወሻ (2026-11-14)፦ በ Render ላይ ያለው የ Python bot አገልግሎት
  // (plan-atsede-teguhan.onrender.com) የ Tesfa ነባር አገልግሎት ነው፤ ግን የ PHP API
  // (+ MySQL) ገና በየትም ቦታ አልተጫነም። ከታች ያለው _defaultProdUrl ነባሪ እሴት ብቻ
  // ነው — እስኪዘጋጅ ድረስ አፕሉ በ release mode ከ PHP API ጋር መገናኘት አይችልም።
  // PHP API በ 42web ላይ ሲጫን የአገልጋዩን አድራሻ በሚከተለው መንገድ ያስቀምጡ፦
  //   1) --dart-define API_BASE_URL=https://<የ42web ዶሜይን>/api, ወይም
  //   2) ApiService.baseUrl = 'https://<የ42web ዶሜይን>/api' (static setter —
  //      በ login screen ላይ ሊቀየር ይችላል)።
  // ቅደም ተከተል፦ setter/የተቀመጠ እሴት > --dart-define > ነባሪ።
  static const String _defaultProdUrl = 'https://plan-atsede-teguhan.onrender.com/api';

  /// በ --dart-define API_BASE_URL የሚሰጥ የአገልጋይ አድራሻ (build ጊዜ override)።
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Debug (M1)፦ 127.0.0.1 በእውነተኛ Android ስልክ ላይ አይሰራም፤ በ Android
  // emulator ላይ የ host PC አድራሻ 10.0.2.2 ነው፤ በሌሎች platform (iOS
  // simulator / desktop / web) 127.0.0.1 ይሰራል። በእውነተኛ ስልክ ላይ debug
  // ለማድረግ የ PCውን LAN IP መጠቀም ያስፈልጋል — ለምሳሌ
  // --dart-define API_BASE_URL=http://192.168.x.x:8000/api።
  static const String _defaultDevUrl = 'http://127.0.0.1:8000/api';
  static const String _defaultDevUrlAndroidEmulator = 'http://10.0.2.2:8000/api';

  static String get _defaultDebugUrl {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _defaultDevUrlAndroidEmulator;
    }
    return _defaultDevUrl;
  }

  static String? _customBaseUrl;

  /// ተለዋዋጭ እና አስተማማኝ የአገልጋይ አድራሻ (Effective Base URL)
  static String get baseUrl {
    // በድር (Web) ላይ በ localhost ወይም 127.0.0.1 ሲከፈት ሁልጊዜ ወደ አካባቢው አገልጋይ ማመልከት
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
        return _defaultDevUrl;
      }
    }
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }
    return kReleaseMode ? _defaultProdUrl : _defaultDebugUrl;
  }

  static set baseUrl(String value) {
    _customBaseUrl = value;
  }

  static const String _prefApiBaseKey = 'atsede_api_base_url';
  static const String _prefTokenKey = 'atsede_auth_token';
  static const String _prefUserDataKey = 'atsede_user_data';

  // ደህንነቱ የተጠበቀ የፕላትፎርም ማስቀመጫ (Platform Secure Storage)
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static String? authToken;
  static Map<String, dynamic>? currentUser;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // በአካባቢው Web ላይ ካልሆነ ብቻ የተቀመጠውን base URL ማንበብ
      if (!kIsWeb || (Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1')) {
        final savedBase = prefs.getString(_prefApiBaseKey);
        if (savedBase != null && savedBase.isNotEmpty) {
          final parsed = Uri.tryParse(savedBase);
          if (parsed != null && (parsed.isScheme('https') || (!kReleaseMode && parsed.isScheme('http')))) {
            _customBaseUrl = savedBase;
          }
        }
      }

      // 1. መጀመሪያ ቶከኑን ከ Secure Storage ማንበብ
      authToken = await _secureStorage.read(key: _prefTokenKey);

      // 2. በ SharedPreferences ውስጥ የቆየ ቶከን ካለ ወደ Secure Storage ማዛወር (Migration)
      if (authToken == null || authToken!.isEmpty) {
        final legacyToken = prefs.getString(_prefTokenKey);
        if (legacyToken != null && legacyToken.isNotEmpty) {
          authToken = legacyToken;
          await _secureStorage.write(key: _prefTokenKey, value: legacyToken);
          await prefs.remove(_prefTokenKey); // ከ SharedPreferences ማጽዳት
        }
      }

      final savedUser = prefs.getString(_prefUserDataKey);
      if (savedUser != null) {
        currentUser = jsonDecode(savedUser);
      }
    } catch (e) {
      debugPrint('ApiService init error: $e');
    }
  }

  static Future<void> setBaseUrl(String newUrl) async {
    final parsed = Uri.tryParse(newUrl.trim());
    if (parsed != null && (parsed.isScheme('https') || (!kReleaseMode && parsed.isScheme('http')))) {
      baseUrl = newUrl.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefApiBaseKey, baseUrl);
    }
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

  // 1. መግቢያ (Login — የይለፍ ቃል ሳያጥር ትክክለኛውን ብቻ መላክ)
  Future<Map<String, dynamic>> login(String usernameOrDept, String password) async {
    final url = Uri.parse('$baseUrl/auth.php?action=login');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'username': usernameOrDept.trim(),
          'department_id': usernameOrDept.trim(),
          'password': password, // Never trim password!
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        final token = data['data']['token'];
        final user = data['data']['user'];
        authToken = token;
        currentUser = user;

        // ቶከኑን በ Secure Storage ብቻ ማስቀመጥ (Never in SharedPreferences)
        await _secureStorage.write(key: _prefTokenKey, value: token);

        final prefs = await SharedPreferences.getInstance();
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
      await _secureStorage.delete(key: _prefTokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefUserDataKey);
    } catch (_) {}
  }

  /// የአሁኑን የተጠቃሚ መረጃ ከአገልጋዩ ማረጋገጥ (Get Live Current User Profile)
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final uri = Uri.parse('$baseUrl/auth.php?action=me');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['user'] != null && data['user'] is Map) {
          final user = Map<String, dynamic>.from(data['user']);
          currentUser = user;
          return user;
        }
      }
    } catch (_) {}
    return null;
  }

  // 2. እቅዶችን ማምጣት (Get Plans)
  // M10፦ የአገልጋይ ስህተት ከ "እቅድ የለም" እንዳይደባለቅ፦
  //  • fetchPlans() — ስህተት ሲኖር ApiException ይጥላል (UI "server አልተገኘም" ማለት ይችላል)።
  //  • getPlans() — ለኋላ ተኳሃኝነት [] ይመልሳል፣ ግን ስህተቱን በ lastError ላይ ይመዘግባል።
  //  • lastError — የመጨረሻው የ getPlans()/fetchPlans() ጥሪ ስህተት፤ null ማለት
  //    ስኬታማ ወይም ገና አልተጠራም ማለት ነው።
  String? lastError;

  /// እቅዶችን ከአገልጋዩ ማምጣት — network/HTTP/JSON ስህተት ሲኖር ApiException ይጥላል።
  Future<List<Map<String, dynamic>>> fetchPlans({String? dept, String? status, String? search}) async {
    final queryParams = <String, String>{};
    if (dept != null && dept.isNotEmpty && dept != 'all') queryParams['dept'] = dept;
    if (status != null && status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final uri = Uri.parse('$baseUrl/plans.php').replace(queryParameters: queryParams);
    http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
    } catch (e) {
      lastError = 'የአገልጋይ ግንኙነት አልተሳካም፦ $e';
      debugPrint('fetchPlans network error: $e');
      throw ApiException(lastError!);
    }
    if (res.statusCode != 200) {
      lastError = 'አገልጋዩ ስህተት መልሷል (HTTP ${res.statusCode})';
      throw ApiException(lastError!, res.statusCode);
    }
    try {
      final data = jsonDecode(res.body);
      if (data['status'] == 'success' && data['data'] is List) {
        lastError = null;
        return List<Map<String, dynamic>>.from(data['data']);
      }
      lastError = data['message']?.toString() ?? 'አገልጋዩ ያልተጠበቀ መልስ ሰጥቷል';
      throw ApiException(lastError!, res.statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      lastError = 'የአገልጋዩን መልስ ማንበብ አልተቻለም፦ $e';
      throw ApiException(lastError!);
    }
  }

  /// ለኋላ ተኳሃኝነት፦ ስህተት ሲኖር [] ይመልሳል እና ስህተቱን በ [lastError] ላይ ይመዘግባል።
  Future<List<Map<String, dynamic>>> getPlans({String? dept, String? status, String? search}) async {
    try {
      return await fetchPlans(dept: dept, status: status, search: search);
    } on ApiException catch (e) {
      debugPrint('getPlans failed: $e');
      return [];
    }
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
      // ማስታወሻ፦ አዲስ እቅድ ሲፈጠር plans.php 201 ይመልሳል (200 አይደለም)።
      if ((res.statusCode == 200 || res.statusCode == 201) && data['status'] == 'success') {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'እቅዱን ማስቀመጥ አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }

  // 3b. ሰነድ ወደ ሰነዶች ማህደር ማስቀመጥ (Save Document — M12)
  // ሰነዶች ወደ documents.php ይላካሉ እንጂ ወደ plans.php አይደሉም። auth token
  // በ _headers ውስጥ በ Bearer ይላካል።
  Future<Map<String, dynamic>> saveDocument(Map<String, dynamic> documentData) async {
    final url = Uri.parse('$baseUrl/documents.php');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(documentData),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      // ማስታወሻ፦ አዲስ ሰነድ ሲፈጠር documents.php 201 ይመልሳል (200 አይደለም)።
      if ((res.statusCode == 200 || res.statusCode == 201) && data['status'] == 'success') {
        final saved = data['data'] is Map ? Map<String, dynamic>.from(data['data']) : <String, dynamic>{};
        return {'success': true, 'data': saved, 'id': saved['id']};
      }
      return {'success': false, 'message': data['message'] ?? 'ሰነዱን ማስቀመጥ አልተቻለም'};
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
      if ((res.statusCode == 200 || res.statusCode == 201) && data['status'] == 'success') {
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

  // 13. የይለፍ ቃል መቀየር (Change Password)
  Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) async {
    final url = Uri.parse('$baseUrl/auth.php?action=change_password');
    try {
      final res = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['status'] == 'success') {
        return {'success': true, 'message': data['data']['message'] ?? 'የይለፍ ቃል ተቀይሯል'};
      }
      return {'success': false, 'message': data['message'] ?? 'የይለፍ ቃል መቀየር አልተቻለም'};
    } catch (e) {
      return {'success': false, 'message': 'የአውታረ-መረብ ስህተት፦ $e'};
    }
  }
}
