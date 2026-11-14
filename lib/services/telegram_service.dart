// TelegramService — የቤተክርስቲያኑን Telegram bot ከአፑ ጋር የሚያገናኝ አገልግሎት.
//
// የደህንነት ማስታወሻዎች (audit 2026-11-14):
// - H3: Bot token የሚቀመጠው በ flutter_secure_storage ብቻ ነው — በ
//   SharedPreferences (plaintext) በጭራሽ አይቀመጥም። የቆየ token ካለ,
//   init() ሲጠራ ወደ secure storage ይዛወራል እና የቆየው ግቤት ይሰረዛል.
//   Token በ URL query string ውስጥ በጭራሽ አይላክም፤
//   ወደ Render proxy ሲላክ የሚላከው በ `Authorization: Bearer` header ብቻ
//   ነው፤ proxyው የራሱን server-side token ካልተዋቀረ ይጠቀማል።
//   (ወደ api.telegram.org ቀጥታ ጥሪ ሲደረግ token በ URL path ውስጥ
//   `bot<token>/...` መልክ መሆን የ Telegram Bot API ንድፍ ነው —
//   በ query string አይደለም።)
// - H4: ምንም hardcoded Telegram chat ID የለም። Chat ID የሚነበበው ከ
//   secure storage (`atsede_telegram_chat_id`) ብቻ ነው፤ ካልተዋቀረ
//   ባዶ ('') ነው — መልእክት ወደ ማንም ሰው chat በ fallback አይላክም።
//   Chat ID የሚያዋቅረው የቤተክርስቲያን አስተዳዳሪ (admin) ነው። መልእክት
//   ከመላኩ በፊት chat ID ከሌለ፣ መላኪያው በግልጽ ስህተት ይቋረጣል።
// - H8: Telegram `getUpdates` በአፑ ውስጥ በጭራሽ አይጠራም። getUpdates
//   በ Telegram በኩል በአንድ ጊዜ ለአንድ consumer ብቻ ይሰጣል፤ ብቸኛ
//   consumer የ bot server (Render) polling loop ነው። አፑ የውይይት
//   ታሪክ የሚያነበው ከ server-side PHP chat API (`chat.php`) በኩል ብቻ ነው።
// - L4: የ bot መልእክቶች እንደ ተጠቃሚው የላኩት (`isMe`) አይታዩም፤
//   `isMe` የሚሆነው sender ከአሁኑ ተጠቃሚ ጋር ሲዛመድ ብቻ ነው።
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class TelegramService {
  static String botToken = '';
  static String get baseUrl => botToken.isNotEmpty ? 'https://api.telegram.org/bot$botToken' : '';
  static String get fileBaseUrl => botToken.isNotEmpty ? 'https://api.telegram.org/file/bot$botToken' : '';
  static const String cloudBackendUrl = 'https://plan-atsede-teguhan.onrender.com';

  static String? savedChatId;

  // H3/H4: Token እና chat ID የሚቀመጡት በ secure storage ብቻ ነው።
  // እነዚህ ቁልፎች ከዚህ በፊት በ SharedPreferences ይጠቀሙበት የነበሩት
  // ተመሳሳይ ስሞች ናቸው — ስለዚህ የቆየ plaintext ግቤት ካለ፣ init()
  // ወደ secure storage ሲያዛውረው ሊያገኘው ይችላል።
  static const String _secureBotTokenKey = 'atsede_telegram_bot_token';
  static const String _secureChatIdKey = 'atsede_telegram_chat_id';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  // H8: የውይይት ታሪክ ከ server-side chat API የሚነበውበት ቻናል።
  static const String _chatApiChannel = 'ይፋዊ መመሪያዎች';

  // የቀጥታ ዥረት (Real-time Stream) ለውይይት
  static final StreamController<List<TelegramLiveMessage>> _messageStreamController =
      StreamController<List<TelegramLiveMessage>>.broadcast();
  static Stream<List<TelegramLiveMessage>> get messageStream => _messageStreamController.stream;

  static final List<TelegramLiveMessage> _cachedMessages = [];
  static List<TelegramLiveMessage> get currentMessages => List.unmodifiable(_cachedMessages);

  static bool _isPollerRunning = false;

  /// የተቀመጠውን Chat ID እና Bot Token ከደህንነቱ የተጠበቀ ማህደረ-ትውስታ ይጭናል.
  ///
  /// ከዚህ በፊት በ SharedPreferences (plaintext) የተቀመጠ token/chat ID
  /// ካለ፣ ወደ secure storage ይዛወራል እና የቆየው plaintext ግቤት ይሰረዛል (H3).
  /// Chat ID ካልተዋቀረ `savedChatId` ባዶ string ነው — ምንም fallback የለም (H4).
  static Future<void> init() async {
    try {
      botToken = await _secureStorage.read(key: _secureBotTokenKey) ?? '';
      savedChatId = await _secureStorage.read(key: _secureChatIdKey) ?? '';

      // የቆየ plaintext ግቤት ከ SharedPreferences ወደ secure storage ማዛወር።
      final prefs = await SharedPreferences.getInstance();
      if (botToken.isEmpty) {
        final legacyToken = prefs.getString(_secureBotTokenKey);
        if (legacyToken != null && legacyToken.isNotEmpty) {
          botToken = legacyToken;
          await _secureStorage.write(key: _secureBotTokenKey, value: legacyToken);
        }
      }
      if (savedChatId == null || savedChatId!.isEmpty) {
        final legacyChatId = prefs.getString(_secureChatIdKey);
        if (legacyChatId != null && legacyChatId.isNotEmpty) {
          savedChatId = legacyChatId;
          await _secureStorage.write(key: _secureChatIdKey, value: legacyChatId);
        }
      }
      // የቆዩ plaintext ቅጂዎች ሁልጊዜ ይሰረዛሉ — secure storage ውስጥ እሴት
      // ቢኖርም እንኳን።
      await prefs.remove(_secureBotTokenKey);
      await prefs.remove(_secureChatIdKey);
    } catch (_) {}
  }

  /// Bot Token ን በ secure storage ብቻ ቋሚ አድርጎ መመዝገብ (H3).
  static Future<void> saveBotToken(String token) async {
    botToken = token.trim();
    try {
      if (botToken.isEmpty) {
        await _secureStorage.delete(key: _secureBotTokenKey);
      } else {
        await _secureStorage.write(key: _secureBotTokenKey, value: botToken);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_secureBotTokenKey);
    } catch (_) {}
  }

  /// Chat ID ን በ secure storage ብቻ ቋሚ አድርጎ መመዝገብ (H4).
  /// Chat ID የሚያዋቅረው የቤተክርስቲያን አስተዳዳሪ (admin) ነው።
  static Future<void> saveChatId(String chatId) async {
    savedChatId = chatId.trim();
    try {
      if (savedChatId == null || savedChatId!.isEmpty) {
        await _secureStorage.delete(key: _secureChatIdKey);
      } else {
        await _secureStorage.write(key: _secureChatIdKey, value: savedChatId);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_secureChatIdKey);
    } catch (_) {}
  }

  /// ወደ Render proxy ሲላክ የሚጠቀሙ headers። Token የሚላከው በ
  /// `Authorization: Bearer` header ብቻ ነው — በ URL query ወይም
  /// በ body field (`bot_token`) አይላክም (H3)። Token ካልተዋቀረ header
  /// አይላክም፤ proxyው የራሱን server-side token ይጠቀማል።
  static Map<String, String> _proxyHeaders({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (botToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $botToken';
    }
    return headers;
  }

  /// የቴሌግራም ፋይል ቀጥተኛ URL ማግኘት (ፎቶ ወይም ሰነድ)
  static Future<String?> getFileUrl(String fileId) async {
    if (botToken.isEmpty) {
      debugPrint('Telegram getFileUrl: Bot Token አልተዋቀረም!');
      return null;
    }
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

  /// የቀጥታ (Real-time) አድማጭ ማስጀመር.
  ///
  /// H8: አፑ Telegram `getUpdates` long-polling አያደርግም። getUpdates
  /// በአንድ ጊዜ ለአንድ consumer ብቻ ይሰጣል፤ ብቸኛ consumer የ bot server
  /// (Render) polling loop ነው — አፑ ሁለተኛ consumer ቢሆን updates
  /// ይቀማማሉ። ስለዚህ ይህ method ምንም polling loop አይጀምርም፤ የውይይት
  /// ታሪክ የሚመጣው `fetchInitialMessages()` ከ server-side chat API
  /// በኩል ብቻ ነው። ለተኳሃኝነት (chat_screen ይጠራዋል) signatureው ተጠብቋል።
  static void startRealtimeListener() {
    if (_isPollerRunning) return;
    _isPollerRunning = true;
    debugPrint(
      'Telegram realtime listener: app does not poll getUpdates — '
      'the bot server is the single getUpdates consumer; '
      'history is read from the server chat API instead.',
    );
  }

  /// የቀጥታ አድማጭ ማቆም
  static void stopRealtimeListener() {
    _isPollerRunning = false;
  }

  /// ጅምር መልዕክቶችን መጫን — ከ server-side PHP chat API (`chat.php`)
  /// በኩል ብቻ (H8)። Telegram `getUpdates` በጭራሽ አይጠራም፤ token በ URL
  /// ውስጥ አይላክም — ApiService Bearer auth header ይጠቀማል።
  /// PHP API ካልተጫነ ወይም login ካልተደረገ፣ የተቀመጡ መልእክቶች ብቻ ይመለሳሉ።
  static Future<List<TelegramLiveMessage>> fetchInitialMessages() async {
    try {
      final rows = await ApiService().getChatMessages(_chatApiChannel);
      final currentUserName = ApiService.currentUser?['full_name']?.toString() ?? '';

      for (final raw in rows) {
        final messageId = int.tryParse(raw['id']?.toString() ?? '') ?? raw['id'].hashCode;
        if (_cachedMessages.any((m) => m.messageId == messageId)) {
          continue;
        }

        final senderName = (raw['sender_name'] ?? raw['senderName'] ?? 'አባል').toString();
        final text = (raw['message'] ?? '').toString();
        if (text.isEmpty) continue;

        final createdAt = (raw['created_at'] ?? '').toString();
        final timeStr = createdAt.length >= 16 ? createdAt.substring(11, 16) : '00:00';

        // L4: `isMe` የሚሆነው sender ከአሁኑ ተጠቃሚ ጋር ሲዛመድ ብቻ ነው፤
        // የ bot ወይም የሌላ አባል መልእክት እንደ "የእኔ" በጭራሽ አይታይም።
        final isMe = currentUserName.isNotEmpty && senderName == currentUserName;

        _cachedMessages.add(
          TelegramLiveMessage(
            messageId: messageId,
            senderName: senderName,
            username: null,
            text: text,
            time: timeStr,
            isFromApp: false,
            isMe: isMe,
            isBot: false,
            photoUrl: null,
            documentName: null,
            documentUrl: null,
          ),
        );
      }

      _messageStreamController.add(List.unmodifiable(_cachedMessages));
    } catch (e) {
      debugPrint('Telegram fetchInitialMessages exception: $e');
    }
    return _cachedMessages;
  }

  /// የጽሑፍ ማሳወቂያ ወደ ቴሌግራም መላክ (በቀጥታ እና በደመና Proxy ባለሁለት አማራጭ)
  static Future<bool> sendMessage({
    required String text,
    String? targetChatId,
    String parseMode = 'HTML',
  }) async {
    final chatId = targetChatId ?? savedChatId;
    if (chatId == null || chatId.isEmpty) {
      // H4: Chat ID ካልተዋቀረ ወደ ማንም ሰው chat በ fallback አንልክም —
      // አስተዳዳሪው (admin) Chat ID ማዋቀር አለበት።
      debugPrint(
        'Telegram error: Chat ID አልተዋቀረም! መልእክቱ አልተላከም። '
        'የቤተክርስቲያን አስተዳዳሪው Chat ID በ Telegram ቅንብሮች ማስገባት አለበት።',
      );
      return false;
    }

    // አማራጭ 1፦ በቀጥታ ወደ ቴሌግራም ኤፒአይ መሞከር (token ካለ ብቻ)
    if (botToken.isNotEmpty) {
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
    }

    // አማራጭ 2፦ በ Render Cloud Proxy በኩል መላክ (100% አስተማማኝ)
    // H3: token የሚላከው በ Authorization Bearer header ብቻ ነው።
    try {
      final proxyUri = Uri.parse('$cloudBackendUrl/api/telegram/sendMessage');
      final response = await http.post(
        proxyUri,
        headers: _proxyHeaders(),
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': parseMode,
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
      // H4: Chat ID ካልተዋቀረ ወደ ማንም ሰው chat በ fallback አንልክም።
      debugPrint(
        'Telegram error: Chat ID አልተዋቀረም! ሰነዱ አልተላከም። '
        'የቤተክርስቲያን አስተዳዳሪው Chat ID በ Telegram ቅንብሮች ማስገባት አለበት።',
      );
      return false;
    }

    final safeFileName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';

    // አማራጭ 1፦ ቀጥታ ጥሪ (token ካለ ብቻ)
    if (botToken.isNotEmpty) {
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
    }

    // አማራጭ 2፦ በ Render Cloud Proxy በኩል
    // H3: token የሚላከው በ Authorization Bearer header ብቻ ነው።
    try {
      final uri = Uri.parse('$cloudBackendUrl/api/telegram/sendDocument');
      final request = http.MultipartRequest('POST', uri)..fields['chat_id'] = chatId;
      request.headers.addAll(_proxyHeaders(json: false));

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
      // H4: Chat ID ካልተዋቀረ ወደ ማንም ሰው chat በ fallback አንልክም።
      debugPrint(
        'Telegram error: Chat ID አልተዋቀረም! ምስሉ አልተላከም። '
        'የቤተክርስቲያን አስተዳዳሪው Chat ID በ Telegram ቅንብሮች ማስገባት አለበት።',
      );
      return false;
    }

    // አማራጭ 1፦ ቀጥታ ጥሪ (token ካለ ብቻ)
    if (botToken.isNotEmpty) {
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
    }

    // አማራጭ 2፦ በ Cloud Proxy በኩል
    // H3: token የሚላከው በ Authorization Bearer header ብቻ ነው።
    try {
      final uri = Uri.parse('$cloudBackendUrl/api/telegram/sendPhoto');
      final request = http.MultipartRequest('POST', uri)..fields['chat_id'] = chatId;
      request.headers.addAll(_proxyHeaders(json: false));

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

  /// ቦቱን ያናገሩ የቅርብ ጊዜ ግሩፖችን ወይም ተጠቃሚዎችን Chat ID በራስ-ሰር መፈለግ.
  ///
  /// H8/H4: ይህ ከዚህ በፊት Telegram `getUpdates` ይጠቀም ነበር — አሁን
  /// getUpdates በአፑ ውስጥ የተከለከለ ነው (bot server ብቸኛ consumer ነው)።
  /// የ Telegram chats ዝርዝር ከ server በኩል ብቻ ሊመጣ ይችላል፤ እስከዚያው
  /// ድረስ ባዶ ዝርዝር ይመለሳል እና አስተዳዳሪው Chat ID በእጅ ማስገባት አለበት።
  /// ከዚህ በፊት የነበረው hardcoded የግል chat fallback ተወግዷል።
  static Future<List<Map<String, dynamic>>> fetchRecentChats() async {
    debugPrint(
      'Telegram fetchRecentChats: getUpdates is disabled in the app '
      '(bot server is the single consumer); no chat list available. '
      'The church admin must enter the chat ID manually.',
    );
    return [];
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
  // L4: የ bot መልእክት መሆኑን የሚለይ ምልክት። Bot መልእክት `isMe`
  // በጭራሽ መሆን የለበትም — እንደ ተጠቃሚው የላከው እንዳይታይ።
  final bool isBot;
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
    this.isBot = false,
    this.photoUrl,
    this.localImageBytes,
    this.documentName,
    this.documentUrl,
  });
}
