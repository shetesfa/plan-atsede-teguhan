import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atsede_teguhan_app/models/department.dart';
import 'package:atsede_teguhan_app/services/auth_service.dart';
import 'package:atsede_teguhan_app/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthService Tests', () {
    test('Successful login with default password 1234', () async {
      final dept = Department.allDepartments.first;
      final result = await AuthService.attemptLogin(dept, '1234');
      expect(result, isNull);
      expect(AuthService.isLoggedIn, isTrue);
      expect(AuthService.currentDepartment?.id, equals(dept.id));
    });

    test('Successful login with empty password for convenience', () async {
      final dept = Department.allDepartments[1];
      final result = await AuthService.attemptLogin(dept, '');
      expect(result, isNull);
      expect(AuthService.isLoggedIn, isTrue);
      expect(AuthService.currentDepartment?.id, equals(dept.id));
    });

    test('Logout clears current department', () async {
      await AuthService.logout();
      expect(AuthService.isLoggedIn, isFalse);
      expect(AuthService.currentDepartment, isNull);
    });
  });

  group('LoginScreen Widget Tests', () {
    testWidgets('LoginScreen shows logo and title, and triggers dialog on tap', (WidgetTester tester) async {
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

      // ርዕሶቹ መኖራቸውን ማረጋገጥ
      expect(find.text('አጸደ ትጉሃን ሰንበት ትምህርት ቤት'), findsOneWidget);
      expect(find.text('የአመራሮች እቅድ መቆጣጠሪያ መተግበሪያ'), findsOneWidget);

      // አርማው ሲነካ የመግቢያ ሳጥን (Dialog) መከፈቱን መፈተሽ
      await tester.tap(find.text('አጸደ ትጉሃን ሰንበት ትምህርት ቤት'));
      await tester.pump(const Duration(milliseconds: 500));

      // በመስኮቱ ውስጥ 'የአመራር መግቢያ በር' እና 'ግባ' አዝራር መታየታቸውን ማረጋገጥ
      expect(find.text('የአመራር መግቢያ በር'), findsOneWidget);
      expect(find.text('ግባ'), findsOneWidget);

      // 'ግባ' የሚለውን አዝራር ጠቅ ሲደረግ ስኬታማ መግቢያ መከናወኑን መፈተሽ
      await tester.tap(find.text('ግባ'));
      await tester.idle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(AuthService.isLoggedIn, isTrue);
      expect(loginTriggered, isTrue);
    });
  });
}
