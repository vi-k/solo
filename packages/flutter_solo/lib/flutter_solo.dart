/// State management for Flutter: sequential jobs over one state,
/// exclusive ownership, cooperative cancellation, and rebuilds through
/// `ValueListenable`. Re-exports `solo` — and, through it, `jobs` —
/// whole, so this is the only import an app needs.
library;

export 'package:flutter/foundation.dart' show ValueListenable;
export 'package:solo/solo.dart';
export 'src/solo_listenable.dart';
