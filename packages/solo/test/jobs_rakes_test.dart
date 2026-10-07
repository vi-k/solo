@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/jobs_first_attempts.dart' as first;
import 'support/jobs_page.dart' as page;
import 'support/jobs_stubs.dart';
import 'support/page_code.dart';
import 'support/readme_quick_start.dart' as quick;
import 'support/test_solo.dart';

/// The first attempts of `doc/jobs.md`, and what each one costs.
///
/// The code of the page stands verbatim in `test/support/jobs_*.dart`: the
/// first attempts and the second attempt of the pause in one file, the
/// versions that work in another. The tests below run that code and pin
/// what the prose, the tables and the comments of the page say about it.
/// The recipes of the page have files of their own: the method that tells
/// whose job it was handed in `droppable_recipe_test.dart`, the pause that
/// works in `queue_pause_recipe_test.dart`.

/// An api of the quick start that answers when the test says so.
final class _Api extends quick.ProfileApi {
  final _answer = Completer<String>();

  @override
  Future<String> fetchName() => _answer.future;

  void answer(String name) => _answer.complete(name);

  void fail(Object error) => _answer.completeError(error);
}

/// Hears the errors and the starts every controller reports.
final class _Watcher extends SoloObserver {
  final errors = <String>[];
  final labels = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      labels.add('${job.key}: ${job.describe()}');

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      errors.add('$job: $error');
}

/// A reason of the caller's own.
final class _Obsolete extends CancelReason {
  const _Obsolete();

  @override
  String get name => 'obsolete';
}

/// A key of the caller's own: two of them are equal when their names are.
@immutable
final class _Named {
  final String name;

  const _Named(this.name);

  @override
  bool operator ==(Object other) => other is _Named && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A new key every time: two `const` ones would be the same object.
_Named _named(String name) => _Named(name);

/// A controller with a group that waits for its accumulation window.
final class _Windows extends Solo<CameraState> with OpenSolo<CameraState> {
  _Windows() : super(const Ready());

  late final _queries = accumulate<Ready, String, void>(
    key: 'search',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
    merge: (previous, incoming) => incoming,
    (ctx, text) async => stage.trace.add('search runs'),
  );

  SoloJob<void> query(String text) => _queries.add(text);

  SoloJob<void> ready() => run<Ready, void>(
        key: 'ready',
        (ctx) async => stage.trace.add('ready runs'),
      );
}

String _page() => File('doc/jobs.md').readAsStringSync();

String _engine() => File('lib/src/solo.dart').readAsStringSync();

/// What [body] prints.
List<String> _printed(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// Runs [body] under fake time, in a zone of its own, and returns the
/// errors that reached that zone. Nothing is asserted inside: an `expect`
/// that failed in there would be one more error of the list.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
    );
    async.flushTimers();
  });
  return errors;
}

void main() {
  setUp(() => stage = Stage());

  tearDown(() {
    Solo.observer = null;
    Solo.errorHandler = null;
    Solo.debug = null;
  });

  group('Jobs and results', () {
    test('the block reads a load that succeeded', () {
      fakeAsync((async) {
        final api = _Api();
        final profile = quick.ProfileController(api);
        final lines = _printed(() {
          unawaited(page.readOutcome(profile));
          async.flushMicrotasks();
          api.answer('Ada');
          async.flushTimers();
        });

        expect(lines, ['loaded Ada']);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('the block reads a load that failed', () {
      fakeAsync((async) {
        final api = _Api();
        final profile = quick.ProfileController(api);
        final lines = _printed(() {
          unawaited(page.readOutcome(profile));
          async.flushMicrotasks();
          api.fail(StateError('no network'));
          async.flushTimers();
        });

        expect(lines, ['not loaded: Bad state: no network']);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('the block reads a load that was cancelled', () {
      fakeAsync((async) {
        final profile = quick.ProfileController(_Api());
        final lines = _printed(() {
          unawaited(page.readOutcome(profile));
          async.flushMicrotasks();
          // The quick start's load is droppable: this is the job the block
          // is waiting for.
          profile.load().cancel().ignore();
          async.flushTimers();
        });

        expect(lines, ['gave up: manual']);
        profile.close().ignore();
        async.flushTimers();
      });
    });

    test('the call queues the work, and no await sets it going', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final job = camera.save();

        expect(job.isQueued, isTrue, reason: 'queued inside the call');
        expect(job.outcome, isNull);

        async.flushTimers();
        expect(stage.trace, ['save begins', 'save ends']);
        expect('${job.outcome}', 'Done(null)', reason: 'nobody awaited it');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the failure of a job reaches the controller with nobody waiting', () {
      late page.CameraController camera;
      _zone((async) {
        camera = page.CameraController();
        stage.saveError = StateError('disk full');
        camera.save();
        async.flushTimers();
        camera.close().ignore();
      });

      expect(camera.hookHeard, ['Job(_Op.save): Bad state: disk full']);
    });

    group('the table', () {
      test('value hands over T, and throws on failure and on cancellation', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          Object? got;
          camera.load('ada').value.then((value) => got = value).ignore();
          async.flushTimers();
          expect('$got', 'Profile(ada)');

          stage.saveError = StateError('disk full');
          Object? failure;
          unawaited(
            camera.save().value.then(
              (_) {},
              onError: (Object error) {
                failure = error;
              },
            ),
          );
          async.flushTimers();
          expect(failure, isA<StateError>());

          Object? cancellation;
          final load = camera.load('ada');
          unawaited(
            load.value.then(
              (_) {},
              onError: (Object error) {
                cancellation = error;
              },
            ),
          );
          async.flushMicrotasks();
          load.cancel().ignore();
          async.flushTimers();
          expect(cancellation, isA<Cancelled>());
          expect(cancellation, same(load.outcome));
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('done hands over the outcome and does not throw', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          stage.saveError = StateError('disk full');
          Outcome<void>? outcome;
          Object? thrown;
          unawaited(
            camera.save().done.then(
              (value) {
                outcome = value;
              },
              onError: (Object error) {
                thrown = error;
              },
            ),
          );
          async.flushTimers();

          expect('$outcome', 'Failed(Bad state: disk full)');
          expect(thrown, isNull);
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('outcome is null until the job has finished', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          final job = camera.save();

          expect(job.outcome, isNull, reason: 'queued');
          async.flushMicrotasks();
          expect(job.isRunning, isTrue);
          expect(job.outcome, isNull, reason: 'running');
          async.flushTimers();
          expect(job.outcome, isA<Done<void>>());
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('cancel() comes back when the job has ended', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          final job = camera.seekWithoutToken(const Duration(seconds: 1));
          async.elapse(const Duration(milliseconds: 200));
          var back = false;
          unawaited(job.cancel().then((_) => back = true));

          async.elapse(const Duration(milliseconds: 700));
          expect(job.isCancelled, isTrue, reason: 'asked at once');
          expect(back, isFalse, reason: 'the device is still seeking');

          async.elapse(const Duration(milliseconds: 200));
          expect(back, isTrue);
          expect('${job.outcome}', 'Cancelled(manual)');
          camera.close().ignore();
          async.flushTimers();
        });
      });

      for (final (name, access, handled) in <(
        String,
        void Function(Job<void> job),
        bool,
      )>[
        ('done', (job) => job.done.ignore(), true),
        ('value', (job) => job.value.ignore(), true),
        ('ignoreFailure()', (job) => job.ignoreFailure(), true),
        ('outcome', (job) => job.outcome, false),
        ('whenCancelled', (job) => job.whenCancelled((_) {}), false),
        ('nothing at all', (job) {}, false),
      ]) {
        test(
            'a failure accessed through $name '
            '${handled ? 'stays out of' : 'reaches'} the zone', () {
          late page.CameraController camera;
          final zone = _zone((async) {
            camera = page.CameraController();
            stage.saveError = StateError('disk full');
            access(camera.save());
            async.flushTimers();
            camera.close().ignore();
          });

          expect(zone, handled ? isEmpty : ['Bad state: disk full']);
          expect(camera.hookHeard, hasLength(1), reason: 'the hook either way');
        });
      }

      test('whenCancelled hears a job cancelled while it runs', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          final job = camera.work('a');
          final heard = <String>[];
          job.whenCancelled((cancelled) => heard.add('$cancelled'));
          async.flushMicrotasks();
          expect(job.isRunning, isTrue);

          job.cancel().ignore();
          expect(heard, ['Cancelled(manual)'], reason: 'as it is accepted');
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('whenCancelled hears a job removed while it is still queued', () {
        fakeAsync((async) {
          final camera = page.CameraController()..work('running');
          async.flushMicrotasks();
          final job = camera.work('queued');
          final heard = <Cancelled>[];
          job.whenCancelled(heard.add);

          camera.queue.remove(job);
          expect(heard.single.started, isFalse);
          expect('${heard.single}', 'Cancelled(manual)');
          camera.close().ignore();
          async.flushTimers();
        });
      });
    });

    test('a failed job does not stop the queue, and its error is reported', () {
      final watcher = _Watcher();
      Solo.observer = watcher;
      late page.CameraController camera;
      late Job<void> failed;
      late Job<void> next;
      final zone = _zone((async) {
        camera = page.CameraController();
        stage.saveError = StateError('disk full');
        failed = camera.save();
        next = camera.work('next');
        async.flushTimers();
        camera.close().ignore();
      });

      expect('${failed.outcome}', 'Failed(Bad state: disk full)');
      expect('${next.outcome}', 'Done(null)');
      expect(stage.trace, ['save begins', 'next starts', 'next ends']);
      // Once to the hook of the controller, once to the observer.
      expect(camera.hookHeard, ['Job(_Op.save): Bad state: disk full']);
      expect(watcher.errors, ['Job(_Op.save): Bad state: disk full']);
      expect(zone, ['Bad state: disk full'], reason: 'nobody accessed it');
    });

    test('closing, removing and the rules end work Cancelled, not failed', () {
      final watcher = _Watcher();
      Solo.observer = watcher;
      late page.CameraController camera;
      final outcomes = <String>[];
      final zone = _zone((async) {
        camera = page.CameraController();
        final running = camera.work('running');
        final removed = camera.work('removed');
        final byRule = camera.run<Ready, void>(
          key: 'by rule',
          canStart: (state) => false,
          (ctx) async {},
        );
        final atClose = camera.work('at close');
        async.flushMicrotasks();
        camera.queue.remove(removed);
        async.elapse(const Duration(milliseconds: 150));
        camera.close().ignore();
        async.flushTimers();
        outcomes.addAll([
          for (final job in [running, removed, byRule, atClose])
            '${job.key} ${job.outcome}',
        ]);
      });

      expect(outcomes, [
        'running Done(null)',
        'removed Cancelled(manual)',
        'by rule Cancelled(rules: canStart)',
        'at close Cancelled(closed)',
      ]);
      expect(camera.hookHeard, isEmpty);
      expect(watcher.errors, isEmpty);
      expect(zone, isEmpty);
    });

    test('the zone is the one the job was created in, not the one of add', () {
      final created = <String>[];
      final added = <String>[];
      fakeAsync((async) {
        late page.CameraController camera;
        late SoloJob<void> job;
        runZonedGuarded(
          () {
            camera = page.CameraController();
            job = camera.job<Ready, void>(
              key: 'made',
              (ctx) async => throw StateError('made failed'),
            );
          },
          (error, stackTrace) => created.add('$error'),
        );
        runZonedGuarded(
          () {
            camera.add(job);
            async.flushTimers();
          },
          (error, stackTrace) => added.add('$error'),
        );
        camera.close().ignore();
        async.flushTimers();
      });

      expect(created, ['Bad state: made failed']);
      expect(added, isEmpty);
    });

    test('an access after the job has ended comes too late', () {
      Outcome<void>? late;
      final zone = _zone((async) {
        final camera = page.CameraController();
        stage.saveError = StateError('disk full');
        final job = camera.save();
        async.elapse(const Duration(milliseconds: 51));
        job.done.then((outcome) => late = outcome).ignore();
        async.flushTimers();
        camera.close().ignore();
      });

      expect('$late', 'Failed(Bad state: disk full)', reason: 'done answers');
      expect(zone, ['Bad state: disk full'], reason: 'and the zone has it');
    });
  });

  group('Creating and scheduling jobs', () {
    test('job assembles, add queues, and the job held on to is the one queued',
        () {
      fakeAsync((async) {
        final assembling = page.Assembling();
        final first = assembling.saveInTwoSteps();
        // A second save queues behind the first: the handle a caller holds
        // on to is always the job that runs.
        final second = assembling.saveInTwoSteps();

        expect(first.isQueued, isTrue);
        expect(second.isQueued, isTrue);
        expect(second.outcome, isNull, reason: 'not dropped as a duplicate');

        async.flushTimers();
        expect('${first.outcome}', 'Done(null)');
        expect('${second.outcome}', 'Done(null)');
        expect(
          stage.trace,
          ['save begins', 'save ends', 'save begins', 'save ends'],
        );
        assembling.close().ignore();
        async.flushTimers();
      });
    });

    test('run does both at once', () {
      fakeAsync((async) {
        final assembling = page.Assembling();
        final job = assembling.setZoom(2);

        expect(job.isQueued, isTrue);
        async.flushMicrotasks();
        expect(job.isQueued, isFalse, reason: 'it runs now');
        expect(job.isRunning, isTrue);
        async.flushTimers();
        expect(stage.trace, ['zoom 2.0 begins', 'zoom 2.0 ends']);
        assembling.close().ignore();
        async.flushTimers();
      });
    });

    test('job, add and run are protected, and so are collect and accumulate',
        () {
      // Only the analyzer sees the annotation: a call from outside the
      // class is reported as `invalid_use_of_protected_member`.
      final engine = _engine();
      for (final member in [
        'SoloJob<T> job<W extends S, T>(',
        'SoloJob<T> add<T>(',
        'SoloJob<T> run<W extends S, T>(',
        'SoloAccumulator<E, T> collect<W extends S, E, T>(',
        'SoloAccumulator<E, T> accumulate<W extends S, E, T>(',
      ]) {
        expect(engine, contains('  @protected\n  $member'), reason: member);
      }
    });

    test('describe is built when somebody asks for the label, not before', () {
      fakeAsync((async) {
        final assembling = page.Assembling();
        var built = 0;
        final job = assembling.run<Ready, void>(
          key: 'lazy',
          describe: () {
            built++;
            return 'label';
          },
          (ctx) async {},
        );
        async.flushTimers();

        expect(built, 0, reason: 'the job ran, and nobody asked');
        expect('$job', 'Job(lazy: label)');
        expect(built, 1);
        assembling.close().ignore();
        async.flushTimers();
      });
    });

    test('toString is Job(key: label), and Job(key) without a description', () {
      fakeAsync((async) {
        final assembling = page.Assembling();

        expect('${assembling.setZoom(2)}', 'Job(_Op.zoom: zoom: 2.0)');
        expect('${assembling.saveInTwoSteps()}', 'Job(_Op.save)');
        assembling.close().ignore();
        async.flushTimers();
      });
    });

    test('a log and an observer read the same label', () {
      fakeAsync((async) {
        final watcher = _Watcher();
        final log = <String>[];
        Solo.observer = watcher;
        Solo.debug = log.add;
        final assembling = page.Assembling()..setZoom(2);
        async.flushTimers();

        expect(log, contains('add Job(_Op.zoom: zoom: 2.0)'));
        expect(watcher.labels, ['_Op.zoom: zoom: 2.0']);
        assembling.close().ignore();
        async.flushTimers();
      });
    });

    test('the first type argument is the states the body works in', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.save();
        final queued = camera.save();
        async.flushMicrotasks();

        camera.externalSetState(const Disconnected());
        async.flushTimers();

        expect('${running.outcome}', 'Cancelled(rules: is not Ready)');
        expect('${queued.outcome}', 'Cancelled(rules: is not Ready)');
        camera.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Queue and policies', () {
    test('only one root job runs at a time', () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('a');
        async.flushMicrotasks();
        // Submitted while the first one runs.
        camera.work('b');
        async.flushMicrotasks();

        expect(camera.runningKey, 'a');
        expect(camera.waiting, ['b']);
        async.flushTimers();
        expect(stage.trace, ['a starts', 'a ends', 'b starts', 'b ends']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('sequential: one after another, in the order asked for', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final jobs = [camera.save(), camera.work('between'), camera.save()];

        expect(jobs.toSet(), hasLength(3), reason: 'nothing is shared');
        async.flushTimers();
        expect(stage.trace, [
          'save begins',
          'save ends',
          'between starts',
          'between ends',
          'save begins',
          'save ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('droppable: a second load of the same profile returns the first job',
        () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('running');
        async.flushMicrotasks();
        final queued = camera.load('ada');

        expect(queued.isQueued, isTrue);
        expect(camera.load('ada'), same(queued), reason: 'while it is queued');

        async.elapse(const Duration(milliseconds: 150));
        expect(queued.isRunning, isTrue);
        expect(camera.load('ada'), same(queued), reason: 'while it runs');

        async.flushTimers();
        expect(
          stage.trace.where((line) => line.startsWith('load')),
          ['load ada begins', 'load ada ends'],
        );
        final later = camera.load('ada');
        expect(later, isNot(same(queued)), reason: 'once that load is over');
        async.flushTimers();
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('replace: the queued zoom goes, a running one is left alone', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.setZoom(1);
        async.flushMicrotasks();
        final queued = camera.setZoom(2);
        final last = camera.setZoom(3);

        expect(
          queued.outcome,
          isA<Cancelled>()
              .having((c) => '$c', 'text', 'Cancelled(replaced)')
              .having((c) => c.reason, 'reason', isA<ReplacedCancelReason>())
              .having((c) => c.started, 'started', isFalse),
          reason: 'removed inside the call',
        );
        expect(running.isCancelled, isFalse);

        async.flushTimers();
        expect('${running.outcome}', 'Done(null)');
        expect('${last.outcome}', 'Done(null)');
        expect(stage.trace, [
          'zoom 1.0 begins',
          'zoom 1.0 ends',
          'zoom 3.0 begins',
          'zoom 3.0 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('replace removes cancellable queued jobs only', () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('running');
        async.flushMicrotasks();
        final kept = camera.run<Ready, void>(
          key: 'k',
          cancellable: false,
          (ctx) async => stage.trace.add('kept runs'),
        );
        final removed = camera.run<Ready, void>(key: 'k', (ctx) async {});
        final replacement = camera.run<Ready, void>(
          key: 'k',
          policy: Policy.replace,
          (ctx) async => stage.trace.add('replacement runs'),
        );

        expect(kept.isQueued, isTrue);
        expect('${removed.outcome}', 'Cancelled(replaced)');
        async.flushTimers();
        expect('${kept.outcome}', 'Done(null)');
        expect('${replacement.outcome}', 'Done(null)');
        expect(
          stage.trace.skip(2),
          ['kept runs', 'replacement runs'],
          reason: 'the new job is enqueued behind it',
        );
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('restart: the same, and the running one is asked to stop as well', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.seek(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 200));
        final queued = camera.seek(const Duration(seconds: 2));
        final last = camera.seek(const Duration(seconds: 3));

        expect(
          '${queued.outcome}',
          'Cancelled(replaced)',
          reason: 'as replace',
        );
        expect(running.isCancelled, isTrue, reason: 'asked as it is submitted');
        expect(running.isFinished, isFalse, reason: 'and not over yet');
        expect(last.isQueued, isTrue);

        async.flushTimers();
        expect(
          running.outcome,
          isA<Cancelled>()
              .having((c) => '$c', 'text', 'Cancelled(replaced)')
              .having((c) => c.reason, 'reason', isA<ReplacedCancelReason>()),
        );
        expect('${last.outcome}', 'Done(null)');
        // The token stopped the device, and the next seek began after that:
        // the two bodies do not overlap.
        expect(stage.trace, [
          'seek 1 begins',
          'token cancelled',
          'seek 1 stopped by its token',
          'seek 3 begins',
          'seek 3 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a root job holds the queue through its children, cleanup and handler',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final holder = camera.run<Ready, void>(
          key: 'holder',
          onError: (state, error, stackTrace) {
            stage.trace.add('the state handler runs');
            return state;
          },
          (ctx) async {
            ctx
              ..onDispose(() async {
                stage.trace.add('the cleanup begins');
                await Future<void>.delayed(const Duration(milliseconds: 50));
                stage.trace.add('the cleanup ends');
              })
              ..run(
                camera.job<Ready, void>(key: 'child', (child) async {
                  stage.trace.add('the child begins');
                  await child.pause(const Duration(milliseconds: 100));
                  stage.trace.add('the child ends');
                }),
              ).ignore();
            stage.trace.add('the body ends');
            throw StateError('failed');
          },
        )..ignoreFailure();
        camera.work('next');
        async.flushTimers();

        expect('${holder.outcome}', 'Failed(Bad state: failed)');
        expect(stage.trace, [
          'the child begins',
          'the body ends',
          'the child ends',
          'the cleanup begins',
          'the cleanup ends',
          'the state handler runs',
          'next starts',
          'next ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    for (final policy in [Policy.droppable, Policy.replace, Policy.restart]) {
      test('${policy.name} does not see a child with the same key', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          late SoloJob<void> child;
          final parent = camera.run<Ready, void>(key: 'parent', (ctx) {
            child = camera.job<Ready, void>(key: 'k', (ctx) async {
              stage.trace.add('the child begins');
              await ctx.pause(const Duration(milliseconds: 100));
              stage.trace.add('the child ends');
            });
            return ctx.run(child);
          });
          async.flushMicrotasks();
          final root = camera.run<Ready, void>(
            key: 'k',
            policy: policy,
            (ctx) async => stage.trace.add('the root job runs'),
          );

          expect(root, isNot(same(child)), reason: 'not handed the child');
          expect(child.isCancelled, isFalse, reason: 'and the child goes on');
          async.flushTimers();
          expect('${child.outcome}', 'Done(null)');
          expect('${parent.outcome}', 'Done(null)');
          expect(stage.trace, [
            'the child begins',
            'the child ends',
            'the root job runs',
          ]);
          camera.close().ignore();
          async.flushTimers();
        });
      });
    }

    test('droppable: a running job that has been cancelled is no duplicate',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final cancelled = camera.load('ada');
        async.flushMicrotasks();
        camera.cancelAll().ignore();
        final again = camera.load('ada');

        expect(again, isNot(same(cancelled)));
        expect(again.isQueued, isTrue, reason: 'a job of its own');
        async.flushTimers();
        expect('${cancelled.outcome}', 'Cancelled(manual)');
        expect('${again.outcome}', 'Done(Profile(ada))');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('restart: the new job waits at the tail, behind what was queued', () {
      fakeAsync((async) {
        final camera = page.CameraController()
          ..seek(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 200));
        camera
          ..work('queued before')
          ..seek(const Duration(seconds: 2));

        expect(camera.waiting, ['queued before', '_Op.seek']);
        async.flushTimers();
        expect(stage.trace, [
          'seek 1 begins',
          'token cancelled',
          'seek 1 stopped by its token',
          'queued before starts',
          'queued before ends',
          'seek 2 begins',
          'seek 2 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a job created with cancellable: false delays its replacement', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final refusing = camera.seekToTheEnd(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 200));
        final next = camera.seek(const Duration(seconds: 2));

        expect(refusing.isCancelled, isFalse, reason: 'it refused');
        async.elapse(const Duration(milliseconds: 790));
        expect(next.isRunning, isFalse, reason: '990 ms, and still waiting');

        async.flushTimers();
        expect('${refusing.outcome}', 'Done(null)');
        expect(stage.trace, [
          'seek 1 begins',
          'seek 1 ends',
          'seek 2 begins',
          'seek 2 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a join around a call the request cannot reach waits the call out',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final replaced = camera.seekWithoutToken(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 200));
        final next = camera.seekWithoutToken(const Duration(seconds: 2));

        async.elapse(const Duration(milliseconds: 790));
        expect(replaced.outcome, isNull, reason: '990 ms: the call goes on');
        expect(next.isRunning, isFalse);

        async.flushTimers();
        expect('${replaced.outcome}', 'Cancelled(replaced)');
        expect(stage.trace, [
          'seek 1 begins',
          'seek 1 ends',
          'seek 2 begins',
          'seek 2 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('ctx.abandonable lets go of an operation that finishes on its own',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final replaced = camera.seekLetGo(const Duration(seconds: 1));
        async.elapse(const Duration(milliseconds: 200));
        final next = camera.seekLetGo(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect('${replaced.outcome}', 'Cancelled(replaced)', reason: 'at once');
        expect(next.isRunning, isTrue);
        async.flushTimers();
        // The first seek ran to its end on the device, beside the second.
        expect(stage.trace, [
          'seek 1 begins',
          'seek 2 begins',
          'seek 1 ends',
          'seek 2 ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('A key for each request', () {
    test('the first attempt: a second load of the same profile shares the job',
        () {
      fakeAsync((async) {
        final camera = first.SharedKeyController();
        final ada = camera.load('ada');

        expect(camera.load('ada'), same(ada), reason: 'as meant');
        async.flushTimers();
        expect(stage.trace, ['load ada begins', 'load ada ends']);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the first attempt: a load of another profile is handed that job too',
        () {
      fakeAsync((async) {
        final camera = first.SharedKeyController();
        final ada = camera.load('ada');
        async.flushMicrotasks();
        final grace = camera.load('grace');

        expect(grace, same(ada), reason: 'a duplicate, to the policy');

        Object? got;
        grace.value.then((profile) => got = profile).ignore();
        async.flushTimers();
        expect('$got', 'Profile(ada)', reason: 'the caller asked for grace');
        expect(
          stage.trace,
          ['load ada begins', 'load ada ends'],
          reason: 'no request for grace',
        );
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the record key: the same profile shares a load, another one loads',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final ada = camera.load('ada');
        async.flushMicrotasks();
        final grace = camera.load('grace');

        expect(camera.load('ada'), same(ada));
        expect(grace, isNot(same(ada)));

        Object? got;
        grace.value.then((profile) => got = profile).ignore();
        async.flushTimers();
        expect('$got', 'Profile(grace)');
        expect(stage.trace, [
          'load ada begins',
          'load ada ends',
          'load grace begins',
          'load grace ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a key is any object, compared with ==', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final job = camera.run<Ready, void>(
          key: _named('k'),
          policy: Policy.droppable,
          (ctx) async {},
        );
        // An equal key, and not the same object.
        final again = camera.run<Ready, void>(
          key: _named('k'),
          policy: Policy.droppable,
          (ctx) async {},
        );
        final other = camera.run<Ready, void>(
          key: _named('another'),
          policy: Policy.droppable,
          (ctx) async {},
        );

        expect(again, same(job));
        expect(other, isNot(same(job)));
        async.flushTimers();
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('run returns one handle and does not say whose job it is', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final mine = camera.load('ada');
        final handed = camera.load('ada');

        // The handle the second call got is the first job, live and well:
        // nothing on it says that a job of the second call was dropped.
        expect(handed, same(mine));
        expect(handed.outcome, isNull);
        expect(handed.isCancelled, isFalse);
        async.flushTimers();
        expect('${handed.outcome}', 'Done(Profile(ada))');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('a key held by another result type throws before the job is taken',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final held = camera.run<Ready, String>(
          key: 'k',
          policy: Policy.droppable,
          (ctx) async => 'held',
        );
        final other = camera.job<Ready, int>(key: 'k', (ctx) async => 1);

        expect(
          () => camera.add(other, policy: Policy.droppable),
          throwsArgumentError,
        );
        expect(camera.waiting, ['k'], reason: 'nothing was queued');
        expect(held.isCancelled, isFalse, reason: 'nothing was cancelled');
        expect(other.outcome, isNull, reason: 'the handle is untouched');

        // The same handle, under Policy.sequential.
        expect(camera.add(other), same(other));
        async.flushTimers();
        expect('${held.outcome}', 'Done(held)');
        expect('${other.outcome}', 'Done(1)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the refused handle can be added later, once the key is free', () {
      fakeAsync((async) {
        final camera = page.CameraController()
          ..run<Ready, String>(
            key: 'k',
            policy: Policy.droppable,
            (ctx) async => 'held',
          );
        final other = camera.job<Ready, int>(key: 'k', (ctx) async => 1);
        expect(
          () => camera.add(other, policy: Policy.droppable),
          throwsArgumentError,
        );

        async.flushTimers();
        expect(camera.add(other, policy: Policy.droppable), same(other));
        async.flushTimers();
        expect('${other.outcome}', 'Done(1)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    for (final policy in [Policy.droppable, Policy.replace, Policy.restart]) {
      test('${policy.name} with a null key throws ArgumentError', () {
        fakeAsync((async) {
          final camera = page.CameraController();
          final keyless = camera.job<Ready, void>((ctx) async {});

          // An `ArgumentError`, not the `AssertionError` of a check that a
          // release build would drop.
          expect(
            () => camera.add(keyless, policy: policy),
            throwsArgumentError,
          );
          expect(camera.add(keyless), same(keyless), reason: 'sequential');
          async.flushTimers();
          camera.close().ignore();
          async.flushTimers();
        });
      });
    }
  });

  group('Working the queue directly', () {
    test('stop() counts what waits, drops the queued zooms, jumps the line',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.setZoom(1);
        async.flushMicrotasks();
        final save = camera.save();
        final queued = camera.setZoom(2);
        late Job<void> stop;
        final lines = _printed(() => stop = camera.stop());

        expect(lines, ['2'], reason: 'a save and a zoom were waiting');
        expect('${queued.outcome}', 'Cancelled(manual)');
        expect(camera.waiting, ['_Op.stop', '_Op.save']);
        // The zoom that runs is neither removed nor interrupted.
        expect(running.isCancelled, isFalse);

        async.flushTimers();
        expect('${running.outcome}', 'Done(null)');
        expect('${stop.outcome}', 'Done(null)');
        expect('${save.outcome}', 'Done(null)');
        expect(stage.trace, [
          'zoom 1.0 begins',
          'zoom 1.0 ends',
          'stop begins',
          'stop ends',
          'save begins',
          'save ends',
        ]);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('queue shows jobs, length, isEmpty and isNotEmpty', () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('running');
        async.flushMicrotasks();

        expect(camera.queue.isEmpty, isTrue, reason: 'the running one is out');
        expect(camera.queue.isNotEmpty, isFalse);
        expect(camera.queue.length, 0);

        final a = camera.work('a');
        final b = camera.work('b');
        expect(camera.queue.jobs, [a, b]);
        expect(camera.queue.length, 2);
        expect(camera.queue.isEmpty, isFalse);
        expect(camera.queue.isNotEmpty, isTrue);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('lastJobWhere: the last queued job that passes, else the running one',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.work('a');
        async.flushMicrotasks();

        expect(camera.lastJobWhere((job) => job.key == 'a'), same(running));

        camera.work('a');
        final last = camera.work('a');
        expect(camera.lastJobWhere((job) => job.key == 'a'), same(last));
        expect(camera.lastJobWhere((job) => job.key == 'none'), isNull);
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('remove, removeWhere and clear touch queued jobs only', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.work('running');
        async.flushMicrotasks();
        final a = camera.work('a');
        final b = camera.work('b');
        final c = camera.work('c');

        expect(camera.queue.remove(running), isFalse);
        expect(camera.queue.remove(a), isTrue);
        expect(camera.queue.removeWhere((job) => job.key == 'b'), 1);
        expect(camera.queue.clear(), 1);
        for (final job in [a, b, c]) {
          expect('${job.outcome}', 'Cancelled(manual)');
        }
        expect(running.isCancelled, isFalse);

        async.flushTimers();
        expect('${running.outcome}', 'Done(null)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('they keep a job created with cancellable: false unless forced', () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('running');
        async.flushMicrotasks();
        final kept = camera.run<Ready, void>(
          key: 'kept',
          cancellable: false,
          (ctx) async {},
        );

        expect(camera.queue.remove(kept), isFalse);
        expect(camera.queue.removeWhere((job) => true), 0);
        expect(camera.queue.clear(), 0);
        expect(kept.isQueued, isTrue);

        expect(camera.queue.clear(force: true), 1);
        expect('${kept.outcome}', 'Cancelled(manual)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('what they remove carries the reason the caller passes', () {
      fakeAsync((async) {
        final camera = page.CameraController()..work('running');
        async.flushMicrotasks();
        final a = camera.work('a');
        final b = camera.work('b');
        final c = camera.work('c');
        camera.queue
          ..remove(a, reason: const _Obsolete())
          ..removeWhere((job) => job.key == 'b', reason: const _Obsolete())
          ..clear(reason: const _Obsolete());

        for (final job in [a, b, c]) {
          expect('${job.outcome}', 'Cancelled(obsolete)');
        }
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('cancelAll clears the queue, cancels the running job, takes a reason',
        () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final running = camera.work('running');
        async.flushMicrotasks();
        final queued = camera.work('queued');
        camera.cancelAll(reason: const _Obsolete()).ignore();
        async.flushTimers();

        expect('${running.outcome}', 'Cancelled(obsolete)');
        expect('${queued.outcome}', 'Cancelled(obsolete)');
        expect(stage.trace, ['running starts'], reason: 'neither went on');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    test('the head of jobs is not always what starts next', () {
      fakeAsync((async) {
        final windows = _Windows()
          ..query('a')
          ..ready();

        expect(
          [for (final job in windows.queue.jobs) job.key],
          ['search', 'ready'],
        );
        async.flushMicrotasks();
        expect(stage.trace, ['ready runs'], reason: 'it passed the group');
        expect([for (final job in windows.queue.jobs) job.key], ['search']);

        async.elapse(const Duration(milliseconds: 201));
        expect(stage.trace, ['ready runs', 'search runs']);
        windows.close().ignore();
        async.flushTimers();
      });
    });
  });

  group('Pausing the queue', () {
    test('a job ends Cancelled when the state leaves its working type', () {
      fakeAsync((async) {
        final camera = page.CameraController();
        final inReady = camera.work('in Ready', inReady: true);
        async.flushMicrotasks();
        camera.externalSetState(const Disconnected());
        async.flushTimers();

        expect('${inReady.outcome}', 'Cancelled(rules: is not Ready)');
        camera.close().ignore();
        async.flushTimers();
      });
    });

    group('the first attempt', () {
      test('a job that waits on a Completer holds the queue', () {
        fakeAsync((async) {
          final camera = first.TailGateController()..pause();
          async.flushMicrotasks();
          final jobs = [camera.work('a'), camera.work('b')];
          async.elapse(const Duration(seconds: 1));

          expect(camera.runningKey, '_Op.pause');
          expect(camera.waiting, ['a', 'b']);
          expect([for (final job in jobs) job.outcome], [null, null]);

          camera.resume();
          async.flushTimers();
          expect(stage.trace, ['a starts', 'a ends', 'b starts', 'b ends']);
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('three jobs already waiting run before the pause begins', () {
        fakeAsync((async) {
          final camera = first.TailGateController()..work('running');
          async.flushMicrotasks();
          final jobs = [camera.work('a'), camera.work('b'), camera.work('c')];
          camera.pause();
          final after = camera.work('after');

          expect(camera.waiting, ['a', 'b', 'c', '_Op.pause', 'after']);
          async.elapse(const Duration(seconds: 1));
          expect(
            [for (final job in jobs) '${job.outcome}'],
            ['Done(null)', 'Done(null)', 'Done(null)'],
          );
          // Only what was submitted after `pause()` waits behind the gate.
          expect(camera.runningKey, '_Op.pause');
          expect(after.outcome, isNull);
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('after cancelAll the field stays set while the queue runs', () {
        fakeAsync((async) {
          final camera = first.TailGateController()..pause();
          async.flushMicrotasks();
          camera.cancelAll().ignore();
          async.flushMicrotasks();

          expect(camera.runningKey, isNull, reason: 'the gate is gone');
          expect(camera.isPaused, isTrue, reason: 'and the field is not');

          final job = camera.work('a');
          async.flushTimers();
          expect('${job.outcome}', 'Done(null)', reason: 'the queue runs');
          expect(camera.isPaused, isTrue);

          // The next pause returns at its first line.
          camera.pause();
          expect(camera.waiting, isEmpty);
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('close cancels the gate as well, and the field stays set', () {
        fakeAsync((async) {
          final camera = first.TailGateController()..pause();
          async.flushMicrotasks();
          var closed = false;
          unawaited(camera.close().then((_) => closed = true));
          async.flushTimers();

          expect(closed, isTrue, reason: 'without a resume');
          expect(camera.isPaused, isTrue);
        });
      });
    });

    group('the second attempt', () {
      test('what is already queued waits along with what comes later', () {
        fakeAsync((async) {
          final camera = first.BodyGateController()..work('running');
          async.flushMicrotasks();
          final jobs = [camera.work('a'), camera.work('b'), camera.work('c')];
          camera.pause();
          final after = camera.work('after');

          expect(camera.waiting, ['_Op.pause', 'a', 'b', 'c', 'after']);
          async.elapse(const Duration(seconds: 1));
          expect(camera.runningKey, '_Op.pause');
          for (final job in [...jobs, after]) {
            expect(job.outcome, isNull, reason: '${job.key} waits');
          }
          camera.close().ignore();
          async.flushTimers();
        });
      });

      test('a gate cancelled while it runs clears the field', () {
        fakeAsync((async) {
          final camera = first.BodyGateController()..pause();
          async.flushMicrotasks();
          camera.cancelAll().ignore();
          async.flushMicrotasks();

          expect(camera.isPaused, isFalse);
          camera.pause();
          async.flushMicrotasks();
          expect(camera.runningKey, '_Op.pause', reason: 'it pauses again');
          camera.close().ignore();
          async.flushTimers();
          expect(camera.isPaused, isFalse, reason: 'close cleared it too');
        });
      });

      for (final (name, take) in <(
        String,
        void Function(first.BodyGateController camera),
      )>[
        ('queue.clear()', (camera) => camera.queue.clear()),
        ('cancelAll()', (camera) => camera.cancelAll().ignore()),
      ]) {
        test('$name while the gate waits its turn leaves the field set', () {
          fakeAsync((async) {
            final camera = first.BodyGateController()..work('running');
            async.flushMicrotasks();
            camera.pause();
            expect(camera.waiting, ['_Op.pause']);

            take(camera);
            async.flushTimers();
            expect(camera.waiting, isEmpty, reason: 'the gate is gone');
            expect(camera.isPaused, isTrue, reason: 'no callback to clear it');

            // `isPaused` says true over a queue that runs, and the next
            // pause does nothing.
            camera.pause();
            final job = camera.work('a');
            async.flushTimers();
            expect('${job.outcome}', 'Done(null)');
            expect(camera.isPaused, isTrue);
            camera.close().ignore();
            async.flushTimers();
          });
        });
      }

      test('close() while the gate waits its turn leaves the field set', () {
        fakeAsync((async) {
          final camera = first.BodyGateController()..work('running');
          async.flushMicrotasks();
          camera.pause();
          camera.close().ignore();
          async.flushTimers();

          expect(camera.isFinished, isTrue);
          expect(camera.isPaused, isTrue);
        });
      });
    });
  });

  group('The page', () {
    test('two sections open with a first attempt, as the introduction says',
        () {
      final attempts = RegExp(r'^#### The first attempt$', multiLine: true)
          .allMatches(_page())
          .length;
      expect(attempts, 2);
      expect(
        _page(),
        contains('Two sections below open with the version'),
      );
    });

    test('one of them goes on to a second attempt', () {
      expect(
        RegExp(r'^#### The second attempt$', multiLine: true)
            .allMatches(_page()),
        hasLength(1),
      );
    });

    test('has no fence the checks do not read', () {
      expect(strayFences('doc/jobs.md'), isEmpty);
    });

    // Each version under its own file: an answer turned into its own first
    // attempt would still be found among all of them.
    const answers = 'test/support/jobs_page.dart';
    const firstAttempts = 'test/support/jobs_first_attempts.dart';
    const holders = {
      '## Jobs and results': answers,
      '### Creating and scheduling jobs': answers,
      '## Queue and policies': answers,
      '#### The first attempt': firstAttempts,
      '#### The record key': answers,
      '### Working the queue directly': answers,
      '#### The second attempt': firstAttempts,
      '#### The handle of the gate': answers,
    };
    for (final MapEntry(key: heading, value: holder) in holders.entries) {
      test('the code under "$heading" is a run of lines of $holder', () {
        expect(
          codeMissingFrom('doc/jobs.md', holder, under: heading),
          isEmpty,
        );
      });
    }

    test('every piece of code on the page is a run of lines of these files',
        () {
      expect(
        codeMissingFrom('doc/jobs.md', answers, alsoIn: [firstAttempts]),
        isEmpty,
      );
    });

    test('every heading with code under it is held to a file', () {
      final withCode = [
        for (final part in _page().split(RegExp('^(?=#)', multiLine: true)))
          if (part.contains('```dart')) part.split('\n').first,
      ];
      expect(withCode.toSet(), holders.keys.toSet());
    });
  });
}

extension on Job<Object?> {
  /// The methods of the page declare `Job<T>`; whether the job still waits
  /// in the queue is on the `SoloJob<T>` the controller made.
  bool get isQueued => (this as SoloJob<Object?>).isQueued;
}
