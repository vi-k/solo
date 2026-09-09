@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a replacement cancelled by the old job never occupies its key', () {
    runSolo((solo, journal, async) {
      solo.run<TestState, void>((ctx) => pause(ctx, 50));
      async.flushMicrotasks();
      final old = solo.run<TestState, void>(key: 'same', (ctx) async {});
      final incoming = solo.job<TestState, void>(key: 'same', (ctx) async {});
      old.whenCancelled((_) => incoming.cancel().ignore());
      solo.add(incoming, policy: Policy.replace);
      expect(incoming.isFinished, isTrue);
      expect(incoming.isQueued, isFalse);
      var ran = false;
      final retry = solo.run<TestState, void>(
        key: 'same',
        policy: Policy.droppable,
        (ctx) async => ran = true,
      );
      async.flushTimers();
      expect(ran, isTrue);
      expect(retry.outcome, isA<Done<void>>());
    });
  });

  test('a listener receives the domain reason of a rule cancellation', () {
    runSolo((solo, journal, async) {
      final seen = <Cancelled>[];
      final job = solo.run<NotDisposed, void>(
        (ctx) => ctx.wait(() => delay(50)),
      )..whenCancelled(seen.add);
      async.flushMicrotasks();
      solo.externalSetState(const Disposed());
      expect(seen.single.reason, SoloCancelReason.rules);
      expect(seen.single.description, 'is not NotDisposed');
      expect(seen.single.started, isTrue);
      async.flushTimers();
      expect(job.outcome, same(seen.single));
    });
  });

  test('closing delivers the drop reason before close returns', () {
    runSolo((solo, journal, async) {
      final seen = <Cancelled>[];
      solo.run<TestState, void>((ctx) => pause(ctx, 50));
      async.flushMicrotasks();
      final queued = solo.run<TestState, void>((ctx) async {})
        ..whenCancelled(seen.add);
      solo.close().ignore();
      expect(seen.single.reason, SoloCancelReason.closed);
      expect(seen.single.started, isFalse);
      expect(queued.isQueued, isFalse);
      expect(queued.outcome, same(seen.single));
    });
  });
}
