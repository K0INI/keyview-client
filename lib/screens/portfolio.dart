import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../auth.dart';
import '../brand.dart';
import '../money.dart';
import '../funnel.dart';
import '../supabase_config.dart';
import '../watch.dart';
import 'collectibles.dart';
import 'sign_in.dart';
import 'token_detail.dart';

class PortfolioScreen extends StatefulWidget {
  final String address;
  const PortfolioScreen({super.key, required this.address});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  /// 0.1.9: the future is created ONCE, not inside build(). It used to be
  /// built inline in the FutureBuilder, so every rebuild — including every
  /// display-currency change — refetched the whole wallet.
  late Future<Portfolio> _future = KeyviewApi.portfolio(widget.address);
  late Future<History> _history = KeyviewApi.history(widget.address);

  void _retry() => setState(() {
        _future = KeyviewApi.portfolio(widget.address);
        _history = KeyviewApi.history(widget.address);
      });

  String get address => widget.address;

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
    // Beta finding (Craig Rader, 2026-09-09): this was the one add path that
    // used the raw cached session — an expired access token made PostgREST
    // return 401 and the button looked dead. Every other screen already
    // refreshes first; now this one does too.
    var s = await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;
    if (s == null) {
      final ok = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
      if (ok != true) return;
      s = KeyviewAuth.session.value;
      if (s == null) return;
    }
    final err = await WatchlistService.add(s, address);
    if (err == null) Funnel.track(Funnel.evWatchAdded);
    if (context.mounted) snack(err ?? 'Watching $shortAddr');
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the display currency or its rate changes.
    return ValueListenableBuilder<int>(
      valueListenable: Money.version,
      builder: (context, _, __) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
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
        future: _future,
        builder: (context, snap) {
          // 0.1.9: a failure is shown as a failure. The old code returned
          // ~$50k of sample holdings here and drew them like real money.
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error is KeyviewApiException
                  ? '${snap.error}'
                  : "Couldn't load this wallet.",
              onRetry: _retry,
            );
          }
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
                  const RatesUnavailableBanner(),
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
                          Text(Money.format(p.totalUsd),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('view-only · keys never touched',
                              style: Brand.micro(color: Brand.amber, size: 10)),
                          if (p.pricedAt != null) ...[
                            const SizedBox(height: 4),
                            Text('prices as of ${_agoShort(p.pricedAt!)}',
                                style: Brand.micro(size: 10)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Family handoff slot (spec §4.8): one quiet card, now a
                  // rotation served from apps.koini.io via /v1/promos.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PromoCarousel(),
                  ),
                  if (p.holdings.isNotEmpty && p.totalUsd > 0) ...[
                    const SizedBox(height: 8),
                    _AllocationCard(p: p),
                  ],
                  const SizedBox(height: 8),
                  ...p.holdings.map((h) => _AssetRow(
                        h: h,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => TokenDetailScreen(h: h)),
                        ),
                      )),
                  if (p.unpriced.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('NOT RELIABLY PRICED · NOT IN TOTAL',
                          style: Brand.micro()),
                    ),
                    ...p.unpriced.map((h) => _UnpricedRow(h: h)),
                  ],
                  // Collectibles — staged behind a build flag (default off) so
                  // in-flight store builds are untouched; fetches only when
                  // the user opens the section (each build costs Alchemy CU).
                  if (kCollectibles) CollectiblesSection(address: address),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text('RECENT ACTIVITY', style: Brand.micro()),
                  ),
                  _HistorySection(address: address, history: _history),
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
  final VoidCallback onTap;
  const _AssetRow({required this.h, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final up = h.change24h >= 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Brand.surface2,
          foregroundImage: (h.logoUrl != null && h.logoUrl!.isNotEmpty)
              ? NetworkImage(h.logoUrl!)
              : null,
          onForegroundImageError: (h.logoUrl != null && h.logoUrl!.isNotEmpty)
              ? (_, __) {}
              : null,
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
            Text(Money.format(h.valueUsd),
                style: const TextStyle(
                    color: Brand.warm, fontWeight: FontWeight.w600)),
            Text('${up ? '+' : ''}${h.change24h.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: up ? Brand.up : Brand.down, fontSize: 12)),
            // 0.1.9: a real price with a caveat beats a blank row. These
            // notes are why the EthFan tokens can show a value again.
            if (h.exitRisk == 'thin-for-size')
              Text('hard to exit at size', style: Brand.micro(size: 9)),
            if (h.exitRisk == 'thin-market')
              Text('thin market', style: Brand.micro(size: 9)),
            if (h.priceStale)
              Text('last known price', style: Brand.micro(size: 9)),
            if (h.priceConfidence < 0.7 && h.exitRisk == null && !h.priceStale)
              Text('~ low confidence', style: Brand.micro(size: 9)),
          ],
        ),
      ),
    );
  }
}

/// A real position we won't put a number on (spec §21): the reason is the
/// product. Tapping shows sources and liquidity so the user can judge.
class _UnpricedRow extends StatelessWidget {
  final Holding h;
  const _UnpricedRow({required this.h});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: Brand.surface,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WHY NO PRICE FOR ${h.symbol.toUpperCase()}',
                    style: Brand.micro()),
                const SizedBox(height: 10),
                Text(h.priceReason ?? 'No market data from any source.',
                    style: const TextStyle(color: Brand.warm)),
                const SizedBox(height: 14),
                Text(
                  [
                    if (h.priceSources.isNotEmpty)
                      'sources: ${h.priceSources.join(', ')}',
                    if (h.liquidityUsd != null)
                      'pool liquidity: ${Money.formatCompact(h.liquidityUsd!)}',
                    if (h.priceUsd > 0)
                      'quoted (unverified): ${Money.formatPrice(h.priceUsd)}',
                  ].join('\n'),
                  style: const TextStyle(color: Brand.warm2, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Text(
                  'KŌINIkeyview only counts what it can defend. This balance is real; its dollar value is not.',
                  style: Brand.micro(size: 10),
                ),
              ],
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: Brand.surface2,
          foregroundImage: (h.logoUrl != null && h.logoUrl!.isNotEmpty)
              ? NetworkImage(h.logoUrl!)
              : null,
          onForegroundImageError: (h.logoUrl != null && h.logoUrl!.isNotEmpty)
              ? (_, __) {}
              : null,
          child: Text(h.symbol.isEmpty ? '?' : h.symbol[0],
              style: const TextStyle(color: Brand.warm3)),
        ),
        title: Text(h.name, style: const TextStyle(color: Brand.warm2)),
        subtitle: Text('${h.amount} ${h.symbol} · ${h.chain}',
            style: const TextStyle(color: Brand.warm3, fontSize: 12)),
        trailing: Text('no reliable price',
            style: Brand.micro(color: Brand.warm3, size: 10)),
      ),
    );
  }
}

String _agoShort(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}

/// Recent transfers across every chain (Solana shows bare signatures for now).
class _HistorySection extends StatelessWidget {
  final String address;
  /// Created once by [_PortfolioScreenState], not in build(): a FutureBuilder
  /// given a future built during build refetches on every rebuild, and 0.1.9
  /// rebuilds this screen on each display-currency change.
  final Future<History> history;
  const _HistorySection({required this.address, required this.history});

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
      future: history,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Couldn't load recent activity.",
                style: Brand.micro(size: 10)),
          );
        }
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

/// Honest failure (0.1.9). Replaces the sample-data fallback that used to
/// stand in for a network error — a wrong number is worse than no number.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Brand.warm3, size: 28),
              const SizedBox(height: 14),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.warm2, height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
              const SizedBox(height: 14),
              Text('no figures are shown unless they can be verified',
                  style: Brand.micro(size: 9)),
            ],
          ),
        ),
      );
}

/// Shown when a non-USD currency is chosen but no rate could be fetched, so
/// the figures on screen are still dollars. Silence here was the reason the
/// app looked like currency selection "did nothing".
class RatesUnavailableBanner extends StatelessWidget {
  const RatesUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Money.rateMissing) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Brand.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.line),
      ),
      child: Row(children: [
        const Icon(Icons.currency_exchange_rounded, size: 14, color: Brand.amber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Exchange rates unavailable — showing US dollars.',
            style: Brand.micro(size: 10),
          ),
        ),
      ]),
    );
  }
}
