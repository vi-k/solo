@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

/// The first attempts of `doc/observing.md`, and what each one costs.
///
/// A section of the page opens with the version the names lead to and shows
/// what that version prints. The page has no bench, so the code is repeated
/// here as it stands there, and the last test holds the lines the page
/// quotes to the lines these tests print.

/// What each `text` block of the page says, in the order of the page.
const quoted = [
  [
    'outcome: Done(null)',
    'zone: Bad state: analytics offline',
  ],
  [
    'outcome: Done(null)',
    'onError: Bad state: analytics offline',
  ],
];

/// What the observer and the code around the job print.
final printed = <String>[];

void say(String line) => printed.add(line);

final class Analytics {
  Future<void> send(String event) async {
    await delay(10);
    throw StateError('analytics offline');
  }
}

/// The observer of the page's jobs: it prints what reaches it.
final class PrintingObserver extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      say('onError: $error');
}

final analytics = Analytics();

/// Runs [body] as a job, with the page's observer unless [observed] is
/// false, and returns what was printed. An error that reaches the zone is
/// printed as `zone:`.
List<String> play<T>(
  Future<T> Function(JobContext ctx) body, {
  bool observed = true,
}) {
  printed.clear();
  runZonedGuarded(
    () => fakeAsync((async) {
      final job = Job<T>(body, observer: observed ? PrintingObserver() : null);
      unawaited(job.done.then((outcome) => say('outcome: $outcome')));
      async.flushTimers();
    }),
    (error, stackTrace) => say('zone: $error'),
  );
  return printed.toList();
}

void main() {
  group('Work the job does not wait for', () {
    test('unawaited sends the failure past the observer to the zone', () {
      final lines = play((ctx) async {
        unawaited(analytics.send('loaded'));
      });

      expect(lines, quoted[0]);
    });

    test('unattended hands it to the observer, after the job is over', () {
      final lines = play((ctx) async {
        ctx.unattended(() => analytics.send('loaded'));
      });

      expect(lines, quoted[1]);
    });

    test('without an observer unattended goes to the creation zone', () {
      final lines = play(
        (ctx) async {
          ctx.unattended(() => analytics.send('loaded'));
        },
        observed: false,
      );

      expect(lines, quoted[0]);
    });

    test('a future made outside never comes back in there', () {
      final lines = play((ctx) async {
        final sending = analytics.send('loaded');
        ctx.unattended(() async {
          try {
            await sending;
          } on Object catch (error) {
            say('caught: $error');
          }
        });
      });

      expect(lines, [
        'outcome: Done(null)',
        'zone: Bad state: analytics offline',
      ]);
    });

    test('a future made in there hangs the job that awaits it', () {
      final lines = play((ctx) async {
        late Future<void> sending;
        ctx.unattended(() {
          sending = analytics.send('loaded');
        });
        try {
          await ctx.wait(() => sending);
        } on Object catch (error) {
          say('caught: $error');
        }
      });

      expect(lines, ['onError: Bad state: analytics offline']);
    });
  });

  test('the page quotes what these tests print', () {
    final page = File('doc/observing.md').readAsStringSync();
    final blocks = RegExp(r'```text\n(.*?)\n```', dotAll: true)
        .allMatches(page)
        .map((match) => match.group(1)!.split('\n'))
        .toList();

    expect(blocks, quoted);
  });
}
