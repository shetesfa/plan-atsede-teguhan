import 'dart:async';
import 'package:flutter/material.dart';
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

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  Timer? _timer;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  Future<void> init() async {
    await fetchNotifications();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      fetchNotifications();
    });
  }

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
