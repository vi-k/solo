@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

/// Writes down every hook it hears, under its [name].
class Recording with JobObserver {
  final String name;
  final List<String> seen;

  Recording(this.name, this.seen);

  @override
  void onStart(Job<Object?> job) => seen.add('$name onStart');

  @override
  void onFinish(Job<Object?> job) => seen.add('$name onFinish');

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('$name onError: $error');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      seen.add('$name onLog: $message');
}

/// A [Recording] that answers, and stops the error there.
final class Answering extends Recording with JobAnswerer {
  Answering(super.name, super.seen);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('$name onUnanswered: $error');
}

/// Throws from [onStart] and [onLog], [Cancelled] from the latter.
final class Throwing with JobObserver {
  @override
  void onStart(Job<Object?> job) => throw StateError('onStart');

  @override
  void onLog(Job<Object?> job, Object? message) =>
      throw const Cancelled('from onLog');
}

/// Equal to every other [Alike], though each is an observer of its own.
@immutable
final class Alike extends Recording {
  Alike(super.name, super.seen);

  @override
  bool operator ==(Object other) => other is Alike;

  @override
  int get hashCode => 0;
}

/// A job that logs, then leaves an error behind in unattended work.
Job<void> leavingAnError(JobObserver observer) =>
    Job<void>(observer: observer, (ctx) async {
      ctx
        ..log('hello')
        ..unattended(() => throw StateError('late'));
    });

/// What the hooks and the zone hear while [observer] watches
/// [leavingAnError] to its end.
List<String> heard(JobObserver Function(List<String> seen) observer) {
  final seen = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      leavingAnError(observer(seen)).ignore();
      async.flushTimers();
    }),
    (error, stackTrace) => seen.add('zone: $error'),
  );
  return seen;
}

void main() {
  test('every hook goes to each observer in order, the answer after onError',
      () {
    expect(
      heard(
        (seen) => JobObserver.all([
          Recording('a', seen),
          Answering('b', seen),
          Recording('c', seen),
        ]),
      ),
      [
        'a onStart',
        'b onStart',
        'c onStart',
        'a onLog: hello',
        'b onLog: hello',
        'c onLog: hello',
        'a onError: Bad state: late',
        'b onError: Bad state: late',
        'c onError: Bad state: late',
        'b onUnanswered: Bad state: late',
        'a onFinish',
        'b onFinish',
        'c onFinish',
      ],
    );
  });

  test('a hook that throws switches off none of the others', () {
    expect(
      heard(
        (seen) => JobObserver.all([
          Throwing(),
          Recording('a', seen),
        ]),
      ),
      [
        'zone: Bad state: onStart',
        'a onStart',
        'a onLog: hello',
        'a onError: Bad state: late',
        'zone: Bad state: late',
        'a onFinish',
      ],
      reason: 'the Cancelled of onLog goes nowhere',
    );
  });

  test('with nobody answering the error goes to the zone once', () {
    expect(
      heard(
        (seen) => JobObserver.all([Recording('a', seen), Recording('b', seen)]),
      ),
      contains('zone: Bad state: late'),
    );
    expect(
      heard(
        (seen) => JobObserver.all([Recording('a', seen), Recording('b', seen)]),
      ).where((line) => line.startsWith('zone:')),
      hasLength(1),
    );
  });

  test('with nobody answering, the zone is the one the job was created in', () {
    final creation = <String>[];
    final starting = <String>[];
    fakeAsync((async) {
      late final DeferredJob<void> job;
      runZonedGuarded(
        () {
          job = Job.deferred<void>(
            observer: JobObserver.all([
              Recording('a', []),
              Recording('b', []),
            ]),
            (ctx) async {
              ctx
                ..onDispose(() => throw StateError('cleanup'))
                ..onDispose(() => throw const Cancelled('cleanup'));
            },
          );
        },
        (error, stackTrace) => creation.add('$error'),
      );
      runZonedGuarded(job.start, (error, stackTrace) => starting.add('$error'));
      async.flushTimers();
    });
    expect(
      creation,
      ['Bad state: cleanup'],
      reason: 'once, and the cancellation goes nowhere',
    );
    expect(starting, isEmpty);
  });

  test('made of observers that do not answer, it does not answer', () {
    expect(JobObserver.all([Recording('a', [])]), isNot(isA<JobAnswerer>()));
    expect(JobObserver.all([]), isNot(isA<JobAnswerer>()));
    expect(
      JobObserver.all([Answering('a', [])]),
      isA<JobAnswerer>(),
    );
  });

  test('the answer comes from wherever the answering observer stands', () {
    expect(
      heard(
        (seen) => JobObserver.all([
          Answering('a', seen),
          Recording('b', seen),
        ]),
      ).where((line) => line.contains('Error') || line.contains('Unanswered')),
      [
        'a onError: Bad state: late',
        'b onError: Bad state: late',
        'a onUnanswered: Bad state: late',
      ],
    );
  });

  test('one made by all answers inside another', () {
    expect(
      heard(
        (seen) => JobObserver.all([
          Recording('a', seen),
          JobObserver.all([Answering('b', seen)]),
        ]),
      ),
      allOf(
        contains('b onUnanswered: Bad state: late'),
        isNot(contains('zone: Bad state: late')),
      ),
    );
    expect(
      heard(
        (seen) => JobObserver.all([
          Answering('a', seen),
          JobObserver.all([Recording('b', seen)]),
        ]),
      ),
      allOf(
        contains('a onUnanswered: Bad state: late'),
        contains('b onError: Bad state: late'),
        isNot(contains('zone: Bad state: late')),
      ),
      reason: 'one with nobody answering inside is no second answer',
    );
  });

  test('two that answer are refused, inside another one too', () {
    expect(
      () => JobObserver.all([Answering('a', []), Answering('b', [])]),
      throwsArgumentError,
    );
    expect(
      () => JobObserver.all([
        Answering('a', []),
        JobObserver.all([Recording('b', []), Answering('c', [])]),
      ]),
      throwsArgumentError,
    );
  });

  test('the same observer twice is refused, inside another one too', () {
    final a = Recording('a', []);
    final answering = Answering('b', []);
    final inner = JobObserver.all([a]);
    expect(() => JobObserver.all([a, a]), throwsArgumentError);
    final nested = JobObserver.all([a]);
    expect(() => JobObserver.all([a, nested]), throwsArgumentError);
    expect(() => JobObserver.all([inner, inner]), throwsArgumentError);
    final answeringInside = JobObserver.all([answering]);
    expect(
      () => JobObserver.all([answering, answeringInside]),
      throwsArgumentError,
    );
  });

  test('two observers equal by == are two observers', () {
    expect(
      heard(
        (seen) => JobObserver.all([Alike('a', seen), Alike('b', seen)]),
      ).where((line) => line.contains('onStart')),
      ['a onStart', 'b onStart'],
    );
  });

  test('it names its observers', () {
    final a = Recording('a', []);
    expect(
      JobObserver.all([a]).toString(),
      'JobObserver.all([$a])',
    );
    expect(
      JobObserver.all([Answering('b', [])]).toString(),
      startsWith('JobObserver.all(['),
    );
  });

  test('the observers are walked once, and kept as a copy', () {
    var made = 0;
    final seen = <String>[];
    final source = [Recording('a', seen)];
    final lazy = [1, 2].map((n) {
      made++;
      return Recording('lazy $n', seen);
    });
    final copied = JobObserver.all(source);
    final walkedOnce = JobObserver.all(lazy);
    source.add(Recording('added later', seen));
    fakeAsync((async) {
      Job<void>(observer: copied, (ctx) async {}).ignore();
      Job<void>(observer: walkedOnce, (ctx) async {}).ignore();
      async.flushTimers();
    });
    expect(made, 2, reason: 'one walk of two, at creation');
    expect(seen, contains('lazy 2 onFinish'));
    expect(seen, isNot(contains('added later onStart')));
  });

  test('made of nobody, it watches nothing and answers for nothing', () {
    expect(heard((seen) => JobObserver.all([])), ['zone: Bad state: late']);
  });

  test('a child takes it whole, the answer included', () {
    final seen = <String>[];
    runZonedGuarded(
      () => fakeAsync((async) {
        Job<void>(
          observer: JobObserver.all([Answering('a', seen)]),
          (ctx) => ctx.run(
            Job.deferred<void>((ctx) async {
              ctx.unattended(() => throw StateError('child'));
            }),
          ),
        ).ignore();
        async.flushTimers();
      }),
      (error, stackTrace) => seen.add('zone: $error'),
    );
    expect(seen, contains('a onUnanswered: Bad state: child'));
    expect(seen, isNot(contains('zone: Bad state: child')));
  });
}
