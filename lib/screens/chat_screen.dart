import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/telegram_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  StreamSubscription<List<TelegramLiveMessage>>? _streamSubscription;
  List<TelegramLiveMessage> telegramMessages = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initRealtimeChat();
  }

  Future<void> _initRealtimeChat() async {
    // የቀድሞ መልዕክቶችን ጫን
    final initialMsgs = await TelegramService.fetchInitialMessages();
    if (mounted) {
      setState(() {
        telegramMessages = List.from(initialMsgs);
        isLoading = false;
      });
      _scrollToBottom();
    }

    // የቀጥታ ዥረት አድማጭ ጀምር (Real-time Long Polling)
    TelegramService.startRealtimeListener();

    _streamSubscription = TelegramService.messageStream.listen((newMessages) {
      if (!mounted) return;
      final prevCount = telegramMessages.length;
      setState(() {
        telegramMessages = List.from(newMessages);
      });

      if (newMessages.length > prevCount) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    final currentDept = AuthService.currentDepartment;
    final isSuper = AuthService.isSuperAdmin;
    final deptName = currentDept?.shortName ?? 'ክፍል';
    final senderTitle = isSuper ? 'የፅ/ቤት ዋና ጸሐፊ' : '$deptName ኃላፊ';

    messageController.clear();

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final tempMsg = TelegramLiveMessage(
      messageId: now.millisecondsSinceEpoch,
      senderName: '$deptName ($senderTitle)',
      text: text,
      time: timeStr,
      isFromApp: true,
      isMe: true,
    );

    TelegramService.addLocalMessage(tempMsg);
    _scrollToBottom();

    await TelegramService.sendGroupChatMessage(
      text: text,
      senderDept: deptName,
      senderName: senderTitle,
    );

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickAnyFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isNotEmpty) {
        final file = files.first;
        final fileName = file.name;
        final fileBytes = await file.xFile.readAsBytes();

        setState(() => _isSending = true);
        final currentDept = AuthService.currentDepartment;
        final deptName = currentDept?.shortName ?? 'ክፍል';
        final caption = '<b>[$deptName]</b> ይፋዊ ሰነድ አያይዘዋል፦ $fileName';

        final now = DateTime.now();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final tempMsg = TelegramLiveMessage(
          messageId: now.millisecondsSinceEpoch,
          senderName: deptName,
          text: '📄 ይፋዊ ሰነድ ተልኳል፡ $fileName',
          time: timeStr,
          isFromApp: true,
          isMe: true,
          documentName: fileName,
        );
        TelegramService.addLocalMessage(tempMsg);
        _scrollToBottom();

        await TelegramService.sendDocument(
          fileBytes: fileBytes,
          fileName: fileName,
          caption: caption,
        );

        if (mounted) {
          setState(() => _isSending = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ፋይል መላክ አልተቻለም: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() => _isSending = true);

        final currentDept = AuthService.currentDepartment;
        final deptName = currentDept?.shortName ?? 'ክፍል';
        final caption = '<b>[$deptName]</b> ምስል አያይዘዋል';

        final now = DateTime.now();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final tempMsg = TelegramLiveMessage(
          messageId: now.millisecondsSinceEpoch,
          senderName: deptName,
          text: '📷 ምስል ተልኳል',
          time: timeStr,
          isFromApp: true,
          isMe: true,
          localImageBytes: bytes,
        );
        TelegramService.addLocalMessage(tempMsg);
        _scrollToBottom();

        await TelegramService.sendPhoto(
          imageBytes: bytes,
          fileName: img.name,
          caption: caption,
        );

        if (mounted) {
          setState(() => _isSending = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ፎቶ መላክ አልተቻለም: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EEF3), // የቴሌግራም የበስተጀርባ ቀለም
      appBar: AppBar(
        backgroundColor: const Color(0xFF0088CC), // የቴሌግራም ሰማያዊ ቀለም
        foregroundColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.telegram, color: Color(0xFF0088CC), size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'test atsede',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676), // የቀጥታ አረንጓዴ መብራት
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'የቀጥታ ግንኙነት (Live Sync) • አውቶማቲክ',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'የቴሌግራም ቅንብር',
            onPressed: () => TelegramConnectDialog.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // የመልዕክቶች ዝርዝር
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0088CC)),
                  )
                : telegramMessages.isEmpty
                    ? _buildTelegramEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        itemCount: telegramMessages.length,
                        itemBuilder: (ctx, index) {
                          final msg = telegramMessages[index];
                          return _buildTelegramMessageBubble(msg);
                        },
                      ),
          ),
          // የመልዕክት ምዝገቢያ ሳጥን
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildTelegramEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0088CC).withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.telegram, size: 55, color: Color(0xFF0088CC)),
          ),
          const SizedBox(height: 12),
          const Text(
            'የቴሌግራም ይፋዊ ግሩፕ (test atsede)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0088CC)),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'በዚህ ግሩፕ ውስጥ አባላት በስልካቸው ቴሌግራም ላይ የሚጽፉትም ሆነ እዚህ አፑ ውስጥ የሚጻፈው በሙሉ ያለምንም Refresh በቅጽበት (Real-time) እዚህ ይታያል!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0088CC).withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Color(0xFF0088CC), size: 18),
                SizedBox(width: 6),
                Text(
                  'የቀጥታ አድማጭ ነቅቷል (Auto-sync Active)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF0088CC), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelegramMessageBubble(TelegramLiveMessage msg) {
    final isMe = msg.isMe;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFFE3F2FD) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 2),
              bottomRight: Radius.circular(isMe ? 2 : 14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
            border: Border.all(
              color: isMe ? const Color(0xFF0088CC).withAlpha(50) : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMe ? Icons.verified_user : Icons.person_pin,
                    size: 14,
                    color: isMe ? const Color(0xFF0088CC) : AppTheme.primaryMaroon,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    msg.senderName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isMe ? const Color(0xFF0088CC) : AppTheme.primaryMaroon,
                    ),
                  ),
                  if (msg.username != null && msg.username!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      '@${msg.username}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // ፎቶ ካለው (ከቴሌግራም URL ወይም ከአገር ውስጥ Bytes)
              if (msg.localImageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    msg.localImageBytes!,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 6),
              ] else if (msg.photoUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    msg.photoUrl!,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 150,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFF0088CC), strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (ctx, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.grey.shade200,
                        child: const Row(
                          children: [
                            Icon(Icons.broken_image, color: Colors.grey),
                            SizedBox(width: 6),
                            Text('ምስሉን መጫን አልተቻለም', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // ሰነድ ካለው ማሳየት
              if (msg.documentName != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.documentName!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.cloud_done, color: Color(0xFF0088CC), size: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],

              Text(
                msg.text,
                style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg.time,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all, size: 13, color: Color(0xFF0088CC)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // ፋይል አያይዝ አዝራር
            IconButton(
              icon: const Icon(Icons.attach_file, color: Color(0xFF0088CC)),
              tooltip: 'ሰነድ/ፋይል አያይዝ',
              onPressed: _isSending ? null : _pickAnyFile,
            ),
            // ፎቶ አንሳ/ምረጥ አዝራር
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF0088CC)),
              tooltip: 'ፎቶ ላክ',
              onPressed: _isSending ? null : _pickImage,
            ),
            // የጽሑፍ መጻፊያ
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: messageController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'በቴሌግራም ግሩፕ ውስጥ መልዕክት ይጻፉ...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // መላኪያ አዝራር
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0088CC),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
