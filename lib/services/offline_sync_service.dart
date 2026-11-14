import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// የአጸደ ትጉሃን ከመስመር ውጭ ማስተዳደሪያ እና ማመሳከሪያ አገልግሎት (Offline-First Sync & User-Scoped Cache)
class OfflineSyncService {
  static const String _prefPendingQueueKey = 'atsede_pending_sync_queue';
  static const String _prefPlansCachePrefix = 'atsede_cached_plans_';
  static const String _prefReportsCachePrefix = 'atsede_cached_reports_';
  static const String _prefLastSyncTimeKey = 'atsede_last_sync_timestamp';

  /// የተጠቃሚን እና የክፍልን መለያ በማጣመር ደህንነቱ የተጠበቀ የካሽ ቁልፍ ያዘጋጃል (User & Dept Scoped Cache Key)
  static String _buildCacheKey(String prefix, String deptId, [String? explicitUserId]) {
    final userId = explicitUserId ?? AuthService.currentUserProfile?['id']?.toString() ?? 'common';
    return '$prefix${userId}_$deptId';
  }

  /// 1. እቅዶችን ለተጠቃሚውና ለክፍሉ ብቻ በአካባቢው ካሽ ማድረግ (Durable User-Scoped Local Cache)
  static Future<void> cachePlans(String deptId, List<Map<String, dynamic>> plans, {String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildCacheKey(_prefPlansCachePrefix, deptId, userId);
      await prefs.setString(key, jsonEncode(plans));
      await prefs.setString(_prefLastSyncTimeKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('cachePlans error: $e');
    }
  }

  /// 2. በአካባቢው የተቀመጡ እቅዶችን ማምጣት (Get Cached Plans)
  static Future<List<Map<String, dynamic>>> getCachedPlans(String deptId, {String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildCacheKey(_prefPlansCachePrefix, deptId, userId);
      var raw = prefs.getString(key);
      // ለቀድሞ ስሪት ተኳሃኝነት (Fallback to legacy key if user-scoped key is empty)
      if (raw == null || raw.isEmpty) {
        raw = prefs.getString('$_prefPlansCachePrefix$deptId');
      }
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

  /// 3. ከመስመር ውጭ የተሰራ ለውጥን በወረፋ መመዝገብ (Enqueue Pending Change with User ID)
  static Future<void> enqueueChange({
    required String entityType, // 'plan', 'report', 'chat'
    required String action,     // 'insert', 'update', 'delete'
    required Map<String, dynamic> data,
    required String departmentId,
    String? userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefPendingQueueKey);
      List<dynamic> queue = [];
      if (raw != null && raw.isNotEmpty) {
        queue = jsonDecode(raw);
      }

      final currentUid = userId ?? AuthService.currentUserProfile?['id']?.toString() ?? 'u_anon';
      final syncId = 'sync_${DateTime.now().millisecondsSinceEpoch}_${queue.length + 1}';
      final item = {
        'sync_id': syncId,
        'user_id': currentUid,
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

  /// ያልተመሳከሩ ወረፋዎች መኖራቸውን ማረጋገጫ (Check if queue has pending items)
  static Future<bool> hasPendingChanges() async {
    final q = await getPendingQueue();
    return q.isNotEmpty;
  }

  /// 5. አውታረ-መረብ ሲገኝ ወረፋውን ከአገልጋዩ ጋር ማመሳከር እና የተሳኩትን ብቻ ማስወገድ (Per-Item Sync Resolution)
  static Future<Map<String, dynamic>> syncPendingQueue(String deviceId) async {
    final queue = await getPendingQueue();
    if (queue.isEmpty) {
      return {'processed': 0, 'status': 'no_pending'};
    }

    try {
      final result = await ApiService().syncOfflineQueue(queue, deviceId);
      final data = result['data'] ?? {};
      final items = data['items'] as List<dynamic>? ?? [];

      // አገልጋዩ ያረጋገጣቸውን የተሳኩ sync_id መለያዎች ብቻ መለየት
      final successfulSyncIds = <String>{};
      for (final it in items) {
        if (it is Map && (it['status'] == 'success' || it['status'] == 'skipped')) {
          final sId = it['sync_id']?.toString();
          if (sId != null && sId.isNotEmpty) {
            successfulSyncIds.add(sId);
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();

      // የተሳኩትን ብቻ ከወረፋው ማስወገድ (Remove only confirmed successful items)
      if (successfulSyncIds.isNotEmpty) {
        final remainingQueue = queue.where((item) {
          final sId = item['sync_id']?.toString();
          return sId == null || !successfulSyncIds.contains(sId);
        }).toList();

        if (remainingQueue.isEmpty) {
          await prefs.remove(_prefPendingQueueKey);
        } else {
          await prefs.setString(_prefPendingQueueKey, jsonEncode(remainingQueue));
        }
        await prefs.setString(_prefLastSyncTimeKey, DateTime.now().toIso8601String());

        return {
          'processed': successfulSyncIds.length,
          'remaining': remainingQueue.length,
          'status': remainingQueue.isEmpty ? 'success' : 'partial_success',
          'details': data
        };
      }

      // ሙሉ ባቹ ስህተት ካጋጠመው ወረፋው ሙሉ በሙሉ ይጠበቃል
      return {
        'processed': 0,
        'remaining': queue.length,
        'status': 'failed',
        'message': result['message'] ?? 'አንዳቸውም አልተመሳከሩም'
      };
    } catch (e) {
      return {'processed': 0, 'remaining': queue.length, 'status': 'network_error', 'message': e.toString()};
    }
  }

  /// 6. ሎግአውት ሲደረግ የአካባቢ ካሽን ማጽዳት (ያልተመሳከሩ ወረፋዎችን ሳያጠፉ!)
  static Future<void> purgeUserData(String deptId, {String? userId, bool forcePurgeQueue = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyPlans = _buildCacheKey(_prefPlansCachePrefix, deptId, userId);
      final keyReports = _buildCacheKey(_prefReportsCachePrefix, deptId, userId);

      await prefs.remove(keyPlans);
      await prefs.remove(keyReports);
      await prefs.remove('$_prefPlansCachePrefix$deptId');
      await prefs.remove('$_prefReportsCachePrefix$deptId');

      // ያልተመሳከሩ ወረፋዎች ካሉ ያለ ተጠቃሚው ግልጽ ፈቃድ (forcePurgeQueue) በጭራሽ አይጠፉም!
      if (forcePurgeQueue) {
        await prefs.remove(_prefPendingQueueKey);
      }
    } catch (e) {
      debugPrint('purgeUserData error: $e');
    }
  }
}
