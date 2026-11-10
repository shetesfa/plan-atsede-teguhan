import 'package:flutter/material.dart';
import '../models/department.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

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
    _loadReports();
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
                  reviewerName: AuthService.currentUserProfile?['full_name'] ?? 'ዲ/ን ቴዎድሮስ (ፅ/ቤት)',
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
                                    '🏛️ ${r['department_name'] ?? r['department_id']} | 👤 ${r['submitted_by'] ?? 'አባል'} | 📅 ${(r['created_at'] ?? '').toString().split(' ')[0]}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    r['activities_completed'] ?? '',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
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
