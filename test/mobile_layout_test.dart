import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/auth/auth_form_page.dart';
import 'package:owniverse/features/onboarding/onboarding_page.dart';

/// The app is built for phones as well as desktops, so the single column has to
/// survive a 360 px viewport without overflowing.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildTheme(), home: child),
      ),
    );
    await tester.pump();
  }

  testWidgets('onboarding fits a 360 px phone', (tester) async {
    await pumpAt(tester, const Size(360, 780), const OnboardingPage());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Continue to login'), findsOneWidget);
  });

  testWidgets('the login form fits a 360 px phone', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 780),
      const AuthFormPage(mode: AuthMode.signIn),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('the sign-up form fits a 360 px phone', (tester) async {
    await pumpAt(
      tester,
      const Size(360, 780),
      const AuthFormPage(mode: AuthMode.signUp),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('SIGN UP'), findsOneWidget);
  });
}
