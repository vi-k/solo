import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_code.dart';
import 'support/readme_profile.dart';
import 'support/testing_code.dart';
import 'support/testing_variants.dart';

/// The sentinel of `doc/testing.md`.
///
/// The code of the page stands verbatim in `test/support/testing_code.dart`,
/// over the model of the README, `readme_profile.dart`. The tests below run
/// that code. What the page says in prose about a version it does not show
/// is run from `testing_variants.dart`, and a test that checks a sentence
/// holds the page to it through [_says].
///
/// The bench `tool/flutter_snippets.py` builds the same code out of the
/// markdown itself, in a package of its own; this file is what `flutter
/// test` of the package knows about the page.

const _doc = 'doc/testing.md';
const _code = 'test/support/testing_code.dart';

String _page() => File(_doc).readAsStringSync();

/// The page without its code, every run of whitespace turned into one
/// space, so that a phrase is found wherever its lines were broken.
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

/// Runs [body] the way `testWidgets` runs the body of a widget test — on the
/// fake clock of the binding, in a zone that fails the test on an uncaught
/// error — and returns what it reported as failures instead of failing.
///
/// For a plain `test` only: the binding does not nest one widget test in
/// another.
Future<List<FlutterErrorDetails>> _asWidgetTest(
  Future<void> Function(TestWidgetsFlutterBinding binding) body,
) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final reported = <FlutterErrorDetails>[];
  final reporter = reportTestException;
  reportTestException = (details, description) => reported.add(details);
  try {
    await binding.runTest(
      () => body(binding),
      () {},
      description: 'a first attempt of the page',
    );
  } finally {
    reportTestException = reporter;
    binding.postTest();
  }
  return reported;
}

void main() {
  // A widget test is given ten minutes by default, and a sentinel that
  // takes that long to say a wait never ended is one nobody runs.
  (TestWidgetsFlutterBinding.ensureInitialized()
          as AutomatedTestWidgetsFlutterBinding)
      .defaultTestTimeout = const Timeout(Duration(seconds: 30));

  group('The page', () {
    test('every piece of its code stands in the support file', () {
      expect(codeMissingFrom(_doc, _code), isEmpty);
    });

    test('its blocks are dart', () {
      expect(strayFences(_doc), isEmpty);
      expect(
        RegExp(r'^```dart$', multiLine: true).allMatches(_page()),
        hasLength(3),
        reason: 'a new block of the page needs a place in the support file '
            'and a test that runs it',
      );
    });
  });

  group('The first attempt', () {
    testWidgets('the first attempt stands until the clock moves',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );

      var through = false;
      unawaited(firstAttempt(tester, controller).then((_) => through = true));
      await tester.pump();
      await tester.pump();
      await tester.idle();
      expect(through, isFalse);
      expect(controller.currentState, isA<Loading>());

      // It is the clock it was waiting for, and nothing else. The clock is
      // moved without a pump: the attempt pumps a frame of its own as it
      // comes through, and the tester takes one call at a time.
      await tester.binding.delayed(const Duration(milliseconds: 9));
      await tester.idle();
      expect(through, isFalse);
      await tester.binding.delayed(const Duration(milliseconds: 1));
      await tester.idle();
      expect(through, isTrue);
      expect(find.text('Ada Lovelace'), findsOneWidget);

      await controller.close();
      _says('it answers with the name ten milliseconds after the call');
      _says('The test never gets past the first line');
      _says('Nothing inside `testWidgets` moves that clock but the test.');
      _says('the test moves the clock, with `pump` or `pumpAndSettle`; '
          'awaiting a job does not move it');
    });
  });

  group('Moving the clock', () {
    theProfileAppears();

    testWidgets('pumpAndSettle waits for the screen, not for the job',
        (tester) async {
      const second = Duration(seconds: 1);

      // A slow load under the spinner of the page: the spinner keeps asking
      // for frames, and the clock runs until the name is there.
      final spinning = ProfileController(FakeApi(delay: second));
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: spinning)),
      );
      await tester.tap(find.text('Load'));
      var before = tester.binding.clock.now();
      await tester.pumpAndSettle();
      expect(
        tester.binding.clock.now().difference(before),
        greaterThan(second),
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);

      // The same load with nothing animating.
      final quiet = ProfileController(FakeApi(delay: second));
      await tester.pumpWidget(
        MaterialApp(home: QuietView(controller: quiet)),
      );
      await tester.tap(find.text('Load'));
      before = tester.binding.clock.now();
      final frames = await tester.pumpAndSettle();
      expect(frames, lessThanOrEqualTo(2));
      expect(
        tester.binding.clock.now().difference(before),
        const Duration(milliseconds: 100) * frames,
      );
      expect(quiet.currentState, isA<Loading>());
      expect(find.text('Loading'), findsOneWidget);

      await tester.pump(second);
      await spinning.close();
      await quiet.close();
      _says('`pumpAndSettle` pumps a frame every hundred milliseconds for as '
          'long as another frame is asked for.');
      _says('A slower one would be waited for as well, because the spinner '
          'of `Loading` keeps asking for frames.');
      _says('With nothing animating, `pumpAndSettle` stops after a frame or '
          'two, and a load that takes longer than that is still waiting.');
    });

    testWidgets('closed in the body, a controller with a load running lets go',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );
      await tester.tap(find.text('Load'));
      await tester.pump();
      expect(controller.currentState, isA<Loading>());

      await controller.close();

      expect(controller.isFinished, isTrue);
      // The call the load walked away from is the fake's own timer.
      await tester.pump(const Duration(milliseconds: 10));
      _says('The controller is closed in the body of the test, not in '
          '`addTearDown`.');
    });

    test('awaited once the clock has stopped, the same close() never returns',
        () async {
      late ProfileController controller;
      final reported = await _asWidgetTest((binding) async {
        // The answer of this API never comes, so the load is still running
        // when the body ends, as it is when an expectation fails halfway
        // through one.
        controller = ProfileController(SilentApi());
        controller.load().ignoreFailure();
        await binding.pump();
        expect(controller.currentState, isA<Loading>());
      });
      expect(reported, isEmpty);

      // What a tear-down does next.
      var back = false;
      unawaited(controller.close().then((_) => back = true));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(back, isFalse);
      expect(controller.isFinished, isFalse);
      _says('the test closes the controller in its body, not in '
          '`addTearDown`');
      _says('A tear-down runs after the fake clock has stopped. A `close()` '
          'awaited there with a job still running never comes back, and an '
          'expectation that failed halfway through a load is enough to leave '
          'one running.');
    });

    for (final timed in [true, false]) {
      test(
          'a job ${timed ? 'with' : 'without'} a deadline left running when '
          'the body ends', () async {
        late Solo<Profile> controller;
        final reported = await _asWidgetTest((binding) async {
          if (timed) {
            final load = TimedLoad(SilentApi());
            controller = load;
            load.load().ignoreFailure();
          } else {
            final load = ProfileController(SilentApi());
            controller = load;
            load.load().ignoreFailure();
          }
          await binding.pump();
          expect(controller.currentState, isA<Loading>());
        });

        expect(
          [for (final details in reported) '${details.exception}'],
          [
            if (timed)
              contains(
                'A Timer is still pending even after the widget tree was '
                'disposed',
              ),
          ],
        );
        _says('Left running when the body of a `testWidgets` ends, such a job '
            'fails the test with '
            '`A Timer is still pending even after the widget tree was '
            'disposed`. The same job without a deadline lets the test pass.');
        unawaited(controller.close());
      });
    }

    test('closed in the body, a job with a deadline takes its timer along',
        () async {
      late TimedLoad controller;
      final reported = await _asWidgetTest((binding) async {
        controller = TimedLoad(SilentApi());
        final job = controller.load()..ignoreFailure();
        await binding.pump();
        await controller.close();
        expect('${job.outcome}', 'Cancelled(closed)');
      });

      expect(reported, isEmpty);
      expect(controller.isFinished, isTrue);
      _says('Closing the controller in the body, as above, ends the job and '
          'takes its timer along.');
    });
  });

  group('Waiting for the job', () {
    testWidgets('the handle waits for the job, and its pump leaves the frame',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );

      final outcome = await theHandle(tester, controller);

      expect(outcome, isA<Done<String>>());
      expect(find.text('Ada Lovelace'), findsOneWidget);
      await controller.close();
      _says('`pump` with a duration moves the clock and then draws, so the '
          'frame it leaves shows the last state.');
    });

    testWidgets('twenty milliseconds are more than the fake takes',
        (tester) async {
      // The handle of the page over a fake that takes longer than its pump
      // gives it: the outcome is not there yet.
      final controller = ProfileController(
        FakeApi(delay: const Duration(milliseconds: 21)),
      );
      final done = controller.load().done;
      Outcome<String>? outcome;
      unawaited(done.then((value) => outcome = value));
      await tester.pump(const Duration(milliseconds: 20));
      expect(outcome, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(outcome, isA<Done<String>>());

      expect(FakeApi().delay, const Duration(milliseconds: 10));
      await controller.close();
    });

    testWidgets('read before the clock moves, a load that fails is no trouble',
        (tester) async {
      final controller = ProfileController(
        FakeApi(error: StateError('no network')),
      );
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );

      final outcome = await theHandle(tester, controller);

      expect(outcome, isA<Failed>());
      expect(find.text('Load'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await controller.close();
      _says('`done` is read on the first line, before the clock moves, and '
          'the order matters');
    });

    test('read after the pump, the same load fails the test', () async {
      Object? taken = 'never asked';
      Outcome<String>? outcome;
      final reported = await _asWidgetTest((binding) async {
        final controller = ProfileController(
          FakeApi(error: StateError('no network')),
        );
        final job = controller.load();
        await binding.pump(const Duration(milliseconds: 20));
        taken = binding.takeException();
        outcome = await job.done;
        await controller.close();
      });

      expect(reported.single.exception, isA<StateError>());
      expect(taken, isNull);
      expect(outcome, isA<Failed>(), reason: 'the test did read done');
      _says('a test that reads `done` reads it before it moves the clock');
      _says('A `Failed` nobody has asked about is reported as the job ends, '
          'to the zone it was created in. Here that is the zone of the test, '
          'which fails the test on the spot, and `tester.takeException()` '
          'has nothing to take afterwards.');
      _says('A load that fails makes a test red even though it reads `done`, '
          'if it reads it after the pump.');
    });

    testWidgets('a job the test drops says so with ignoreFailure()',
        (tester) async {
      final controller = ProfileController(
        FakeApi(error: StateError('no network')),
      );
      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 20));

      expect(controller.currentState, isA<Empty>());
      await controller.close();
      _says('A job the test starts and drops says so with `ignoreFailure()`.');
    });

    testWidgets('one pump after load() moves the state and not the screen',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );
      // The frame a `MaterialApp` asks for after its first.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      controller.load().ignoreFailure();
      await tester.pump();
      expect(controller.currentState, isA<Loading>());
      expect(find.text('Load'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 10));
      await controller.close();
      _says('after `controller.load()` and one `pump()` the state has moved '
          'and the screen has not');
      _says('A second `pump()` draws it.');
    });

    testWidgets('right after a MaterialApp has been pumped, one pump draws it',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );
      expect(tester.binding.hasScheduledFrame, isTrue);

      controller.load().ignoreFailure();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 10));
      await controller.close();
      _says('unless a frame was already asked for, as one is right after a '
          '`MaterialApp` has been pumped');
    });
  });
}
