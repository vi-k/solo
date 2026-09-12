/// State management for Flutter: sequential jobs over one state,
/// exclusive ownership, cooperative cancellation, and rebuilds through
/// `ValueListenable`. Re-exports `solo` — and, through it, `jobs` —
/// whole, so this is the only import an app needs.
///
/// `select` and `listen` are the exception: they are extensions on the
/// framework's own listenables, so they live next door in
/// `listenable.dart` with the subscriptions `listen` hands back, and an
/// import of their own decides whether an app takes them.
library;

export 'package:flutter/foundation.dart' show ValueListenable;
export 'package:solo/solo.dart';
export 'src/solo_listenable.dart';
export 'src/solo_selection.dart' show SoloSelection;
export 'src/solo_selector.dart';
