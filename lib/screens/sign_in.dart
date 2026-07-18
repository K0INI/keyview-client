import 'package:flutter/material.dart';
import '../auth.dart';
import '../brand.dart';

/// Two-step sign-in: email → 6-digit code. Pops with `true` when signed in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@') || email.length < 5) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await KeyviewAuth.sendCode(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _codeSent = true;
    });
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await KeyviewAuth.verifyCode(_email.text.trim(), _code.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Brand.warm3),
        errorText: _error,
        filled: true,
        fillColor: Brand.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Brand.line),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('SIGN IN', style: Brand.micro())),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EYES ON · KEYS OFF',
                      style: Brand.micro(color: Brand.amber)),
                  const SizedBox(height: 10),
                  Text(
                    _codeSent
                        ? 'Enter the 6-digit code we emailed you.'
                        : 'An account only syncs watchlists and alarms.\nNo keys. No custody. Ever.',
                    style: const TextStyle(color: Brand.warm2),
                  ),
                  const SizedBox(height: 20),
                  if (!_codeSent) ...[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: Brand.warm),
                      decoration: _dec('you@example.com'),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _send,
                        child: Text(_busy ? 'Sending…' : 'Email me a code'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      maxLength: 6,
                      onSubmitted: (_) => _verify(),
                      style: const TextStyle(
                          color: Brand.warm, letterSpacing: 8, fontSize: 20),
                      decoration: _dec('123456'),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _verify,
                        child: Text(_busy ? 'Checking…' : 'Sign in'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _send,
                      child: Text('Resend code',
                          style: Brand.micro(color: Brand.warm3, size: 10)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
