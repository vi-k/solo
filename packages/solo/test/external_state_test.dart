@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('an external state outside W cancels the running job at once', () {
    runSolo((solo, journal, async) {
      final job = solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());

      expect(job.isCancelled, isTrue, reason: 'marked before the body notices');
      var cancelledSeen = false;
      job.whenCancelled.then((_) => cancelledSeen = true);
      async.flushMicrotasks();
      expect(cancelledSeen, isTrue);
      expect(job.isFinished, isFalse, reason: 'body still parked on delay');

      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[job] started',
        'state: Disposed()',
        '[job] finished Cancelled(rules: is not NotDisposed)',
      ]);
      expect((job.outcome! as Cancelled).started, isTrue);
    });
  });

  test('an external state failing keepWhile cancels the running job', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<Preparing, void>(
        key: 'job',
        keepWhile: (state) => state.progress < 100,
        (ctx) async {
          await delay(100);
          ctx.check();
        },
      );
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 100));
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 100)',
        '[job] finished Cancelled(rules: keepWhile)',
      ]);
    });
  });

  test('an external state still inside W leaves the job running', () {
    runSolo(initialState: const Preparing(), (solo, journal, async) {
      solo.run<Preparing, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.emit(ctx.state.copyWith(progress: ctx.state.progress + 1));
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Preparing(progress: 10));
      async.elapse(const Duration(milliseconds: 50));
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 10)',
        'state: Preparing(progress: 11)',
        '[job] finished Done(null)',
      ]);
    });
  });

  test('own emit is trusted, the next read cancels lazily', () {
    runSolo((solo, journal, async) {
      final job = solo.run<Initial, void>(key: 'job', (ctx) async {
        ctx
          ..emit(const Preparing())
          ..check();
      });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[job] started',
        'state: Preparing(progress: 0)',
        '[job] finished Cancelled(rules: is not Initial)',
      ]);
      expect((job.outcome! as Cancelled).stackTrace, isNotNull);
    });
  });

  test('a job that emits outside W and never reads again finishes Done', () {
    runSolo((solo, journal, async) {
      solo.run<NotDisposed, void>(key: 'close', (ctx) async {
        ctx.emit(const Disposed());
      });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[close] started',
        'state: Disposed()',
        '[close] finished Done(null)',
      ]);
    });
  });

  test('stateAs narrows or cancels with rules', () {
    runSolo(initialState: const Preparing(progress: 5), (solo, journal, async) {
      solo
        ..run<NotDisposed, void>(key: 'ok', (ctx) async {
          final preparing = ctx.stateAs<Preparing>();
          ctx.emit(preparing.copyWith(progress: 6));
        })
        ..run<NotDisposed, void>(key: 'bad', (ctx) async {
          ctx.stateAs<Working>();
        });
      async.flushMicrotasks();
      expect(journal.take(), [
        '[ok] started',
        'state: Preparing(progress: 6)',
        '[ok] finished Done(null)',
        '[bad] started',
        '[bad] finished Cancelled(rules: is not Working)',
      ]);
    });
  });

  test('the same Cancelled instance is thrown and stored', () {
    runSolo((solo, journal, async) {
      Object? thrown;
      final job = solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await delay(100);
        try {
          ctx.check();
        } on Cancelled catch (e) {
          thrown = e;
          rethrow;
        }
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.elapse(const Duration(milliseconds: 50));
      expect(identical(thrown, job.outcome), isTrue);
    });
  });

  test('the rules stack trace points at externalSetState', () {
    runSolo((solo, journal, async) {
      final job = solo.run<NotDisposed, void>(key: 'job', (ctx) async {
        await delay(100);
        ctx.check();
      });
      async.elapse(const Duration(milliseconds: 50));
      solo.externalSetState(const Disposed());
      async.elapse(const Duration(milliseconds: 50));
      final trace = (job.outcome! as Cancelled).stackTrace.toString();
      expect(trace, contains('externalSetState'));
    });
  });

  test('externalSetState while idle only changes the state', () {
    runSolo((solo, journal, async) {
      solo.externalSetState(const Working());
      async.flushMicrotasks();
      expect(journal.take(), ['state: Working(a: 0, b: 0)']);
      expect(solo.state, const Working());
    });
  });
}
