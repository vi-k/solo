// What an observer's `onCreate` may already do with the controller it is
// handed: queue a job through the controller's own method and then close or
// clear it. The queue exists by then, and `close` and `cancelAll` reach it.
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

final class _Loader extends Solo<int> {
  _Loader() : super(0);

  /// A job that would wait for good once started.
  SoloJob<void> load() =>
      enqueue<int, void>(key: 'load', (ctx) => Completer<void>().future);
}

/// Hands every [_Loader] it sees created to [act].
final class _OnCreate extends SoloObserver {
  final void Function(_Loader loader) act;

  _OnCreate(this.act);

  @override
  void onCreate(SoloController<Object> solo) {
    if (solo is _Loader) act(solo);
  }
}

void main() {
  tearDown(() {
    Solo.observer = null;
  });

  test('a job queued in onCreate is dropped by close from there', () async {
    SoloJob<void>? job;
    Solo.observer = _OnCreate((loader) {
      job = loader.load();
      loader.close().ignore();
    });
    _Loader();
    await pumpEventQueue();

    expect(job?.isFinished, isTrue);
    expect(
      job?.outcome,
      isA<Cancelled>()
          .having((c) => c.reason, 'reason', isA<ClosedCancelReason>())
          .having((c) => c.started, 'started', isFalse),
    );
  });

  test('a job queued in onCreate is dropped by cancelAll from there', () async {
    SoloJob<void>? job;
    Solo.observer = _OnCreate((loader) {
      job = loader.load();
      loader.cancelAll().ignore();
    });
    _Loader();
    await pumpEventQueue();

    expect(job?.isFinished, isTrue);
    expect(
      job?.outcome,
      isA<Cancelled>()
          .having((c) => c.reason, 'reason', isA<ManualCancelReason>())
          .having((c) => c.started, 'started', isFalse),
    );
  });
}
