@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support/children_stubs.dart' as stubs;
import 'support/delay.dart';
import 'support/page_code.dart';
import 'support/streams_page.dart' as page;

/// The first attempts of `doc/streams.md`, and what each one costs.
///
/// The page has no bench: its code stands verbatim in
/// `support/streams_page.dart`, on the stubs it shares with the page on
/// children, and the tests below run it. Every claim the page makes about a
/// first attempt is pinned here, next to the version it then shows.
void main() {
  group('The code of the page', () {
    setUp(() => stubs.stage = stubs.Stage());

    List<String> trace() => stubs.stage.trace;

    test('each in a body saves one message after the other', () {
      fakeAsync((async) {
        final job = page.eachInABody();
        stubs.stage.messages
          ..add('m1')
          ..add('m2');
        async.flushTimers();
        expect(trace(), [
          'm1: body begins',
          'm1: body saved',
          'm2: body begins',
          'm2: body saved',
        ]);
        expect(job.isFinished, isFalse, reason: 'the stream is still open');
        stubs.stage.messages.close().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
      });
    });

    test('each in a body, cancelled while the stream is silent', () {
      fakeAsync((async) {
        final job = page.eachInABody()..ignore();
        stubs.stage.messages.add('m1');
        async.flushTimers();
        job.cancel().ignore();
        async.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(stubs.stage.messages.hasListener, isFalse);
        stubs.stage.messages.close().ignore();
      });
    });

    test('each in a body, a save that fails', () {
      fakeAsync((async) {
        stubs.stage.stepError = StateError('save');
        final job = page.eachInABody()..ignore();
        stubs.stage.messages.add('m1');
        async.flushTimers();
        expect(job.outcome, isA<Failed>());
        expect(stubs.stage.messages.hasListener, isFalse);
        stubs.stage.messages.close().ignore();
      });
    });

    test('watchTicks prints two ticks, then the parent goes on', () {
      final lines = <String>[];
      runZoned(
        () => fakeAsync((async) {
          page.watchTicks();
          async.flushTimers();
        }),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      expect(lines, ['Tick 1', 'Tick 2', 'Parent continues']);
    });

    test('a plain await runs the whole callback after the cancellation', () {
      fakeAsync((async) {
        final parent = page.savingInSteps()..ignore();
        stubs.stage.messages.add('m1');
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.flushTimers();
        stubs.stage.messages.close().ignore();
        expect(trace(), [
          'm1: body begins',
          'm1: body saved',
          'm1: attachments begins',
          'm1: attachments saved',
          'parent cleanup',
        ]);
      });
    });

    test("the child's join lets the cancellation out after the first step", () {
      fakeAsync((async) {
        final parent = page.savingWithCheckpoints()..ignore();
        stubs.stage.messages.add('m1');
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.flushTimers();
        stubs.stage.messages.close().ignore();
        expect(trace(), [
          'm1: body begins',
          'm1: body saved',
          'parent cleanup',
        ]);
      });
    });

    test('a cancelled each does not wait for the source to shut down', () {
      fakeAsync((async) {
        final job = page.feedLeftToItself();
        job.done.then((outcome) => stubs.stage.trace.add('job $outcome'));
        async.flushMicrotasks();
        job.cancel().ignore();
        async.flushTimers();
        expect(trace(), ['job Cancelled(manual)', 'feed disconnected']);
      });
    });

    test('onDispose with the close of the source makes the job wait', () {
      fakeAsync((async) {
        final job = page.feedClosedByTheJob();
        var cancelReturned = false;
        job.done.then((outcome) => stubs.stage.trace.add('job $outcome'));
        async.flushMicrotasks();
        job.cancel().then((_) => cancelReturned = true);
        async.elapse(const Duration(milliseconds: 29));
        expect(job.isFinished, isFalse);
        expect(cancelReturned, isFalse);
        async.flushTimers();
        expect(trace(), ['feed disconnected', 'job Cancelled(manual)']);
        expect(cancelReturned, isTrue);
      });
    });

    test('dispose in the callback keeps every draft open to the end', () {
      fakeAsync((async) {
        final parent = page.draftsOnTheStackOfTheStream();
        stubs.stage.messages
          ..add('m1')
          ..add('m2');
        async.flushTimers();
        expect(
          trace(),
          [
            'm1: draft opened',
            'm1: writing',
            'm1: written',
            'm2: draft opened',
            'm2: writing',
            'm2: written',
          ],
          reason: 'two messages in, neither draft is closed',
        );
        stubs.stage.messages.close().ignore();
        async.flushTimers();
        expect(trace().sublist(6), ['m2: draft closed', 'm1: draft closed']);
        expect(parent.outcome, isA<Done<void>>());
      });
    });

    test('a child for the event closes its draft before the next event', () {
      fakeAsync((async) {
        final parent = page.draftsOnTheStackOfTheirEvent();
        stubs.stage.messages
          ..add('m1')
          ..add('m2');
        async.flushTimers();
        expect(trace(), [
          'm1: draft opened',
          'm1: writing',
          'm1: written',
          'm1: draft closed',
          'm2: draft opened',
          'm2: writing',
          'm2: written',
          'm2: draft closed',
        ]);
        expect(parent.isFinished, isFalse, reason: 'the stream is still open');
        stubs.stage.messages.close().ignore();
        async.flushTimers();
        expect(parent.outcome, isA<Done<void>>());
      });
    });

    test('a child for the event closes its draft when cancelled mid-write', () {
      fakeAsync((async) {
        final parent = page.draftsOnTheStackOfTheirEvent()..ignore();
        stubs.stage.messages.add('m1');
        async.elapse(const Duration(milliseconds: 5));
        parent.cancel().ignore();
        async.flushTimers();
        stubs.stage.messages.close().ignore();
        expect(trace(), [
          'm1: draft opened',
          'm1: writing',
          'm1: written',
          'm1: draft closed',
        ]);
        expect(parent.outcome, isA<Cancelled>());
      });
    });

    test('await for hears a cancellation only with the next event', () {
      fakeAsync((async) {
        final job = page.awaitForInABody()..ignore();
        var cancelReturned = false;
        stubs.stage.messages.add('m1');
        async.flushTimers();
        job.cancel().then((_) => cancelReturned = true);
        async.elapse(const Duration(hours: 1));
        expect(job.isRunning, isTrue, reason: 'parked between two events');
        expect(cancelReturned, isFalse);
        expect(stubs.stage.messages.hasListener, isTrue);
        stubs.stage.messages.add('m2');
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(cancelReturned, isTrue);
        expect(stubs.stage.messages.hasListener, isFalse);
        expect(trace(), ['m1: body begins', 'm1: body saved']);
        stubs.stage.messages.close().ignore();
      });
    });

    test('listen starts the second save while the first one runs', () {
      fakeAsync((async) {
        final job = page.listenInABody()..ignore();
        stubs.stage.messages
          ..add('m1')
          ..add('m2');
        async.flushTimers();
        expect(trace(), [
          'm1: body begins',
          'm2: body begins',
          'm1: body saved',
          'm2: body saved',
        ]);
        job.cancel().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Cancelled>());
        expect(stubs.stage.messages.hasListener, isFalse);
        stubs.stage.messages.close().ignore();
      });
    });

    test('an error of a listen callback goes to the zone, past the job', () {
      final zoneErrors = <Object>[];
      late final Job<void> job;
      late final bool listening;
      runZonedGuarded(
        () => fakeAsync((async) {
          stubs.stage.stepError = StateError('save');
          job = page.listenInABody()..ignore();
          stubs.stage.messages.add('m1');
          async.flushTimers();
          listening = stubs.stage.messages.hasListener;
          stubs.stage.messages.close().ignore();
        }),
        (error, _) => zoneErrors.add(error),
      );
      expect(zoneErrors, [isA<StateError>()]);
      expect(job.isRunning, isTrue, reason: 'the job heard nothing');
      expect(listening, isTrue);
    });

    test('the onError of listen hears the stream, not the callback', () {
      final zoneErrors = <Object>[];
      final heard = <Object>[];
      runZonedGuarded(
        () => fakeAsync((async) {
          final messages = StreamController<String>();
          messages.stream.listen(
            (message) async => throw StateError('save'),
            onError: heard.add,
          );
          messages.add('m1');
          async.flushTimers();
          expect(heard, isEmpty, reason: 'the callback threw past onError');
          messages.addError(ArgumentError('stream'));
          async.flushTimers();
          messages.close().ignore();
        }),
        (error, _) => zoneErrors.add(error),
      );
      expect(zoneErrors, [isA<StateError>()]);
      expect(heard, [isA<ArgumentError>()]);
    });

    test('asyncMap saves one message after the other', () {
      fakeAsync((async) {
        final job = page.asyncMapInABody();
        stubs.stage.messages
          ..add('m1')
          ..add('m2');
        async.flushTimers();
        expect(trace(), [
          'm1: body begins',
          'm1: body saved',
          'm2: body begins',
          'm2: body saved',
        ]);
        stubs.stage.messages.close().ignore();
        async.flushTimers();
        expect(job.outcome, isA<Done<void>>());
      });
    });

    test('asyncMap, a save that fails, fails the job', () {
      final zoneErrors = <Object>[];
      late final Job<void> job;
      runZonedGuarded(
        () => fakeAsync((async) {
          stubs.stage.stepError = StateError('save');
          job = page.asyncMapInABody()..ignore();
          stubs.stage.messages.add('m1');
          async.flushTimers();
          stubs.stage.messages.close().ignore();
        }),
        (error, _) => zoneErrors.add(error),
      );
      expect(job.outcome, isA<Failed>());
      expect(zoneErrors, isEmpty);
    });

    test('asyncMap, cancelled mid-save, ends before the save does', () {
      fakeAsync((async) {
        final job = page.asyncMapInABody();
        stubs.stage.messages.add('m1');
        async.flushMicrotasks();
        job.cancel().then((_) => trace().add('cancel returned')).ignore();
        async.flushMicrotasks();
        expect(job.outcome, isA<Cancelled>());
        expect(trace(), ['m1: body begins', 'cancel returned']);
        async.flushTimers();
        expect(trace().last, 'm1: body saved');
        stubs.stage.messages.close().ignore();
      });
    });

    test('asyncMap, a save that fails after the cancellation, is lost', () {
      final zoneErrors = <Object>[];
      late final Job<void> job;
      runZonedGuarded(
        () => fakeAsync((async) {
          job = page.asyncMapInABody();
          stubs.stage.messages.add('m1');
          async.flushMicrotasks();
          job.cancel().ignore();
          async.flushMicrotasks();
          stubs.stage.stepError = StateError('late save');
          async.flushTimers();
          stubs.stage.messages.close().ignore();
        }),
        (error, _) => zoneErrors.add(error),
      );
      expect(job.outcome, isA<Cancelled>());
      expect(zoneErrors, isEmpty);
    });

    test('each in a body, cancelled mid-save, waits for the save', () {
      fakeAsync((async) {
        final job = page.eachInABody();
        stubs.stage.messages.add('m1');
        async.flushMicrotasks();
        expect(trace(), ['m1: body begins']);
        job.cancel().then((_) => trace().add('cancel returned')).ignore();
        async.flushMicrotasks();
        expect(job.isRunning, isTrue);
        expect(stubs.stage.messages.hasListener, isFalse);
        async.flushTimers();
        expect(trace(), [
          'm1: body begins',
          'm1: body saved',
          'cancel returned',
        ]);
        expect(job.outcome, isA<Cancelled>());
        stubs.stage.messages.close().ignore();
      });
    });

    test('saveAll saves one message after the other, in one job', () {
      fakeAsync((async) {
        final messages = StreamController<String>();
        final started = <String>[];
        var over = false;
        Job.debug = (line) {
          if (line.endsWith('started')) started.add(line);
        };
        addTearDown(() => Job.debug = null);
        page.saveAll(messages.stream, (message) async {
          stubs.stage.trace.add('$message begins');
          await delay(10);
          stubs.stage.trace.add('$message saved');
        }).then((_) => over = true);
        expect(started, ['Job(each) started'], reason: 'one job, in the call');
        expect(messages.hasListener, isTrue, reason: 'inside the call');
        messages
          ..add('a')
          ..add('b')
          ..close().ignore();
        async.flushTimers();
        expect(trace(), ['a begins', 'a saved', 'b begins', 'b saved']);
        expect(over, isTrue);
      });
    });
  });

  test('every piece of code on the page is a run of lines of this file', () {
    expect(
      codeMissingFrom('doc/streams.md', 'test/support/streams_page.dart'),
      isEmpty,
    );
  });
}
