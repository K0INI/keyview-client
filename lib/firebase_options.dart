// Firebase configuration as Dart constants — the FlutterFire
// "DefaultFirebaseOptions" pattern, assembled from the same Firebase-console
// values as firebase/google-services.json and firebase/GoogleService-Info.plist.
//
// Why Dart options instead of the native files:
//  - iOS: a plist dropped into ios/Runner/ is NOT bundled unless it is also
//    added to the Runner target's resources in Xcode — a silent, easy-to-miss
//    manual step. Dart options remove that failure mode entirely.
//  - Android: the google-services Gradle plugin exists only to turn the JSON
//    into build-time resources, and `flutter create` does not add it. With
//    Dart options it is not needed at all.
//
// None of these values are secrets: Google ships them inside every app binary.
// Access control lives in Firebase/Google Cloud, not in these strings.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('No Firebase web app is configured for keyview.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        // Desktop uses OS notifiers, not FCM (spec §9); PushPlatform never
        // calls into Firebase there.
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBtJCYreEwrwz1eVWIwCuPXIKFxNRwBrfQ',
    appId: '1:292723856032:android:378b8b9138c25fec3a2fc5',
    messagingSenderId: '292723856032',
    projectId: 'koinikeyview',
    storageBucket: 'koinikeyview.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA7Aave9vdbDC0_C19ut6RGXoIqjMD9HxQ',
    appId: '1:292723856032:ios:96a4175e7eebb1803a2fc5',
    messagingSenderId: '292723856032',
    projectId: 'koinikeyview',
    storageBucket: 'koinikeyview.firebasestorage.app',
    iosBundleId: 'io.koini.keyview',
  );
}
