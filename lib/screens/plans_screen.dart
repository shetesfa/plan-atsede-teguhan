import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/department.dart';
import '../models/plan_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/excel_importer.dart';
import '../services/offline_sync_service.dart';
import '../services/notification_service.dart';
import '../services/telegram_service.dart';
import '../theme/app_theme.dart';

class PlansScreen extends StatefulWidget {
  final List<PlanItem> plans;
  final Function(PlanItem updatedItem) onUpdatePlan;
  final Function(List<PlanItem> newPlans) onImportNewPlans;
  final String? initialDepartmentId;

  const PlansScreen({
    super.key,
    required this.plans,
    required this.onUpdatePlan,
    required this.onImportNewPlans,
    this.initialDepartmentId,
  });

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String selectedDeptId = 'all';
  String selectedStatusFilter = 'all'; // 'all', 'postponed', 'reported', 'completed', 'overdue'
  bool isTableView = true;

  /// M10፦ የመጨረሻው የአገልጋይ ዝርዝር-ማደስ ስህተት — "server አልተገኘም" ከ "እቅድ የለም"
  /// ለመለየት። null ማለት ስህተት የለም ማለት ነው።
  String? _serverError;


  @override
  void initState() {
    super.initState();
    final currentDept = AuthService.currentDepartment;
    if (!AuthService.isSuperAdmin && currentDept != null) {
      selectedDeptId = currentDept.id;
    } else if (widget.initialDepartmentId != null) {
      selectedDeptId = widget.initialDepartmentId!;
    }
    // C5: እቅዶች ሲጫኑ የአካባቢ ማሳሰቢያዎችን ማስያዝ (NotificationService init
    // በ main.dart ተደርጓል፤ ካልተዘጋጀ scheduleRemindersForPlans በዝምታ ይመለሳል)።
    NotificationService().scheduleRemindersForPlans(widget.plans);
  }

  @override
  void didUpdateWidget(covariant PlansScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plans != widget.plans) {
      // C5: ወላጅ አዲስ እቅዶች ሲያመጣ ማሳሰቢያዎችን እንደገና ማስያዝ (IDs
      // deterministic ስለሆኑ ተመሳሳይ ማሳሰቢያ አይደገምም)።
      NotificationService().scheduleRemindersForPlans(widget.plans);
    }
  }

  List<PlanItem> get filteredPlans {
    final currentDept = AuthService.currentDepartment;

    return widget.plans.where((p) {
      // 1. የክፍል ፍተሻ
      if (!AuthService.isSuperAdmin && currentDept != null) {
        if (!p.departmentName.contains(currentDept.shortName) && p.departmentId != currentDept.id) {
          return false;
        }
      } else if (selectedDeptId != 'all') {
        final dept = Department.allDepartments.firstWhere((d) => d.id == selectedDeptId);
        if (!p.departmentName.contains(dept.shortName) && p.departmentId != selectedDeptId) {
          return false;
        }
      }

      // 2. የሁኔታ/ሪፖርት ፍተሻ
      if (selectedStatusFilter == 'postponed') {
        return p.isPostponed;
      } else if (selectedStatusFilter == 'reported') {
        return p.hasReport || p.progressPercent > 0;
      } else if (selectedStatusFilter == 'completed') {
        return p.isCompleted;
      } else if (selectedStatusFilter == 'overdue') {
        return !p.isCompleted;
      }

      return true;
    }).toList();
  }

  Future<void> _pickExcelFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (files.isNotEmpty) {
      final bytes = await files.first.xFile.readAsBytes();
      final newPlans = await ExcelImporterService.loadPlans(fileBytes: bytes);
      if (newPlans.isNotEmpty) {
        widget.onImportNewPlans(newPlans);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${newPlans.length} እቅዶች ከኤክሴል በተሳካ ሁኔታ ገብተዋል!'),
              backgroundColor: AppTheme.greenSuccess,
            ),
          );
        }
      }
    }
  }

  // ── H5፦ ከመስመር ውጭ ወረፋ ማመሳከር ─────────────────────────────────────────
  // ከስኬታማ ለውጥ በኋላ ይጠራል። ስህተት ቢኖር አፕሉን በጭራሽ አያቋርጥም — ወረፋው
  // ተቀምጦ በሚቀጥለው ስኬታማ ጥሪ ይመሳከራል።
  Future<void> _trySyncPending() async {
    try {
      final result = await OfflineSyncService.syncPendingQueue('atsede_app_device');
      debugPrint('Offline sync result: $result');
    } catch (e) {
      debugPrint('Offline sync failed (queue kept, will retry later): $e');
    }
  }

  // ── M10፦ እቅዶችን ከአገልጋዩ እንደገና ማምጣት ───────────────────────────────────
  // fetchPlans() ስህተት ሲጥል "server አልተገኘም" እንጂ "እቅድ የለም" አይባልም።
  Future<bool> _refreshPlansFromServer() async {
    try {
      final remoteData = await ApiService().fetchPlans();
      if (!mounted) return false;
      setState(() => _serverError = null);
      final fetchedPlans =
          remoteData.map((d) => PlanItem.fromDbJson(d)).toList();
      widget.onImportNewPlans(fetchedPlans);
      // C5: ለተገኙት እቅዶች የአካባቢ ማሳሰቢያ ማስያዝ።
      NotificationService().scheduleRemindersForPlans(fetchedPlans);
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
      return false;
    } catch (e) {
      if (mounted) setState(() => _serverError = e.toString());
      return false;
    }
  }

  // ── H1(a)፦ አዲስ እቅድ መፍጠሪያ ሞዳል ────────────────────────────────────────
  void _showCreatePlanDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final execTimeController = TextEditingController();
    final isSuper = AuthService.isSuperAdmin;
    final currentDept = AuthService.currentDepartment;
    // ጽ/ቤት ካልሆነ እቅዱ ለራሱ ክፍል ብቻ ነው የሚፈጠረው (አገልጋዩም ያንኑ ያስገድዳል)።
    final deptChoices = isSuper
        ? Department.allDepartments.where((d) => !d.isSuperAdmin).toList()
        : (currentDept != null ? [currentDept] : <Department>[]);
    Department? selectedDept = deptChoices.isNotEmpty ? deptChoices.first : null;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_task, color: AppTheme.primaryMaroon),
                  SizedBox(width: 8),
                  Text('አዲስ እቅድ', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('የእቅዱ ርዕስ / ዋና ተግባር፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'ለምሳሌ፦ የመዝሙር ስልጠና ለአባላት',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('ክፍል፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<Department>(
                      value: selectedDept,
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      items: deptChoices
                          .map((d) => DropdownMenuItem(value: d, child: Text(d.name, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: isSuper ? (d) => setDialogState(() => selectedDept = d) : null,
                    ),
                    const SizedBox(height: 12),
                    const Text('የማስፈጸሚያ ጊዜ / ቀን፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: execTimeController,
                      decoration: const InputDecoration(
                        hintText: 'ለምሳሌ፦ ህዳር 15',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('ዝርዝር መግለጫ፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'እቅዱ ምን እንደሚያካትት በዝርዝር ይጻፉ...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ይቅር'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryMaroon, foregroundColor: Colors.white),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('እባክዎን የእቅዱን ርዕስ ያስገቡ!'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (selectedDept == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ክፍል አልተመረጠም!'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);

                          final payload = <String, dynamic>{
                            'department_id': selectedDept!.id,
                            'main_task': title,
                            'title': title,
                            'detail_task': descController.text.trim(),
                            'description': descController.text.trim(),
                            'execution_time': execTimeController.text.trim(),
                            'target_date': execTimeController.text.trim(),
                            'measurement': '',
                            'quantity': '',
                            'budget': '',
                            'remarks': '',
                            'progress_percent': 0,
                          };

                          final result = await ApiService().savePlan(payload);
                          if (!context.mounted) return;
                          Navigator.pop(ctx);

                          if (result['success'] == true) {
                            await _refreshPlansFromServer();
                            await _trySyncPending();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('አዲስ እቅድ በአገልጋዩ ላይ በተሳካ ሁኔታ ተመዝግቧል!'),
                                  backgroundColor: AppTheme.greenSuccess,
                                ),
                              );
                            }
                          } else {
                            // አገልጋዩ ካልተገኘ እቅዱ ከመስመር ውጭ ወረፋ ውስጥ ይቀመጣል — ሐሰተኛ
                            // "ተመዝግቧል" መልእክት በጭራሽ አይታይም (H1/H5)።
                            await OfflineSyncService.enqueueChange(
                              entityType: 'plan',
                              action: 'insert',
                              data: payload,
                              departmentId: selectedDept!.id,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('አገልጋዩ አልተገኘም — እቅዱ ከመስመር ውጭ ተቀምጧል፤ ኢንተርኔት ሲገኝ በራስ-ሰር ይላካል። (${result['message'] ?? ''})'),
                                  backgroundColor: Colors.orange.shade800,
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('እቅዱን መዝግብ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── H1(b)፦ እቅድ መሰረዣ (በማረጋገጫ) ────────────────────────────────────────
  Future<void> _deletePlan(PlanItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('እቅዱን መሰረዝ ይፈልጋሉ?', style: TextStyle(fontSize: 16)),
        content: Text(
          '«${item.detailTask.isNotEmpty ? item.detailTask : item.mainTask}»\n\nይህ እቅድ ከአገልጋዩ ላይ በቋሚነት ይሰረዛል።',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ይቅር')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('አዎ፣ ሰርዝ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await ApiService().deletePlan(item.id);
    if (!mounted) return;

    if (ok) {
      widget.onImportNewPlans(widget.plans.where((p) => p.id != item.id).toList());
      await _trySyncPending();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('እቅዱ ከአገልጋዩ ላይ ተሰርዟል።'), backgroundColor: AppTheme.greenSuccess),
      );
    } else {
      // መሰረዙ ካልተሳካ ለውጡ ከመስመር ውጭ ወረፋ ውስጥ ይቀመጣል፤ እቅዱ በአካባቢው አይጠፋም።
      await OfflineSyncService.enqueueChange(
        entityType: 'plan',
        action: 'delete',
        data: {'id': item.id},
        departmentId: item.departmentId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('አገልጋዩ አልተገኘም — የመሰረዝ ጥያቄው ከመስመር ውጭ ተቀምጧል፤ ኢንተርኔት ሲገኝ ይላካል።'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // 1. የክንውን ሪፖርት ማቅረቢያ ሞዳል (የተሰራበትን እና ያልተሰራበትን ምክንያት በዝርዝር መመዝገቢያ)
  void _showReportDialog(PlanItem item) {
    int currentPercent = item.progressPercent;
    final doneController = TextEditingController(text: item.reportDetails ?? '');
    final notDoneController = TextEditingController(text: item.notDoneDetails ?? item.reason);
    String? pickedImagePath = item.evidencePath;
    // በዚህ ክፍለ-ጊዜ የተመረጠ ፎቶ (XFile.readAsBytes() በሁሉም platform ይሰራል —
    // dart:io File መጠቀም በ web ላይ አይሰራም)።
    Uint8List? pickedImageBytes;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.assignment_turned_in, color: AppTheme.primaryMaroon),
                            SizedBox(width: 8),
                            Text(
                              'የእቅድ ክንውን ሪፖርት ማቅረቢያ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryMaroon,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      item.detailTask,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ክፍል፦ ${item.departmentName} | የማስፈጸሚያ ጊዜ፦ ${item.effectiveExecutionTime}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    // የክንውን መቶኛ ምርጫ
                    const Text('የአፈፃፀም ደረጃ (በመቶኛ)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [0, 25, 50, 75, 100].map((percent) {
                        final isSelected = currentPercent == percent;
                        return ChoiceChip(
                          label: Text('$percent%'),
                          selected: isSelected,
                          selectedColor: percent == 100 ? AppTheme.greenSuccess : AppTheme.secondaryGold,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => currentPercent = percent);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // የተከናወኑ ተግባራት ዝርዝር
                    const Text(
                      'የተከናወኑ ስራዎች ዝርዝር (ምን ተሰራ?)፦',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.greenSuccess),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: doneController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'የተሰሩትን ዋና ዋና ስራዎች እዚህ ይዘርዝሩ...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ያልተከናወኑ ስራዎች እና ምክንያታቸው (መቶኛው 100 ካልሆነ)
                    if (currentPercent < 100) ...[
                      const Text(
                        'ያልተከናወነ ነገር እና ያልተሰራበት ምክንያት፦',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.redDanger),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          'የበጀት እጥረት',
                          'የአባላት አለመገኘት',
                          'የቀን መደራረብ',
                          'የቁሳቁስ እጥረት',
                          'የፈቃድ መዘግየት',
                          'ከበዓላት ጋር መገጣጠም',
                        ].map((quickReason) {
                          return ActionChip(
                            label: Text(quickReason, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                if (notDoneController.text.isEmpty) {
                                  notDoneController.text = quickReason;
                                } else {
                                  notDoneController.text += '፣ $quickReason';
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notDoneController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'ያልተከናወኑትን እና ምክንያታቸውን እዚህ ይጻፉ...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(10),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // የፎቶ ማስረጃ
                    const Text('የፎቶ/ማስረጃ ማያያዣ፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              final bytes = await img.readAsBytes();
                              setModalState(() {
                                pickedImagePath = img.path;
                                pickedImageBytes = bytes;
                              });
                            }
                          },
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('ፎቶ ያያይዙ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (pickedImagePath != null)
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

                    // የማስረከቢያ እና ወደ ቴሌግራም መላኪያ አዝራር
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryMaroon,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);

                                final currentDept = AuthService.currentDepartment;
                                final isSuper = AuthService.isSuperAdmin;
                                final senderTitle = isSuper
                                    ? 'የጽ/ቤት ዋና ጸሐፊ'
                                    : '${currentDept?.shortName ?? item.departmentName} ኃላፊ';
                                final doneDetails = doneController.text.trim();
                                final notDoneDetails = notDoneController.text.trim();
                                final taskTitle = item.detailTask.isNotEmpty ? item.detailTask : item.mainTask;

                                // H1(c)፦ ሪፖርቱ መጀመሪያ ወደ አገልጋዩ (reports.php) ይላካል።
                                // "ተመዝግቧል" የሚለው መልእክት የሚታየው አገልጋዩ ካረጋገጠ በኋላ ብቻ ነው።
                                final reportPayload = <String, dynamic>{
                                  'plan_id': item.id,
                                  'department_id': item.departmentId,
                                  'title': taskTitle,
                                  // reports.php የተከናወነ ዝርዝር ባዶ ከሆነ 400 ይመልሳል፤
                                  // ስለዚህ ባዶ ከሆነ የአፈፃፀም ደረጃውን እንደ ማብራሪያ እንልካለን።
                                  'activities_completed': doneDetails.isNotEmpty
                                      ? doneDetails
                                      : 'የአፈፃፀም ደረጃ፦ $currentPercent%',
                                  'progress_percent': currentPercent,
                                  'challenges': notDoneDetails,
                                  'solutions_proposed': '',
                                  'status': 'submitted',
                                };

                                final result = await ApiService().submitReport(reportPayload);
                                final submitted = result['success'] == true;

                                // የአካባቢው ሁኔታ በሁለቱም መንገድ ይዘምናል (በስክሪኑ ላይ ይታይ) —
                                // ግን የስኬት መልእክቱ የሚወሰነው በአገልጋዩ መልስ ብቻ ነው።
                                item.progressPercent = currentPercent;
                                item.reportDetails = doneDetails;
                                item.notDoneDetails = notDoneDetails;
                                item.reason = notDoneDetails;
                                item.evidencePath = pickedImagePath;
                                item.reportSubmittedAt = DateTime.now();
                                item.submittedBy = senderTitle;
                                item.updatedAt = DateTime.now();

                                widget.onUpdatePlan(item);

                                if (submitted) {
                                  // ወደ ቴሌግራም ግሩፕ ይፋዊ ማሳወቂያ መላክ
                                  await TelegramService.sendPlanReportNotice(
                                    deptName: item.departmentName,
                                    senderTitle: senderTitle,
                                    taskTitle: taskTitle,
                                    progressPercent: currentPercent,
                                    doneDetails: doneDetails,
                                    notDoneDetails: notDoneDetails.isEmpty ? null : notDoneDetails,
                                  );

                                  // H1(d)፦ የፎቶ ማስረጃ ከተያያዘ ወደ ቴሌግራም ይላካል
                                  if (pickedImageBytes != null) {
                                    try {
                                      await TelegramService.sendPhoto(
                                        imageBytes: pickedImageBytes!,
                                        fileName: 'evidence_${item.id}.jpg',
                                        caption: '📷 የ«$taskTitle» ሪፖርት ማስረጃ — $currentPercent%',
                                      );
                                    } catch (e) {
                                      debugPrint('Evidence photo send failed: $e');
                                    }
                                  }

                                  await _trySyncPending();

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('ሪፖርቱ ለጽ/ቤት ተመዝግቧል፤ ወደ ቴሌግራም ግሩፕም ተልኳል!'),
                                        backgroundColor: AppTheme.greenSuccess,
                                      ),
                                    );
                                  }
                                } else {
                                  // አገልጋዩ ካልተገኘ ሪፖርቱ ከመስመር ውጭ ወረፋ ውስጥ ይቀመጣል
                                  // እና ሐሰተኛ "ተመዝግቧል" መልእክት በጭራሽ አይታይም (H1/H5)።
                                  await OfflineSyncService.enqueueChange(
                                    entityType: 'report',
                                    action: 'insert',
                                    data: reportPayload,
                                    departmentId: item.departmentId,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('አገልጋዩ አልተገኘም — ሪፖርቱ ከመስመር ውጭ ተቀምጧል፤ ኢንተርኔት ሲገኝ በራስ-ሰር ይላካል። (${result['message'] ?? ''})'),
                                        backgroundColor: Colors.orange.shade800,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text(
                          'ሪፖርቱን መዝግብ እና ለጽ/ቤት / ቴሌግራም ላክ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
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

  // 2. እቅድ ማስተላለፊያ ሞዳል (Postpone / Reschedule Plan)
  void _showPostponeDialog(PlanItem item) {
    final newDateController = TextEditingController(text: item.postponedDate ?? '');
    final reasonController = TextEditingController(text: item.postponeReason ?? '');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.update, color: Colors.deepOrange),
                            SizedBox(width: 8),
                            Text(
                              'እቅድ ማስተላለፊያ (Postpone / Reschedule)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      item.detailTask,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ክፍል፦ ${item.departmentName}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),

                    // የቀደመው ቀን
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'የቀደመው የማስፈጸሚያ ጊዜ፦ ${item.executionTime}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // አዲሱ የተላለፈበት ቀን
                    const Text(
                      'አዲሱ የተላለፈበት ቀን (New Target Date)፦',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newDateController,
                      decoration: InputDecoration(
                        hintText: 'ለምሳሌ፦ ህዳር 15 ወይም ታህሳስ 1',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (val) {
                            setModalState(() => newDateController.text = val);
                          },
                          itemBuilder: (ctx) => [
                            'ጥቅምት 30',
                            'ህዳር 15',
                            'ህዳር 30',
                            'ታህሳስ 15',
                            'ታህሳስ 30',
                            'ጥር 15',
                            'የካቲት 15',
                          ].map((d) => PopupMenuItem(value: d, child: Text(d))).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // የማስተላለፊያ ምክንያት
                    const Text(
                      'የማስተላለፊያ ምክንያት (ምክንያቱ ለምን ተላለፈ?)፦',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        'የበጀት ዝግጅት ስለሚያስፈልግ',
                        'የቀን መደራረብ ስላጋጠመ',
                        'ከበዓላት ዝግጅት ጋር በማያያዝ',
                        'አስፈላጊ ግብዓቶችን ለማሟላት',
                        'የአባላት ስምምነት ስለተደረገ',
                      ].map((quickR) {
                        return ActionChip(
                          label: Text(quickR, style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            setModalState(() {
                              reasonController.text = quickR;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'ምክንያቱን በዝርዝር እዚህ ይጻፉ...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // የማስተላለፊያ አዝራር
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final newDate = newDateController.text.trim();
                                if (newDate.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('እባክዎን አዲሱን ቀን ያስገቡ!'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }

                                setModalState(() => isSubmitting = true);

                                final currentDept = AuthService.currentDepartment;
                                final isSuper = AuthService.isSuperAdmin;
                                final senderTitle = isSuper
                                    ? 'የጽ/ቤት ዋና ጸሐፊ'
                                    : '${currentDept?.shortName ?? item.departmentName} ኃላፊ';
                                final postponeReason = reasonController.text.trim();

                                // H1(e)፦ ማስተላለፉ መጀመሪያ ወደ አገልጋዩ (plans.php) ይቀመጣል።
                                // plans.php ያለውን እቅድ ሲያሻሽል ሁሉንም መስኮች ስለሚተካ
                                // ያሉትን እሴቶች ሁሉ እንልካለን — አለበለዚያ ይጠፋሉ።
                                final planPayload = <String, dynamic>{
                                  'id': item.id,
                                  'department_id': item.departmentId,
                                  'sub_department': item.subDepartment,
                                  'main_task': item.mainTask,
                                  'detail_task': item.detailTask,
                                  'measurement': item.measurement,
                                  'quantity': item.quantity,
                                  'execution_time': newDate,
                                  'target_date': newDate,
                                  'budget': item.budget,
                                  'remarks': postponeReason.isNotEmpty ? postponeReason : item.remarks,
                                  'progress_percent': item.progressPercent,
                                };

                                final result = await ApiService().savePlan(planPayload);
                                final saved = result['success'] == true;

                                item.postponedDate = newDate;
                                item.postponeReason = postponeReason;
                                item.updatedAt = DateTime.now();

                                widget.onUpdatePlan(item);

                                if (saved) {
                                  // ወደ ቴሌግራም ግሩፕ ማሳወቂያ መላክ
                                  await TelegramService.sendPlanPostponedNotice(
                                    deptName: item.departmentName,
                                    senderTitle: senderTitle,
                                    taskTitle: item.detailTask.isNotEmpty ? item.detailTask : item.mainTask,
                                    originalDate: item.executionTime,
                                    newDate: newDate,
                                    reason: postponeReason.isNotEmpty ? postponeReason : 'ምክንያት አልተገለጸም',
                                  );

                                  await _trySyncPending();

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('እቅዱ ወደ $newDate ተላልፏል፤ ለጽ/ቤት እና ቴሌግራም ተልኳል!'),
                                        backgroundColor: AppTheme.greenSuccess,
                                      ),
                                    );
                                  }
                                } else {
                                  // አገልጋዩ ካልተገኘ ማስተላለፉ ከመስመር ውጭ ወረፋ ውስጥ ይቀመጣል፤
                                  // ሐሰተኛ "ተላልፏል" መልእክት በጭራሽ አይታይም።
                                  await OfflineSyncService.enqueueChange(
                                    entityType: 'plan',
                                    action: 'update',
                                    data: planPayload,
                                    departmentId: item.departmentId,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('አገልጋዩ አልተገኘም — ማስተላለፉ ከመስመር ውጭ ተቀምጧል፤ ኢንተርኔት ሲገኝ ይላካል። (${result['message'] ?? ''})'),
                                        backgroundColor: Colors.orange.shade800,
                                        duration: const Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.schedule_send),
                        label: const Text(
                          'እቅዱን አስተላልፍ እና ለጽ/ቤት/ቴሌግራም አሳውቅ',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final isSuper = AuthService.isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('የክፍሎች ዝርዝር እቅድ'),
        actions: [
          IconButton(
            icon: Icon(isTableView ? Icons.grid_view : Icons.table_chart),
            tooltip: isTableView ? 'ወደ ካርድ እይታ ቀይር' : 'ወደ ሰንጠረዥ እይታ ቀይር',
            onPressed: () => setState(() => isTableView = !isTableView),
          ),
          IconButton(
            icon: const Icon(Icons.add_task),
            tooltip: 'አዲስ እቅድ',
            onPressed: _showCreatePlanDialog,
          ),
          if (isSuper)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'አዲስ የኤክሴል እቅድ ጫን',
              onPressed: _pickExcelFile,
            ),
        ],
      ),
      body: Column(
        children: [
          // ፅ/ቤት ከሆነ የክፍሎች ማጣሪያ ባር
          if (isSuper)
            Container(
              height: 48,
              color: Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [
                  _buildDeptTab('all', 'ሁሉም ክፍሎች (${widget.plans.length})'),
                  ...Department.allDepartments.map((d) {
                    final count = widget.plans.where((p) => p.departmentName.contains(d.shortName) || p.departmentId == d.id).length;
                    return _buildDeptTab(d.id, '${d.shortName} ($count)');
                  }),
                ],
              ),
            ),

          // የሁኔታ ማጣሪያ ባር (ሁሉም፣ የተላለፉ፣ ሪፖርት የቀረበባቸው፣ የተጠናቀቁ)
          Container(
            height: 42,
            color: Colors.grey.shade50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _buildStatusChip('all', 'ሁሉም (${filteredPlans.length})', Icons.list),
                _buildStatusChip('postponed', '📅 የተላለፉ እቅዶች', Icons.update, color: Colors.deepOrange),
                _buildStatusChip('reported', '📋 ሪፖርት የቀረበባቸው', Icons.assignment_turned_in, color: AppTheme.greenSuccess),
                _buildStatusChip('completed', '✅ 100% የተጠናቀቁ', Icons.check_circle, color: Colors.blue),
                _buildStatusChip('overdue', '⏳ ክትትል የሚሹ', Icons.warning_amber_rounded, color: Colors.red),
              ],
            ),
          ),

          // የእይታ መረጃ ባነር
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AppTheme.lightGold,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isTableView ? 'የኤክሴል ሰንጠረዥ እይታ (ወደ ግራ እና ቀኝ ያሸብልሉ)' : 'የካርድ ዝርዝር እይታ',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                ),
                Text('${filteredPlans.length} እቅዶች', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),

          // ይዘት — M10፦ አገልጋዩ ካልተገኘ "እቅድ የለም" ሳይሆን "server አልተገኘም" ይታያል
          Expanded(
            child: filteredPlans.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _serverError != null ? Icons.cloud_off : Icons.inbox_outlined,
                            size: 40,
                            color: _serverError != null ? Colors.red.shade400 : Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _serverError != null
                                ? 'አገልጋዩ አልተገኘም፦ $_serverError'
                                : 'በተመረጠው መስፈርት መሰረት ምንም እቅድ አልተገኘም',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (_serverError != null) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _refreshPlansFromServer,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('እንደገና ሞክር'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryMaroon,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : (isTableView ? _buildExcelTableView() : _buildCardsView()),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String filterKey, String label, IconData icon, {Color? color}) {
    final isSelected = selectedStatusFilter == filterKey;
    final activeColor = color ?? AppTheme.primaryMaroon;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: Icon(icon, size: 14, color: isSelected ? Colors.white : activeColor),
        label: Text(label),
        selected: isSelected,
        selectedColor: activeColor,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (val) {
          setState(() {
            selectedStatusFilter = val ? filterKey : 'all';
          });
        },
      ),
    );
  }

  // 1. የኤክሴል ሰንጠረዥ እይታ
  Widget _buildExcelTableView() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF530A14)),
          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 64,
          columnSpacing: 14,
          border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
          columns: const [
            DataColumn(label: Text('ተ.ቁ')),
            DataColumn(label: Text('ክፍል')),
            DataColumn(label: Text('ንዑስ ክፍል')),
            DataColumn(label: Text('ዝርዝር ተግባር')),
            DataColumn(label: Text('የማስፈጸሚያ ጊዜ')),
            DataColumn(label: Text('ሁኔታ / ማስተላለፍ')),
            DataColumn(label: Text('ደረጃ')),
            DataColumn(label: Text('እርምጃዎች')),
          ],
          rows: List.generate(filteredPlans.length, (index) {
            final item = filteredPlans[index];

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (item.isCompleted) return Colors.green.withAlpha(20);
                if (item.isPostponed) return Colors.orange.withAlpha(25);
                if (index.isOdd) return Colors.grey.withAlpha(15);
                return null;
              }),
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(
                  Text(
                    item.departmentName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                DataCell(Text(item.subDepartment, style: const TextStyle(fontSize: 11))),
                DataCell(
                  SizedBox(
                    width: 250,
                    child: Text(
                      item.detailTask.isNotEmpty ? item.detailTask : item.mainTask,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item.executionTime, style: const TextStyle(fontSize: 11)),
                      if (item.isPostponed)
                        Text(
                          '👉 የተላለፈ፦ ${item.postponedDate}',
                          style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                DataCell(
                  item.isPostponed
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('ተላልፏል', style: TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                        )
                      : (item.hasReport
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ሪፖርት ቀርቧል', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                            )
                          : const Text('-', style: TextStyle(color: Colors.grey))),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isCompleted
                          ? AppTheme.greenSuccess
                          : (item.isInProgress ? AppTheme.secondaryGold : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${item.progressPercent}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.assignment_turned_in, size: 18, color: AppTheme.primaryMaroon),
                        tooltip: 'ሪፖርት ስጥ',
                        onPressed: () => _showReportDialog(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.update, size: 18, color: Colors.deepOrange),
                        tooltip: 'እቅድ አስተላልፍ (ቀን ቀይር)',
                        onPressed: () => _showPostponeDialog(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'እቅድ ሰርዝ',
                        onPressed: () => _deletePlan(item),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // 2. የካርድ እይታ
  Widget _buildCardsView() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredPlans.length,
      itemBuilder: (ctx, index) {
        final item = filteredPlans[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: item.isPostponed ? 2 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: item.isPostponed
                  ? Colors.deepOrange.shade300
                  : (item.isCompleted ? Colors.green.shade300 : Colors.grey.shade200),
              width: item.isPostponed ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.departmentName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (item.isPostponed) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.update, size: 12, color: Colors.deepOrange),
                                      SizedBox(width: 3),
                                      Text(
                                        'ተላልፏል',
                                        style: TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (item.hasReport) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '📋 ሪፖርት አለው',
                                    style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.detailTask,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          if (item.mainTask != item.detailTask) ...[
                            const SizedBox(height: 3),
                            Text(
                              'ዐቢይ ተግባር፦ ${item.mainTask}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.isCompleted
                            ? AppTheme.greenSuccess
                            : (item.isInProgress ? AppTheme.secondaryGold : Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.progressPercent}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // የማስፈጸሚያ ጊዜ እና የተላለፈበት ቀን
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'የማስፈጸሚያ ጊዜ፦ ${item.executionTime}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                if (item.isPostponed) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.deepOrange.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_forward, size: 14, color: Colors.deepOrange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'የተላለፈበት አዲስ ቀን፦ ${item.postponedDate} (${item.postponeReason ?? "ምክንያት አልተገለጸም"})',
                            style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (item.reportDetails != null && item.reportDetails!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'የተከናወነ፦ ${item.reportDetails}',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade900),
                    ),
                  ),
                ],

                if (item.notDoneDetails != null && item.notDoneDetails!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ያልተከናወነ እና ምክንያት፦ ${item.notDoneDetails}',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 6),

                // እርምጃዎች (ሪፖርት ስጥ እና ቀን ቀይር)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () => _deletePlan(item),
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      tooltip: 'እቅድ ሰርዝ',
                    ),
                    TextButton.icon(
                      onPressed: () => _showPostponeDialog(item),
                      icon: const Icon(Icons.update, size: 15, color: Colors.deepOrange),
                      label: const Text('ቀን ቀይር / አስተላልፍ', style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showReportDialog(item),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryMaroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: const Icon(Icons.assignment_turned_in, size: 15),
                      label: const Text('ሪፖርት ስጥ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeptTab(String id, String label) {
    final isSelected = selectedDeptId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppTheme.primaryMaroon,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (val) {
          if (val) setState(() => selectedDeptId = id);
        },
      ),
    );
  }
}
