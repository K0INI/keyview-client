import 'package:flutter/material.dart';
import 'auth.dart';
import 'brand.dart';
import 'screens/lookup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local read only — a stored session appears instantly, stale tokens
  // refresh in the background. Never blocks first paint on the network.
  await KeyviewAuth.restore();
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
