@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('one job emits five states and finishes with Done', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'test', (ctx) async {
        ctx
          ..emit(const Preparing())
          ..emit(const Preparing(progress: 50))
          ..emit(const Preparing(progress: 100))
          ..emit(const Working())
          ..emit(const Disposed());
      });
      expect(job.isQueued, isTrue);
      expect(journal.lines, isEmpty, reason: 'nothing runs synchronously');

      async.flushMicrotasks();

      expect(journal.take(), [
        '[test] started',
        'state: Preparing(progress: 0)',
        'state: Preparing(progress: 50)',
        'state: Preparing(progress: 100)',
        'state: Working(a: 0, b: 0)',
        'state: Disposed()',
        '[test] finished Done(null)',
      ]);
      expect(job.outcome, isA<Done<void>>());
      expect(job.isFinished, isTrue);
      expect(solo.state, const Disposed());
    });
  });

  test('jobs run one after another in queue order', () {
    runSolo((solo, journal, async) {
      solo
        ..run<Initial, void>(key: 'first', (ctx) async {
          await delay(100);
          ctx.emit(const Preparing());
        })
        ..run<Preparing, void>(key: 'second', (ctx) async {
          await delay(100);
          ctx.emit(const Working());
        });

      async.elapse(const Duration(milliseconds: 150));
      expect(journal.take(), [
        '[first] started',
        'state: Preparing(progress: 0)',
        '[first] finished Done(null)',
        '[second] started',
      ]);
      expect(solo.current?.key, 'second');
      expect(solo.queue.isEmpty, isTrue);

      async.elapse(const Duration(milliseconds: 100));
      expect(journal.take(), [
        'state: Working(a: 0, b: 0)',
        '[second] finished Done(null)',
      ]);
      expect(solo.current, isNull);
    });
  });

  test('value, done and outcome agree on a returned value', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, int>((ctx) async => 42);
      int? value;
      Outcome<int>? outcome;
      job.value.then((v) => value = v);
      job.done.then((o) => outcome = o);
      async.flushMicrotasks();

      expect(value, 42);
      expect(outcome, isA<Done<int>>());
      expect((job.outcome! as Done<int>).value, 42);
    });
  });

  test('a throwing body ends with Failed, onError and onFinish', () {
    runSolo((solo, journal, async) {
      final job = solo.run<TestState, void>(key: 'bad', (ctx) async {
        throw StateError('boom');
      });
      Object? error;
      job.value.then<void>((_) {}, onError: (Object e) => error = e);
      async.flushMicrotasks();

      expect(journal.take(), [
        '[bad] started',
        '[bad] error Bad state: boom',
        '[bad] finished Failed(Bad state: boom)',
      ]);
      expect(error, isA<StateError>());
    });
  });

  test('the stream delivers every state in order on the next microtask', () {
    runSolo((solo, journal, async) {
      final seen = <TestState>[];
      solo.stream.listen(seen.add);
      // Read inside the body, asserted outside: a failing `expect` in a job
      // body ends the job as `Failed` instead of failing the test.
      TestState? stateAfterEmit;
      List<TestState>? seenAfterEmit;
      solo.run<TestState, void>((ctx) async {
        ctx.emit(const Preparing());
        stateAfterEmit = solo.state;
        seenAfterEmit = [...seen];
        ctx.emit(const Working());
      });
      async.flushMicrotasks();
      expect(stateAfterEmit, const Preparing(), reason: 'state is fresh');
      expect(seenAfterEmit, isEmpty, reason: 'the stream is asynchronous');
      expect(seen, [const Preparing(), const Working()]);
    });
  });

  test('describe and toString show the key and the description', () {
    runSolo((solo, journal, async) {
      final plain = solo.job<TestState, void>(key: 'a', (ctx) async {});
      final described = solo.job<TestState, void>(
        key: 'b',
        describe: () => 'zoom: 2',
        (ctx) async {},
      );
      expect(plain.describe(), '');
      expect(plain.toString(), 'Job(a)');
      expect(described.toString(), 'Job(b: zoom: 2)');
      expect(solo.job<TestState, void>((ctx) async {}).toString(), 'Job(null)');
    });
  });

  test('a finished root job is no longer current when onFinish runs', () {
    fakeAsync((async) {
      final solo = _CurrentProbe()
        ..run<TestState, void>(key: 'probe', (ctx) async {});
      async.flushMicrotasks();

      expect(solo.idleInOnFinish, [true]);
      solo.close();
      async.flushTimers();
    });
  });
}

/// Records whether the controller was already idle when `onFinish` ran.
final class _CurrentProbe extends Solo<TestState> {
  _CurrentProbe() : super(const Initial());

  final idleInOnFinish = <bool>[];

  @override
  void onFinish(Job<Object?> job) => idleInOnFinish.add(current == null);
}
