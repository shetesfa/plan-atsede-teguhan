import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/department.dart';
import '../models/unplanned_activity.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class UnplannedActivitiesScreen extends StatefulWidget {
  final List<UnplannedActivity> activities;
  // 2026-11-26: server FIRST — each callback saves to the server and
  // returns {'success': true} only after the server confirms; on failure
  // it returns {'success': false, 'message': ...} and the caller keeps
  // the dialog open instead of pretending the save worked.
  final Future<Map<String, dynamic>> Function(
    UnplannedActivity activity, {
    String? evidenceBase64,
    String? evidenceName,
  }) onAddActivity;
  final Future<Map<String, dynamic>> Function(
    UnplannedActivity activity, {
    String? evidenceBase64,
    String? evidenceName,
  }) onUpdateActivity;
  // Shown in the empty state when the server list could not be loaded
  // (the list stays empty — no stale data is shown).
  final String? loadError;

  const UnplannedActivitiesScreen({
    super.key,
    required this.activities,
    required this.onAddActivity,
    required this.onUpdateActivity,
    this.loadError,
  });

  @override
  State<UnplannedActivitiesScreen> createState() => _UnplannedActivitiesScreenState();
}

class _UnplannedActivitiesScreenState extends State<UnplannedActivitiesScreen> {
  void _showAddDialog() {
    final currentDept = AuthService.currentDepartment;
    String deptName = currentDept?.name ?? 'ልማትና በጎ አድራጎት ክፍል';
    // 2026-11-26: super-admin picks a department by name — keep its ID
    // too, or the record would land in the office's own department.
    String deptId = currentDept?.id ?? 'development';
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    // Audit M8: date field starts EMPTY (was pre-filled with a sample date).
    final dateCtrl = TextEditingController();
    final budgetCtrl = TextEditingController(text: '0');
    // The picked photo itself (XFile) — its bytes are read at save time
    // and uploaded to the server; a device-local path is never stored.
    XFile? pickedPhoto;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ያልታቀደ ግን የተከናወነ ስራ መመዝገቢያ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryMaroon,
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 6),

                    if (AuthService.isSuperAdmin) ...[
                      const Text('ክፍል፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: deptName,
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: Department.allDepartments
                            .where((d) => !d.isSuperAdmin)
                            .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              deptName = val;
                              final picked = Department.allDepartments
                                  .where((d) => d.name == val);
                              if (picked.isNotEmpty) {
                                deptId = picked.first.id;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    _buildField('የስራው ርዕስ (ግዴታ)፡', titleCtrl, hint: 'የስራው ርዕስ እዚህ ያስገቡ'),
                    const SizedBox(height: 10),
                    _buildField('የክንውን ቀን፡', dateCtrl, hint: 'ቀን/ወር/ዓመት ዓ.ም'),
                    const SizedBox(height: 10),
                    _buildField('የስራው ዝርዝር መግለጫ፡', descCtrl, maxLines: 3, hint: 'ዝርዝር መግለጫ እዚህ ያስገቡ'),
                    const SizedBox(height: 10),
                    _buildField('የወጣው ወጪ / በጀት (ብር)፡', budgetCtrl),
                    const SizedBox(height: 12),

                    // የፎቶ ማስረጃ
                    const Text('የክንውን ፎቶ ማስረጃ፡', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              setDlgState(() => pickedPhoto = img);
                            }
                          },
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('ፎቶ ያያይዙ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (pickedPhoto != null)
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: AppTheme.greenSuccess, size: 18),
                              SizedBox(width: 4),
                              Text('ፎቶ ተያይዟል', style: TextStyle(fontSize: 12, color: AppTheme.greenSuccess)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (titleCtrl.text.trim().isEmpty) return;

                                setDlgState(() => isSaving = true);
                                String? evidenceBase64;
                                String? evidenceName;
                                try {
                                  // The photo bytes are read here and sent
                                  // to the server with the record — the
                                  // dialog never claims a save before the
                                  // server confirms it.
                                  if (pickedPhoto != null) {
                                    final bytes =
                                        await pickedPhoto!.readAsBytes();
                                    evidenceBase64 = base64Encode(bytes);
                                    evidenceName = pickedPhoto!.name;
                                  }

                                  final act = UnplannedActivity(
                                    id: 'unplanned_${DateTime.now().millisecondsSinceEpoch}',
                                    departmentId: deptId,
                                    departmentName: deptName,
                                    title: titleCtrl.text.trim(),
                                    description: descCtrl.text.trim(),
                                    executionDate: dateCtrl.text.trim(),
                                    budgetUsed: budgetCtrl.text.trim(),
                                  );

                                  final res = await widget.onAddActivity(
                                    act,
                                    evidenceBase64: evidenceBase64,
                                    evidenceName: evidenceName,
                                  );
                                  if (!context.mounted) return;
                                  if (res['success'] == true) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ያልታቀደው የስራ ክንውን በተሳካ ሁኔታ ተመዝግቧል!'),
                                        backgroundColor: AppTheme.greenSuccess,
                                      ),
                                    );
                                  } else {
                                    // Server (or network) failed — the
                                    // dialog stays open, nothing is lost.
                                    setDlgState(() => isSaving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'ስራውን መመዝገብ አልተቻለም፦ ${res['message'] ?? 'እባክዎ እንደገና ይሞክሩ።'}'),
                                        backgroundColor: AppTheme.redDanger,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setDlgState(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('ስራውን መመዝገብ አልተቻለም፦ $e'),
                                      backgroundColor: AppTheme.redDanger,
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                              },
                        child: Text(isSaving ? 'በመላክ ላይ…' : 'መዝግብ እና ለፅ/ቤት ላክ'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 3),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = AuthService.isSuperAdmin;
    final currentDept = AuthService.currentDepartment;

    final visibleActivities = isSuper
        ? widget.activities
        : widget.activities.where((a) => a.departmentName.contains(currentDept?.shortName ?? '') || a.departmentId == currentDept?.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ያልታቀዱ ግን የተከናወኑ ስራዎች'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('ስራ መዝግብ'),
        backgroundColor: AppTheme.primaryMaroon,
        foregroundColor: Colors.white,
      ),
      body: visibleActivities.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'ምንም ያልታቀደ የተከናወነ ስራ አልተመዘገበም',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    if (widget.loadError != null) ...[
                      Text(
                        'ከሰርቨር መጫን አልተቻለም፦ ${widget.loadError}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.redDanger, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                    ],
                    const Text(
                      'በዓመታዊ እቅድ ውስጥ ያልነበረ ነገር ግን በድንገት የተከናወነ ስራ ሲኖር «ስራ መዝግብ» የሚለውን ተጭነው ያስገቡ።',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: visibleActivities.length,
              itemBuilder: (ctx, index) {
                final act = visibleActivities[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryMaroon.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                act.departmentName,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: act.status == 'በፅ/ቤት ጸድቋል' ? AppTheme.greenSuccess : AppTheme.secondaryGold,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                act.status,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          act.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (act.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(act.description, style: const TextStyle(fontSize: 12, height: 1.3)),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('ቀን፡ ${act.executionDate}', style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 14),
                            Icon(Icons.attach_money, size: 14, color: Colors.grey.shade600),
                            Text('ወጪ፡ ${act.budgetUsed} ብር', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        if (isSuper && act.status != 'በፅ/ቤት ጸድቋል') ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  // Server FIRST: approve only after the
                                  // server confirms — the local copy is
                                  // never mutated before the save.
                                  final updated =
                                      UnplannedActivity.fromJson({
                                    ...act.toJson(),
                                    'status': 'በፅ/ቤት ጸድቋል',
                                  });
                                  final res = await widget
                                      .onUpdateActivity(updated);
                                  if (!context.mounted) return;
                                  if (res['success'] == true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('ስራው በፅ/ቤት ጸድቋል!')),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'ስራውን ማጽደቅ አልተቻለም፦ ${res['message'] ?? 'እባክዎ እንደገና ይሞክሩ።'}'),
                                        backgroundColor: AppTheme.redDanger,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check, size: 16, color: AppTheme.greenSuccess),
                                label: const Text('አጽድቅ', style: TextStyle(color: AppTheme.greenSuccess)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
