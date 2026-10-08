// Where a cancellation by the rules says it came from.
@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// The change the rule turns down, made from a frame with a name of its
/// own so the trace can be searched for it.
void _breakTheRule(TestSolo solo) => solo.externalSetState(const Working());

void main() {
  test('a change that cancels a running job is in its trace', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(
        key: 'job',
        keepWhile: (state) => state is! Working,
        (ctx) => pause(ctx, 100),
      );
      async.flushMicrotasks();
      _breakTheRule(solo);
      async.flushTimers();

      final cancelled = job.outcome! as Cancelled;
      expect(cancelled.reason, isA<RulesCancelReason>());
      final trace = '${cancelled.stackTrace}';
      expect(trace, contains('_breakTheRule'));
      expect(
        trace,
        contains('_reevaluate'),
        reason: 'taken where the rule was checked, inside the change',
      );
    });
  });

  test('a rule broken with no change is traced to the checkpoint', () {
    runSolo((solo, journal, async) {
      var allowed = true;
      final job = solo.run<TestState, void>(
        key: 'job',
        keepWhile: (state) => allowed,
        (ctx) async {
          await delay(10);
          ctx.check();
        },
      );
      async.flushMicrotasks();
      allowed = false;
      async.flushTimers();

      final cancelled = job.outcome! as Cancelled;
      expect(cancelled.description, 'keepWhile');
      expect('${cancelled.stackTrace}', contains('_checkedState'));
    });
  });
}
