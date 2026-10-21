// What stands between a test of `doc/testing.md` and the runner.
//
// The code of the page is tests. In the files that hold it `test` is the
// function below, not the one of `package:test`: it keeps the name and the
// body it was given instead of handing them to the runner, and
// `testing_rakes_test` decides how each one runs — as a test of the suite,
// under the name the page gives it, or as the body of a test case of its
// own, where a test that is meant to fail can fail and be looked at.
import 'dart:async';

/// A test of the page: what its `test(name, body)` was given.
typedef PageTest = ({String name, FutureOr<void> Function() body});

/// Stands in for `test` of `package:test` in the files of the page's code.
PageTest test(String name, FutureOr<void> Function() body) =>
    (name: name, body: body);
