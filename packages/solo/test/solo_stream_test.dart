import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_state.dart';

void main() {
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
final class _BombAboveStream extends Solo<TestState>
    with SoloStream<TestState>, _Bomb<TestState> {
  _BombAboveStream(super.initialState);

  void set(TestState next) => externalSetState(next);
}

/// `SoloStream` is the topmost override here: it calls `_Bomb.publish`
/// through `super` first, and the throw from inside that call happens
/// before `SoloStream` reaches its own line that feeds the stream.
final class _BombBelowStream extends Solo<TestState>
    with _Bomb<TestState>, SoloStream<TestState> {
  _BombBelowStream(super.initialState);

  void set(TestState next) => externalSetState(next);
}
