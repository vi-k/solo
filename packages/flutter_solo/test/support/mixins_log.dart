// The log of the app in "A base class without Flutter" of `doc/mixins.md`.
// The page names `AppLog` and shows no more of it: this one keeps what it
// was handed. It imports nothing, so a base that reports to it stays
// without Flutter.

// The page calls `AppLog.error` statically, so the fake is all statics.
// ignore: avoid_classes_with_only_static_members
abstract final class AppLog {
  /// Every error handed to [error], in order.
  static final errors = <Object>[];

  /// Keeps [error].
  static void error(Object error, StackTrace stackTrace) => errors.add(error);
}
