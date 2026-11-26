import 'package:flutter/material.dart';
import '../api.dart';
import '../brand.dart';
import '../money.dart';

/// Collectibles on the portfolio screen — watch-only NFT display.
///
/// Collapsed by default, and the network call happens only on the FIRST
/// expand: every uncached build costs real Alchemy compute, so a user who
/// never opens the section never spends a unit. The floor-value subtotal is
/// labelled and kept apart — it NEVER joins Total Watched, because an
/// OpenSea floor is an indicative, single-source figure for an illiquid
/// asset, not a price this product is willing to defend.
class CollectiblesSection extends StatefulWidget {
  final String address;
  const CollectiblesSection({super.key, required this.address});

  @override
  State<CollectiblesSection> createState() => _CollectiblesSectionState();
}

class _CollectiblesSectionState extends State<CollectiblesSection> {
  bool _expanded = false;
  Future<Collectibles>? _future; // created on first expand only

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _future ??= KeyviewApi.nfts(widget.address);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6, top: 2),
            child: Row(
              children: [
                Text('COLLECTIBLES', style: Brand.micro()),
                const SizedBox(width: 6),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: Brand.warm3),
              ],
            ),
          ),
        ),
        if (_expanded && _future != null)
          FutureBuilder<Collectibles>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Brand.amber))),
                );
              }
              if (snap.hasError) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(snap.error.toString(),
                        style:
                            const TextStyle(color: Brand.warm2, fontSize: 13)),
                    trailing: TextButton(
                      onPressed: () => setState(
                          () => _future = KeyviewApi.nfts(widget.address)),
                      child: const Text('Retry',
                          style: TextStyle(color: Brand.amber)),
                    ),
                  ),
                );
              }
              final c = snap.data!;
              if (!c.enabled) return const SizedBox.shrink();
              if (!c.supported) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text('Not yet supported for this address.',
                      style: TextStyle(color: Brand.warm3, fontSize: 12)),
                );
              }
              if (c.collections.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                      c.hiddenCount > 0
                          ? 'No collectibles to show (${c.hiddenCount} hidden as likely spam).'
                          : 'No collectibles found for this address.',
                      style: const TextStyle(color: Brand.warm3, fontSize: 12)),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.collectiblesUsd > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                          '≈ ${Money.format(c.collectiblesUsd)} FLOOR VALUE · NOT IN TOTAL',
                          style: Brand.micro(size: 10)),
                    ),
                  ...c.collections.map((col) => _CollectionRow(
                        c: col,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => NftCollectionScreen(c: col)),
                        ),
                      )),
                  if (c.hiddenCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4),
                      child: Text('${c.hiddenCount} hidden as likely spam',
                          style: Brand.micro(size: 10)),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _CollectionRow extends StatelessWidget {
  final NftCollection c;
  final VoidCallback onTap;
  const _CollectionRow({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: _NftThumb(imageUrl: c.imageUrl, fallback: c.name, size: 40),
        title: Text(c.name, style: const TextStyle(color: Brand.warm)),
        subtitle: Text(
            '${c.count} item${c.count == 1 ? '' : 's'} · ${c.chain}',
            style: const TextStyle(color: Brand.warm3, fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: c.valueUsd != null
              ? [
                  Text(Money.format(c.valueUsd!),
                      style: const TextStyle(
                          color: Brand.warm, fontWeight: FontWeight.w600)),
                  Text('FLOOR · OPENSEA', style: Brand.micro(size: 8)),
                ]
              : [
                  Text('no floor price',
                      style: Brand.micro(color: Brand.warm3, size: 10)),
                ],
        ),
      ),
    );
  }
}

/// Square NFT image with the same guarded-fallback discipline as token
/// logos: Alchemy CDN URL or a letter tile — never a broken-image icon.
class _NftThumb extends StatelessWidget {
  final String? imageUrl;
  final String fallback;
  final double size;
  const _NftThumb(
      {required this.imageUrl, required this.fallback, required this.size});

  @override
  Widget build(BuildContext context) {
    final letter = fallback.isEmpty ? '?' : fallback[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: Brand.surface2,
        child: (imageUrl != null && imageUrl!.isNotEmpty)
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                    child: Text(letter,
                        style: const TextStyle(color: Brand.amber))),
              )
            : Center(
                child:
                    Text(letter, style: const TextStyle(color: Brand.amber))),
      ),
    );
  }
}

/// One collection, as a grid of items.
class NftCollectionScreen extends StatelessWidget {
  final NftCollection c;
  const NftCollectionScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final more = c.itemCount - c.items.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('${c.count} ITEM${c.count == 1 ? '' : 'S'} · ${c.chain.toUpperCase()}',
                  style: Brand.micro()),
              const Spacer(),
              if (c.floorEth != null)
                Text(
                    'FLOOR ${c.floorEth!.toStringAsFixed(c.floorEth! < 0.01 ? 4 : 3)} ETH${c.valueUsd != null ? ' · ≈ ${Money.format(c.valueUsd!)}' : ''}',
                    style: Brand.micro(color: Brand.amber, size: 10))
              else
                Text('NO FLOOR PRICE', style: Brand.micro(size: 10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.floorEth != null
                ? 'Floor value is an indicative OpenSea figure, not a sale price. It is never added to your watched total.'
                : 'No marketplace floor exists for this collection, so KŌINIkeyview shows no dollar value — a real balance deserves better than an invented number.',
            style: const TextStyle(color: Brand.warm3, fontSize: 11),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: c.items
                .map((it) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            width: double.infinity,
                            child: _NftThumb(
                                imageUrl: it.imageUrl,
                                fallback: it.name ?? c.name,
                                size: 100),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          it.name ?? '#${it.tokenId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: Brand.warm2, fontSize: 10),
                        ),
                        if (it.balance > 1)
                          Text('×${it.balance.toStringAsFixed(0)}',
                              style: Brand.micro(size: 8)),
                      ],
                    ))
                .toList(),
          ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('+ $more more in this collection',
                  style: Brand.micro(size: 10)),
            ),
        ],
      ),
    );
  }
}
