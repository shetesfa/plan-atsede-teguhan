import 'package:flutter/material.dart';
import '../models/department.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// ዘመናዊ፣ ውብ እና የተቀናጀ የአጸደ ትጉሃን የመግቢያ ገጽ (Modern Ecclesiastical Login Portal)
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Department selectedDept = Department.allDepartments.first;
  final passwordController = TextEditingController();
  String? errorMessage;
  bool isPasswordVisible = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (AuthService.isLocked) {
      setState(() {
        errorMessage = 'ስርዓቱ ለደህንነት ሲባል ተቆልፏል! የቀረው ጊዜ፡ ${AuthService.remainingLockMinutes} ደቂቃ';
      });
      return;
    }

    final pwd = passwordController.text;
    if (pwd.isEmpty) {
      setState(() {
        errorMessage = 'እባክዎ የይለፍ ቃል ያስገቡ።';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final err = await AuthService.attemptLogin(selectedDept, pwd);
      if (!mounted) return;

      if (err == null) {
        widget.onLoginSuccess();
      } else {
        setState(() {
          errorMessage = err;
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'ከአገልጋዩ ጋር መገናኘት አልተቻለም። እባክዎ የአገልጋዩን ዝግጁነት ያረጋግጡ።';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 850;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3B0B14), // Deep Imperial Maroon
              Color(0xFF6B1D2F), // Primary Maroon
              Color(0xFF1E060A), // Shadowed Velvet Maroon
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop ? 960 : 480,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(120),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: AppTheme.secondaryGold.withAlpha(80),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ዴስክቶፕ እይታ፦ በግራ በኩል የአርማ እና የክብር ማብራሪያ፣ በቀኝ በኩል የመግቢያ ቅጽ (Split Modern Layout)
  Widget _buildDesktopLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ግራ ጎን፦ አርማ እና መሪ ቃል
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFAF7F2),
                    Color(0xFFF3ECE1),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildEmblemAvatar(size: 190),
                  const SizedBox(height: 28),
                  const Text(
                    'ዓጸደ ትጉሃን ሰንበት ት/ቤት',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1D2F),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'የኢትዮጵያ ኦርቶዶክስ ተዋሕዶ ቤተክርስቲያን\nየአመራር እና ማዕከላዊ እቅድ መቆጣጠሪያ ስርዓት',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF5A4A38),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildServerBadge(),
                ],
              ),
            ),
          ),

          // መለያያ ወርቃማ መስመር
          Container(width: 1, color: AppTheme.secondaryGold.withAlpha(80)),

          // ቀኝ ጎን፦ የመግቢያ ቅጽ
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(44),
              child: _buildFormContent(),
            ),
          ),
        ],
      ),
    );
  }

  /// ሞባይል እይታ፦ ውብ ማዕከላዊ ካርድ
  Widget _buildMobileLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEmblemAvatar(size: 130),
          const SizedBox(height: 18),
          const Text(
            'ዓጸደ ትጉሃን ሰንበት ት/ቤት',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6B1D2F),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'የአመራር መግቢያ በር',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.secondaryGold,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _buildServerBadge(),
          const SizedBox(height: 24),
          _buildFormContent(),
        ],
      ),
    );
  }

  /// አዲሱ ዘመናዊ አርማ (Modern Ecclesiastical Emblem Avatar)
  Widget _buildEmblemAvatar({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: AppTheme.secondaryGold, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondaryGold.withAlpha(120),
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: ClipOval(
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.church_rounded,
            size: 60,
            color: AppTheme.primaryMaroon,
          ),
        ),
      ),
    );
  }

  /// የአገልጋይ ሁኔታ ማሳወቂያ (Connected Server Badge)
  Widget _buildServerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF81C784)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'ኤፒአይ፦ ${ApiService.baseUrl.contains('127.0.0.1') || ApiService.baseUrl.contains('localhost') ? 'አካባቢያዊ (127.0.0.1:8000)' : 'ደመና (Cloud)'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }

  /// የቅጹ ይዘት (Dropdown, Password Field, Login Button)
  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'ክፍልዎን ይምረጡ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2A26),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Department>(
              value: selectedDept,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: AppTheme.primaryMaroon, size: 20),
              items: Department.allDepartments
                  .map(
                    (dept) => DropdownMenuItem(
                      value: dept,
                      child: Row(
                        children: [
                          Icon(
                            dept.isSuperAdmin ? Icons.admin_panel_settings : Icons.school_outlined,
                            size: 18,
                            color: dept.isSuperAdmin ? AppTheme.primaryMaroon : AppTheme.secondaryGold,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              dept.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: dept.isSuperAdmin ? FontWeight.bold : FontWeight.w500,
                                color: const Color(0xFF2D2A26),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    selectedDept = val;
                    errorMessage = null;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 18),

        const Text(
          'የይለፍ ቃል',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2A26),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: passwordController,
          obscureText: !isPasswordVisible,
          onSubmitted: (_) => _handleLogin(),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.primaryMaroon),
            hintText: 'የይለፍ ቃልዎን ያስገቡ — የይለፍ ቃል ከቤተክርስቲያኑ ፅ/ቤት ይሰጣል',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.primaryMaroon, width: 2),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: Colors.grey.shade600,
              ),
              onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCDD2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFC62828), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // የመግቢያ አዝራር (Modern Elevated Button with Gradient)
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMaroon,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: AppTheme.primaryMaroon.withAlpha(120),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'ወደ ስርዓቱ ግባ',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),

        const Center(
          child: Text(
            'የፅ/ቤት እና የ10ሩ ክፍሎች ማዕከላዊ ቁጥጥር ስርዓት',
            style: TextStyle(fontSize: 11, color: Color(0xFF8C827A)),
          ),
        ),
      ],
    );
  }
}
