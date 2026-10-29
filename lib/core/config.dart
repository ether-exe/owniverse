/// Build-time configuration.
///
/// Injected with `--dart-define` so no infrastructure detail lives in source:
///
/// ```bash
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<publishable key>
/// ```
///
/// The publishable key is public by design — it ships inside the web bundle
/// either way. The **secret** key must never be passed here.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
