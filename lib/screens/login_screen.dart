import 'package:flutter/material.dart';
import '../models/department.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Department selectedDept = Department.allDepartments.first;
  final passwordController = TextEditingController(text: '1234');
  String? errorMessage;
  bool isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showLoginDialog() {
    if (AuthService.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ስርዓቱ ለደህንነት ሲባል ተቆልፏል! የቀረው ጊዜ፡ ${AuthService.remainingLockMinutes} ደቂቃ'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
      return;
    }

    errorMessage = null;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Center(
              child: SingleChildScrollView(
                child: Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 16,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Container(
                    width: 440,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // አርማ እና ርዕስ
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.secondaryGold, width: 2),
                              ),
                              child: ClipOval(
                                child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'የአመራር መግቢያ በር',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryMaroon,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'ክፍልዎን ይምረጡና «ግባ» የሚለውን ይጫኑ',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 20),

                        // ክፍል መራጭ
                        const Text(
                          'ክፍልዎን ይምረጡ፡',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.grey.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Department>(
                              value: selectedDept,
                              isExpanded: true,
                              items: Department.allDepartments
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d.name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    selectedDept = val;
                                    errorMessage = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // የይለፍ ቃል
                        const Text(
                          'የይለፍ ቃል፡',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passwordController,
                          obscureText: !isPasswordVisible,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            hintText: 'የይለፍ ቃል (ነባሪ፡ 1234)',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            suffixIcon: IconButton(
                              icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                              onPressed: () => setDialogState(() => isPasswordVisible = !isPasswordVisible),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              errorMessage!,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        const Text(
                          'ማሳሰቢያ፦ የይለፍ ቃል በተከታታይ 16 ጊዜ ከተሳሳተ ስርዓቱ ለ 30 ደቂቃ ይቆለፋል።',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 22),

                        // የመግቢያ አዝራር
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              final err = await AuthService.attemptLogin(selectedDept, passwordController.text);
                              if (err == null) {
                                widget.onLoginSuccess();
                                if (dialogCtx.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                }
                              } else {
                                setDialogState(() => errorMessage = err);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryMaroon,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text(
                              'ግባ',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              // ማዕከላዊ አርማ - ተጠቃሚው ሲጫነው የመግቢያ መስኮቱ በቅጽበት ይከፈታል
              Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _showLoginDialog,
                    behavior: HitTestBehavior.opaque,
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(90),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: AppTheme.secondaryGold.withAlpha(140),
                              blurRadius: 36,
                              spreadRadius: 3,
                            ),
                          ],
                          border: Border.all(color: AppTheme.secondaryGold, width: 4),
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ርዕስ - እንዲሁ ሲነካ መግቢያውን መክፈት ይችላል
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _showLoginDialog,
                  behavior: HitTestBehavior.opaque,
                  child: const Column(
                    children: [
                      Text(
                        'አጸደ ትጉሃን ሰንበት ትምህርት ቤት',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'የአመራሮች እቅድ መቆጣጠሪያ መተግበሪያ',
                        style: TextStyle(
                          color: AppTheme.lightGold,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              const Text(
                'የፅ/ቤት እና የ10ሩ ክፍሎች ማዕከላዊ ቁጥጥር ስርዓት',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
