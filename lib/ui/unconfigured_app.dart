import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'canvas.dart';

/// Shown when the build has no `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
///
/// Fails loudly and usefully instead of throwing somewhere deeper: a blank
/// white screen at this point costs an hour of guessing.
class UnconfiguredApp extends StatelessWidget {
  const UnconfiguredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Owniverse',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Canvas(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NOT CONFIGURED', style: AppType.mono(size: 11, spacing: 2.4)),
            const SizedBox(height: 20),
            Text(
              'The build has no backend address.',
              style: AppType.serif(size: 28, height: 1.25),
            ),
            const SizedBox(height: 20),
            Text(
              'Copy dart_define.example.json to dart_define.json, fill it in, '
              'then run:',
              style: AppType.sans(size: 14, color: Palette.muted),
            ),
            const SizedBox(height: 12),
            SelectableText(
              'flutter run -d chrome --dart-define-from-file=dart_define.json',
              style: AppType.mono(size: 12, color: Palette.ink),
            ),
          ],
        ),
      ),
    );
  }
}
