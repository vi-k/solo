@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

// `ctx.start` of `async_job` works in `solo` with no code of its own: the
// rules of the controller come through `startChild`, as they do for
// `ctx.run`, and the outcome of the child stays with whoever holds it.

void main() {
  test(
      'a child the rules turn away ends Cancelled(rules), and nothing is '
      'said of it', () {
    runSolo((solo, journal, async) {
      late SoloJob<void> child;
      var returned = false;
      solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
        child = solo.job<Working, void>(key: 'child', (ctx) async {});
        ctx.start(child);
        returned = true;
      });
      async.flushTimers();
      expect(returned, isTrue);
      expect('${child.outcome}', 'Cancelled(rules: is not Working)');
      expect(journal.take(), [
        '[parent] started',
        '> [child] dropped Cancelled(rules: is not Working)',
        '[parent] finished Done(null)',
      ]);
    });
  });

  test('a canStart that throws throws from start, and the child ends Failed',
      () {
    runSolo((solo, journal, async) {
      late SoloJob<void> child;
      Object? thrown;
      solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
        child = solo.job<TestState, void>(
          key: 'child',
          canStart: (state) => throw StateError('rule broke'),
          (ctx) async {},
        );
        try {
          ctx.start(child);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushTimers();
      expect('$thrown', 'Bad state: rule broke');
      expect('${child.outcome}', 'Failed(Bad state: rule broke)');
      final lines = journal.take();
      expect(lines, contains('[parent] finished Done(null)'));
      expect(lines.where((line) => line.contains('unanswered')), isEmpty);
    });
  });

  test(
      'a failure of the child goes to the unanswered handler, and the '
      'parent ends Done', () {
    runSolo((solo, journal, async) {
      solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
        ctx.start(
          solo.job<TestState, void>(key: 'child', (ctx) async {
            throw StateError('child failed');
          }),
        );
      });
      async.flushTimers();
      final lines = journal.take();
      expect(
        lines,
        containsAllInOrder([
          '> [child] finished Failed(Bad state: child failed)',
          '[parent] finished Done(null)',
        ]),
      );
      expect(lines, contains('> [child] unanswered Bad state: child failed'));
    });
  });

  test('a job of another controller is refused with an ArgumentError', () {
    runSolo((solo, journal, async) {
      final other = TestSolo();
      Object? thrown;
      solo.enqueue<TestState, void>(key: 'parent', (ctx) async {
        try {
          ctx.start(other.job<TestState, void>(key: 'theirs', (ctx) async {}));
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushTimers();
      other.close().ignore();
      async.flushTimers();
      expect(
        '$thrown',
        'Invalid argument (job): was not created by this Solo (make it '
            'with job(...) or ctx.child of this controller): '
            '"Job(theirs)"',
      );
      journal.take();
    });
  });
}
