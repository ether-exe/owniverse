import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import 'auth_providers.dart';

/// Mandatory and unavoidable (SPEC §13 step 3). Until a username exists the
/// router will not let anyone anywhere else.
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() =>
      _CompleteProfilePageState();
}

enum _Availability { idle, checking, free, taken }

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  static const _networks = ['x', 'github', 'instagram', 'youtube', 'website'];

  final _name = TextEditingController();
  final _username = TextEditingController();
  final _link = TextEditingController();

  String _network = 'website';
  bool _emailPublic = false;
  bool _busy = false;
  String? _error;

  _Availability _availability = _Availability.idle;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    _link.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    final candidate = value.trim().toLowerCase();

    if (candidate.length < 3) {
      setState(() => _availability = _Availability.idle);
      return;
    }

    setState(() => _availability = _Availability.checking);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final free = await usernameAvailable(candidate);
      if (!mounted) return;
      if (_username.text.trim().toLowerCase() != candidate) return;
      setState(
        () => _availability = free ? _Availability.free : _Availability.taken,
      );
    });
  }

  Future<void> _submit() async {
    if (_busy) return;

    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();

    if (name.isEmpty) {
      setState(() => _error = 'A name, so the page knows whose it is.');
      return;
    }
    if (_availability != _Availability.free) {
      setState(() => _error = 'Pick a username that is free.');
      return;
    }

    final link = _link.text.trim();
    final social = <String, dynamic>{};
    if (link.isNotEmpty) {
      social[_network] = link.startsWith('http') ? link : 'https://$link';
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'update_profile',
            params: {
              'p_name': name,
              'p_username': username,
              'p_avatar_path': null,
              'p_email_public': _emailPublic,
              'p_social': social,
            },
          );

      ref.invalidate(profileProvider);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message == 'username_taken'
              ? 'That username was just taken.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _availabilityNote => switch (_availability) {
    _Availability.checking => 'checking…',
    _Availability.free => 'free',
    _Availability.taken => 'taken',
    _Availability.idle => null,
  };

  Color get _availabilityColor =>
      _availability == _Availability.taken ? Palette.accent : Palette.muted;

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(sessionProvider)?.user.email ?? '';

    return Canvas(
      maxWidth: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('COMPLETE PROFILE', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 20),
          Text('Who is writing?', style: AppType.serif(size: 30)),
          const SizedBox(height: 12),
          Text(
            'Your username is the address of everything you publish. '
            'It is permanent enough to choose carefully.',
            style: AppType.sans(size: 14, color: Palette.muted, height: 1.6),
          ),
          const SizedBox(height: 32),

          LabelledField(
            label: 'Name',
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: AppType.sans(size: 15),
              cursorColor: Palette.accent,
              decoration: const InputDecoration(
                hintText: 'How you sign your work',
              ),
            ),
          ),
          const SizedBox(height: 24),

          LabelledField(
            label: 'Username',
            hint: _availabilityNote,
            child: TextField(
              controller: _username,
              onChanged: _onUsernameChanged,
              style: AppType.mono(size: 15, color: Palette.ink),
              cursorColor: Palette.accent,
              decoration: const InputDecoration(
                hintText: 'lowercase, hyphens, 3–30',
                prefixText: '@',
              ),
            ),
          ),
          if (_availabilityNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _availabilityNote!,
                style: AppType.mono(size: 11, color: _availabilityColor),
              ),
            ),
          const SizedBox(height: 24),

          LabelledField(
            label: 'One link',
            hint: 'optional — the server accepts x, github, instagram, youtube, website',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _link,
                    keyboardType: TextInputType.url,
                    style: AppType.mono(size: 14, color: Palette.ink),
                    cursorColor: Palette.accent,
                    decoration: const InputDecoration(hintText: 'https://'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            children: [
              for (final network in _networks)
                GestureDetector(
                  onTap: () => setState(() => _network = network),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      network,
                      style: AppType.mono(
                        size: 12,
                        color: _network == network
                            ? Palette.ink
                            : Palette.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EMAIL', style: AppType.mono(size: 10, spacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(
                      email,
                      style: AppType.mono(size: 13, color: Palette.ink),
                    ),
                  ],
                ),
              ),
              Text(
                _emailPublic ? 'public' : 'private',
                style: AppType.mono(size: 11),
              ),
              Switch(
                value: _emailPublic,
                activeThumbColor: Palette.accent,
                activeTrackColor: Palette.hairline,
                inactiveThumbColor: Palette.muted,
                inactiveTrackColor: Palette.hairline,
                onChanged: (value) => setState(() => _emailPublic = value),
              ),
            ],
          ),
          if (_error != null) QuietError(_error!),
          const SizedBox(height: 28),

          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy ? 'Saving…' : 'Continue →',
              style: AppType.sans(size: 15, color: Palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}
