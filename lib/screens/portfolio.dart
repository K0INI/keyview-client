import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../brand.dart';

class PortfolioScreen extends StatelessWidget {
  final String address;
  const PortfolioScreen({super.key, required this.address});

  String get shortAddr => address.length > 12
      ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
      : address;

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
      ),
      body: FutureBuilder<Portfolio>(
        future: KeyviewApi.portfolio(address),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Brand.amber));
          }
          final p = snap.data!;
          return ListView(
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
              const SizedBox(height: 8),
              ...p.holdings.map((h) => _AssetRow(h: h, money: money)),
            ],
          );
        },
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final Holding h;
  final NumberFormat money;
  const _AssetRow({required this.h, required this.money});

  @override
  Widget build(BuildContext context) {
    final up = h.change24h >= 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Brand.surface2,
          child: Text(h.symbol.substring(0, 1),
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
