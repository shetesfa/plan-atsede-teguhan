import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// የአጸደ ትጉሃን ከመስመር ውጭ ማስተዳደሪያ እና ማመሳከሪያ አገልግሎት (Offline-First Sync & Cache Manager)
class OfflineSyncService {
  static const String _prefPendingQueueKey = 'atsede_pending_sync_queue';
  static const String _prefPlansCachePrefix = 'atsede_cached_plans_';
  static const String _prefReportsCachePrefix = 'atsede_cached_reports_';
  static const String _prefLastSyncTimeKey = 'atsede_last_sync_timestamp';

  /// 1. እቅዶችን ለክፍሉ ብቻ በአካባቢው ካሽ ማድረግ (Durable Local Cache per Department)
  static Future<void> cachePlans(String deptId, List<Map<String, dynamic>> plans) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefPlansCachePrefix$deptId';
      await prefs.setString(key, jsonEncode(plans));
      await prefs.setString(_prefLastSyncTimeKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('cachePlans error: $e');
    }
  }

  /// 2. በአካባቢው የተቀመጡ እቅዶችን ማምጣት (Get Cached Plans)
  static Future<List<Map<String, dynamic>>> getCachedPlans(String deptId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefPlansCachePrefix$deptId';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (e) {
      debugPrint('getCachedPlans error: $e');
    }
    return [];
  }

  /// 3. ከመስመር ውጭ የተሰራ ለውጥን በወረፋ መመዝገብ (Enqueue Pending Change)
  static Future<void> enqueueChange({
    required String entityType, // 'plan', 'report', 'chat'
    required String action,     // 'insert', 'update', 'delete'
    required Map<String, dynamic> data,
    required String departmentId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefPendingQueueKey);
      List<dynamic> queue = [];
      if (raw != null && raw.isNotEmpty) {
        queue = jsonDecode(raw);
      }

      final syncId = 'sync_${DateTime.now().millisecondsSinceEpoch}_${queue.length + 1}';
      final item = {
        'sync_id': syncId,
        'entity_type': entityType,
        'action': action,
        'department_id': departmentId,
        'payload': data,
        'created_at': DateTime.now().toIso8601String(),
        'version': data['version'] ?? 1,
      };

      queue.add(item);
      await prefs.setString(_prefPendingQueueKey, jsonEncode(queue));
    } catch (e) {
      debugPrint('enqueueChange error: $e');
    }
  }

  /// 4. ያልተመሳከሩ ወረፋዎችን ማምጣት (Get Pending Changes)
  static Future<List<Map<String, dynamic>>> getPendingQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefPendingQueueKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (e) {
      debugPrint('getPendingQueue error: $e');
    }
    return [];
  }

  /// 5. አውታረ-መረብ ሲገኝ ወረፋውን ከአገልጋዩ ጋር ማመሳከር (Process & Flush Sync Queue)
  static Future<Map<String, dynamic>> syncPendingQueue(String deviceId) async {
    final queue = await getPendingQueue();
    if (queue.isEmpty) {
      return {'processed': 0, 'status': 'no_pending'};
    }

    try {
      final result = await ApiService().syncOfflineQueue(queue, deviceId);
      if (result['success'] == true) {
        // በስኬት ከተመሳከረ ወረፋውን ማጽዳት
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefPendingQueueKey);
        await prefs.setString(_prefLastSyncTimeKey, DateTime.now().toIso8601String());
        return {'processed': queue.length, 'status': 'success', 'details': result['data']};
      }
      return {'processed': 0, 'status': 'failed', 'message': result['message']};
    } catch (e) {
      return {'processed': 0, 'status': 'network_error', 'message': e.toString()};
    }
  }

  /// 6. ሎግአውት ሲደረግ ሚስጥራዊ የአካባቢ ካሽን ማጽዳት (Purge Local Cache on Logout)
  static Future<void> purgeUserData(String deptId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefPlansCachePrefix$deptId');
      await prefs.remove('$_prefReportsCachePrefix$deptId');
      await prefs.remove(_prefPendingQueueKey);
    } catch (e) {
      debugPrint('purgeUserData error: $e');
    }
  }
}
