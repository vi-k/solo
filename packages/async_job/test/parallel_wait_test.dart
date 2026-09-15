@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'support/error_observer.dart';
import 'support/probe_job.dart';

typedef _ListEnvelope = ParallelWaitError<List<Object?>, List<AsyncError?>>;

_ListEnvelope _listEnvelope(List<AsyncError?> errors) =>
    ParallelWaitError<List<Object?>, List<AsyncError?>>(
      List<Object?>.filled(errors.length, null),
      errors,
    );

ParallelWaitError<Object?, Object?> _recordEnvelope(Object errors) =>
    ParallelWaitError<Object?, Object?>(null, errors);

Object _recordErrors(List<Object?> values) => switch (values.length) {
      2 => (values[0], values[1]),
      3 => (values[0], values[1], values[2]),
      4 => (values[0], values[1], values[2], values[3]),
      5 => (values[0], values[1], values[2], values[3], values[4]),
      6 => (
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
        ),
      7 => (
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
          values[6],
        ),
      8 => (
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
          values[6],
          values[7],
        ),
      9 => (
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
          values[6],
          values[7],
          values[8],
        ),
      _ => throw ArgumentError.value(values.length, 'length'),
    };

Future<Outcome<void>> _run(Future<void> Function() body) async {
  final job = Job<void>((ctx) async => body());
  return job.done;
}

void _cancel(ProbeJob<void> job, Cancelled cancellation) =>
    job.cancelBy(cancellation);

void main() {
  group('clean envelopes', () {
    test('a list envelope gives the body cancellation', () async {
      const cancelled = Cancelled('why');
      final branchTrace = StackTrace.current;
      var notifications = 0;
      final job = Job<void>((ctx) async {
        await [
          Future<void>.value(),
          Future<void>.error(cancelled, branchTrace),
        ].wait;
      })
        ..whenCancelled((_) => notifications++);

      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      final result = outcome as Cancelled;
      expect(result.reason, isA<HandlerCancelReason>());
      expect(result.description, 'why');
      expect(result.stackTrace, same(branchTrace));
      expect(result.reason, isA<HandlerCancelReason>());
      expect(notifications, 1);
    });

    test('a record envelope gives the body cancellation', () async {
      const cancelled = Cancelled('why');
      final branchTrace = StackTrace.current;
      final outcome = await _run(() async {
        await (
          Future<void>.value(),
          Future<void>.error(cancelled, branchTrace),
        ).wait;
      });

      expect(outcome, isA<Cancelled>());
      final result = outcome as Cancelled;
      expect(result.description, 'why');
      expect(result.stackTrace, same(branchTrace));
      expect(result.reason, isA<HandlerCancelReason>());
    });

    test('a child cancellation keeps its child description and cascades',
        () async {
      const childThrown = Cancelled('child stopped');
      late Job<void> child;
      late Job<void> neighbor;
      late Job<void> third;
      var thirdWasRunning = false;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((childContext) async {
          throw childThrown;
        });
        neighbor = Job.deferred<void>((childContext) async {});
        final thirdGate = Completer<void>();
        third = Job.deferred<void>((childContext) async {
          await childContext.wait(() => thirdGate.future);
        });
        ctx.run(child).ignore();
        ctx.run(neighbor).ignore();
        ctx.run(third).ignore();
        await child.done;
        await neighbor.done;
        thirdWasRunning = third.isRunning;
        final childCancelled = child.outcome! as Cancelled;
        await [
          Future<void>.value(),
          Future<void>.error(childCancelled, childCancelled.stackTrace),
        ].wait;
      });

      final outcome = await parent.done;
      expect(thirdWasRunning, isTrue);
      expect(neighbor.outcome, isA<Done<void>>());
      expect(third.outcome, isA<Cancelled>());
      expect(outcome, isA<Cancelled>());
      final result = outcome as Cancelled;
      expect(result.description, contains('child'));
      expect((result.reason as HandlerCancelReason).cause, same(child.outcome));
      expect(
        (third.outcome! as Cancelled).reason,
        isA<ParentCancelReason>(),
      );
    });

    test('a list envelope nested in a list keeps the branch trace', () async {
      const cancelled = Cancelled('nested');
      final branchTrace = StackTrace.current;
      final inner = _listEnvelope([AsyncError(cancelled, branchTrace)]);
      final outer = _listEnvelope([AsyncError(inner, StackTrace.current)]);

      final outcome = await _run(() async => throw outer);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'nested');
      expect(outcome.stackTrace, same(branchTrace));
    });

    test('a record envelope nested in a record keeps the branch trace',
        () async {
      const cancelled = Cancelled('nested');
      final branchTrace = StackTrace.current;
      final inner = _recordEnvelope(
        (AsyncError(cancelled, branchTrace), null),
      );
      final outer = _recordEnvelope(
        (AsyncError(inner, StackTrace.current), null),
      );

      final outcome = await _run(() async => throw outer);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'nested');
      expect(outcome.stackTrace, same(branchTrace));
    });

    test('an unobserved clean envelope stays out of the zone', () async {
      final zoneErrors = <Object>[];
      const cancelled = Cancelled('quiet');
      final trace = StackTrace.current;
      await runZonedGuarded(
        () async {
          final job = Job<void>(
            (ctx) async => throw _listEnvelope([AsyncError(cancelled, trace)]),
          );
          await Future<void>.delayed(Duration.zero);
          expect(job.outcome, isA<Cancelled>());
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      expect(zoneErrors, isEmpty);
    });
  });

  group('forms and traversal', () {
    test('all tuple arities and positions are parsed', () async {
      for (var arity = 2; arity <= 9; arity++) {
        for (var position = 0; position < arity; position++) {
          final cancelled = Cancelled('tuple $arity/$position');
          final values = List<Object?>.filled(arity, null);
          values[position] = AsyncError(cancelled, StackTrace.current);
          final outcome = await _run(
            () async => throw _recordEnvelope(_recordErrors(values)),
          );
          expect(
            outcome,
            isA<Cancelled>(),
            reason: 'tuple position $arity/$position',
          );
          expect(
            (outcome as Cancelled).description,
            'tuple $arity/$position',
          );
        }
      }
    });

    test('an empty envelope remains a failure', () async {
      final envelope = _listEnvelope([]);
      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(envelope));
    });

    test('an all-null envelope remains a failure', () async {
      final envelope = _listEnvelope([null, null]);
      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(envelope));
    });

    test('an unknown nested form beside cancellation remains a failure',
        () async {
      const cancelled = Cancelled('known');
      final unknown = _recordEnvelope(Object());
      final envelope = _listEnvelope([
        AsyncError(cancelled, StackTrace.current),
        AsyncError(unknown, StackTrace.current),
      ]);
      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(envelope));
    });

    test('a cast list read failure still finishes as a failure', () async {
      const cancelled = Cancelled('first');
      final source = <Object?>[
        AsyncError(cancelled, StackTrace.current),
        StateError('bad element'),
      ];
      final errors = source.cast<AsyncError?>();
      final envelope = ParallelWaitError<Object?, List<AsyncError?>>(
        null,
        errors,
      );
      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(envelope));
    });

    test('a chain of twenty thousand envelopes does not overflow', () async {
      const cancelled = Cancelled('deep');
      ParallelWaitError<Object?, Object?> envelope = _listEnvelope([
        AsyncError(cancelled, StackTrace.current),
      ]);
      for (var i = 0; i < 20000; i++) {
        envelope = _listEnvelope([
          AsyncError(envelope, StackTrace.empty),
        ]);
      }

      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'deep');
    });

    test('a shared completed subgraph is not a cycle', () async {
      const cancelled = Cancelled('shared');
      final inner = _listEnvelope([AsyncError(cancelled, StackTrace.current)]);
      final branch = AsyncError(inner, StackTrace.current);
      final envelope = _listEnvelope([branch, branch]);

      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'shared');
    });

    test('a cycle makes the envelope unparsed', () async {
      const cancelled = Cancelled('cycle');
      final errors = <AsyncError?>[];
      final envelope = _listEnvelope(errors);
      errors
        ..add(AsyncError(cancelled, StackTrace.current))
        ..add(AsyncError(envelope, StackTrace.current));

      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(envelope));
    });

    test('an envelope that calls itself equal is still not a cycle', () async {
      // `ParallelWaitError` is not a `final` class, so `==` can say two
      // distinct envelopes are the same. Nesting must follow identity, or a
      // nested envelope would be read as a cycle and lose its cancellation.
      const cancelled = Cancelled('deep');
      final inner = _EqualEnvelope(
        const <Object?>[null],
        <AsyncError?>[AsyncError(cancelled, StackTrace.empty)],
      );
      final outer = _EqualEnvelope(
        const <Object?>[null],
        <AsyncError?>[AsyncError(inner, StackTrace.empty)],
      );
      expect(inner == outer, isTrue, reason: 'the input needs equal envelopes');

      final outcome = await _run(() async => throw outer);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'deep');
    });
  });

  group('cancellation selection', () {
    test('selection follows position rather than completion time', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      const firstCancelled = Cancelled('first position');
      const secondCancelled = Cancelled('second position');
      final job = Job<void>((ctx) async {
        await [
          first.future.then<void>((_) => throw firstCancelled),
          second.future.then<void>((_) => throw secondCancelled),
        ].wait;
      });
      await Future<void>.delayed(Duration.zero);
      second.complete();
      first.complete();

      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'first position');
      expect(outcome.reason, isA<HandlerCancelReason>());
    });

    test('a foreign cancellation before a child wins', () async {
      const foreign = Cancelled('foreign first');
      final foreignTrace = StackTrace.current;
      late Job<void> child;
      final parent = Job<void>((ctx) async {
        child = Job.deferred<void>((childContext) async {
          throw const Cancelled('child cancellation');
        });
        ctx.run(child).ignore();
        await child.done;
        final childCancelled = child.outcome! as Cancelled;
        final envelope = _listEnvelope([
          AsyncError(foreign, foreignTrace),
          AsyncError(childCancelled, StackTrace.current),
        ]);
        await Future<void>.error(envelope, StackTrace.current);
      });

      final outcome = await parent.done;
      expect(outcome, isA<Cancelled>());
      final result = outcome as Cancelled;
      expect(result.reason, isA<HandlerCancelReason>());
      expect(result.description, 'foreign first');
    });

    test('the first trace is kept when cancellation repeats', () async {
      const cancelled = Cancelled('repeated');
      final firstTrace = StackTrace.current;
      final secondTrace = StackTrace.current;
      final envelope = _listEnvelope([
        AsyncError(cancelled, firstTrace),
        AsyncError(cancelled, secondTrace),
      ]);

      final outcome = await _run(() async => throw envelope);
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).stackTrace, same(firstTrace));
    });
  });

  group('external cancellation and diagnostics', () {
    test('an external cancellation inside wait keeps its identity', () async {
      final errors = <Object>[];
      final cancellation = Cancelled.by(
        reason: const ManualCancelReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
      final job = ProbeJob<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          await [ctx.wait(Future<void>.value)].wait;
        },
      )
        ..whenCancelled((value) => expect(value, same(cancellation)))
        ..launch();
      _cancel(job, cancellation);

      final outcome = await job.done;
      expect(outcome, same(cancellation));
      expect(errors, isEmpty);
    });

    test('a clean envelope reaches an observer as cancellation', () async {
      final errors = <Object>[];
      const cancelled = Cancelled('observed');
      final envelope =
          _listEnvelope([AsyncError(cancelled, StackTrace.current)]);
      final job = ProbeJob<void>(
        observer: ErrorObserver(errors),
        (ctx) async => throw envelope,
      )..launch();

      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      expect(errors, isEmpty);
    });

    test('the zone route filters only a clean cancellation envelope', () async {
      final caught = <Object>[];
      final clean = _listEnvelope([
        AsyncError(const Cancelled('clean route'), StackTrace.current),
      ]);
      final mixed = _listEnvelope([
        AsyncError(StateError('route failure'), StackTrace.current),
        AsyncError(const Cancelled('route cancellation'), StackTrace.current),
      ]);
      await runZonedGuarded(
        () async {
          ProbeJob<void>((ctx) async {})
            ..report(clean, StackTrace.current)
            ..report(mixed, StackTrace.current);
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => caught.add(error),
      );
      expect(caught, [same(mixed)]);
    });

    test('unattended cancellation keeps ownership filtering', () async {
      final ownErrors = <Object>[];
      final own = Job<void>(
        observer: ErrorObserver(ownErrors),
        (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(Duration.zero);
            ctx.check();
          });
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
      );
      own.cancel().ignore();
      await own.done;
      await Future<void>.delayed(Duration.zero);
      expect(ownErrors, isEmpty);

      final foreignErrors = <Object>[];
      const foreign = Cancelled('foreign');
      final job = Job<void>(
        observer: ErrorObserver(foreignErrors),
        (ctx) async {
          ctx.unattended(() => throw foreign);
          await Future<void>.delayed(Duration.zero);
        },
      );
      await job.done;
      await Future<void>.delayed(Duration.zero);
      expect(foreignErrors, [same(foreign)]);
    });

    test('unattended hears a clean envelope but the zone does not', () async {
      final errors = <Object>[];
      final zone = <Object>[];
      const cancelled = Cancelled('unattended-clean');

      await runZonedGuarded(
        () async {
          final job = Job<void>(
            observer: ErrorObserver(errors),
            (ctx) async {
              ctx.unattended(() async {
                await [
                  Future<String>.value('ok'),
                  Future<String>.error(cancelled, StackTrace.empty),
                ].wait;
              });
              await Future<void>.delayed(Duration.zero);
            },
          );
          await job.done;
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => zone.add(error),
      )!;

      expect(errors, hasLength(1));
      expect(errors.single, isA<ParallelWaitError<Object?, Object?>>());
      expect(zone, isEmpty);
    });

    test('an unobserved clean envelope from unattended stays silent', () async {
      final zone = <Object>[];
      const cancelled = Cancelled('unattended-clean');

      await runZonedGuarded(
        () async {
          final job = Job<void>((ctx) async {
            ctx.unattended(() async {
              await [
                Future<String>.value('ok'),
                Future<String>.error(cancelled, StackTrace.empty),
              ].wait;
            });
            await Future<void>.delayed(Duration.zero);
          });
          await job.done;
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => zone.add(error),
      )!;

      expect(zone, isEmpty);
    });

    test('a mixed envelope from unattended reaches both routes', () async {
      final errors = <Object>[];
      final zone = <Object>[];
      final boom = StateError('unattended-boom');

      await runZonedGuarded(
        () async {
          final observed = Job<void>(
            observer: ErrorObserver(errors),
            (ctx) async {
              ctx.unattended(() async {
                await [
                  Future<void>.error(boom, StackTrace.empty),
                  Future<void>.error(
                    const Cancelled('mixed'),
                    StackTrace.empty,
                  ),
                ].wait;
              });
              await Future<void>.delayed(Duration.zero);
            },
          );
          await observed.done;
          await Future<void>.delayed(Duration.zero);

          final unobserved = Job<void>((ctx) async {
            ctx.unattended(() async {
              await [
                Future<void>.error(boom, StackTrace.empty),
                Future<void>.error(const Cancelled('mixed'), StackTrace.empty),
              ].wait;
            });
            await Future<void>.delayed(Duration.zero);
          });
          await unobserved.done;
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => zone.add(error),
      )!;

      expect(errors, hasLength(1));
      expect(errors.single, isA<ParallelWaitError<Object?, Object?>>());
      expect(zone, hasLength(1));
      expect(zone.single, isA<ParallelWaitError<Object?, Object?>>());
    });

    test('each turns a handler cancellation into a parent cancellation',
        () async {
      final controller = StreamController<int>();
      const cancelled = Cancelled('handler stopped');
      final parent = Job<void>((ctx) async {
        final listening = ctx.each(controller.stream, (child, event) {
          throw cancelled;
        });
        await listening.value;
      });
      await Future<void>.delayed(Duration.zero);
      controller.add(1);

      final outcome = await parent.done;
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, contains('handler stopped'));
      expect(controller.hasListener, isFalse);
      await controller.close();
    });

    test('each finishes its active handler before external cancellation',
        () async {
      final controller = StreamController<int>();
      final started = Completer<void>();
      final release = Completer<void>();
      var events = 0;
      final errors = <Object>[];
      final parent = Job<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          final listening = ctx.each(controller.stream, (child, event) async {
            events++;
            started.complete();
            await release.future;
          });
          await [listening.value, Future<void>.value()].wait;
        },
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(1);
      await started.future;
      parent.cancel().ignore();
      controller.add(2);
      release.complete();

      final outcome = await parent.done;
      expect(outcome, isA<Cancelled>());
      expect(events, 1);
      expect(errors, isEmpty);
      expect(controller.hasListener, isFalse);
      await controller.close();
    });

    test('each preserves a handler failure inside its diagnostic envelope',
        () async {
      final controller = StreamController<int>();
      final handlerError = StateError('handler failure');
      const cancellation = Cancelled('parallel sibling');
      final errors = <Object>[];
      late Job<void> parent;
      parent = Job<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          final listening = ctx.each(
            controller.stream,
            (child, event) {
              child.job.cancel().ignore();
              throw handlerError;
            },
          );
          await [
            listening.value,
            Future<void>.error(handlerError, StackTrace.current),
            Future<void>.error(cancellation, StackTrace.current),
          ].wait;
        },
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(1);
      final outcome = await parent.done;

      expect(outcome, isA<Failed>());
      final envelopes =
          errors.whereType<ParallelWaitError<Object?, Object?>>().toList();
      expect(errors, hasLength(2));
      expect(errors.first, same(handlerError));
      expect(envelopes, hasLength(1));
      final envelope = envelopes.single;
      final errorList = envelope.errors! as List<AsyncError?>;
      expect(
        errorList.any((error) => identical(error?.error, handlerError)),
        isTrue,
      );
      expect(
        errorList.any((error) => identical(error?.error, cancellation)),
        isTrue,
      );
      expect(errors, contains(same(handlerError)));
      expect(controller.hasListener, isFalse);
      await controller.close();
    });
  });

  group('continuation', () {
    test('a continuation classifies a clean parallel cancellation', () async {
      const cancelled = Cancelled('continuation stopped');
      final source = Job<int>((ctx) async => 1);
      final continuation = source.then<void>((ctx, value) async {
        await [
          Future<void>.value(),
          Future<void>.error(cancelled, StackTrace.current),
        ].wait;
      });

      final outcome = await continuation.done;
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'continuation stopped');
      expect(outcome.reason, isA<HandlerCancelReason>());
    });
  });

  group('invariance guards', () {
    test('a mixed envelope stays a failed object everywhere', () async {
      final failure = StateError('real failure');
      const cancelled = Cancelled('mixed cancellation');
      final values = <Object?>[null, 'value'];
      final errors = <AsyncError?>[
        AsyncError(cancelled, StackTrace.current),
        AsyncError(failure, StackTrace.current),
      ];
      final envelope = ParallelWaitError<List<Object?>, List<AsyncError?>>(
        values,
        errors,
      );
      final outcome = await _run(() async => throw envelope);

      expect(outcome, isA<Failed>());
      final result = outcome as Failed;
      expect(result.error, same(envelope));
      expect((result.error as ParallelWaitError).errors, same(errors));
      expect((result.error as ParallelWaitError).values, same(values));
    });

    test('an unobserved mixed envelope reaches the zone once', () async {
      final caught = <Object>[];
      final failure = StateError('mixed zone failure');
      final envelope = _listEnvelope([
        AsyncError(failure, StackTrace.current),
        AsyncError(const Cancelled('mixed'), StackTrace.current),
      ]);
      await runZonedGuarded(
        () async {
          final job = Job<void>((ctx) async => throw envelope);
          await Future<void>.delayed(Duration.zero);
          expect(job.outcome, isA<Failed>());
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => caught.add(error),
      );
      expect(caught, [same(envelope)]);
    });

    test('a mixed nested envelope stays as the outer object', () async {
      final failure = StateError('nested real failure');
      final inner = _listEnvelope([
        AsyncError(failure, StackTrace.current),
        AsyncError(const Cancelled('nested cancel'), StackTrace.current),
      ]);
      final outer = _listEnvelope([AsyncError(inner, StackTrace.current)]);

      final outcome = await _run(() async => throw outer);
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(outer));
    });

    test('a pending cancellation wins over a mixed envelope with observer',
        () async {
      final errors = <Object>[];
      final failure = StateError('pending failure');
      final pending = Completer<void>();
      final cancellation = Cancelled.by(
        reason: const ManualCancelReason(),
        started: true,
        stackTrace: StackTrace.current,
      );
      final job = ProbeJob<void>(
        observer: ErrorObserver(errors),
        (ctx) async {
          await [
            Future<void>.error(failure, StackTrace.current),
            ctx.wait(() => pending.future),
          ].wait;
        },
      )..launch();
      await Future<void>.delayed(Duration.zero);
      _cancel(job, cancellation);
      final outcome = await job.done;

      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).reason, isA<ManualCancelReason>());
      expect(errors, hasLength(1));
      expect(errors.single, isA<ParallelWaitError<Object?, Object?>>());
      expect(outcome, same(cancellation));
    });

    test('a pending cancellation wins over a mixed envelope without observer',
        () async {
      final caught = <Object>[];
      final failure = StateError('pending silent failure');
      await runZonedGuarded(
        () async {
          final pending = Completer<void>();
          final cancellation = Cancelled.by(
            reason: const ManualCancelReason(),
            started: true,
            stackTrace: StackTrace.current,
          );
          final job = ProbeJob<void>((ctx) async {
            await [
              Future<void>.error(failure, StackTrace.current),
              ctx.wait(() => pending.future),
            ].wait;
          })
            ..launch();
          await Future<void>.delayed(Duration.zero);
          _cancel(job, cancellation);
          final outcome = await job.done;
          expect(outcome, isA<Cancelled>());
          await Future<void>.delayed(Duration.zero);
        },
        (error, stackTrace) => caught.add(error),
      );
      expect(caught, isEmpty);
    });

    test('Future.wait keeps its first completed error behavior', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final firstFailure = StateError('first future');
      const secondCancelled = Cancelled('second future');
      final job = Job<void>((ctx) async {
        await Future.wait<void>([first.future, second.future]);
      });
      await Future<void>.delayed(Duration.zero);
      second.completeError(secondCancelled, StackTrace.current);
      first.completeError(firstFailure, StackTrace.current);

      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      expect((outcome as Cancelled).description, 'second future');
      expect(outcome.reason, isA<HandlerCancelReason>());
    });

    test('eagerError wakes the body early and ends nothing early', () async {
      // What `doc/children.md` promises about the idiom: the body wakes on
      // the first error, nothing asks the other branch to stop, and the job
      // still ends with its last child — by which time a body that caught
      // the error has already decided the outcome, and a resource the slow
      // branch returned has gone to a `Future.wait` that is over.
      final slow = Completer<void>();
      final errors = <Object>[];
      final closed = <String>[];
      var bodyWoke = false;
      var finished = false;
      final quick = Job.deferred<String>((ctx) async => throw StateError('q'));
      final late = Job.deferred<String>((ctx) async {
        await ctx.wait(() => slow.future);

        return ctx.wait(() => 'db', discard: closed.add);
      });
      final job = Job<void>(observer: ErrorObserver(errors), (ctx) async {
        try {
          await Future.wait(
            [ctx.run(quick), ctx.run(late)],
            eagerError: true,
          );
        } on Object {
          bodyWoke = true;
        }
      });
      unawaited(job.done.then((_) => finished = true));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bodyWoke, isTrue, reason: 'the first error reached the body');
      expect(
        finished,
        isFalse,
        reason: 'and the job is still waiting for the branch nobody stopped',
      );

      slow.complete();
      final outcome = await job.done;
      expect(
        outcome,
        isA<Done<void>>(),
        reason: 'the body caught the error and returned, so a failed branch '
            'left the job successful',
      );
      expect(
        closed,
        isEmpty,
        reason: 'the branch handed its value to a `Future.wait` that had '
            'already completed, and nobody closed it',
      );
      expect(errors, [isA<StateError>()], reason: 'only the branch own error');
    });

    test('an intentional envelope and a nested Failed stay opaque', () async {
      final failure = StateError('intentional failure');
      final envelope = _listEnvelope([AsyncError(failure, StackTrace.current)]);
      final envelopeOutcome = await _run(() async => throw envelope);
      expect(envelopeOutcome, isA<Failed>());
      expect((envelopeOutcome as Failed).error, same(envelope));

      final failed = Failed(failure, StackTrace.current);
      final nestedOutcome = await _run(
        () async => Future<void>.error(failed, failed.stackTrace),
      );
      expect(nestedOutcome, isA<Failed>());
      expect((nestedOutcome as Failed).error, same(failed));
    });

    test('a continuation forwards a source failure unchanged', () async {
      final failure = StateError('source failure');
      var called = false;
      final source = Job<int>((ctx) async => throw failure);
      final continuation = source.then<void>((ctx, value) {
        called = true;
      });

      final outcome = await continuation.done;
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).error, same(failure));
      expect(called, isFalse);
    });

    test('wait disposal runs once before the job finishes', () async {
      final resource = Object();
      var closed = 0;
      const cancelled = Cancelled('dispose');
      final job = Job<void>((ctx) async {
        await ctx.wait(
          () async => resource,
          dispose: (value) {
            expect(value, same(resource));
            closed++;
          },
        );
        throw cancelled;
      });

      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      expect(closed, 1);
    });
  });
}

/// An envelope that reports every other envelope as equal to itself.
@immutable
final class _EqualEnvelope
    extends ParallelWaitError<List<Object?>, List<AsyncError?>> {
  _EqualEnvelope(super.values, super.errors);

  @override
  bool operator ==(Object other) => other is _EqualEnvelope;

  @override
  int get hashCode => 1;
}
