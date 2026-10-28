@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

/// Writes down what [onError] of the controller is told, and answers for
/// every error itself so that none reaches the zone.
final class _Telling extends Solo<TestState> with OpenSolo<TestState> {
  final List<String> seen;

  _Telling(this.seen) : super(const Initial());

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => seen.add('solo: $error ${answer.name}');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('unanswered: $error');
}

/// Writes down what [onError] of the observer is told, under its [name].
final class _Watching extends SoloObserver {
  final String name;
  final List<String> seen;

  _Watching(this.name, this.seen);

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => seen.add('$name: $error ${answer.name}');
}

final class _Stopped implements Exception {
  @override
  String toString() => 'stopped';
}

/// What the hooks hear while [scenario] runs on a controller watched by two
/// observers through [SoloObserver.all].
List<String> _heard(void Function(_Telling solo, FakeAsync async) scenario) {
  final seen = <String>[];
  fakeAsync((async) {
    Solo.observer = SoloObserver.all([
      _Watching('a', seen),
      _Watching('b', seen),
    ]);
    try {
      final solo = _Telling(seen);
      scenario(solo, async);
      async.flushTimers();
      solo.close();
      async.flushTimers();
    } finally {
      Solo.observer = null;
    }
  });
  return seen;
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Job.isCancellationError = null;
  });

  test('a disposer that throws', () {
    expect(
      _heard((solo, async) {
        solo.enqueue<TestState, void>((ctx) async {
          ctx.onDispose(() => throw StateError('dispose'));
        });
      }),
      [
        'a: Bad state: dispose answered',
        'b: Bad state: dispose answered',
        'solo: Bad state: dispose answered',
        'unanswered: Bad state: dispose',
      ],
    );
  });

  test('a failure nobody reads', () {
    expect(
      _heard((solo, async) {
        solo.enqueue<TestState, void>((ctx) => throw StateError('boom'));
      }),
      [
        'a: Bad state: boom later',
        'b: Bad state: boom later',
        'solo: Bad state: boom later',
        'unanswered: Bad state: boom',
      ],
    );
  });

  test('a failure under ignoreFailure', () {
    expect(
      _heard((solo, async) {
        solo
            .enqueue<TestState, void>((ctx) => throw StateError('boom'))
            .ignoreFailure();
      }),
      [
        'a: Bad state: boom never',
        'b: Bad state: boom never',
        'solo: Bad state: boom never',
      ],
    );
  });

  test('a stop the filter names after a cancellation', () {
    Job.isCancellationError = (error) => error is _Stopped;
    expect(
      _heard((solo, async) {
        final job = solo.enqueue<TestState, void>((ctx) async {
          await ctx.join(
            () => Future<void>.delayed(
              const Duration(milliseconds: 10),
              () => throw _Stopped(),
            ),
          );
        });
        async.elapse(const Duration(milliseconds: 5));
        job.cancel().ignore();
      }),
      [
        'a: stopped cancellation',
        'b: stopped cancellation',
        'solo: stopped cancellation',
      ],
    );
  });
}
