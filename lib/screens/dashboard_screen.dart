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

  void _showNotificationsSheet(
    BuildContext context,
    List<PlanItem> overduePlans,
    List<PlanItem> postponedPlans,
    List<PlanItem> reportedPlans,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryMaroon.withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.notifications_active, color: AppTheme.primaryMaroon, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'የማሳወቂያ ማዕከል',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.primaryMaroon),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  labelColor: AppTheme.primaryMaroon,
                  indicatorColor: AppTheme.primaryMaroon,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  unselectedLabelColor: AppTheme.textMuted,
                  tabs: [
                    Tab(text: '🚨 ያዘገዩ (${overduePlans.length})'),
                    Tab(text: '📅 የተላለፉ (${postponedPlans.length})'),
                    Tab(text: '📋 ሪፖርቶች (${reportedPlans.length})'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [
                      // 1. ያዘገዩ
                      overduePlans.isEmpty
                          ? _buildEmptyState('ምንም ያዘገየ እቅድ የለም! ሁሉም በሰዓቱ እየተከናወነ ነው።', Icons.check_circle_outline)
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: overduePlans.length,
                              itemBuilder: (c, i) {
                                final p = overduePlans[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.redBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppTheme.redDanger.withAlpha(50)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    leading: const CircleAvatar(
                                      backgroundColor: AppTheme.redDanger,
                                      child: Icon(Icons.alarm, color: Colors.white, size: 20),
                                    ),
                                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(
                                      'ክፍል፦ ${p.departmentName}\nየማስፈጸሚያ ወር፦ መስከረም / ጥቅምት',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.redDanger),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      onSelectDepartment(p.departmentId);
                                    },
                                  ),
                                );
                              },
                            ),

                      // 2. የተላለፉ
                      postponedPlans.isEmpty
                          ? _buildEmptyState('የተላለፈ እቅድ አልተገኘም።', Icons.calendar_today_outlined)
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: postponedPlans.length,
                              itemBuilder: (c, i) {
                                final p = postponedPlans[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.amberBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppTheme.amberWarning.withAlpha(50)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    leading: const CircleAvatar(
                                      backgroundColor: AppTheme.amberWarning,
                                      child: Icon(Icons.update, color: Colors.white, size: 20),
                                    ),
                                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(
                                      'ክፍል፦ ${p.departmentName}\nአዲስ ቀን፦ ${p.postponedDate ?? "ያልተጠቀሰ"}\nምክንያት፦ ${p.postponeReason ?? "ያልተገለጸ"}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ),
                                );
                              },
                            ),

                      // 3. የቀረቡ ሪፖርቶች
                      reportedPlans.isEmpty
                          ? _buildEmptyState('እስካሁን የቀረበ ሪፖርት የለም።', Icons.description_outlined)
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: reportedPlans.length,
                              itemBuilder: (c, i) {
                                final p = reportedPlans[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.greenBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppTheme.greenSuccess.withAlpha(50)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    leading: const CircleAvatar(
                                      backgroundColor: AppTheme.greenSuccess,
                                      child: Icon(Icons.done_all, color: Colors.white, size: 20),
                                    ),
                                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text(
                                      'ክፍል፦ ${p.departmentName}\nየተከናወነ፦ ${p.doneDetails ?? "ዝርዝር አለ"}\nደረጃ፦ ${p.progressPercent}% ተጠናቋል',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
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

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppTheme.textMuted.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDept = AuthService.currentDepartment;
    final isSuper = AuthService.isSuperAdmin;

    final visiblePlans = isSuper
        ? plans
        : plans
            .where((p) =>
                p.departmentName.contains(currentDept?.shortName ?? '') ||
                p.departmentId == currentDept?.id)
            .toList();

    final totalPlans = visiblePlans.length;
    final completedPlans = visiblePlans.where((p) => p.isCompleted).length;
    final inProgressPlans = visiblePlans.where((p) => p.isInProgress).length;
    final overallPercent = totalPlans > 0 ? ((completedPlans / totalPlans) * 100).toInt() : 0;

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
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: Text(isSuper ? 'የፅ/ቤት ማዕከላዊ መቆጣጠሪያ' : '${currentDept?.name}'),
        actions: [
          // የማሳወቂያ ደወል
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
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
                      color: AppTheme.brightGold,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$totalNotifications',
                      style: const TextStyle(color: AppTheme.darkMaroon, fontSize: 10, fontWeight: FontWeight.bold),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🌟 1. ፕሪሚየም የራስጌ ባነር (Hero Executive Banner)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: AppTheme.primaryGlow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.secondaryGold, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(
                      child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(width: 16),
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
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSuper ? 'የ10ሩ ክፍላት የ2019 ዓ.ም ማዕከላዊ ቁጥጥር' : 'የክፍሉ የ2019 ዓ.ም የስራ አፈፃፀም',
                          style: const TextStyle(color: AppTheme.lightGold, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        // የአፈፃፀም ባር
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: totalPlans > 0 ? (completedPlans / totalPlans) : 0,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.brightGold),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryGold,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$overallPercent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
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

            // ⚡ 2. ፈጣን ተግባራት (Quick Actions Grid)
            Row(
              children: [
                _buildQuickAction(
                  context,
                  title: 'Word ጽሑፍ',
                  subtitle: 'ሪፖርት/ደብዳቤ',
                  icon: Icons.article_rounded,
                  color: const Color(0xFF2B579A),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 0)),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  title: 'Excel ሰንጠረዥ',
                  subtitle: 'በጀት/ሒሳብ',
                  icon: Icons.table_chart_rounded,
                  color: const Color(0xFF217346),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 1)),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  title: 'ያልታቀዱ',
                  subtitle: '$totalUnplanned ስራዎች',
                  icon: Icons.add_task_rounded,
                  color: AppTheme.primaryMaroon,
                  onTap: onOpenUnplanned,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 🚨 3. የማሳወቂያ ማጠቃለያ ባነር
            InkWell(
              onTap: () => _showNotificationsSheet(context, overduePlans, postponedPlans, reportedPlans),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.secondaryGold.withAlpha(90)),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightGold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: AppTheme.secondaryGold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'የእቅድ ክትትል እና የማሳወቂያ ማዕከል',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryMaroon),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${reportedPlans.length} ሪፖርቶች ቀርበዋል | ${postponedPlans.length} ተላልፈዋል | ${overduePlans.length} ያዘገዩ አሉ',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.primaryMaroon),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 📊 4. ዘመናዊ KPI ስታቲስቲክስ ካርዶች
            const Text(
              'የአፈፃፀም ማጠቃለያ ቁጥሮች',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildModernStatCard('ጠቅላላ እቅዶች', '$totalPlans', Icons.list_alt_rounded, AppTheme.primaryMaroon, AppTheme.surfaceBg),
                const SizedBox(width: 10),
                _buildModernStatCard('የተጠናቀቁ', '$completedPlans', Icons.check_circle_rounded, AppTheme.greenSuccess, AppTheme.greenBg),
                const SizedBox(width: 10),
                _buildModernStatCard('በሂደት ላይ', '$inProgressPlans', Icons.timelapse_rounded, AppTheme.amberWarning, AppTheme.amberBg),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildModernStatCard('የተላለፉ', '${postponedPlans.length}', Icons.update_rounded, AppTheme.purpleAccent, AppTheme.purpleBg),
                const SizedBox(width: 10),
                _buildModernStatCard('ሪፖርቶች', '${reportedPlans.length}', Icons.assignment_turned_in_rounded, AppTheme.blueInfo, AppTheme.blueBg),
                const SizedBox(width: 10),
                _buildModernStatCard('ያዘገዩ', '${overduePlans.length}', Icons.alarm_rounded, overduePlans.isNotEmpty ? AppTheme.redDanger : AppTheme.textMuted, overduePlans.isNotEmpty ? AppTheme.redBg : AppTheme.surfaceBg),
              ],
            ),
            const SizedBox(height: 24),

            // 🏛 5. የ 10ሩ ክፍላት የደረጃ ሰንጠረዥ (ለፅ/ቤት)
            if (isSuper) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'የ 10ሩ ክፍላት የአፈፃፀም ደረጃ',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryMaroon),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryMaroon.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('2019 ዓ.ም', style: TextStyle(color: AppTheme.primaryMaroon, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
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

                  // የሜዳሊያ ወይም የደረጃ ምልክት
                  String badge = '${index + 1}';
                  Color badgeBg = AppTheme.primaryMaroon.withAlpha(20);
                  Color badgeColor = AppTheme.primaryMaroon;
                  if (index == 0) {
                    badge = '🥇';
                    badgeBg = const Color(0xFFFFD700).withAlpha(50);
                  } else if (index == 1) {
                    badge = '🥈';
                    badgeBg = const Color(0xFFC0C0C0).withAlpha(50);
                  } else if (index == 2) {
                    badge = '🥉';
                    badgeBg = const Color(0xFFCD7F32).withAlpha(50);
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderLight),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: badgeBg,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: index < 3 ? 16 : 13, color: badgeColor),
                        ),
                      ),
                      title: Text(dept.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'ጠቅላላ እቅድ፡ ${deptPlans.length} | የተጠናቀቁ፡ $deptCompleted${deptPostponed > 0 ? " | የተላለፉ: $deptPostponed" : ""}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: deptPlans.isNotEmpty ? (deptCompleted / deptPlans.length) : 0,
                              backgroundColor: Colors.grey.shade100,
                              color: deptPercent == 100 ? AppTheme.greenSuccess : AppTheme.secondaryGold,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: deptPercent == 100 ? AppTheme.greenBg : AppTheme.surfaceBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$deptPercent%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: deptPercent == 100 ? AppTheme.greenSuccess : AppTheme.primaryMaroon,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textMuted),
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

  Widget _buildQuickAction(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(40)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernStatCard(String title, String value, IconData icon, Color color, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
