@Timeout(Duration(seconds: 10))
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The first attempts of `doc/testing.md`, and what each one costs.
///
/// Seven sections of the page open with the test its vocabulary leads to —
/// assert after the call, close the controller to let the work finish,
/// await inside `fakeAsync`, assert inside the zone — and each one is run
/// here, together with the version that works.
///
/// The page has no bench: its fragments are tests of an application, not a
/// program that runs. So the fixtures below are the page's, down to the
/// twenty milliseconds of the fake API, and every claim the page makes
/// about where a value, a failure or a line of the journal ends up is
/// guarded here.

// --- The application under test -------------------------------------------

sealed class ProfileState {}

final class Initial implements ProfileState {
  const Initial();
}

final class Loading implements ProfileState {
  const Loading();
}

final class Loaded implements ProfileState {
  const Loaded(this.name);

  final String name;
}

final class Failure implements ProfileState {
  const Failure(this.error);

  final Object error;
}

/// The page's fake: an answer after twenty milliseconds, or an error.
class FakeProfileApi {
  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

  final String name;
  final Object? error;

  int started = 0;
  int finished = 0;

  Future<String> fetchName() async {
    started++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    finished++;
    final error = this.error;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return name;
  }
}

/// The controller of the quick start.
final class ProfileController extends Solo<ProfileState> {
  ProfileController(this.api) : super(const Initial());

  final FakeProfileApi api;

  /// How many times `onCancel` ran; the page has no use for the count.
  int cancels = 0;

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) {
          cancels++;
          return const Initial();
        },
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  /// The first attempt of the timeouts section: a deadline on the call.
  Job<String> loadWithTimeout() => run<ProfileState, String>(
        key: 'load',
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(
            () => api.fetchName().timeout(const Duration(milliseconds: 5)),
          );
          ctx.emit(Loaded(name));
          return name;
        },
      );
}

/// The page's observer, with the lines collected instead of printed.
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}

// --- The device of the timeouts section -----------------------------------

sealed class CameraState {}

final class Idle implements CameraState {
  const Idle();
}

final class Connected implements CameraState {
  const Connected();
}

/// A token the way a device SDK offers one: cancelling it fails the call.
class CancelToken {
  final _callbacks = <void Function()>[];

  bool isCancelled = false;

  void whenCancelled(void Function() callback) {
    if (isCancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }

  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
  }
}

/// A camera that opens only when the test says so.
class FakeCamera {
  Completer<void>? _opening;

  bool isOpen = false;
  int refused = 0;

  Future<void> open({required CancelToken cancelToken}) {
    final opening = _opening = Completer<void>();
    cancelToken.whenCancelled(() {
      if (opening.isCompleted) return;
      refused++;
      opening.completeError(StateError('open cancelled'), StackTrace.current);
    });
    return opening.future;
  }

  /// The device answers the call that is waiting.
  void answer() {
    final opening = _opening;
    if (opening == null || opening.isCompleted) return;
    isOpen = true;
    opening.complete();
  }
}

final class CameraController extends Solo<CameraState> {
  CameraController(this.hw) : super(const Idle());

  final FakeCamera hw;

  Job<void> connect() => run<Idle, void>(
        key: 'connect',
        (ctx) async {
          final token = CancelToken();
          final timer = Timer(const Duration(seconds: 5), token.cancel);
          ctx.onCancel(token.cancel);
          try {
            await ctx.join(() => hw.open(cancelToken: token));
          } finally {
            timer.cancel();
          }
          ctx.emit(const Connected());
        },
      );
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
  });

  // --- Awaiting a job -----------------------------------------------------

  group('awaiting a job', () {
    test('the state right after the call is still the initial one', () async {
      final profile = ProfileController(FakeProfileApi());

      final job = profile.load();

      expect(profile.currentState, isA<Initial>());
      expect(job.outcome, isNull);
      expect(job.isRunning, isFalse);

      await job.done;
      await profile.close();
    });

    test('the outcome and the state arrive together', () async {
      final profile = ProfileController(FakeProfileApi());

      final outcome = await profile.load().done;

      expect(outcome, isA<Done<String>>());
      expect(
        profile.currentState,
        isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
      );

      await profile.close();
    });

    test('a test that awaits waits the fake out for real', () async {
      final profile = ProfileController(FakeProfileApi());
      final started = clock.now();

      await profile.load().done;

      expect(
        clock.now().difference(started),
        greaterThanOrEqualTo(const Duration(milliseconds: 20)),
      );

      await profile.close();
    });

    test('value returns the name the body returned', () async {
      final profile = ProfileController(FakeProfileApi());

      expect(await profile.load().value, 'Ada Lovelace');

      await profile.close();
    });

    test('value throws what the body threw', () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      );

      await expectLater(profile.load().value, throwsA(isA<StateError>()));
      expect(
        profile.currentState,
        isA<Failure>()
            .having((state) => state.error, 'error', isA<StateError>()),
      );

      await profile.close();
    });

    test('a cancelled load ends Cancelled', () async {
      final profile = ProfileController(FakeProfileApi());
      final job = profile.load();

      await job.cancel();

      expect(
        await job.done,
        isA<Cancelled>()
            .having((outcome) => outcome.started, 'started', isFalse),
      );
      expect(profile.currentState, isA<Initial>());
      expect(profile.cancels, 0);

      await profile.close();
    });

    test('value of a cancelled job throws, done does not', () async {
      final profile = ProfileController(FakeProfileApi());
      final job = profile.load();

      await job.cancel();

      expect(await job.done, isA<Cancelled>());
      await expectLater(job.value, throwsA(isA<Cancelled>()));
      expect(profile.cancels, 0);

      await profile.close();
    });
  });

  // --- Closing the controller ---------------------------------------------

  group('closing the controller', () {
    test('close cancels the load it finds running', () async {
      final profile = ProfileController(FakeProfileApi());
      final job = profile.load();
      await pumpEventQueue();
      expect(profile.currentState, isA<Loading>());

      await profile.close();

      expect(job.outcome, isA<Cancelled>());
      expect('${job.outcome}', 'Cancelled(closed)');
      expect(profile.currentState, isA<Initial>());
      expect(profile.cancels, 1);
      expect(profile.api.finished, 0);
    });

    test('close drops a load that has not left the queue', () async {
      final profile = ProfileController(FakeProfileApi());
      final job = profile.load();

      await profile.close();

      expect('${job.outcome}', 'Cancelled(closed)');
      expect(profile.currentState, isA<Initial>());
      expect(profile.cancels, 0);
      expect(profile.api.started, 0);
    });

    test('a drain lets it finish', () async {
      final profile = ProfileController(FakeProfileApi());
      final job = profile.load();

      await profile.close(mode: SoloCloseMode.drain);

      expect(job.outcome, isA<Done<String>>());
      expect(profile.currentState, isA<Loaded>());
    });
  });

  // --- A failure nobody read ----------------------------------------------

  group('a failure nobody read', () {
    test('it reaches the zone the job was created in', () async {
      final zoneErrors = <Object>[];
      late ProfileState state;

      await runZonedGuarded(
        () async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          )..load();
          await profile.close(mode: SoloCloseMode.drain);
          state = profile.currentState;
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(state, isA<Failure>());
      expect(zoneErrors, [isA<StateError>()]);
    });

    test('reading done keeps it out of the zone', () async {
      final zoneErrors = <Object>[];
      late Outcome<String> outcome;

      await runZonedGuarded(
        () async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          outcome = await profile.load().done;
          await profile.close();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(outcome, isA<Failed>());
      expect(zoneErrors, isEmpty);
    });

    test('ignore keeps it out of the zone as well', () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          profile.load().ignore();
          await profile.close(mode: SoloCloseMode.drain);
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, isEmpty);
    });

    test('reading outcome is not reading the job', () {
      final zoneErrors = <Object>[];
      Outcome<String>? outcome;

      runZonedGuarded(
        () => fakeAsync((async) {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          final job = profile.load();
          async.elapse(const Duration(milliseconds: 20));
          outcome = job.outcome;
          profile.close();
          async.flushTimers();
        }),
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(outcome, isA<Failed>());
      expect(zoneErrors, [isA<StateError>()]);
    });

    test('inside fakeAsync ignore is what marks it observed', () {
      final zoneErrors = <Object>[];
      Outcome<String>? outcome;

      runZonedGuarded(
        () => fakeAsync((async) {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          );
          final job = profile.load()..ignore();
          async.elapse(const Duration(milliseconds: 20));
          outcome = job.outcome;
          profile.close();
          async.flushTimers();
        }),
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(outcome, isA<Failed>());
      expect(zoneErrors, isEmpty);
    });
  });

  // --- The order of what happened -----------------------------------------

  group('the order of what happened', () {
    test('two calls in one turn drop the duplicate before the start', () {
      fakeAsync((async) {
        final journal = Journal();
        Solo.observer = journal;
        final profile = ProfileController(FakeProfileApi());

        final first = profile.load();
        final second = profile.load();

        expect(identical(first, second), isTrue);
        expect(journal.lines, ['load Cancelled(manual: duplicate)']);

        async.elapse(const Duration(milliseconds: 20));

        expect(journal.lines, [
          'load Cancelled(manual: duplicate)',
          'load started',
          'state: Loading',
          'state: Loaded',
          'load Done(Ada Lovelace)',
        ]);

        profile.close();
        async.flushTimers();
      });
    });

    test('a flush between the calls lets the first one start', () {
      fakeAsync((async) {
        final journal = Journal();
        Solo.observer = journal;
        final profile = ProfileController(FakeProfileApi());

        final first = profile.load();
        async.flushMicrotasks();
        final second = profile.load();

        expect(identical(first, second), isTrue);

        async.elapse(const Duration(milliseconds: 20));

        expect(journal.lines, [
          'load started',
          'state: Loading',
          'load Cancelled(manual: duplicate)',
          'state: Loaded',
          'load Done(Ada Lovelace)',
        ]);

        profile.close();
        async.flushTimers();
      });
    });
  });

  // --- Awaiting inside fakeAsync ------------------------------------------

  group('awaiting inside fakeAsync', () {
    test('an async callback never gets past its first await', () async {
      var reached = false;

      final returned = fakeAsync((async) async {
        final profile = ProfileController(FakeProfileApi());
        await profile.load().done;
        reached = true;
        await profile.close();
      });

      await expectLater(
        returned.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      expect(reached, isFalse);
    });

    test('elapse takes the place of the await', () {
      fakeAsync((async) {
        final profile = ProfileController(FakeProfileApi());

        final job = profile.load()..ignore();
        async.elapse(const Duration(milliseconds: 20));

        expect(job.outcome, isA<Done<String>>());
        expect(profile.currentState, isA<Loaded>());

        profile.close();
        async.flushTimers();

        expect(async.pendingTimers, isEmpty);
      });
    });

    test('elapse moves the clock along with the timers', () {
      fakeAsync((async) {
        final before = clock.now();

        async.elapse(const Duration(seconds: 3));

        expect(clock.now().difference(before), const Duration(seconds: 3));
      });
    });

    test('a cancellation lands on the next microtask', () {
      fakeAsync((async) {
        final profile = ProfileController(FakeProfileApi());
        final job = profile.load();
        async.flushMicrotasks();

        job.cancel().ignore();

        expect(job.outcome, isNull);
        async.flushMicrotasks();
        expect('${job.outcome}', 'Cancelled(manual)');

        profile.close();
        async.flushTimers();
      });
    });
  });

  // --- What one test leaves for the next ----------------------------------

  group('what one test leaves for the next', () {
    test('a failing expectation skips the line under it', () {
      var reset = false;

      expect(
        () {
          expect(1 + 1, 3);
          reset = true;
        },
        throwsA(isA<TestFailure>()),
      );

      expect(reset, isFalse);
    });

    test('one observer serves every controller in the process', () async {
      final journal = Journal();
      Solo.observer = journal;
      final first = ProfileController(FakeProfileApi());
      final second = ProfileController(FakeProfileApi());

      await first.load().done;
      await second.load().done;

      expect(
        journal.lines.where((line) => line == 'load started').length,
        2,
      );

      await first.close();
      await second.close();
    });
  });

  // --- Assertions inside a zone -------------------------------------------

  group('assertions inside a zone', () {
    test('a failed expectation inside the zone is caught by the zone', () {
      final zoneErrors = <Object>[];
      var returned = false;

      runZonedGuarded(
        () {
          expect(1 + 1, 3);
          returned = true;
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, [isA<TestFailure>()]);
      expect(returned, isFalse);
    });

    test('collected in the zone, asserted outside it', () async {
      final zoneErrors = <Object>[];

      await runZonedGuarded(
        () async {
          final profile = ProfileController(
            FakeProfileApi(error: StateError('no network')),
          )..load();
          await profile.close(mode: SoloCloseMode.drain);
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, [isA<StateError>()]);
    });
  });

  // --- Timeouts -----------------------------------------------------------

  group('timeouts', () {
    test('a timeout ends the job while the call goes on', () async {
      final api = FakeProfileApi();
      final profile = ProfileController(api);

      final outcome = await profile.loadWithTimeout().done;

      expect(outcome, isA<Failed>());
      expect(
        (outcome as Failed).error,
        isA<TimeoutException>(),
      );
      expect(api.started, 1);
      expect(api.finished, 0);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(api.finished, 1);

      await profile.close();
    });

    test('a timer wired to the device stops the call', () {
      fakeAsync((async) {
        final hw = FakeCamera();
        final camera = CameraController(hw);

        final job = camera.connect()..ignore();
        async.elapse(const Duration(seconds: 4));

        expect(job.outcome, isNull);
        expect(hw.refused, 0);

        async.elapse(const Duration(seconds: 2));

        expect(job.outcome, isA<Failed>());
        expect(hw.refused, 1);
        expect(hw.isOpen, isFalse);
        expect(camera.currentState, isA<Idle>());

        camera.close();
        async.flushTimers();
      });
    });

    test('cancelling the job stops the device too', () {
      final zoneErrors = <Object>[];
      FakeCamera? camera;
      Outcome<void>? outcome;

      runZonedGuarded(
        () => fakeAsync((async) {
          final hw = camera = FakeCamera();
          final controller = CameraController(hw);
          final job = controller.connect()..ignore();
          async.flushMicrotasks();

          job.cancel().ignore();
          async.flushMicrotasks();

          outcome = job.outcome;
          expect(async.pendingTimers, isEmpty);
          controller.close();
          async.flushTimers();
        }),
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(camera?.refused, 1);
      expect(outcome, isA<Cancelled>());
      expect(zoneErrors, isEmpty);
    });

    test('the timer goes away when the device answers first', () {
      fakeAsync((async) {
        final hw = FakeCamera();
        final camera = CameraController(hw);

        final job = camera.connect()..ignore();
        async.elapse(const Duration(seconds: 1));
        hw.answer();
        async.flushMicrotasks();

        expect(job.outcome, isA<Done<void>>());
        expect(camera.currentState, isA<Connected>());
        expect(async.pendingTimers, isEmpty);

        camera.close();
        async.flushTimers();
      });
    });
  });
}
