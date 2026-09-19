// Where a cancellation by the rules says it came from, with the record of
// every change on and off.
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

/// Runs [body] with [Solo.traceStateChanges] set to [on], and puts the
/// default back after.
void _withTrace(bool on, void Function() body) {
  final before = Solo.traceStateChanges;
  Solo.traceStateChanges = on;
  try {
    body();
  } finally {
    Solo.traceStateChanges = before;
  }
}

void main() {
  test('the record is on where assertions are', () {
    expect(Solo.traceStateChanges, isTrue, reason: 'tests run with asserts');
  });

  for (final on in [true, false]) {
    test(
        'a change that cancels a running job is in its trace, '
        'record ${on ? 'on' : 'off'}', () {
      _withTrace(on, () {
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
            on ? isNot(contains('_reevaluate')) : contains('_reevaluate'),
            reason: on
                ? 'the record of the change itself'
                : 'taken where the rule was checked, inside the change',
          );
        });
      });
    });
  }

  test('a rule broken with no change is traced to the checkpoint', () {
    _withTrace(false, () {
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
  });
}
