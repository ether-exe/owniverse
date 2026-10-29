import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';

/// `/` for a logged-out visitor. Nothing else is reachable (SPEC §13 step 1).
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Canvas(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('OWNIVERSE', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 28),
          Text(
            'Write a page.\nDecide what a stranger reads.',
            style: AppType.serif(size: 34, height: 1.2),
          ),
          const SizedBox(height: 20),
          const AccentRule(),
          const SizedBox(height: 20),
          Text(
            'A Space is yours to write. You place a door where the writing '
            'should stop being public — everything after it needs an identity.',
            style: AppType.sans(size: 15, color: Palette.muted, height: 1.6),
          ),
          const SizedBox(height: 36),
          _Action(
            label: 'Continue to login',
            onTap: () => context.go('/login'),
          ),
          const SizedBox(height: 4),
          _Action(
            label: 'Continue to sign up',
            muted: true,
            onTap: () => context.go('/signup'),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(
              label,
              style: AppType.sans(
                size: 15,
                color: muted ? Palette.muted : Palette.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '→',
              style: AppType.mono(
                size: 13,
                color: muted ? Palette.muted : Palette.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
