import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/department.dart';
import '../models/unplanned_activity.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class UnplannedActivitiesScreen extends StatefulWidget {
  final List<UnplannedActivity> activities;
  final Function(UnplannedActivity newActivity) onAddActivity;
  final Function(UnplannedActivity updatedActivity) onUpdateActivity;

  const UnplannedActivitiesScreen({
    super.key,
    required this.activities,
    required this.onAddActivity,
    required this.onUpdateActivity,
  });

  @override
  State<UnplannedActivitiesScreen> createState() => _UnplannedActivitiesScreenState();
}

class _UnplannedActivitiesScreenState extends State<UnplannedActivitiesScreen> {
  void _showAddDialog() {
    final currentDept = AuthService.currentDepartment;
    String deptName = currentDept?.name ?? 'ልማትና በጎ አድራጎት ክፍል';
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: '15/02/2019 ዓ.ም');
    final budgetCtrl = TextEditingController(text: '0');
    String? pickedPhotoPath;

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
                          if (val != null) setDlgState(() => deptName = val);
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    _buildField('የስራው ርዕስ (ግዴታ)፡', titleCtrl),
                    const SizedBox(height: 10),
                    _buildField('የክንውን ቀን፡', dateCtrl),
                    const SizedBox(height: 10),
                    _buildField('የስራው ዝርዝር መግለጫ፡', descCtrl, maxLines: 3),
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
                              setDlgState(() => pickedPhotoPath = img.path);
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
                        if (pickedPhotoPath != null)
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
                        onPressed: () {
                          if (titleCtrl.text.trim().isEmpty) return;

                          final act = UnplannedActivity(
                            id: 'unplanned_${DateTime.now().millisecondsSinceEpoch}',
                            departmentId: currentDept?.id ?? 'development',
                            departmentName: deptName,
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            executionDate: dateCtrl.text.trim(),
                            budgetUsed: budgetCtrl.text.trim(),
                            evidencePath: pickedPhotoPath,
                          );

                          widget.onAddActivity(act);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ያልታቀደው የስራ ክንውን በተሳካ ሁኔታ ተመዝግቧል!'),
                              backgroundColor: AppTheme.greenSuccess,
                            ),
                          );
                        },
                        child: const Text('መዝግብ እና ለፅ/ቤት ላክ'),
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

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 3),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                                onPressed: () {
                                  act.status = 'በፅ/ቤት ጸድቋል';
                                  widget.onUpdateActivity(act);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ስራው በፅ/ቤት ጸድቋል!')),
                                  );
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
