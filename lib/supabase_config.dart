/// Supabase project config. The URL is public; the anon key is the PUBLISHABLE
/// client key — safe to ship in a client binary because row-level security
/// enforces all access. Until the key is pasted (one line, or a
/// --dart-define=SUPABASE_ANON_KEY=...), account features stay hidden and the
/// app remains fully view-only. Mock-mode-first, same as everything else.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://ucgakrzintxpyqgdwues.supabase.co');

  /// Paste the anon (publishable) key from
  /// supabase.com/dashboard → project keyview → Settings → API Keys.
  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get enabled => anonKey.isNotEmpty;
}
