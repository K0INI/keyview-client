import 'package:flutter/material.dart';
import '../auth.dart';
import '../brand.dart';
import '../funnel.dart';
import '../push.dart';
import '../supabase_config.dart';
import 'portfolio.dart';
import 'sign_in.dart';

/// Notifications feed — the history of every alarm that fired (spec §6, §11).
///
/// Reads `notification_log`, which the backend writes BEFORE attempting to
/// push. That ordering is deliberate: if a push is dropped by the OS or the
/// network, the alert is still here. This screen is the durable record.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationEntry>? _items;
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
    final s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) {
      if (mounted) setState(() => _items = null);
      return;
    }
    try {
      final items = await PushService.feed(s);
      if (mounted) setState(() { _items = items; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your notifications.');
    }
  }

  Future<void> _signIn() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('NOTIFICATIONS', style: Brand.micro()),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 19, color: Brand.warm3),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _body(),
          ),
        ),
      );

  Widget _body() {
    if (!SupabaseConfig.enabled) {
      return _message('Alerts arrive in Beta.\nSet an alarm on any watched address and its history lands here.');
    }
    final s = KeyviewAuth.session.value;
    if (s == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sign in to see your alert history.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.warm2)),
            const SizedBox(height: 16),
            SizedBox(
                height: 48,
                child: FilledButton(onPressed: _signIn, child: const Text('Sign in'))),
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
      return _message('No alerts yet.\nWhen a watched wallet moves, it shows up here.');
    }

    final sections = FeedFormat.groupByDay(items, DateTime.now());
    return RefreshIndicator(
      color: Brand.amber,
      backgroundColor: Brand.surface,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final sec in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(sec.label.toUpperCase(), style: Brand.micro()),
            ),
            for (final e in sec.entries) _tile(e),
          ],
          const SizedBox(height: 18),
          Center(
            child: Text('alerts are best-effort · never a security system',
                style: Brand.micro(size: 9.5)),
          ),
        ],
      ),
    );
  }

  Widget _tile(NotificationEntry e) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: () {
            Funnel.track(Funnel.evNotificationTapped);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PortfolioScreen(address: e.address)));
          },
          leading: const Icon(Icons.notifications_active_outlined,
              size: 18, color: Brand.amber),
          title: Text(e.summary,
              style: const TextStyle(color: Brand.warm, fontSize: 13.5, height: 1.4)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${e.shortAddress} · ${FeedFormat.relative(e.firedAt, DateTime.now())}',
              style: const TextStyle(color: Brand.warm3, fontSize: 11),
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded,
              size: 18, color: Brand.warm3),
        ),
      );

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.warm2, height: 1.6)),
        ),
      );
}
