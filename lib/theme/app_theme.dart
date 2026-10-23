import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // የአጸደ ትጉሃን ፕሪሚየም ይፋዊ ቀለሞች (Royal Modern Palette)
  static const Color primaryMaroon = Color(0xFF7A1321); // ጥልቅ ሮያል ማሩን
  static const Color darkMaroon = Color(0xFF4A0A13); // የከበረ ማሩን
  static const Color accentMaroon = Color(0xFF9E1B2D); // ደማቅ ማሩን
  static const Color secondaryGold = Color(0xFFD4AF37); // ወርቃማ አምበር
  static const Color brightGold = Color(0xFFF1C40F);
  static const Color lightGold = Color(0xFFFFF9E6);
  static const Color surfaceBg = Color(0xFFF7F9FC); // ንጹህ ዘመናዊ የገጽታ ዳራ
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1A1D20); // ፕሪሚየም ጥቁር
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF718096);
  static const Color borderLight = Color(0xFFE2E8F0);

  // የሁኔታ ቀለሞች (Status Accents)
  static const Color greenSuccess = Color(0xFF10B981);
  static const Color greenBg = Color(0xFFECFDF5);
  static const Color redDanger = Color(0xFFEF4444);
  static const Color redBg = Color(0xFFFEF2F2);
  static const Color blueInfo = Color(0xFF2563EB);
  static const Color blueBg = Color(0xFFEFF6FF);
  static const Color amberWarning = Color(0xFFF59E0B);
  static const Color amberBg = Color(0xFFFFFBEB);
  static const Color purpleAccent = Color(0xFF8B5CF6);
  static const Color purpleBg = Color(0xFFF5F3FF);

  // ውብ ፕሪሚየም ግራዲየንቶች
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8A1726), Color(0xFF520B15)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFE5A93C), Color(0xFFC68A1B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ዘመናዊ ለስላሳ ጥላዎች (Modern Soft Elevation Shadows)
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withAlpha(10),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF1E293B).withAlpha(15),
          blurRadius: 20,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF1E293B).withAlpha(8),
          blurRadius: 6,
          spreadRadius: -1,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: primaryMaroon.withAlpha(70),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryMaroon,
        primary: primaryMaroon,
        secondary: secondaryGold,
        surface: cardBg,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: surfaceBg,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryMaroon,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSansEthiopic(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryMaroon, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: redDanger),
        ),
        hintStyle: GoogleFonts.notoSansEthiopic(
          color: textMuted,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryMaroon,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryMaroon.withAlpha(60),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.notoSansEthiopic(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryMaroon,
          side: const BorderSide(color: primaryMaroon, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.notoSansEthiopic(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      textTheme: GoogleFonts.notoSansEthiopicTextTheme().apply(
        bodyColor: textDark,
        displayColor: textDark,
      ),
    );
  }
}
