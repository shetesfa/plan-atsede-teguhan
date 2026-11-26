import 'package:flutter/material.dart';
import '../models/department.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// የተጠቃሚዎች አስተዳደር ገጽ — ለጽ/ቤት (Super Admin) ብቻ (2026-11-26)።
/// አዲስ user መጨመር፣ መረጃ ማሻሻል፣ password reset፣ user ማሰናከል/ማንቃት።
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (!AuthService.isSuperAdmin) {
      // ይህ ገጽ ለጽ/ቤት ብቻ ነው — ሌላ ሰው ከገባ መልእክት አሳይተን እንወጣለን።
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ይህ ገጽ ለጽ/ቤት (Super Admin) ብቻ ነው'),
              backgroundColor: AppTheme.redDanger,
            ),
          );
          Navigator.of(context).pop();
        }
      });
      return;
    }
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await ApiService().fetchUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _loading = false;
      });
    }
  }

  void _snack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? AppTheme.greenSuccess : AppTheme.redDanger,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  int _userId(Map<String, dynamic> u) =>
      (u['id'] is int) ? u['id'] as int : int.tryParse('${u['id']}') ?? 0;

  String _roleLabel(String? role) =>
      role == 'dept_admin' ? 'የክፍል አስተዳዳሪ' : 'አባል';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text('ተጠቃሚዎች አስተዳደር'),
        backgroundColor: AppTheme.primaryMaroon,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'እንደገና አምጣ',
            onPressed: _loadUsers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryMaroon,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('አዲስ user'),
        onPressed: () => _showAddDialog(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('ምንም ተጠቃሚ አልተገኘም'))
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _users.length,
                    itemBuilder: (ctx, i) {
                      final u = _users[i];
                      final status = '${u['status'] ?? 'active'}';
                      final isActive = status == 'active';
                      final role = '${u['role'] ?? 'member'}';
                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryMaroon,
                            foregroundColor: Colors.white,
                            child: Text(
                              ('${u['full_name'] ?? '?'}').isNotEmpty
                                  ? ('${u['full_name']}')[0]
                                  : '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            '${u['full_name'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${u['username'] ?? ''} • ${u['department_name'] ?? u['department_id'] ?? ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _chip(
                                    _roleLabel(role),
                                    role == 'dept_admin'
                                        ? AppTheme.secondaryGold
                                        : Colors.grey.shade300,
                                    role == 'dept_admin'
                                        ? Colors.black87
                                        : Colors.black54,
                                  ),
                                  const SizedBox(width: 6),
                                  _chip(
                                    isActive ? 'ንቁ' : 'ታግዷል',
                                    isActive
                                        ? AppTheme.greenBg
                                        : AppTheme.redBg,
                                    isActive
                                        ? AppTheme.greenSuccess
                                        : AppTheme.redDanger,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.textMuted,
                          ),
                          onTap: () => _showActionsDialog(u),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ---------- አዲስ user ----------
  Future<void> _showAddDialog() async {
    final usernameCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    final roleTitleCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String deptId = AuthService.currentDepartment?.id ?? 'education';
    String role = 'member';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('አዲስ user ጨምር', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'የተጠቃሚ ስም *'),
              ),
              TextField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'ሙሉ ስም *'),
              ),
              DropdownButtonFormField<String>(
                value: deptId,
                decoration: const InputDecoration(labelText: 'ክፍል *'),
                items: Department.allDepartments
                    .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                    .toList(),
                onChanged: (v) => deptId = v ?? deptId,
              ),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'ፈቃድ'),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('አባል')),
                  DropdownMenuItem(value: 'dept_admin', child: Text('የክፍል አስተዳዳሪ')),
                ],
                onChanged: (v) => role = v ?? 'member',
              ),
              TextField(
                controller: roleTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'የስራ መደብ (ለምሳሌ፦ የትምህርት ኃላፊ)',
                ),
              ),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'ጊዜያዊ የይለፍ ቃል * (ቢያንስ 8 ፊደል + ቁጥር)',
                ),
              ),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'ስልክ'),
              ),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'ኢሜል'),
              ),
              const SizedBox(height: 8),
              const Text(
                'ተጠቃሚው በመጀመሪያ መግቢያ ላይ የይለፍ ቃሉን መቀየር አለበት።',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ይቅር'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMaroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ፍጠር'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await ApiService().createUser({
      'username': usernameCtrl.text.trim(),
      'full_name': fullNameCtrl.text.trim(),
      'department_id': deptId,
      'role': role,
      'role_title': roleTitleCtrl.text.trim(),
      'password': passwordCtrl.text,
      'phone': phoneCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
    });
    _snack(
      result['success'] == true
          ? 'ተጠቃሚው ተፈጥሯል'
          : '${result['message'] ?? 'ተጠቃሚውን መፍጠር አልተቻለም'}',
      result['success'] == true,
    );
    if (result['success'] == true) _loadUsers();
  }

  // ---------- የተጠቃሚ እርምጃዎች ----------
  Future<void> _showActionsDialog(Map<String, dynamic> u) async {
    final isActive = '${u['status'] ?? 'active'}' == 'active';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${u['full_name'] ?? ''}', style: const TextStyle(fontSize: 16)),
        content: Text(
          '${u['username'] ?? ''} • ${u['department_name'] ?? u['department_id'] ?? ''}\n${_roleLabel('${u['role'] ?? 'member'}')} • ${isActive ? 'ንቁ' : 'ታግዷል'}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('edit'),
            child: const Text('መረጃ አሻሽል'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('reset'),
            child: const Text('password ዳግም አስጀምር'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(isActive ? 'deactivate' : 'activate'),
            child: Text(
              isActive ? 'አሰናክል' : 'አንቃ',
              style: TextStyle(
                color: isActive ? AppTheme.redDanger : AppTheme.greenSuccess,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('ዝጋ'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'edit') {
      _showEditDialog(u);
    } else if (choice == 'reset') {
      _showResetDialog(u);
    } else if (choice == 'deactivate') {
      _confirmDeactivate(u);
    } else if (choice == 'activate') {
      final result = await ApiService().updateUser(
        _userId(u),
        {'status': 'active'},
      );
      _snack(
        result['success'] == true
            ? 'ተጠቃሚው እንደገና ተንቅቷል'
            : '${result['message'] ?? 'ማንቃት አልተቻለም'}',
        result['success'] == true,
      );
      if (result['success'] == true) _loadUsers();
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> u) async {
    final fullNameCtrl = TextEditingController(text: '${u['full_name'] ?? ''}');
    final roleTitleCtrl = TextEditingController(text: '${u['role_title'] ?? ''}');
    final phoneCtrl = TextEditingController(text: '${u['phone'] ?? ''}');
    final emailCtrl = TextEditingController(text: '${u['email'] ?? ''}');
    String deptId = '${u['department_id'] ?? 'education'}';
    String role = '${u['role'] ?? 'member'}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('መረጃ አሻሽል', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'ሙሉ ስም'),
              ),
              TextField(
                controller: roleTitleCtrl,
                decoration: const InputDecoration(labelText: 'የስራ መደብ'),
              ),
              DropdownButtonFormField<String>(
                value: deptId,
                decoration: const InputDecoration(labelText: 'ክፍል'),
                items: Department.allDepartments
                    .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                    .toList(),
                onChanged: (v) => deptId = v ?? deptId,
              ),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'ፈቃድ'),
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('አባል')),
                  DropdownMenuItem(value: 'dept_admin', child: Text('የክፍል አስተዳዳሪ')),
                ],
                onChanged: (v) => role = v ?? 'member',
              ),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'ስልክ'),
              ),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'ኢሜል'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ይቅር'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMaroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('አስቀምጥ'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final result = await ApiService().updateUser(_userId(u), {
      'full_name': fullNameCtrl.text.trim(),
      'role_title': roleTitleCtrl.text.trim(),
      'department_id': deptId,
      'role': role,
      'phone': phoneCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
    });
    _snack(
      result['success'] == true
          ? 'መረጃው ተሻሽሏል'
          : '${result['message'] ?? 'ማሻሻል አልተቻለም'}',
      result['success'] == true,
    );
    if (result['success'] == true) _loadUsers();
  }

  Future<void> _showResetDialog(Map<String, dynamic> u) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'password ዳግም አስጀምር — ${u['full_name'] ?? ''}',
          style: const TextStyle(fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'አዲስ ጊዜያዊ የይለፍ ቃል (ቢያንስ 8 ፊደል + ቁጥር)',
              ),
            ),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'ድገም አስገባ'),
            ),
            const SizedBox(height: 8),
            const Text(
              'ተጠቃሚው በመጀመሪያ መግቢያ ላይ የይለፍ ቃሉን መቀየር አለበት።',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ይቅር'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryMaroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('አስጀምር'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (passCtrl.text != confirmCtrl.text) {
      _snack('የይለፍ ቃሎቹ አይመሳሰሉም — እንደገና ይሞክሩ', false);
      return;
    }

    final result = await ApiService().resetUserPassword(_userId(u), passCtrl.text);
    _snack(
      result['success'] == true
          ? 'የይለፍ ቃል ዳግም ተጀምሯል'
          : '${result['message'] ?? 'ዳግም ማስጀመር አልተቻለም'}',
      result['success'] == true,
    );
  }

  Future<void> _confirmDeactivate(Map<String, dynamic> u) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ተጠቃሚውን ማሰናከል ይፈልጋሉ?', style: TextStyle(fontSize: 16)),
        content: Text(
          '«${u['full_name'] ?? ''}» ከአሁን በኋላ መግባት አይችልም።\nመረጃው አይሰረዝም — በኋላ እንደገና ማንቃት ይቻላል።',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ይቅር'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('አዎ፣ አሰናክል', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await ApiService().deactivateUser(_userId(u));
    _snack(
      result['success'] == true
          ? 'ተጠቃሚው ታግዷል'
          : '${result['message'] ?? 'ማሰናከል አልተቻለም'}',
      result['success'] == true,
    );
    if (result['success'] == true) _loadUsers();
  }
}
