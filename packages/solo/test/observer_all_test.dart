@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/plain_solo.dart';
import 'support/test_state.dart';

/// Writes down every hook it hears, under its [name].
final class Recording extends SoloObserver {
  final String name;
  final List<String> seen;

  Recording(this.name, this.seen);

  @override
  void onCreate(Solo<Object> solo) => seen.add('$name onCreate');

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      seen.add('$name onStart');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      seen.add('$name onFinish');

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      seen.add('$name onError: $error');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      seen.add('$name onChange');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      seen.add('$name onLog: $message');

  @override
  void onClose(Solo<Object> solo) => seen.add('$name onClose');
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

/// Throws from [onStart], and a [Cancelled] from [onLog].
final class Throwing extends SoloObserver {
  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      throw StateError('onStart');

  @override
  void onLog(Solo<Object> solo, Job<Object?> job, Object? message) =>
      throw const Cancelled('from onLog');
}

/// What the hooks and the zone hear while [observer] watches a controller
/// whose one job changes the state, logs and fails, and which then closes.
List<String> heard(SoloObserver Function(List<String> seen) observer) {
  final seen = <String>[];
  runZonedGuarded(
    () => fakeAsync((async) {
      Solo.observer = observer(seen);
      try {
        final solo = PlainSolo<TestState>(const Initial());
        solo.run<TestState, void>((ctx) async {
          ctx
            ..emit(const Preparing())
            ..log('hello');
          throw StateError('boom');
        }).ignore();
        async.flushTimers();
        solo.close();
        async.flushTimers();
      } finally {
        Solo.observer = null;
      }
    }),
    (error, stackTrace) => seen.add('zone: $error'),
  );
  return seen;
}

void main() {
  tearDown(() => Solo.observer = null);

  test('every hook goes to each observer in order', () {
    expect(
      heard(
        (seen) => SoloObserver.all([
          Recording('a', seen),
          Recording('b', seen),
        ]),
      ),
      [
        'a onCreate',
        'b onCreate',
        'a onStart',
        'b onStart',
        'a onChange',
        'b onChange',
        'a onLog: hello',
        'b onLog: hello',
        'a onError: Bad state: boom',
        'b onError: Bad state: boom',
        'a onFinish',
        'b onFinish',
        'a onClose',
        'b onClose',
      ],
    );
  });

  test('a hook that throws switches off none of the others', () {
    expect(
      heard((seen) => SoloObserver.all([Throwing(), Recording('a', seen)]))
          .where((line) => !line.contains('onC')),
      [
        'zone: Bad state: onStart',
        'a onStart',
        'zone: Cancelled(handler: from onLog)',
        'a onLog: hello',
        'a onError: Bad state: boom',
        'a onFinish',
      ],
      reason: 'a Cancelled goes to the zone, as one thrown by a single '
          'observer does',
    );
    expect(
      heard((seen) => Throwing()),
      contains('zone: Cancelled(handler: from onLog)'),
      reason: 'the single observer, for comparison',
    );
  });

  test('the same observer twice is refused, inside another one too', () {
    final a = Recording('a', []);
    final inner = SoloObserver.all([a]);
    expect(() => SoloObserver.all([a, a]), throwsArgumentError);
    expect(() => SoloObserver.all([a, inner]), throwsArgumentError);
    expect(() => SoloObserver.all([inner, inner]), throwsArgumentError);
  });

  test('two observers equal by == are two observers', () {
    expect(
      heard((seen) => SoloObserver.all([Alike('a', seen), Alike('b', seen)]))
          .where((line) => line.contains('onCreate')),
      ['a onCreate', 'b onCreate'],
    );
  });

  test('it names its observers', () {
    final a = Recording('a', []);
    expect(SoloObserver.all([a]).toString(), 'SoloObserver.all([$a])');
  });

  test('the observers are walked once, and kept as a copy', () {
    var made = 0;
    final seen = <String>[];
    final lazy = [1, 2].map((n) {
      made++;
      return Recording('lazy $n', seen);
    });
    final source = <SoloObserver>[Recording('a', seen)];
    final observer = SoloObserver.all(lazy);
    final copied = SoloObserver.all(source);
    source.add(Recording('added later', seen));
    fakeAsync((async) {
      Solo.observer = SoloObserver.all([observer, copied]);
      PlainSolo<TestState>(const Initial()).close();
      async.flushTimers();
    });
    expect(made, 2);
    expect(seen, isNot(contains('added later onCreate')));
    expect(seen, contains('lazy 2 onClose'));
  });
}
