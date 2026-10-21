import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TelegramService {
  static const String botToken = '8754142388:AAGKJUQ9PoeCgrlFNRQQlXEPy4uldnAP_c8';
  static const String baseUrl = 'https://api.telegram.org/bot$botToken';
  static const String fileBaseUrl = 'https://api.telegram.org/file/bot$botToken';
  
  static String? savedChatId = '-1004395752939';
  static const String _prefChatIdKey = 'atsede_telegram_chat_id';

  // የቀጥታ ዥረት (Real-time Stream) ለውይይት
  static final StreamController<List<TelegramLiveMessage>> _messageStreamController =
      StreamController<List<TelegramLiveMessage>>.broadcast();
  static Stream<List<TelegramLiveMessage>> get messageStream => _messageStreamController.stream;

  static final List<TelegramLiveMessage> _cachedMessages = [];
  static List<TelegramLiveMessage> get currentMessages => List.unmodifiable(_cachedMessages);

  static bool _isPollerRunning = false;
  static int? _lastUpdateId;

  /// የተቀመጠውን Chat ID ከአካባቢ ማህደረ-ትውስታ ይጭናል
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefChatIdKey);
      if (id != null && id.isNotEmpty) {
        savedChatId = id;
      }
    } catch (_) {}
  }

  /// Chat ID ን ቋሚ አድርጎ መመዝገብ
  static Future<void> saveChatId(String chatId) async {
    savedChatId = chatId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefChatIdKey, savedChatId!);
    } catch (_) {}
  }

  /// የቴሌግራም ፋይል ቀጥተኛ URL ማግኘት (ፎቶ ወይም ሰነድ)
  static Future<String?> getFileUrl(String fileId) async {
    try {
      final uri = Uri.parse('$baseUrl/getFile?file_id=$fileId');
      final res = await http.get(uri);
      final data = jsonDecode(res.body);
      if (data['ok'] == true && data['result'] != null) {
        final filePath = data['result']['file_path'];
        if (filePath != null) {
          return '$fileBaseUrl/$filePath';
        }
      }
    } catch (e) {
      debugPrint('Telegram getFileUrl exception: $e');
    }
    return null;
  }

  /// የቀጥታ (Real-time Long Polling) አድማጭ ማስጀመር
  static void startRealtimeListener() {
    if (_isPollerRunning) return;
    _isPollerRunning = true;
    _runPollerLoop();
  }

  /// የቀጥታ አድማጭ ማቆም
  static void stopRealtimeListener() {
    _isPollerRunning = false;
  }

  /// Long Polling ሉፕ - ያለ ማቋረጥ እና ያለ Refresh አዳዲስ መልእክቶችን በቅጽበት ያዳምጣል
  static Future<void> _runPollerLoop() async {
    while (_isPollerRunning) {
      try {
        final queryParams = <String, String>{
          'timeout': '15', // ቴሌግራም መልእክት እስኪመጣ ድረስ ለ15 ሰከንድ ጥያቄውን ይዞ ያቆየዋል (Long Polling)
          'allowed_updates': jsonEncode(['message', 'channel_post']),
        };
        if (_lastUpdateId != null) {
          queryParams['offset'] = '$_lastUpdateId';
        }

        final uri = Uri.parse('$baseUrl/getUpdates').replace(queryParameters: queryParams);
        final response = await http.get(uri).timeout(const Duration(seconds: 25));

        if (!_isPollerRunning) break;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['ok'] == true && data['result'] is List) {
            final List results = data['result'];
            bool hasNew = false;

            for (var update in results) {
              final updateId = update['update_id'] as int;
              _lastUpdateId = updateId + 1; // ቀጣዩን ዝመና ብቻ ለመቀበል

              final msg = update['message'] ?? update['channel_post'];
              if (msg == null) continue;

              final chat = msg['chat'];
              final chatId = chat?['id']?.toString();

              // የእኛ ይፋዊ ግሩፕ ብቻ
              if (chatId == savedChatId || chatId == '-1004395752939') {
                final messageId = msg['message_id'] as int? ?? 0;

                // ቀድሞ የተመዘገበ ከሆነ አትድገመው
                if (_cachedMessages.any((m) => m.messageId == messageId)) {
                  continue;
                }

                final from = msg['from'] ?? {};
                final firstName = from['first_name'] ?? 'አባል';
                final lastName = from['last_name'] ?? '';
                final senderName = '$firstName $lastName'.trim();
                final username = from['username'];
                final isBot = from['is_bot'] == true;

                // የፎቶ መረጃ ካለ
                String? photoUrl;
                final photos = msg['photo'] as List?;
                if (photos != null && photos.isNotEmpty) {
                  final bestPhoto = photos.last;
                  final fileId = bestPhoto['file_id'] as String?;
                  if (fileId != null) {
                    photoUrl = await getFileUrl(fileId);
                  }
                }

                // የሰነድ መረጃ ካለ
                String? docName;
                String? docUrl;
                final doc = msg['document'];
                if (doc != null) {
                  docName = doc['file_name'] as String? ?? 'ሰነድ.pdf';
                  final docFileId = doc['file_id'] as String?;
                  if (docFileId != null) {
                    docUrl = await getFileUrl(docFileId);
                  }
                }

                String text = msg['text'] ?? msg['caption'] ?? '';
                if (text.isEmpty) {
                  if (photoUrl != null) {
                    text = '📷 [ምስል ተልኳል]';
                  } else if (docName != null) {
                    text = '📄 [$docName ተልኳል]';
                  }
                }

                if (text.isEmpty && photoUrl == null && docName == null) continue;

                final dateSec = msg['date'] as int? ?? 0;
                final date = DateTime.fromMillisecondsSinceEpoch(dateSec * 1000);
                final timeStr =
                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                _cachedMessages.add(
                  TelegramLiveMessage(
                    messageId: messageId,
                    senderName: senderName.isEmpty ? 'የግሩፕ አባል' : senderName,
                    username: username,
                    text: text,
                    time: timeStr,
                    isFromApp: isBot,
                    isMe: isBot,
                    photoUrl: photoUrl,
                    documentName: docName,
                    documentUrl: docUrl,
                  ),
                );
                hasNew = true;
              }
            }

            if (hasNew) {
              _messageStreamController.add(List.unmodifiable(_cachedMessages));
            }
          }
        }
      } catch (e) {
        // የኔትዎርክ ወይም የጊዜ ገደብ መቋረጥ ካጋጠመ ለአፍታ አርፎ ይቀጥላል
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// ጅምር መልዕክቶችን አንድ ጊዜ ለመጫን (Initial load)
  static Future<List<TelegramLiveMessage>> fetchInitialMessages() async {
    try {
      final uri = Uri.parse('$baseUrl/getUpdates?limit=50');
      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (data['ok'] != true || data['result'] == null) {
        return _cachedMessages;
      }

      final List results = data['result'];
      for (var update in results) {
        final updateId = update['update_id'] as int;
        if (_lastUpdateId == null || updateId >= _lastUpdateId!) {
          _lastUpdateId = updateId + 1;
        }

        final msg = update['message'] ?? update['channel_post'];
        if (msg == null) continue;

        final chat = msg['chat'];
        final chatId = chat?['id']?.toString();

        if (chatId == savedChatId || chatId == '-1004395752939') {
          final messageId = msg['message_id'] as int? ?? 0;
          if (_cachedMessages.any((m) => m.messageId == messageId)) {
            continue;
          }

          final from = msg['from'] ?? {};
          final firstName = from['first_name'] ?? 'አባል';
          final lastName = from['last_name'] ?? '';
          final senderName = '$firstName $lastName'.trim();
          final username = from['username'];
          final isBot = from['is_bot'] == true;

          String? photoUrl;
          final photos = msg['photo'] as List?;
          if (photos != null && photos.isNotEmpty) {
            final bestPhoto = photos.last;
            final fileId = bestPhoto['file_id'] as String?;
            if (fileId != null) {
              photoUrl = await getFileUrl(fileId);
            }
          }

          String? docName;
          String? docUrl;
          final doc = msg['document'];
          if (doc != null) {
            docName = doc['file_name'] as String? ?? 'ሰነድ.pdf';
            final docFileId = doc['file_id'] as String?;
            if (docFileId != null) {
              docUrl = await getFileUrl(docFileId);
            }
          }

          String text = msg['text'] ?? msg['caption'] ?? '';
          if (text.isEmpty) {
            if (photoUrl != null) text = '📷 [ምስል ተልኳል]';
            if (docName != null) text = '📄 [$docName ተልኳል]';
          }

          if (text.isEmpty && photoUrl == null && docName == null) continue;

          final dateSec = msg['date'] as int? ?? 0;
          final date = DateTime.fromMillisecondsSinceEpoch(dateSec * 1000);
          final timeStr =
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

          _cachedMessages.add(
            TelegramLiveMessage(
              messageId: messageId,
              senderName: senderName.isEmpty ? 'የግሩፕ አባል' : senderName,
              username: username,
              text: text,
              time: timeStr,
              isFromApp: isBot,
              isMe: isBot,
              photoUrl: photoUrl,
              documentName: docName,
              documentUrl: docUrl,
            ),
          );
        }
      }

      _messageStreamController.add(List.unmodifiable(_cachedMessages));
      return _cachedMessages;
    } catch (e) {
      debugPrint('Telegram fetchInitialMessages exception: $e');
      return _cachedMessages;
    }
  }

  /// የጽሑፍ ማሳወቂያ ወደ ቴሌግራም መላክ
  static Future<bool> sendMessage({
    required String text,
    String? targetChatId,
    String parseMode = 'HTML',
  }) async {
    final chatId = targetChatId ?? savedChatId;
    if (chatId == null || chatId.isEmpty) {
      debugPrint('Telegram error: Chat ID አልተገኘም!');
      return false;
    }

    try {
      final uri = Uri.parse('$baseUrl/sendMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': parseMode,
        }),
      );

      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('Telegram sendMessage exception: $e');
      return false;
    }
  }

  /// የተዘጋጀ ይፋዊ ፒዲኤፍ (PDF) ሰነድ በቀጥታ ወደ ቴሌግራም መላክ
  static Future<bool> sendDocument({
    required Uint8List fileBytes,
    required String fileName,
    String? caption,
    String? targetChatId,
  }) async {
    final chatId = targetChatId ?? savedChatId;
    if (chatId == null || chatId.isEmpty) {
      debugPrint('Telegram error: Chat ID አልተገኘም!');
      return false;
    }

    try {
      final uri = Uri.parse('$baseUrl/sendDocument');
      final request = http.MultipartRequest('POST', uri)..fields['chat_id'] = chatId;

      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
        request.fields['parse_mode'] = 'HTML';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'document',
          fileBytes,
          filename: fileName.endsWith('.pdf') ? fileName : '$fileName.pdf',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('Telegram sendDocument exception: $e');
      return false;
    }
  }

  /// ምስል (Photo) በቀጥታ ወደ ቴሌግራም መላክ
  static Future<bool> sendPhoto({
    required Uint8List imageBytes,
    String fileName = 'photo.jpg',
    String? caption,
    String? targetChatId,
  }) async {
    final chatId = targetChatId ?? savedChatId;
    if (chatId == null || chatId.isEmpty) {
      debugPrint('Telegram error: Chat ID አልተገኘም!');
      return false;
    }

    try {
      final uri = Uri.parse('$baseUrl/sendPhoto');
      final request = http.MultipartRequest('POST', uri)..fields['chat_id'] = chatId;

      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
        request.fields['parse_mode'] = 'HTML';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          imageBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('Telegram sendPhoto exception: $e');
      return false;
    }
  }

  /// ቦቱን ያናገሩ የቅርብ ጊዜ ግሩፖችን ወይም ተጠቃሚዎችን Chat ID በራስ-ሰር መፈለግ
  static Future<List<Map<String, dynamic>>> fetchRecentChats() async {
    try {
      final uri = Uri.parse('$baseUrl/getUpdates');
      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (data['ok'] != true || data['result'] == null) {
        return [];
      }

      final List results = data['result'];
      final Map<String, Map<String, dynamic>> uniqueChats = {};

      for (var update in results) {
        final message = update['message'] ?? update['channel_post'] ?? update['my_chat_member'];
        if (message != null && message['chat'] != null) {
          final chat = message['chat'];
          final id = chat['id'].toString();
          final title = chat['title'] ??
              '${chat['first_name'] ?? ''} ${chat['last_name'] ?? ''}'.trim();
          final type = chat['type'] ?? 'unknown';

          uniqueChats[id] = {
            'id': id,
            'title': title.isEmpty ? 'ያልታወቀ ተጠቃሚ' : title,
            'type': type,
          };
        }
      }

      return uniqueChats.values.toList();
    } catch (e) {
      debugPrint('Telegram fetchRecentChats exception: $e');
      return [];
    }
  }

  /// ከአፑ ወደ ቴሌግራም ግሩፕ መልእክት መላክ
  static Future<bool> sendGroupChatMessage({
    required String text,
    required String senderDept,
    required String senderName,
  }) async {
    final formattedText = '<b>[$senderDept]</b> <i>$senderName</i>፦\n$text';
    final ok = await sendMessage(text: formattedText);
    return ok;
  }

  /// በአገር ውስጥ የተጨመረ መልዕክት (Local optimistic insert)
  static void addLocalMessage(TelegramLiveMessage msg) {
    _cachedMessages.add(msg);
    _messageStreamController.add(List.unmodifiable(_cachedMessages));
  }

  /// የእቅድ ክንውን ሪፖርት ማሳወቂያ በቀጥታ ወደ ቴሌግራም ግሩፕ መላክ
  static Future<bool> sendPlanReportNotice({
    required String deptName,
    required String senderTitle,
    required String taskTitle,
    required int progressPercent,
    required String doneDetails,
    String? notDoneDetails,
  }) async {
    final statusEmoji = progressPercent == 100
        ? '✅ ተጠናቋል (100%)'
        : progressPercent > 0
            ? '🔄 በከፊል ተከናውኗል ($progressPercent%)'
            : '⚠️ አልተከናወነም (0%)';

    final buffer = StringBuffer();
    buffer.writeln('📋 <b>ይፋዊ የእቅድ ክንውን ሪፖርት</b>');
    buffer.writeln('🏛 <b>ክፍል፦</b> $deptName');
    buffer.writeln('👤 <b>አቅራቢ፦</b> $senderTitle');
    buffer.writeln('🎯 <b>የእቅድ ርዕስ፦</b> $taskTitle');
    buffer.writeln('📊 <b>የአፈፃፀም ደረጃ፦</b> $statusEmoji');
    buffer.writeln('');

    if (doneDetails.trim().isNotEmpty) {
      buffer.writeln('✅ <b>የተከናወኑ ተግባራት፦</b>');
      buffer.writeln(doneDetails.trim());
      buffer.writeln('');
    }

    if (notDoneDetails != null && notDoneDetails.trim().isNotEmpty) {
      buffer.writeln('⚠️ <b>ያልተከናወነ እና ምክንያቱ፦</b>');
      buffer.writeln(notDoneDetails.trim());
      buffer.writeln('');
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    buffer.writeln('📅 <i>ሪፖርት የተላከበት ሰዓት፦ $dateStr</i>');

    return await sendMessage(text: buffer.toString());
  }

  /// የእቅድ ማስተላለፍ (Postpone / Reschedule) ማሳወቂያ ወደ ቴሌግራም መላክ
  static Future<bool> sendPlanPostponedNotice({
    required String deptName,
    required String senderTitle,
    required String taskTitle,
    required String originalDate,
    required String newDate,
    required String reason,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('📅 <b>የእቅድ ማስተላለፍ (Postpone) ማሳወቂያ</b>');
    buffer.writeln('🏛 <b>ክፍል፦</b> $deptName');
    buffer.writeln('👤 <b>ያስተላለፈው አካል፦</b> $senderTitle');
    buffer.writeln('🎯 <b>የእቅድ ርዕስ፦</b> $taskTitle');
    buffer.writeln('⏳ <b>የቀደመው የማስፈጸሚያ ጊዜ፦</b> $originalDate');
    buffer.writeln('➡️ <b>የተላለፈበት አዲስ ቀን፦</b> $newDate');
    buffer.writeln('');
    buffer.writeln('📝 <b>የማስተላለፊያ ምክንያት፦</b>');
    buffer.writeln(reason.trim());
    buffer.writeln('');
    buffer.writeln('📌 <i>ለጽ/ቤት እና ለአመራሮች ይፋዊ መረጃ የቀረበ</i>');

    return await sendMessage(text: buffer.toString());
  }
}

class TelegramLiveMessage {
  final int messageId;
  final String senderName;
  final String? username;
  final String text;
  final String time;
  final bool isFromApp;
  final bool isMe;
  final String? photoUrl;
  final Uint8List? localImageBytes;
  final String? documentName;
  final String? documentUrl;

  TelegramLiveMessage({
    required this.messageId,
    required this.senderName,
    this.username,
    required this.text,
    required this.time,
    required this.isFromApp,
    required this.isMe,
    this.photoUrl,
    this.localImageBytes,
    this.documentName,
    this.documentUrl,
  });
}
