/// Whether [reference] is gone once the collector has had a fair chance.
///
/// The same helper as `packages/async_job/test/support/reachability.dart`,
/// copied because a package does not export its tests.
///
/// A Dart VM cannot be asked for a collection, so this asks with garbage:
/// every round allocates and drops a few megabytes, and the loop stops the
/// moment the target goes. A target still standing after all the rounds is
/// one something still points at -- when the link is there the loop runs
/// them all and the answer is the same every time.
///
/// A microtask between the rounds, because the loop would otherwise hold
/// the turn: a job whose handle is not in the test finishes on a microtask
/// of its own, and until it does it is still holding everything.
Future<bool> collected(
  WeakReference<Object> reference, {
  int rounds = 40,
}) async {
  var sink = 0;
  for (var round = 0; round < rounds; round++) {
    if (reference.target == null) {
      return true;
    }
    await Future<void>.microtask(() {});
    for (var i = 0; i < 20; i++) {
      sink ^= List<int>.filled(100000, i).length;
    }
  }
  return sink != -1 && reference.target == null;
}
