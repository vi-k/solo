/// The listener list a controller notifies through, for a package that
/// builds a delivery of its own on top of `solo`.
///
/// Not part of `package:solo/solo.dart`: an application listens through
/// `Solo.addListener` and never holds one of these. It is reachable
/// because `flutter_solo` needs it — `SoloSelection` has listeners of its
/// own and cannot use a controller's — and because one copy of the
/// mechanics is better than two.
library;

export 'src/listeners.dart';
