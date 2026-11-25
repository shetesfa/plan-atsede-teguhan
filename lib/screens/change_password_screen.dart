import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// የይለፍ ቃል መቀየሪያ ገጽ (Audit fix 2026-11-25).
///
/// ከዚህ በፊት በአፕ ውስጥ የይለፍ ቃል መቀየሪያ ምንም ገጽ አልነበረም —
//  api/auth.php ላይ change_password ቢኖርም ምንም የሚጠራው አልነበረም፤
//  ለዚህ ነው admin ሲገባ ምንም ያልጠየቀው። አሁን፦
//  * ነባሪ (seed) የይለፍ ቃል ያለው ተጠቃሚ በመጀመሪያ መግቢያ ላይ
//    ይህን ገጽ ማለፍ አይችልም (mustChange: true)።
//  * ማንኛውም ተጠቃሚ ከዳሽቦርድ መቀየር ይችላል (mustChange: false)።
class ChangePasswordScreen extends StatefulWidget {
  final bool mustChange;
  final VoidCallback? onPasswordChanged;

  const ChangePasswordScreen({
    super.key,
    this.mustChange = false,
    this.onPasswordChanged,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _oldVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validate() {
    final oldPass = _oldController.text;
    final newPass = _newController.text;
    final confirm = _confirmController.text;
    if (oldPass.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      return 'እባክዎ ሦስቱንም መስኮች ይሙሉ።';
    }
    if (newPass.length < 8 || !RegExp(r'[0-9]').hasMatch(newPass)) {
      return 'አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።';
    }
    if (newPass != confirm) {
      return 'አዲሱ የይለፍ ቃል እና ማረጋገጫው አይመሳሰሉም።';
    }
    if (newPass == oldPass) {
      return 'አዲሱ የይለፍ ቃል ከድሮው መለየት አለበት።';
    }
    return null;
  }

  Future<void> _handleChange() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = await ApiService().changePassword(
      _oldController.text,
      _newController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      await AuthService.clearMustChangePassword();
      widget.onPasswordChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('የይለፍ ቃልዎ በተሳካ ሁኔታ ተቀይሯል!'),
          backgroundColor: AppTheme.greenSuccess,
        ),
      );
      // mustChange ሲሆን ይህ ገጽ በቀጥታ ከዋናው ማያ ተመልሷል (push አልተደረገም)
      // ስለዚህ pop ማድረግ የለበትም — onPasswordChanged rebuild ያደርጋል።
      if (!widget.mustChange) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() => _errorMessage = result['message']?.toString() ?? 'የይለፍ ቃል መቀየር አልተቻለም');
    }
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    widget.onPasswordChanged?.call();
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback onToggleVisible,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggleVisible,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.mustChange,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('የይለፍ ቃል ቀይር'),
          automaticallyImplyLeading: !widget.mustChange,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.mustChange)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.amberBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.amberWarning),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_reset, color: AppTheme.amberWarning, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'እርስዎ አሁን ያለዎት ነባሪ የይለፍ ቃል ነው። ለመቀጠል እባክዎ አዲስ የይለፍ ቃል ያስገቡ።',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.mustChange) const SizedBox(height: 20),
              _passwordField(
                label: 'የድሮው የይለፍ ቃል',
                controller: _oldController,
                visible: _oldVisible,
                onToggleVisible: () => setState(() => _oldVisible = !_oldVisible),
              ),
              const SizedBox(height: 16),
              _passwordField(
                label: 'አዲስ የይለፍ ቃል',
                controller: _newController,
                visible: _newVisible,
                onToggleVisible: () => setState(() => _newVisible = !_newVisible),
              ),
              const SizedBox(height: 16),
              _passwordField(
                label: 'አዲሱን የይለፍ ቃል ያረጋግጡ',
                controller: _confirmController,
                visible: _confirmVisible,
                onToggleVisible: () => setState(() => _confirmVisible = !_confirmVisible),
              ),
              const SizedBox(height: 8),
              const Text(
                'አዲሱ የይለፍ ቃል ቢያንስ 8 ፊደላት እና ቢያንስ አንድ ቁጥር መያዝ አለበት።',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppTheme.redDanger, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleChange,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryMaroon,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('የይለፍ ቃል ቀይር', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
              if (widget.mustChange) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _handleLogout,
                  child: const Text('ከስርዓቱ ውጣ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
