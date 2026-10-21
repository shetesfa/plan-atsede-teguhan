import 'package:flutter/material.dart';
import '../models/department.dart';
import '../models/plan_item.dart';
import '../models/unplanned_activity.dart';
import '../services/auth_service.dart';
import '../widgets/telegram_connect_dialog.dart';
import '../theme/app_theme.dart';
import 'document_editor_screen.dart';

class DashboardScreen extends StatelessWidget {
  final List<PlanItem> plans;
  final List<UnplannedActivity> unplannedActivities;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final Function(String departmentId) onSelectDepartment;
  final VoidCallback onOpenUnplanned;

  const DashboardScreen({
    super.key,
    required this.plans,
    required this.unplannedActivities,
    required this.onRefresh,
    required this.onLogout,
    required this.onSelectDepartment,
    required this.onOpenUnplanned,
  });

  void _showNotificationsSheet(BuildContext context, List<PlanItem> overduePlans, List<PlanItem> postponedPlans, List<PlanItem> reportedPlans) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 3,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active, color: AppTheme.primaryMaroon),
                        SizedBox(width: 8),
                        Text(
                          'የማሳወቂያ ማዕከል (Notifications)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryMaroon),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                TabBar(
                  labelColor: AppTheme.primaryMaroon,
                  indicatorColor: AppTheme.primaryMaroon,
                  tabs: [
                    Tab(text: '🚨 ያዘገዩ (${overduePlans.length})'),
                    Tab(text: '📅 የተላለፉ (${postponedPlans.length})'),
                    Tab(text: '📋 ሪፖርቶች (${reportedPlans.length})'),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      // 1. ያዘገዩ
                      overduePlans.isEmpty
                          ? const Center(child: Text('ምንም ያዘገየ እቅድ የለም! ሁሉም በጥሩ ሁኔታ ላይ ነው።'))
                          : ListView.builder(
                              itemCount: overduePlans.length,
                              itemBuilder: (c, i) {
                                final p = overduePlans[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Colors.red.shade50,
                                  child: ListTile(
                                    title: Text(p.detailTask.isNotEmpty ? p.detailTask : p.mainTask, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text('ክፍል፦ ${p.departmentName} | የመጀመሪያ ጊዜ፦ ${p.executionTime}', style: const TextStyle(fontSize: 11)),
                                    trailing: const Icon(Icons.alarm, color: Colors.red, size: 20),
                                  ),
                                );
                              },
                            ),

                      // 2. የተላለፉ
                      postponedPlans.isEmpty
                          ? const Center(child: Text('ምንም የተላለፈ እቅድ አልተመዘገበም።'))
                          : ListView.builder(
                              itemCount: postponedPlans.length,
                              itemBuilder: (c, i) {
                                final p = postponedPlans[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Colors.orange.shade50,
                                  child: ListTile(
                                    title: Text(p.detailTask.isNotEmpty ? p.detailTask : p.mainTask, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text('ክፍል፦ ${p.departmentName}\n👉 አዲስ ቀን፦ ${p.postponedDate} (${p.postponeReason ?? ""})', style: const TextStyle(fontSize: 11)),
                                    trailing: const Icon(Icons.update, color: Colors.deepOrange, size: 20),
                                  ),
                                );
                              },
                            ),

                      // 3. ሪፖርቶች
                      reportedPlans.isEmpty
                          ? const Center(child: Text('እስካሁን የቀረበ አዲስ ሪፖርት የለም።'))
                          : ListView.builder(
                              itemCount: reportedPlans.length,
                              itemBuilder: (c, i) {
                                final p = reportedPlans[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Colors.green.shade50,
                                  child: ListTile(
                                    title: Text(p.detailTask.isNotEmpty ? p.detailTask : p.mainTask, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(
                                      'ክፍል፦ ${p.departmentName} (${p.progressPercent}%)\n'
                                      '${p.reportDetails != null && p.reportDetails!.isNotEmpty ? "የተሰራ፦ ${p.reportDetails}\n" : ""}'
                                      '${p.notDoneDetails != null && p.notDoneDetails!.isNotEmpty ? "ምክንያት፦ ${p.notDoneDetails}" : ""}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDept = AuthService.currentDepartment;
    final isSuper = AuthService.isSuperAdmin;

    // ለክፍል ተጠቃሚ ከሆነ የራሱን እቅዶች ብቻ ይመርጣል፤ ለፅ/ቤት ከሆነ ሁሉንም
    final visiblePlans = isSuper
        ? plans
        : plans.where((p) => p.departmentName.contains(currentDept?.shortName ?? '') || p.departmentId == currentDept?.id).toList();

    final totalPlans = visiblePlans.length;
    final completedPlans = visiblePlans.where((p) => p.isCompleted).length;
    final inProgressPlans = visiblePlans.where((p) => p.isInProgress).length;
    final overallPercent = totalPlans > 0 ? ((completedPlans / totalPlans) * 100).toInt() : 0;

    // የተላለፉ፣ ያዘገዩ እና ሪፖርት ያላቸው
    final postponedPlans = visiblePlans.where((p) => p.isPostponed).toList();
    final reportedPlans = visiblePlans.where((p) => p.hasReport || p.progressPercent > 0).toList();
    final overduePlans = visiblePlans.where((p) {
      if (p.isCompleted || p.isPostponed) return false;
      final mes = p.months['መስ'] ?? '';
      final tiq = p.months['ጥቅ'] ?? '';
      return (mes.isNotEmpty && mes != '-') || (tiq.isNotEmpty && tiq != '-');
    }).toList();

    final totalNotifications = overduePlans.length + postponedPlans.length;
    final totalUnplanned = unplannedActivities.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSuper ? 'የፅ/ቤት ማዕከላዊ መቆጣጠሪያ' : '${currentDept?.name}'),
        actions: [
          // የማሳወቂያ ደወል ከቁጥር ባጅ ጋር
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                tooltip: 'ማሳወቂያዎች',
                onPressed: () => _showNotificationsSheet(context, overduePlans, postponedPlans, reportedPlans),
              ),
              if (totalNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$totalNotifications',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.telegram, color: Colors.white),
            tooltip: 'የቴሌግራም ቦት ቅንብር',
            onPressed: () => TelegramConnectDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
            tooltip: 'አድስ',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
            tooltip: 'ውጣ',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // የራስጌ ማራኪ ባነር
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryMaroon.withAlpha(70),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.secondaryGold, width: 2),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentDept?.name ?? 'አጸደ ትጉሃን ሰንበት ት/ቤት',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSuper ? 'የ10ሩ ክፍሎች የ2019 ዓ.ም የቁጥጥር ዳሽቦርድ' : 'የክፍሉ የ2019 ዓ.ም የስራ አፈፃፀም',
                          style: const TextStyle(color: AppTheme.lightGold, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('አጠቃላይ ክንውን፡ ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: AppTheme.goldGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$overallPercent%',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ለፅ/ቤት የሚታይ አዲስ ሪፖርት እና ማስተላለፍ ማሳወቂያ ባነር
            InkWell(
              onTap: () => _showNotificationsSheet(context, overduePlans, postponedPlans, reportedPlans),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightGold,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.secondaryGold),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: AppTheme.primaryMaroon, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'የእቅድ ክትትል እና የማሳወቂያ ማዕከል',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryMaroon),
                          ),
                          Text(
                            '${reportedPlans.length} ሪፖርቶች ቀርበዋል | ${postponedPlans.length} እቅዶች ተላልፈዋል | ${overduePlans.length} ያዘገዩ አሉ (ዝርዝሩን ለማየት ይጫኑ)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.primaryMaroon),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // አጭር ስታቲስቲክስ ካርዶች (ረድፍ 1)
            Row(
              children: [
                _buildStatCard('የታቀዱ እቅዶች', '$totalPlans', Icons.list_alt, AppTheme.primaryMaroon),
                const SizedBox(width: 10),
                _buildStatCard('የተጠናቀቁ', '$completedPlans', Icons.check_circle_outline, AppTheme.greenSuccess),
                const SizedBox(width: 10),
                _buildStatCard('በሂደት ላይ', '$inProgressPlans', Icons.timelapse, AppTheme.secondaryGold),
              ],
            ),
            const SizedBox(height: 10),

            // አጭር ስታቲስቲክስ ካርዶች (ረድፍ 2፦ የተላለፉ፣ ሪፖርቶች፣ ያዘገዩ)
            Row(
              children: [
                _buildStatCard('የተላለፉ እቅዶች', '${postponedPlans.length}', Icons.update, Colors.deepOrange),
                const SizedBox(width: 10),
                _buildStatCard('የቀረቡ ሪፖርቶች', '${reportedPlans.length}', Icons.assignment_turned_in, Colors.teal),
                const SizedBox(width: 10),
                _buildStatCard('ያዘገዩ (Overdue)', '${overduePlans.length}', Icons.alarm, overduePlans.isNotEmpty ? Colors.red : Colors.grey),
              ],
            ),
            const SizedBox(height: 18),

            // ያልታቀዱ ግን የተከናወኑ ስራዎች ካርድ
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppTheme.secondaryGold.withAlpha(80), width: 1),
              ),
              child: ListTile(
                onTap: onOpenUnplanned,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.lightGold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_task, color: AppTheme.primaryMaroon, size: 24),
                ),
                title: const Text(
                  'ያልታቀዱ ግን የተከናወኑ ስራዎች',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'በዓመታዊ እቅድ ውስጥ ያልነበሩ ነገር ግን የተሰሩ ተግባራት ($totalUnplanned ተመዝግበዋል)',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              ),
            ),
            const SizedBox(height: 12),

            // ፈጣን የሰነድ እና ሰንጠረዥ (Word & Excel) ማዘጋጃ ካርዶች
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 0)),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B579A).withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2B579A).withAlpha(40)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.description, color: Color(0xFF2B579A), size: 24),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Word ጽሑፍ ጻፍ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2B579A))),
                                Text('ሪፖርት / ቃለ-ጉባኤ', style: TextStyle(fontSize: 10, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 1)),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF217346).withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF217346).withAlpha(40)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.table_chart_rounded, color: Color(0xFF217346), size: 24),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Excel ሰንጠረዥ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF217346))),
                                Text('በጀት / Auto-sum', style: TextStyle(fontSize: 10, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ፅ/ቤት ከሆነ የ10ሩ ክፍሎች ዝርዝር
            if (isSuper) ...[
              const Text(
                'የ 10ሩ ክፍላት የክንውን ደረጃ እና ዝርዝር እቅድ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: Department.allDepartments.length,
                itemBuilder: (ctx, index) {
                  final dept = Department.allDepartments[index];
                  final deptPlans = plans.where((p) => p.departmentName.contains(dept.shortName) || p.departmentId == dept.id).toList();
                  final deptCompleted = deptPlans.where((p) => p.isCompleted).length;
                  final deptPostponed = deptPlans.where((p) => p.isPostponed).length;
                  final deptPercent = deptPlans.isNotEmpty ? ((deptCompleted / deptPlans.length) * 100).toInt() : 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryMaroon.withAlpha(20),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                        ),
                      ),
                      title: Text(dept.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'ጠቅላላ እቅድ፡ ${deptPlans.length} | የተጠናቀቁ፡ $deptCompleted${deptPostponed > 0 ? " | የተላለፉ: $deptPostponed" : ""}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: deptPlans.isNotEmpty ? (deptCompleted / deptPlans.length) : 0,
                            backgroundColor: Colors.grey.shade200,
                            color: deptPercent == 100 ? AppTheme.greenSuccess : AppTheme.secondaryGold,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$deptPercent%',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryMaroon),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                        ],
                      ),
                      onTap: () => onSelectDepartment(dept.id),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(50)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
