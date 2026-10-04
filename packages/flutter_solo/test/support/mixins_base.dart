// The base of "A base class without Flutter" in `doc/mixins.md`, as "A
// report under another name" writes it. `test/mixins_rakes_test.dart` runs
// it.
//
// The page puts the class in a package without Flutter, under imports of
// `meta` and `solo`, and so does this file: the test holds its imports to
// the ones below, with no Flutter among them. `flutter_solo` itself takes
// `@protected` from Flutter, and `meta` is a dev dependency of the package
// for the sake of this file and of `mixins_base_first.dart`.

// A package of your own, without Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

import 'mixins_log.dart';

abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  @protected
  void reportListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}
