import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import '../auth/auth_providers.dart';
import '../auth/profile.dart';
import '../media/media.dart';
import '../spaces/space.dart';
import '../spaces/space_row_menu.dart';
import '../spaces/space_title_dialog.dart';
import '../spaces/spaces_providers.dart';

/// `@username` — one URL, two lenses (D14).
///
/// The owner sees every live Space, drafts included, with its state; a visitor
/// sees only what is public and published, with no chips, no controls and no
/// count. Same page, rendered by who is asking.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final isOwner = me?.username?.toLowerCase() == username.toLowerCase();

    if (isOwner) return _OwnerLens(me: me!);

    final public = ref.watch(publicProfileProvider(username));
    return public.when(
      loading: () => const Canvas(child: LinearProgressIndicator(minHeight: 1)),
      error: (_, _) => const _Missing(),
      data: (data) {
        if (data == null) return const _Missing();

        return _Shell(
          name: (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : '@${data['username']}',
          handle: '@${data['username']}',
          link: _firstLink(data['social']),
          avatarPath: data['avatar_path'] as String?,
          body: _VisitorBody(
            handle: '@${data['username']}',
            spaces: [
              for (final row in (data['spaces'] as List?) ?? const [])
                if (row is Map<String, dynamic>) Space.fromPublicMap(row),
            ],
          ),
        );
      },
    );
  }

  static MapEntry<String, String>? _firstLink(Object? social) {
    if (social is! Map) return null;
    for (final entry in social.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        return MapEntry(entry.key.toString(), value);
      }
    }
    return null;
  }
}

/// The owner's own page: the list, the tile that adds to it, and the count.
class _OwnerLens extends ConsumerWidget {
  const _OwnerLens({required this.me});

  final Profile me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(ownerSpacesProvider);

    // `hasError` before `isLoading`, deliberately. Riverpod retries a failed
    // future ten times with backoff, and for every one of those retries the
    // value is an `AsyncLoading` that *carries* the error — so a `when(...)`
    // that checks loading first would hide the failure behind a spinner for
    // half a minute and then finally say something. Show the failure at once;
    // the retry keeps running underneath and the list appears if it lands.
    final Widget body;
    if (spaces.hasError) {
      body = _LoadFailed(
        onRetry: () => ref.invalidate(ownerSpacesProvider),
        sentence: 'Your Spaces could not be loaded.',
      );
    } else if (spaces.isLoading) {
      body = const LinearProgressIndicator(minHeight: 1);
    } else {
      body = _OwnerBody(spaces: spaces.requireValue, handle: me.handle);
    }

    return _Shell(
      name: me.displayName,
      handle: me.handle,
      link: me.firstSocial,
      avatarPath: me.avatarPath,
      trailing: _AccountMenu(initial: _initial(me.displayName)),
      body: body,
    );
  }
}

/// A failure that says what failed and offers the only useful action: ask again.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.sentence, required this.onRetry});

  final String sentence;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sentence, style: AppType.sans(size: 15, color: Palette.muted)),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Text(
            'Try again',
            style: AppType.mono(size: 11, color: Palette.ink),
          ),
        ),
      ],
    );
  }
}

class _OwnerBody extends ConsumerWidget {
  const _OwnerBody({required this.spaces, required this.handle});

  final List<Space> spaces;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Trash link says how much is in there, so a Space that just vanished
    // from the list has somewhere visible to have gone. A failed or pending
    // read is not worth a spinner for a number this small.
    final trashed = ref.watch(trashedSpacesProvider).value?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spaces.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Nothing here yet. Your first Space will sit in this column.',
              style: AppType.sans(size: 15, color: Palette.muted, height: 1.6),
            ),
          )
        else ...[
          for (var i = 0; i < spaces.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Palette.hairline),
            _SpaceRow(space: spaces[i], handle: handle, owner: true),
          ],
          const Divider(height: 1, color: Palette.hairline),
        ],
        _NewSpaceTile(handle: handle),
        const SizedBox(height: 18),
        Row(
          children: [
            // D14: the count belongs to the owner. A visitor sees no numbers.
            Text(
              'SPACES ${spaces.length}',
              style: AppType.mono(size: 11, spacing: 1.6),
            ),
            const Spacer(),
            // D15: the Trash lives at the bottom of the owner lens.
            TextButton(
              onPressed: () => context.push('/trash'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'TRASH $trashed →',
                style: AppType.mono(size: 11, color: Palette.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The visitor's page: published rows and nothing else. No chip, no count, no
/// controls, no trace of a draft (DoD 16).
class _VisitorBody extends StatelessWidget {
  const _VisitorBody({required this.spaces, required this.handle});

  final List<Space> spaces;
  final String handle;

  @override
  Widget build(BuildContext context) {
    if (spaces.isEmpty) {
      return Text(
        'Nothing published here yet.',
        style: AppType.sans(size: 15, color: Palette.muted, height: 1.6),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < spaces.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Palette.hairline),
          _SpaceRow(space: spaces[i], handle: handle, owner: false),
        ],
      ],
    );
  }
}

/// One Space in the column. Depth is a hairline, so a "card" is a row.
class _SpaceRow extends StatelessWidget {
  const _SpaceRow({
    required this.space,
    required this.handle,
    required this.owner,
  });

  final Space space;
  final String handle;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    // The owner opens the Space in the editor; a visitor opens the frozen page.
    // Same row, two destinations — which is what D14's two lenses mean in code.
    final onTap = owner
        ? () => context.push('/space/${space.id}')
        : () => context.push('/$handle/${space.addressSlug}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            hoverColor: Palette.hairline.withValues(alpha: 0.4),
            focusColor: Palette.hairline,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(space.title, style: AppType.serif(size: 22)),
                  const SizedBox(height: 2),
                  Text(
                    '$handle/${space.addressSlug}',
                    style: AppType.mono(size: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (owner) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              space.state.label,
              style: AppType.mono(
                size: 10,
                spacing: 1.4,
                color: space.state == SpaceState.published
                    ? Palette.ink
                    : Palette.muted,
              ),
            ),
          ),
          // The menu sits outside the row's tap target on purpose: aiming at
          // the dots must never open the Space.
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SpaceRowMenu(space: space, handle: handle),
          ),
        ],
      ],
    );
  }
}

/// D15: New Space lives on the owner lens, as a tile, not in a sidebar.
class _NewSpaceTile extends StatelessWidget {
  const _NewSpaceTile({required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final space = await SpaceTitleDialog.show(context, handle: handle);
        // DoD 5 asks for the editor to open here. It does not exist until M3,
        // so the new Space opens at its own URL and says so, rather than
        // bouncing back to the profile as if nothing happened.
        if (space != null && context.mounted) {
          context.push('/space/${space.id}');
        }
      },
      hoverColor: Palette.hairline.withValues(alpha: 0.4),
      focusColor: Palette.hairline,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Text('+', style: AppType.mono(size: 15, color: Palette.ink)),
            const SizedBox(width: 12),
            Text(
              'NEW SPACE',
              style: AppType.mono(size: 10, spacing: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page itself: name, handle, one link, a hairline, then whatever the lens
/// put underneath.
class _Shell extends ConsumerWidget {
  const _Shell({
    required this.name,
    required this.handle,
    required this.link,
    required this.body,
    this.avatarPath,
    this.trailing,
  });

  final String name;
  final String handle;
  final MapEntry<String, String>? link;
  final Widget body;

  /// DoD 4. Null for anyone who has not uploaded one, which is most people.
  final String? avatarPath;

  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolved lazily: no picture means no reason to reach for a client at all.
    final avatar = avatarPath == null
        ? null
        : avatarUrl(ref.watch(supabaseProvider), avatarPath);

    return Canvas(
      maxWidth: 560,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (avatar != null)
                Padding(
                  padding: const EdgeInsets.only(right: 14, top: 4),
                  child: ClipOval(
                    child: Image.network(
                      avatar,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  name.isEmpty ? handle : name,
                  style: AppType.serif(size: 38),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(handle, style: AppType.mono(size: 13)),
              if (link != null)
                Text(
                  '${link!.key} ↗',
                  style: AppType.mono(size: 12, color: Palette.ink),
                ),
            ],
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Palette.hairline),
          const SizedBox(height: 28),
          body,
        ],
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return Canvas(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('404', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 16),
          Text('No profile at that address.', style: AppType.serif(size: 26)),
        ],
      ),
    );
  }
}

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '·';
  return trimmed.substring(0, 1).toUpperCase();
}

/// D15: sign-out lives in the account menu on the profile card — not in a
/// settings screen, not in a sidebar. There is nowhere else for it to be.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 44),
      color: Palette.canvas,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Palette.hairline),
      ),
      onSelected: (value) {
        if (value == 'signout') signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'signout',
          child: Text('Sign out', style: AppType.sans(size: 14)),
        ),
      ],
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Palette.hairline),
        ),
        child: Text(initial, style: AppType.mono(size: 13, color: Palette.ink)),
      ),
    );
  }
}
