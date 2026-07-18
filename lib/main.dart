import 'package:flutter/material.dart';
import 'brand.dart';
import 'screens/lookup.dart';

void main() => runApp(const KeyviewApp());

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
