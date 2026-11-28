import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/department.dart';
import '../models/plan_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/excel_importer.dart';
import '../services/file_download.dart';
import '../services/office_export_service.dart';
import '../services/offline_sync_service.dart';
import '../services/notification_service.dart';
import '../services/telegram_service.dart';
import '../theme/app_theme.dart';
import '../utils/ethiopian_date_display.dart';

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
  /// Month view (2026-11-25): -1 = all months, else 0-12 index into
  /// ethiopianMonths13. Defaults to the month we are in (ህዳር).
  int selectedMonthIndex = -1;
  bool isTableView = true;

  // PR #46: visible horizontal scrollbar for the wide plans table, so
  // the Actions column is reachable without wheel-scrolling blind.
  final ScrollController _tableScrollController = ScrollController();

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  /// M10፦ የመጨረሻው የአገልጋይ ዝርዝር-ማደስ ስህተት — "server አልተገኘም" ከ "እቅድ የለም"
  /// ለመለየት። null ማለት ስህተት የለም ማለት ነው።
  String? _serverError;

  // 2026-11-28: every visible report, grouped by plan, so each plan
  // card can show the office decision (status) and the office comment
  // (office_feedback) on its latest report. Same pattern as the
  // calendar screen. The server scopes the list to the user's own
  // department (office / control see all).
  Map<String, List<Map<String, dynamic>>> _reportsByPlan = {};

  /// Load all visible reports once. A failure is silent — the card
  /// simply shows no office chip.
  Future<void> _loadReports() async {
    try {
      final data = await ApiService().getReports();
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final r in data) {
        final planId = (r['plan_id'] ?? '').toString();
        if (planId.isEmpty) continue;
        grouped.putIfAbsent(planId, () => []).add(r);
      }
      if (mounted) setState(() => _reportsByPlan = grouped);
    } catch (_) {}
  }

  /// The latest report of [item] (by occurrence date, then created_at).
  Map<String, dynamic>? _latestReport(PlanItem item) {
    final list = _reportsByPlan[item.id];
    if (list == null || list.isEmpty) return null;
    var best = list.first;
    var bestKey = _reportSortKey(best);
    for (final r in list.skip(1)) {
      final key = _reportSortKey(r);
      if (key.compareTo(bestKey) > 0) {
        best = r;
        bestKey = key;
      }
    }
    return best;
  }

  String _reportSortKey(Map<String, dynamic> r) =>
      '${(r['occurrence_date'] ?? '').toString()}|${(r['created_at'] ?? '').toString()}';

  /// Office decision colour — the exact mapping the Office Review
  /// screen uses (office_reports_screen.dart).
  Color _officeStatusColor(String status) {
    if (status == 'approved') return AppTheme.greenSuccess;
    if (status == 'revision_requested') return Colors.orange;
    if (status == 'rejected') return AppTheme.redDanger;
    if (status == 'under_review') return Colors.purple;
    return Colors.blue;
  }

  /// Office decision label — the exact mapping the Office Review
  /// screen uses (office_reports_screen.dart).
  String _officeStatusLabel(String status) {
    if (status == 'approved') return 'የጸደቀ';
    if (status == 'revision_requested') return 'ማሻሻያ የተጠየቀበት';
    if (status == 'rejected') return 'ውድቅ የተደረገ';
    if (status == 'under_review') return 'በግምገማ ላይ';
    return 'የቀረበ';
  }

  /// Office-decision status chip, same style as Office Review.
  Widget _buildOfficeStatusChip(String status) {
    final color = _officeStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        _officeStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    final currentDept = AuthService.currentDepartment;
    // 2026-11-26: the control department (can_view_all) sees all
    // departments — do not force its own department here.
    if (!AuthService.isSuperAdmin && !AuthService.canViewAll && currentDept != null) {
      selectedDeptId = currentDept.id;
    } else if (widget.initialDepartmentId != null) {
      selectedDeptId = widget.initialDepartmentId!;
    }
    // C5: እቅዶች ሲጫኑ የአካባቢ ማሳሰቢያዎችን ማስያዝ (NotificationService init
    // በ main.dart ተደርጓል፤ ካልተዘጋጀ scheduleRemindersForPlans በዝምታ ይመለሳል)።
    NotificationService().scheduleRemindersForPlans(widget.plans);
    // Month view: open on the month we are in.
    selectedMonthIndex = currentEthiopianMonthIndex();
    // 2026-11-28: load the reports once, so each plan card can show
    // the office decision + comment on its latest report.
    _loadReports();
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

  /// Plans after the department filter only (month chips count these).
  List<PlanItem> get _deptFilteredPlans {
    final currentDept = AuthService.currentDepartment;
    return widget.plans.where((p) {
      // 2026-11-26: the control department (can_view_all) sees all
      // departments — view-only, like the office.
      if (!AuthService.isSuperAdmin && !AuthService.canViewAll && currentDept != null) {
        if (!p.departmentName.contains(currentDept.shortName) && p.departmentId != currentDept.id) {
          return false;
        }
      } else if (selectedDeptId != 'all') {
        final dept = Department.allDepartments.firstWhere((d) => d.id == selectedDeptId);
        if (!p.departmentName.contains(dept.shortName) && p.departmentId != selectedDeptId) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<PlanItem> get filteredPlans {
    final filtered = _deptFilteredPlans.where((p) {
      // 2. የሁኔታ/ሪፖርት ፍተሻ
      if (selectedStatusFilter == 'postponed') {
        return p.isPostponed;
      } else if (selectedStatusFilter == 'reported') {
        return p.hasReport || p.progressPercent > 0;
      } else if (selectedStatusFilter == 'completed') {
        return p.isCompleted;
      } else if (selectedStatusFilter == 'overdue') {
        // Audit fix 2026-11-25: overdue = real due date passed with no
        // report (was: every plan that is not completed).
        return p.isOverdue;
      }

      return true;
    }).where((p) {
      // 3. የወር ፍተሻ (2026-11-25): plan seen by the month it is DUE in.
      if (selectedMonthIndex < 0) return true;
      final dueMonth = dueEthiopianMonthName(
        dueDateEthiopian: p.dueDateEthiopian,
        dueDate: p.dueDate,
      );
      return dueMonth == ethiopianMonths13[selectedMonthIndex];
    }).toList();

    // Month view: earliest due date first, plans without a due date last.
    filtered.sort((a, b) {
      final da = a.dueDate;
      final db = b.dueDate;
      if (da == null && db == null) return a.id.compareTo(b.id);
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return filtered;
  }

  Future<void> _pickExcelFile() async {
    // PR #46: the file picker opens with no visible feedback, so the
    // button looked dead while the picker was opening.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('የኤክሴል ፋይል ይምረጡ…'),
          duration: Duration(seconds: 3),
        ),
      );
    }
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

  // እቅዶችን ወደ Excel አውርድ — PR #46 (2026-11-28).
  // The AppBar used to show only an Excel IMPORT icon (upload_file);
  // the export generator (OfficeExportService) existed but was never
  // wired to any button, so the header looked like it had a dead
  // export icon. This exports the currently filtered plans and
  // downloads the file for real (web) or saves it (mobile).
  Future<void> _exportPlansToExcel() async {
    if (filteredPlans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ለማውረድ እቅድ የለም!')),
      );
      return;
    }
    try {
      final bytes = OfficeExportService.generateExcelFile(
        plans: filteredPlans,
        sheetName: 'እቅዶች',
      );
      final ok = await downloadBytes(
        bytes: bytes,
        fileName: 'የክፍሎች_እቅዶች.xlsx',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'የኤክሴል ፋይሉ ወርዷል (${filteredPlans.length} እቅዶች)'
                : 'የኤክሴል ፋይሉን ማውረድ አልተቻለም!',
          ),
          backgroundColor:
              ok ? AppTheme.greenSuccess : AppTheme.redDanger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('የኤክሴል ፋይሉን ማመንጨት አልተቻለም: $e'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
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
      // 2026-11-28: plans refreshed — reload the reports too, so the
      // office chips stay in step with the plan list.
      _loadReports();
      // ከመስመር ውጭ ሲሆን እቅዶቹ ከዚህ ካሽ ይታያሉ — ካሹን አዘምን።
      await OfflineSyncService.cachePlans(
          AuthService.currentDepartment?.id ?? 'admin', remoteData);
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

  // ── H1(a)፦ አዲስ እቅድ መፍጠሪያ / ያለውን እቅድ ማሻሻያ (Edit) ሞዳል ──────────────
  // PR #46 (2026-11-28): there was no edit control anywhere. The same
  // dialog now opens pre-filled for editing and saves through the
  // savePlan upsert the server already supports. Editing sends the FULL
  // plan payload (like the postpone flow) because plans.php replaces all
  // fields on update — including the postpone state, so editing a
  // postponed plan does not silently clear its postpone status.
  void _showCreatePlanDialog({PlanItem? existing}) {
    final isEdit = existing != null;
    final titleController = TextEditingController(
      text: isEdit ? existing.mainTask : '',
    );
    final descController = TextEditingController(
      text: isEdit ? existing.detailTask : '',
    );
    final execTimeController = TextEditingController(
      text: isEdit ? existing.executionTime : '',
    );
    final isSuper = AuthService.isSuperAdmin;
    final currentDept = AuthService.currentDepartment;
    // ጽ/ቤት ካልሆነ እቅዱ ለራሱ ክፍል ብቻ ነው የሚፈጠረው (አገልጋዩም ያንኑ ያስገድዳል)።
    // In edit mode the department is locked: a plan never changes owner.
    final deptChoices = isEdit
        ? <Department>[
            Department.allDepartments.firstWhere(
              (d) => d.id == existing.departmentId,
              orElse: () => Department.allDepartments.first,
            ),
          ]
        : isSuper
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
              title: Row(
                children: [
                  Icon(
                    isEdit ? Icons.edit : Icons.add_task,
                    color: AppTheme.primaryMaroon,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEdit ? 'እቅዱን አስተካክል' : 'አዲስ እቅድ',
                    style: const TextStyle(fontSize: 16),
                  ),
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
                      onChanged: isEdit
                          ? null
                          : isSuper
                              ? (d) => setDialogState(() => selectedDept = d)
                              : null,
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
                          if (isEdit) {
                            // Full payload: plans.php replaces ALL fields
                            // on update, so every unchanged field must be
                            // sent back — otherwise the edit would blank
                            // budget/remarks/months and clear a postpone.
                            // (status/priority/version are left out on
                            // purpose: the server derives status from
                            // progress and defaults priority, exactly as
                            // the postpone flow already does.)
                            payload.addAll({
                              'id': existing.id,
                              'sub_department': existing.subDepartment,
                              'measurement': existing.measurement,
                              'quantity': existing.quantity,
                              'budget': existing.budget,
                              'remarks': existing.remarks,
                              'months': existing.months,
                              'progress_percent': existing.progressPercent,
                              'is_postponed': existing.isPostponed,
                              'postponed_date': existing.postponedDate,
                              'postpone_reason': existing.postponeReason,
                              'original_execution_time':
                                  existing.originalExecutionTime,
                            });
                          }

                          final result = await ApiService().savePlan(payload);
                          if (!context.mounted) return;
                          Navigator.pop(ctx);

                          if (result['success'] == true) {
                            await _refreshPlansFromServer();
                            await _trySyncPending();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isEdit
                                        ? 'እቅዱ ተስተካክሏል!'
                                        : 'አዲስ እቅድ በአገልጋዩ ላይ በተሳካ ሁኔታ ተመዝግቧል!',
                                  ),
                                  backgroundColor: AppTheme.greenSuccess,
                                ),
                              );
                            }
                          } else {
                            // አገልጋዩ ካልተገኘ እቅዱ ከመስመር ውጭ ወረፋ ውስጥ ይቀመጣል — ሐሰተኛ
                            // "ተመዝግቧል" መልእክት በጭራሽ አይታይም (H1/H5)።
                            await OfflineSyncService.enqueueChange(
                              entityType: 'plan',
                              action: isEdit ? 'update' : 'insert',
                              data: payload,
                              departmentId: selectedDept!.id,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('አገልጋዩ አልተገኘም — እቅዱ offline ተቀምጧል፤ ኢንተርኔት ሲገኝ በራስ-ሰር ይላካል። (${result['message'] ?? ''})'),
                                  backgroundColor: Colors.orange.shade800,
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isEdit ? 'ለውጦቹን አስቀምጥ' : 'እቅዱን መዝግብ'),
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
          content: Text('አገልጋዩ አልተገኘም — የመሰረዝ ጥያቄው offline ተቀምጧል፤ ኢንተርኔት ሲገኝ ይላካል።'),
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
    // 2026-11-26: many attachments — images + documents (pdf/doc/docx/
    // xls/xlsx). Bytes are kept in memory (XFile.readAsBytes() works on
    // all platforms — dart:io File does not work on web).
    final List<_PickedAttachment> pickedAttachments = [];
    bool isSubmitting = false;
    // 2026-11-26 (per-occurrence): the exact date this report belongs
    // to — the plan's due date when known, else today. The user can
    // pick any week/date (weekly / 2-week plans).
    DateTime occurrenceDate = item.dueDate ?? DateTime.now();

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
                    const SizedBox(height: 10),

                    // 2026-11-26 (per-occurrence): which exact week/date
                    // is this report for?
                    Row(
                      children: [
                        const Text('የሪፖርት ቀን፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: occurrenceDate,
                              firstDate: DateTime(2025, 9, 11),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setModalState(() => occurrenceDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(formatEthiopianDate(occurrenceDate)),
                        ),
                      ],
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

                    // የፎቶ/የሰነድ ማስረጃዎች (ብዙ ፋይሎች)
                    const Text('የፎቶ/የሰነድ ማስረጃዎች (ብዙ ፋይሎች)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'xls', 'xlsx'],
                            );
                            if (picked.isEmpty) return;
                            final List<_PickedAttachment> added = [];
                            final List<String> skipped = [];
                            int totalBytes = pickedAttachments.fold<int>(0, (s, a) => s + a.bytes.length);
                            for (final f in picked) {
                              final bytes = await f.xFile.readAsBytes();
                              // የአገልጋዩ ገደብ፦ በአንድ ፋይል 10MB፣ ጠቅላላ 20MB።
                              if (bytes.length > 10 * 1024 * 1024) {
                                skipped.add(f.name);
                                continue;
                              }
                              if (totalBytes + bytes.length > 20 * 1024 * 1024) {
                                skipped.add(f.name);
                                continue;
                              }
                              totalBytes += bytes.length;
                              added.add(_PickedAttachment(name: f.name, mime: _mimeForFile(f.name), bytes: bytes));
                            }
                            setModalState(() => pickedAttachments.addAll(added));
                            if (skipped.isNotEmpty && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('ከ 10MB በላይ ወይም ጠቅላላ ከ 20MB በላይ የሆኑ ፋይሎች አልተጨመሩም፦ ${skipped.join('፣ ')}'),
                                  backgroundColor: Colors.orange.shade800,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: const Text('ፋይሎች ያያይዙ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (pickedAttachments.isNotEmpty)
                          Text(
                            '${pickedAttachments.length} ፋይል${pickedAttachments.length > 1 ? 'ዎች' : ''} ተያይዟል',
                            style: const TextStyle(fontSize: 12, color: AppTheme.greenSuccess),
                          ),
                      ],
                    ),
                    if (pickedAttachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...pickedAttachments.map((att) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(att.isImage ? Icons.image : Icons.insert_drive_file, size: 18, color: AppTheme.primaryMaroon),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${att.name} (${att.sizeLabel})',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // PR #46: the remove button had zero
                                // padding + empty constraints — a ~18px
                                // hit target, so taps just off-centre
                                // missed silently. Full 48px target now.
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: 'አባሪ አስወግድ',
                                  onPressed: () => setModalState(() => pickedAttachments.remove(att)),
                                ),
                              ],
                            ),
                          )),
                    ],
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
                                  // 2026-11-26 (per-occurrence): the exact
                                  // date this report belongs to.
                                  'occurrence_date': formatGregorianDateYmd(occurrenceDate),
                                  // 2026-11-26: many attachments — the
                                  // server stores each in report_attachments.
                                  if (pickedAttachments.isNotEmpty)
                                    'attachments': pickedAttachments
                                        .map((a) => {'name': a.name, 'mime': a.mime, 'data': base64Encode(a.bytes)})
                                        .toList(),
                                };

                                final result = await ApiService().submitReport(reportPayload);
                                final submitted = result['success'] == true;

                                // የአካባቢው ሁኔታ በሁለቱም መንገድ ይዘምናል (በስክሪኑ ላይ ይታይ) —
                                // ግን የስኬት መልእክቱ የሚወሰነው በአገልጋዩ መልስ ብቻ ነው።
                                item.progressPercent = currentPercent;
                                item.reportDetails = doneDetails;
                                item.notDoneDetails = notDoneDetails;
                                item.reason = notDoneDetails;
                                item.evidencePath = pickedAttachments.isNotEmpty ? pickedAttachments.first.name : item.evidencePath;
                                item.reportSubmittedAt = DateTime.now();
                                item.submittedBy = senderTitle;
                                item.updatedAt = DateTime.now();

                                widget.onUpdatePlan(item);
                                // 2026-11-28: a report was just submitted
                                // — reload, so its 'submitted' office chip
                                // shows on the card right away.
                                _loadReports();

                                if (submitted) {
                                  // ወደ ቴሌግራም ግሩፕ ይፋዊ ማሳወቂያ መላክ
                                  await TelegramService.sendPlanReportNotice(
                                    deptName: item.departmentName,
                                    senderTitle: senderTitle,
                                    taskTitle: taskTitle,
                                    progressPercent: currentPercent,
                                    doneDetails: doneDetails,
                                    notDoneDetails: notDoneDetails.isEmpty ? null : notDoneDetails,
                                    reportId: result['data']?['id']?.toString(),
                                  );

                                  // H1(d)፦ የተያያዘ ፎቶ ካለ የመጀመሪያው ፎቶ
                                  // ወደ ቴሌግራም ይላካል (እንደ ቀድሞው)።
                                  _PickedAttachment? firstImage;
                                  for (final a in pickedAttachments) {
                                    if (a.isImage) {
                                      firstImage = a;
                                      break;
                                    }
                                  }
                                  if (firstImage != null) {
                                    try {
                                      await TelegramService.sendPhoto(
                                        imageBytes: firstImage.bytes,
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
                                        content: Text('አገልጋዩ አልተገኘም — ሪፖርቱ offline ተቀምጧል፤ ኢንተርኔት ሲገኝ በራስ-ሰር ይላካል። (${result['message'] ?? ''})'),
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
                                  // Audit fix 2026-11-25: postpone is now
                                  // persisted server-side (migration 06).
                                  'original_execution_time': item.executionTime,
                                  'postponed_date': newDate,
                                  'postpone_reason': postponeReason,
                                  'is_postponed': true,
                                };

                                final oldDate = item.executionTime;
                                final result = await ApiService().savePlan(planPayload);
                                final saved = result['success'] == true;

                                item.originalExecutionTime = oldDate;
                                item.executionTime = newDate;
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
                                    originalDate: oldDate,
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
                                        content: Text('አገልጋዩ አልተገኘም — ማስተላለፉ offline ተቀምጧል፤ ኢንተርኔት ሲገኝ ይላካል። (${result['message'] ?? ''})'),
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
    // 2026-11-26: the control department sees the department tabs too
    // (view-only). The Excel import button below stays super-admin only.
    final canViewAllDepts = isSuper || AuthService.canViewAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text('የክፍሎች ዝርዝር እቅድ'),
        actions: [
          IconButton(
            icon: Icon(isTableView ? Icons.grid_view : Icons.table_chart),
            tooltip: isTableView ? 'ወደ ካርድ እይታ ቀይር' : 'ወደ ሰንጠረዥ እይታ ቀይር',
            onPressed: () => setState(() => isTableView = !isTableView),
          ),
          // PR #46: the export generator existed but no button called it.
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'እቅዶች ወደ Excel አውጣ',
            onPressed: _exportPlansToExcel,
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
          // ፅ/ቤት ወይም ቁጥጥር (can_view_all) ከሆነ የክፍሎች ማጣሪያ ባር
          if (canViewAllDepts)
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

          // የወር ማጣሪያ ባር (2026-11-25): እቅድ በወር — እቅዱ በሚጠናቀቅበት ወር
          // ይታያል። ነባሪው አሁን ያለንበት ወር ነው።
          Container(
            height: 42,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _buildMonthChip(-1, 'ሁሉም ወራት (${_deptFilteredPlans.length})'),
                ...List.generate(ethiopianMonths13.length, (idx) {
                  final count = _deptFilteredPlans.where((p) =>
                      dueEthiopianMonthName(
                        dueDateEthiopian: p.dueDateEthiopian,
                        dueDate: p.dueDate,
                      ) ==
                      ethiopianMonths13[idx]).length;
                  return _buildMonthChip(idx, '${ethiopianMonths13[idx]} ($count)');
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
                                : selectedMonthIndex >= 0
                                    ? 'በ${ethiopianMonths13[selectedMonthIndex]} ወር ምንም እቅድ አልተገኘም'
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

  /// Month chip (2026-11-25): -1 = all months, else an index into
  /// ethiopianMonths13. Tapping a month shows only the plans due in
  /// that month; tapping the selected month again shows all months.
  Widget _buildMonthChip(int monthIndex, String label) {
    final isSelected = selectedMonthIndex == monthIndex;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: Icon(Icons.calendar_month,
            size: 14,
            color: isSelected ? Colors.white : AppTheme.primaryMaroon),
        label: Text(label),
        selected: isSelected,
        selectedColor: AppTheme.primaryMaroon,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (val) {
          setState(() {
            selectedMonthIndex =
                val ? monthIndex : currentEthiopianMonthIndex();
          });
        },
      ),
    );
  }

  // 1. የኤክሴል ሰንጠረዥ እይታ
  Widget _buildExcelTableView() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      // PR #46: a visible horizontal scrollbar — the table is wider
      // than the screen and the Actions column was only reachable by
      // wheel-scrolling right with no visual cue.
      child: Scrollbar(
        controller: _tableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _tableScrollController,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF530A14)),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            dataRowMinHeight: 48,
            dataRowMaxHeight: 64,
            // PR #46: tighter spacing + narrower task columns so more
            // of the table (including Actions) fits on a desktop width.
            columnSpacing: 10,
          border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
          // Excel header (2026-11-25): the table shows the same columns
          // as the 2019 Excel — ተ.ቁ | ክፍል | ንዑስ ክፍል | ዐቢይ ተግባራት |
          // ዝርዝር ተግባር | መለኪያ | ብዛት | የማስፈጸሚያ ጊዜ | በጀት — so a
          // plan reads exactly like its Excel row.
          columns: const [
            DataColumn(label: Text('ተ.ቁ')),
            DataColumn(label: Text('ክፍል')),
            DataColumn(label: Text('ንዑስ ክፍል')),
            DataColumn(label: Text('ዐቢይ ተግባራት')),
            DataColumn(label: Text('ዝርዝር ተግባር')),
            DataColumn(label: Text('መለኪያ')),
            DataColumn(label: Text('ብዛት')),
            DataColumn(label: Text('የማስፈጸሚያ ጊዜ')),
            DataColumn(label: Text('በጀት')),
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
                    width: 160,
                    child: Text(
                      item.mainTask,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Text(
                      item.detailTask.isNotEmpty ? item.detailTask : item.mainTask,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(item.measurement, style: const TextStyle(fontSize: 11))),
                DataCell(Text(item.quantity, style: const TextStyle(fontSize: 11))),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Full month names, not abbreviations:
                      // "መስከረም 10–30, የካቲት 6–28" instead of "መስ (10-30), የካ (6-28)".
                      Text(readableExecutionTime(item.executionTime), style: const TextStyle(fontSize: 11)),
                      if (item.dueDateEthiopian != null && item.dueDateEthiopian!.isNotEmpty)
                        Text(
                          'ቀኑ፦ ${item.dueDateEthiopian}',
                          style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold),
                        ),
                      if (item.isPostponed)
                        Text(
                          '👉 የተላለፈ፦ ${item.postponedDate}',
                          style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                DataCell(Text(item.budget, style: const TextStyle(fontSize: 11))),
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
                      // PR #46: plan edit — same RBAC gate as delete
                      // (super-admin any dept, dept_admin own dept).
                      if (AuthService.canManagePlan(item.departmentId))
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryMaroon),
                          tooltip: 'እቅድ አስተካክል',
                          onPressed: () => _showCreatePlanDialog(existing: item),
                        ),
                      if (AuthService.canManagePlan(item.departmentId))
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
        final latestReport = _latestReport(item);
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
                        'የማስፈጸሚያ ጊዜ፦ ${readableExecutionTime(item.executionTime)}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (item.dueDateEthiopian != null && item.dueDateEthiopian!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'ቀኑ፦ ${item.dueDateEthiopian}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],

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

                // 2026-11-28: the office decision on this plan's latest
                // report — view-only, so the department sees approved /
                // under review / revision / rejected + the office comment
                // on its own plan page.
                if (latestReport != null) ...[
                  const SizedBox(height: 6),
                  _buildOfficeStatusChip(
                    (latestReport['status'] ?? 'submitted').toString(),
                  ),
                  if ((latestReport['office_feedback'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '💬 የፅ/ቤት አስተያየት፦ ${latestReport['office_feedback'].toString().trim()}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                    ),
                  ],
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

                // እርምጃዎች (አስተካክል፣ ሪፖርት ስጥ እና ቀን ቀይር)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (AuthService.canManagePlan(item.departmentId))
                      IconButton(
                        onPressed: () => _deletePlan(item),
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'እቅድ ሰርዝ',
                      ),
                    // PR #46: plan edit — same RBAC gate as delete.
                    if (AuthService.canManagePlan(item.departmentId))
                      TextButton.icon(
                        onPressed: () => _showCreatePlanDialog(existing: item),
                        icon: const Icon(Icons.edit_outlined, size: 15, color: AppTheme.primaryMaroon),
                        label: const Text('አስተካክል', style: TextStyle(fontSize: 11, color: AppTheme.primaryMaroon)),
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

/// 2026-11-26: one file picked for a report (image or document).
class _PickedAttachment {
  final String name;
  final String mime;
  final Uint8List bytes;
  const _PickedAttachment({required this.name, required this.mime, required this.bytes});

  bool get isImage => mime.startsWith('image/');

  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// MIME type by file extension (the server re-validates the real
/// content type, so this is only a hint for the payload).
String _mimeForFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return 'application/octet-stream';
  }
}
