@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('each follows the stream until it is done', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <int>[];
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, seen.add);
      });
      async.flushMicrotasks();
      controller
        ..add(1)
        ..add(2);
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(seen, [1, 2]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('the subscription lives exactly as long as the job', () {
    fakeAsync((async) {
      var cancelled = false;
      final controller = StreamController<int>(
        onCancel: () => cancelled = true,
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (_) {});
      });
      async.flushMicrotasks();
      expect(cancelled, isFalse);
      job.cancel().ignore();
      async.flushTimers();
      expect(cancelled, isTrue, reason: 'nothing is left listening');
      expect(job.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });

  test('an error from the stream ends the wait and reaches the body', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      Object? caught;
      final job = Job<void>((ctx) async {
        try {
          await ctx.each(controller.stream, (_) {});
        } on Object catch (error) {
          caught = error;
        }
      });
      async.flushMicrotasks();
      controller.addError(StateError('stream'));
      async.flushMicrotasks();
      expect(caught, isA<StateError>());
      expect(job.outcome, isA<Done<void>>(), reason: 'the body caught it');
      controller.close().ignore();
    });
  });

  test('an error from onData ends the wait too', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (_) => throw StateError('onData'));
      })
        ..ignore();
      async.flushMicrotasks();
      controller.add(1);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Failed>());
      expect((job.outcome! as Failed).error, isA<StateError>());
      controller.close().ignore();
      async.flushTimers();
    });
  });

  test('each leaves nothing listening for a job already cancelled', () {
    fakeAsync((async) {
      var listened = false;
      final controller = StreamController<int>(
        onListen: () => listened = true,
      );
      Object? thrown;
      final job = Job<void>((ctx) async {
        try {
          await ctx.wait(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        } on Cancelled {
          // Caught: the body walks on to a stream anyway.
        }
        try {
          await ctx.each(controller.stream, (_) {});
        } on Object catch (error) {
          thrown = error;
        }
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(thrown, isA<Cancelled>());
      expect(listened, isFalse, reason: 'it never subscribed at all');
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('a body that cancels itself from onData does not hang', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) {
          if (event == 2) {
            throw const Cancelled('enough');
          }
        });
      });
      async.flushMicrotasks();
      controller
        ..add(1)
        ..add(2);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Cancelled>());
      expect(
        (job.outcome! as Cancelled).description,
        contains('enough'),
        reason: 'a body cancelling itself is not a cancellation from outside',
      );
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('a stream that refuses to be listened to leaves nothing behind', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final controller = StreamController<int>();
      // Single-subscription, and already taken: `listen` throws.
      controller.stream.listen((_) {}).cancel().ignore();
      Object? caught;
      final job = Job<void>(
        key: 'job',
        observer: journal,
        (ctx) async {
          try {
            await ctx.each(controller.stream, (_) {});
          } on Object catch (error) {
            caught = error;
          }
          await ctx.wait(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        },
      );
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(caught, isA<StateError>(), reason: 'the body sees the refusal');
      expect(
        journal.take().where((line) => line.contains('error')),
        isEmpty,
        reason: 'and the kernel invents no error of its own',
      );
      controller.close().ignore();
    });
  });

  test('a stream that cancels the job while it is being listened to', () {
    fakeAsync((async) {
      final journal = JobJournal();
      late final Job<void> job;
      final controller = StreamController<int>(
        onListen: () => job.cancel().ignore(),
      );
      job = Job<void>(
        key: 'job',
        observer: journal,
        (ctx) async {
          await ctx.each(controller.stream, (_) {});
        },
      );
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(controller.hasListener, isFalse);
      expect(
        journal.take().where((line) => line.contains('error')),
        isEmpty,
        reason: 'the callback fired before the subscription existed',
      );
      controller.close().ignore();
    });
  });

  test('each refuses a context that outlived its job', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      late final JobContext leaked;
      Job<void>((ctx) async {
        leaked = ctx;
      });
      async.flushMicrotasks();
      Object? caught;
      unawaited(
        leaked.each(controller.stream, (_) {}).then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) => caught = error,
            ),
      );
      async.flushMicrotasks();
      expect(
        caught,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cannot follow a stream'),
        ),
        reason: 'the message names what the caller asked for',
      );
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('the cancel callback leaves with the job it belonged to', () {
    fakeAsync((async) {
      // Counted on the subscription itself: the SDK makes a second cancel
      // of one subscription idempotent, so the source never sees it. A
      // callback left behind by `each` would show up here, and nowhere
      // else in this suite.
      final controller = StreamController<int>();
      final stream = _CountingStream<int>(controller.stream);
      final job = Job<void>((ctx) async {
        await ctx.each(stream, (_) {});
        await ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      });
      async.flushMicrotasks();
      controller.close().ignore();
      async.flushMicrotasks();
      expect(stream.cancels, 1, reason: 'the stream ended, each let go');
      job.cancel().ignore();
      async.flushTimers();
      expect(
        stream.cancels,
        1,
        reason: 'and the callback left with it, not with the job',
      );
    });
  });
  test('the subscription leaves with a job that ended without a cancellation',
      () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        // Followed in the background: the body walks away from the call, so
        // nothing of `each` runs again once the body is over.
        unawaited(ctx.each(controller.stream, (event) {}));
        await ctx.wait(() => delay(10));
      });
      async.elapse(const Duration(milliseconds: 50));
      expect(job.outcome, isA<Done<void>>());
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('an asynchronous onData is waited for, one event at a time', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <String>[];
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) async {
          seen.add('start $event');
          await delay(10);
          seen.add('end $event');
        });
      });
      async.flushMicrotasks();
      controller
        ..add(1)
        ..add(2);
      unawaited(controller.close());
      async.elapse(const Duration(milliseconds: 100));
      expect(seen, ['start 1', 'end 1', 'start 2', 'end 2']);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('an error from an asynchronous onData ends the wait too', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) async {
          await delay(10);
          throw StateError('boom');
        });
      })
        ..ignore();
      async.flushMicrotasks();
      controller.add(1);
      async.elapse(const Duration(milliseconds: 100));
      expect(job.outcome, isA<Failed>());
      expect(controller.hasListener, isFalse);
      controller.close().ignore();
    });
  });

  test('an event after an error of the stream never reaches onData', () {
    fakeAsync((async) {
      final controller = StreamController<int>();
      final seen = <int>[];
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, seen.add);
      })
        ..ignore();
      async.flushMicrotasks();
      controller
        ..addError(StateError('boom'))
        ..add(1);
      async.elapse(const Duration(milliseconds: 10));
      expect(seen, isEmpty);
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });

  test('onData that cancels its own job leaves no error behind', () {
    fakeAsync((async) {
      final journal = JobJournal();
      final controller = StreamController<int>();
      late Job<void> job;
      job = Job<void>(
        key: 'job',
        observer: journal,
        (ctx) async {
          await ctx.each(controller.stream, (event) {
            // The cancellation lands first, and the checkpoint right after
            // throws it: the wait ends by itself, and nothing here is an
            // error of the job.
            job.cancel().ignore();
            ctx.check();
          });
        },
      );
      async.flushMicrotasks();
      controller.add(1);
      async.elapse(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Cancelled>());
      expect(
        journal.lines.where((line) => line.contains('error')).toList(),
        isEmpty,
      );
      controller.close().ignore();
    });
  });
  test('events delivered from onListen keep their order', () {
    fakeAsync((async) {
      // A broadcast controller that hands the newcomer what it has: the
      // events arrive synchronously, from inside `listen` itself.
      final seen = <String>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2),
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) async {
          seen.add('start $event');
          await delay(10);
          seen.add('end $event');
        });
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 5));
      controller.add(3);
      unawaited(controller.close());
      async.flushTimers();
      expect(seen, [
        'start 1',
        'end 1',
        'start 2',
        'end 2',
        'start 3',
        'end 3',
      ]);
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('a handler that threw is not called again', () {
    fakeAsync((async) {
      final seen = <int>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2)
          ..add(3),
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) {
          seen.add(event);
          throw StateError('boom');
        });
      })
        ..ignore();
      async.flushTimers();
      expect(seen, [1]);
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });

  test('an error of a handler still running when the stream ends is kept', () {
    fakeAsync((async) {
      final seen = <String>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () {
          controller.add(1);
          unawaited(controller.close());
        },
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) async {
          seen.add('start $event');
          await delay(10);
          throw StateError('late boom');
        });
        seen.add('each returned');
      })
        ..ignore();
      async.flushTimers();
      expect(seen, ['start 1'], reason: 'the wait does not end before it');
      expect(job.outcome, isA<Failed>());
    });
  });
  test('an error from onListen waits for the events it came after', () {
    fakeAsync((async) {
      final seen = <String>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..addError(StateError('source boom')),
      );
      final job = Job<void>((ctx) async {
        try {
          await ctx.each(controller.stream, (event) async {
            seen.add('start $event');
            await delay(10);
            seen.add('end $event');
          });
        } on Object {
          seen.add('each threw');
          rethrow;
        }
      })
        ..ignore();
      async.flushTimers();
      expect(
        seen,
        ['start 1', 'end 1', 'each threw'],
        reason: 'the error waits for the event it came after',
      );
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });
  test('a handler that threw is not called by a source in the same stripe', () {
    fakeAsync((async) {
      // A synchronous source hands over two events in one go: the first
      // one throws, and the subscription has to be gone before the second
      // is delivered.
      final seen = <int>[];
      final controller = StreamController<int>(sync: true);
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) {
          seen.add(event);
          throw StateError('boom');
        });
      })
        ..ignore();
      async.flushMicrotasks();
      controller
        ..add(1)
        ..add(2);
      async.flushTimers();
      expect(seen, [1]);
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });
  test('a cancellation stops the playback of the early events', () {
    fakeAsync((async) {
      final seen = <String>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2)
          ..add(3),
      );
      late Job<void> job;
      job = Job<void>((ctx) async {
        await ctx.each(controller.stream, (event) async {
          seen.add('start $event');
          await delay(10);
          seen.add('end $event');
        });
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(
        seen,
        ['start 1', 'end 1'],
        reason: 'the handler in flight finishes, the rest is not delivered',
      );
      expect(job.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });

  test('a job cancelled from onListen delivers nothing at all', () {
    fakeAsync((async) {
      final seen = <int>[];
      late StreamController<int> controller;
      late Job<void> job;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () {
          controller
            ..add(1)
            ..add(2);
          job.cancel().ignore();
        },
      );
      job = Job<void>((ctx) async {
        await ctx.each(controller.stream, seen.add);
      })
        ..ignore();
      async.flushTimers();
      expect(
        seen,
        isEmpty,
        reason: 'the body learns of a cancellation before the handler does',
      );
      expect(job.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });

  test('an early error of a released stream reaches nobody', () {
    final caught = <Object>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          late StreamController<int> controller;
          late Job<void> job;
          controller = StreamController<int>.broadcast(
            sync: true,
            onListen: () {
              controller
                ..add(1)
                ..addError(StateError('source boom'));
              job.cancel().ignore();
            },
          );
          job = Job<void>((ctx) async {
            await ctx.each(controller.stream, (event) {});
          })
            ..ignore();
          async.flushTimers();
          controller.close().ignore();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(
      caught,
      isEmpty,
      reason: 'a released subscription drops what was still on its way',
    );
  });

  test('the playback stops when the job the body walked away from ends', () {
    fakeAsync((async) {
      final seen = <String>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2)
          ..add(3),
      );
      final job = Job<void>((ctx) async {
        ctx.each(controller.stream, (event) async {
          seen.add('start $event');
          await delay(10);
        }).ignore();
        await ctx.wait(() => delay(5));
      })
        ..ignore();
      async.flushTimers();
      expect(seen, ['start 1']);
      expect(job.outcome, isA<Done<void>>());
      controller.close().ignore();
    });
  });
  test('an error arrives without waiting for the source to clean up', () {
    fakeAsync((async) {
      // `onCancel` of a source may take as long as it likes, and may never
      // come back at all: that is the source's own business, and the body
      // does not wait for it.
      Object? thrown;
      final controller = StreamController<int>(
        onCancel: () => Completer<void>().future,
      );
      final job = Job<void>((ctx) async {
        try {
          await ctx.each(controller.stream, (event) {});
        } on Object catch (error) {
          thrown = error;
        }
      })
        ..ignore();
      async.flushMicrotasks();
      controller.addError(StateError('source boom'));
      async.elapse(const Duration(milliseconds: 10));
      expect(thrown, isA<StateError>());
      expect(job.outcome, isA<Done<void>>());
      controller.close().ignore();
    });
  });
  test('an error from onListen with no events reaches the observer', () {
    final caught = <Object>[];
    final journal = JobJournal();
    runZonedGuarded(
      () {
        fakeAsync((async) {
          late StreamController<int> controller;
          late Job<void> job;
          controller = StreamController<int>.broadcast(
            sync: true,
            onListen: () {
              // No event before it, so the error does not go through the
              // buffer: it ends the wait before anyone is waiting.
              controller.addError(StateError('source boom'));
              job.cancel().ignore();
            },
          );
          job = Job<void>(
            key: 'job',
            observer: journal,
            (ctx) async => ctx.each(controller.stream, (event) {}),
          )..ignore();
          async.flushTimers();
          controller.close().ignore();
        });
      },
      (error, stackTrace) => caught.add(error),
    );
    expect(caught, isEmpty, reason: 'an error of the stream is not zone news');
    expect(
      journal.lines.where((line) => line.contains('error')).toList(),
      ['[job] error Bad state: source boom'],
    );
  });

  test('an event from an asynchronous onListen reaches no cancelled job', () {
    fakeAsync((async) {
      // The event is delivered after `listen` comes back but before the
      // cancellation reaches the body: only the flag stands between the
      // handler and a job that is already marked.
      final seen = <int>[];
      late StreamController<int> controller;
      late Job<void> job;
      controller = StreamController<int>(
        onListen: () {
          controller.add(1);
          job.cancel().ignore();
        },
      );
      job = Job<void>((ctx) async => ctx.each(controller.stream, seen.add))
        ..ignore();
      async.flushTimers();
      expect(seen, isEmpty);
      expect(job.outcome, isA<Cancelled>());
      controller.close().ignore();
    });
  });

  test('an event after an error of onListen never reaches onData either', () {
    fakeAsync((async) {
      // The same rule as on the ordinary path: after an error of the
      // stream nothing else is delivered.
      final seen = <int>[];
      late StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..addError(StateError('source boom'))
          ..add(2),
      );
      final job = Job<void>((ctx) async {
        await ctx.each(controller.stream, seen.add);
      })
        ..ignore();
      async.flushTimers();
      expect(seen, [1]);
      expect(job.outcome, isA<Failed>());
      controller.close().ignore();
    });
  });
}

/// A stream that counts how many times its subscription is cancelled.
final class _CountingStream<T> extends Stream<T> {
  final Stream<T> _inner;

  /// How many times `cancel()` was called on the subscription.
  int cancels = 0;

  _CountingStream(this._inner);

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _CountingSubscription<T>(
        _inner.listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        ),
        this,
      );
}

final class _CountingSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _inner;
  final _CountingStream<T> _owner;

  _CountingSubscription(this._inner, this._owner);

  @override
  Future<void> cancel() {
    _owner.cancels++;
    return _inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}
