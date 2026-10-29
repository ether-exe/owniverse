import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import '../auth/auth_providers.dart';

/// `@username` — one URL, two lenses (D14). In M1 the owner lens is honest
/// about being empty; Spaces arrive in M2.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final isOwner = me?.username?.toLowerCase() == username.toLowerCase();

    if (isOwner) {
      return _ProfileView(
        name: me!.displayName,
        handle: me.handle,
        link: me.firstSocial,
        spaces: const [],
        owner: true,
      );
    }

    final public = ref.watch(publicProfileProvider(username));
    return public.when(
      loading: () => const Canvas(child: LinearProgressIndicator(minHeight: 1)),
      error: (_, _) => const _Missing(),
      data: (data) {
        if (data == null) return const _Missing();

        return _ProfileView(
          name: (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : '@${data['username']}',
          handle: '@${data['username']}',
          link: _firstLink(data['social']),
          spaces:
              (data['spaces'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
          owner: false,
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

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.name,
    required this.handle,
    required this.link,
    required this.spaces,
    required this.owner,
  });

  final String name;
  final String handle;
  final MapEntry<String, String>? link;
  final List<Map<String, dynamic>> spaces;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    return Canvas(
      maxWidth: 560,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? handle : name,
                  style: AppType.serif(size: 38),
                ),
              ),
              // D15: the account menu lives on the profile card, nowhere else.
              if (owner)
                _AccountMenu(initial: _initial(name.isEmpty ? handle : name)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(handle, style: AppType.mono(size: 13)),
              if (link != null) ...[
                const SizedBox(width: 16),
                Text(
                  '${link!.key} ↗',
                  style: AppType.mono(size: 12, color: Palette.ink),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Palette.hairline),
          const SizedBox(height: 28),
          if (spaces.isEmpty)
            _EmptySpaces(owner: owner)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final space in spaces)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (space['title'] as String?) ?? '',
                          style: AppType.serif(size: 22),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$handle/${space['slug']}',
                          style: AppType.mono(size: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptySpaces extends StatelessWidget {
  const _EmptySpaces({required this.owner});

  final bool owner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          owner
              ? 'Nothing here yet. Your first Space will sit in this column.'
              : 'Nothing published here yet.',
          style: AppType.sans(size: 15, color: Palette.muted, height: 1.6),
        ),
        if (owner) ...[
          const SizedBox(height: 20),
          Text('SPACES 0', style: AppType.mono(size: 11, spacing: 1.6)),
        ],
      ],
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
