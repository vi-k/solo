@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/page_code.dart';
import 'support/vs_bloc_10_firmware.dart' as firmware;
import 'support/vs_bloc_11_preview.dart' as preview;
import 'support/vs_bloc_1_notes.dart' as notes;
import 'support/vs_bloc_2_recorder.dart' as recorder;
import 'support/vs_bloc_3_chat.dart' as chat;
import 'support/vs_bloc_4_refresh.dart' as refresh;
import 'support/vs_bloc_5_player.dart' as player;
import 'support/vs_bloc_6_map.dart' as map;
import 'support/vs_bloc_7_device.dart' as device;
import 'support/vs_bloc_8_checkout.dart' as checkout;
import 'support/vs_bloc_9_report.dart' as report;
import 'support/vs_bloc_stubs.dart';

/// The sentinel of `doc/vs-bloc.md`, for the solo side of its eleven
/// sections.
///
/// The code under each `### Solo` heading stands verbatim in the file
/// `test/support/vs_bloc_<n>_<name>.dart` of its section, after the model
/// and the fake API the page leaves out. The tests below run that code
/// through the scenario of the section and hold the page to what it says of
/// the result: a test names the phrase it stands for, so a page that stops
/// saying it leaves the test red.
///
/// The bloc side is not here, because this package does not depend on bloc.
/// The first attempts, the bloc answers and every trace the prose quotes of
/// either side are built, run and compared by the bench
/// `tool/doc_snippets.py`; this file is what `dart test` knows of the page
/// between two runs of the bench.
///
/// Every scenario runs under fake time. A test collects what it saw and
/// asserts once the zone it ran in has returned: an `expect` that failed
/// inside would be one more error of that zone.

const _doc = 'doc/vs-bloc.md';

const _files = {
  1: 'test/support/vs_bloc_1_notes.dart',
  2: 'test/support/vs_bloc_2_recorder.dart',
  3: 'test/support/vs_bloc_3_chat.dart',
  4: 'test/support/vs_bloc_4_refresh.dart',
  5: 'test/support/vs_bloc_5_player.dart',
  6: 'test/support/vs_bloc_6_map.dart',
  7: 'test/support/vs_bloc_7_device.dart',
  8: 'test/support/vs_bloc_8_checkout.dart',
  9: 'test/support/vs_bloc_9_report.dart',
  10: 'test/support/vs_bloc_10_firmware.dart',
  11: 'test/support/vs_bloc_11_preview.dart',
};

String _page() => File(_doc).readAsStringSync();

/// The page without its fenced blocks and with every run of whitespace
/// turned into one space, so that a phrase is found wherever its lines were
/// broken.
String _prose() => _page()
    .replaceAll(RegExp('```.*?```', dotAll: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
///
/// The page is not handed to `expect`: a failure would print all of it.
void _says(String phrase) => expect(
      _prose().contains(phrase),
      isTrue,
      reason: '$_doc no longer says: $phrase',
    );

/// The numbered sections of the page, heading line first.
Map<int, String> _sections() => {
      for (final part in _page().split(RegExp('^## ', multiLine: true)).skip(1))
        if (RegExp(r'^(\d+)\. ').firstMatch(part) case final number?)
          int.parse(number.group(1)!): part,
    };

/// The `dart` blocks under the `### Solo` heading of section [number].
List<String> _soloBlocks(int number) {
  final parts =
      _sections()[number]!.split(RegExp('^(?=### )', multiLine: true));
  final solo = parts.singleWhere((part) => part.startsWith('### Solo\n'));
  return [
    for (final block
        in RegExp(r'```dart\n(.*?)```', dotAll: true).allMatches(solo))
      block.group(1)!,
  ];
}

/// What the page quotes under its `text` fences, in order.
List<String> _quotes() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!,
    ];

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

/// Runs [body] under fake time, in a zone of its own, and returns the errors
/// that reached that zone uncaught. Nothing is asserted inside.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  fakeAsync((async) {
    runZonedGuarded(() => body(async), (error, _) => errors.add('$error'));
    async.flushMicrotasks();
  });
  return errors;
}

List<firmware.Chunk> _chunks(int from) =>
    [for (var i = from; i < from + 6; i++) firmware.Chunk(i)];

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.unansweredHandler = null;
  });

  group('The page', () {
    test('the code under every Solo heading stands in the support files', () {
      final files = _files.values.toList();
      expect(
        codeMissingFrom(
          _doc,
          files.first,
          alsoIn: files.sublist(1),
          under: '### Solo',
        ),
        isEmpty,
      );
    });

    test('the code of a section stands in the file of that section', () {
      final astray = <String>[];
      var blocks = 0;
      for (final MapEntry(key: number, value: file) in _files.entries) {
        final source = File(file).readAsStringSync();
        for (final block in _soloBlocks(number)) {
          blocks++;
          if (!source.contains(block)) {
            astray.add('section $number: ${block.split('\n').first}');
          }
        }
      }
      expect(astray, isEmpty);
      // One block a section, and the platform handler of section 8.
      expect(blocks, 12);
    });

    test('the page fences nothing but dart and text', () {
      expect(strayFences(_doc), isEmpty);
    });

    test('each of the eleven sections opens with a first attempt', () {
      final sections = _sections();
      expect(sections.keys, [for (var n = 1; n <= 11; n++) n]);
      final shapes = {
        for (final MapEntry(key: number, value: text) in sections.entries)
          number: [
            for (final heading
                in RegExp(r'^### (.*)$', multiLine: true).allMatches(text))
              heading.group(1)!,
          ],
      };
      for (final headings in shapes.values) {
        expect(headings.first, 'The first attempt');
        expect(headings.last, 'Solo');
      }
      _says('Each section states the required behavior, starts from the code '
          'that behavior invites');
      _says('through eleven controller scenarios');
      // Where one attempt does not get close enough, a second follows.
      expect(
        [
          for (final MapEntry(key: number, value: headings) in shapes.entries)
            if (headings.contains('The second attempt')) number,
        ],
        [1, 5, 10],
      );
    });

    test('the prose writes a dash as a dash', () {
      expect(_prose().contains(' -- '), isFalse);
    });

    test('the correspondences name what the engine has', () {
      expect(
        Policy.values.map((policy) => policy.name),
        containsAll(['sequential', 'droppable', 'restart', 'replace']),
      );
      _says('`Policy.sequential`, `Policy.droppable` and `Policy.restart`');
      _says('| `BlocObserver` | `SoloObserver` |');
      _says('| `EventTransformer` | `Policy` on a job submission |');
      _says('| `close()` | `close()` |');
      final controller = notes.NotesController(notes.Api());
      var heard = 0;
      // `currentState` and `addListener` are members of every controller.
      controller.addListener(() => heard++);
      expect(controller.currentState.notes, isEmpty);
      expect(heard, 0);
      _says('| `state`, `stream` | `currentState`, `addListener`; `stream` '
          'with `SoloStream` mixed in |');
    });

    test('value gives the value or throws, done gives the outcome', () {
      Object? value;
      Object? thrown;
      Outcome<checkout.Receipt>? failed;
      final errors = _zone((async) {
        checkout.CheckoutController(checkout.Api())
            .pay(const checkout.Order('A'))
            .value
            .then((receipt) => value = receipt);
        final declined =
            checkout.CheckoutController(checkout.Api(declines: true));
        declined.pay(const checkout.Order('B')).value.then(
          (_) {},
          onError: (Object error) {
            thrown = error;
          },
        );
        declined
            .pay(const checkout.Order('C'))
            .done
            .then((outcome) => failed = outcome);
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect('$value', 'Receipt(for A)');
      expect(thrown, isA<StateError>());
      expect(failed, isA<Failed>());
      _says('The caller can await `job.value` for a value or exception, or '
          '`job.done` for a `Done`, `Failed` or `Cancelled` outcome.');
    });
  });

  group('1. Ordering updates to shared state', () {
    test('upload and refresh end with both notes, in the order of bloc', () {
      late notes.TracedNotesController controller;
      final errors = _zone((async) {
        controller = notes.TracedNotesController(notes.Api())
          ..upload(notes.Note('n1'))
          ..refresh();
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect(
        '${controller.currentState}',
        'NotesState([n0, n1], uploading: false)',
      );
      _says('The final state is also `NotesState([n0, n1], uploading: '
          'false)`, from the same order as the bloc above');
      // "With job keys where that run has event types."
      expect(
        controller.api.trace,
        _quotes()[1]
            .replaceAll('UploadNote', 'upload')
            .replaceAll('RefreshList', 'refresh')
            .split('\n'),
      );
      _says('with job keys where that run has event types');
    });

    test('under join a cancelled upload holds the queue for the server', () {
      late notes.Api api;
      Outcome<void>? upload;
      Outcome<void>? next;
      final errors = _zone((async) {
        api = notes.Api();
        final controller = notes.NotesController(api);
        final job = controller.upload(notes.Note('n1'));
        final refresh = controller.refresh();
        async.elapse(_ms(10));
        unawaited(job.cancel());
        async.elapse(_ms(300));
        upload = job.outcome;
        next = refresh.outcome;
      });
      expect(errors, isEmpty);
      expect('$upload', 'Cancelled(manual)');
      expect('$next', 'Done(null)');
      expect(api.trace, [
        'upload n1 starts',
        'server receives n1 and holds [n0, n1]',
        'list reads [n0, n1]',
      ]);
      _says('Upload uses `join` so that even a cancelled upload holds the '
          'queue until the server has answered: the next root job cannot '
          'read the server while the upload is still in progress.');
      _says('`ctx.join(action)` calls the operation and waits for it.');
    });

    test('under abandonable the refresh reads a server that has not the note',
        () {
      late notes.Api api;
      late notes.AbandoningNotesController controller;
      final errors = _zone((async) {
        api = notes.Api();
        controller = notes.AbandoningNotesController(api);
        final job = controller.upload(notes.Note('n1'));
        controller.refresh();
        async.elapse(_ms(10));
        unawaited(job.cancel());
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect(api.trace, [
        'upload n1 starts',
        'list reads [n0]',
        'server receives n1 and holds [n0, n1]',
      ]);
      expect('${controller.currentState.notes}', '[n0]');
    });

    test('a cancelled refresh ends before the API answers', () {
      Outcome<void>? atTen;
      late notes.NotesController controller;
      final errors = _zone((async) {
        controller = notes.NotesController(notes.Api());
        final job = controller.refresh();
        async.elapse(_ms(10));
        unawaited(job.cancel());
        async.flushMicrotasks();
        atTen = job.outcome;
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect('$atTen', 'Cancelled(manual)');
      expect(controller.currentState.notes, isEmpty);
      _says('Refresh uses `ctx.abandonable`, which can stop waiting on '
          'cancellation because this example allows its read result to be '
          'abandoned.');
    });

    test('root jobs run one at a time, in the order they were added', () {
      late notes.PlainNotesController controller;
      final errors = _zone((async) {
        controller = notes.PlainNotesController(notes.Api())
          ..upload(notes.Note('n1'))
          ..mark('second')
          ..mark('third');
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect(controller.met, [
        'the await returned',
        'emitted',
        'second started',
        'third started',
      ]);
      _says('The root jobs of a controller run one at a time, in the order '
          'they were added, and that is the only way they run.');
    });

    test('a plain await keeps the body and the queue under a cancellation', () {
      Outcome<void>? atThirtyFive;
      final atForty = <String>[];
      Outcome<void>? atLast;
      late notes.PlainNotesController controller;
      final errors = _zone((async) {
        controller = notes.PlainNotesController(notes.Api());
        final job = controller.upload(notes.Note('n1'));
        controller.mark('next');
        async.elapse(_ms(10));
        unawaited(job.cancel());
        async.elapse(_ms(25));
        atThirtyFive = job.outcome;
        atForty.addAll(controller.met);
        async.elapse(_ms(10));
        atLast = job.outcome;
      });
      expect(errors, isEmpty);
      expect(atThirtyFive, isNull);
      expect(atForty, isEmpty);
      expect('$atLast', 'Cancelled(manual)');
      expect(controller.met, [
        'the await returned',
        'emit threw Cancelled',
        'next started',
      ]);
      _says('A plain `await` still keeps the body and queue occupied but '
          'does not react to cancellation.');
    });

    test('work nobody awaits outlives the job and close', () {
      var closedBefore = false;
      late notes.PlainNotesController controller;
      final errors = _zone((async) {
        controller = notes.PlainNotesController(notes.Api());
        final job = controller.detached();
        async.elapse(_ms(10));
        var closed = false;
        controller.close().then((_) => closed = true);
        async.flushMicrotasks();
        closedBefore = closed && job.outcome is Done && controller.met.isEmpty;
        async.elapse(_ms(200));
      });
      expect(errors, isEmpty);
      expect(closedBefore, isTrue);
      expect(controller.met, ['detached work ended']);
      _says('Work started without awaiting it can outlive the job; it must '
          'not be assumed to finish before `close()`.');
    });
  });

  group('2. An observer fails during a state update', () {
    test('a throwing observer changes neither the outcome nor the queue', () {
      final device = recorder.Recorder();
      final journal = recorder.Journal();
      late recorder.RecorderController controller;
      Outcome<void>? first;
      Outcome<void>? second;
      final errors = _zone((async) {
        Solo.observer = recorder.TelemetryObserver(recorder.Telemetry());
        controller = recorder.RecorderController(device, journal);
        controller.start().done.then((outcome) => first = outcome);
        async.elapse(_ms(10));
        controller.start().done.then((outcome) => second = outcome);
        async.elapse(_ms(10));
      });
      expect('${controller.currentState}', 'Recording');
      expect('$first', 'Done(null)');
      expect('$second', 'Done(null)');
      expect(journal.entries, ['Recording', 'Recording']);
      expect(device.trace, [
        'native start',
        'arm meter',
        'native start',
        'arm meter',
      ]);
      expect(errors, ['telemetry unavailable', 'telemetry unavailable']);
      _says('With the throwing observer, the state still reaches '
          '`Recording`, the meter is armed, the journal holds `[Recording]` '
          'and the job finishes with `Done(null)`: the failing hook changes '
          "neither the job's outcome nor the queue.");
      _says('The observer, installed as `Solo.observer`, and the '
          "controller's own hooks are invoked independently.");
    });

    test('the error of a hook goes to the zone and nowhere else', () {
      final handled = <String>[];
      final watcher = recorder.WatchingObserver();
      final errors = _zone((async) {
        Solo.observer = SoloObserver.all([
          recorder.TelemetryObserver(recorder.Telemetry()),
          watcher,
        ]);
        Solo.unansweredHandler =
            (solo, job, error, stackTrace) => handled.add('$error');
        recorder.RecorderController(recorder.Recorder(), recorder.Journal())
            .start();
        async.elapse(_ms(10));
      });
      expect(errors, ['telemetry unavailable']);
      expect(handled, isEmpty);
      // The observer next to the failing one saw the change and no error.
      expect(watcher.seen, ['change to Recording']);
      _says("Each hook's exception is reported to the current Dart zone");
      _says('The telemetry error goes to `Zone.current.handleUncaughtError`');
      _says('and nowhere else');
    });

    test('a throwing hook of the controller leaves the observer alone', () {
      final watcher = recorder.WatchingObserver();
      Outcome<void>? outcome;
      late recorder.ThrowingHookController controller;
      final errors = _zone((async) {
        Solo.observer = watcher;
        controller = recorder.ThrowingHookController();
        controller.start().done.then((o) => outcome = o);
        async.elapse(_ms(10));
      });
      expect(errors, ['Bad state: the hook of the controller failed']);
      expect('$outcome', 'Done(null)');
      expect('${controller.currentState}', 'Recording');
      expect(watcher.seen, ['change to Recording']);
    });
  });

  group('3. Closing and cancelling in-flight work', () {
    test('close cancels the running send and the queued one', () {
      late chat.Api api;
      late chat.ChatController controller;
      Outcome<void>? running;
      Outcome<void>? queued;
      var closedAtOnce = false;
      final errors = _zone((async) {
        api = chat.Api();
        controller = chat.ChatController(api);
        final first = controller.send('hi');
        final second = controller.send('and again');
        async.elapse(_ms(10));
        chat.onScreenClosed(controller).then((_) => closedAtOnce = true);
        async.flushMicrotasks();
        running = first.outcome;
        queued = second.outcome;
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      // `ctx.abandonable` let the call go: closing did not wait for the API.
      expect(closedAtOnce, isTrue);
      expect('$running', 'Cancelled(closed)');
      expect('$queued', 'Cancelled(closed)');
      expect(api.sent, ['hi']);
      expect(api.reads, 0);
      expect('${controller.currentState}', 'ChatState(null)');
      _says('`close()` stops accepting jobs, cancels queued jobs, requests '
          'cancellation of the running job and waits for its completion');
      _says('In this body, `ctx.abandonable` throws `Cancelled` when closing '
          'cancels the job.');
      _says('A message still queued behind the running one never reaches '
          'the API: it ends `Cancelled(closed)` without starting');
    });

    test('a call after close comes back already Cancelled(closed)', () {
      Outcome<void>? atOnce;
      final errors = _zone((async) {
        final controller = chat.ChatController(chat.Api())..close();
        atOnce = controller.send('bye').outcome;
      });
      expect(errors, isEmpty);
      expect('$atOnce', 'Cancelled(closed)');
      _says('Calls made after closure return jobs already completed with '
          '`Cancelled(closed)`, so the call site needs no `isClosed` guard.');
    });

    test('markReplyRead is a root job of its own, not a child of send', () {
      Outcome<void>? send;
      var readUnderWay = false;
      var idleAtLast = false;
      late chat.Api api;
      late chat.ChatController controller;
      final errors = _zone((async) {
        api = chat.Api();
        controller = chat.ChatController(api);
        final job = controller.send('hi');
        // The reply comes at 50 ms, and the read it starts takes ten more.
        async.elapse(_ms(55));
        send = job.outcome;
        readUnderWay = api.reads == 1 && controller.pending != null;
        async.elapse(_ms(45));
        idleAtLast = controller.pending == null;
      });
      expect(errors, isEmpty);
      // `send` is over while the read is still under way: a child would
      // have held it until the read returned.
      expect('$send', 'Done(null)');
      expect(readUnderWay, isTrue);
      expect(idleAtLast, isTrue);
      expect(api.reads, 1);
      expect('${controller.currentState}', 'ChatState(reply to hi)');
      _says('That method would submit a separate root job through the '
          "controller's `run`; it is not a child of `send`.");
    });

    test('with a plain await closing waits for the API, and emit throws', () {
      late chat.PlainAwaitChatController controller;
      var closedAtForty = true;
      var closedAtSixty = false;
      Outcome<void>? outcome;
      final errors = _zone((async) {
        controller = chat.PlainAwaitChatController(chat.Api());
        final job = controller.send('hi');
        async.elapse(_ms(10));
        var closed = false;
        controller.close().then((_) => closed = true);
        async.elapse(_ms(30));
        closedAtForty = closed;
        async.elapse(_ms(20));
        closedAtSixty = closed;
        outcome = job.outcome;
      });
      expect(errors, isEmpty);
      expect(closedAtForty, isFalse);
      expect(closedAtSixty, isTrue);
      expect(controller.afterAwait, isA<Cancelled>());
      expect('$outcome', 'Cancelled(closed)');
      expect('${controller.currentState}', 'ChatState(null)');
      _says('With a plain await instead, closing would wait for the API '
          'response. The `ctx.emit` after it would still throw `Cancelled`, '
          'so the reply would not be published.');
    });

    test('a drain sends the queued message and takes no new root job', () {
      late chat.Api api;
      late chat.ChatController controller;
      var closedAtSeventy = true;
      var closed = false;
      final errors = _zone((async) {
        api = chat.Api();
        controller = chat.ChatController(api)
          ..send('hi')
          ..send('and again');
        async.elapse(_ms(10));
        controller.close(mode: SoloCloseMode.drain).then((_) => closed = true);
        async.elapse(_ms(60));
        closedAtSeventy = closed;
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect(closedAtSeventy, isFalse);
      expect(closed, isTrue);
      expect(api.answered, ['hi', 'and again']);
      expect('${controller.currentState}', 'ChatState(reply to and again)');
      expect(api.reads, 0);
      _says('`close(mode: SoloCloseMode.drain)` runs the queue first, as '
          '`sequential()` does');
      _says('The `markReplyRead()` each reply calls still comes back '
          '`Cancelled(closed)` there, because a closing controller takes no '
          'new root job.');
    });

    test('an emit after the job is over throws and leaves the state', () {
      late chat.LateChatController controller;
      final errors = _zone((async) {
        controller = chat.LateChatController(chat.Api())..send('hi');
        async.elapse(_ms(200));
      });
      expect(
        errors,
        ['Bad state: Job(send) has already finished, cannot emit'],
      );
      expect('${controller.currentState}', 'ChatState(null)');
      _says('That call throws `Bad state: Job(send) has already finished, '
          'cannot emit`, in debug and release alike, and the state stays as '
          'it was.');
    });

    test('close waits for the cleanup of the job it cancels', () {
      var closedAtTwenty = true;
      var closedAtForty = false;
      final errors = _zone((async) {
        final controller =
            refresh.SlowCleanupRefreshController(refresh.RefreshApi())
              ..refresh();
        async.flushMicrotasks();
        var closed = false;
        controller.close().then((_) => closed = true);
        async.elapse(_ms(20));
        closedAtTwenty = closed;
        async.elapse(_ms(20));
        closedAtForty = closed;
      });
      expect(errors, isEmpty);
      expect(closedAtTwenty, isFalse);
      expect(closedAtForty, isTrue);
      _says('waits for its completion, including cleanup');
    });
  });

  group('4. Leaving a loading state when the work is cancelled', () {
    test('cancelRefresh cancels the running refresh and hands back its job',
        () {
      late refresh.RefreshController controller;
      var same = false;
      String? atTheCall;
      Outcome<void>? outcome;
      final errors = _zone((async) {
        controller = refresh.RefreshController(refresh.RefreshApi());
        final job = controller.refresh();
        async.flushMicrotasks();
        same = identical(controller.cancelRefresh(), job);
        atTheCall = '${controller.currentState}';
        async.flushMicrotasks();
        outcome = job.outcome;
      });
      expect(errors, isEmpty);
      expect(same, isTrue);
      // The handler has not run yet when `cancelRefresh()` returns.
      expect(atTheCall, 'Loading');
      expect('$outcome', 'Cancelled(manual)');
      expect('${controller.currentState}', 'Initial');
      _says('`cancelRefresh()` finds the running refresh by its key and '
          'cancels it');
      _says('It hands back the job it is cancelling rather than a future');
      _says("solo's state handler runs after the cancelled job's cleanup");
    });

    test('with nothing to cancel it answers null', () {
      final controller = refresh.RefreshController(refresh.RefreshApi());
      expect(controller.cancelRefresh(), isNull);
      _says('`null` there means there was nothing to cancel');
    });

    test('the queued refresh is found before the running one', () {
      var foundQueued = false;
      Outcome<void>? first;
      Outcome<void>? second;
      late refresh.RefreshController controller;
      final errors = _zone((async) {
        controller = refresh.RefreshController(refresh.RefreshApi());
        final running = controller.refresh();
        async.flushMicrotasks();
        final queued = controller.refresh();
        foundQueued = identical(controller.cancelRefresh(), queued) &&
            running.isCancelled;
        async.flushMicrotasks();
        first = running.outcome;
        second = queued.outcome;
      });
      expect(errors, isEmpty);
      expect(foundQueued, isTrue);
      expect('$first', 'Cancelled(replaced)');
      expect('$second', 'Cancelled(manual)');
      expect('${controller.currentState}', 'Initial');
      _says('`lastJobWhere` searches the queue from the end and falls back '
          'to the running job, so it answers with the queued refresh when '
          'one is waiting.');
      _says('`Policy.restart` cancelled the running one at that moment');
    });

    test('the handler runs after the cleanup and before the queue goes on', () {
      late refresh.SlowCleanupRefreshController controller;
      String? atTen;
      final errors = _zone((async) {
        controller = refresh.SlowCleanupRefreshController(refresh.RefreshApi());
        final job = controller.refresh();
        controller.mark();
        async.flushMicrotasks();
        unawaited(job.cancel());
        async.elapse(_ms(10));
        atTen = '${controller.currentState}';
        async.elapse(_ms(30));
      });
      expect(errors, isEmpty);
      expect(atTen, 'Loading');
      expect(controller.seen, [
        'cleanup starts in Loading',
        'cleanup ends in Loading',
        'the next job starts in Initial',
      ]);
      _says('`ctx.abandonable` ends the wait for the API, and `ifCancelled` '
          'returns `Initial` before the queue proceeds.');
    });

    test('a refresh that succeeds or fails leaves Initial as well', () {
      Outcome<void>? succeeded;
      String? afterSuccess;
      String? whileLoading;
      Outcome<void>? failed;
      late refresh.RefreshController controller;
      final errors = _zone((async) {
        final api = refresh.RefreshApi();
        controller = refresh.RefreshController(api);
        final ok = controller.refresh();
        async.flushMicrotasks();
        api.pending.complete();
        async.flushMicrotasks();
        succeeded = ok.outcome;
        afterSuccess = '${controller.currentState}';
        api.pending = Completer<void>();
        final bad = controller.refresh()..ignoreFailure();
        async.flushMicrotasks();
        whileLoading = '${controller.currentState}';
        api.pending.completeError(StateError('offline'));
        async.flushMicrotasks();
        failed = bad.outcome;
      });
      expect(errors, isEmpty);
      expect('$succeeded', 'Done(null)');
      expect(afterSuccess, 'Initial');
      expect(whileLoading, 'Loading');
      expect('$failed', 'Failed(Bad state: offline)');
      expect('${controller.currentState}', 'Initial');
      _says('A successful refresh publishes `Initial` from the body; '
          '`ifFailed` resets the indicator on failure while the job still '
          'reports `Failed`.');
    });

    test('an external state that breaks the job skips its handlers', () {
      late refresh.SlowCleanupRefreshController controller;
      Outcome<void>? broken;
      String? afterBroken;
      final afterBrokenSeen = <String>[];
      Outcome<void>? byHand;
      final errors = _zone((async) {
        controller = refresh.SlowCleanupRefreshController(refresh.RefreshApi())
          ..outside(const refresh.Loading());
        final job = controller.narrow();
        async.flushMicrotasks();
        controller.outside(const refresh.Initial());
        async.flushMicrotasks();
        broken = job.outcome;
        afterBroken = '${controller.currentState}';
        afterBrokenSeen.addAll(controller.seen);
        controller.outside(const refresh.Loading());
        final other = controller.narrow();
        async.flushMicrotasks();
        unawaited(other.cancel());
        async.flushMicrotasks();
        byHand = other.outcome;
      });
      expect(errors, isEmpty);
      expect('$broken', 'Cancelled(rules: is not Loading)');
      expect(afterBroken, 'Initial');
      expect(afterBrokenSeen, isEmpty);
      // The same job cancelled by hand does get its handler.
      expect('$byHand', 'Cancelled(manual)');
      expect(controller.seen, ['ifCancelled ran']);
      _says('If an independent external state makes the solo job invalid, '
          'its final state handlers are skipped');
    });
  });

  group('5. Restarting one operation within a shared queue', () {
    test('the drag reaches the device as play, seek 3, pause', () {
      late player.Player device;
      late player.PlayerController controller;
      final outcomes = <String>[];
      final errors = _zone((async) {
        device = player.Player();
        controller = player.PlayerController(device);
        final jobs = [
          controller.play(),
          for (final position in [1, 2, 3]) controller.seek(_ms(position)),
          controller.pause(),
        ];
        async.elapse(_ms(300));
        outcomes.addAll([for (final job in jobs) '${job.outcome}']);
      });
      expect(errors, isEmpty);
      expect('${callsOf(device.trace)}', '[play, seek 3, pause]');
      expect(device.trace, [
        'play start',
        'play end',
        'seek 3 start',
        'seek 3 end',
        'pause start',
        'pause end',
      ]);
      expect('${controller.currentState}', 'Ready(3ms)');
      expect(outcomes, [
        'Done(null)',
        'Cancelled(replaced)',
        'Cancelled(replaced)',
        'Done(null)',
        'Done(null)',
      ]);
      _says('The traces are those of the bloc answer above: `[play, seek 3, '
          'pause]` for the drag');
      _says('`Policy.restart` removes cancellable queued seeks with the '
          'same key and requests cancellation of the active `seek`.');
      _says('`pause` and `play` remain in the same queue with their default '
          'sequential policy.');
      _says('callers can inspect the outcome of each `seek`, including '
          '`Cancelled(replaced)` for a replaced request');
    });

    test('a seek in flight is stopped before its replacement starts', () {
      late player.Player device;
      final atTwenty = <String>[];
      var cancelledAtTheCall = false;
      Outcome<void>? stale;
      Outcome<void>? fresh;
      final errors = _zone((async) {
        device = player.Player();
        final controller = player.PlayerController(device);
        final first = controller.seek(_ms(1));
        async.elapse(_ms(15));
        final second = controller.seek(_ms(3));
        cancelledAtTheCall = first.isCancelled && first.outcome == null;
        async.elapse(_ms(5));
        atTwenty.addAll(device.trace);
        async.elapse(_ms(300));
        stale = first.outcome;
        fresh = second.outcome;
      });
      expect(errors, isEmpty);
      expect(cancelledAtTheCall, isTrue);
      // The token reached the player while the call was still under way:
      // it stopped on its next step instead of running to the end.
      expect(atTwenty, ['seek 1 start', 'seek 1 stopped', 'seek 3 start']);
      expect(
        '${device.trace}',
        '[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]',
      );
      expect('$stale', 'Cancelled(replaced)');
      expect('$fresh', 'Done(null)');
      _says('`[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]` '
          'when `seek 1` is already active');
      _says('`ctx.onCancel` forwards that request to the player '
          'immediately.');
      _says('`ctx.join` waits for the operation to return before the '
          'current job can finish and the replacement can start.');
    });

    test('an error of the stopped call reaches the body, not the outcome', () {
      late player.CatchingPlayerController controller;
      Outcome<void>? stale;
      Outcome<void>? fresh;
      final errors = _zone((async) {
        controller = player.CatchingPlayerController(
          player.Player(failsWhenStopped: true),
        );
        final first = controller.seek(_ms(1));
        async.elapse(_ms(15));
        final second = controller.seek(_ms(3));
        async.elapse(_ms(300));
        stale = first.outcome;
        fresh = second.outcome;
      });
      expect(errors, isEmpty);
      expect(
        controller.met,
        ['join threw StateError: Bad state: seek 1 interrupted'],
      );
      expect('$stale', 'Cancelled(replaced)');
      expect('$fresh', 'Done(null)');
      _says('If the operation fails after cancellation, its error reaches '
          "the body; the job's outcome still remains cancelled.");
    });
  });

  group('6. Typed methods with queued execution', () {
    test('the first move stops, the middle one never starts', () {
      late map.MapApi api;
      late map.MapController controller;
      final outcomes = <String>[];
      var aFuture = true;
      final errors = _zone((async) {
        api = map.MapApi();
        controller = map.MapController(api);
        final first = controller.moveTo(const Point<double>(1, 0));
        aFuture = first is Future;
        async.elapse(_ms(10));
        final rest = [
          controller.moveTo(const Point<double>(2, 0)),
          controller.moveTo(const Point<double>(3, 0)),
          controller.setZoom(4),
        ];
        async.elapse(_ms(300));
        outcomes
            .addAll(['${first.outcome}', for (final j in rest) '${j.outcome}']);
      });
      expect(errors, isEmpty);
      expect(
        '${api.trace}',
        '[moveTo 1 start, moveTo 1 stopped, moveTo 3 start, moveTo 3 end]',
      );
      expect('${controller.currentState}', 'MapState(3, z4)');
      expect(outcomes, [
        'Cancelled(replaced)',
        'Cancelled(replaced)',
        'Done(null)',
        'Done(null)',
      ]);
      expect(aFuture, isFalse);
      _says('In the scenario below a drag sends position 1, then, while the '
          'map is still moving there, positions 2 and 3, and the user zooms '
          'to 4.');
      _says('The trace is `[moveTo 1 start, moveTo 1 stopped, moveTo 3 '
          'start, moveTo 3 end]`: the first request was already under way '
          'and stops before the latest one begins, and the middle one does '
          'not start.');
      _says('Both the map and `MapState(3, z4)` reflect the latest request.');
      _says('The returned job itself is not a `Future`');
    });

    test('onMapDrag is a finished statement that waits for nothing', () {
      late map.MapApi api;
      final errors = _zone((async) {
        api = map.MapApi();
        map.onMapDrag(map.MapController(api), const Point<double>(3, 0));
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect(api.trace, ['moveTo 3 start', 'moveTo 3 end']);
      _says('or omit waiting');
    });

    test('the failure of a job nobody waits for goes to the zone', () {
      final errors = _zone((async) {
        map.FailingMapController().fail();
        async.elapse(_ms(10));
      });
      expect(errors, ['Bad state: the map failed']);
      _says('what becomes of the failure of a job nobody waits for is in');
    });
  });

  group('7. Removing selected pending work', () {
    test('disconnect removes the queued read at the call', () {
      late device.Ble ble;
      late device.DeviceController controller;
      Outcome<void>? atTheCall;
      final outcomes = <String>[];
      final errors = _zone((async) {
        ble = device.Ble();
        controller = device.DeviceController(ble);
        final connect = controller.connect();
        final battery = controller.readBattery();
        final rename = controller.rename('kitchen');
        final disconnect = controller.disconnect();
        atTheCall = battery.outcome;
        async.elapse(_ms(300));
        outcomes.addAll([
          for (final job in [connect, battery, rename, disconnect])
            '${job.outcome}',
        ]);
      });
      expect(errors, isEmpty);
      expect('$atTheCall', 'Cancelled(manual)');
      expect(ble.trace, ['connect', 'rename kitchen', 'disconnect']);
      expect(outcomes, [
        'Done(null)',
        'Cancelled(manual)',
        'Done(null)',
        'Done(null)',
      ]);
      expect('${controller.currentState}', 'Offline');
      _says('the removal happens when `disconnect` is called');
      _says('The removed read job completes with `Cancelled(manual)`');
      _says('Rename stays queued, and disconnect runs after it.');
    });

    test('a read that has already started is not removed', () {
      late device.Ble ble;
      Outcome<void>? reading;
      final errors = _zone((async) {
        ble = device.Ble();
        final controller = device.DeviceController(ble)..connect();
        async.elapse(_ms(30));
        final battery = controller.readBattery();
        controller.rename('kitchen');
        async.elapse(_ms(5));
        controller.disconnect();
        async.elapse(_ms(100));
        reading = battery.outcome;
      });
      expect(errors, isEmpty);
      expect(
        '${ble.trace}',
        '[connect, battery, rename kitchen, disconnect]',
      );
      expect('$reading', 'Done(null)');
      _says('`removeWhere` works on the queue alone: if the read has '
          'already started, it is not removed, and the device receives '
          '`[connect, battery, rename kitchen, disconnect]`.');
    });

    for (final (name, sweep, renamed) in <(
      String,
      void Function(device.DeviceController),
      bool,
    )>[
      ('cancelAll()', (controller) => controller.cancelAll(), true),
      ('queue.clear()', (controller) => controller.clearQueue(), true),
      (
        'cancelAll(force: true)',
        (controller) => controller.cancelAll(force: true),
        false,
      ),
      (
        'queue.clear(force: true)',
        (controller) => controller.clearQueue(force: true),
        false,
      ),
    ]) {
      test('$name ${renamed ? 'skips' : 'takes'} the queued rename', () {
        late device.Ble ble;
        Outcome<void>? rename;
        Outcome<void>? read;
        final errors = _zone((async) {
          ble = device.Ble();
          final controller = device.DeviceController(ble)..connect();
          async.elapse(_ms(30));
          // A read in flight keeps the rename and the second read in the
          // queue until the sweep comes.
          controller.readBattery();
          async.elapse(_ms(1));
          final kept = controller.rename('hall');
          final dropped = controller.readBattery();
          sweep(controller);
          async.elapse(_ms(200));
          rename = kept.outcome;
          read = dropped.outcome;
        });
        expect(errors, isEmpty);
        expect('$read', 'Cancelled(manual)');
        expect(
          '$rename',
          renamed ? 'Done(null)' : 'Cancelled(manual)',
        );
        expect(ble.trace.contains('rename hall'), renamed);
        _says('a sweep skips such a job instead of removing it, and '
            '`force: true` is what takes it');
        _says('code that later sweeps the whole queue with `cancelAll()` or '
            '`queue.clear()`');
      });
    }

    test('a read queued behind the disconnect never reaches the device', () {
      late device.Ble ble;
      Outcome<void>? late_;
      final errors = _zone((async) {
        ble = device.Ble();
        final controller = device.DeviceController(ble)
          ..connect()
          ..disconnect();
        final read = controller.readBattery();
        async.elapse(_ms(200));
        late_ = read.outcome;
      });
      expect(errors, isEmpty);
      expect(ble.trace, ['connect', 'disconnect']);
      expect('$late_', 'Cancelled(rules: is not Connected)');
      _says('Here `run<Connected, void>` is checked when the job starts, so '
          'the same read ends as `Cancelled(rules: is not Connected)` and '
          'the call is never made.');
    });
  });

  group('8. Awaiting a particular request', () {
    test('three requests for two orders make two charges', () {
      late checkout.Api api;
      late checkout.CheckoutController controller;
      var shared = false;
      final replies = <Map<String, Object?>>[];
      final errors = _zone((async) {
        api = checkout.Api();
        controller = checkout.CheckoutController(api);
        final running = controller.pay(const checkout.Order('A'));
        final queued = controller.pay(const checkout.Order('B'));
        // The running job and the queued one alike.
        shared =
            identical(running, controller.pay(const checkout.Order('A'))) &&
                identical(queued, controller.pay(const checkout.Order('B')));
        for (final order in ['A', 'A', 'B']) {
          checkout
              .handlePayRequest(controller, checkout.Order(order))
              .then(replies.add);
        }
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect(shared, isTrue);
      expect(api.calls, 2);
      expect(replies, [
        {'paid': true, 'receipt': 'R-A'},
        {'paid': true, 'receipt': 'R-A'},
        {'paid': true, 'receipt': 'R-B'},
      ]);
      expect('${controller.currentState}', 'Paid(Receipt(for B))');
      _says('`Policy.droppable` returns the existing queued or running job '
          'for the same order key.');
      _says('The three requests again make two API calls.');
    });

    test('a cancel from a screen is refused, running or queued', () {
      late checkout.Api api;
      var cancelled = true;
      final outcomes = <String>[];
      final errors = _zone((async) {
        api = checkout.Api();
        final controller = checkout.CheckoutController(api);
        final charging = controller.pay(const checkout.Order('A'));
        async.elapse(_ms(10));
        final queued = controller.pay(const checkout.Order('B'));
        unawaited(queued.cancel());
        unawaited(charging.cancel());
        async.flushMicrotasks();
        cancelled = charging.isCancelled || queued.isCancelled;
        async.elapse(_ms(100));
        outcomes.addAll(['${charging.outcome}', '${queued.outcome}']);
      });
      expect(errors, isEmpty);
      expect(cancelled, isFalse);
      expect(outcomes, ['Done(Receipt(for A))', 'Done(Receipt(for B))']);
      expect(api.calls, 2);
      _says('Every other cancellation is rejectable, and `cancellable: '
          'false` rejects it: `Job.cancel` from a screen, a closing '
          'controller.');
      _says('The flag also refuses manual cancellation while the payment is '
          'queued.');
    });

    test('close waits for the running payment and discards the queued one', () {
      late checkout.Api api;
      late checkout.CheckoutController controller;
      Outcome<checkout.Receipt>? waitingAtOnce;
      var closedAtOnce = true;
      var closed = false;
      Outcome<checkout.Receipt>? running;
      Map<String, Object?>? afterClose;
      final errors = _zone((async) {
        api = checkout.Api();
        controller = checkout.CheckoutController(api);
        final first = controller.pay(const checkout.Order('C'));
        async.elapse(_ms(10));
        final second = controller.pay(const checkout.Order('D'));
        controller.close().then((_) => closed = true);
        async.flushMicrotasks();
        closedAtOnce = closed;
        waitingAtOnce = second.outcome;
        async.elapse(_ms(100));
        running = first.outcome;
        checkout
            .handlePayRequest(controller, const checkout.Order('E'))
            .then((reply) => afterClose = reply);
        async.flushMicrotasks();
      });
      expect(errors, isEmpty);
      expect(closedAtOnce, isFalse);
      expect(closed, isTrue);
      expect('$waitingAtOnce', 'Cancelled(closed)');
      expect('$running', 'Done(Receipt(for C))');
      expect(api.calls, 1);
      expect('${controller.currentState}', 'Paid(Receipt(for C))');
      expect(afterClose, {'paid': false, 'cancelled': 'closed'});
      _says('The body publishes `Paid` before completing with the receipt, '
          'and `close()` waits for that completion.');
      _says('`close()` and `queue.clear(force: true)` can still discard a '
          'queued payment without charging, and a submission after close '
          'also never starts.');
      _says("These cases explain the platform handler's `Cancelled` branch.");
    });

    test('queue.clear takes a queued payment only by force', () {
      late checkout.Api api;
      Outcome<checkout.Receipt>? afterClear;
      final outcomes = <String>[];
      final errors = _zone((async) {
        api = checkout.Api();
        final controller = checkout.CheckoutController(api);
        final first = controller.pay(const checkout.Order('F'));
        async.elapse(_ms(10));
        final second = controller.pay(const checkout.Order('G'));
        controller.clearQueue();
        async.flushMicrotasks();
        afterClear = second.outcome;
        controller.clearQueue(force: true);
        async.elapse(_ms(100));
        outcomes.addAll(['${first.outcome}', '${second.outcome}']);
      });
      expect(errors, isEmpty);
      expect(afterClear, isNull);
      expect(outcomes, ['Done(Receipt(for F))', 'Cancelled(manual)']);
      expect(api.calls, 1);
    });

    test('a declined card is Failed, and the handler says so', () {
      late checkout.CheckoutController controller;
      Map<String, Object?>? reply;
      final errors = _zone((async) {
        controller = checkout.CheckoutController(checkout.Api(declines: true));
        checkout
            .handlePayRequest(controller, const checkout.Order('A'))
            .then((value) => reply = value);
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect(reply, {'paid': false, 'error': 'Bad state: card declined'});
      // No `onError` was supplied, so the state stays where the body left it.
      expect('${controller.currentState}', 'Paying(A)');
      _says('API failures still produce `Failed`; a failure state can be '
          'supplied with `run(ifFailed: ...)`.');
    });

    test('a narrower type lets a state rule cancel a charge that was sent', () {
      late checkout.Api wideApi;
      late checkout.Api narrowApi;
      Outcome<checkout.Receipt>? wide;
      Outcome<checkout.Receipt>? narrow;
      String? narrowState;
      final errors = _zone((async) {
        wideApi = checkout.Api();
        final page = checkout.CheckoutController(wideApi);
        final job = page.pay(const checkout.Order('A'));
        async.elapse(_ms(10));
        page.suspend();
        async.elapse(_ms(100));
        wide = job.outcome;

        narrowApi = checkout.Api();
        final other = checkout.NarrowCheckoutController(narrowApi);
        final cut = other.pay(const checkout.Order('A'))..ignoreFailure();
        async.elapse(_ms(10));
        other.suspend();
        async.elapse(_ms(100));
        narrow = cut.outcome;
        narrowState = '${other.currentState}';
      });
      expect(errors, isEmpty);
      expect('$wide', 'Done(Receipt(for A))');
      expect('$narrow', 'Cancelled(rules: is not Open)');
      // The charge went out, and nothing recorded it.
      expect(narrowApi.calls, 1);
      expect(narrowState, 'Suspended');
      expect(wideApi.calls, 1);
      _says('It sets no `keepWhile` and accepts the base `CheckoutState`, '
          'so no state rule can reject it');
      _says('a state rule cancels even a non-cancellable job: a narrower '
          'type would allow cancellation after a charge was sent but before '
          'it was recorded');
    });

    test(
        'abandonable lets go, join stays, uncancellable holds the cancellation',
        () {
      final atTen = <String, String>{};
      final atLast = <String, List<String>>{};
      final errors = _zone((async) {
        for (final member in ['abandonable', 'join', 'uncancellable']) {
          final controller = checkout.WaitingCheckoutController(checkout.Api());
          const order = checkout.Order('A');
          final job = switch (member) {
            'abandonable' => controller.viaAbandonable(order),
            'join' => controller.viaJoin(order),
            _ => controller.viaUncancellable(order),
          };
          async.elapse(_ms(10));
          unawaited(job.cancel());
          async.flushMicrotasks();
          atTen[member] = '${job.outcome}, cancelled ${job.isCancelled}';
          async.elapse(_ms(100));
          atLast[member] = ['${job.outcome}', ...controller.met];
        }
      });
      expect(errors, isEmpty);
      expect(atTen, {
        'abandonable': 'Cancelled(manual), cancelled true',
        'join': 'null, cancelled true',
        'uncancellable': 'null, cancelled false',
      });
      expect(atLast, {
        'abandonable': ['Cancelled(manual)', 'abandonable threw Cancelled'],
        'join': ['Cancelled(manual)', 'join threw Cancelled'],
        'uncancellable': [
          'Cancelled(manual)',
          'uncancellable got Receipt(for A)',
          'the next checkpoint threw Cancelled',
        ],
      });
      _says('`abandonable` lets go of the call, `join` stays with it until it '
          'answers, `uncancellable` holds the cancellation back until the '
          'step ends.');
      _says('The charge is a plain `await`.');
    });
  });

  group('9. Reacting to an independent external state change', () {
    test('the revocation shows at once and cancels the build by its rule', () {
      late report.Reports reports;
      late report.ReportController controller;
      final states = <report.ReportState>[];
      String? atTheCall;
      Outcome<void>? atFortyNine;
      var builtAtFortyNine = -1;
      Outcome<void>? atFifty;
      final errors = _zone((async) {
        reports = report.Reports();
        final auth = report.Auth();
        controller = report.ReportController(reports, auth);
        controller.stream.listen(states.add);
        final job = controller.build(const report.Range(30));
        async.elapse(_ms(25));
        auth.revoke('signed out elsewhere');
        atTheCall = '${controller.currentState}, cancelled ${job.isCancelled}';
        async.elapse(_ms(24));
        atFortyNine = job.outcome;
        builtAtFortyNine = reports.built;
        async.elapse(_ms(1));
        atFifty = job.outcome;
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect(atTheCall, 'SignedOut(signed out elsewhere), cancelled true');
      // `join` ends the job when the build it cannot stop returns.
      expect(atFortyNine, isNull);
      expect(builtAtFortyNine, 0);
      expect('$atFifty', 'Cancelled(rules: is not SignedIn)');
      expect(reports.built, 1);
      expect('$states', '[SignedOut(signed out elsewhere)]');
      _says('`externalSetState` updates state immediately and checks '
          'running bodies against their rules.');
      _says('the revocation cancels it with `Cancelled(rules: is not '
          'SignedIn)`');
      _says('The build already in progress still finishes in both examples.');
    });

    test('join holds the queue for the build', () {
      late report.UnguardedReportController controller;
      final errors = _zone((async) {
        final auth = report.Auth();
        controller = report.UnguardedReportController(report.Reports(), auth)
          ..build(const report.Range(1));
        async.elapse(_ms(25));
        auth.revoke('signed out elsewhere');
        controller.mark();
        async.elapse(_ms(100));
      });
      expect(errors, isEmpty);
      expect(controller.seen, [
        'report is over',
        'the next root job starts with 1 built',
        'mark is over',
      ]);
      _says('`join` waits for it before allowing another root job to '
          'start.');
    });

    test('published by an ordinary job the revocation waits its turn', () {
      final states = <report.ReportState>[];
      final errors = _zone((async) {
        final auth = report.Auth();
        final controller =
            report.QueuedRevocationController(report.Reports(), auth);
        controller.stream.listen(states.add);
        controller.build(const report.Range(30));
        async.elapse(_ms(25));
        auth.revoke('signed out elsewhere');
        async.elapse(_ms(300));
      });
      expect(errors, isEmpty);
      expect(
        '$states',
        '[Ready(Report(30 days)), SignedOut(signed out elsewhere)]',
      );
      _says('Published by an ordinary job, `SignedOut` would queue behind '
          'the build and wait for the very work it makes worthless.');
    });

    test('the job may end by emitting Ready, and no further', () {
      Outcome<void>? page;
      String? pageState;
      Outcome<void>? checked;
      final errors = _zone((async) {
        final controller =
            report.ReportController(report.Reports(), report.Auth());
        final job = controller.build(const report.Range(30));
        async.elapse(_ms(100));
        page = job.outcome;
        pageState = '${controller.currentState}';
        final reading =
            report.HandledReportController(report.Reports(), report.Auth());
        final other =
            reading.build(const report.Range(30), readsAfterEmit: true);
        async.elapse(_ms(100));
        checked = other.outcome;
      });
      expect(errors, isEmpty);
      expect('$page', 'Done(null)');
      expect(pageState, 'Ready(Report(30 days))');
      expect('$checked', 'Cancelled(rules: is not SignedIn)');
      _says('On the success path, the job may finish by emitting `Ready`, '
          'even though that state is outside `SignedIn`. Its own `emit` is '
          'excluded from the rule check; a later state checkpoint would '
          'cancel it.');
    });

    test('final state handlers are disabled by the revocation', () {
      late report.HandledReportController revoked;
      late report.HandledReportController byHand;
      Outcome<void>? cancelled;
      final errors = _zone((async) {
        final auth = report.Auth();
        revoked = report.HandledReportController(report.Reports(), auth)
          ..build(const report.Range(30));
        async.elapse(_ms(25));
        auth.revoke('signed out elsewhere');
        async.elapse(_ms(100));
        byHand =
            report.HandledReportController(report.Reports(), report.Auth());
        final stall = byHand.stall();
        async.elapse(_ms(10));
        unawaited(stall.cancel());
        async.elapse(_ms(10));
        cancelled = stall.outcome;
      });
      expect(errors, isEmpty);
      expect(revoked.handlers, isEmpty);
      expect('${revoked.currentState}', 'SignedOut(signed out elsewhere)');
      // The handler does run for a cancellation nothing external caused.
      expect('$cancelled', 'Cancelled(manual)');
      expect(byHand.handlers, ['ifCancelled']);
      _says('Final `ifFailed` and `ifCancelled` state handlers, if supplied, '
          'are disabled by an incompatible external update, so they do not '
          'overwrite `SignedOut` during cleanup.');
    });

    test('a drain still hears the revocation', () {
      late report.ReportController controller;
      final outcomes = <String>[];
      var draining = false;
      var closed = false;
      final errors = _zone((async) {
        final auth = report.Auth();
        controller = report.ReportController(report.Reports(), auth);
        final first = controller.build(const report.Range(1));
        final second = controller.build(const report.Range(2));
        async.elapse(_ms(10));
        controller.close(mode: SoloCloseMode.drain).then((_) => closed = true);
        async.elapse(_ms(15));
        draining = controller.isDraining && !controller.isFinished;
        auth.revoke('signed out elsewhere');
        async.elapse(_ms(200));
        outcomes.addAll(['${first.outcome}', '${second.outcome}']);
      });
      expect(errors, isEmpty);
      expect(draining, isTrue);
      expect(closed, isTrue);
      expect(outcomes, [
        'Cancelled(rules: is not SignedIn)',
        'Cancelled(rules: is not SignedIn)',
      ]);
      expect('${controller.currentState}', 'SignedOut(signed out elsewhere)');
      _says('so that a `SoloCloseMode.drain` still hears the revocation '
          'while its queue runs');
    });

    test('a revocation after the end is dropped by the guard', () {
      late report.ReportController guarded;
      late report.UnguardedReportController unguarded;
      Object? thrown;
      final errors = _zone((async) {
        final auth = report.Auth();
        guarded = report.ReportController(report.Reports(), auth)..close();
        async.flushMicrotasks();
        auth.revoke('after the end');

        final other = report.Auth();
        unguarded = report.UnguardedReportController(report.Reports(), other)
          ..build(const report.Range(1))
          ..close();
        async.elapse(_ms(100));
        try {
          other.revoke('after the end');
        } on Object catch (error) {
          thrown = error;
        }
      });
      expect(errors, isEmpty);
      expect(guarded.isFinished, isTrue);
      expect('${guarded.currentState}', 'SignedIn');
      expect(thrown, isA<StateError>());
      // `onClose` comes after the last job, with `isFinished` still false.
      expect(unguarded.seen, ['report is over', 'onClose, isFinished false']);
      _says('the write is guarded with `isFinished` and the listener is '
          'stopped in `onClose`, which comes once every job is over');
      _says('a revocation arriving after the end is dropped by the guard '
          'instead of throwing');
    });
  });

  group('10. Finishing an in-flight write before restarting', () {
    test('the restart waits for the write in flight; nothing overlaps', () {
      late firmware.Ble ble;
      late firmware.FirmwareController controller;
      Outcome<void>? first;
      Outcome<void>? second;
      final errors = _zone((async) {
        ble = firmware.Ble();
        controller = firmware.FirmwareController(ble);
        final replaced = controller.flash(_chunks(0));
        async.elapse(_ms(30));
        final replacement = controller.flash(_chunks(100));
        async.elapse(_ms(300));
        first = replaced.outcome;
        second = replacement.outcome;
      });
      expect(errors, isEmpty);
      expect('${ble.written}', '[0, 1, 100, 101, 102, 103, 104, 105]');
      // Every write ends before the next one starts.
      for (var index = 0; index < ble.trace.length; index += 2) {
        expect(
          ble.trace[index + 1],
          ble.trace[index].replaceFirst('start', 'end'),
        );
      }
      expect('$first', 'Cancelled(replaced)');
      expect('$second', 'Done(null)');
      expect('${controller.currentState}', 'Flashing(6/6)');
      _says('The device gets the chunks in the order of the locked bloc, '
          '`[0, 1, 100, 101, …]`, and no write starts before the one ahead '
          'of it has ended.');
      _says('`join` waits for the current write and throws `Cancelled` once '
          'it returns, before the next iteration; the replaced upload ends '
          'at `Cancelled(replaced)`.');
    });

    test('a Broken state from outside stops the upload after its write', () {
      late firmware.Ble ble;
      late firmware.FirmwareController controller;
      Outcome<void>? outcome;
      final errors = _zone((async) {
        ble = firmware.Ble();
        controller = firmware.FirmwareController(ble);
        final job = controller.flash(_chunks(0));
        async.elapse(_ms(50));
        controller.hardwareFailed('cable unplugged');
        async.elapse(_ms(300));
        outcome = job.outcome;
      });
      expect(errors, isEmpty);
      expect('${ble.written}', '[0, 1, 2]');
      expect('$outcome', 'Cancelled(rules: is not NotBroken)');
      expect('${controller.currentState}', 'Broken(cable unplugged)');
      _says('When the state turns `Broken` during the third write, the '
          'upload stops after `[0, 1, 2]` with `Cancelled(rules: is not '
          'NotBroken)`.');
      _says('The one checkpoint in `join` covers both replacement and state '
          'invalidation.');
    });

    test('a parent waits for its children and their cleanup', () {
      late firmware.ParentController controller;
      Outcome<void>? atForty;
      Outcome<void>? atSixty;
      final errors = _zone((async) {
        controller = firmware.ParentController();
        final job = controller.withChild();
        controller.mark();
        async.elapse(_ms(40));
        atForty = job.outcome;
        async.elapse(_ms(20));
        atSixty = job.outcome;
      });
      expect(errors, isEmpty);
      expect(atForty, isNull);
      expect('$atSixty', 'Done(null)');
      expect(controller.seen, [
        'the body of the parent ended',
        'the body of the child ended',
        'the cleanup of the child ended',
        'the next job started',
      ]);
      _says('If the upload starts child jobs through `ctx.run`, the parent '
          'also waits for those children and their cleanup.');
    });

    test('unattended work does not hold the queue, and its error is heard', () {
      late firmware.ParentController controller;
      final atTen = <String>[];
      final errors = _zone((async) {
        controller = firmware.ParentController()
          ..withUnattended()
          ..mark();
        async.elapse(_ms(10));
        atTen.addAll(controller.seen);
        async.elapse(_ms(100));
      });
      expect(atTen, ['the body ended', 'the next job started']);
      expect(
        controller.seen.last,
        'onError of upload: Bad state: the unattended work failed',
      );
      // Nothing answered for it, so it ends in the zone as well.
      expect(errors, ['Bad state: the unattended work failed']);
      _says('Work intentionally allowed to outlive the job can use '
          "`ctx.unattended`, whose errors are reported through the job's "
          'hooks; it does not keep the queue occupied.');
    });
  });

  group('11. Releasing a resource returned after cancellation', () {
    test('the stale buffer is released when it arrives, after close', () {
      late preview.Decoder decoder;
      late preview.PreviewController controller;
      Outcome<void>? staleBeforeAnyBuffer;
      var startedWithoutWaiting = false;
      var closedBeforeTheLateBuffer = false;
      late preview.Buffer current;
      late preview.Buffer stale;
      final errors = _zone((async) {
        decoder = preview.Decoder();
        controller = preview.PreviewController(decoder);
        const first = preview.Clip(1);
        const second = preview.Clip(2);
        final replaced = controller.open(first);
        async.flushMicrotasks();
        controller.open(second);
        async.flushMicrotasks();
        staleBeforeAnyBuffer = replaced.outcome;
        startedWithoutWaiting = '${decoder.trace}' == '[open 1, open 2]';
        current = decoder.deliver(second);
        async.flushMicrotasks();
        controller.close();
        async.flushMicrotasks();
        closedBeforeTheLateBuffer = controller.isFinished;
        stale = decoder.deliver(first);
        async.flushMicrotasks();
      });
      expect(errors, isEmpty);
      expect('$staleBeforeAnyBuffer', 'Cancelled(replaced)');
      expect(startedWithoutWaiting, isTrue);
      expect(closedBeforeTheLateBuffer, isTrue);
      expect(
        '${decoder.trace}',
        '[open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1]',
      );
      expect('${controller.currentState}', 'Preview(2)');
      expect([current.releases, stale.releases], [1, 1]);
      _says('`ctx.abandonable` can end the cancelled job before the decoder '
          'finishes. A late buffer is still passed to `dispose`');
      _says('The replacement job may therefore start without waiting for '
          'the obsolete decode, while each buffer is released.');
      _says('The guarded bloc and this controller both go through `[open 1, '
          'open 2, ready 2, sample 2, release 2, ready 1, release 1]` and '
          'end at `Preview(2)`.');
      _says('In solo, `close()` finishes before the obsolete buffer '
          'arrives; it is released when decoding finally returns it.');
    });

    test('with discard the buffer of a successful job is not released', () {
      late preview.Buffer current;
      late preview.Buffer stale;
      Outcome<void>? done;
      final errors = _zone((async) {
        final decoder = preview.Decoder();
        final controller = preview.OtherPreviewController(decoder)
          ..openDiscarding(const preview.Clip(1));
        async.flushMicrotasks();
        final job = controller.openDiscarding(const preview.Clip(2));
        async.flushMicrotasks();
        current = decoder.deliver(const preview.Clip(2));
        async.flushMicrotasks();
        stale = decoder.deliver(const preview.Clip(1));
        async.flushMicrotasks();
        done = job.outcome;
      });
      expect(errors, isEmpty);
      expect('$done', 'Done(null)');
      expect([current.releases, stale.releases], [0, 1]);
      _says('`discard` is for a resource handed to the caller as the '
          'successful result; it would not release this temporary buffer '
          'after a successful waveform update.');
    });

    test('with join the queue and close wait for the decode', () {
      late preview.Decoder decoder;
      var closedWhilePending = true;
      var closed = false;
      late preview.Buffer buffer;
      final outcomes = <String>[];
      final errors = _zone((async) {
        decoder = preview.Decoder();
        final controller = preview.OtherPreviewController(decoder);
        final first = controller.openJoining(const preview.Clip(1));
        async.flushMicrotasks();
        final second = controller.openJoining(const preview.Clip(2));
        async.flushMicrotasks();
        controller.close().then((_) => closed = true);
        async.flushMicrotasks();
        closedWhilePending = closed || first.outcome != null;
        buffer = decoder.deliver(const preview.Clip(1));
        async.flushMicrotasks();
        outcomes.addAll(['${first.outcome}', '${second.outcome}']);
      });
      expect(errors, isEmpty);
      expect(closedWhilePending, isFalse);
      expect(closed, isTrue);
      // The second decode never began: the first one held the queue.
      expect(decoder.trace, ['open 1', 'ready 1', 'release 1']);
      expect(buffer.releases, 1);
      expect(outcomes, ['Cancelled(replaced)', 'Cancelled(closed)']);
      _says('Use `join` when both the operation and its resource release '
          'must finish before the queue or controller proceeds.');
    });
  });
}
