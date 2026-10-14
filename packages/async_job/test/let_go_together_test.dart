import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

// Alone in a file of its own, and the first test in it: the trouble guarded
// here shows only while the routine of a job has not been optimized yet,
// and any test run before this one in the same isolate would warm it up.
void main() {
  test(
    'thousands of branches let go together end in linear time',
    () async {
      // Under JIT a frame that went to sleep in unoptimized code wakes up in
      // it, and at the header of a loop it asks the VM to replace it with
      // optimized code. A loop where the routine of a job goes on after an
      // `await` made the VM compile the whole routine again for every job
      // that woke up there: two milliseconds or so a job. Here every branch
      // sleeps in its routine three times over — in its body, at the barrier
      // between the passes, and in a cleanup — and wakes up together with
      // the others each time. Measured on this test, 30 000 branches: 40 s
      // with the loops in the routine, 13 s with them in one big local
      // function, under 0.4 s with them in small ones. The bound sits
      // between the last and the others with room on both sides.
      //
      // A clock, and not the timeout: the branches end in microtasks, and no
      // timer of the runner gets a turn until they are over.
      const count = 30000;
      final release = Completer<void>();
      final cleanups = Completer<void>();
      var cleaned = 0;
      final job = Job<List<int>>(
        (ctx) => ctx.runAll([
          for (var i = 0; i < count; i++)
            Job.deferred<int>((ctx) async {
              ctx
                ..onDispose(() => cleaned++)
                ..onDispose(() => cleanups.future);
              await release.future;
              return i;
            }),
        ]),
      );
      // Every body is asleep on the same future before any of them wakes.
      await Future<void>.delayed(Duration.zero);
      final watch = Stopwatch()..start();
      release.complete();
      // And every cleanup on another one.
      await Future<void>.delayed(Duration.zero);
      cleanups.complete();
      final values = await job.value;
      watch.stop();
      expect(values, [for (var i = 0; i < count; i++) i]);
      expect(cleaned, count);
      expect(
        watch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'no frame of a job wakes up at the header of a loop in a '
            'routine as big as the one of a job',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'thousands of jobs whose skipped discards wake together end in linear '
    'time',
    () async {
      // The pass over the `discard` registrations a `Done` skipped, which
      // a cancellation hands back, runs in a function of its own, and no
      // test above reaches it. Every job here sleeps in a cleanup, is
      // cancelled there, and then sleeps in both its discards at once.
      // Measured on 30 000 jobs: 6 to 8.5 s with a loop in that pass,
      // under 0.3 s without.
      const count = 30000;
      final slow = Completer<void>();
      final discards = Completer<void>();
      var discarded = 0;
      final jobs = [
        for (var i = 0; i < count; i++)
          Job<int>((ctx) async {
            ctx
              ..onDispose(() => slow.future)
              ..onDiscard(() async {
                await discards.future;
                discarded++;
              })
              ..onDiscard(() async {
                await discards.future;
                discarded++;
              });
            return i;
          }),
      ];
      // Every job is asleep in its cleanup, both discards skipped.
      await Future<void>.delayed(Duration.zero);
      final watch = Stopwatch()..start();
      for (final job in jobs) {
        job.cancel().ignore();
      }
      slow.complete();
      await Future<void>.delayed(Duration.zero);
      discards.complete();
      await Future.wait([for (final job in jobs) job.done]);
      watch.stop();
      expect(discarded, 2 * count);
      expect(
        watch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'no frame of a job wakes up at the header of a loop in the '
            'pass over its skipped discards',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
