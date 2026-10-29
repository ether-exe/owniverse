import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import 'auth_providers.dart';

enum AuthMode { signIn, signUp }

/// Login and sign up are the same page with a different verb (SPEC §10).
class AuthFormPage extends ConsumerStatefulWidget {
  const AuthFormPage({super.key, required this.mode});

  final AuthMode mode;

  @override
  ConsumerState<AuthFormPage> createState() => _AuthFormPageState();
}

class _AuthFormPageState extends ConsumerState<AuthFormPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isSignUp => widget.mode == AuthMode.signUp;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;

    if (!email.contains('@') || password.length < 6) {
      setState(
        () => _error = 'An email and a password of at least 6 characters.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(supabaseProvider).auth;
      if (_isSignUp) {
        final result = await auth.signUp(email: email, password: password);
        if (result.session == null && mounted) {
          setState(() => _error = 'Check your email to confirm the account.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Canvas(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isSignUp ? 'SIGN UP' : 'LOGIN',
              style: AppType.mono(size: 11, spacing: 2.4),
            ),
            const SizedBox(height: 20),
            Text(
              _isSignUp ? 'Begin.' : 'Welcome back.',
              style: AppType.serif(size: 30),
            ),
            const SizedBox(height: 32),
            LabelledField(
              label: 'Email',
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                style: AppType.sans(size: 15),
                cursorColor: Palette.accent,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
            ),
            const SizedBox(height: 24),
            LabelledField(
              label: 'Password',
              child: TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                style: AppType.sans(size: 15),
                cursorColor: Palette.accent,
                decoration: InputDecoration(
                  hintText: _isSignUp ? 'at least 6 characters' : '••••••••',
                ),
              ),
            ),
            if (_error != null) QuietError(_error!),
            const SizedBox(height: 28),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? 'Working…'
                        : (_isSignUp ? 'Create account →' : 'Log in →'),
                    style: AppType.sans(size: 15, color: Palette.ink),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.go(_isSignUp ? '/login' : '/signup'),
                  child: Text(
                    _isSignUp ? 'I have an account' : 'I need an account',
                    style: AppType.mono(size: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
