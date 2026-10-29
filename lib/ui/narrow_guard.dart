import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'canvas.dart';

/// Narrow screens are out of v0.0.1 (D29).
///
/// A canvas editor needs width. Below the breakpoint the app says so plainly
/// instead of rendering a squeezed version of a layout that was never designed
/// for it — a broken-looking product is worse than an honest limit.
class NarrowGuard extends StatelessWidget {
  const NarrowGuard({super.key, required this.child, this.breakpoint = 768});

  final Widget child;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < breakpoint) return const NarrowNotice();
    return child;
  }
}

class NarrowNotice extends StatelessWidget {
  const NarrowNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Canvas(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOO NARROW', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 18),
          Text(
            'This needs a wider window.',
            style: AppType.serif(size: 26, height: 1.3),
          ),
          const SizedBox(height: 14),
          Text(
            'Owniverse is built for a desktop screen. Nothing is lost — widen '
            'the window and it comes back.',
            style: AppType.sans(size: 14, color: Palette.muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}
