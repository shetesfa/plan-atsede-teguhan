import 'package:flutter/material.dart';
import '../models/plan_item.dart';
import '../models/unplanned_activity.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/offline_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/ethiopian_date_display.dart';
import 'dashboard_screen.dart';
import 'plans_screen.dart';
import 'letter_generator_screen.dart';
import 'proposal_generator_screen.dart';
import 'unplanned_activities_screen.dart';
import 'document_editor_screen.dart';
import 'office_reports_screen.dart';
import 'plan_calendar_screen.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'change_password_screen.dart';

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
  String? _serverError;
  // 2026-11-26: unplanned works load from the server — when the load
  // fails the list stays EMPTY (no stale data) and this holds the error
  // shown on the unplanned screen.
  String? _unplannedError;
  String? selectedDeptForPlans;
  // ከመስመር ውጭ ሲሆን እቅዶቹ ከካሽ ይታያሉ — ማሳያው ይህን ያመለክታል።
  bool _isOffline = false;
  String? _lastSyncText;

  @override
  void initState() {
    super.initState();
    _loadInitialPlans();
  }

  // 2026-11-26 (startup fix): OFFLINE-FIRST — show the cached plans
  // immediately, then refresh from the server in the background (fetchPlans
  // retries itself while the Render server wakes). The full-screen
  // "server not found" error appears ONLY when there is truly no cache
  // AND the server is unreachable after retries.
  Future<void> _loadInitialPlans() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        _serverError = null;
      });
    }
    final deptId = AuthService.currentDepartment?.id ?? 'admin';
    // 1. Cached plans first — the app opens instantly, even offline.
    var cached = <Map<String, dynamic>>[];
    try {
      cached = await OfflineSyncService.getCachedPlans(deptId);
    } catch (_) {}
    if (cached.isNotEmpty && mounted) {
      final lastSync = await OfflineSyncService.getLastSyncTime();
      setState(() {
        plans = cached.map((d) => PlanItem.fromDbJson(d)).toList();
        isLoading = false;
        _isOffline = true;
        _lastSyncText =
            lastSync != null ? formatEthiopianDate(lastSync) : null;
        _serverError = null;
      });
    }
    // 2. Server refresh in the background (retries inside fetchPlans).
    try {
      final remoteData = await ApiService().fetchPlans();
      final dbPlans = remoteData.map((d) => PlanItem.fromDbJson(d)).toList();
      await OfflineSyncService.cachePlans(deptId, remoteData);
      if (!mounted) return;
      setState(() {
        plans = dbPlans;
        isLoading = false;
        _isOffline = false;
        _lastSyncText = null;
      });
    } on ApiException catch (e) {
      // Server still unreachable after retries — keep the cached plans
      // on screen (offline banner); only show the error when no cache
      // exists at all.
      if (cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            isLoading = false;
          });
        }
      } else {
        await _loadFromCacheOrError(deptId, e.message);
      }
    } catch (e) {
      if (cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            isLoading = false;
          });
        }
      } else {
        await _loadFromCacheOrError(deptId, e.toString());
      }
    }
    await _loadUnplannedActivities();
  }

  /// ያልታቀዱ ስራዎች ከሰርቨር ይጫናሉ (2026-11-26: server storage —
  /// አካባቢው ብቻ ከሆነ app ሲዘጋ ይጠፋሉ, ስለዚህ ካሽ የለም። ካልተጫኑ
  /// ዝርዝሩ ባዶ ሆኖ ይቀራል እና ስህተቱ ይታያል — ያረጀ መረጃ አይታይም።
  Future<void> _loadUnplannedActivities() async {
    try {
      final remote = await ApiService().fetchUnplannedActivities();
      final acts = remote.map((d) => UnplannedActivity.fromDbJson(d)).toList();
      if (mounted) {
        setState(() {
          unplannedActivities = acts;
          _unplannedError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          unplannedActivities = [];
          _unplannedError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          unplannedActivities = [];
          _unplannedError = e.toString();
        });
      }
    }
  }

  /// Server unreachable: show the last synced plans (offline) when any
  /// are cached; only show the error screen when nothing is cached yet
  /// (e.g. first launch with no internet).
  Future<void> _loadFromCacheOrError(String deptId, String message) async {
    final cached = await OfflineSyncService.getCachedPlans(deptId);
    if (!mounted) return;
    if (cached.isNotEmpty) {
      final lastSync = await OfflineSyncService.getLastSyncTime();
      final dbPlans = cached.map((d) => PlanItem.fromDbJson(d)).toList();
      setState(() {
        plans = dbPlans;
        isLoading = false;
        _isOffline = true;
        _lastSyncText =
            lastSync != null ? formatEthiopianDate(lastSync) : null;
        _serverError = null;
      });
    } else {
      setState(() {
        plans = [];
        _serverError = message;
        isLoading = false;
        _isOffline = false;
      });
    }
  }

  /// ከመስመር ውጭ ሲሆን ከገጹ በላይ የሚታይ ማሳያ — የተቀመጠ መረጃ
  /// እያሳየ መሆኑን እና መቼ እንደተመሳከረ ያሳያል።
  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _lastSyncText != null
                  ? 'offline — የተቀመጠ መረጃ እያሳየ ነው (መጨረሻ ማመሳከሪያ፦ $_lastSyncText)'
                  : 'offline — የተቀመጠ መረጃ እያሳየ ነው',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: _loadInitialPlans,
            child: const Text('እንደገና ሞክር',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
          loadError: _unplannedError,
          // 2026-11-26: server FIRST — the local list changes only after
          // the server confirms the save. On failure the dialog stays
          // open and the error is shown (the screen shows the message).
          onAddActivity: (act, {String? evidenceBase64, String? evidenceName}) async {
            final body = act.toServerJson();
            if (evidenceBase64 != null) {
              body['evidence_base64'] = evidenceBase64;
              body['evidence_name'] = evidenceName ?? 'evidence.jpg';
            }
            final res = await ApiService().createUnplannedActivity(body);
            if (res['success'] == true && res['data'] is Map) {
              final saved = UnplannedActivity.fromDbJson(
                  Map<String, dynamic>.from(res['data'] as Map));
              if (mounted) {
                setState(() => unplannedActivities.insert(0, saved));
              }
              return {'success': true};
            }
            return {
              'success': false,
              'message': res['message'] ?? 'ስራውን መመዝገብ አልተቻለም'
            };
          },
          onUpdateActivity: (act, {String? evidenceBase64, String? evidenceName}) async {
            final body = act.toServerJson();
            if (evidenceBase64 != null) {
              body['evidence_base64'] = evidenceBase64;
              body['evidence_name'] = evidenceName ?? 'evidence.jpg';
            }
            final res = await ApiService().updateUnplannedActivity(act.id, body);
            if (res['success'] == true && res['data'] is Map) {
              final saved = UnplannedActivity.fromDbJson(
                  Map<String, dynamic>.from(res['data'] as Map));
              if (mounted) {
                setState(() {
                  final idx =
                      unplannedActivities.indexWhere((a) => a.id == saved.id);
                  if (idx != -1) unplannedActivities[idx] = saved;
                });
              }
              return {'success': true};
            }
            return {
              'success': false,
              'message': res['message'] ?? 'ስራውን ማሻሻል አልተቻለም'
            };
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

    // Audit fix 2026-11-25: ነባሪ (seed) የይለፍ ቃል ያለው ተጠቃሚ
    // በመጀመሪያ መግቢያ ላይ የይለፍ ቃል መቀየር አለበት — ይህን ገጽ ሳይቀይር
    // ወደ ዋናው ገጽ መግባት አይችልም።
    if (AuthService.mustChangePassword) {
      return ChangePasswordScreen(
        mustChange: true,
        onPasswordChanged: () => setState(() {}),
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
                'የዐጸደ ትጉሃን እቅድ እየተጫነ ነው...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Server could not be reached: plans live on the server only,
    // so there is nothing local to show — offer a retry instead.
    if (_serverError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'ሰርቨሩ አልተገኘም',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ኢንተርኔት አልተገኘም — እቅዶች ገና በአካባቢው አልተቀመጡም። እባክዎ ኢንተርኔትዎን ይፈትሹ እና እንደገና ይሞክሩ።',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadInitialPlans,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryMaroon,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('እንደገና ሞክር'),
                ),
              ],
            ),
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
      body: Column(
        children: [
          if (_isOffline) _buildOfflineBanner(),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
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
      backgroundColor: AppTheme.surfaceBg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLetterheadHeader(context),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'የሚፈልጉትን አገልግሎት ይምረጡ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.primaryMaroon,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: Divider(color: AppTheme.secondaryGold, thickness: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 2026-11-28: Office Review is for the office (super admin)
            // and the control department (can_view_all, view-only) only.
            // A department head is admin inside their OWN plan control,
            // but must not see or control other departments' reports —
            // so this card stays hidden for them.
            if (AuthService.isSuperAdmin || AuthService.canViewAll)
              _paperCard(
                context: context,
                icon: Icons.rate_review_outlined,
                iconColor: AppTheme.primaryMaroon,
                title: 'የክንውን ሪፖርቶች መገምገሚያ (Office Review)',
                subtitle: 'በክፍሎች የቀረቡ የክንውን ሪፖርቶችን ይገምግሙ፣ ያጽድቁ፣ ወይም ማሻሻያ አስተያየት ይስጡ።',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (ctx) => const OfficeReportsScreen()),
                ),
              ),
            _paperCard(
              context: context,
              icon: Icons.mail_outline,
              iconColor: AppTheme.primaryMaroon,
              title: 'ይፋዊ ደብዳቤ መጻፊያ',
              subtitle: 'ለማንኛውም አካል በዐጸደ ትጉሃን አርማ እና ፎርማት ይፋዊ ደብዳቤ አዘጋጅተው ወደ PDF ያውጡ።',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const LetterGeneratorScreen()),
              ),
            ),
            _paperCard(
              context: context,
              icon: Icons.assignment_outlined,
              iconColor: AppTheme.secondaryGold,
              title: 'ይፋዊ ፕሮፖዛል ማዘጋጃ',
              subtitle: 'ለበዓላት ወይም ለስራዎች የበጀት ሰንጠረዥ የያዘ ይፋዊ ፕሮፖዛል አዘጋጅተው ወደ PDF ያውጡ።',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const ProposalGeneratorScreen()),
              ),
            ),
            _paperCard(
              context: context,
              icon: Icons.playlist_add_check,
              iconColor: AppTheme.greenSuccess,
              title: 'ያልታቀዱ ግን የተከናወኑ ስራዎች',
              subtitle: 'በዓመታዊ እቅድ ውስጥ ያልነበሩ ነገር ግን በድንገት የተከናወኑ ተግባራትን መዝግበው ለፅ/ቤት ያቅርቡ።',
              onTap: onOpenUnplanned,
            ),
            _paperCard(
              context: context,
              icon: Icons.description,
              iconColor: const Color(0xFF2B579A),
              title: 'Word የጽሑፍ ሰነድ መጻፊያ',
              subtitle: 'ኮምፒውተር ሳይኖር በስልክዎ በቀላሉ የክንውን ሪፖርት፣ ቃለ-ጉባኤ እና ማስታወሻዎችን አዘጋጅተው ወደ PDF እና ቴሌግራም ያውጡ።',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => const DocumentEditorScreen()),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Text(
                'ሁሉም ሰነዶች በቤተክርስቲያኗ አርማ እና ይፋዊ ፎርማት ወደ PDF ይወጣሉ።',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// የቤተክርስቲያኗ ይፋዊ አርማ ያለው የሰነድ ራስጌ (Letterhead)።
  Widget _buildLetterheadHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.darkMaroon, AppTheme.primaryMaroon],
        ),
        border: Border(
          bottom: BorderSide(color: AppTheme.secondaryGold, width: 3),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 18,
        20,
        22,
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppTheme.secondaryGold, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.secondaryGold.withAlpha(120),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: ClipOval(
              child: Image.asset(
                'assets/icon.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.church_rounded,
                  size: 56,
                  color: AppTheme.primaryMaroon,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ዐጸደ ትጉሃን ሰንበት ት/ቤት',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ይፋዊ ሰነዶች እና ስራዎች ማዘጋጃ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryGold,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Container(width: 64, height: 2, color: AppTheme.secondaryGold),
          const SizedBox(height: 10),
          const Text(
            'የቤተክርስቲያኗ ይፋዊ ሰነዶች ብቻ',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// የወረቀት ገጽ የሚመስል ሰነድ ካርድ — ከላይ የቤተክርስቲያኗ አርማ ያለው
  /// ራስጌ (letterhead) እና የወርቅ መስመር አለው፣ ልክ እንደ Word ገጽ።
  Widget _paperCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // የሰነድ ራስጌ — አርማ + የቤተክርስቲያኗ ስም (ልክ እንደ እውነተኛ ወረቀት)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: AppTheme.secondaryGold, width: 1.5),
                      ),
                      padding: const EdgeInsets.all(1),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.church_rounded,
                            size: 16,
                            color: AppTheme.primaryMaroon,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ዐጸደ ትጉሃን ሰንበት ት/ቤት',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryMaroon,
                        ),
                      ),
                    ),
                    const Text(
                      'ይፋዊ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryGold,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Divider(color: AppTheme.secondaryGold, thickness: 1, height: 1),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: iconColor.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
