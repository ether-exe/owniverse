import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/ui/narrow_guard.dart';

void main() {
  testWidgets('below the breakpoint the limit is stated, not squeezed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: NarrowGuard(child: Text('wide layout'))),
    );

    expect(find.text('wide layout'), findsNothing);
    expect(find.textContaining('needs a wider window'), findsOneWidget);
  });

  testWidgets('at the breakpoint and above, the real layout renders', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: NarrowGuard(child: Text('wide layout'))),
    );

    expect(find.text('wide layout'), findsOneWidget);
    expect(find.textContaining('needs a wider window'), findsNothing);
  });
}
