import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';

/// 404 is a real page, not a redirect: it says what was looked for (SPEC §10).
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, this.lookedFor});

  final String? lookedFor;

  @override
  Widget build(BuildContext context) {
    return Canvas(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('404', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 16),
          Text(
            lookedFor == null
                ? 'There is nothing at this address.'
                : 'There is nothing at $lookedFor.',
            style: AppType.serif(size: 26, height: 1.3),
          ),
          const SizedBox(height: 16),
          Text(
            'A page appears here once someone publishes it.',
            style: AppType.sans(size: 14, color: Palette.muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}
