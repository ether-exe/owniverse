import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// The single source of truth for "is anyone signed in".
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final sessionProvider = Provider<Session?>((ref) {
  final state = ref.watch(authStateProvider);
  if (state.hasValue) return state.requireValue.session;
  return ref.watch(supabaseProvider).auth.currentSession;
});

/// The caller's profile row. RLS lets an owner read only their own, so this
/// is also the onboarding gate.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  final row = await ref
      .watch(supabaseProvider)
      .from('users')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();

  return row == null ? null : Profile.fromJson(row);
});

/// Public read of someone else's profile, via the gated function (D24).
final publicProfileProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, handle) async {
      final result = await ref
          .watch(supabaseProvider)
          .rpc('profile_public', params: {'p_handle': handle});

      if (result is! Map) return null;
      final map = Map<String, dynamic>.from(result);
      return map['found'] == true ? map : null;
    });

/// Real-time availability, answered by the database rather than the client.
Future<bool> usernameAvailable(String candidate) async {
  final normalized = candidate.trim().toLowerCase();
  if (normalized.length < 3) return false;

  final result = await Supabase.instance.client.rpc(
    'username_available',
    params: {'p_username': normalized},
  );
  return result == true;
}

Future<void> signOut() => Supabase.instance.client.auth.signOut();
