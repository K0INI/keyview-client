import 'dart:async';

import 'package:flutter/material.dart';
import 'auth.dart';
import 'brand.dart';
import 'funnel.dart';
import 'push_platform.dart';
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
  unawaited(PushPlatform.start());
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
