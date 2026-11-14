import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atsede_teguhan_app/models/department.dart';
import 'package:atsede_teguhan_app/models/plan_item.dart';
import 'package:atsede_teguhan_app/services/auth_service.dart';
import 'package:atsede_teguhan_app/screens/login_screen.dart';

// Audit 2026-11-14 (H6): the old tests expected login to succeed with the
// old default password and with an EMPTY password, and expected the login
// screen to log in without a server. All three expectations contradict
// AuthService (empty password is rejected; login always calls the server).
// These tests need NO live server: they cover validation, widget rendering
// and pure model logic only. Nothing here hits the network.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
  });

  group('AuthService validation (no server)', () {
    test('Empty password is rejected and does not log in', () async {
      final dept = Department.allDepartments.first;
      final result = await AuthService.attemptLogin(dept, '');
      expect(result, isNotNull);
      expect(result, contains('የይለፍ ቃል'));
      expect(AuthService.isLoggedIn, isFalse);
      expect(AuthService.currentDepartment, isNull);
    });

    test('Empty password is rejected for every department', () async {
      for (final dept in Department.allDepartments) {
        final result = await AuthService.attemptLogin(dept, '');
        expect(result, isNotNull, reason: 'dept ${dept.id}');
        expect(AuthService.isLoggedIn, isFalse);
      }
    });

    test('AuthService is not locked before any failed attempt', () {
      expect(AuthService.isLocked, isFalse);
      expect(AuthService.failedAttempts, 0);
    });

    test('Logout clears current department and profile', () async {
      await AuthService.logout();
      expect(AuthService.isLoggedIn, isFalse);
      expect(AuthService.currentDepartment, isNull);
      expect(AuthService.currentUserProfile, isNull);
    });
  });

  group('Department model', () {
    test('There are 10 departments with unique ids', () {
      expect(Department.allDepartments.length, 10);
      final ids = Department.allDepartments.map((d) => d.id).toSet();
      expect(ids.length, 10);
    });

    test('First department is the super-admin office', () {
      final admin = Department.allDepartments.first;
      expect(admin.id, 'admin');
      expect(admin.isSuperAdmin, isTrue);
      expect(
        Department.allDepartments.where((d) => d.isSuperAdmin).length,
        1,
      );
    });
  });

  group('PlanItem pure logic', () {
    PlanItem sample({int progress = 0}) {
      return PlanItem(
        id: 'plan-1',
        departmentId: 'education',
        departmentName: 'ትምህርት እና ስልጠና ክፍል',
        subDepartment: '',
        mainTask: 'የሰንበት ትምህርት ማጠናከር',
        detailTask: 'የመምህራን ስልጠና',
        measurement: 'ሰልጣኞች',
        quantity: '20',
        executionTime: 'መስከረም',
        budget: '5000',
        remarks: '',
        months: {'መስ': '10'},
        progressPercent: progress,
      );
    }

    test('Progress getters reflect the percent', () {
      expect(sample(progress: 0).isNotStarted, isTrue);
      expect(sample(progress: 0).isCompleted, isFalse);
      expect(sample(progress: 50).isInProgress, isTrue);
      expect(sample(progress: 100).isCompleted, isTrue);
      expect(sample(progress: 100).isInProgress, isFalse);
    });

    test('Title falls back to mainTask when detailTask is empty', () {
      final item = sample()..detailTask = '';
      expect(item.title, 'የሰንበት ትምህርት ማጠናከር');
      expect(sample().title, 'የመምህራን ስልጠና');
    });

    test('fromJson / toJson round-trip keeps fields', () {
      final item = sample(progress: 50);
      final restored = PlanItem.fromJson(item.toJson());
      expect(restored.id, item.id);
      expect(restored.departmentId, item.departmentId);
      expect(restored.mainTask, item.mainTask);
      expect(restored.progressPercent, 50);
      expect(restored.months['መስ'], '10');
    });

    test('fromJson tolerates missing optional fields', () {
      final item = PlanItem.fromJson({'id': 'x'});
      expect(item.id, 'x');
      expect(item.progressPercent, 0);
      expect(item.isNotStarted, isTrue);
      expect(item.months, isEmpty);
    });

    test('Postpone and report flags', () {
      final item = sample();
      expect(item.isPostponed, isFalse);
      expect(item.hasReport, isFalse);
      final postponed = item.copyWith(
        postponedDate: '20/02/2019 ዓ.ም',
        postponeReason: 'ዝናብ',
      );
      expect(postponed.isPostponed, isTrue);
      expect(
        postponed.effectiveExecutionTime,
        contains('የተላለፈበት'),
      );
      final reported = item.copyWith(reportDetails: 'ስልጠና ተሰጥቷል');
      expect(reported.hasReport, isTrue);
    });
  });

  group('LoginScreen widget (no server)', () {
    Future<void> pumpLogin(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(onLoginSuccess: () {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('LoginScreen renders title, department picker and login button',
        (WidgetTester tester) async {
      await pumpLogin(tester);

      expect(find.text('ዓጸደ ትጉሃን ሰንበት ት/ቤት'), findsOneWidget);
      expect(find.text('የአመራር መግቢያ በር'), findsOneWidget);
      expect(find.text('ክፍልዎን ይምረጡ'), findsOneWidget);
      expect(find.text('የይለፍ ቃል'), findsWidgets);
      expect(find.text('ወደ ስርዓቱ ግባ'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(DropdownButton<Department>), findsOneWidget);
    });

    testWidgets('LoginScreen shows no default password anywhere',
        (WidgetTester tester) async {
      await pumpLogin(tester);

      // No hint, label or text may advertise a default password (H7).
      expect(find.textContaining('ነባሪ'), findsNothing);
      // The hint now points at the church office instead.
      expect(find.textContaining('ከቤተክርስቲያኑ ፅ/ቤት'), findsOneWidget);
    });

    testWidgets('Tapping login with an empty password shows a validation error',
        (WidgetTester tester) async {
      bool loginTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            onLoginSuccess: () {
              loginTriggered = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ወደ ስርዓቱ ግባ'));
      await tester.pump();

      expect(find.text('እባክዎ የይለፍ ቃል ያስገቡ።'), findsOneWidget);
      expect(loginTriggered, isFalse);
      expect(AuthService.isLoggedIn, isFalse);
    });
  });
}
