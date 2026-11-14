import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'services/offline_sync_service.dart';
import 'services/telegram_service.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // M5፦ የአገልግሎት ማስጀመሪያ ስህተቶች በዝምታ አይዋጡም — ስሙ እና ምክንያቱ
  // ይመዘገባሉ እና ለተጠቃሚው በሚታይ ማስጠንቅቂያ ይቀርባሉ። አፕሉ ቢወድቅም ይነሳል።
  final initErrors = <String>[];

  Future<void> safeInit(String serviceName, Future<void> Function() init) async {
    try {
      await init();
    } catch (e) {
      final message = '$serviceName ማስጀመር አልተቻለም፦ $e';
      debugPrint('[Init] $message');
      initErrors.add(message);
    }
  }

  await safeInit('ApiService', ApiService.init);
  await safeInit('AuthService', AuthService.initSession);
  await safeInit('NotificationService', () => NotificationService().init());
  await safeInit('ChatService', () => ChatService().init());
  await safeInit('TelegramService', TelegramService.init);

  // H5፦ ከመስመር ውጭ የተቀመጡ ለውጦች ካሉ አፕ ሲከፈት (እና ተጠቃሚው ከገባ በኋላ)
  // ከአገልጋዩ ጋር ይመሳከራሉ። ስህተት ቢኖር አፕሉን አያቋርጥም — ወረፋው ተቀምጦ
  // በሚቀጥለው ስኬታማ ጥሪ ይሞከራል።
  if (ApiService.authToken != null && ApiService.authToken!.isNotEmpty) {
    try {
      final syncResult = await OfflineSyncService.syncPendingQueue('atsede_app_device');
      debugPrint('[Init] Startup offline sync: $syncResult');
    } catch (e) {
      debugPrint('[Init] Startup offline sync failed (queue kept, will retry later): $e');
    }
  }

  runApp(AtsedeTeguhanApp(initErrors: initErrors));
}

class AtsedeTeguhanApp extends StatelessWidget {
  /// M5፦ ማስጀመር ያልቻሉ አገልግሎቶች (ለተጠቃሚው በሚታይ ማስጠንቅቂያ ይታያሉ)።
  final List<String> initErrors;

  const AtsedeTeguhanApp({super.key, this.initErrors = const []});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ዓጸደ ትጉሃን ሰንበት ትምህርት ቤት',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _InitErrorBanner(
        errors: initErrors,
        child: const MainNavigationScreen(),
      ),
    );
  }
}

/// M5፦ አገልግሎት ማስጀመር ሲያቅተው በገጹ ላይኛው ክፍል ላይ የሚታይ ማስጠንቅቂያ —
/// ተጠቃሚው "ለምን አይሰራም?" ሲል ምክንያቱን ማየት ይችላል። ሊዘጋ ይችላል፤
/// አፕሉን አያግድም።
class _InitErrorBanner extends StatefulWidget {
  final List<String> errors;
  final Widget child;

  const _InitErrorBanner({required this.errors, required this.child});

  @override
  State<_InitErrorBanner> createState() => _InitErrorBannerState();
}

class _InitErrorBannerState extends State<_InitErrorBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.errors.isEmpty || _dismissed) return widget.child;

    return Column(
      children: [
        Material(
          color: Colors.red.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'አንዳንድ አገልግሎቶች መጀመር አልቻሉም፦ ${widget.errors.join('፤ ')}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    tooltip: 'ዝጋ',
                    onPressed: () => setState(() => _dismissed = true),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
