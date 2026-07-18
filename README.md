# KŌINIkeyview — client

**Eyes on. Keys off.** The world's only dedicated crypto keys viewer — view-only, non-custodial, free. This app never asks for, stores, or transmits private keys or funds, and cannot make transactions.

One Flutter codebase → iOS · Android · Windows · macOS. Brand tokens live in `lib/brand.dart` (source of truth: keys.koini.io — do not restyle).

## Run it (works immediately, zero accounts — mock data built in)

```bash
flutter create . --org io.koini --project-name keyview --platforms=android,ios,macos,windows
flutter run
```

## Point it at the real backend (after `wrangler deploy` in keyview-backend)

```bash
flutter run --dart-define=KEYVIEW_API=https://keyview-api.<your-subdomain>.workers.dev
```

Project codename: KeyHole. Spec: `KeyHole_v1_Spec.docx` · Plan: `KeyHole_Build_Deploy_Plan.docx` (in the project folder).
