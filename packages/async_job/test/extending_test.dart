// The protected surface an engine of a domain stands on.
//
// Four of its members are held by `solo` alone and by nothing in here, so
// a change to their contract would leave this package green and redden the
// neighbour: `createEachJob`, `whenDone`, `inUncancellableSection` and
// `heldCancel`. Each of them is exercised below by a small engine of its
// own, the way `solo` does it. So is the way an engine answers for an
// error nobody answered for: through an observer of its own on every job,
// which is how `solo` reaches `Solo.onUnanswered`.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// An engine that has its own answer for an error nobody answered for: it
/// puts an observer of its own on every job, the way `solo` does, and
/// answers there.
final class AnsweringJob<T> extends JobBase<T> {
  factory AnsweringJob(
    Future<T> Function(JobContext ctx) body, {
    Object? key,
    bool cancellable = true,
  }) {
    final answer = EngineAnswer();
    return AnsweringJob._(
      body,
      answer,
      key: key,
      cancellable: cancellable,
      observer: answer,
    );
  }

  AnsweringJob._(
    this._body,
    this._answer, {
    super.key,
    super.cancellable,
    super.observer,
  });

  final Future<T> Function(JobContext ctx) _body;
  final EngineAnswer _answer;

  /// What reached the engine's answer instead of the zone.
  List<Object> get answered => _answer.answered;

  @override
  JobContextBase createContext() => DomainContext(this);

  @override
  Future<T> execute(covariant DomainContext ctx) => _body(ctx);
}

final class DomainContext extends JobContextBase {
  DomainContext(super.owner);
}

/// The observer of [AnsweringJob]: it hears nothing and answers for
/// everything nobody else answered for.
final class EngineAnswer extends JobObserver {
  final answered = <Object>[];

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      answered.add(error);
}

/// An engine that waits for a job the way it waits for a child: without
/// observing, so a failure nobody looked at still goes to the zone.
final class WaitingJob<T> extends JobBase<T> {
  WaitingJob(this._body, {super.key});

  final Future<T> Function(JobContext ctx) _body;

  Future<void> get waited => whenDone;

  void launch() => start();

  @override
  JobContextBase createContext() => DomainContext(this);

  @override
  Future<T> execute(covariant DomainContext ctx) => _body(ctx);
}

/// An engine that wants to say why it is still waiting.
final class SectionJob<T> extends JobBase<T> {
  SectionJob(this._body, {super.key});

  final Future<T> Function(JobContext ctx) _body;

  bool get inSection => inUncancellableSection;

  Cancelled? get held => heldCancel;

  void launch() => start();

  @override
  JobContextBase createContext() => DomainContext(this);

  @override
  Future<T> execute(covariant DomainContext ctx) => _body(ctx);
}

/// An engine that restricts child ownership: the children of `each` are
/// jobs of its own making.
final class EachJob<T> extends JobBase<T> {
  EachJob(this._body, {super.key});

  final Future<T> Function(JobContext ctx) _body;

  void launch() => start();

  @override
  JobContextBase createContext() => EachContext(this);

  @override
  Future<T> execute(covariant EachContext ctx) => _body(ctx);
}

final class EachContext extends JobContextBase {
  EachContext(super.owner);

  static final made = <Job<void>>[];

  @override
  Job<void> createEachJob(Future<void> Function(JobContext ctx) body) {
    final child = Job.deferred<void>(body, describe: () => 'a child of mine');
    made.add(child);
    return child;
  }
}

void main() {
  test("the engine's observer answers for the failure a group did not throw",
      () {
    fakeAsync((async) {
      final first = AnsweringJob<int>(key: 'a', (ctx) async {
        await ctx.wait(() => delay(10));
        throw StateError('first');
      });
      // Refuses the stop the group asks for, runs on and fails on its own:
      // a diagnosis of its own, which the caller never sees, because the
      // group throws the first failure and only that one.
      final second = AnsweringJob<int>(
        key: 'b',
        cancellable: false,
        (ctx) async {
          await ctx.wait(() => delay(20));
          throw StateError('second');
        },
      );
      Object? thrown;
      Job<void>((ctx) async {
        try {
          await ctx.runAll([first, second]);
        } on Object catch (error) {
          thrown = error;
        }
      }).ignore();
      async.flushTimers();
      expect('$thrown', 'Bad state: first');
      expect(first.answered, isEmpty, reason: 'this one reached the caller');
      expect(
        second.answered.map((error) => '$error').toList(),
        ['Bad state: second'],
        reason: 'and this one reached the answer of the engine, which is '
            'the whole reason the engine puts an observer of its own on '
            'every job',
      );
    });
  });

  test('without an answer of its own it goes to the zone', () {
    final caught = <Object>[];
    Object? thrown;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final second = Job.deferred<int>(
            key: 'b',
            cancellable: false,
            (ctx) async {
              await ctx.wait(() => delay(20));
              throw StateError('second');
            },
          );
          Job<void>((ctx) async {
            try {
              await ctx.runAll([
                Job.deferred<int>(key: 'a', (ctx) async {
                  await ctx.wait(() => delay(10));
                  throw StateError('first');
                }),
                second,
              ]);
            } on Object catch (error) {
              thrown = error;
            }
          }).ignore();
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect('$thrown', 'Bad state: first');
    expect(caught.map((error) => '$error').toList(), ['Bad state: second']);
  });

  test('createEachJob is where the children of each come from', () {
    fakeAsync((async) {
      EachContext.made.clear();
      final seen = <int>[];
      final controller = StreamController<int>();
      late Job<void> subscription;
      final job = EachJob<void>((ctx) async {
        subscription = ctx.each(controller.stream, (ctx, event) {
          seen.add(event);
        });
        await ctx.wait(() => delay(50));
      })
        ..ignore()
        ..launch();
      async.flushMicrotasks();
      controller.add(1);
      async.flushMicrotasks();
      // Closed, or the subscription child never ends and the job waits for
      // it for ever -- which is the point of `each` and not of this test.
      unawaited(controller.close());
      async.elapse(const Duration(milliseconds: 60));
      expect(
        EachContext.made.map((child) => child.describe()).toList(),
        ['a child of mine'],
        reason: 'the engine restricts child ownership, and the factory is '
            'the only way it can',
      );
      expect(identical(subscription, EachContext.made.single), isTrue);
      expect(seen, [1]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('whenDone waits without observing the failure', () {
    final caught = <Object>[];
    var waited = false;
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = WaitingJob<int>((ctx) async => throw StateError('boom'))
            ..launch();
          job.waited.then((_) => waited = true).ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(waited, isTrue);
    expect(
      caught.map((error) => '$error').toList(),
      ['Bad state: boom'],
      reason: 'the waiting of an engine is not observation, so a failure '
          'nobody looked at still goes to the zone',
    );
  });

  test('done, unlike whenDone, is observation', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          final job = WaitingJob<int>((ctx) async => throw StateError('boom'))
            ..launch();
          job.done.ignore();
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty);
  });

  test('inUncancellableSection is open while the section is', () {
    fakeAsync((async) {
      final inside = <bool>[];
      late SectionJob<void> job;
      job = SectionJob<void>((ctx) async {
        inside.add(job.inSection);
        await ctx.uncancellable(() async {
          inside.add(job.inSection);
          await delay(10);
        });
        inside.add(job.inSection);
      });
      job.launch();
      async.flushTimers();
      expect(
        inside,
        [false, true, false],
        reason: 'an engine waiting for this job says why, and an open '
            'section is one of the answers',
      );
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('heldCancel names the cancellation a section holds, and no other', () {
    fakeAsync((async) {
      final seen = <String>[];
      late SectionJob<void> job;
      job = SectionJob<void>((ctx) async {
        await ctx.uncancellable(() async {
          await delay(10);
          seen.add('asked nothing: ${job.held}');
          await delay(10);
          seen.add('asked: ${job.held}');
          await delay(10);
        });
      });
      job.launch();
      async.elapse(const Duration(milliseconds: 15));
      unawaited(job.cancel());
      async.elapse(const Duration(milliseconds: 10));
      seen.add('let through: ${job.held}');
      async.flushTimers();

      expect(seen, [
        'asked nothing: null',
        'asked: Cancelled(manual)',
        'let through: Cancelled(manual)',
      ]);
      expect(job.held, isNull, reason: 'the section closed and let it go');
      expect(job.outcome, isA<Cancelled>());
    });
  });
}
