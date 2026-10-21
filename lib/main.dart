import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/telegram_service.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Non-blocking — ካልሰራ app አያቆምም
  try {
    await AuthService.initSession();
  } catch (_) {}
  try {
    await ChatService().init();
  } catch (_) {}
  try {
    await TelegramService.init();
  } catch (_) {}
  runApp(const AtsedeTeguhanApp());
}

class AtsedeTeguhanApp extends StatelessWidget {
  const AtsedeTeguhanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'አጸደ ትጉሃን ሰንበት ትምህርት ቤት',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigationScreen(),
    );
  }
}
