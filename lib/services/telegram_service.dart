import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TelegramService {
  static String botToken = '8787655703:AAEKUtBab8oi8rIUiwnV3n7HMDpTW63Cehk';
  static String get baseUrl => 'https://api.telegram.org/bot$botToken';
  static String get fileBaseUrl => 'https://api.telegram.org/file/bot$botToken';
  static const String cloudBackendUrl = 'https://plan-atsede-teguhan.onrender.com';
  
  static String? savedChatId = '1537845176';
  static const String _prefChatIdKey = 'atsede_telegram_chat_id';
  static const String _prefBotTokenKey = 'atsede_telegram_bot_token';

  // የቀጥታ ዥረት (Real-time Stream) ለውይይት
  static final StreamController<List<TelegramLiveMessage>> _messageStreamController =
      StreamController<List<TelegramLiveMessage>>.broadcast();
  static Stream<List<TelegramLiveMessage>> get messageStream => _messageStreamController.stream;

  static final List<TelegramLiveMessage> _cachedMessages = [];
  static List<TelegramLiveMessage> get currentMessages => List.unmodifiable(_cachedMessages);

  static bool _isPollerRunning = false;
  static int? _lastUpdateId;

  /// የተቀመጠውን Chat ID እና Bot Token ከአካባቢ ማህደረ-ትውስታ ይጭናል
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefChatIdKey);
      if (id != null && id.isNotEmpty && id != '-1004395752939') {
        savedChatId = id;
      } else {
        savedChatId = '1537845176';
        await prefs.setString(_prefChatIdKey, savedChatId!);
      }

      final token = prefs.getString(_prefBotTokenKey);
      if (token != null && token.isNotEmpty && !token.contains('8754142388')) {
        botToken = token.trim();
      } else {
        botToken = '8787655703:AAEKUtBab8oi8rIUiwnV3n7HMDpTW63Cehk';
        await prefs.setString(_prefBotTokenKey, botToken);
      }
    } catch (_) {}
  }

  /// Bot Token ን ቋሚ አድርጎ መመዝገብ
  static Future<void> saveBotToken(String token) async {
    botToken = token.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefBotTokenKey, botToken);
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
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
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
          'timeout': '15',
          'allowed_updates': jsonEncode(['message', 'channel_post']),
        };
        if (_lastUpdateId != null) {
          queryParams['offset'] = '$_lastUpdateId';
        }

        http.Response? response;
        try {
          final uri = Uri.parse('$baseUrl/getUpdates').replace(queryParameters: queryParams);
          response = await http.get(uri).timeout(const Duration(seconds: 20));
        } catch (_) {
          // ቀጥታ ካልሰራ ከ Render Proxy እንጠይቅ
          try {
            final proxyUri = Uri.parse('$cloudBackendUrl/api/telegram/getUpdates').replace(
              queryParameters: {
                ...queryParams,
                'bot_token': botToken,
              },
            );
            response = await http.get(proxyUri).timeout(const Duration(seconds: 22));
          } catch (_) {}
        }

        if (!_isPollerRunning) break;
        if (response == null) {
          await Future.delayed(const Duration(seconds: 4));
          continue;
        }

        if (response.statusCode == 401) {
          debugPrint('Telegram 401: Unauthorized');
          await Future.delayed(const Duration(seconds: 15));
          continue;
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['ok'] == true && data['result'] is List) {
            final List results = data['result'];
            bool hasNew = false;

            for (var update in results) {
              final updateId = update['update_id'] as int;
              _lastUpdateId = updateId + 1;

              final msg = update['message'] ?? update['channel_post'];
              if (msg == null) continue;

              final chat = msg['chat'];
              final chatId = chat?['id']?.toString();

              if (chatId == savedChatId || chatId == '1537845176' || chatId == '-1004395752939') {
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
                hasNew = true;
              }
            }

            if (hasNew) {
              _messageStreamController.add(List.unmodifiable(_cachedMessages));
            }
          }
        }
      } catch (e) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// ጅምር መልዕክቶችን መጫን
  static Future<List<TelegramLiveMessage>> fetchInitialMessages() async {
    try {
      http.Response? response;
      try {
        final uri = Uri.parse('$baseUrl/getUpdates?limit=50');
        response = await http.get(uri).timeout(const Duration(seconds: 8));
      } catch (_) {
        try {
          final proxyUri = Uri.parse('$cloudBackendUrl/api/telegram/getUpdates?limit=50&bot_token=$botToken');
          response = await http.get(proxyUri).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      if (response == null || response.statusCode != 200) {
        return _cachedMessages;
      }

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

        if (chatId == savedChatId || chatId == '1537845176' || chatId == '-1004395752939') {
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

  /// የጽሑፍ ማሳወቂያ ወደ ቴሌግራም መላክ (በቀጥታ እና በደመና Proxy ባለሁለት አማራጭ)
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

    // አማራጭ 1፦ በቀጥታ ወደ ቴሌግራም ኤፒአይ መሞከር
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
      ).timeout(const Duration(seconds: 7));

      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        return true;
      }
    } catch (e) {
      debugPrint('Direct Telegram send failed, trying Cloud Proxy: $e');
    }

    // አማራጭ 2፦ በ Render Cloud Proxy በኩል መላክ (100% አስተማማኝ)
    try {
      final proxyUri = Uri.parse('$cloudBackendUrl/api/telegram/sendMessage');
      final response = await http.post(
        proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': parseMode,
          'bot_token': botToken,
        }),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        return true;
      }
    } catch (e) {
      debugPrint('Cloud Proxy Telegram send exception: $e');
    }

    // አማራጭ 3፦ በ /api/send_notice በኩል የመጨረሻ ሙከራ
    try {
      final noticeUri = Uri.parse('$cloudBackendUrl/api/send_notice');
      final response = await http.post(
        noticeUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': text, 'chat_id': chatId}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (data['ok'] == true) return true;
    } catch (_) {}

    return false;
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

    final safeFileName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';

    // አማራጭ 1፦ ቀጥታ ጥሪ
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
          filename: safeFileName,
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      if (data['ok'] == true) return true;
    } catch (e) {
      debugPrint('Direct sendDocument failed, trying Cloud Proxy: $e');
    }

    // አማራጭ 2፦ በ Render Cloud Proxy በኩል
    try {
      final uri = Uri.parse('$cloudBackendUrl/api/telegram/sendDocument');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = chatId
        ..fields['bot_token'] = botToken;

      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'document',
          fileBytes,
          filename: safeFileName,
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('Cloud Proxy sendDocument exception: $e');
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

    // አማራጭ 1፦ ቀጥታ ጥሪ
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

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      if (data['ok'] == true) return true;
    } catch (e) {
      debugPrint('Direct sendPhoto failed, trying Cloud Proxy: $e');
    }

    // አማራጭ 2፦ በ Cloud Proxy በኩል
    try {
      final uri = Uri.parse('$cloudBackendUrl/api/telegram/sendPhoto');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = chatId
        ..fields['bot_token'] = botToken;

      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          imageBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);
      return data['ok'] == true;
    } catch (e) {
      debugPrint('Cloud Proxy sendPhoto exception: $e');
      return false;
    }
  }

  /// ቦቱን ያናገሩ የቅርብ ጊዜ ግሩፖችን ወይም ተጠቃሚዎችን Chat ID በራስ-ሰር መፈለግ
  static Future<List<Map<String, dynamic>>> fetchRecentChats() async {
    try {
      http.Response? response;
      try {
        final uri = Uri.parse('$baseUrl/getUpdates');
        response = await http.get(uri).timeout(const Duration(seconds: 6));
      } catch (_) {
        try {
          final proxyUri = Uri.parse('$cloudBackendUrl/api/telegram/getUpdates?bot_token=$botToken');
          response = await http.get(proxyUri).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }

      if (response == null || response.statusCode != 200) {
        return [
          {
            'id': '1537845176',
            'title': 'Shetesfa (የእርስዎ ቻት)',
            'type': 'private',
          }
        ];
      }

      final data = jsonDecode(response.body);
      if (data['ok'] != true || data['result'] == null) {
        return [
          {
            'id': '1537845176',
            'title': 'Shetesfa (የእርስዎ ቻት)',
            'type': 'private',
          }
        ];
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

      // የእርስዎን ቻት በእርግጠኝነት ማካተት
      if (!uniqueChats.containsKey('1537845176')) {
        uniqueChats['1537845176'] = {
          'id': '1537845176',
          'title': 'Shetesfa (የእርስዎ ቻት)',
          'type': 'private',
        };
      }

      return uniqueChats.values.toList();
    } catch (e) {
      debugPrint('Telegram fetchRecentChats exception: $e');
      return [
        {
          'id': '1537845176',
          'title': 'Shetesfa (የእርስዎ ቻት)',
          'type': 'private',
        }
      ];
    }
  }

  /// ከአፑ ወደ ቴሌግራም ግሩፕ መልእክት መላክ
  static Future<bool> sendGroupChatMessage({
    required String text,
    required String senderDept,
    required String senderName,
  }) async {
    final formattedText = '<b>[$senderDept]</b> <i>$senderName</i>፦\n$text';
    return await sendMessage(text: formattedText);
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
