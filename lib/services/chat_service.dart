import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class ChatMessage {
  final String id;
  final String channel;
  final String senderName;
  final String senderRole;
  final String senderDept;
  final String message;
  final String time;
  final String dateLabel;
  final bool isMe;
  final bool isOfficialNotice;
  final String? attachmentName;
  final String? imagePath;
  final MessageStatus status;

  ChatMessage({
    required this.id,
    required this.channel,
    required this.senderName,
    required this.senderRole,
    required this.senderDept,
    required this.message,
    required this.time,
    this.dateLabel = 'ዛሬ',
    required this.isMe,
    this.isOfficialNotice = false,
    this.attachmentName,
    this.imagePath,
    this.status = MessageStatus.sent,
  });

  ChatMessage copyWith({MessageStatus? status}) => ChatMessage(
        id: id,
        channel: channel,
        senderName: senderName,
        senderRole: senderRole,
        senderDept: senderDept,
        message: message,
        time: time,
        dateLabel: dateLabel,
        isMe: isMe,
        isOfficialNotice: isOfficialNotice,
        attachmentName: attachmentName,
        imagePath: imagePath,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel,
        'sender_name': senderName,
        'sender_role': senderRole,
        'department_id': senderDept,
        'message': message,
        'time': time,
        'is_official_notice': isOfficialNotice ? 1 : 0,
        'attachment_path': attachmentName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserName) {
    final sender = json['sender_name'] ?? json['senderName'] ?? 'አባል';
    final isMine = sender == currentUserName;
    return ChatMessage(
      id: json['id'] ?? ('msg_' + DateTime.now().millisecondsSinceEpoch.toString()),
      channel: json['channel'] ?? json['room_id'] ?? 'ይፋዊ መመሪያዎች',
      senderName: sender,
      senderRole: json['sender_role'] ?? json['senderRole'] ?? 'ተወካይ',
      senderDept: json['department_id'] ?? json['senderDept'] ?? 'admin',
      message: json['message'] ?? '',
      time: json['time'] ?? (json['created_at'] != null ? json['created_at'].toString().substring(11, 16) : '00:00'),
      isMe: isMine,
      isOfficialNotice: json['is_official_notice'] == 1 || json['isOfficialNotice'] == true,
      attachmentName: json['attachment_path'] ?? json['attachmentName'],
      status: MessageStatus.delivered,
    );
  }
}

enum MessageStatus { sending, sent, delivered }

class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final List<ChatMessage> _allMessages = [];
  final _streamController = StreamController<List<ChatMessage>>.broadcast();
  Timer? _pollingTimer;
  String _activeChannel = 'ይፋዊ መመሪያዎች';

  Stream<List<ChatMessage>> get messagesStream => _streamController.stream;

  List<ChatMessage> getMessagesForChannel(String channel) =>
      _allMessages.where((m) => m.channel == channel).toList();

  Future<void> init() async {
    await _loadCachedMessages();
    _startPolling();
  }

  void setActiveChannel(String channel) {
    _activeChannel = channel;
    refreshMessages(channel);
  }

  Future<void> refreshMessages(String channel) async {
    try {
      final remote = await ApiService().getChatMessages(channel);
      if (remote.isNotEmpty) {
        final currentUserName = ApiService.currentUser?['full_name'] ?? '';
        for (var raw in remote) {
          final msg = ChatMessage.fromJson(raw, currentUserName);
          final exists = _allMessages.any((m) => m.id == msg.id);
          if (!exists) {
            _allMessages.add(msg);
          }
        }
        await _saveToCache();
        _emit();
        notifyListeners();
      }
    } catch (_) {}
  }

  void _startPolling() {
    // Audit M4: was every 5 s — three services polling at once (chat 5 s,
    // notifications 15 s, Telegram long-poll) drained battery and mobile
    // data. 30 s is still frequent enough for a department chat, and the
    // user can pull-to-refresh / switch channel for an immediate fetch.
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshMessages(_activeChannel);
    });
  }

  Future<void> _loadCachedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('atsede_chat_cache');
      if (saved != null) {
        final list = jsonDecode(saved) as List;
        final currentUserName = ApiService.currentUser?['full_name'] ?? '';
        _allMessages.clear();
        for (var raw in list) {
          _allMessages.add(ChatMessage.fromJson(raw, currentUserName));
        }
        _emit();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _allMessages.map((m) => m.toJson()).toList();
      await prefs.setString('atsede_chat_cache', jsonEncode(list));
    } catch (_) {}
  }

  Future<void> clearCache() async {
    _allMessages.clear();
    _emit();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('atsede_chat_cache');
    } catch (_) {}
  }

  Future<void> sendMessage({
    required String channel,
    required String senderName,
    required String senderRole,
    required String senderDept,
    required String message,
    String? attachmentName,
    String? imagePath,
    bool isOfficialNotice = false,
  }) async {
    final id = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final now = _timeNow();

    final localMsg = ChatMessage(
      id: id,
      channel: channel,
      senderName: senderName,
      senderRole: senderRole,
      senderDept: senderDept,
      message: message,
      time: now,
      dateLabel: 'ዛሬ',
      isMe: true,
      isOfficialNotice: isOfficialNotice,
      attachmentName: attachmentName,
      imagePath: imagePath,
      status: MessageStatus.sending,
    );

    _allMessages.add(localMsg);
    _emit();
    notifyListeners();
    await _saveToCache();

    try {
      final res = await ApiService().sendChatMessage({
        'id': id,
        'channel': channel,
        'room_id': channel,
        'message': message,
        'is_official_notice': isOfficialNotice ? 1 : 0,
        'attachment_path': attachmentName,
      });

      final idx = _allMessages.indexWhere((m) => m.id == id);
      if (idx != -1) {
        _allMessages[idx] = _allMessages[idx].copyWith(
          status: res['success'] == true ? MessageStatus.delivered : MessageStatus.sent,
        );
        _emit();
        notifyListeners();
        await _saveToCache();
      }
    } catch (_) {
      final idx = _allMessages.indexWhere((m) => m.id == id);
      if (idx != -1) {
        _allMessages[idx] = _allMessages[idx].copyWith(status: MessageStatus.sent);
        _emit();
        notifyListeners();
      }
    }
  }

  void _emit() {
    if (!_streamController.isClosed) {
      _streamController.add(List.unmodifiable(_allMessages));
    }
  }

  static String _timeNow() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _streamController.close();
    super.dispose();
  }
}
