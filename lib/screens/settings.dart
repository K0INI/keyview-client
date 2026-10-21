import 'package:flutter/material.dart';
import '../auth.dart';
import '../brand.dart';
import '../money.dart';
import '../si.dart';
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
  bool _siBusy = false;

  @override
  void initState() {
    super.initState();
    // Cheap and fail-soft; keeps the SI section honest after store changes.
    SiService.refresh();
  }

  // ── SI call alerts ─────────────────────────────────────────────────────────

  Future<void> _subscribe() async {
    setState(() => _siBusy = true);
    String? err;
    if (!SiService.purchasesSupported) {
      err = 'Subscribing is available in the iPhone and Android apps. '
          'Once subscribed, SI works here too.';
    } else {
      final p = await SiService.monthlyPackage();
      err = p == null
          ? 'Could not reach the store — try again.'
          : await SiService.buy(p);
    }
    if (!mounted) return;
    setState(() => _siBusy = false);
    if (err != null) _snackText(err);
  }

  Future<void> _restore() async {
    setState(() => _siBusy = true);
    final err = await SiService.restore();
    if (!mounted) return;
    setState(() => _siBusy = false);
    _snackText(err ?? 'SI restored.');
  }

  Future<void> _verifyPhone() async {
    final phoneCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    var codeSent = false;
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: Brand.surface,
          title: Text(codeSent ? 'ENTER THE CODE' : 'YOUR PHONE NUMBER',
              style: Brand.micro()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  codeSent
                      ? 'We texted a 6-digit code to ${phoneCtrl.text.trim()}.'
                      : 'The COINY agent calls this number for your alerts. '
                          'We text a code to confirm it’s yours.',
                  style: const TextStyle(
                      color: Brand.warm2, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 12),
              if (!codeSent)
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  style: const TextStyle(color: Brand.warm),
                  decoration: InputDecoration(
                    hintText: '(555) 123-4567',
                    hintStyle: const TextStyle(color: Brand.warm3),
                    errorText: error,
                  ),
                )
              else
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  style: const TextStyle(
                      color: Brand.warm, fontSize: 20, letterSpacing: 6),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: const TextStyle(color: Brand.warm3),
                    errorText: error,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!codeSent) {
                  final e = await SiService.sendCode(phoneCtrl.text);
                  setDlg(() {
                    error = e;
                    if (e == null) codeSent = true;
                  });
                } else {
                  final e =
                      await SiService.verifyCode(phoneCtrl.text, codeCtrl.text);
                  if (e == null) {
                    Navigator.of(ctx).pop(true);
                  } else {
                    setDlg(() => error = e);
                  }
                }
              },
              child: Text(codeSent ? 'Verify' : 'Text me a code'),
            ),
          ],
        ),
      ),
    );
    phoneCtrl.dispose();
    codeCtrl.dispose();
    if (!mounted) return;
    setState(() {});
    if (done == true) _snackText('Phone verified.');
  }

  void _snackText(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surface2,
      content: Text(msg, style: const TextStyle(color: Brand.warm)),
    ));
  }

  /// Currency chooser. Converting is display-only — every price, total and
  /// alarm threshold stays in USD underneath, so switching back and forth can
  /// never change what the app is actually tracking.
  Future<void> _pickCurrency() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(children: [
                  Text('DISPLAY CURRENCY', style: Brand.micro()),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Brand.warm3),
                  ),
                ]),
              ),
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: Money.currencies.length,
                  itemBuilder: (_, i) {
                    final c = Money.currencies[i];
                    final selected = c.code == Money.code;
                    return ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 44,
                        child: Text(c.symbol.trim(),
                            style: TextStyle(
                                color: selected ? Brand.amber : Brand.warm,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      title: Text(c.name,
                          style: TextStyle(
                              color: selected ? Brand.amber : Brand.warm,
                              fontSize: 14)),
                      subtitle: Text(c.code,
                          style: const TextStyle(
                              color: Brand.warm3, fontSize: 11)),
                      trailing: selected
                          ? const Icon(Icons.check_rounded,
                              size: 18, color: Brand.amber)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(c.code),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await Money.setCurrency(chosen);
    if (!mounted) return;
    setState(() {});
    if (Money.rateMissing) {
      final why = Money.lastError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Brand.surface2,
        duration: const Duration(seconds: 6),
        content: Text(
            why == null
                ? 'No exchange rate available, so values stay in US dollars.'
                : 'No exchange rate available ($why), so values stay in US '
                    'dollars.',
            style: const TextStyle(color: Brand.warm)),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Brand.amber,
          onPressed: () async {
            await Money.refreshRates();
            if (mounted) setState(() {});
          },
        ),
      ));
    } else if (Money.ratesStale) {
      final a = Money.ratesAsOf;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Brand.surface2,
        content: Text(
            "Converting at the last rate we were able to fetch"
            "${a == null ? '' : ' (${a.toLocal().toString().split('.').first})'}.",
            style: const TextStyle(color: Brand.warm)),
      ));
    }
  }

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

              _section('DISPLAY'),
              _card([
                ValueListenableBuilder<int>(
                  valueListenable: Money.version,
                  builder: (context, _, __) => _tile(
                    Icons.payments_outlined,
                    'Currency',
                    trailingText:
                        '${Money.current.code} · ${Money.current.symbol.trim()}',
                    onTap: _pickCurrency,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                    'Holdings are priced in US dollars and converted for display at the day\u2019s rate.',
                    style: TextStyle(
                        color: Brand.warm3, fontSize: 12, height: 1.5)),
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

              _section('SI CALL ALERTS'),
              _card([
                ValueListenableBuilder<SiStatus>(
                  valueListenable: SiService.status,
                  builder: (context, st, _) => ValueListenableBuilder<String?>(
                    valueListenable: SiService.phone,
                    builder: (context, ph, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s == null)
                          _line('Sign in to use SI.',
                              'SI calls your phone when a big move hits a wallet '
                              'you alarm — the COINY voice agent answers questions '
                              'about your holdings on every call.')
                        else if (st == SiStatus.active) ...[
                          _line('SI — active',
                              '45 call-minutes a month, shared across your KŌINI '
                              'apps. Turn calls on per alarm: open a watched '
                              'address → Alarm settings → Phone calls.'),
                          const Divider(height: 22),
                          _tile(
                              Icons.phone_iphone_rounded,
                              ph == null ? 'Verify your phone' : 'Phone',
                              trailingText: ph,
                              onTap: _siBusy ? null : _verifyPhone),
                          if (ph != null)
                            _tile(Icons.phone_disabled_rounded, 'Remove phone',
                                danger: true,
                                onTap: _siBusy
                                    ? null
                                    : () async {
                                        final ok =
                                            await SiService.removePhone();
                                        if (!mounted) return;
                                        setState(() {});
                                        _snackText(ok
                                            ? 'Phone removed — calls off.'
                                            : 'Could not remove — try again.');
                                      }),
                        ] else ...[
                          _line('A voice agent on call for your wallets.',
                              'SI calls you when a large transaction hits a wallet '
                              'you alarm. Ask it about your holdings, prices and '
                              'recent alerts — it knows your KŌINIkeyview list. '
                              '\$14.99/month, 45 call-minutes across your KŌINI '
                              'apps. It reads facts and never gives financial '
                              'advice.'),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 46,
                            child: FilledButton(
                              onPressed: _siBusy ? null : _subscribe,
                              child: _siBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Brand.amberInk))
                                  : const Text('Subscribe to SI'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton(
                                onPressed: _siBusy ? null : _restore,
                                child: const Text('Restore purchases',
                                    style: TextStyle(
                                        color: Brand.warm3, fontSize: 12))),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
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
                _line('Free to use.',
                    'Watching, alarms and push alerts cost nothing. SI call '
                    'alerts are the one optional subscription — cancel any time '
                    'in your app store account.'),
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
          {VoidCallback? onTap, bool danger = false, String? trailingText}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon,
            size: 18, color: danger ? Brand.down : Brand.warm3),
        title: Text(label,
            style: TextStyle(
                color: danger ? Brand.down : Brand.warm, fontSize: 14)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailingText != null)
            Text(trailingText,
                style: const TextStyle(color: Brand.warm2, fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: Brand.warm3),
        ]),
        onTap: onTap,
      );
}
