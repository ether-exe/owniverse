import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'router.dart';
import 'ui/narrow_guard.dart';

class OwniverseApp extends ConsumerWidget {
  const OwniverseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Owniverse',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      // D29, in one place: every route obeys the same width limit.
      builder: (context, child) =>
          NarrowGuard(child: child ?? const SizedBox.shrink()),
    );
  }
}
