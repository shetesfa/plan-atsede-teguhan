import 'dart:async';
import 'package:flutter/foundation.dart';

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
}

enum MessageStatus { sending, sent, delivered }

/// Pure in-memory chat service — ያለ ዲስክ ወይም IndexedDB ይሰራል።
/// StreamController ይጠቀማል → ቀጥተኛ real-time ለሁሉም listeners።
class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final List<ChatMessage> _allMessages = [];
  final _streamController = StreamController<List<ChatMessage>>.broadcast();
  bool _seeded = false;

  Stream<List<ChatMessage>> get messagesStream => _streamController.stream;

  List<ChatMessage> getMessagesForChannel(String channel) =>
      _allMessages.where((m) => m.channel == channel).toList();

  Future<void> init() async {
    if (_seeded) {
      notifyListeners();
      return;
    }
    _seeded = true;
    _seedDefaultMessages();
  }

  void _seedDefaultMessages() {
    final now = _timeNow();
    _allMessages.addAll([
      ChatMessage(
        id: 'seed_001',
        channel: 'ይፋዊ መመሪያዎች',
        senderName: 'ዲ/ን ቴዎድሮስ',
        senderRole: 'የፅ/ቤት ዋና ጸሐፊ',
        senderDept: 'ጽ/ቤት',
        message:
            'በስመ አብ ወወልድ ወመንፈስ ቅዱስ አሐዱ አምላክ አሜን። የተከበራችሁ የ10ሩም ክፍሎች ኃላፊዎች፡ የ2019 ዓ.ም የ1ኛ ሩብ ዓመት እቅድ ክንውን ሪፖርታችሁን እስከ ጥቅምት 30 እንድታጠናቅቁ በጥብቅ እናሳስባለን።',
        time: '09:30',
        dateLabel: 'ዛሬ',
        isMe: false,
        isOfficialNotice: true,
        attachmentName: 'የሩብ_ዓመት_ሪፖርት_መመሪያ.pdf',
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'seed_002',
        channel: 'የአመራሮች አጠቃላይ ጉባኤ',
        senderName: 'ተስፋሁን ባይህ',
        senderRole: 'የትምህርት ኃላፊ',
        senderDept: 'ትምህርት ክፍል',
        message: 'የቤተ-መጻሕፍት ደንብ ተዘጋጅቷል፤ ወደ PDF አውጥተን ለፅ/ቤት ልከናል።',
        time: now,
        dateLabel: 'ዛሬ',
        isMe: false,
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'seed_003',
        channel: 'ከፅ/ቤት ጋር ቀጥታ',
        senderName: 'ዲ/ን ቴዎድሮስ',
        senderRole: 'የፅ/ቤት ዋና ጸሐፊ',
        senderDept: 'ጽ/ቤት',
        message: 'ሰላም! ይህ ቀጥታ መስመር ሚስጥራዊ ይዘቶችን ለሚልኩ ነው። ፈርሙ ወዴት ደረሳችሁ?',
        time: now,
        dateLabel: 'ዛሬ',
        isMe: false,
        status: MessageStatus.delivered,
      ),
      ChatMessage(
        id: 'seed_004',
        channel: 'የሰነዶች እና እቅድ ማጋሪያ',
        senderName: 'ፍቃዱ ኃይሌ',
        senderRole: 'የልማት ኃላፊ',
        senderDept: 'ልማት ክፍል',
        message: 'አዲሱ ፕሮፖዛል ተዘጋጅቷል። ለሁሉም ክፍሎች እንዲያዩ ይህ ቻናል ተጠቀሙ።',
        time: now,
        dateLabel: 'ዛሬ',
        isMe: false,
        status: MessageStatus.delivered,
      ),
    ]);
    _emit();
    notifyListeners();
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

    final msg = ChatMessage(
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

    _allMessages.add(msg);
    _emit();
    notifyListeners();

    // Simulate delivery confirmation
    await Future.delayed(const Duration(milliseconds: 300));
    final idx = _allMessages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _allMessages[idx] = msg.copyWith(status: MessageStatus.delivered);
      _emit();
      notifyListeners();
    }
  }

  void _emit() {
    if (!_streamController.isClosed) {
      _streamController.add(List.unmodifiable(_allMessages));
    }
  }

  String _timeNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _streamController.close();
    super.dispose();
  }
}
