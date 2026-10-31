import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import '../../ui/not_found_page.dart';
import '../auth/auth_providers.dart';
import '../blocks/block.dart';
import '../media/media.dart';
import '../media/media_image.dart';
import '../spaces/space_actions.dart';
import '../spaces/spaces_providers.dart';
import '../spaces/space_feedback.dart';
import 'public_space.dart';

/// `@username/slug` — the frozen page (D5, D8, D22).
///
/// What a reader gets is decided by the database, not by this widget: `space_head`
/// returns the public slice, and the gated blocks are **absent from the payload**.
/// The page cannot leak what it was never sent.
class PublicSpacePage extends ConsumerStatefulWidget {
  const PublicSpacePage({super.key, required this.handle, required this.slug});

  final String handle;
  final String slug;

  @override
  ConsumerState<PublicSpacePage> createState() => _PublicSpacePageState();
}

class _PublicSpacePageState extends ConsumerState<PublicSpacePage> {
  /// Set once the reader has entered. Before that, everything on screen came from
  /// `space_head` and stopped at the door.
  PublicSpace? _entered;
  bool _entering = false;

  @override
  Widget build(BuildContext context) {
    final address = (widget.handle, widget.slug);
    final public = ref.watch(publicSpaceProvider(address));
    final session = ref.watch(sessionProvider);

    if (public.hasError) {
      return Canvas(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This page could not be loaded.',
              style: AppType.sans(size: 15, color: Palette.muted),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => ref.invalidate(publicSpaceProvider(address)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Try again',
                style: AppType.mono(size: 11, color: Palette.ink),
              ),
            ),
          ],
        ),
      );
    }

    if (public.isLoading) {
      return const Canvas(child: LinearProgressIndicator(minHeight: 1));
    }

    final space = public.value;
    if (space == null) {
      return NotFoundPage(
        lookedFor: '/@${widget.handle}/${widget.slug}',
      );
    }

    // The reader's own version wins once they have entered.
    final shown = _entered ?? space;
    final signedIn = session != null;

    return _Page(
      space: shown,
      signedIn: signedIn,
      entering: _entering,
      onEnter: _enter,
      onLike: _like,
      onSignIn: () => context.push('/login'),
    );
  }

  Future<void> _enter() async {
    setState(() => _entering = true);
    try {
      final result = await ref
          .read(spaceActionsProvider)
          .enter(widget.handle, widget.slug);

      if (!mounted) return;
      if (result == null) {
        showSpaceNotice(
          context,
          'That page is not reachable any more.',
          bad: true,
        );
        return;
      }
      setState(() => _entered = PublicSpace.fromMap(result));
    } on SpaceFailure catch (failure) {
      if (mounted) showSpaceFailure(context, failure);
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  Future<void> _like() async {
    try {
      final result = await ref
          .read(spaceActionsProvider)
          .toggleLike(widget.handle, widget.slug);

      if (!mounted) return;
      final current =
          _entered ??
          ref.read(publicSpaceProvider((widget.handle, widget.slug))).value;
      if (current == null) return;
      setState(
        () => _entered = current.withLiked(
          liked: result.liked,
          likes: result.likes,
        ),
      );
    } on SpaceFailure catch (failure) {
      if (mounted) showSpaceFailure(context, failure);
    }
  }
}

class _Page extends ConsumerWidget {
  const _Page({
    required this.space,
    required this.signedIn,
    required this.entering,
    required this.onEnter,
    required this.onLike,
    required this.onSignIn,
  });

  final PublicSpace space;
  final bool signedIn;
  final bool entering;
  final VoidCallback onEnter;
  final VoidCallback onLike;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handle = '@${space.authorHandle ?? ''}';

    // `space_media` (migration 13) is how a block's `media_id` becomes a path
    // for anyone who is not the owner. The bucket still decides the bytes (D25).
    final mediaPaths =
        ref.watch(publicMediaPathsProvider(space.id)).value ??
        const <String, String>{};

    return Canvas(
      maxWidth: 680,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(space.title, style: AppType.serif(size: 40, height: 1.15)),
          const SizedBox(height: 10),
          Text('$handle/${space.slug}', style: AppType.mono(size: 11)),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Palette.hairline),
          const SizedBox(height: 28),
          for (final block in space.blocks)
            _PublishedBlock(
              key: ValueKey(block.id),
              block: block,
              space: space,
              signedIn: signedIn,
              onLike: onLike,
              mediaPath: mediaPaths[block.mediaId],
            ),
          if (space.hasDoor && space.blocks.length <= 1)
            const SizedBox.shrink(),
          if (_needsDoorHere(space))
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: _Door(
                signedIn: signedIn,
                entering: entering,
                onEnter: onEnter,
                onSignIn: onSignIn,
              ),
            ),
          const SizedBox(height: 40),
          Text(
            space.authorName?.isNotEmpty == true ? space.authorName! : handle,
            style: AppType.sans(size: 13, color: Palette.muted),
          ),
        ],
      ),
    );
  }

  /// A door is shown when the page has one and the reader has not passed it.
  bool _needsDoorHere(PublicSpace space) =>
      space.hasDoor && !_hasGatedContent(space);

  /// After entering, the document includes the door block itself, so its presence
  /// means the reader is already past it.
  bool _hasGatedContent(PublicSpace space) =>
      space.blocks.any((block) => block.type == 'door');
}

/// One block as a reader sees it. Read-only by construction: there is no field
/// here, so there is nothing to edit even by accident.
class _PublishedBlock extends StatelessWidget {
  const _PublishedBlock({
    super.key,
    required this.block,
    required this.space,
    required this.signedIn,
    required this.onLike,
    this.mediaPath,
  });

  final Block block;
  final PublicSpace space;
  final bool signedIn;
  final VoidCallback onLike;
  final String? mediaPath;

  @override
  Widget build(BuildContext context) {
    if (!block.isRenderable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: switch (block.kind) {
        BlockType.heading => Text(
          block.text,
          style: AppType.serif(size: block.level == 1 ? 30 : 23, height: 1.25),
        ),
        BlockType.text => Text(
          block.text,
          style: AppType.sans(size: 16, height: 1.75),
        ),
        BlockType.longtext => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(block.text, style: AppType.sans(size: 14, height: 1.85)),
        ),
        BlockType.door => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1, color: Palette.hairline),
            const SizedBox(height: 10),
            Text(
              'ENTERED',
              style: AppType.mono(size: 9, spacing: 2.2, color: Palette.accent),
            ),
            if (block.data['note'] case final String note
                when note.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note,
                style: AppType.sans(
                  size: 13,
                  color: Palette.muted,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
        BlockType.readers => Text(
          '${space.readers} ${space.readers == 1 ? 'PERSON HAS' : 'PEOPLE HAVE'} ENTERED',
          style: AppType.mono(size: 10, spacing: 1.8),
        ),
        BlockType.likes => _Likes(
          space: space,
          signedIn: signedIn,
          onLike: onLike,
        ),
        BlockType.profile => _ProfileCard(space: space),
        // Cover and image render through the caller's own session, which is what
        // makes D25 true without a second rule in the client: an anonymous
        // reader on a gated Space is refused by the bucket, not by this widget.
        BlockType.cover || BlockType.image => mediaPath == null
            ? const MediaWithheld()
            : MediaImage(
                path: mediaPath!,
                maxHeight: block.kind == BlockType.cover ? 380 : 520,
                fit: block.kind == BlockType.cover
                    ? BoxFit.cover
                    : BoxFit.contain,
              ),
        null => const SizedBox.shrink(),
      },
    );
  }
}

class _Likes extends StatelessWidget {
  const _Likes({
    required this.space,
    required this.signedIn,
    required this.onLike,
  });

  final PublicSpace space;
  final bool signedIn;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${space.likes} ${space.likes == 1 ? 'LIKE' : 'LIKES'}',
          style: AppType.mono(size: 10, spacing: 1.8),
        ),
        const SizedBox(width: 16),
        if (signedIn)
          TextButton(
            onPressed: onLike,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(
              space.likedByMe ? 'Liked' : 'Like',
              style: AppType.sans(
                size: 13,
                color: space.likedByMe ? Palette.muted : Palette.accent,
              ),
            ),
          )
        else
          Text(
            'Sign in to add one.',
            style: AppType.sans(size: 13, color: Palette.muted),
          ),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.space});

  final PublicSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = space.authorAvatar == null
        ? null
        : avatarUrl(ref.watch(supabaseProvider), space.authorAvatar);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Palette.hairline)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipOval(
                child: Image.network(
                  avatar,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.authorName?.isNotEmpty == true
                      ? space.authorName!
                      : '@${space.authorHandle ?? ''}',
                  style: AppType.serif(size: 20),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${space.authorHandle ?? ''}',
                  style: AppType.mono(size: 10),
                ),
                if (space.authorEmail != null) ...[
                  const SizedBox(height: 2),
                  Text(space.authorEmail!, style: AppType.mono(size: 10)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The threshold. Before it, the reader has only what `space_head` gave them.
class _Door extends StatelessWidget {
  const _Door({
    required this.signedIn,
    required this.entering,
    required this.onEnter,
    required this.onSignIn,
  });

  final bool signedIn;
  final bool entering;
  final VoidCallback onEnter;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A DOOR',
            style: AppType.mono(size: 9, spacing: 2.2, color: Palette.accent),
          ),
          const SizedBox(height: 8),
          Text(
            'There is more past this point. It is not on this page until you '
            'ask for it.',
            style: AppType.sans(size: 15, color: Palette.ink, height: 1.6),
          ),
          const SizedBox(height: 12),
          if (signedIn)
            TextButton(
              onPressed: entering ? null : onEnter,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                entering ? 'Entering…' : 'Enter →',
                style: AppType.sans(size: 14, color: Palette.accent),
              ),
            )
          else
            Row(
              children: [
                TextButton(
                  onPressed: onSignIn,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    'Sign in to enter →',
                    style: AppType.sans(size: 14, color: Palette.accent),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
