@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

// A continuation, a handle of `shared()` and a child of `ctx.each` take a
// `key` and a `describe` as any job does; without a `describe` they are
// described by the member that made them.

/// Keeps the key of every job it hears an error of, and answers for it.
final class Keys extends JobObserver with JobAnswerer {
  final heard = <String>[];

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      heard.add('${job.key}: ${error.runtimeType}');

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}

String describedBy() => 'by hand';

void main() {
  group('the name of', () {
    test('a continuation', () {
      String name({Object? key, String Function()? describe}) {
        final source = Job<int>((ctx) async => 1);
        final then = source.then(
          (ctx, value) => value,
          key: key,
          describe: describe,
        );
        unawaited(then.done);
        return '$then';
      }

      expect(name(), 'Job(then)');
      expect(name(key: 'load'), 'Job(load: then)');
      expect(name(describe: describedBy), 'Job(by hand)');
      expect(name(key: 'load', describe: describedBy), 'Job(load: by hand)');
    });

    test('a handle of shared()', () {
      String name({Object? key, String Function()? describe}) {
        final handle =
            Job<int>((ctx) async => 1).shared(key: key, describe: describe);
        unawaited(handle.done);
        return '$handle';
      }

      expect(name(), 'Job(shared)');
      expect(name(key: 'load'), 'Job(load: shared)');
      expect(name(describe: describedBy), 'Job(by hand)');
      expect(name(key: 'load', describe: describedBy), 'Job(load: by hand)');
    });

    test('a child of ctx.each', () {
      fakeAsync((async) {
        final names = <String>[];
        void name(JobContext ctx, {Object? key, String Function()? describe}) {
          final child = ctx.each(
            const Stream<int>.empty(),
            key: key,
            describe: describe,
            (ctx, _) {},
          );
          names.add('$child');
        }

        Job<void>((ctx) async {
          name(ctx);
          name(ctx, key: 'events');
          name(ctx, describe: describedBy);
          name(ctx, key: 'events', describe: describedBy);
        });
        async.flushMicrotasks();
        expect(names, [
          'Job(each)',
          'Job(events: each)',
          'Job(by hand)',
          'Job(events: by hand)',
        ]);
      });
    });
  });

  test('the key of a continuation reaches its observer with the error', () {
    fakeAsync((async) {
      final keys = Keys();
      Job<int>((ctx) async => throw StateError('load'))
          .then((ctx, value) => value, key: 'length', observer: keys);
      async.flushMicrotasks();
      expect(keys.heard, ['length: StateError']);
    });
  });
}
