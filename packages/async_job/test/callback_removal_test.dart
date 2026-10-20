import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

import 'support/probe_job.dart';

void main() {
  group('a registration leaves without a search', () {
    // A clock, and not the timeout: everything here ends in microtasks, and
    // no timer of the runner gets a turn until it is over. Measured on
    // 20 000 with the callbacks in a list searched on every removal: 0.9 s,
    // 2.3 s and 5.8 s, test by test; with a chain, under 0.1 s each. The
    // bound sits between the two with room on both sides.
    const count = 20000;
    const bound = 600;

    test('thousands of calls of abandonable in flight in one job', () async {
      final release = Completer<void>();
      final job = Job<int>((ctx) async {
        final values = await [
          for (var i = 0; i < count; i++)
            ctx.abandonable(() async {
              await release.future;
              return i;
            }),
        ].wait;
        return values.length;
      });
      await Future<void>.delayed(Duration.zero);
      final watch = Stopwatch()..start();
      release.complete();
      expect(await job.value, count);
      watch.stop();
      expect(
        watch.elapsedMilliseconds,
        lessThan(bound),
        reason: 'each call takes its cancel callback off without a search',
      );
    });

    test('thousands of listeners taken off in the order they came', () {
      final job = Job<void>((ctx) async {});
      final watch = Stopwatch()..start();
      final finished = [
        for (var i = 0; i < count; i++) job.whenFinished((_) {}),
      ];
      final cancelled = [
        for (var i = 0; i < count; i++) job.whenCancelled((_) {}),
      ];
      for (final remove in [...finished, ...cancelled]) {
        remove();
      }
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(bound));
    });

    test('thousands of onCancel callbacks taken off newest first', () async {
      final done = Completer<int>();
      final job = Job<void>((ctx) async {
        final watch = Stopwatch()..start();
        final removers = [
          for (var i = 0; i < count; i++) ctx.onCancel(() {}),
        ];
        for (final remove in removers.reversed) {
          remove();
        }
        watch.stop();
        done.complete(watch.elapsedMilliseconds);
      });
      expect(await done.future, lessThan(bound));
      await job.done;
    });
  });

  group('a remover takes back its own registration', () {
    test('and no other of the same function', () async {
      // Through the engine's door, which keeps the function as it is given:
      // `onCancel` wraps it, so two registrations there are never equal.
      final calls = <String>[];
      void heard() => calls.add('heard');
      final job = ProbeJob<void>((ctx) async {
        final probe = ctx as ProbeContext;
        final first = probe.onCancelRaw(heard);
        probe.onCancelRaw(heard);
        first();
        first();
        await ctx.abandonable(() => Completer<void>().future);
      })
        ..launch();
      await Future<void>.delayed(Duration.zero);
      await job.cancel();
      expect(calls, ['heard'], reason: 'a second call takes back nothing');
    });

    test('and the others run in the order they came', () async {
      final calls = <int>[];
      final job = Job<void>(
        (ctx) => ctx.abandonable(() => Completer<void>().future),
      );
      final removers = [
        for (var i = 0; i < 5; i++) job.whenCancelled((_) => calls.add(i)),
      ];
      removers[0]();
      removers[2]();
      removers[4]();
      await job.cancel();
      expect(calls, [1, 3]);
    });

    test('and does nothing once the pass is over', () async {
      final calls = <String>[];
      final job = Job<int>((ctx) async => 1);
      final remove = job.whenFinished((_) => calls.add('first'));
      await job.done;
      remove();
      job.whenFinished((_) => calls.add('late'));
      expect(calls, ['first', 'late']);
    });
  });
}
