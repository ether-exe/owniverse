import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/ui/unconfigured_app.dart';

void main() {
  testWidgets(
    'an unconfigured build says so instead of showing a blank screen',
    (tester) async {
      await tester.pumpWidget(const UnconfiguredApp());
      await tester.pump();

      expect(find.text('NOT CONFIGURED'), findsOneWidget);
      expect(
        find.textContaining('--dart-define-from-file=dart_define.json'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the unconfigured screen keeps the canvas, not Material grey', (
    tester,
  ) async {
    await tester.pumpWidget(const UnconfiguredApp());
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
      const Color(0xFF0C0C0D),
    );
  });
}
