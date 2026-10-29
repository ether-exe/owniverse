import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_form_page.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/complete_profile_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/profile/profile_page.dart';
import 'ui/not_found_page.dart';

/// The guard from SPEC §10, in one place:
///
/// | `/`                   | anon → onboarding · signed in → `/@username`     |
/// | `/login`, `/signup`   | anon only                                        |
/// | `/complete-profile`   | signed in with no username, nothing else         |
/// | `/@:username`         | anyone                                           |
///
/// A profile row with `username is null` **is** an incomplete account, so the
/// database and this guard agree without any extra state.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.listen(profileProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      if (session == null) {
        // Nobody signed in: `/` and the auth pages are all there is.
        return state.matchedLocation == '/complete-profile' ? '/' : null;
      }

      // Hold still until the profile is known, so nobody is bounced through
      // Complete Profile on their way back in.
      final profileState = ref.read(profileProvider);
      if (profileState.isLoading) return null;

      final username = profileState.value?.username;
      final onboarded = username != null && username.isNotEmpty;
      final location = state.matchedLocation;

      if (!onboarded) {
        return location == '/complete-profile' ? null : '/complete-profile';
      }

      const owned = {'/', '/login', '/signup', '/complete-profile'};
      return owned.contains(location) ? '/@$username' : null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const OnboardingPage()),
      GoRoute(
        path: '/login',
        builder: (_, _) => const AuthFormPage(mode: AuthMode.signIn),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, _) => const AuthFormPage(mode: AuthMode.signUp),
      ),
      GoRoute(
        path: '/complete-profile',
        builder: (_, _) => const CompleteProfilePage(),
      ),
      // A handle is `@` plus a username. Declared last so the literal routes
      // above win, and validated here rather than trusting the pattern.
      GoRoute(
        path: '/:handle',
        builder: (_, state) {
          final handle = state.pathParameters['handle'] ?? '';
          if (!handle.startsWith('@') || handle.length < 2) {
            return NotFoundPage(lookedFor: state.uri.path);
          }
          return ProfilePage(username: handle.substring(1));
        },
      ),
    ],
    errorBuilder: (context, state) => NotFoundPage(lookedFor: state.uri.path),
  );
});
