import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/department.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/office_export_service.dart';
import '../theme/app_theme.dart';
import '../utils/ethiopian_date_display.dart';

class OfficeReportsScreen extends StatefulWidget {
  const OfficeReportsScreen({super.key});

  @override
  State<OfficeReportsScreen> createState() => _OfficeReportsScreenState();
}

class _OfficeReportsScreenState extends State<OfficeReportsScreen> {
  List<Map<String, dynamic>> reports = [];
  bool isLoading = true;
  String selectedFilter = 'all'; // all, submitted, approved, revision_requested, rejected
  String selectedDept = 'all';

  @override
  void initState() {
    super.initState();
    // 2026-11-28: only the office (super admin) and the control
    // department (can_view_all) may open this screen — for anyone else
    // there is nothing to load; the build method shows the denied
    // message instead of the list.
    if (AuthService.isSuperAdmin || AuthService.canViewAll) {
      _loadReports();
    } else {
      isLoading = false;
    }
  }

  Future<void> _loadReports() async {
    setState(() => isLoading = true);
    final data = await ApiService().getReports(
      dept: selectedDept != 'all' ? selectedDept : null,
      status: selectedFilter != 'all' ? selectedFilter : null,
    );
    setState(() {
      reports = data;
      isLoading = false;
    });
  }

  // PR #46 (2026-11-28): Office Review had no report delete control.
  // Server DELETE /reports.php is super-admin only (soft delete,
  // audit-logged); the control department (can_view_all, view-only)
  // deliberately gets no delete button.
  Future<void> _deleteReport(Map<String, dynamic> report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ሪፖርቱን መሰረዝ ይፈልጋሉ?', style: TextStyle(fontSize: 16)),
        content: Text(
          '«${report['plan_title'] ?? 'ሪፖርት'}»\n\nይህ ሪፖርት ከአገልጋዩ ላይ በቋሚነት ይሰረዛል።',
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
            child: const Text('አዎ፣ ሰርዝ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await ApiService().deleteReport((report['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      await _loadReports();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ሪፖርቱ ተሰርዟል!'),
          backgroundColor: AppTheme.greenSuccess,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ሪፖርቱን መሰረዝ አልተቻለም!'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
    }
  }

  // ── 2026-11-26: report attachment open/download ─────────────────────
  // files.php serves the file by attachment id (auth-guarded: own
  // department, super admin, or can_view_all). Images preview in-app,
  // PDFs open in the share sheet, Word/Excel files are saved to the
  // device documents folder (web cannot save — the app is needed).
  Future<void> _openAttachment(Map<String, dynamic> att) async {
    final id = (att['id'] ?? '').toString();
    final name = (att['file_name'] ?? 'ፋይል').toString();
    final mime = (att['file_type'] ?? '').toString();
    if (id.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('ፋይሉ እየወረደ ነው…'), duration: Duration(seconds: 2)),
    );
    final bytes = await ApiService().downloadAttachment(id);
    if (!mounted) return;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ፋይሉን ማውረድ አልተቻለም — ኢንተርኔትዎን ያረጋግጡ።'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
      return;
    }

    if (mime.startsWith('image/')) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Flexible(child: SingleChildScrollView(child: Image.memory(bytes))),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      return;
    }

    if (mime == 'application/pdf') {
      try {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('ፋይሉን መክፈት አልተቻለም፦ $e'), backgroundColor: AppTheme.redDanger),
          );
        }
      }
      return;
    }

    // Word/Excel ሰነዶች — ወደ መሳሪያው ሰነዶች ማውጫ ማስቀመጥ
    final path = await OfficeExportService.saveAndGetFilePath(fileName: name, bytes: bytes);
    if (!mounted) return;
    if (path != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('ፋይሉ ተወርዷል፦ $name'), backgroundColor: AppTheme.greenSuccess),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('በድረ-ገጽ ላይ ይህን ፋይል ማውረድ አይቻልም — እባክዎ በአንድሮይድ አፕሊኬሽኑ ይክፈቱ።'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showReviewDialog(Map<String, dynamic> report) {
    final commentCtrl = TextEditingController(text: report['office_feedback'] ?? '');
    String currentAction = 'approved';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.rate_review, color: AppTheme.primaryMaroon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'የሪፖርት ግምገማ፦ ${report['title'] ?? 'ሪፖርት'}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'አቅራቢ ክፍል፦ ${report['department_name'] ?? report['department_id']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text('አቅራቢ፦ ${report['submitted_by'] ?? 'አባል'} | ክንውን፦ ${report['progress_percent'] ?? 0}%'),
                const SizedBox(height: 10),
                const Text('የተከናወኑ ተግባራት፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(report['activities_completed'] ?? '', style: const TextStyle(fontSize: 12)),
                ),
                if (report['challenges'] != null && report['challenges'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('ያጋጠሙ ተግዳሮቶች፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                  Text(report['challenges'], style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 14),
                const Text('የፅ/ቤት ውሳኔ፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: currentAction,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'approved', child: Text('✅ አጽድቅ (Approve)')),
                    DropdownMenuItem(value: 'revision_requested', child: Text('⚠️ ማሻሻያ ጠይቅ (Request Revision)')),
                    DropdownMenuItem(value: 'rejected', child: Text('❌ ውድቅ አድርግ (Reject)')),
                    DropdownMenuItem(value: 'under_review', child: Text('⏳ በግምገማ ላይ (Under Review)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => currentAction = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'የፅ/ቤት አስተያየት እና መመሪያ',
                    hintText: 'ለክፍሉ የሚተላለፍ ማሳሰቢያ ወይም ምስጋና...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: currentAction == 'approved'
                    ? AppTheme.greenSuccess
                    : (currentAction == 'revision_requested' ? Colors.orange : AppTheme.redDanger),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final res = await ApiService().reviewReport(
                  reportId: report['id'],
                  action: currentAction,
                  comment: commentCtrl.text.trim(),
                  reviewerName: AuthService.currentUserProfile?['full_name'] ?? 'ዲ/ን ኤፍሬም (ፅ/ቤት)',
                );
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'ውሳኔው ተመዝግቧል!'),
                      backgroundColor: AppTheme.greenSuccess,
                    ),
                  );
                  _loadReports();
                }
              },
              child: const Text('ውሳኔውን መዝግብ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2026-11-28 (defense-in-depth): Office Review is for the office
    // (super admin) and the control department (can_view_all) only. A
    // department head who reaches this screen another way sees this
    // message instead of the report list. Data loading and the
    // review/decision button inside stay unchanged — the button is
    // already super-admin-only.
    if (!AuthService.isSuperAdmin && !AuthService.canViewAll) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          title: const Text('የፅ/ቤት ሪፖርቶች መገምገሚያ (Office Review)'),
          backgroundColor: AppTheme.primaryMaroon,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'ይህ ገጽ ለፅ/ቤት እና ለቁጥጥር ክፍል ብቻ ነው።',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('የፅ/ቤት ሪፖርቶች መገምገሚያ (Office Review)'),
        backgroundColor: AppTheme.primaryMaroon,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: Column(
        children: [
          // የማጣሪያ ሳጥን
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedFilter,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'የሪፖርት ሁኔታ', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('ሁሉም ሁኔታዎች')),
                      DropdownMenuItem(value: 'submitted', child: Text('የቀረቡ (Submitted)')),
                      DropdownMenuItem(value: 'under_review', child: Text('በግምገማ ላይ')),
                      DropdownMenuItem(value: 'approved', child: Text('የጸደቁ (Approved)')),
                      DropdownMenuItem(value: 'revision_requested', child: Text('ማሻሻያ የተጠየቀባቸው')),
                      DropdownMenuItem(value: 'rejected', child: Text('ውድቅ የተደረጉ')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => selectedFilter = val);
                        _loadReports();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedDept,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'ክፍል', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('ሁሉም ክፍሎች')),
                      ...Department.allDepartments
                          .where((d) => !d.isSuperAdmin)
                          .map((d) => DropdownMenuItem(value: d.id, child: Text(d.shortName))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => selectedDept = val);
                        _loadReports();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryMaroon))
                : reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'በዚህ ማጣሪያ የቀረበ ሪፖርት አልተገኘም',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: reports.length,
                        itemBuilder: (ctx, idx) {
                          final r = reports[idx];
                          final status = r['status'] ?? 'submitted';
                          Color statusColor = Colors.blue;
                          String statusLabel = 'የቀረበ';
                          if (status == 'approved') {
                            statusColor = AppTheme.greenSuccess;
                            statusLabel = 'የጸደቀ';
                          } else if (status == 'revision_requested') {
                            statusColor = Colors.orange;
                            statusLabel = 'ማሻሻያ የተጠየቀበት';
                          } else if (status == 'rejected') {
                            statusColor = AppTheme.redDanger;
                            statusLabel = 'ውድቅ የተደረገ';
                          } else if (status == 'under_review') {
                            statusColor = Colors.purple;
                            statusLabel = 'በግምገማ ላይ';
                          }

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r['title'] ?? 'የክንውን ሪፖርት',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: statusColor, width: 0.8),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '🏛️ ${r['department_name'] ?? r['department_id']} | 👤 ${r['submitted_by'] ?? 'አባል'} | 📅 ${formatGregorianDateStringEthiopian((r['created_at'] ?? '').toString())}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  // 2026-11-26 (per-occurrence): the exact
                                  // date this report belongs to.
                                  if ((r['occurrence_date'] ?? '').toString().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '🗓️ የሪፖርት ቀን፦ ${formatGregorianDateStringEthiopian((r['occurrence_date'] ?? '').toString())}',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    r['activities_completed'] ?? '',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  // 2026-11-26: attached files — tap to open/download.
                                  if (r['attachments'] is List && (r['attachments'] as List).isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    const Text('ተያይዘው የቀረቡ ፋይሎች፦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: (r['attachments'] as List).map((a) {
                                        final att = Map<String, dynamic>.from(a as Map);
                                        final fileName = (att['file_name'] ?? 'ፋይል').toString();
                                        final fileSize = att['file_size'] is int
                                            ? att['file_size'] as int
                                            : int.tryParse('${att['file_size'] ?? 0}') ?? 0;
                                        return ActionChip(
                                          avatar: Icon(_attachmentIcon(att), size: 16, color: AppTheme.primaryMaroon),
                                          label: Text(
                                            '$fileName (${_formatFileSize(fileSize)})',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          onPressed: () => _openAttachment(att),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  if (r['office_feedback'] != null && r['office_feedback'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.shade300),
                                      ),
                                      child: Text(
                                        '💬 የፅ/ቤት አስተያየት፦ ${r['office_feedback']}',
                                        style: TextStyle(fontSize: 12, color: Colors.brown.shade800),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'የክንውን ደረጃ፦ ${r['progress_percent'] ?? 0}%',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryMaroon),
                                      ),
                                      if (AuthService.isSuperAdmin)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primaryMaroon,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              icon: const Icon(Icons.rate_review, size: 16),
                                              label: const Text('ገምግም / ውሳኔ ስጥ', style: TextStyle(fontSize: 12)),
                                              onPressed: () => _showReviewDialog(r),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                              tooltip: 'ሪፖርት ሰርዝ',
                                              onPressed: () => _deleteReport(r),
                                            ),
                                          ],
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
}

/// 2026-11-26: icon for a report attachment, by its MIME type.
IconData _attachmentIcon(Map<String, dynamic> att) {
  final mime = (att['file_type'] ?? '').toString();
  if (mime.startsWith('image/')) return Icons.image;
  if (mime == 'application/pdf') return Icons.picture_as_pdf;
  if (mime.contains('spreadsheet') || mime.contains('ms-excel')) return Icons.table_chart;
  if (mime.contains('word') || mime.contains('msword')) return Icons.description;
  return Icons.insert_drive_file;
}

/// 2026-11-26: human-readable file size (KB/MB).
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
