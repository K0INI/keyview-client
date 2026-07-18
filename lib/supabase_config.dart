/// Supabase project config. The URL is public; the anon key is the PUBLISHABLE
/// client key — safe to ship in a client binary because row-level security
/// enforces all access. Until the key is pasted (one line, or a
/// --dart-define=SUPABASE_ANON_KEY=...), account features stay hidden and the
/// app remains fully view-only. Mock-mode-first, same as everything else.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://ucgakrzintxpyqgdwues.supabase.co');

  /// The publishable client key (Supabase: "can be safely shared publicly") —
  /// RLS is the security boundary, this key only unlocks the anon role.
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_Oql2fAHWP9QnNrUHfRyIrA_bifVRLye');

  static bool get enabled => anonKey.isNotEmpty;
}
