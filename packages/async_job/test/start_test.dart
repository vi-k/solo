@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/probe_job.dart';

// `ctx.start` starts a child and leaves its outcome to whoever holds it: a
// failure goes the way a failure nobody observed goes, a cancellation goes
// nowhere, and the parent ends as if the child were not there.

/// Answers for every failure it is asked about and keeps the list.
final class Answers extends JobObserver with JobAnswerer {
  final answered = <String>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add('$job: $error');
}

/// What reached the zone while [body] and the fake time ran.
List<String> zoneOf(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(() => body(async), (error, _) => errors.add('$error'));
    async.flushTimers();
  });
  return errors;
}

void main() {
  test('starts the child at once, and the parent waits for it', () {
    fakeAsync((async) {
      final child = Job.deferred<int>(key: 'child', (ctx) async {
        await delay(10);
        return 1;
      });
      var running = false;
      final parent = Job<void>(key: 'parent', (ctx) async {
        ctx.start(child);
        running = child.isRunning;
      });
      async.flushMicrotasks();
      expect(running, isTrue, reason: 'started synchronously');
      expect(parent.isFinished, isFalse, reason: 'waits for its child');
      async.elapse(const Duration(milliseconds: 10));
      expect('${child.outcome}', 'Done(1)');
      expect('${parent.outcome}', 'Done(null)');
    });
  });

  test("the parent's cancellation cascades onto the child, and the child's "
      'cancellation goes nowhere', () {
    late DeferredJob<void> child;
    late Job<void> parent;
    final answers = Answers();
    final errors = zoneOf((async) {
      child = Job.deferred<void>(
        key: 'child',
        (ctx) => ctx.pause(const Duration(seconds: 1)),
      );
      parent = Job<void>(key: 'parent', observer: answers, (ctx) async {
        ctx.start(child);
      });
      async.flushMicrotasks();
      parent.cancel().ignore();
    });
    expect('${parent.outcome}', 'Cancelled(manual)');
    expect('${child.outcome}', 'Cancelled(parent)');
    expect(answers.answered, isEmpty);
    expect(errors, isEmpty);
  });

  test('a failure of the child goes to the answerer it inherits, and the '
      'parent ends Done', () {
    late DeferredJob<void> child;
    late Job<void> parent;
    final answers = Answers();
    final errors = zoneOf((async) {
      child = Job.deferred<void>(key: 'child', (ctx) async {
        await delay(5);
        throw StateError('child failed');
      });
      parent = Job<void>(key: 'parent', observer: answers, (ctx) async {
        ctx.start(child);
      });
    });
    expect(answers.answered, ['Job(child): Bad state: child failed']);
    expect('${parent.outcome}', 'Done(null)');
    expect('${child.outcome}', 'Failed(Bad state: child failed)');
    expect(errors, isEmpty);
  });

  test('with no answerer, a failure of the child reaches the zone', () {
    final errors = zoneOf((async) {
      Job<void>((ctx) async {
        ctx.start(
          Job.deferred<void>((ctx) async => throw StateError('child failed')),
        );
      });
    });
    expect(errors, ['Bad state: child failed']);
  });

  test('ignoreFailure on the child keeps its failure quiet', () {
    final answers = Answers();
    final errors = zoneOf((async) {
      final child = Job.deferred<void>(
        (ctx) async => throw StateError('child failed'),
      )..ignoreFailure();
      Job<void>(observer: answers, (ctx) async => ctx.start(child));
    });
    expect(answers.answered, isEmpty);
    expect(errors, isEmpty);
  });

  test('a job that has started is refused with a StateError', () {
    fakeAsync((async) {
      Object? thrown;
      final child = Job.deferred<void>((ctx) async {});
      Job<void>((ctx) async {
        ctx.start(child);
        try {
          ctx.start(child);
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.flushMicrotasks();
      expect(thrown, isA<StateError>());
    });
  });

  test('a call after the body is refused with a StateError', () {
    fakeAsync((async) {
      late JobContext saved;
      Job<void>((ctx) async => saved = ctx);
      async.flushMicrotasks();
      final child = Job.deferred<void>((ctx) async {});
      expect(() => saved.start(child), throwsStateError);
      expect(child.isRunning || child.isFinished, isFalse, reason: 'untouched');
    });
  });

  test('a call from unattended work is refused with a StateError', () {
    final errors = zoneOf((async) {
      Job<void>((ctx) async {
        ctx.unattended(() => ctx.start(Job.deferred<void>((ctx) async {})));
      });
    });
    expect(errors, [contains('inside unattended work')]);
  });

  test(
    'a parent cancelled already throws its Cancelled and drops the child',
    () {
      fakeAsync((async) {
        Object? thrown;
        final child = Job.deferred<void>(key: 'child', (ctx) async {});
        final parent = Job<void>((ctx) async {
          await ctx.uncancellable(() => delay(5));
          try {
            ctx.start(child);
          } on Object catch (error) {
            thrown = error;
            rethrow;
          }
        });
        async.flushMicrotasks();
        parent.cancel().ignore();
        async.flushTimers();
        expect(thrown, isA<Cancelled>());
        expect('${child.outcome}', 'Cancelled(parent)');
      });
    },
  );

  test('a rule of the domain that throws ends the child Failed and throws '
      'from start', () {
    late DeferredJob<void> child;
    Object? thrown;
    final answers = Answers();
    final errors = zoneOf((async) {
      child = Job.deferred<void>(key: 'child', (ctx) async {});
      ThrowingRulesJob<void>(observer: answers, (ctx) async {
        try {
          ctx.start(child);
        } on Object catch (error) {
          thrown = error;
        }
      }).launch();
    });
    expect('$thrown', 'Bad state: rule failed');
    expect('${child.outcome}', 'Failed(Bad state: rule failed)');
    expect(answers.answered, isEmpty, reason: 'the caller has the error');
    expect(errors, isEmpty);
  });
}
