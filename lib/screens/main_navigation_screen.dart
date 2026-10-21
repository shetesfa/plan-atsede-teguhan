import 'package:flutter/material.dart';
import '../models/plan_item.dart';
import '../models/unplanned_activity.dart';
import '../services/auth_service.dart';
import '../services/excel_importer.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'plans_screen.dart';
import 'letter_generator_screen.dart';
import 'proposal_generator_screen.dart';
import 'unplanned_activities_screen.dart';
import 'document_editor_screen.dart';
import 'plan_calendar_screen.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  List<PlanItem> plans = [];
  List<UnplannedActivity> unplannedActivities = [];
  bool isLoading = true;
  String? selectedDeptForPlans;

  @override
  void initState() {
    super.initState();
    _loadInitialPlans();
  }

  Future<void> _loadInitialPlans() async {
    setState(() => isLoading = true);
    final loadedPlans = await ExcelImporterService.loadPlans();
    setState(() {
      plans = loadedPlans;
      isLoading = false;
    });
  }

  void _onSelectDepartmentFromDashboard(String departmentId) {
    setState(() {
      selectedDeptForPlans = departmentId;
      _currentIndex = 1;
    });
  }

  void _openUnplannedScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => UnplannedActivitiesScreen(
          activities: unplannedActivities,
          onAddActivity: (act) {
            setState(() {
              unplannedActivities.insert(0, act);
            });
          },
          onUpdateActivity: (act) {
            setState(() {
              final idx = unplannedActivities.indexWhere((a) => a.id == act.id);
              if (idx != -1) unplannedActivities[idx] = act;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ተጠቃሚው ካልገባ መጀመሪያ LoginScreen ያሳያል!
    if (!AuthService.isLoggedIn) {
      return LoginScreen(
        onLoginSuccess: () {
          setState(() {
            _currentIndex = 0;
            selectedDeptForPlans = null;
          });
        },
      );
    }

    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryMaroon),
              SizedBox(height: 16),
              Text(
                'የአጸደ ትጉሃን እቅድ እየተጫነ ነው...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final pages = [
      DashboardScreen(
        plans: plans,
        unplannedActivities: unplannedActivities,
        onRefresh: _loadInitialPlans,
        onLogout: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('ከስርዓቱ ለመውጣት ይፈልጋሉ?', style: TextStyle(fontSize: 16)),
              content: const Text('«አዎ» ካሉ ከክፍለ-ጊዜው ወጥተው ወደ ዋናው ገጽ ይመለሳሉ።', style: TextStyle(fontSize: 13)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('ይቅር'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('አዎ፣ ውጣ', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await AuthService.logout();
            if (mounted) setState(() {});
          }
        },
        onSelectDepartment: _onSelectDepartmentFromDashboard,
        onOpenUnplanned: _openUnplannedScreen,
      ),
      PlansScreen(
        plans: plans,
        initialDepartmentId: selectedDeptForPlans,
        onUpdatePlan: (updated) {
          setState(() {
            final idx = plans.indexWhere((p) => p.id == updated.id);
            if (idx != -1) {
              plans[idx] = updated;
            }
          });
        },
        onImportNewPlans: (newPlans) {
          setState(() {
            plans = newPlans;
          });
        },
      ),
      PlanCalendarScreen(
        plans: plans,
        onUpdatePlan: (updated) {
          setState(() {
            final idx = plans.indexWhere((p) => p.id == updated.id);
            if (idx != -1) plans[idx] = updated;
          });
        },
      ),
      DocumentsHubScreen(onOpenUnplanned: _openUnplannedScreen),
      const ChatScreen(),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
            if (idx != 1) selectedDeptForPlans = null;
          });
        },
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.lightGold,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppTheme.primaryMaroon),
            label: 'ዳሽቦርድ',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check, color: AppTheme.primaryMaroon),
            label: 'እቅዶች',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month, color: AppTheme.primaryMaroon),
            label: 'ቀን መቁጠሪያ',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description, color: AppTheme.primaryMaroon),
            label: 'ሰነዶች',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat, color: AppTheme.primaryMaroon),
            label: 'ውይይት',
          ),
        ],
      ),
    );
  }
}

class DocumentsHubScreen extends StatelessWidget {
  final VoidCallback onOpenUnplanned;

  const DocumentsHubScreen({super.key, required this.onOpenUnplanned});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ይፋዊ ሰነዶች እና ስራዎች ማዘጋጃ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'የሚፈልጉትን አገልግሎት ይምረጡ፡',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryMaroon),
            ),
            const SizedBox(height: 14),

            // ደብዳቤ ካርድ
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryMaroon.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mail_outline, color: AppTheme.primaryMaroon, size: 26),
                ),
                title: const Text(
                  'ይፋዊ ደብዳቤ መጻፊያ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'ለማንኛውም አካል በአጸደ ትጉሃን አርማ እና ፎርማት ይፋዊ ደብዳቤ አዘጋጅተው ወደ PDF ያውጡ።',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => const LetterGeneratorScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ፕሮፖዛል ካርድ
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryGold.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_outlined, color: AppTheme.secondaryGold, size: 26),
                ),
                title: const Text(
                  'ይፋዊ ፕሮፖዛል ማዘጋጃ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'ለበዓላት ወይም ለስራዎች የበጀት ሰንጠረዥ የያዘ ይፋዊ ፕሮፖዛል አዘጋጅተው ወደ PDF ያውጡ።',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => const ProposalGeneratorScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ያልታቀደ ግን የተከናወነ ስራ ካርድ
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.greenSuccess.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.playlist_add_check, color: AppTheme.greenSuccess, size: 26),
                ),
                title: const Text(
                  'ያልታቀዱ ግን የተከናወኑ ስራዎች',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'በዓመታዊ እቅድ ውስጥ ያልነበሩ ነገር ግን በድንገት የተከናወኑ ተግባራትን መዝግበው ለፅ/ቤት ያቅርቡ።',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: onOpenUnplanned,
              ),
            ),
            const SizedBox(height: 12),

            // 1. Word ሰነድ መጻፊያ ካርድ
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B579A).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.description, color: Color(0xFF2B579A), size: 28),
                ),
                title: const Text(
                  'Word የጽሑፍ ሰነድ መጻፊያ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'ኮምፒውተር ሳይኖር በስልክዎ በቀላሉ የክንውን ሪፖርት፣ ቃለ-ጉባኤ እና ማስታወሻዎችን አዘጋጅተው ወደ PDF እና ቴሌግራም ያውጡ።',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 0)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // 2. Excel ሰንጠረዥና በጀት ሰሪ ካርድ
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF217346).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Color(0xFF217346), size: 28),
                ),
                title: const Text(
                  'Excel የሰንጠረዥና የበጀት ሰሪ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'የእቃ፣ የስራና የወጪ ዝርዝር ሰንጠረዥ አዘጋጅተው ዋጋውን በራስ-ሰር (Auto-sum) አስልተው ወደ PDF ያውጡ።',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen(initialTabIndex: 1)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
