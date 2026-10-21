import 'dart:async';

import 'package:flutter/material.dart';
import 'auth.dart';
import 'brand.dart';
import 'funnel.dart';
import 'money.dart';
import 'push_platform.dart';
import 'desktop_notifier.dart';
import 'si.dart';
import 'screens/lookup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local read only — a stored session appears instantly, stale tokens
  // refresh in the background. Never blocks first paint on the network.
  await KeyviewAuth.restore();
  // Aggregate open counter — the core habit metric (spec §18).
  Funnel.track(Funnel.evAppOpen);
  // Push registration is fire-and-forget: it must never delay first paint, and
  // it no-ops entirely on desktop or when Firebase isn't configured.
  // Display currency. Local disk only — restores the saved choice AND the last
  // known rate table, so first paint is already in the chosen currency even if
  // the network is slow or /v1/fx is unreachable. The live refresh is fired
  // off inside init() and never blocks first paint.
  await Money.init();
  unawaited(PushPlatform.start());
  // SI entitlement + verified phone. Same contract as push: fire-and-forget,
  // fail-soft, never blocks first paint; no-ops where purchases don't exist.
  unawaited(SiService.start());
  // Desktop banners poll the feed while the app runs (spec §9). Same rule:
  // fire-and-forget, fail-soft, mobile/web no-op.
  unawaited(DesktopNotifier.start());
  runApp(const KeyviewApp());
}

class KeyviewApp extends StatelessWidget {
  const KeyviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KŌINIkeyview — Eyes on. Keys off.',
        debugShowCheckedModeBanner: false,
        theme: Brand.theme(),
        home: const LookupScreen(),
      );
}
