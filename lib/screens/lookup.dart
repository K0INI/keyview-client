import 'package:flutter/material.dart';
import '../api.dart';
import '../brand.dart';
import 'portfolio.dart';

/// First-run screen: paste any public address, see the portfolio. No sign-up wall.
class LookupScreen extends StatefulWidget {
  const LookupScreen({super.key});
  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  final _ctrl = TextEditingController();
  String? _error;

  void _go() {
    final a = _ctrl.text.trim();
    if (!KeyviewApi.isValidAddress(a)) {
      setState(() => _error = 'Enter a valid EVM (0x…), Solana, or ENS address');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PortfolioScreen(address: a)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('K', style: Brand.micro(color: Brand.warm, size: 26)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3),
                        child: KeyholeMark(size: 30),
                      ),
                      Text('INI', style: Brand.micro(color: Brand.warm, size: 26)),
                    ]),
                    const SizedBox(height: 4),
                    Text('k e y v i e w', style: Brand.micro(size: 12)),
                    const SizedBox(height: 26),
                    Text('EYES ON · KEYS OFF',
                        style: Brand.micro(color: Brand.amber)),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Watch any wallet. '),
                        TextSpan(
                            text: 'Never touch a key.',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Brand.warm)),
                      ]),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w300),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A dedicated keyviewer — check holdings countless times a day, fully watch-only.',
                      style: TextStyle(color: Brand.warm2),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _ctrl,
                      onSubmitted: (_) => _go(),
                      style: const TextStyle(color: Brand.warm),
                      decoration: InputDecoration(
                        hintText: '0x…  ·  Solana address  ·  name.eth',
                        hintStyle: const TextStyle(color: Brand.warm3),
                        errorText: _error,
                        filled: true,
                        fillColor: Brand.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Brand.line),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                          onPressed: _go, child: const Text('Watch it')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
