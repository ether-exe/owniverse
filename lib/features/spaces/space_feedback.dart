import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'space_actions.dart';

/// One way to say something happened without a dialog or a route change.
///
/// A `SnackBar` with its Material-ness removed: no elevation, no shadow, no
/// rounded pill — a canvas with a hairline, which is what everything else here
/// is.
void showSpaceNotice(BuildContext context, String sentence, {bool bad = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          sentence,
          style: AppType.sans(size: 13, color: Palette.ink, height: 1.5),
        ),
        backgroundColor: Palette.canvas,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: bad ? Palette.accent : Palette.hairline),
          borderRadius: BorderRadius.zero,
        ),
      ),
    );
}

/// A failed write, said in the words `spaceFailureFrom` chose for it.
void showSpaceFailure(BuildContext context, SpaceFailure failure) =>
    showSpaceNotice(context, failure.message, bad: true);
