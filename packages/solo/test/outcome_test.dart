import 'package:solo/solo.dart';
import 'package:test/test.dart';

void main() {
  test('public Cancelled constructor is a handler signal', () {
    const cancelled = Cancelled('no photo');
    expect(cancelled.reason, CancelReason.handler);
    expect(cancelled.started, isTrue);
    expect(cancelled.description, 'no photo');
    expect(cancelled.stackTrace, isNull);
    expect(cancelled, isA<Exception>());
  });

  test('toString shows reason and description', () {
    expect(const Cancelled().toString(), 'Cancelled(handler)');
    expect(const Cancelled('busy').toString(), 'Cancelled(handler: busy)');
    expect(const Done(42).toString(), 'Done(42)');
    expect(const Done<void>(null).toString(), 'Done(null)');
    expect(
      Failed(StateError('boom'), StackTrace.empty).toString(),
      'Failed(Bad state: boom)',
    );
  });

  test('switch over Outcome<T> is exhaustive with three cases', () {
    String describe(Outcome<int> outcome) => switch (outcome) {
          Done(:final value) => 'done $value',
          Failed(:final error) => 'failed $error',
          Cancelled(:final reason) => 'cancelled ${reason.name}',
        };
    expect(describe(const Done(1)), 'done 1');
    expect(describe(const Cancelled()), 'cancelled handler');
    expect(
      describe(Failed(StateError('x'), StackTrace.empty)),
      'failed Bad state: x',
    );
  });

  test('Policy has four values in spec order', () {
    expect(Policy.values, [
      Policy.sequential,
      Policy.droppable,
      Policy.replace,
      Policy.restart,
    ]);
  });
}
