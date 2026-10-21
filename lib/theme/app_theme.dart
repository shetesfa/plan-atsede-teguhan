import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // የአጸደ ትጉሃን ይፋዊ ማራኪ የግራዲየንት ቀለሞች
  static const Color primaryMaroon = Color(0xFF8B1D2C); // ሮያል ወይን ጠጅ
  static const Color darkMaroon = Color(0xFF4E0812); // ጥልቅ ማሩን
  static const Color secondaryGold = Color(0xFFF39C12); // ወርቃማ አምበር
  static const Color darkGold = Color(0xFFD68910);
  static const Color lightGold = Color(0xFFFFF7E6);
  static const Color bgGrey = Color(0xFFF4F6F9);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1E2124);
  static const Color textMuted = Color(0xFF6C757D);
  static const Color greenSuccess = Color(0xFF27AE60);
  static const Color redDanger = Color(0xFFE74C3C);
  static const Color blueInfo = Color(0xFF2980B9);
  static const Color purpleAccent = Color(0xFF8E44AD);
  static const Color tealAccent = Color(0xFF16A085);

  // ውብ ግራዲየንቶች
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B1D2C), Color(0xFF530A14)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFF39C12), Color(0xFFE67E22)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardHeaderGradient = LinearGradient(
    colors: [Color(0xFF2C3E50), Color(0xFF1A252F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryMaroon,
        primary: primaryMaroon,
        secondary: secondaryGold,
        surface: cardBg,
      ),
      scaffoldBackgroundColor: bgGrey,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryMaroon,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSansEthiopic(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 3,
        shadowColor: Colors.black.withAlpha(25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryMaroon,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.notoSansEthiopic(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      textTheme: GoogleFonts.notoSansEthiopicTextTheme(),
    );
  }
}
