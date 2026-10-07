import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

const cancelled = Cancelled('c');
final failure = StateError('f');

StackTrace trace(String name) => StackTrace.fromString(name);

AsyncError branch(Object error, String name) => AsyncError(error, trace(name));

/// Names an error the way the expectations below spell it.
final names = Map<Object, String>.identity();

ParallelWaitError<Object?, Object?> envelope(
  List<AsyncError?> errors, [
  String? name,
]) {
  final error = ParallelWaitError<List<Object?>, List<AsyncError?>>(
    List<Object?>.filled(errors.length, null),
    errors,
  );
  if (name != null) names[error] = name;
  return error;
}

ParallelWaitError<Object?, Object?> recordEnvelope(
  Object errors, [
  String? name,
]) {
  final error = ParallelWaitError<Object?, Object?>(null, errors);
  if (name != null) names[error] = name;
  return error;
}

String nameOf(Object error) => switch (error) {
      StateError(:final message) => message,
      Cancelled() => 'cancelled',
      _ => names[error] ?? '$error',
    };

/// A list whose elements throw when read.
final class Unreadable extends ListBase<AsyncError?> {
  @override
  int get length => 2;

  @override
  set length(int _) {}

  @override
  AsyncError? operator [](int index) => throw StateError('unreadable');

  @override
  void operator []=(int index, AsyncError? value) {}
}

/// A list whose length throws when read.
final class NoLength extends ListBase<AsyncError?> {
  @override
  int get length => throw StateError('no length');

  @override
  set length(int _) {}

  @override
  AsyncError? operator [](int index) => null;

  @override
  void operator []=(int index, AsyncError? value) {}
}

/// One error, what the walk hands over, and whether the job drops it.
///
/// `drops` was read off the core before it walked with [Job.visitErrors], at
/// 1c2be62: a body throwing `error` ends `Cancelled` exactly when it is
/// true. So the core of today is held to what it decided before.
typedef Shape = ({
  String name,
  Object error,
  List<String> calls,
  bool drops,
});

List<Shape> shapes() {
  final cycleBranches = <AsyncError?>[branch(cancelled, 'a'), null];
  final cycle = envelope(cycleBranches, 'cycle');
  cycleBranches[1] = branch(cycle, 'back');

  final loopBranches = <AsyncError?>[null, null];
  final loop = envelope(loopBranches, 'loop');
  loopBranches[0] = branch(loop, 'x');
  loopBranches[1] = branch(loop, 'y');

  final shared = envelope([branch(cancelled, 's')]);
  final sharedTen = recordEnvelope(
    (
      branch(cancelled, '1'),
      branch(cancelled, '2'),
      branch(cancelled, '3'),
      branch(cancelled, '4'),
      branch(cancelled, '5'),
      branch(cancelled, '6'),
      branch(cancelled, '7'),
      branch(cancelled, '8'),
      branch(cancelled, '9'),
      branch(cancelled, '10'),
    ),
    'ten',
  );

  var deep = envelope([branch(cancelled, 'bottom')]);
  for (var i = 0; i < 10000; i++) {
    deep = envelope([branch(deep, 'level')]);
  }

  final partlyReadable = ParallelWaitError<Object?, List<AsyncError?>>(
    null,
    <Object?>[branch(cancelled, 'a'), 'not a branch', branch(failure, 'b')]
        .cast<AsyncError?>(),
  );
  names[partlyReadable] = 'partly readable';

  final bare = envelope([branch(failure, 'x')], 'bare');

  return [
    (
      name: 'a failure',
      error: failure,
      calls: ['failure f @root'],
      drops: false,
    ),
    (
      name: 'a cancellation',
      error: cancelled,
      calls: ['cancelled @root'],
      drops: true,
    ),
    (
      name: 'two cancellations',
      error: envelope([branch(cancelled, 'a'), branch(cancelled, 'b')]),
      calls: ['cancelled @a', 'cancelled @b'],
      drops: true,
    ),
    (
      name: 'a value and a cancellation',
      error: envelope([null, branch(cancelled, 'b')]),
      calls: ['cancelled @b'],
      drops: true,
    ),
    (
      name: 'a cancellation and a failure',
      error: envelope([branch(cancelled, 'a'), branch(failure, 'b')]),
      calls: ['cancelled @a', 'failure f @b'],
      drops: false,
    ),
    (
      name: 'nested cancellations',
      error: envelope([
        branch(envelope([branch(cancelled, 'aa')]), 'a'),
        branch(cancelled, 'b'),
      ]),
      calls: ['cancelled @aa', 'cancelled @b'],
      drops: true,
    ),
    (
      name: 'a nested failure',
      error: envelope([
        branch(envelope([branch(failure, 'aa')]), 'a'),
        branch(cancelled, 'b'),
      ]),
      calls: ['failure f @aa', 'cancelled @b'],
      drops: false,
    ),
    (
      name: 'a record of cancellations',
      error: recordEnvelope(
        (branch(cancelled, 'a'), branch(cancelled, 'b')),
      ),
      calls: ['cancelled @a', 'cancelled @b'],
      drops: true,
    ),
    (
      name: 'a record with a failure',
      error: recordEnvelope((branch(cancelled, 'a'), branch(failure, 'b'))),
      calls: ['cancelled @a', 'failure f @b'],
      drops: false,
    ),
    (
      name: 'a record of ten',
      error: sharedTen,
      calls: ['failure ten @root'],
      drops: false,
    ),
    (
      name: 'an envelope of an unknown shape',
      error: recordEnvelope('not errors', 'unknown'),
      calls: ['failure unknown @root'],
      drops: false,
    ),
    (
      name: 'values only',
      error: envelope([null, null], 'values'),
      calls: ['failure values @root'],
      drops: false,
    ),
    (
      name: 'a bare failure in a record',
      error: recordEnvelope((failure, branch(cancelled, 'b'))),
      calls: ['failure f @root', 'cancelled @b'],
      drops: false,
    ),
    (
      name: 'a bare cancellation in a record',
      error: recordEnvelope((cancelled, branch(cancelled, 'b'))),
      calls: ['failure cancelled @root', 'cancelled @b'],
      drops: false,
    ),
    (
      name: 'a cycle',
      error: cycle,
      calls: ['cancelled @a', 'failure cycle @back'],
      drops: false,
    ),
    (
      name: 'two edges back to one envelope',
      error: loop,
      calls: ['failure loop @x'],
      drops: false,
    ),
    (
      name: 'two paths to one envelope',
      error: envelope([branch(shared, 'a'), branch(shared, 'b')]),
      calls: ['cancelled @s'],
      drops: true,
    ),
    (
      name: 'two paths to one unreadable envelope',
      error: envelope([branch(sharedTen, 'a'), branch(sharedTen, 'b')]),
      calls: ['failure ten @a'],
      drops: false,
    ),
    (
      name: 'nesting ten thousand deep',
      error: deep,
      calls: ['cancelled @bottom'],
      drops: true,
    ),
    (
      name: 'an unreadable list',
      error: envelope(Unreadable(), 'unreadable'),
      calls: ['failure unreadable @root'],
      drops: false,
    ),
    (
      name: 'a partly readable list',
      error: partlyReadable,
      calls: [
        'cancelled @a',
        'failure partly readable @root',
        'failure f @b',
      ],
      drops: false,
    ),
    (
      name: 'a partly readable list, nested',
      error: envelope([branch(partlyReadable, 'n')]),
      calls: [
        'cancelled @a',
        'failure partly readable @n',
        'failure f @b',
      ],
      drops: false,
    ),
    (
      name: 'a bare failure in a nested record',
      error: envelope([
        branch(recordEnvelope((failure, branch(cancelled, 'x'))), 'n'),
      ]),
      calls: ['failure f @n', 'cancelled @x'],
      drops: false,
    ),
    (
      name: 'one envelope bare twice',
      error: recordEnvelope((bare, bare)),
      calls: ['failure bare @root'],
      drops: false,
    ),
    (
      name: 'one envelope walked, then bare',
      error: recordEnvelope((branch(bare, 'w'), bare)),
      calls: ['failure f @x', 'failure bare @root'],
      drops: false,
    ),
    (
      name: 'an empty nested envelope beside a failure',
      error: envelope([
        branch(envelope([null]), 'a'),
        branch(failure, 'b'),
      ]),
      calls: ['failure f @b'],
      drops: false,
    ),
    (
      name: 'an empty nested envelope beside a cancellation',
      error: envelope([
        branch(envelope([null]), 'a'),
        branch(cancelled, 'b'),
      ]),
      calls: ['cancelled @b'],
      drops: true,
    ),
  ];
}

List<String> walk(Object error, {bool cancellations = true}) {
  final calls = <String>[];
  Job.visitErrors(
    error,
    trace('root'),
    onFailure: (error, stackTrace) =>
        calls.add('failure ${nameOf(error)} @$stackTrace'),
    onCancelled: cancellations
        ? (cancelled, stackTrace) => calls.add('cancelled @$stackTrace')
        : null,
  );
  return calls;
}

/// Whether the job drops [error] as a cancellation: a body that throws it
/// ends `Cancelled`, and `Failed` otherwise.
Future<bool> jobDrops(Object error) async {
  final job = Job<void>(
    (ctx) async => Error.throwWithStackTrace(error, StackTrace.current),
  );
  final outcome = await job.done;
  return outcome is Cancelled;
}

void shrinkWhileWalking(SendPort port) {
  final branches = <AsyncError?>[
    branch(cancelled, 'a'),
    branch(cancelled, 'b'),
    branch(failure, 'c'),
  ];
  final calls = <String>[];
  Job.visitErrors(
    envelope(branches),
    trace('root'),
    onFailure: (error, stackTrace) => calls.add(
      error is ParallelWaitError ? 'failure envelope' : 'failure $error',
    ),
    onCancelled: (cancelled, stackTrace) {
      calls.add('cancelled');
      branches.clear();
    },
  );
  port.send(calls);
}

void main() {
  group('every shape', () {
    for (final shape in shapes()) {
      test('${shape.name}: the walk', () {
        expect(walk(shape.error), shape.calls);
      });

      test('${shape.name}: the walk without onCancelled', () {
        expect(
          walk(shape.error, cancellations: false),
          shape.calls.where((call) => call.startsWith('failure')),
        );
      });

      test('${shape.name}: the job', () async {
        expect(await jobDrops(shape.error), shape.drops);
        expect(
          shape.calls.any((call) => call.startsWith('failure')),
          !shape.drops,
          reason: 'no onFailure exactly when the job drops the error',
        );
      });
    }
  });

  group('the length of a list', () {
    test('that throws hands the envelope over whole', () {
      expect(
        walk(recordEnvelope(NoLength(), 'no length')),
        ['failure no length @root'],
      );
    });

    test('that throws ends a job that throws it Failed', () async {
      final job = Job<void>(
        (ctx) async => throw recordEnvelope(NoLength(), 'no length'),
      );
      final outcome = await job.done.timeout(const Duration(seconds: 5));
      expect(outcome, isA<Failed>());
    });

    test('that throws, from a hook of an observer, reaches the zone', () async {
      final error = recordEnvelope(NoLength(), 'no length');
      final zone = <Object>[];
      final outcome = Completer<Outcome<void>>();
      unawaited(
        runZonedGuarded(
          () async {
            final job = Job<void>(observer: _Starting(error), (ctx) async {});
            final done = await job.done;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            outcome.complete(done);
          },
          (error, stackTrace) => zone.add(error),
        ),
      );
      expect(
        await outcome.future.timeout(const Duration(seconds: 5)),
        isA<Done<void>>(),
      );
      expect(zone, [same(error)]);
    });

    test('is read once, and a callback that shortens the list ends the walk',
        () async {
      final port = ReceivePort();
      final isolate = await Isolate.spawn(shrinkWhileWalking, port.sendPort);
      final calls = await port.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 'the walk never returned',
      );
      isolate.kill(priority: Isolate.immediate);
      expect(calls, ['cancelled', 'failure envelope']);
    });
  });

  test('a callback that throws ends the walk and reaches the caller', () {
    final calls = <String>[];
    expect(
      () => Job.visitErrors(
        envelope([branch(failure, 'a'), branch(failure, 'b')]),
        trace('root'),
        onFailure: (error, stackTrace) {
          calls.add('failure @$stackTrace');
          throw StateError('thrown');
        },
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'thrown')),
    );
    expect(calls, ['failure @a']);
  });

  test('a Cancelled thrown inside onUnanswered goes nowhere', () async {
    final calls = <String>[];
    final zone = <Object>[];
    final done = Completer<void>();
    unawaited(
      runZonedGuarded(
        () async {
          final job = Job<void>(
            observer: _Answering(calls),
            (ctx) async {
              ctx.unattended(
                () async => throw envelope(
                  [branch(failure, 'a'), branch(failure, 'b')],
                ),
              );
            },
          );
          await job.done;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          done.complete();
        },
        (error, stackTrace) => zone.add(error),
      ),
    );
    await done.future;
    // The job asks about each failure in a call of its own, so the second
    // answer is not lost with the first.
    expect(calls, ['failure @a', 'failure @b']);
    expect(zone, isEmpty);
  });
}

final class _Starting extends JobObserver {
  final Object error;

  _Starting(this.error);

  @override
  void onStart(Job<Object?> job) =>
      Error.throwWithStackTrace(error, StackTrace.current);
}

final class _Answering extends JobObserver with JobAnswerer {
  final List<String> calls;

  _Answering(this.calls);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    calls.add('failure @$stackTrace');
    throw cancelled;
  }
}
