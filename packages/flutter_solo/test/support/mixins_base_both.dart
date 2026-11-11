// The base of "A base for both kinds" in `doc/mixins.md`: a mixin on
// `SoloController`, the base of `Solo` and `SoloLanes`.
// `test/mixins_rakes_test.dart` runs it.
//
// The page puts the mixin in a package without Flutter, under imports of
// `meta` and `solo`, and so does this file: the test holds its imports to
// the ones below, with no Flutter among them.

// A package of your own, without Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

import 'mixins_log.dart';

mixin AppController<S extends Object> on SoloController<S> {
  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);
}
