import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test(
    'close re-entered from a hook returns the same future, with a stream',
    () {
      fakeAsync((async) {
        final solo = _StreamCloseOnFinish()
          ..run<TestState, void>(key: 'dropped', (ctx) async {});
        final outer = solo.close();
        expect(solo.reentered, isNotNull, reason: 'the hook ran');
        expect(identical(solo.reentered, outer), isTrue);
        async.flushTimers();
      });
    },
  );

  test(
    'a plain close over a running drain stops it, sharing the future, '
    'with a stream',
    () {
      runSoloStream((solo, journal, async) {
        solo
          ..run<TestState, void>(
            key: 'running',
            (ctx) async => pause(ctx, 50),
          )
          ..run<TestState, void>(key: 'queued', (ctx) async {});
        async.flushMicrotasks();
        final first = solo.close(mode: SoloCloseMode.drain);
        async.elapse(const Duration(milliseconds: 10));
        final second = solo.close();
        expect(identical(first, second), isTrue);
        expect(solo.isDraining, isFalse);
        async.flushTimers();
        expect(journal.take(), [
          '[running] started',
          '[queued] dropped Cancelled(closed)',
          '[running] finished Cancelled(closed)',
          'closed',
        ]);
      });
    },
  );

  test('a neighbor above SoloStream still lets the stream see the event', () {
    fakeAsync((async) {
      final solo = _BombAboveStream(const Initial());
      final seen = <TestState>[];
      solo.stream.listen(seen.add);
      expect(() => solo.set(const Working()), throwsStateError);
      async.flushMicrotasks();
      expect(seen, [const Working()]);
    });
  });

  test('a neighbor below SoloStream keeps the stream from seeing it', () {
    fakeAsync((async) {
      final solo = _BombBelowStream(const Initial());
      final seen = <TestState>[];
      solo.stream.listen(seen.add);
      expect(() => solo.set(const Working()), throwsStateError);
      async.flushMicrotasks();
      expect(seen, isEmpty);
    });
  });

  test('a generic controller takes SoloStream by inference', () {
    fakeAsync((async) {
      final solo = _OpenGeneric<int>(0);
      final SoloStream<int> typed = solo;
      final seen = <int>[];
      typed.stream.listen(seen.add);
      solo.run<int, void>((ctx) async => ctx.emit(3));
      async.flushMicrotasks();
      expect(seen, [3]);
    });
  });
}

/// A neighbor that delivers, then gives up: calls `super.publish` before
/// throwing, so the mixin below it in `with` always sees the change.
mixin _Bomb<S extends Object> on Solo<S> {
  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    throw StateError('bomb');
  }
}

/// `_Bomb` is the topmost override here, so it reaches `SoloStream.publish`
/// through `super` before throwing: the stream is fed, then the throw
/// escapes `externalSetState`.
final class _BombAboveStream extends Solo<TestState> with SoloStream, _Bomb {
  _BombAboveStream(super.initialState);

  void set(TestState next) => externalSetState(next);
}

/// `SoloStream` is the topmost override here: it calls `_Bomb.publish`
/// through `super` first, and the throw from inside that call happens
/// before `SoloStream` reaches its own line that feeds the stream.
final class _BombBelowStream extends Solo<TestState> with _Bomb, SoloStream {
  _BombBelowStream(super.initialState);

  void set(TestState next) => externalSetState(next);
}

final class _StreamCloseOnFinish extends Solo<TestState>
    with SoloStream, OpenSolo<TestState> {
  _StreamCloseOnFinish() : super(const Initial());

  /// The future returned by the `close` called from inside `close`.
  Future<void>? reentered;

  @override
  void onFinish(Job<Object?> job) {
    reentered ??= close();
  }
}

/// The one-line class `CHANGELOG` gives for a controller that used to be
/// created directly for its stream: the argument of `SoloStream` comes from
/// the superclass, a type parameter included, and the constructor of `Solo`
/// is taken as it is.
final class _Generic<T extends Object> = Solo<T> with SoloStream;

/// [_Generic] as it is, with its protected surface open for the test.
final class _OpenGeneric<T extends Object> = _Generic<T> with OpenSolo<T>;
