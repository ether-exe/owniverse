/// Build-time configuration.
///
/// The defaults below are the project's **publishable** credentials. They are
/// not secrets: `sb_publishable_…` is designed to ship inside a browser bundle
/// — any deployed instance of this app contains it — and the project URL is
/// public. The security boundary is row level security, not a hidden key
/// (D24), which is why 42 assertions in `scripts/db-test.mjs` exist.
///
/// They are committed so that `flutter run -d chrome` works with no flags.
/// Both are overridable at build time for forks and other deployments:
///
/// ```bash
/// flutter run -d chrome --dart-define-from-file=dart_define.json
/// ```
///
/// The **secret** key must never appear here, in a define, or in the repo.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mozotxgaqhtxyhjjnnqx.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_fBKghBsZtHF2ydBlYwBAQA_v2wQbzvb',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
