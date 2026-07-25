import 'package:flutter/material.dart';
import '../auth.dart';
import '../brand.dart';
import '../supabase_config.dart';
import 'notifications.dart';
import 'sign_in.dart';

/// Settings / account (spec §6). There is deliberately no billing screen —
/// KŌINIkeyview is pure free (§20.1), so nothing here can cost money.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
    if (mounted) setState(() {});
  }

  /// Play requires an in-app account deletion path, and the published privacy
  /// policy promises exactly this route (Settings → Account → Delete account).
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text('DELETE ACCOUNT', style: Brand.micro()),
        content: const Text(
          'This permanently removes your account, watchlist, labels, alarms and '
          'notification history.\n\nPublic blockchain data is not ours to delete '
          'and is unaffected. You can keep using the app without an account.',
          style: TextStyle(color: Brand.warm2, height: 1.5, fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Brand.down)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    final ok = s == null ? false : await KeyviewAuth.deleteAccount(s);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surface2,
      content: Text(
        ok
            ? 'Account deleted.'
            : 'Could not delete automatically — email support@koini.io and we will remove it within 30 days.',
        style: const TextStyle(color: Brand.warm),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = KeyviewAuth.session.value;
    return Scaffold(
      appBar: AppBar(title: Text('SETTINGS', style: Brand.micro())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _section('ACCOUNT'),
              _card([
                if (!SupabaseConfig.enabled)
                  _line('Accounts arrive in Beta.',
                      'Everything you can see today works without one.')
                else if (s == null) ...[
                  _line('Not signed in',
                      'An account only syncs your watchlist and enables alerts.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                        onPressed: _signIn, child: const Text('Sign in')),
                  ),
                ] else ...[
                  _line(s.email.isEmpty ? 'Signed in' : s.email,
                      'Synced across your devices.'),
                  const Divider(height: 26),
                  _tile(Icons.logout_rounded, 'Sign out',
                      onTap: _busy
                          ? null
                          : () {
                              KeyviewAuth.signOut();
                              setState(() {});
                            }),
                  _tile(Icons.delete_outline_rounded, 'Delete account',
                      danger: true, onTap: _busy ? null : _deleteAccount),
                ],
              ]),

              _section('ALERTS'),
              _card([
                _tile(Icons.notifications_none_rounded, 'Notification history',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()))),
                const Divider(height: 22),
                _line('Alarm settings live on each address.',
                    'Open a watched address, then its ⋮ menu → Alarm settings.'),
              ]),

              _section('THE PROMISE'),
              _card([
                _line('Eyes on. Keys off.',
                    'KŌINIkeyview is a view-only crypto portfolio tracker. It shows public '
                    'on-chain data for addresses you choose to watch. It never asks for, '
                    'stores, or transmits private keys or funds, and cannot make transactions.'),
                const Divider(height: 22),
                _line('We will never ask for a seed phrase.',
                    'There is no field for one anywhere in the app. Anyone who asks is not us.'),
              ]),

              _section('LEGAL'),
              _card([
                _tile(Icons.privacy_tip_outlined, 'Privacy policy',
                    onTap: () => _openDoc('privacy')),
                _tile(Icons.description_outlined, 'Terms of service',
                    onTap: () => _openDoc('terms')),
                const Divider(height: 22),
                _line('Free, with no paid tier.',
                    'No subscription, no in-app purchase, nothing to cancel.'),
              ]),

              const SizedBox(height: 22),
              Center(child: Text('EYES ON · KEYS OFF',
                  style: Brand.micro(color: Brand.amber, size: 10))),
            ],
          ),
        ),
      ),
    );
  }

  /// Legal docs live on keys.koini.io so there is one canonical copy to keep
  /// current, rather than a stale snapshot frozen into each app build.
  void _openDoc(String slug) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surface2,
      content: Text('Open keys.koini.io/$slug',
          style: const TextStyle(color: Brand.warm)),
    ));
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(t, style: Brand.micro()),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _line(String title, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Brand.warm, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(
                  color: Brand.warm3, fontSize: 12, height: 1.5)),
        ],
      );

  Widget _tile(IconData icon, String label,
          {VoidCallback? onTap, bool danger = false}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon,
            size: 18, color: danger ? Brand.down : Brand.warm3),
        title: Text(label,
            style: TextStyle(
                color: danger ? Brand.down : Brand.warm, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 18, color: Brand.warm3),
        onTap: onTap,
      );
}
