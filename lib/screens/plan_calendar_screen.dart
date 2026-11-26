import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/department.dart';
import '../models/plan_item.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pdf_generator_service.dart';
import '../services/telegram_service.dart';
import '../utils/ethiopian_date_display.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';

class PlanCalendarScreen extends StatefulWidget {
  final List<PlanItem> plans;
  final Function(PlanItem) onUpdatePlan;

  const PlanCalendarScreen({
    super.key,
    required this.plans,
    required this.onUpdatePlan,
  });

  @override
  State<PlanCalendarScreen> createState() => _PlanCalendarScreenState();
}

class _PlanCalendarScreenState extends State<PlanCalendarScreen> {
  static const List<String> ethiopianMonths = [
    'መስከረም', 'ጥቅምት', 'ህዳር', 'ታህሳስ', 'ጥር', 'የካቲት',
    'መጋቢት', 'ሚያዝያ', 'ግንቦት', 'ሰኔ', 'ሐምሌ', 'ነሐሴ'
  ];

  static const List<String> shortMonths = [
    'መስ', 'ጥቅ', 'ህዳር', 'ታህ', 'ጥር', 'የካ', 'መጋ', 'ሚያ', 'ግን', 'ሰኔ', 'ሐም', 'ነሐ'
  ];

  int selectedMonthIndex = currentEthiopianMonthIndex(); // ነባሪ፦ አሁን ያለንበት ወር
  String selectedFilter = 'all'; // 'all', 'overdue', 'postponed', 'reported', 'completed'
  String? selectedDeptId;

  bool isSendingAlert = false;
  bool isGeneratingAudit = false;

  List<PlanItem> get _filteredPlans {
    final currentDept = AuthService.currentDepartment;
    // 2026-11-26: the control department (can_view_all) sees all
    // departments — view-only, like the office.
    final canViewAll = AuthService.isSuperAdmin || AuthService.canViewAll;

    return widget.plans.where((p) {
      // የክፍል ፍተሻ
      if (!canViewAll) {
        if (!p.departmentName.contains(currentDept?.shortName ?? '') && p.departmentId != currentDept?.id) {
          return false;
        }
      } else if (selectedDeptId != null && selectedDeptId != 'all') {
        if (p.departmentId != selectedDeptId && !p.departmentName.contains(selectedDeptId!)) {
          return false;
        }
      }

      // የወር ፍተሻ፦ የተመረጠው ወር ውስጥ እቅድ አለው?
      final sMonth = shortMonths[selectedMonthIndex];
      final fMonth = ethiopianMonths[selectedMonthIndex];
      final monthVal = p.months[sMonth] ?? p.months[fMonth] ?? '';
      final hasPlanThisMonth = monthVal.isNotEmpty && monthVal != '-';
      final isYearRound = p.executionTime.contains('ዓመቱን ሙሉ');
      final isPostponedToThisMonth = p.postponedDate != null &&
          (p.postponedDate!.contains(fMonth) || p.postponedDate!.contains(sMonth));

      if (!hasPlanThisMonth && !isYearRound && !isPostponedToThisMonth) return false;

      // የሁኔታ ፍተሻ
      final isCompleted = p.isCompleted;
      final isOverdue = !isCompleted && selectedMonthIndex >= 1 && !p.isPostponed;

      if (selectedFilter == 'overdue') return isOverdue;
      if (selectedFilter == 'postponed') return p.isPostponed;
      if (selectedFilter == 'reported') return p.hasReport || p.progressPercent > 0;
      if (selectedFilter == 'completed') return isCompleted;

      return true;
    }).toList();
  }

  // ያዘገዩ (Overdue) እቅዶች - እስካሁን ያልተላለፉ እና ያልተጠናቀቁ
  List<PlanItem> get _allOverduePlans {
    return widget.plans.where((p) {
      if (p.isCompleted || p.isPostponed) return false;
      final mes = p.months['መስ'] ?? '';
      final tiq = p.months['ጥቅ'] ?? '';
      return (mes.isNotEmpty && mes != '-') || (tiq.isNotEmpty && tiq != '-');
    }).toList();
  }

  /// ያዘገዩ እቅዶች ማስጠንቀቂያን በቀጥታ ወደ ቴሌግራም ግሩፕ መላክ
  Future<void> _sendOverdueAlertToTelegram() async {
    final overdueList = _allOverduePlans;
    if (overdueList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('በአሁኑ ወቅት ያዘገየ ምንም እቅድ የለም! ሁሉም በጥሩ ሁኔታ ላይ ነው።'), backgroundColor: AppTheme.greenSuccess),
      );
      return;
    }

    if (TelegramService.savedChatId == null || TelegramService.savedChatId!.isEmpty) {
      final connected = await TelegramConnectDialog.show(context);
      if (connected != true) return;
    }

    setState(() => isSendingAlert = true);

    final buffer = StringBuffer();
    buffer.writeln('🚨 <b>ይፋዊ የእቅድ ክትትል እና የጊዜ ማሳሰቢያ ማስጠንቀቂያ</b>');
    buffer.writeln('🏛 <b>አጸደ ትጉሃን ሰ/ት/ቤት ዋና ጽ/ቤት</b>\n');
    buffer.writeln('በጥቅምት ወር መርሃ-ግብር መሰረት የማስፈጸሚያ ጊዜያቸው ያለፈባቸው (ያዘገዩ) እቅዶች ዝርዝር፦\n');

    final Map<String, List<PlanItem>> grouped = {};
    for (var plan in overdueList) {
      grouped.putIfAbsent(plan.departmentName, () => []).add(plan);
    }

    int deptIndex = 1;
    grouped.forEach((dept, items) {
      buffer.writeln('<b>$deptIndex. $dept (${items.length} ያዘገዩ እቅዶች)፦</b>');
      for (var p in items) {
        final taskName = p.detailTask.isNotEmpty ? p.detailTask : p.mainTask;
        buffer.writeln('  • <i>$taskName</i> (የቀደመ ጊዜ፦ ${p.executionTime})');
      }
      buffer.writeln('');
      deptIndex++;
    });

    buffer.writeln('⚠️ <b>ማሳሰቢያ ለክፍላት ኃላፊዎች፦</b>');
    buffer.writeln('ያዘገዩ እቅዶችን ሪፖርት በአፑ በኩል እንዲያቀርቡ ወይም ወደፊት የሚከናወኑ ከሆነ <b>ቀኑን እንዲያስተላልፉ (Postpone)</b> በአክብሮት እናሳስባለን።');

    final success = await TelegramService.sendMessage(text: buffer.toString());
    setState(() => isSendingAlert = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('የ${overdueList.length} ያዘገዩ እቅዶች ማስጠንቀቂያ ወደ ቴሌግራም ግሩፕ ተልኳል!'),
            backgroundColor: AppTheme.greenSuccess,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('መልዕክቱን ወደ ቴሌግራም መላክ አልተቻለም። እባክዎ ግንኙነቱን ያረጋግጡ።'), backgroundColor: AppTheme.redDanger),
        );
      }
    }
  }

  /// የኦዲት እና ቁጥጥር PDF ሪፖርት ማመንጨት
  Future<void> _generateAuditReport() async {
    setState(() => isGeneratingAudit = true);
    try {
      final periodName = ethiopianMonths[selectedMonthIndex];
      final totalPlans = widget.plans.length;
      final completed = widget.plans.where((p) => p.isCompleted).length;
      final overdueList = _allOverduePlans;

      final List<Map<String, dynamic>> deptStats = Department.allDepartments.map((dept) {
        final dPlans = widget.plans.where((p) => p.departmentName.contains(dept.shortName) || p.departmentId == dept.id).toList();
        final dComp = dPlans.where((p) => p.isCompleted).length;
        final dOverdue = dPlans.where((p) => !p.isCompleted && !p.isPostponed).length;
        final dPostponed = dPlans.where((p) => p.isPostponed).length;
        return {
          'name': dept.name,
          'shortName': dept.shortName,
          'total': dPlans.length,
          'completed': dComp,
          'overdue': dOverdue,
          'postponed': dPostponed,
          'percent': dPlans.isNotEmpty ? ((dComp / dPlans.length) * 100).toInt() : 0,
        };
      }).toList();

      final List<String> overdueWarnings = overdueList.map((p) {
        final taskName = p.detailTask.isNotEmpty ? p.detailTask : p.mainTask;
        return '${p.departmentName} - $taskName (የማስፈጸሚያ ጊዜ፦ ${p.executionTime})';
      }).toList();

      final pdfBytes = await PdfGeneratorService.generateAuditEvaluationPdf(
        deptStats: deptStats,
        overdueWarnings: overdueWarnings,
        periodName: periodName,
        totalPlansCount: totalPlans,
        completedCount: completed,
        overdueCount: overdueList.length,
      );

      final fileName = 'የክፍላት_አፈፃፀም_ግምገማ_${periodName}_${currentEthiopianYear()}.pdf';
      await PdfGeneratorService.printOrSharePdf(pdfBytes, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileName በተሳካ ሁኔታ ተዘጋጅቷል!'),
            backgroundColor: AppTheme.greenSuccess,
            action: SnackBarAction(
              label: 'ወደ ቴሌግራም ላክ',
              textColor: Colors.white,
              onPressed: () async {
                final caption = '📊 <b>የ10ሩ ክፍላት የ${ethiopianMonths[selectedMonthIndex]} ወር አፈፃፀም ግምገማ ሪፖርት (ኦዲት)</b>';
                await TelegramService.sendDocument(
                  fileBytes: pdfBytes,
                  fileName: fileName,
                  caption: caption,
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF ማመንጨት አልተቻለም: $e'), backgroundColor: AppTheme.redDanger),
        );
      }
    } finally {
      if (mounted) setState(() => isGeneratingAudit = false);
    }
  }

  // 1. የክንውን ሪፖርት መስጫ ሞዳል
  void _showReportDialog(PlanItem item) {
    int currentPercent = item.progressPercent;
    final doneController = TextEditingController(text: item.reportDetails ?? '');
    final notDoneController = TextEditingController(text: item.notDoneDetails ?? item.reason);
    String? pickedImagePath = item.evidencePath;
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
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                            ),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(),
                    Text(item.detailTask, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'ክፍል፦ ${item.departmentName} | የማስፈጸሚያ ጊዜ፦ ${item.effectiveExecutionTime}',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),

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
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                          onSelected: (val) {
                            if (val) setModalState(() => currentPercent = percent);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('የተከናወኑ ስራዎች ዝርዝር (ምን ተሰራ?)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.greenSuccess)),
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

                    if (currentPercent < 100) ...[
                      const Text('ያልተከናወነ ነገር እና ያልተሰራበት ምክንያት፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.redDanger)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ['የበጀት እጥረት', 'የአባላት አለመገኘት', 'የቀን መደራረብ', 'የቁሳቁስ እጥረት', 'የፈቃድ መዘግየት'].map((quickR) {
                          return ActionChip(
                            label: Text(quickR, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                if (notDoneController.text.isEmpty) {
                                  notDoneController.text = quickR;
                                } else {
                                  notDoneController.text += '፣ $quickR';
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

                    const Text('የፎቶ ማስረጃ (Evidence)፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              setModalState(() => pickedImagePath = img.path);
                            }
                          },
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('ፎቶ ያያይዙ'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
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

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryMaroon, foregroundColor: Colors.white),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                final currentDept = AuthService.currentDepartment;
                                final isSuper = AuthService.isSuperAdmin;
                                final senderTitle = isSuper ? 'የጽ/ቤት ዋና ጸሐፊ' : '${currentDept?.shortName ?? item.departmentName} ኃላፊ';
                                final doneDetails = doneController.text.trim();
                                final notDoneDetails = notDoneController.text.trim();
                                final taskTitle = item.detailTask.isNotEmpty ? item.detailTask : item.mainTask;

                                // H1(c)፦ ሪፖርቱ መጀመሪያ ወደ አገልጋዩ (reports.php) ይላካል።
                                // "ተመዝግቧል" የሚለው መልእክት የሚታየው አገልጋዩ ካረጋገጠ በኋላ ብቻ ነው።
                                // ከዚህ በፊት እዚህ ሞዳል አገልጋዩን ሳያነጋግር በአካባቢው ብቻ
                                // ይቀይር ነበር — ስለዚህ ሪፖርቱ ወደ Office Review በጭራሽ
                                // አይደርስም ነበር።
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

                                if (!submitted) {
                                  if (context.mounted) {
                                    setModalState(() => isSubmitting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('ሪፖርቱ ወደ ሰርቨር አልተላከም፦ ${result['message'] ?? 'እባክዎ እንደገና ይሞክሩ'}'),
                                        backgroundColor: AppTheme.redDanger,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                item.progressPercent = currentPercent;
                                item.reportDetails = doneDetails;
                                item.notDoneDetails = notDoneDetails;
                                item.reason = notDoneDetails;
                                item.evidencePath = pickedImagePath;
                                item.reportSubmittedAt = DateTime.now();
                                item.submittedBy = senderTitle;
                                item.updatedAt = DateTime.now();

                                widget.onUpdatePlan(item);

                                await TelegramService.sendPlanReportNotice(
                                  deptName: item.departmentName,
                                  senderTitle: senderTitle,
                                  taskTitle: taskTitle,
                                  progressPercent: currentPercent,
                                  doneDetails: doneDetails,
                                  notDoneDetails: notDoneDetails.isEmpty ? null : notDoneDetails,
                                );

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ሪፖርቱ ለጽ/ቤት ተመዝግቧል፤ ወደ ቴሌግራም ተልኳል!'), backgroundColor: AppTheme.greenSuccess),
                                  );
                                }
                              },
                        icon: isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                        label: const Text('ሪፖርቱን መዝግብ እና ለጽ/ቤት / ቴሌግራም ላክ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

  // 2. እቅድ ማስተላለፊያ ሞዳል
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
                            Text('እቅድ ማስተላለፊያ (Postpone)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(),
                    Text(item.detailTask, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('ክፍል፦ ${item.departmentName} | የመጀመሪያ ጊዜ፦ ${item.executionTime}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    const SizedBox(height: 14),

                    const Text('አዲሱ የተላለፈበት ቀን፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newDateController,
                      decoration: InputDecoration(
                        hintText: 'ለምሳሌ፦ ህዳር 15 ወይም ታህሳስ 1',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (val) => setModalState(() => newDateController.text = val),
                          itemBuilder: (ctx) => [
                            'ጥቅምት 30', 'ህዳር 15', 'ህዳር 30', 'ታህሳስ 15', 'ታህሳስ 30', 'ጥር 15', 'የካቲት 15',
                          ].map((d) => PopupMenuItem(value: d, child: Text(d))).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('የማስተላለፊያ ምክንያት፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        'የበጀት ዝግጅት ስለሚያስፈልግ',
                        'የቀን መደራረብ ስላጋጠመ',
                        'ከበዓላት ዝግጅት ጋር በማያያዝ',
                        'አስፈላጊ ግብዓቶችን ለማሟላት',
                      ].map((quickR) {
                        return ActionChip(
                          label: Text(quickR, style: const TextStyle(fontSize: 11)),
                          onPressed: () => setModalState(() => reasonController.text = quickR),
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

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
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
                                final senderTitle = isSuper ? 'የጽ/ቤት ዋና ጸሐፊ' : '${currentDept?.shortName ?? item.departmentName} ኃላፊ';
                                final postponeReason = reasonController.text.trim();

                                // H1(e)፦ ማስተላለፉ መጀመሪያ ወደ አገልጋዩ (plans.php) ይቀመጣል።
                                // ከዚህ በፊት እዚህ ሞዳል አገልጋዩን ሳያነጋግር በአካባቢው ብቻ
                                // ይቀይር ነበር — ስለዚህ ማስተላለፉ አፕሉን እንደገና ሲከፍት
                                // ይጠፋና እቅዱ አሁንም ያዘገየ ሆኖ ይታይ ነበር።
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
                                  'original_execution_time': item.executionTime,
                                  'postponed_date': newDate,
                                  'postpone_reason': postponeReason,
                                  'is_postponed': true,
                                };

                                final oldDate = item.executionTime;
                                final result = await ApiService().savePlan(planPayload);
                                final saved = result['success'] == true;

                                if (!saved) {
                                  if (context.mounted) {
                                    setModalState(() => isSubmitting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('ማስተላለፉ ወደ ሰርቨር አልተላከም፦ ${result['message'] ?? 'እባክዎ እንደገና ይሞክሩ'}'),
                                        backgroundColor: AppTheme.redDanger,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                item.originalExecutionTime = oldDate;
                                item.executionTime = newDate;
                                item.postponedDate = newDate;
                                item.postponeReason = postponeReason;
                                item.updatedAt = DateTime.now();

                                widget.onUpdatePlan(item);

                                await TelegramService.sendPlanPostponedNotice(
                                  deptName: item.departmentName,
                                  senderTitle: senderTitle,
                                  taskTitle: item.detailTask.isNotEmpty ? item.detailTask : item.mainTask,
                                  originalDate: oldDate,
                                  newDate: newDate,
                                  reason: postponeReason.isNotEmpty ? postponeReason : 'ምክንያት አልተገለጸም',
                                );

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('እቅዱ ወደ $newDate ተላልፏል፤ ለጽ/ቤት እና ቴሌግራም ተልኳል!'), backgroundColor: AppTheme.greenSuccess),
                                  );
                                }
                              },
                        icon: isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.schedule_send),
                        label: const Text('እቅዱን አስተላልፍ እና ለጽ/ቤት/ቴሌግራም አሳውቅ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
    // 2026-11-26: the control department (can_view_all) gets the
    // department selector too (view-only). The overdue banner below
    // stays super-admin only — it sends office alerts to Telegram.
    final canViewAllDepts = isSuper || AuthService.canViewAll;
    final overdueCount = _allOverduePlans.length;
    final filtered = _filteredPlans;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.calendar_month, color: Colors.white),
            const SizedBox(width: 8),
            Text('የቀን መቁጠሪያ እና ማስታወሻ (${ethiopianMonths[selectedMonthIndex]})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'አድስ',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // ፅ/ቤት ወይም ቁጥጥር (can_view_all) ከሆነ የክፍሎች መራጭ
          if (canViewAllDepts)
            Container(
              height: 44,
              color: Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  _buildDeptChoice(null, 'ሁሉም ክፍሎች'),
                  ...Department.allDepartments.map((d) => _buildDeptChoice(d.id, d.shortName)),
                ],
              ),
            ),

          // ያዘገዩ እቅዶች የማስጠንቀቂያ ባነር
          if (isSuper)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: overdueCount > 0 ? AppTheme.redDanger.withAlpha(20) : AppTheme.greenSuccess.withAlpha(20),
              child: Row(
                children: [
                  Icon(
                    overdueCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: overdueCount > 0 ? AppTheme.redDanger : AppTheme.greenSuccess,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      overdueCount > 0
                          ? '$overdueCount ቀናቸው ያለፈባቸው (ያዘገዩ) እቅዶች አሉ! ለክፍሎች ማስጠንቀቂያ ይላኩ።'
                          : 'ሁሉም ክፍሎች እቅዶቻቸውን በሰዓቱ እያከናወኑ ይገኛሉ።',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: overdueCount > 0 ? AppTheme.redDanger : AppTheme.greenSuccess,
                      ),
                    ),
                  ),
                  if (overdueCount > 0)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.redDanger,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: isSendingAlert ? null : _sendOverdueAlertToTelegram,
                      icon: isSendingAlert
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                      label: const Text('ማስጠንቀቂያ ላክ', style: TextStyle(fontSize: 11, color: Colors.white)),
                    ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryMaroon,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: isGeneratingAudit ? null : _generateAuditReport,
                    icon: isGeneratingAudit
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.analytics_outlined, size: 14, color: Colors.white),
                    label: const Text('ግምገማ PDF', style: TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ],
              ),
            ),

          // የወራት መምረጫ አግድም ዝርዝር
          Container(
            height: 48,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: ethiopianMonths.length,
              itemBuilder: (ctx, idx) {
                final isSelected = selectedMonthIndex == idx;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(ethiopianMonths[idx]),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryMaroon,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => selectedMonthIndex = idx);
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // ማጣሪያዎች
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'ሁሉም (${filtered.length})'),
                        const SizedBox(width: 6),
                        _buildFilterChip('overdue', '🔴 ያዘገዩ ($overdueCount)'),
                        const SizedBox(width: 6),
                        _buildFilterChip('postponed', '📅 የተላለፉ'),
                        const SizedBox(width: 6),
                        _buildFilterChip('reported', '📋 ሪፖርት ያላቸው'),
                        const SizedBox(width: 6),
                        _buildFilterChip('completed', '🟢 የተጠናቀቁ'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // የእቅዶች ዝርዝር ካርዶች
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_available, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'በ${ethiopianMonths[selectedMonthIndex]} ወር ምንም እቅድ አልተገኘም',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final isOverdue = !item.isCompleted && selectedMonthIndex >= 1 && !item.isPostponed;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: item.isPostponed ? 2 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: item.isPostponed
                                ? Colors.deepOrange.shade300
                                : (isOverdue ? AppTheme.redDanger : (item.isCompleted ? AppTheme.greenSuccess : Colors.grey.shade300)),
                            width: item.isPostponed || isOverdue || item.isCompleted ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: item.isPostponed
                                          ? Colors.deepOrange.shade100
                                          : (isOverdue
                                              ? AppTheme.redDanger.withAlpha(20)
                                              : (item.isCompleted ? AppTheme.greenSuccess.withAlpha(20) : AppTheme.primaryMaroon.withAlpha(20))),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.departmentName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: item.isPostponed
                                            ? Colors.deepOrange
                                            : (isOverdue
                                                ? AppTheme.redDanger
                                                : (item.isCompleted ? AppTheme.greenSuccess : AppTheme.primaryMaroon)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (item.isPostponed)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.deepOrange.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('ተላልፏል', style: TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                                    ),
                                  const Spacer(),
                                  if (isOverdue)
                                    const Row(
                                      children: [
                                        Icon(Icons.alarm, size: 14, color: AppTheme.redDanger),
                                        SizedBox(width: 4),
                                        Text('ቀኑ አልፏል!', style: TextStyle(color: AppTheme.redDanger, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ],
                                    )
                                  else if (item.isCompleted)
                                    const Row(
                                      children: [
                                        Icon(Icons.check_circle, size: 14, color: AppTheme.greenSuccess),
                                        SizedBox(width: 4),
                                        Text('ተጠናቋል', style: TextStyle(color: AppTheme.greenSuccess, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              Text(
                                item.detailTask,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 6),

                              // የቀን እና የማስተላለፊያ መረጃ
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'የማስፈጸሚያ ጊዜ፦ ${item.executionTime}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                  ),
                                  Text('${item.progressPercent}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryMaroon)),
                                ],
                              ),

                              if (item.isPostponed) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.deepOrange.shade200),
                                  ),
                                  child: Text(
                                    '👉 የተላለፈበት አዲስ ቀን፦ ${item.postponedDate} (${item.postponeReason ?? ""})',
                                    style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],

                              if (item.reportDetails != null && item.reportDetails!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('የተከናወነ፦ ${item.reportDetails}', style: TextStyle(fontSize: 11, color: Colors.green.shade900)),
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
                                  child: Text('ያልተከናወነ/ምክንያት፦ ${item.notDoneDetails}', style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                                ),
                              ],

                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 6),

                              // እርምጃዎች
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showPostponeDialog(item),
                                    icon: const Icon(Icons.update, size: 14, color: Colors.deepOrange),
                                    label: const Text('ቀን ቀይር / አስተላልፍ', style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _showReportDialog(item),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryMaroon,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    ),
                                    icon: const Icon(Icons.assignment_turned_in, size: 14),
                                    label: const Text('ሪፖርት ስጥ', style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeptChoice(String? deptId, String label) {
    final isSelected = selectedDeptId == deptId;
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
          setState(() => selectedDeptId = val ? deptId : null);
        },
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = selectedFilter == value;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      selectedColor: AppTheme.primaryMaroon,
      checkmarkColor: Colors.white,
      onSelected: (val) {
        setState(() => selectedFilter = value);
      },
    );
  }
}
