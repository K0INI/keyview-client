import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../brand.dart';

/// Per-holding detail: position, price, chain, contract, explorer reference.
/// View-only by design — there is nothing here that can move funds.
class TokenDetailScreen extends StatelessWidget {
  final Holding h;
  const TokenDetailScreen({super.key, required this.h});

  String _price(double v) =>
      v >= 1 ? NumberFormat.currency(symbol: r'$').format(v) : '\$${v.toStringAsPrecision(3)}';

  String _shorten(String s) =>
      s.length > 16 ? '${s.substring(0, 8)}…${s.substring(s.length - 6)}' : s;

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surface2,
      content: Text('$label copied',
          style: const TextStyle(color: Brand.warm)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: r'$');
    final up = h.change24h >= 0;
    final explorer = KeyviewApi.explorerTokenUrl(h) ??
        (KeyviewApi.explorers[h.chain] ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(h.symbol, style: const TextStyle(color: Brand.warm)),
          const SizedBox(width: 10),
          Text(h.chain.toUpperCase(), style: Brand.micro(size: 10)),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                        CircleAvatar(
                          backgroundColor: Brand.surface2,
                          child: Text(h.symbol.isEmpty ? '?' : h.symbol[0],
                              style: const TextStyle(color: Brand.amber)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(h.name,
                              style: const TextStyle(
                                  color: Brand.warm,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16)),
                        ),
                        Text('${up ? '+' : ''}${h.change24h.toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: up ? Brand.up : Brand.down,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 16),
                      Text('POSITION VALUE', style: Brand.micro()),
                      const SizedBox(height: 4),
                      Text(money.format(h.valueUsd),
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${h.amount} ${h.symbol} · ${_price(h.priceUsd)} each',
                          style: const TextStyle(
                              color: Brand.warm2, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  _row('CHAIN', h.chain),
                  _row('AMOUNT', '${h.amount}'),
                  _row('PRICE', _price(h.priceUsd)),
                  if (h.contract != null)
                    _row('CONTRACT', _shorten(h.contract!),
                        onCopy: () =>
                            _copy(context, 'Contract', h.contract!)),
                  if (explorer.isNotEmpty)
                    _row('EXPLORER', Uri.parse(explorer).host,
                        onCopy: () => _copy(context, 'Explorer link', explorer)),
                ]),
              ),
              const SizedBox(height: 14),
              Center(
                  child: Text('view-only · keys never touched',
                      style: Brand.micro(color: Brand.amber, size: 10))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onCopy}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text(label, style: Brand.micro(size: 10)),
          const Spacer(),
          Text(value,
              style: const TextStyle(color: Brand.warm, fontSize: 13)),
          if (onCopy != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onCopy,
              child: const Icon(Icons.copy_rounded,
                  size: 15, color: Brand.warm3),
            ),
          ],
        ]),
      );
}
