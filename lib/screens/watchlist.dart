import 'package:flutter/material.dart';
import '../api.dart';
import '../auth.dart';
import '../brand.dart';
import '../supabase_config.dart';
import '../watch.dart';
import 'portfolio.dart';
import 'sign_in.dart';

/// Synced watchlist (Beta core). Hidden behind SupabaseConfig.enabled so the
/// app stays honest until the publishable key is pasted.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<WatchedAddress>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    KeyviewAuth.session.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    KeyviewAuth.session.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    // Refresh a stale token first; fall back to the stored one so a blip
    // in the refresh call degrades to a retryable error, not a sign-out.
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) {
      if (mounted) setState(() => _items = null);
      return;
    }
    try {
      final items = await WatchlistService.list(s);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your watchlist.');
    }
  }

  Future<void> _signIn() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
    if (ok == true) _reload();
  }

  Future<void> _addDialog() async {
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) return;
    final ctrl = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text('WATCH AN ADDRESS', style: Brand.micro()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Brand.warm),
          decoration: const InputDecoration(
              hintText: '0x…  ·  Solana  ·  name.eth',
              hintStyle: TextStyle(color: Brand.warm3)),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Watch')),
        ],
      ),
    );
    if (address == null || address.isEmpty) return;
    if (!KeyviewApi.isValidAddress(address)) {
      _snack('That does not look like a valid address.');
      return;
    }
    final err = await WatchlistService.add(s, address);
    _snack(err ?? 'Watching $address');
    _reload();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surface2,
      content: Text(msg, style: const TextStyle(color: Brand.warm)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = KeyviewAuth.session.value;
    return Scaffold(
      appBar: AppBar(
        title: Text('MY WATCHLIST', style: Brand.micro()),
        actions: [
          if (s != null)
            IconButton(
              tooltip: 'Add address',
              onPressed: _addDialog,
              icon: const Icon(Icons.add_rounded, color: Brand.amber),
            ),
          if (s != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => KeyviewAuth.signOut(),
              icon: const Icon(Icons.logout_rounded,
                  size: 18, color: Brand.warm3),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _body(s),
        ),
      ),
    );
  }

  Widget _body(Session? s) {
    if (!SupabaseConfig.enabled) {
      return _message(
          'Accounts arrive in Beta.\nWatchlists will sync across your devices — still view-only, still no keys.');
    }
    if (s == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in to sync a watchlist across devices.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.warm2)),
            const SizedBox(height: 16),
            SizedBox(
                height: 48,
                child: FilledButton(
                    onPressed: _signIn, child: const Text('Sign in'))),
          ],
        ),
      );
    }
    if (_error != null) return _message(_error!);
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.amber));
    }
    if (items.isEmpty) {
      return _message('Nothing watched yet.\nTap + to add your first address.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final w in items)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PortfolioScreen(address: w.address))),
              leading: Icon(
                w.chainKind == 'solana'
                    ? Icons.wb_sunny_outlined
                    : Icons.diamond_outlined,
                size: 18,
                color: Brand.amber,
              ),
              title: Text(
                w.label?.isNotEmpty == true ? w.label! : _short(w.address),
                style: const TextStyle(color: Brand.warm, fontSize: 14),
              ),
              subtitle: Text(
                '${_short(w.address)} · ${w.chainKind}',
                style: const TextStyle(color: Brand.warm3, fontSize: 11),
              ),
              trailing: IconButton(
                tooltip: 'Stop watching',
                icon: const Icon(Icons.visibility_off_outlined,
                    size: 17, color: Brand.warm3),
                onPressed: () async {
                  final s2 = await KeyviewAuth.ensureFresh() ??
                      KeyviewAuth.session.value;
                  if (s2 == null) return;
                  await WatchlistService.remove(s2, w.id);
                  _reload();
                },
              ),
            ),
          ),
        const SizedBox(height: 14),
        Center(
            child: Text('view-only · keys never touched',
                style: Brand.micro(color: Brand.amber, size: 10))),
      ],
    );
  }

  static String _short(String a) => a.length > 14
      ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}'
      : a;

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.warm2, height: 1.6)),
        ),
      );
}
