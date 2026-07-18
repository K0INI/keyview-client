import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../auth.dart';
import '../brand.dart';
import '../supabase_config.dart';
import '../watch.dart';
import 'sign_in.dart';
import 'token_detail.dart';

class PortfolioScreen extends StatelessWidget {
  final String address;
  const PortfolioScreen({super.key, required this.address});

  String get shortAddr => address.length > 12
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;

  Future<void> _watch(BuildContext context) async {
    void snack(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Brand.surface2,
        content: Text(msg, style: const TextStyle(color: Brand.warm)),
      ));
    }

    if (!SupabaseConfig.enabled) {
      snack('Accounts arrive in Beta — watchlists sync then.');
      return;
    }
    var s = KeyviewAuth.session.value;
    if (s == null) {
      final ok = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (ok != true) return;
      s = KeyviewAuth.session.value;
      if (s == null) return;
    }
    final err = await WatchlistService.add(s, address);
    if (context.mounted) snack(err ?? 'Watching $shortAddr');
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: r'$');
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('WATCHING ', style: Brand.micro()),
          Text(shortAddr,
              style: const TextStyle(fontSize: 14, color: Brand.warm)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Add to watchlist',
            onPressed: () => _watch(context),
            icon: const Icon(Icons.star_border_rounded, color: Brand.amber),
          ),
        ],
      ),
      body: FutureBuilder<Portfolio>(
        future: KeyviewApi.portfolio(address),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Brand.amber));
          }
          final p = snap.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('TOTAL VALUE WATCHED', style: Brand.micro()),
                            const Spacer(),
                            if (p.isMock)
                              Text('SAMPLE DATA', style: Brand.micro(size: 9)),
                          ]),
                          const SizedBox(height: 6),
                          Text(money.format(p.totalUsd),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('view-only · keys never touched',
                              style: Brand.micro(color: Brand.amber, size: 10)),
                        ],
                      ),
                    ),
                  ),
                  if (p.holdings.isNotEmpty && p.totalUsd > 0) ...[
                    const SizedBox(height: 8),
                    _AllocationCard(p: p),
                  ],
                  const SizedBox(height: 8),
                  ...p.holdings.map((h) => _AssetRow(
                        h: h,
                        money: money,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => TokenDetailScreen(h: h)),
                        ),
                      )),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text('RECENT ACTIVITY', style: Brand.micro()),
                  ),
                  _HistorySection(address: address),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Stacked allocation bar + legend: top holdings as a share of total value.
class _AllocationCard extends StatelessWidget {
  final Portfolio p;
  const _AllocationCard({required this.p});

  static const _palette = [
    Brand.amber,
    Brand.up,
    Brand.down,
    Brand.warm,
    Brand.warm2,
    Brand.warm3,
  ];

  @override
  Widget build(BuildContext context) {
    final sorted = [...p.holdings]
      ..sort((a, b) => b.valueUsd.compareTo(a.valueUsd));
    final top = sorted.take(_palette.length).toList();
    final otherUsd =
        sorted.skip(_palette.length).fold<double>(0, (s, h) => s + h.valueUsd);

    final slices = <(String, double, Color)>[
      for (var i = 0; i < top.length; i++)
        (top[i].symbol, top[i].valueUsd / p.totalUsd, _palette[i]),
      if (otherUsd > 0) ('OTHER', otherUsd / p.totalUsd, Brand.surface2),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ALLOCATION', style: Brand.micro()),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  for (final s in slices)
                    Expanded(
                      flex: (s.$2 * 1000).round().clamp(1, 1000).toInt(),
                      child: Container(color: s.$3),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final s in slices)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${s.$1} ${(s.$2 * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: Brand.warm2, fontSize: 12)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final Holding h;
  final NumberFormat money;
  final VoidCallback onTap;
  const _AssetRow({required this.h, required this.money, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final up = h.change24h >= 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Brand.surface2,
          child: Text(h.symbol.isEmpty ? '?' : h.symbol[0],
              style: const TextStyle(color: Brand.amber)),
        ),
        title: Text(h.name, style: const TextStyle(color: Brand.warm)),
        subtitle: Text('${h.amount} ${h.symbol} · ${h.chain}',
            style: const TextStyle(color: Brand.warm3, fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money.format(h.valueUsd),
                style: const TextStyle(
                    color: Brand.warm, fontWeight: FontWeight.w600)),
            Text('${up ? '+' : ''}${h.change24h.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: up ? Brand.up : Brand.down, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Recent transfers across every chain (Solana shows bare signatures for now).
class _HistorySection extends StatelessWidget {
  final String address;
  const _HistorySection({required this.address});

  static String _ago(int timeMs) {
    if (timeMs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(timeMs);
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return DateFormat.yMMMd().format(t);
  }

  @override
  Widget build(BuildContext context) {
    final amt = NumberFormat('#,##0.######');
    return FutureBuilder<History>(
      future: KeyviewApi.history(address),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.amber))),
          );
        }
        final events = snap.data!.events;
        if (events.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('No recent activity found.',
                  style: TextStyle(color: Brand.warm3)),
            ),
          );
        }
        return Card(
          child: Column(children: [
            for (final e in events.take(12))
              ListTile(
                dense: true,
                leading: Icon(
                  e.direction == 'in'
                      ? Icons.south_west_rounded
                      : e.direction == 'out'
                          ? Icons.north_east_rounded
                          : Icons.bolt_rounded,
                  size: 18,
                  color: e.direction == 'in'
                      ? Brand.up
                      : e.direction == 'out'
                          ? Brand.down
                          : Brand.warm3,
                ),
                title: Text(
                  e.direction == 'in'
                      ? 'Received ${e.asset}'.trim()
                      : e.direction == 'out'
                          ? 'Sent ${e.asset}'.trim()
                          : 'Activity',
                  style: const TextStyle(color: Brand.warm, fontSize: 13),
                ),
                subtitle: Text('${e.chain} · ${_ago(e.timeMs)}',
                    style:
                        const TextStyle(color: Brand.warm3, fontSize: 11)),
                trailing: e.amount == null
                    ? null
                    : Text(amt.format(e.amount),
                        style: const TextStyle(
                            color: Brand.warm2, fontSize: 12)),
              ),
          ]),
        );
      },
    );
  }
}
