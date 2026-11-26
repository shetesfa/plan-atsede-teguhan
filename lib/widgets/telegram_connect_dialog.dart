import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/telegram_service.dart';
import '../theme/app_theme.dart';

class TelegramConnectDialog extends StatefulWidget {
  const TelegramConnectDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => const TelegramConnectDialog(),
    );
    return result ?? false;
  }

  @override
  State<TelegramConnectDialog> createState() => _TelegramConnectDialogState();
}

class _TelegramConnectDialogState extends State<TelegramConnectDialog> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _recentChats = [];
  String? _statusMessage;

  // PR #31 (Telegram ማገናኘት — በኮድ)፦
  // _telegramLinked null ማለት ሁኔታው ገና አልታወቀም ማለት ነው።
  bool? _telegramLinked;
  String? _linkCode;
  bool _isLinkLoading = false;

  // 2026-11-26 (M3): only the office (super admin) and the education
  // department may change the bot token. For everyone else the token
  // field stays empty and disabled, so the token is never shown.
  bool get _canChangeToken =>
      AuthService.isSuperAdmin ||
      AuthService.currentDepartment?.id == 'education';

  @override
  void initState() {
    super.initState();
    if (TelegramService.savedChatId != null) {
      _idController.text = TelegramService.savedChatId!;
    }
    if (_canChangeToken) {
      _tokenController.text = TelegramService.botToken;
    }
    _autoDiscover();
    _loadTelegramStatus();
  }

  /// PR #31፦ የአሁኑ ተጠቃሚ Telegram አገናኝቶ እንደሆነ ከአገልጋዩ ማረጋገጥ።
  Future<void> _loadTelegramStatus() async {
    final result = await ApiService().getTelegramStatus();
    if (!mounted) return;
    setState(() {
      _telegramLinked = result['success'] == true ? result['linked'] == true : false;
    });
  }

  /// PR #31፦ አንድ ጊዜ ብቻ የሚሰራ 6 አሃዝ የአገናኝ ኮድ መጠየቅ።
  Future<void> _requestLinkCode() async {
    setState(() => _isLinkLoading = true);
    final result = await ApiService().requestTelegramLinkCode();
    if (!mounted) return;
    setState(() => _isLinkLoading = false);
    if (result['success'] == true && result['code'] != null) {
      setState(() => _linkCode = result['code'].toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'ኮድ ማግኘት አልተቻለም። እባክዎ እንደገና ይሞክሩ።'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
    }
  }

  /// PR #31፦ የ Telegram አገናኝ ማቋረጥ እና ሁኔታውን እንደገና ማረጋገጥ።
  Future<void> _unlinkTelegram() async {
    setState(() => _isLinkLoading = true);
    final result = await ApiService().unlinkTelegram();
    if (!mounted) return;
    setState(() => _isLinkLoading = false);
    if (result['success'] == true) {
      setState(() {
        _linkCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('የ Telegram አገናኝ ተቋርጧል።')),
      );
      await _loadTelegramStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'አገናኙን ማቋረጥ አልተቻለም።'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
    }
  }

  Future<void> _autoDiscover() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'አዳዲስ የቴሌግራም መልእክቶችንና ግሩፖችን በመፈለግ ላይ...';
    });

    final chats = await TelegramService.fetchRecentChats();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _recentChats = chats;
        if (chats.isEmpty) {
          _statusMessage = 'እስካሁን ቦቱን ያናገረ ግሩፕ ወይም ተጠቃሚ አልተገኘም።\nእባክዎ @atsede_leaders_bot ላይ መልእክት ይላኩ ወይም ግሩፕ ውስጥ Add ያድርጉት።';
        } else {
          _statusMessage = '${chats.length} ንቁ የቴሌግራም ውይይት(ቶች) ተገኝተዋል!';
        }
      });
    }
  }

  Future<void> _saveAndTest() async {
    final text = _idController.text.trim();
    final token = _tokenController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('እባክዎ የቴሌግራም Chat ID ያስገቡ ወይም ከዝርዝሩ ይምረጡ!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    if (token.isNotEmpty && _canChangeToken) {
      await TelegramService.saveBotToken(token);
    }
    await TelegramService.saveChatId(text);

    // የሙከራ መልእክት መላክ
    final success = await TelegramService.sendMessage(
      text: '<b>✅ የዐጸደ ትጉሃን ሰንበት ት/ቤት መተግበሪያ</b>\n\nየቴሌግራም ግንኙነት በተሳካ ሁኔታ ተመስርቷል! ከዚህ በኋላ ይፋዊ ደብዳቤዎች እና ሪፖርቶች እዚህ ይደርሳሉ።',
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('የቴሌግራም ግንኙነት ተሳክቷል! የሙከራ መልእክት ተልኳል።'),
            backgroundColor: AppTheme.greenSuccess,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('መልእክት መላክ አልተቻለም። እባክዎ Chat ID ን ያረጋግጡ ወይም ቦቱ ግሩፑ ውስጥ መኖሩን ያረጋግጡ።'),
            backgroundColor: AppTheme.redDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.send_rounded, color: Color(0xFF0088CC)),
          SizedBox(width: 8),
          Text('የቴሌግራም ቦት ማገናኛ', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088CC).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0088CC).withAlpha(60)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'የቦቱ መለያ፦ @atsede_leaders_bot',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0088CC)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '1. በቴሌግራም @atsede_leaders_bot ብለው ፈልገው Start ይበሉት ወይም ወደ ግሩፕ Add ያድርጉት።\n2. ከታች «በራስ-ሰር ፈልግ» የሚለውን ይጫኑ።',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('የተገኙ የቴሌግራም ውይይቶች፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _autoDiscover,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('በራስ-ሰር ፈልግ', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_recentChats.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _recentChats.map((c) {
                      final isSelected = _idController.text == c['id'];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          c['type'] == 'group' || c['type'] == 'supergroup'
                              ? Icons.group
                              : Icons.person,
                          color: const Color(0xFF0088CC),
                        ),
                        title: Text(c['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('ID: ${c['id']} (${c['type']})', style: const TextStyle(fontSize: 11)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppTheme.greenSuccess)
                            : null,
                        onTap: () {
                          setState(() {
                            _idController.text = c['id'];
                          });
                        },
                      );
                    }).toList(),
                  ),
                )
              else if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),

              const SizedBox(height: 12),
              const Text('የደመና ሰርቨር (Cloud Backend)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_done, size: 16, color: Colors.green),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'https://plan-atsede-teguhan-new.onrender.com (Online)',
                        style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Text('የቴሌግራም Bot Token፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _tokenController,
                keyboardType: TextInputType.text,
                obscureText: true,
                enabled: _canChangeToken,
                decoration: InputDecoration(
                  hintText: _canChangeToken
                      ? 'አዲስ የ Bot Token ከ @BotFather...'
                      : 'የ Bot Token መቀየር ለፅ/ቤት እና ለትምህርት ክፍል ብቻ ነው',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 12),
              const Text('የቴሌግራም Chat ID (ወይም ከላይ ይምረጡ)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _idController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: 'ለምሳሌ፦ -100123456789 ወይም 12345678',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              // ── PR #31፦ Telegram ማገናኘት (በኮድ) ────────────────────────
              const SizedBox(height: 16),
              const Text('Telegram ማገናኘት፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              if (_telegramLinked == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_telegramLinked == true)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '✅ Telegram ተገናኝቷል — ${AuthService.currentUserProfile?['full_name'] ?? ''} (${AuthService.currentUserProfile?['department_name'] ?? ''})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _isLinkLoading ? null : _unlinkTelegram,
                        child: _isLinkLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('አገናኝ አቁም', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLinkLoading ? null : _requestLinkCode,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('አገናኝ', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0088CC)),
                    ),
                    if (_linkCode != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text(
                                _linkCode!,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                  color: Color(0xFF0088CC),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'በቴሌግራም @atsede_leaders_bot ን ከፍተህ /start <ኮድ> ላክ',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'ኮዱ ለ 15 ደቂቃ ብቻ ይሰራል — አንድ ጊዜ ብቻ',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ዝጋ'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _saveAndTest,
          icon: const Icon(Icons.check),
          label: const Text('አገናኝ እና ሞክር'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0088CC)),
        ),
      ],
    );
  }
}
