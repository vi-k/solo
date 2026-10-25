// What the tests of `doc/observing.md`, `doc/errors.md` and
// `doc/error-rules.md` share: a job run under fake time with what it prints,
// the quotes of a page, and the observers and errors the tests write of their
// own.

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';

import 'delay.dart';
import 'observing_page.dart';
import 'observing_stubs.dart';

/// The fake time of the running [play].
late FakeAsync time;

int get now => time.elapsed.inMilliseconds;

/// Starts a job under fake time and returns what was printed.
///
/// The code around the job prints the outcome as `outcome:` unless
/// [outcomeObserved] is false, and cancels at [cancelAt] ms, printing
/// `cancel` and then how long `cancel()` took. An error that reaches the zone
/// is printed as `zone:`.
List<String> play(
  Job<Object?> Function() start, {
  int? cancelAt,
  bool outcomeObserved = true,
}) {
  final printed = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      time = async;
      final job = start();
      if (outcomeObserved) {
        unawaited(job.done.then((outcome) => print('outcome: $outcome')));
      }
      if (cancelAt != null) {
        async.elapse(Duration(milliseconds: cancelAt));
        print('cancel');
        final calledAt = now;
        unawaited(
          job.cancel().then(
                (_) => print('cancel() returned after ${now - calledAt} ms'),
              ),
        );
      }
      async.flushTimers();
    }),
    (error, stackTrace) => printed.add('zone: $error'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// The lines of [play] that the page quotes: `cancel()` timing is not one.
List<String> quotable(List<String> lines) => [
      for (final line in lines)
        if (!line.startsWith('cancel()')) line,
    ];

/// The job of the first attempt in "Where errors go", with [observer].
Job<void> migratingObserved(JobObserver observer) => Job<void>(
      observer: observer,
      (ctx) async {
        final stop = CancelToken();
        ctx.onCancel(stop.cancel);

        await ctx.join(() => database.migrate(stop));
      },
    );

/// What [run] returns with the filter of the page set as `main` sets it;
/// the field is put back after it.
List<String> withTheStopNamed(List<String> Function() run) {
  nameTheStop();
  try {
    return run();
  } finally {
    Job.isCancellationError = null;
  }
}

/// What [run] returns with the debug channel of the page switched on as
/// `main` switches it: its lines go where the job prints. The field is put
/// back after it.
List<String> debugged(List<String> Function() run) {
  debugToTheConsole();
  try {
    return quotable(run());
  } finally {
    Job.debug = null;
  }
}

/// The `text` blocks of [page], line by line, in the order of the page.
List<List<String>> pageQuotes(String page) => [
      for (final block in RegExp(r'```text\n(.*?)\n```', dotAll: true)
          .allMatches(File(page).readAsStringSync()))
        block.group(1)!.split('\n'),
    ];

/// An observer that hears through `onError` and answers in `onUnanswered`,
/// and with [passedOn] hands each error on to `super` as well.
final class Answerer extends JobObserver with JobAnswerer {
  final bool passedOn;

  Answerer({this.passedOn = false});

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) =>
      print('onError: $error');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    print('onUnanswered: $error');
    if (passedOn) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// Every hook, for the rules the page states about them.
final class Hooks extends JobObserver {
  final String name;

  Hooks([this.name = '']);

  @override
  void onStart(Job<Object?> job) => print('${name}onStart $job');

  @override
  void onFinish(Job<Object?> job) => print('${name}onFinish $job');

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) =>
      print('${name}onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      print('${name}onLog: $message');
}

/// A hook that throws, next to two that do not.
final class ThrowingStart extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart failed');

  @override
  void onLog(Job<Object?> job, Object? message) => print('onLog: $message');

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A hook that throws when the job ends.
final class ThrowingFinish extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => throw StateError('onFinish failed');
}

/// A hook that throws a cancellation, which goes nowhere.
final class ThrowingCancellation extends JobObserver {
  @override
  void onStart(Job<Object?> job) => throw const Cancelled('from onStart');

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A hook that cancels its job the way anybody else would.
final class CallingCancel extends JobObserver {
  @override
  void onStart(Job<Object?> job) => job.cancel().ignore();

  @override
  void onFinish(Job<Object?> job) => print('onFinish $job');
}

/// A class the app already has, which an observer extends.
class Tally {
  int count = 0;
}

/// Extends [Tally] and mixes in the observer and the answer.
final class TallyingAnswerer extends Tally with JobObserver, JobAnswerer {
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    count++;
    print('onError: $error');
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

/// An observer that keeps what `ctx.log` handed it.
final class Keeping extends JobObserver {
  final messages = <Object?>[];

  @override
  void onLog(Job<Object?> job, Object? message) => messages.add(message);
}

/// `SlowCancellations` of the page on fake time. A `Stopwatch` does not move
/// with fake time, so this one reads the fake clock, and the numbers the page
/// states come out exact.
final class FakeTimeCancellations extends JobObserver {
  final _acceptedAt = Expando<int>('cancellation');

  @override
  void onStart(Job<Object?> job) =>
      job.whenCancelled((_) => _acceptedAt[job] = now);

  @override
  void onFinish(Job<Object?> job) {
    final acceptedAt = _acceptedAt[job];
    if (acceptedAt != null) {
      print('$job ran ${now - acceptedAt} ms past its cancellation');
    }
  }
}

/// An observer whose `onError` throws.
final class Throwing extends JobObserver {
  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) =>
      throw StateError('reporter down');
}

/// `Both` of the page with any two observers in its place: `onError` handed
/// on by hand, unwrapped, the way the page writes it.
final class HandedOn extends JobObserver with JobAnswerer {
  final JobObserver first;
  final JobObserver second;

  HandedOn(this.first, this.second);

  @override
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {
    first.onError(job, error, stackTrace, answer: answer);
    second.onError(job, error, stackTrace, answer: answer);
  }

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onUnanswered: $error');
}

/// The error of the log section; it counts how often it is put into words.
final class MigrationFailed implements Exception {
  int formatted = 0;

  @override
  String toString() {
    formatted++;
    return 'MigrationFailed';
  }
}

/// A key that cannot be put into words.
final class BrokenKey {
  @override
  String toString() => throw StateError('key failed');
}

/// A reason of a cancellation that cannot be put into words.
final class BrokenReason extends CancelReason {
  const BrokenReason();

  @override
  String get name => throw StateError('name failed');
}

/// A step that cannot be rolled back: it fails at 20 ms.
Future<void> pay() async {
  await delay(20);
  throw StateError('payment failed');
}

/// A body that fails at 10 ms.
Job<void> failing({JobObserver? observer}) => Job<void>(
      key: 'save',
      observer: observer,
      (ctx) async {
        await delay(10);
        throw StateError('disk full');
      },
    );
