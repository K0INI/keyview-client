import 'package:flutter/material.dart';
import '../api.dart';
import '../auth.dart';
import '../brand.dart';
import '../supabase_config.dart';
import '../watch.dart';
import 'alarm_config.dart';
import 'portfolio.dart';
import 'sign_in.dart';

/// Synced watchlist (Beta core). Hidden behind SupabaseConfig.enabled so the
/// app stays honest until the publishable key is pasted.
///
/// Beta additions (spec §4.4): custom labels, colour/emoji tags, and
/// drag-to-reorder with pin-to-top. Order and tags sync via `sort_order` and
/// `tags` on watched_address.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<WatchedAddress>? _items;
  String? _error;
  String? _tagFilter;
  bool _savingOrder = false;

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

  Future<Session?> _session() async =>
      await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;

  Future<void> _reload() async {
    // Refresh a stale token first; fall back to the stored one so a blip
    // in the refresh call degrades to a retryable error, not a sign-out.
    final s = await _session();
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
          // Drop a filter whose tag no longer exists on any row.
          if (_tagFilter != null &&
              !WatchlistOrdering.allTags(items)
                  .any((t) => t.toLowerCase() == _tagFilter!.toLowerCase())) {
            _tagFilter = null;
          }
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
    final s = await _session();
    if (s == null) return;
    final result = await _showEditSheet(title: 'WATCH AN ADDRESS');
    if (result == null) return;
    final address = result.address?.trim() ?? '';
    if (address.isEmpty) return;
    if (!KeyviewApi.isValidAddress(address)) {
      _snack('That does not look like a valid address.');
      return;
    }
    final err = await WatchlistService.add(s, address,
        label: result.label, tags: result.tags);
    _snack(err ?? 'Watching ${result.label?.isNotEmpty == true ? result.label : address}');
    _reload();
  }

  Future<void> _editDialog(WatchedAddress w) async {
    final s = await _session();
    if (s == null) return;
    final result = await _showEditSheet(
      title: 'EDIT',
      initialLabel: w.label ?? '',
      initialTags: w.tags.join(', '),
      fixedAddress: w.address,
    );
    if (result == null) return;
    final ok = await WatchlistService.update(s, w.id,
        label: result.label ?? '', tags: result.tags);
    if (!ok) _snack('Could not save changes.');
    _reload();
  }

  /// Shared add/edit form. Returns null when cancelled.
  Future<_EditResult?> _showEditSheet({
    required String title,
    String initialLabel = '',
    String initialTags = '',
    String? fixedAddress,
  }) {
    final addrCtrl = TextEditingController();
    final labelCtrl = TextEditingController(text: initialLabel);
    final tagsCtrl = TextEditingController(text: initialTags);

    return showDialog<_EditResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text(title, style: Brand.micro()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fixedAddress == null)
                TextField(
                  controller: addrCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Brand.warm),
                  decoration: const InputDecoration(
                      labelText: 'Address',
                      labelStyle: TextStyle(color: Brand.warm3),
                      hintText: '0x…  ·  Solana  ·  name.eth',
                      hintStyle: TextStyle(color: Brand.warm3)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(fixedAddress,
                      style: const TextStyle(
                          color: Brand.warm3,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                autofocus: fixedAddress != null,
                style: const TextStyle(color: Brand.warm),
                decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    labelStyle: TextStyle(color: Brand.warm3),
                    hintText: 'Whale #1',
                    hintStyle: TextStyle(color: Brand.warm3)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsCtrl,
                style: const TextStyle(color: Brand.warm),
                decoration: const InputDecoration(
                    labelText: 'Tags (optional)',
                    labelStyle: TextStyle(color: Brand.warm3),
                    hintText: 'cold, 🐋, defi',
                    hintStyle: TextStyle(color: Brand.warm3),
                    helperText: 'Comma separated · up to 6',
                    helperStyle: TextStyle(color: Brand.warm3, fontSize: 10)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_EditResult(
              address: fixedAddress ?? addrCtrl.text,
              label: labelCtrl.text,
              tags: WatchedAddress.splitTagInput(tagsCtrl.text),
            )),
            child: Text(fixedAddress == null ? 'Watch' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _persistOrder(List<WatchedAddress> ordered) async {
    // Optimistic: the list already shows the new order. If the write fails we
    // reload, which snaps back to the server's truth rather than lying.
    setState(() {
      _items = ordered;
      _savingOrder = true;
    });
    final s = await _session();
    if (s == null) return;
    final ok = await WatchlistService.reorder(s, ordered);
    if (mounted) setState(() => _savingOrder = false);
    if (!ok) {
      _snack('Could not save the new order.');
      _reload();
    }
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
          if (_savingOrder)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.amber)),
              ),
            ),
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
            const Text('Sign in to sync a watchlist across devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.warm2)),
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

    final tags = WatchlistOrdering.allTags(items);
    final visible = WatchlistOrdering.filterByTag(items, _tagFilter);
    // Reordering while filtered would be ambiguous — the dropped index refers
    // to the filtered list, not the real one. Disable drag instead of guessing.
    final canReorder = _tagFilter == null;

    return Column(
      children: [
        if (tags.isNotEmpty) _tagBar(tags),
        Expanded(
          child: canReorder
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visible.length,
                  onReorder: (oldIndex, newIndex) => _persistOrder(
                      WatchlistOrdering.move(visible, oldIndex, newIndex)),
                  proxyDecorator: (child, _, __) => Material(
                      color: Colors.transparent,
                      elevation: 6,
                      child: child),
                  itemBuilder: (ctx, i) =>
                      _row(visible[i], key: ValueKey(visible[i].id)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) =>
                      _row(visible[i], key: ValueKey(visible[i].id)),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('view-only · keys never touched',
              style: Brand.micro(color: Brand.amber, size: 10)),
        ),
      ],
    );
  }

  Widget _tagBar(List<String> tags) => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            _tagChip('All', _tagFilter == null, () {
              setState(() => _tagFilter = null);
            }),
            for (final t in tags)
              _tagChip(
                  t,
                  _tagFilter != null &&
                      _tagFilter!.toLowerCase() == t.toLowerCase(), () {
                setState(() => _tagFilter =
                    _tagFilter?.toLowerCase() == t.toLowerCase() ? null : t);
              }),
          ],
        ),
      );

  Widget _tagChip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? Brand.amber.withValues(alpha: .14) : Brand.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: active
                      ? Brand.amber.withValues(alpha: .55)
                      : Brand.line),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      color: active ? Brand.amber : Brand.warm2, fontSize: 12)),
            ),
          ),
        ),
      );

  Widget _row(WatchedAddress w, {required Key key}) => Card(
        key: key,
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
          title: Text(w.displayName,
              style: const TextStyle(color: Brand.warm, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w.shortAddress} · ${w.chainKind}',
                  style: const TextStyle(color: Brand.warm3, fontSize: 11)),
              if (w.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final t in w.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Brand.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Brand.line),
                          ),
                          child: Text(t,
                              style: const TextStyle(
                                  color: Brand.warm2, fontSize: 10)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Options',
            color: Brand.surface2,
            icon: const Icon(Icons.more_vert_rounded,
                size: 18, color: Brand.warm3),
            onSelected: (v) async {
              if (v == 'edit') return _editDialog(w);
              if (v == 'alarm') {
                final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => AlarmConfigScreen(watched: w)));
                if (changed == true) _reload();
                return;
              }
              if (v == 'pin') {
                final all = _items;
                if (all == null) return;
                final at = all.indexWhere((e) => e.id == w.id);
                if (at > 0) {
                  await _persistOrder(WatchlistOrdering.pinToTop(all, at));
                }
                return;
              }
              if (v == 'remove') {
                final s2 = await _session();
                if (s2 == null) return;
                await WatchlistService.remove(s2, w.id);
                _reload();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'alarm', child: Text('Alarm settings')),
              PopupMenuItem(value: 'edit', child: Text('Edit label & tags')),
              PopupMenuItem(value: 'pin', child: Text('Pin to top')),
              PopupMenuItem(value: 'remove', child: Text('Stop watching')),
            ],
          ),
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

class _EditResult {
  final String? address;
  final String? label;
  final List<String> tags;
  const _EditResult({this.address, this.label, this.tags = const []});
}
