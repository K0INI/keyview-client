import 'package:flutter/material.dart';
import '../alarms.dart';
import '../auth.dart';
import '../brand.dart';
import '../funnel.dart';
import '../push.dart';
import '../watch.dart';

/// Alarm settings for one watched address (spec §4.5, defaults §20.5).
///
/// Every control is written in plain language — a person setting this up should
/// never have to know what "direction" or "threshold" means in our schema.
class AlarmConfigScreen extends StatefulWidget {
  final WatchedAddress watched;
  const AlarmConfigScreen({super.key, required this.watched});

  @override
  State<AlarmConfigScreen> createState() => _AlarmConfigScreenState();
}

class _AlarmConfigScreenState extends State<AlarmConfigScreen> {
  Alarm? _alarm;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _thresholdError;

  late final TextEditingController _thresholdCtrl = TextEditingController();
  late final TextEditingController _tokensCtrl = TextEditingController();

  /// Digest windows offered, in minutes. 10 is the spec default.
  static const _windows = [5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _tokensCtrl.dispose();
    super.dispose();
  }

  Future<Session?> _session() async =>
      await KeyviewAuth.ensureFresh() ?? KeyviewAuth.session.value;

  Future<void> _load() async {
    final s = await _session();
    if (s == null) {
      if (mounted) setState(() { _loading = false; _error = 'Please sign in.'; });
      return;
    }
    try {
      final existing = await AlarmService.forAddress(s, widget.watched.id);
      // No alarm yet → start from the locked §20.5 defaults, stamped with this
      // device's UTC offset so quiet hours mean the user's local night.
      final a = existing ??
          Alarm.withDefaults(widget.watched.id,
              tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes);
      if (!mounted) return;
      setState(() {
        _alarm = a;
        _loading = false;
        _thresholdCtrl.text =
            a.valueThresholdUsd == null ? '' : _plain(a.valueThresholdUsd!);
        _tokensCtrl.text = a.tokenFilter == 'all' ? '' : a.tokenFilter;
      });
    } catch (_) {
      if (mounted) {
        setState(() { _loading = false; _error = 'Could not load alarm settings.'; });
      }
    }
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _update(Alarm Function(Alarm) f) {
    final a = _alarm;
    if (a == null) return;
    setState(() => _alarm = f(a));
  }

  Future<void> _save() async {
    final a = _alarm;
    if (a == null) return;

    final t = AlarmFormat.parseThreshold(_thresholdCtrl.text);
    if (!t.ok) {
      setState(() => _thresholdError = t.error);
      return;
    }
    setState(() { _thresholdError = null; _saving = true; });

    final next = a.copyWith(
      valueThresholdUsd: t.value,
      clearThreshold: t.value == null,
      tokenFilter: AlarmFormat.parseTokenFilter(_tokensCtrl.text),
      // Always re-stamp the offset: the user may have travelled since the
      // alarm was created, and quiet hours are evaluated server-side.
      tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
    );

    final s = await _session();
    if (s == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final err = await AlarmService.save(s, next);
    if (err == null) {
      // Registration is ref-counted server-side and is safe to repeat. It is
      // deliberately not allowed to fail the save: the settings are stored, and
      // a missed registration retries next time the alarm is touched.
      await PushService.setMonitoring(s, widget.watched.address, on: next.enabled);
      Funnel.track(Funnel.evAlarmCreated);
    }
    if (!mounted) return;
    setState(() { _saving = false; _alarm = next; });
    if (err != null) {
      _snack(err);
    } else {
      _snack(next.enabled ? 'Alarm saved.' : 'Alarm saved — notifications off.');
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final a = _alarm;
    if (a?.id == null) {
      Navigator.of(context).pop(false);
      return;
    }
    final s = await _session();
    if (s == null) return;
    final ok = await AlarmService.remove(s, a!.id!);
    if (ok) await PushService.setMonitoring(s, widget.watched.address, on: false);
    if (!mounted) return;
    _snack(ok ? 'Alarm removed.' : 'Could not remove the alarm.');
    if (ok) Navigator.of(context).pop(true);
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
    final a = _alarm;
    return Scaffold(
      appBar: AppBar(
        title: Text('ALARM', style: Brand.micro()),
        actions: [
          if (a?.id != null)
            IconButton(
              tooltip: 'Remove alarm',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 19, color: Brand.warm3),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.amber))
              : (_error != null || a == null)
                  ? Center(
                      child: Text(_error ?? 'Unavailable',
                          style: const TextStyle(color: Brand.warm2)))
                  : _form(a),
        ),
      ),
    );
  }

  Widget _form(Alarm a) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _header(a),
          const SizedBox(height: 14),

          // ── master switch ────────────────────────────────────────────────
          _card([
            SwitchListTile(
              value: a.enabled,
              activeColor: Brand.amber,
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify me about this wallet',
                  style: TextStyle(color: Brand.warm, fontSize: 14)),
              subtitle: const Text('Turn off to keep watching silently.',
                  style: TextStyle(color: Brand.warm3, fontSize: 11)),
              onChanged: (v) => _update((x) => x.copyWith(enabled: v)),
            ),
          ]),

          _sectionLabel('WHAT TO TELL ME ABOUT'),
          _card([
            _rowLabel('Money moving'),
            const SizedBox(height: 8),
            _directionPicker(a),
            const Divider(height: 26),
            _rowLabel('Only amounts over'),
            const SizedBox(height: 6),
            TextField(
              controller: _thresholdCtrl,
              enabled: a.enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Brand.warm),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: const TextStyle(color: Brand.warm3),
                hintText: 'Any amount',
                hintStyle: const TextStyle(color: Brand.warm3),
                errorText: _thresholdError,
                helperText: 'Leave blank to hear about every transaction.',
                helperStyle: const TextStyle(color: Brand.warm3, fontSize: 10),
              ),
            ),
            const SizedBox(height: 14),
            _rowLabel('Only these coins'),
            const SizedBox(height: 6),
            TextField(
              controller: _tokensCtrl,
              enabled: a.enabled,
              style: const TextStyle(color: Brand.warm),
              decoration: const InputDecoration(
                hintText: 'All coins',
                hintStyle: TextStyle(color: Brand.warm3),
                helperText: 'Comma separated, e.g. ETH, USDC. Blank means all.',
                helperStyle: TextStyle(color: Brand.warm3, fontSize: 10),
              ),
            ),
            const Divider(height: 26),
            SwitchListTile(
              value: a.spamFilter,
              activeColor: Brand.amber,
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide junk tokens',
                  style: TextStyle(color: Brand.warm, fontSize: 14)),
              subtitle: const Text(
                  'Strangers can send worthless tokens to any wallet. This keeps them quiet.',
                  style: TextStyle(color: Brand.warm3, fontSize: 11)),
              onChanged:
                  a.enabled ? (v) => _update((x) => x.copyWith(spamFilter: v)) : null,
            ),
          ]),

          _sectionLabel('HOW OFTEN'),
          _card([
            SwitchListTile(
              value: a.batchingEnabled,
              activeColor: Brand.amber,
              contentPadding: EdgeInsets.zero,
              title: const Text('Group busy periods',
                  style: TextStyle(color: Brand.warm, fontSize: 14)),
              subtitle: const Text(
                  'A single transaction still alerts you straight away. Only bursts get combined.',
                  style: TextStyle(color: Brand.warm3, fontSize: 11)),
              onChanged: a.enabled
                  ? (v) => _update((x) => x.copyWith(batchingEnabled: v))
                  : null,
            ),
            if (a.batchingEnabled) ...[
              const SizedBox(height: 6),
              _rowLabel('Combine anything within'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _windows)
                    _choice('$m min', a.batchingWindowMin == m,
                        a.enabled ? () => _update((x) => x.copyWith(batchingWindowMin: m)) : null),
                ],
              ),
            ],
          ]),

          _sectionLabel('WHEN NOT TO DISTURB'),
          _card([
            SwitchListTile(
              value: a.quietHoursEnabled,
              activeColor: Brand.amber,
              contentPadding: EdgeInsets.zero,
              title: const Text('Stay quiet overnight',
                  style: TextStyle(color: Brand.warm, fontSize: 14)),
              subtitle: Text(
                  a.quietHoursEnabled
                      ? 'Held until ${AlarmFormat.prettyPreset(a.quietPreset).split('–').last.trim()}, then sent as one summary.'
                      : 'Alerts can arrive at any hour.',
                  style: const TextStyle(color: Brand.warm3, fontSize: 11)),
              onChanged: a.enabled
                  ? (v) => _update((x) => x.copyWith(quietHoursEnabled: v))
                  : null,
            ),
            if (a.quietHoursEnabled) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _hourField('From', a, isStart: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _hourField('Until', a, isStart: false)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Your local time · ${AlarmFormat.prettyPreset(a.quietPreset)}',
                  style: Brand.micro(size: 10)),
            ],
          ]),

          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.amberInk))
                  : const Text('Save alarm'),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('alerts are best-effort · never a security system',
                style: Brand.micro(size: 9.5)),
          ),
        ],
      );

  Widget _header(Alarm a) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.watched.displayName,
                style: const TextStyle(
                    color: Brand.warm, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text(widget.watched.shortAddress,
                style: const TextStyle(color: Brand.warm3, fontSize: 11)),
            const SizedBox(height: 10),
            Text(a.summary,
                style: const TextStyle(color: Brand.amber, fontSize: 12)),
          ],
        ),
      );

  Widget _directionPicker(Alarm a) => Row(
        children: [
          Expanded(
              child: _choice('Everything', a.direction == Alarm.dirAll,
                  a.enabled ? () => _update((x) => x.copyWith(direction: Alarm.dirAll)) : null)),
          const SizedBox(width: 8),
          Expanded(
              child: _choice('Coming in', a.direction == Alarm.dirIn,
                  a.enabled ? () => _update((x) => x.copyWith(direction: Alarm.dirIn)) : null)),
          const SizedBox(width: 8),
          Expanded(
              child: _choice('Going out', a.direction == Alarm.dirOut,
                  a.enabled ? () => _update((x) => x.copyWith(direction: Alarm.dirOut)) : null)),
        ],
      );

  /// Hour steppers rather than a clock picker: quiet hours are whole hours in
  /// the spec's preset, and a full time picker invites 03:47 bedtimes.
  Widget _hourField(String label, Alarm a, {required bool isStart}) {
    final m = RegExp(r'^(\d{1,2}):\d{2}\s*-\s*(\d{1,2}):\d{2}$')
        .firstMatch(a.quietPreset);
    final startH = int.tryParse(m?.group(1) ?? '22') ?? 22;
    final endH = int.tryParse(m?.group(2) ?? '7') ?? 7;
    final current = isStart ? startH : endH;

    void bump(int delta) {
      final next = (current + delta + 24) % 24;
      _update((x) => x.copyWith(
          quietPreset: isStart
              ? AlarmFormat.preset(next, endH)
              : AlarmFormat.preset(startH, next)));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Brand.micro(size: 9)),
              Text(AlarmFormat.prettyPreset('${current.toString().padLeft(2, '0')}:00-00:00')
                  .split('–')
                  .first
                  .trim(),
                  style: const TextStyle(color: Brand.warm, fontSize: 14)),
            ],
          ),
          Column(
            children: [
              InkWell(
                onTap: a.enabled ? () => bump(1) : null,
                child: const Icon(Icons.keyboard_arrow_up_rounded,
                    size: 19, color: Brand.warm3),
              ),
              InkWell(
                onTap: a.enabled ? () => bump(-1) : null,
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 19, color: Brand.warm3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice(String label, bool active, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? Brand.amber.withValues(alpha: .14) : Brand.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? Brand.amber.withValues(alpha: .55) : Brand.line),
          ),
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: onTap == null
                        ? Brand.warm3
                        : (active ? Brand.amber : Brand.warm2),
                    fontSize: 12.5)),
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(text, style: Brand.micro()),
      );

  Widget _rowLabel(String text) =>
      Text(text, style: const TextStyle(color: Brand.warm2, fontSize: 13));
}
