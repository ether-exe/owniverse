import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Every page sits on the same canvas: one column, generous vertical rhythm,
/// nothing centred in a card. Depth is a hairline.
class Canvas extends StatelessWidget {
  const Canvas({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: alignment,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled field grows out of a label and a hairline, never a box.
class LabelledField extends StatelessWidget {
  const LabelledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppType.mono(size: 10, spacing: 1.2)),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: AppType.mono(size: 11)),
        ],
      ],
    );
  }
}

/// One accent per screen, so it is used deliberately.
class AccentRule extends StatelessWidget {
  const AccentRule({super.key, this.width = 28});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: 1, color: Palette.accent);
  }
}

/// Errors are stated, not shouted: mono, muted, no red banner.
class QuietError extends StatelessWidget {
  const QuietError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        message,
        style: AppType.mono(size: 12, color: Palette.accent),
      ),
    );
  }
}
