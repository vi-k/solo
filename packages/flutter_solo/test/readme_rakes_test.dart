import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_code.dart';
import 'support/readme_install.dart';
import 'support/readme_listenable.dart' as listenable;
import 'support/readme_profile.dart';
import 'support/readme_variants.dart';
import 'support/readme_widgets.dart';

/// The sentinel of `README.md`.
///
/// The code of the page stands verbatim in two files of `test/support/`:
/// `readme_profile.dart` holds the model of "Usage", and
/// `readme_widgets.dart` the fragments between "Why" and "Outcomes" but for
/// the two that take scopo, which stand in `readme_scopo.dart` and are run
/// by `readme_scopo_test.dart`. The tests below run the rest. The
/// one block the page cuts short, the controller of "Usage" with the mixin
/// and `// ...same as above...` for a body, stands in full in
/// `readme_listenable.dart`, imported here as `listenable`: a test over a
/// fragment that needs a `ValueListenable` builds that controller. What
/// the page says in prose about a version it does not show is run from
/// `readme_variants.dart`, and a test that checks a sentence holds the page
/// to it through [_says].
///
/// The bench `tool/flutter_snippets.py` builds the same code out of the
/// markdown itself, in a package of its own; this file is what `flutter
/// test` of the package knows about the page. The translation is not read
/// here: `README.ru.md` is kept out of the published archive, where these
/// tests run as well, and `tool/check_translations.py` holds it to the page.

const _doc = 'README.md';

/// The block of the page that stands for a class and leaves its body out.
const _cutShort =
    'final class ProfileController extends Solo<Profile> '
    'with SoloListenable {\n'
    '  // ...same as above...\n'
    '}';
const _support = [
  'test/support/readme_profile.dart',
  'test/support/readme_widgets.dart',
  'test/support/readme_install.dart',
  'test/support/readme_scopo.dart',
];

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

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// What the Save button on the screen would call, or `null` when it is
/// disabled.
VoidCallback? _save(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed;

List<String?> _texts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text))) text.data,
];

/// A controller of the page with its profile loaded.
Future<ProfileController> _loaded(WidgetTester tester) async {
  final controller = ProfileController(ProfileApi());
  controller.load().ignoreFailure();
  await tester.pump(const Duration(milliseconds: 10));
  expect(controller.currentState, isA<Loaded>());
  return controller;
}

/// The same with `SoloListenable` mixed in.
Future<listenable.ProfileController> _loadedListenable(
  WidgetTester tester,
) async {
  final controller = listenable.ProfileController(ProfileApi());
  controller.load().ignoreFailure();
  await tester.pump(const Duration(milliseconds: 10));
  expect(controller.value, isA<Loaded>());
  return controller;
}

/// The members of `ProfileController` as [file] declares them.
String _controllerBody(String file) {
  final source = File(file).readAsStringSync();
  final start = source.indexOf(
    '\n',
    source.indexOf('final class ProfileController extends Solo<Profile>'),
  );
  return source.substring(start, source.indexOf('\n}\n', start));
}

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
      .defaultTestTimeout = const Timeout(
    Duration(seconds: 30),
  );

  group('The page', () {
    test('every piece of its code stands in the support files', () {
      // But for the block that cuts its body short: the group of its
      // section holds that one to the controller of "Usage".
      expect(
        codeMissingFrom(
          _doc,
          _support.first,
          alsoIn: _support.skip(1).toList(),
        ),
        [_cutShort],
      );
    });

    test('its blocks are dart, but for one line of shell', () {
      expect(strayFences(_doc), ['```sh']);
      expect(
        RegExp(r'^```dart$', multiLine: true).allMatches(_page()),
        hasLength(17),
        reason:
            'a new block of the page needs a place in the support files '
            'and a test that runs it',
      );
    });
  });

  group('Why', () {
    test('the fragment prints the outcome of the load it cancelled', () async {
      final controller = ProfileController(ProfileApi());
      final printed = <String>[];
      await runZoned(
        () => why(controller),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(printed, ['Cancelled(manual)']);
      await controller.close();
      _says('Here a method stays a method, and it hands back a handle:');
    });

    testWidgets('cancel() comes back when the job has stopped', (tester) async {
      final api = ProfileApi();
      final controller = ProfileController(api);
      final job = controller.load();
      await tester.pump(const Duration(milliseconds: 3));
      expect(controller.currentState, isA<Loading>());

      await job.cancel();

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(controller.currentState, isA<Empty>());
      // The request the job walked away from is still on its way.
      expect(api.trace, ['fetch begins']);
      await tester.pump(const Duration(milliseconds: 10));
      expect(api.trace, ['fetch begins', 'fetch ends']);
      expect(controller.currentState, isA<Empty>());
      await controller.close();
    });

    testWidgets('root jobs run one at a time', (tester) async {
      final bench = Bench();
      final log = <String>[];
      Job<void> step(String name) => bench.go<Profile, void>((ctx) async {
        log.add('$name begins');
        await ctx.pause(const Duration(milliseconds: 5));
        log.add('$name ends');
      });

      step('a').ignoreFailure();
      step('b').ignoreFailure();
      step('c').ignoreFailure();
      await tester.pump(const Duration(milliseconds: 15));

      expect(log, [
        'a begins',
        'a ends',
        'b begins',
        'b ends',
        'c begins',
        'c ends',
      ]);
      await bench.close();
      _says(
        'One root job of a controller at a time, so two of them never '
        'write the same state.',
      );
    });

    testWidgets('a job is cancelled when its rules stop holding', (
      tester,
    ) async {
      final bench = Bench(Loaded('Ada'));
      final typed = bench.go<Loaded, String>((ctx) async {
        await ctx.pause(const Duration(milliseconds: 10));
        return ctx.state.name;
      });
      await tester.pump(const Duration(milliseconds: 3));
      bench.set(Empty());
      await tester.pump();
      expect('${typed.outcome}', 'Cancelled(rules: is not Loaded)');

      bench.set(Loaded('Ada'));
      final kept = bench.go<Profile, String>(
        keepWhile: (state) => state is Loaded,
        (ctx) async {
          await ctx.pause(const Duration(milliseconds: 10));
          return 'went on';
        },
      );
      await tester.pump(const Duration(milliseconds: 3));
      bench.set(Empty());
      await tester.pump();
      expect('${kept.outcome}', 'Cancelled(rules: keepWhile)');

      await bench.close();
      _says(
        'a job declares the states it works with and the condition it '
        'lives under, and it is cancelled when they stop holding',
      );
    });

    testWidgets('a body that never reaches a checkpoint ends Cancelled', (
      tester,
    ) async {
      final bench = Bench();
      final log = <String>[];
      final writing = bench.go<Profile, String>((ctx) async {
        // The check this body forgot is the point of the test.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('the bare await went on');
        ctx.emit(Loaded('written past the cancellation'));
        return 'done anyway';
      });
      await tester.pump(const Duration(milliseconds: 3));
      unawaited(writing.cancel());
      await tester.pump(const Duration(milliseconds: 10));

      expect(log, ['the bare await went on']);
      expect('${writing.outcome}', 'Cancelled(manual)');
      expect(bench.value, isA<Empty>());

      // A body that never asks the context again ends `Cancelled` as well.
      final deaf = bench.go<Profile, String>((ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'done anyway';
      });
      await tester.pump(const Duration(milliseconds: 3));
      unawaited(deaf.cancel());
      await tester.pump(const Duration(milliseconds: 10));
      expect('${deaf.outcome}', 'Cancelled(manual)');

      await bench.close();
      _says(
        'A cancellation the caller can ask for: the next checkpoint of '
        'the context throws it, and a body that never reaches one still '
        'ends `Cancelled` and writes no state of its own.',
      );
    });

    testWidgets('every job ends with one of three outcomes', (tester) async {
      final done = ProfileController(ProfileApi()).load();
      final failed = ProfileController(
        ProfileApi(error: StateError('no network')),
      ).load()..ignoreFailure();
      final cancelled = ProfileController(ProfileApi()).load();
      unawaited(cancelled.cancel());
      await tester.pump(const Duration(milliseconds: 10));

      expect(done.outcome, isA<Done<String>>());
      expect(failed.outcome, isA<Failed>());
      expect(cancelled.outcome, isA<Cancelled>());
      _says(
        'An outcome for every job, one of `Done`, `Failed` and '
        '`Cancelled`,',
      );
    });
  });

  group('Install', () {
    test('one import brings the engine, the mixin and the widgets', () {
      expect(arrivesWithOneImport, hasLength(10));
      expect(
        File('lib/flutter_solo.dart').readAsStringSync(),
        contains("export 'package:solo/solo.dart';"),
      );
      _says(
        '`Solo`, `SoloContext`, `Job`, `Outcome` and `Policy` all arrive '
        'with',
      );
      _says(
        'the mixin `SoloListenable`, the widgets `SoloBuilder` and '
        '`SoloSelector`, and the class `SoloSelection`',
      );
    });

    test('select, listen and the subscriptions are in the second import', () {
      final first = File('lib/flutter_solo.dart').readAsStringSync();
      final second = File('lib/listenable.dart').readAsStringSync();

      expect(first, isNot(contains('subscription.dart')));
      expect(first, contains("'src/solo_selection.dart' show SoloSelection;"));
      expect(second, contains("'src/solo_selection.dart' show SoloSelect;"));
      expect(second, contains("export 'src/subscription.dart';"));
      _says(
        'A second import next door adds `select` and `listen` as '
        'methods, with the subscriptions `listen` hands back',
      );
      _says(
        '`SoloSubscription` and `SoloSubscriptions` come with the second '
        'import only',
      );
    });
  });

  group('Usage', () {
    test(
      'ProfileApi is the service with the two methods the page names',
      () async {
        final api = ProfileApi(delay: Duration.zero);
        expect(api.fetchName, isA<Future<String> Function()>());
        expect(api.saveName, isA<Future<void> Function(String)>());

        expect(await api.fetchName(), 'Ada Lovelace');
        await api.saveName('Grace Hopper');
        expect(api.saved, ['Grace Hopper']);
        await expectLater(
          ProfileApi(
            delay: Duration.zero,
            error: const ApiException('no network'),
          ).fetchName(),
          throwsA(isA<ApiException>()),
        );
        _says(
          "`ProfileApi` stands for the app's own service: `fetchName()` "
          'returns a `Future<String>`, and `saveName(name)` a '
          '`Future<void>`. A call of `fetchName()` that fails throws an '
          '`ApiException`.',
        );
      },
    );

    testWidgets('a second tap returns the first job', (tester) async {
      final api = ProfileApi();
      final controller = ProfileController(api);
      await tester.pumpWidget(_app(ProfileView(controller: controller)));

      final first = controller.load();
      expect(identical(controller.load(), first), isTrue);
      await tester.pump(const Duration(milliseconds: 3));
      expect(identical(controller.load(), first), isTrue);
      await tester.pump(const Duration(milliseconds: 10));

      expect(api.trace, ['fetch begins', 'fetch ends']);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      // Once that job has ended, a call starts another.
      expect(identical(controller.load(), first), isFalse);
      await tester.pump(const Duration(milliseconds: 10));
      await controller.close();
    });

    testWidgets('the handlers take a failed or cancelled load back to Empty', (
      tester,
    ) async {
      final failing = ProfileController(
        ProfileApi(error: StateError('no network')),
      );
      failing.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(failing.currentState, isA<Empty>());

      final cancelled = ProfileController(ProfileApi());
      final job = cancelled.load();
      await tester.pump(const Duration(milliseconds: 3));
      await job.cancel();
      expect(cancelled.currentState, isA<Empty>());

      await tester.pump(const Duration(milliseconds: 10));
      _says(
        'They say what state a load that failed or was cancelled leaves '
        'behind.',
      );
    });

    testWidgets('without them the state stays on Loading', (tester) async {
      final failing = Handlerless(ProfileApi(error: StateError('no network')));
      failing.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(failing.value, isA<Loading>());

      final cancelled = Handlerless(ProfileApi());
      final job = cancelled.load();
      await tester.pump(const Duration(milliseconds: 3));
      await job.cancel();
      expect(cancelled.value, isA<Loading>());

      await tester.pump(const Duration(milliseconds: 10));
      _says(
        'Without them the screen would keep the spinner of a job that '
        'is no longer running.',
      );
    });

    testWidgets('a tap on Load that fails puts Empty back and fails no test', (
      tester,
    ) async {
      final controller = ProfileController(
        ProfileApi(error: const ApiException('no network')),
      );
      await tester.pumpWidget(_app(ProfileView(controller: controller)));

      // The button has no `ignoreFailure()`: `isExpectedError` names the
      // failure, and a failure it left to the zone would fail this test.
      await tester.tap(find.text('Load'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 10));

      expect(controller.currentState, isA<Empty>());
      expect(find.text('Load'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await controller.close();
      _says(
        '`isExpectedError` names the failures the screen is all the answer '
        'for: an `ApiException` goes no further than `Empty`, and a bug, '
        'which is not an `ApiException`, still goes on to the zone.',
      );
    });

    testWidgets('a load that fails with a bug', (tester) async {
      final controller = ProfileController(
        ProfileApi(error: StateError('a bug')),
      );
      await tester.pumpWidget(_app(ProfileView(controller: controller)));

      // The tap creates the job in a zone of its own, where its failure
      // goes; in a widget test that zone would be the test's.
      final errors = <Object>[];
      await runZonedGuarded(
        () => tester.tap(find.text('Load')),
        (error, stackTrace) => errors.add(error),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(controller.currentState, isA<Empty>());
      expect(errors, [isA<StateError>()]);
      await controller.close();
      _says('a bug, which is not an `ApiException`, still goes on to the zone');
    });

    test('a button that drops the job hands a bug to the zone', () async {
      Profile? state;
      final reported = await _asWidgetTest((binding) async {
        final controller = ProfileController(
          ProfileApi(error: StateError('a bug')),
        );
        // What `onPressed: controller.load` calls: the job it hands back
        // goes nowhere.
        final VoidCallback onPressed = controller.load;
        onPressed();
        await binding.pump(const Duration(milliseconds: 10));
        state = controller.currentState;
        await controller.close();
      });

      expect(state, isA<Empty>(), reason: 'ifFailed has answered on screen');
      expect(reported.single.exception, isA<StateError>());
      _says(
        'The button drops the job that `load` hands back. A failure '
        'nobody reads goes on to the zone even after `ifFailed` has put '
        '`Empty` on the screen, unless `Solo.unansweredHandler` answers for '
        'it. In an app it goes towards '
        '`PlatformDispatcher.onError`, in a widget test into the test, '
        'which fails.',
      );
    });

    testWidgets('save does not start over a state that is not Loaded', (
      tester,
    ) async {
      final api = ProfileApi();
      final controller = ProfileController(api);

      final early = controller.save();
      await tester.pump();
      expect('${early.outcome}', 'Cancelled(rules: is not Loaded)');
      expect(api.trace, isEmpty);

      // Asked for while the load is ahead of it, it starts once the state
      // is Loaded.
      controller.load().ignoreFailure();
      final queued = controller.save();
      await tester.pump(const Duration(milliseconds: 20));
      expect(queued.outcome, isA<Done<void>>());
      expect(api.saved, ['Ada Lovelace']);

      await controller.close();
      _says(
        '`save` narrows that to `Loaded`: it does not start in any '
        'other state, it ends `Cancelled` there, and its body reads a '
        '`Loaded` with a `name` in it.',
      );
    });

    testWidgets('abandonable gives up at once, join waits its call out', (
      tester,
    ) async {
      final api = ProfileApi();
      final controller = ProfileController(api);

      final load = controller.load();
      await tester.pump(const Duration(milliseconds: 3));
      unawaited(load.cancel());
      await tester.pump();
      expect('${load.outcome}', 'Cancelled(manual)');
      expect(api.trace, ['fetch begins']);
      await tester.pump(const Duration(milliseconds: 10));

      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      api.trace.clear();
      final save = controller.save();
      await tester.pump(const Duration(milliseconds: 3));
      unawaited(save.cancel());
      await tester.pump();
      expect(save.outcome, isNull, reason: 'the call is still on its way');
      await tester.pump(const Duration(milliseconds: 10));
      expect('${save.outcome}', 'Cancelled(manual)');
      expect(api.trace, ['save begins', 'save ends']);
      expect(api.saved, ['Ada Lovelace']);

      await controller.close();
      _says(
        '`ctx.abandonable` awaits like `await`, except that it gives up '
        'the moment the job is cancelled.',
      );
      _says(
        '`ctx.join` waits its call out either way, so a save is not cut '
        'in half.',
      );
    });

    testWidgets('the builder rebuilds on every change and leaves child alone', (
      tester,
    ) async {
      final plain = Plain();
      final built = <String>[];
      var childBuilds = 0;
      await tester.pumpWidget(
        _app(
          SoloBuilder<Profile>(
            solo: plain,
            child: Builder(
              builder: (context) {
                childBuilds++;
                return const SizedBox();
              },
            ),
            builder: (context, state, child) {
              built.add(show(state));
              return child!;
            },
          ),
        ),
      );
      final same = Loaded('Ada');
      for (final state in [same, same, Loaded('Ada')]) {
        plain.set(state);
        await tester.pump();
      }

      expect(built, ['Empty', 'Loaded(Ada)', 'Loaded(Ada)', 'Loaded(Ada)']);
      expect(childBuilds, 1);
      await plain.close();
      _says(
        '`SoloBuilder` is what draws the state: it takes the controller '
        'as `solo`, rebuilds on every change of the state and hands '
        '`child` through untouched.',
      );
    });
  });

  group('Selecting one value', () {
    test(
      'the Save button drops the job, and a failed save reaches the zone',
      () async {
        Profile? state;
        final reported = await _asWidgetTest((binding) async {
          final controller = ProfileController(
            ProfileApi(saveError: StateError('save offline')),
          );
          controller.load().ignoreFailure();
          await binding.pump(const Duration(milliseconds: 10));
          // What `onPressed: canSave ? controller.save : null` calls on a
          // loaded profile: the job it hands back goes nowhere.
          final VoidCallback onPressed = controller.save;
          onPressed();
          await binding.pump(const Duration(milliseconds: 10));
          state = controller.currentState;
          await controller.close();
        });

        expect(state, isA<Loaded>(), reason: 'nothing on the screen says so');
        expect('${reported.single.exception}', 'Bad state: save offline');
        _says(
          'A save that fails leaves the state `Loaded`, and nothing on the '
          'screen says so. `save` has no `ifFailed`, so its failure goes on '
          'to the zone, with no `Solo.unansweredHandler` set',
        );
      },
    );

    testWidgets('the selector rebuilds only when the pick changes', (
      tester,
    ) async {
      final controller = ProfileController(ProfileApi());
      await tester.pumpWidget(_app(saveSelector(controller)));
      expect(_save(tester), isNull);

      controller.load().ignoreFailure();
      await tester.pump();
      await tester.pump();
      expect(controller.currentState, isA<Loading>());
      expect(_save(tester), isNull);
      await tester.pump(const Duration(milliseconds: 10));
      expect(_save(tester), isNotNull);

      // The same widget, counting its builds.
      final bench = Bench();
      final built = <bool>[];
      await tester.pumpWidget(
        _app(
          SoloSelector<Profile, bool>(
            solo: bench,
            selector: (state) => state.canSave,
            builder: (context, canSave, _) {
              built.add(canSave);
              return const SizedBox();
            },
          ),
        ),
      );
      for (final state in [Loading(), Empty(), Loaded('Ada'), Loaded('Bob')]) {
        bench.set(state);
        await tester.pump();
      }
      expect(built, [false, true]);

      await controller.close();
      await bench.close();
      _says(
        '`SoloSelector` picks the field and rebuilds only when that field '
        'changes',
      );
    });

    testWidgets('changed answers in place of !=', (tester) async {
      final bench = Bench();
      final built = <int>[];
      await tester.pumpWidget(
        _app(
          SoloSelector<Profile, int>(
            solo: bench,
            selector: _length,
            changed: _far,
            builder: (context, length, _) {
              built.add(length);
              return const SizedBox();
            },
          ),
        ),
      );
      for (final name in ['A', 'Ab', 'Abc', 'Abcd']) {
        bench.set(Loaded(name));
        await tester.pump();
      }

      expect(built, [0, 3]);
      await bench.close();
      _says(
        'Picks count as changed when they are `!=`, unless `changed:` '
        'answers that question itself.',
      );
    });

    testWidgets('the selector runs once for every change', (tester) async {
      final plain = Plain();
      _picks = 0;
      await tester.pumpWidget(
        _app(
          SoloSelector<Profile, bool>(
            solo: plain,
            selector: _counted,
            builder: (context, canSave, _) => Text('$canSave'),
          ),
        ),
      );
      expect(_picks, 1);

      plain.set(Loading());
      expect(_picks, 2);
      plain.set(Loaded('Ada'));
      expect(_picks, 3);
      await tester.pump();
      expect(_picks, 3);
      expect(_texts(tester), ['true']);

      await plain.close();
      _says('The selector runs once for every change of the state');
      _says('`solo` is any controller, a `ValueListenable` or not.');
    });

    testWidgets('closures written in place cost a pick and no subscription', (
      tester,
    ) async {
      Future<Plain> rebuilt({required bool inline}) async {
        final plain = Plain();
        final parent = GlobalKey<ParentState>();
        await tester.pumpWidget(
          _app(
            Parent(
              key: parent,
              (context) => SoloSelector<Profile, bool>(
                solo: plain,
                selector: inline ? (state) => state.canSave : _counted,
                changed: inline
                    ? (previous, current) => previous != current
                    : null,
                builder: (context, canSave, _) => const SizedBox(),
              ),
            ),
          ),
        );
        expect((plain.added, plain.removed), (1, 0));
        _picks = 0;
        for (var build = 0; build < 3; build++) {
          parent.currentState!.again();
          await tester.pump();
        }
        return plain;
      }

      final inline = await rebuilt(inline: true);
      expect((inline.added, inline.removed), (1, 0));
      final held = await rebuilt(inline: false);
      expect((held.added, held.removed), (1, 0));
      expect(_picks, 0);

      // One pick for each build of the parent that brings a new closure.
      final plain = Plain();
      final parent = GlobalKey<ParentState>();
      var picks = 0;
      await tester.pumpWidget(
        _app(
          Parent(
            key: parent,
            (context) => SoloSelector<Profile, bool>(
              solo: plain,
              selector: (state) {
                picks++;
                return state.canSave;
              },
              builder: (context, canSave, _) => const SizedBox(),
            ),
          ),
        ),
      );
      picks = 0;
      parent.currentState!.again();
      await tester.pump();
      expect(picks, 1);

      await tester.pumpWidget(const SizedBox());
      await inline.close();
      await held.close();
      await plain.close();
      _says(
        'The selector and `changed:` can be closures written in place, '
        'as the selector is above.',
      );
      _says(
        'Such a closure is a new one on every build of the parent, and '
        'it may pick something else. So the widget picks once more and '
        'puts the pick to `changed:`.',
      );
      _says('It moves no subscription for that');
    });

    testWidgets('a parent rebuild leaves what changed compares with alone', (
      tester,
    ) async {
      Future<List<String?>> shown({required bool inline}) async {
        final plain = Plain();
        final parent = GlobalKey<ParentState>();
        await tester.pumpWidget(
          _app(
            Parent(
              key: parent,
              (context) => SoloSelector<Profile, int>(
                solo: plain,
                selector: inline
                    ? (state) => state is Loaded ? state.name.length : 0
                    : _length,
                changed: _far,
                builder: (context, length, _) => Text('$length'),
              ),
            ),
          ),
        );
        // Two letters are not far from none, so nothing is announced.
        plain.set(Loaded('Ab'));
        await tester.pump();
        final before = _texts(tester).single;
        parent.currentState!.again();
        await tester.pump();
        final after = _texts(tester).single;
        // Three are far from the none on the screen, and not from the two
        // a value started over would have shown.
        plain.set(Loaded('Abc'));
        await tester.pump();
        final later = _texts(tester).single;
        await tester.pumpWidget(const SizedBox());
        await plain.close();
        return [before, after, later];
      }

      expect(await shown(inline: false), ['0', '0', '3']);
      expect(await shown(inline: true), ['0', '0', '3']);
      _says(
        '`changed:` still compares against the last pick the widget '
        'accepted.',
      );
    });

    testWidgets('two changes before a frame: the second against the first', (
      tester,
    ) async {
      Future<(List<String>, String?)> run({
        required bool frameApart,
        bool parentRebuilds = false,
      }) async {
        final plain = Plain();
        final parent = GlobalKey<ParentState>();
        final log = <String>[];
        await tester.pumpWidget(
          _app(
            Parent(
              key: parent,
              // `changed:` is written in place, so a rebuild of the parent
              // asks once more.
              (context) => SoloSelector<Profile, int>(
                solo: plain,
                selector: _length,
                changed: (previous, current) {
                  log.add('$previous->$current');
                  return _far(previous, current);
                },
                builder: (context, length, _) {
                  log.add('build $length');
                  return Text('$length');
                },
              ),
            ),
          ),
        );
        // Three letters are far from none and accepted; five are not far
        // from three, and they are not put against the none on the screen.
        plain.set(Loaded('Abc'));
        if (frameApart) {
          await tester.pump();
        }
        plain.set(Loaded('Abcde'));
        if (parentRebuilds) {
          parent.currentState!.again();
        }
        await tester.pump();
        final screen = _texts(tester).single;
        await tester.pumpWidget(const SizedBox());
        await plain.close();
        return (log, screen);
      }

      final (together, endsAt) = await run(frameApart: false);
      final (apart, endsApartAt) = await run(frameApart: true);
      expect(together, ['build 0', '0->3', '3->5', 'build 3']);
      expect(apart, ['build 0', '0->3', 'build 3', '3->5']);
      expect(endsAt, '3');
      expect(endsApartAt, '3');
      _says(
        '`changed:` is handed two picks: the last one the widget '
        'accepted, as `previous`, and the new one.',
      );
      _says(
        'The builder has usually been given `previous`, but not always. '
        'When two changes come before a frame and the first is accepted, '
        'the second is put against it, and the builder has not seen it '
        'yet.',
      );
      _says(
        'So where the screen ends up depends on the changes alone, not on '
        'how they fall into frames.',
      );

      // The question a parent rebuild asks is put against the same pick.
      final (rebuilt, rebuiltEndsAt) = await run(
        frameApart: false,
        parentRebuilds: true,
      );
      final (rebuiltApart, rebuiltApartEndsAt) = await run(
        frameApart: true,
        parentRebuilds: true,
      );
      expect(rebuilt, ['build 0', '0->3', '3->5', '3->5', 'build 3']);
      expect(rebuiltApart, [
        'build 0',
        '0->3',
        'build 3',
        '3->5',
        '3->5',
        'build 3',
      ]);
      expect(rebuiltEndsAt, '3');
      expect(rebuiltApartEndsAt, '3');
      _says(
        '`changed:` still compares against the last pick the widget '
        'accepted.',
      );
    });

    testWidgets('the selection in a field follows a new controller', (
      tester,
    ) async {
      final loaded = await _loadedListenable(tester);
      final empty = listenable.ProfileController(ProfileApi());

      await tester.pumpWidget(_app(SaveButton(controller: loaded)));
      expect(_save(tester), isNotNull);
      await tester.pumpWidget(_app(SaveButton(controller: empty)));
      expect(_save(tester), isNull);
      await tester.pumpWidget(_app(SaveButton(controller: loaded)));
      expect(_save(tester), isNotNull);

      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(loaded.api.saved, ['Ada Lovelace']);

      await loaded.close();
      await empty.close();
      _says(
        'Where a listenable of the picked value is what you need, the '
        'same pick is made by an object, a `SoloSelection`, and a `State` '
        'holds it in a field:',
      );
    });

    test(
      'the dartdoc of SoloSelection shows members of the State of the page',
      () {
        // The example an editor shows is the page's own, which the test above
        // runs over a new controller: an example of its own once kept the
        // selection in a `late final` field and followed the old controller.
        final source = File('lib/src/solo_selection.dart').readAsStringSync();
        final start = source.indexOf('/// ```dart\n') + '/// ```dart\n'.length;
        final example = source
            .substring(start, source.indexOf('/// ```\n', start))
            .split('\n')
            .map((line) => line.replaceFirst(RegExp('^/// ?'), ''))
            .join('\n');
        expect(example, startsWith('late SoloSelection'));
        // Members of the page's `State`, as the class indents them.
        final members = example
            .split('\n')
            .map((line) => line.isEmpty ? line : '  $line')
            .join('\n');
        // Inside that class, not merely somewhere on the page.
        final page = _page();
        final at = page.indexOf('class _SaveButtonState');
        expect(at, isNot(-1));
        final body = page.substring(at, page.indexOf('\n}\n', at));
        expect(body, contains(members));
      },
    );

    test('a State follows a new controller by identity, not by ==', () {
      final readme = File('README.md').readAsStringSync();
      expect(
        readme,
        contains('!identical(widget.controller, oldWidget.controller)'),
      );
      expect(
        readme,
        isNot(contains('!= oldWidget.controller')),
        reason:
            'two controllers equal by == are still two sources, the way '
            'SoloBuilder treats them',
      );
    });

    testWidgets('without didUpdateWidget it stays with the old one', (
      tester,
    ) async {
      final loaded = await _loadedListenable(tester);
      final empty = listenable.ProfileController(ProfileApi());

      // From a loaded profile to an empty one: the button stays enabled,
      // and its tap goes to a controller that has nothing to save.
      await tester.pumpWidget(_app(StuckSaveButton(controller: loaded)));
      await tester.pumpWidget(_app(StuckSaveButton(controller: empty)));
      expect(_save(tester), isNotNull);
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(loaded.api.trace, ['fetch begins', 'fetch ends']);
      expect(empty.api.trace, isEmpty, reason: 'the rule of save refused it');

      // The other way round the button stays disabled over a profile that
      // could be saved.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(StuckSaveButton(controller: empty)));
      await tester.pumpWidget(_app(StuckSaveButton(controller: loaded)));
      expect(_save(tester), isNull);

      await loaded.close();
      await empty.close();
      _says(
        'The initializer of the field runs once, though, and reads '
        '`widget.controller` as it is at that moment.',
      );
      _says(
        'The `State` outlives the widget: a parent that rebuilds can '
        'hand it a new `SaveButton` with another controller. Without '
        '`didUpdateWidget` the button would go on taking its permission '
        'from the old controller while its tap went to the new one.',
      );
    });

    testWidgets('a selection built inside build is a new one every build', (
      tester,
    ) async {
      final bench = Bench();
      final parent = GlobalKey<ParentState>();
      final built = <int>[];
      await tester.pumpWidget(
        _app(
          Parent(
            key: parent,
            (context) => ValueListenableBuilder<int>(
              valueListenable: SoloSelection<Profile, int>(
                bench,
                _length,
                changed: _far,
              ),
              builder: (context, length, _) {
                built.add(length);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect((bench.added, bench.removed), (1, 0));

      for (final name in ['A', 'Ab']) {
        bench.set(Loaded(name));
        parent.currentState!.again();
        await tester.pump();
      }

      // Every build unsubscribed from one selection and subscribed to the
      // next, and each of them started from the pick of the moment: a
      // selection that was held would still show none.
      expect((bench.added, bench.removed), (3, 2));
      expect(built, [0, 1, 2]);

      await tester.pumpWidget(const SizedBox());
      await bench.close();
      _says(
        'One built inside `build` is a new object on every build. The '
        'builder under it then unsubscribes from the old one and '
        'subscribes to the new, and each new selection starts from a pick '
        'of its own, so the pick a change is compared against starts over '
        'on every build.',
      );
    });

    test('the source is subscribed to only while somebody listens', () async {
      final bench = Bench();
      final selection = SoloSelection<Profile, bool>(
        bench,
        (state) => state.canSave,
      );
      expect(selection.value, isFalse);
      expect(bench.added, 0);

      void first() {}
      void second() {}
      selection
        ..addListener(first)
        ..addListener(second);
      expect((bench.added, bench.removed), (1, 0));
      selection.removeListener(first);
      expect(bench.removed, 0);
      selection.removeListener(second);
      expect(bench.removed, 1);

      // Left alone, it still answers from the state as it is.
      bench.set(Loaded('Ada'));
      expect(selection.value, isTrue);
      await bench.close();
      _says(
        'The source is subscribed to only while the selection has '
        'listeners, and there is nothing to dispose of.',
      );
    });

    test(
      'from builds the same selection of a controller without the mixin',
      () async {
        final plain = Plain();
        final bench = Bench();
        final fromPlain = SoloSelection.from(plain, (state) => state.canSave);
        final ofBench = SoloSelection<Profile, bool>(
          bench,
          (state) => state.canSave,
        );
        final heard = <String>[];
        void onPlain() => heard.add('from ${fromPlain.value}');
        void onBench() => heard.add('constructor ${ofBench.value}');
        fromPlain.addListener(onPlain);
        ofBench.addListener(onBench);

        for (final state in [Loading(), Loaded('Ada'), Loaded('Bob')]) {
          plain.set(state);
          bench.set(state);
        }

        expect(heard, ['from true', 'constructor true']);
        fromPlain.removeListener(onPlain);
        ofBench.removeListener(onBench);
        await plain.close();
        await bench.close();
        expect(
          File('lib/src/solo_selection.dart').readAsStringSync(),
          contains('SoloSelection(\n    ValueListenable<S> source,'),
        );
        _says(
          'The constructor takes a `ValueListenable`: here, the controller '
          'with `SoloListenable`. For a controller without the mixin, '
          '`SoloSelection.from(controller, selector)` builds the same '
          'selection.',
        );
      },
    );
  });

  group('The controller as a ValueListenable', () {
    test(
      'the block that cuts its body short is the controller of Usage',
      () async {
        const mixed = 'test/support/readme_listenable.dart';
        expect(_controllerBody(mixed), _controllerBody(_support.first));
        expect(
          File(mixed).readAsStringSync(),
          contains(_cutShort.split('\n').first),
        );

        final without = ProfileController(ProfileApi());
        final withMixin = listenable.ProfileController(ProfileApi());
        expect(without, isNot(isA<ValueListenable<Profile>>()));
        expect(withMixin, isA<ValueListenable<Profile>>());
        await without.close();
        await withMixin.close();
        _says(
          'they take a `ValueListenable`. Mix `SoloListenable` into the '
          'controller, and it is one:',
        );
      },
    );

    testWidgets('ValueListenableBuilder takes the controller as it is', (
      tester,
    ) async {
      final controller = listenable.ProfileController(ProfileApi());
      await tester.pumpWidget(_app(listenableBuilder(controller)));
      expect(_texts(tester), ['no profile']);

      controller.load().ignoreFailure();
      await tester.pump();
      await tester.pump();
      expect(_texts(tester), ['loading']);
      expect(identical(controller.value, controller.currentState), isTrue);
      await tester.pump(const Duration(milliseconds: 10));
      expect(_texts(tester), ['Ada Lovelace']);
      expect(controller.value, isA<Loaded>());

      await controller.close();
      _says(
        'The state is its `value`, and `ValueListenableBuilder` takes the '
        'controller as it is:',
      );
    });

    testWidgets('the widget over two profiles rebuilds when either changes', (
      tester,
    ) async {
      // Each order loads the other profile last, so the widget has to hear
      // each of the two to end up 'both loaded'.
      for (final leftFirst in [true, false]) {
        final left = listenable.ProfileController(ProfileApi());
        final right = listenable.ProfileController(ProfileApi());
        await tester.pumpWidget(_app(mergedBuilder(left, right)));
        expect(_texts(tester), ['waiting']);

        final (first, second) = leftFirst ? (left, right) : (right, left);
        first.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));
        expect(_texts(tester), ['waiting']);
        second.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));
        expect(_texts(tester), [
          'both loaded',
        ], reason: 'leftFirst: $leftFirst');

        await left.close();
        await right.close();
        await tester.pumpWidget(const SizedBox());
      }
      _says(
        'A widget over two profiles rebuilds when either of them '
        'changes:',
      );
    });

    testWidgets('ListenableBuilder, AnimatedBuilder and a merge take it too', (
      tester,
    ) async {
      final controller = listenable.ProfileController(ProfileApi());
      final scroll = ScrollController();
      var merged = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) =>
                    Text('listenable ${show(controller.value)}'),
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) =>
                    Text('animated ${show(controller.value)}'),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([controller, scroll]),
                builder: (context, _) {
                  merged++;
                  return Text('merged ${show(controller.value)}');
                },
              ),
            ],
          ),
        ),
      );
      expect(_texts(tester), [
        'listenable Empty',
        'animated Empty',
        'merged Empty',
      ]);

      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(_texts(tester), [
        'listenable Loaded(Ada Lovelace)',
        'animated Loaded(Ada Lovelace)',
        'merged Loaded(Ada Lovelace)',
      ]);

      // The other listenable of the merge wakes its builder as well.
      final before = merged;
      scroll.notifyListeners();
      await tester.pump();
      expect(merged, before + 1);

      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      await controller.close();
      _says(
        '`ListenableBuilder` and `AnimatedBuilder` take it the same way, '
        'and `Listenable.merge` joins it with other listenables.',
      );
    });

    testWidgets('SoloBuilder takes a controller with the mixin or without', (
      tester,
    ) async {
      Widget over(Solo<Profile> controller) => _app(
        SoloBuilder<Profile>(
          solo: controller,
          builder: (context, state, _) => Text(show(state)),
        ),
      );

      final withMixin = listenable.ProfileController(ProfileApi());
      await tester.pumpWidget(over(withMixin));
      expect(_texts(tester), ['Empty']);
      withMixin.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(_texts(tester), ['Loaded(Ada Lovelace)']);

      final plain = Plain();
      await tester.pumpWidget(over(plain));
      expect(_texts(tester), ['Empty']);
      plain.set(Loading());
      await tester.pump();
      expect(_texts(tester), ['Loading']);
      expect(plain, isNot(isA<Listenable>()));

      final streamed = StreamOnly();
      await tester.pumpWidget(over(streamed));
      streamed.set(Loaded('Bob'));
      await tester.pump();
      expect(_texts(tester), ['Loaded(Bob)']);
      expect(streamed, isNot(isA<Listenable>()));

      await withMixin.close();
      await plain.close();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(streamed.close);
      _says(
        '`SoloBuilder` goes on taking it, as it takes any controller: '
        'with the mixin, without it, or `with SoloStream`.',
      );
    });

    testWidgets('it moves to a controller that == calls the old one', (
      tester,
    ) async {
      final first = Same(Loaded('first'));
      final second = Same(Loaded('second'));
      // Equal by `==`, and two objects all the same.
      expect(first == second, isTrue);
      expect(identical(first, second), isFalse);
      var soloBuilds = 0;
      var listenableBuilds = 0;
      Widget both(Same controller) => _app(
        Column(
          children: [
            SoloBuilder<Profile>(
              solo: controller,
              builder: (context, state, _) {
                soloBuilds++;
                return Text('solo ${show(state)}');
              },
            ),
            ValueListenableBuilder<Profile>(
              valueListenable: controller,
              builder: (context, state, _) {
                listenableBuilds++;
                return Text('vlb ${show(state)}');
              },
            ),
          ],
        ),
      );

      await tester.pumpWidget(both(first));
      expect(_texts(tester), ['solo Loaded(first)', 'vlb Loaded(first)']);
      await tester.pumpWidget(both(second));
      expect(_texts(tester), ['solo Loaded(second)', 'vlb Loaded(first)']);

      // What each of them listens to from here on: a change of the new
      // controller wakes the first builder alone, and a change of the old
      // one the second.
      soloBuilds = 0;
      listenableBuilds = 0;
      second.set(Loaded('second, later'));
      await tester.pump();
      expect((soloBuilds, listenableBuilds), (1, 0));
      expect(_texts(tester).first, 'solo Loaded(second, later)');
      first.set(Loaded('first, later'));
      await tester.pump();
      expect((soloBuilds, listenableBuilds), (1, 1));

      await first.close();
      await second.close();
      _says(
        'One thing sets it apart from `ValueListenableBuilder`: it '
        'compares controllers by identity.',
      );
      _says(
        'Given a new controller that equals the old one by `==` but not '
        'by `identical`, `SoloBuilder` moves to it, and '
        '`ValueListenableBuilder` goes on listening to the old one.',
      );
    });
  });

  group('Listening without keeping the callback', () {
    testWidgets('the first attempt goes on being called after dispose()', (
      tester,
    ) async {
      final controller = await _loadedListenable(tester);
      final heard = <String>[];
      await tester.pumpWidget(
        Listening(controller: controller, heard: heard, firstAttempt: true),
      );
      await tester.pumpWidget(const SizedBox());

      controller.save().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      heard.clear();
      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, [
        'state Loading',
        'state Loaded(Ada Lovelace)',
      ], reason: 'the closure handed to removeListener was another object');

      // Closing the controller is what lets it go.
      await controller.close();
      _says(
        '`removeListener` has to be given the very callback '
        '`addListener` took; given anything else it removes nothing and '
        'says nothing.',
      );
      _says(
        'The first closure stays registered and goes on being called, '
        'over a `State` that is gone, until the controller is closed.',
      );
    });

    testWidgets('a method named twice is the callback dispose() removes', (
      tester,
    ) async {
      final controller = listenable.ProfileController(ProfileApi());
      final heard = <String>[];
      await tester.pumpWidget(
        Listening(controller: controller, heard: heard, withMethod: true),
      );

      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, ['state Loading', 'state Loaded(Ada Lovelace)']);

      await tester.pumpWidget(const SizedBox());
      heard.clear();
      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, isEmpty);

      // What sets the two spellings apart.
      final named = controller.load;
      final namedAgain = controller.load;
      VoidCallback written() => () {};
      expect(named == namedAgain, isTrue);
      expect(written() == written(), isFalse);

      await controller.close();
      _says(
        'A method can be named in both places. `removeListener` compares '
        'with `==`: a method named twice is equal to itself, and a closure '
        'written twice is not.',
      );
    });

    testWidgets('a group of subscriptions goes with the State', (tester) async {
      final controller = listenable.ProfileController(ProfileApi());
      final heard = <String>[];
      await tester.pumpWidget(Listening(controller: controller, heard: heard));

      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, [
        'state Loading',
        'state Loaded(Ada Lovelace)',
        'canSave true',
      ]);

      await tester.pumpWidget(const SizedBox());
      heard.clear();
      controller.load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, isEmpty);

      await controller.close();
      _says(
        '`listen` keeps the callback instead and hands back a '
        '`SoloSubscription`; `SoloSubscriptions` cancels a group of them '
        'at once',
      );
    });

    test(
      'listen takes a selection and a listenable of the framework',
      () async {
        final bench = Bench();
        final heard = <String>[];
        final canSave = SoloSelection<Profile, bool>(
          bench,
          (state) => state.canSave,
        );
        final scroll = ScrollController();
        final group = SoloSubscriptions();
        bench.listen(() => heard.add('controller')).addTo(group);
        canSave.listen(() => heard.add('selection')).addTo(group);
        scroll.listen(() => heard.add('scroll')).addTo(group);

        bench.set(Loaded('Ada'));
        scroll.notifyListeners();
        expect(heard, ['controller', 'selection', 'scroll']);

        group.cancel();
        bench.set(Empty());
        scroll.notifyListeners();
        expect(heard, hasLength(3));

        // On a `Listenable`, which a plain controller is not.
        expect(
          File('lib/src/subscription.dart').readAsStringSync(),
          contains('extension SoloListen on Listenable {'),
        );
        expect(Plain(), isNot(isA<Listenable>()));
        scroll.dispose();
        await bench.close();
        _says(
          '`listen` works on any `Listenable`: a controller with '
          '`SoloListenable`, a selection, a `ScrollController` of the '
          "framework's own.",
        );
      },
    );

    test(
      'a second cancel does nothing, a cancelled group cancels at once',
      () async {
        final bench = Bench();
        final heard = <String>[];
        final subscription = bench.listen(() => heard.add('first'))
          ..cancel()
          ..cancel();
        expect(subscription.isCancelled, isTrue);
        expect((bench.added, bench.removed), (1, 1));

        final group = SoloSubscriptions()
          ..cancel()
          ..cancel();
        final late = bench.listen(() => heard.add('late'))..addTo(group);
        expect(late.isCancelled, isTrue);
        expect(group.length, 0);

        bench.set(Loading());
        expect(heard, isEmpty);
        await bench.close();
        _says('Cancelling twice does nothing the second time.');
        _says(
          'A group that has been cancelled cancels what it is handed '
          'rather than keeping it.',
        );
      },
    );

    test('a member that will not let go costs the others nothing', () async {
      final bench = Bench();
      final sticky = Sticky();
      final heard = <String>[];
      final reported = <Object>[];
      final group = SoloSubscriptions();
      bench.listen(() => heard.add('first')).addTo(group);
      sticky.listen(() {}).addTo(group);
      sticky.listen(() {}).addTo(group);
      bench.listen(() => heard.add('last')).addTo(group);

      final onError = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      try {
        group.cancel();
      } finally {
        FlutterError.onError = onError;
      }

      bench.set(Loading());
      expect(heard, isEmpty);
      expect(reported, [isA<StateError>(), isA<StateError>()]);
      await bench.close();
      _says(
        'If one member refuses to let go, the others are cancelled all '
        'the same, and every failure goes to `FlutterError.reportError`.',
      );
      _says('Cancelling a group never throws');
    });

    testWidgets(
      'a throw out of dispose() costs the elements behind it theirs',
      (tester) async {
        final log = <String>[];
        await tester.pumpWidget(
          Column(
            children: [
              Disposing(log, 'a'),
              Disposing(log, 'b', throws: true),
              Disposing(log, 'c'),
            ],
          ),
        );
        await tester.pumpWidget(const SizedBox());

        expect(tester.takeException(), isA<StateError>());
        expect(log, ['a', 'b'], reason: 'the dispose() of c was never called');
        _says(
          'an exception out of there costs the elements behind it in that '
          'frame their own `dispose()`, listeners and all',
        );
      },
    );

    testWidgets(
      'handed another controller, initState goes on hearing the old',
      (tester) async {
        final first = listenable.ProfileController(ProfileApi());
        final second = listenable.ProfileController(ProfileApi());
        final heard = <String>[];
        await tester.pumpWidget(Listening(controller: first, heard: heard));
        await tester.pumpWidget(Listening(controller: second, heard: heard));

        second.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));
        expect(heard, isEmpty, reason: 'nobody listens to the new controller');
        first.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));
        expect(heard, isNotEmpty, reason: 'the old one is still listened to');

        await tester.pumpWidget(const SizedBox());
        await first.close();
        await second.close();
        _says(
          'What `initState` subscribes to stays subscribed when the widget '
          'is handed another controller.',
        );
      },
    );

    testWidgets('the subscriptions are taken again into a new group', (
      tester,
    ) async {
      Future<List<String>> followed({required bool newGroup}) async {
        final first = listenable.ProfileController(ProfileApi());
        final second = listenable.ProfileController(ProfileApi());
        final heard = <String>[];
        Widget over(listenable.ProfileController controller) =>
            Following(controller: controller, heard: heard, newGroup: newGroup);
        await tester.pumpWidget(over(first));
        await tester.pumpWidget(over(second));

        first.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));
        expect(heard, isEmpty, reason: 'the old controller was let go');
        second.load().ignoreFailure();
        await tester.pump(const Duration(milliseconds: 10));

        await tester.pumpWidget(const SizedBox());
        await first.close();
        await second.close();
        return heard;
      }

      expect(await followed(newGroup: true), [
        'Loading',
        'Loaded(Ada Lovelace)',
      ]);
      expect(await followed(newGroup: false), isEmpty);
      _says(
        'cancels the group in `didUpdateWidget` and takes its '
        'subscriptions again, into a new group: the cancelled one would '
        'cancel them on the spot',
      );
    });
  });

  group('Methods from a second import', () {
    test('select and listen arrive as methods', () async {
      final controller = listenable.ProfileController(ProfileApi());
      heardBySecondImport.clear();
      final (canSave, subscription) = secondImport(controller);

      await controller.load().done;
      expect(canSave.value, isTrue);
      expect(heardBySecondImport, [true]);

      subscription.cancel();
      await controller.close();
      _says('`select` and `listen` arrive with an import of their own');
    });

    test('they are extensions on the listenables of the framework', () {
      expect(
        File('lib/src/solo_selection.dart').readAsStringSync(),
        contains('extension SoloSelect<S> on ValueListenable<S> {'),
      );
      expect(
        File('lib/src/subscription.dart').readAsStringSync(),
        contains('extension SoloListen on Listenable {'),
      );
      _says(
        "They are extensions on the framework's own `ValueListenable` "
        "and `Listenable`, where another package's `select` and `listen` "
        'sit too.',
      );
    });

    test('without the methods the same things are still done', () async {
      final bench = Bench();
      final heard = <bool>[];
      final direct = SoloSelection<Profile, bool>(
        bench,
        (state) => state.canSave,
      );
      final method = bench.select((state) => state.canSave);
      void listener() => heard.add(direct.value);
      direct.addListener(listener);
      final subscription = method.listen(() => heard.add(method.value));

      bench.set(Loaded('Ada'));
      expect(heard, [true, true]);

      direct.removeListener(listener);
      subscription.cancel();
      await bench.close();
      _says(
        '`SoloSelection(controller, (state) => state.canSave)` is the '
        'same selection;',
      );
      _says('`SoloSelector` needs no method at all;');
      _says(
        '`addListener` with a callback you keep yourself is what '
        '`listen` does for you.',
      );
    });

    test('a select of the controller itself wins over the extension', () async {
      final picker = Picker()..select(7);

      expect(picker.picked, [7]);
      await picker.close();
      _says(
        'A controller of your own with a `select` method keeps it, '
        'because an extension always steps aside for a member.',
      );
    });
  });

  group("The controller's life", () {
    testWidgets('the screen owns its controller and closes it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      final controller = controllerOf(
        tester.state<State<ProfileScreen>>(find.byType(ProfileScreen)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(controller.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(controller.isClosed, isTrue);
      expect(tester.takeException(), isNull);
      _says('Nothing closes a controller for you.');
    });

    testWidgets('close() is safe on either side of super.dispose()', (
      tester,
    ) async {
      // The page's side, over a load that is still running.
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      final first = controllerOf(
        tester.state<State<ProfileScreen>>(find.byType(ProfileScreen)),
      );
      await tester.pump(const Duration(milliseconds: 3));
      await tester.pumpWidget(const SizedBox());
      expect(first.isFinished, isTrue);
      expect(first.currentState, isA<Empty>());

      // The other side.
      final second = ProfileController(ProfileApi());
      await tester.pumpWidget(
        MaterialApp(home: LateCloseScreen(controller: second)),
      );
      await tester.pump(const Duration(milliseconds: 3));
      await tester.pumpWidget(const SizedBox());
      expect(second.isFinished, isTrue);
      expect(second.currentState, isA<Empty>());

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 10));
      _says('`close()` is safe on either side of `super.dispose()`.');
    });

    testWidgets('close() cancels what is queued and what is running', (
      tester,
    ) async {
      final controller = await _loaded(tester);
      final running = controller.save();
      final queued = controller.load();
      await tester.pump(const Duration(milliseconds: 3));

      var closed = false;
      unawaited(controller.close().then((_) => closed = true));
      await tester.pump();
      expect('${queued.outcome}', 'Cancelled(closed)');
      // The save is behind `ctx.join`: its call is waited out, and the
      // future of close() waits with it.
      expect(running.outcome, isNull);
      expect(closed, isFalse);

      await tester.pump(const Duration(milliseconds: 10));
      expect('${running.outcome}', 'Cancelled(closed)');
      expect(controller.api.saved, ['Ada Lovelace']);
      expect(closed, isTrue);
      expect('${controller.load().outcome}', 'Cancelled(closed)');
      _says('`close()` cancels whatever is queued or running');
      _says(
        'it returns a `Future` that completes when the job has actually '
        'stopped',
      );
    });

    testWidgets('a running body stops at its next context call', (
      tester,
    ) async {
      final bench = Bench();
      final log = <String>[];
      bench.go<Profile, void>((ctx) async {
        log.add('first step');
        // A wait the context knows nothing about.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('second step');
        await ctx.pause(const Duration(milliseconds: 10));
        log.add('third step');
      }).ignoreFailure();
      await tester.pump(const Duration(milliseconds: 3));

      var closed = false;
      unawaited(bench.close().then((_) => closed = true));
      await tester.pump();
      expect(closed, isFalse);
      await tester.pump(const Duration(milliseconds: 10));

      expect(log, ['first step', 'second step']);
      expect(closed, isTrue);
      _says('A running body stops at its next context call');
    });

    testWidgets('a job made with cancellable: false runs to its end', (
      tester,
    ) async {
      final bench = Bench();
      final heard = <String>[];
      bench.addListener(() => heard.add(show(bench.value)));
      final job = bench.go<Profile, void>(cancellable: false, (ctx) async {
        await ctx.pause(const Duration(milliseconds: 10));
        ctx.emit(Loaded('written while closing'));
      });
      await tester.pump(const Duration(milliseconds: 3));

      var closed = false;
      unawaited(bench.close().then((_) => closed = true));
      await tester.pump();
      expect(job.outcome, isNull);
      expect(closed, isFalse);
      await tester.pump(const Duration(milliseconds: 10));

      expect('${job.outcome}', 'Done(null)');
      expect(heard, ['Loaded(written while closing)']);
      expect(closed, isTrue);
      _says(
        'a job made with `cancellable: false` turns the cancellation down '
        'and runs to its end',
      );
      _says(
        'from `ifCancelled` or from the body of a job that turned the '
        'cancellation down',
      );
    });

    testWidgets('the screen lets go of the controller without waiting', (
      tester,
    ) async {
      final bench = Bench();
      await tester.pumpWidget(
        _app(
          SoloBuilder<Profile>(
            solo: bench,
            builder: (context, state, _) => Text(show(state)),
          ),
        ),
      );
      final job = bench.go<Profile, void>(
        cancellable: false,
        (ctx) => ctx.pause(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 3));
      final closing = bench.close();
      await tester.pumpWidget(const SizedBox());

      expect(job.outcome, isNull, reason: 'the close is not over yet');
      expect([bench.added, bench.removed], [1, 1]);
      await tester.pump(const Duration(milliseconds: 10));
      await closing;
      _says(
        'The screen does not wait for that: `SoloBuilder` lets go of the '
        'controller in its own `dispose`.',
      );
    });

    testWidgets('it drops every listener and stops notifying for good', (
      tester,
    ) async {
      // What the closing itself changes is still heard: the handler of the
      // load it cancels publishes `Empty`.
      final controller = ProfileController(ProfileApi());
      final heard = <String>[];
      controller
        ..addListener(() => heard.add(show(controller.currentState)))
        ..load().ignoreFailure();
      await tester.pump(const Duration(milliseconds: 3));
      await controller.close();
      expect(heard, ['Loading', 'Empty']);
      _says('Until then the listeners still hear what the closing jobs write');
      await tester.pump(const Duration(milliseconds: 10));

      // Once it has finished, nothing is: a listener added then is not
      // kept, and the state is final.
      final bench = Bench();
      await bench.close();
      expect(bench.isFinished, isTrue);
      final late = <String>[];
      bench.addListener(() => late.add(show(bench.value)));
      expect(() => bench.set(Loaded('late')), throwsStateError);
      expect(late, isEmpty);
      expect(bench.value, isA<Empty>());
      _says('drops every listener and stops notifying for good');
    });

    test('with the mixin a controller is still no ChangeNotifier', () async {
      final controller = listenable.ProfileController(ProfileApi());

      expect(controller, isA<Listenable>());
      expect(controller, isNot(isA<ChangeNotifier>()));
      await controller.close();
      _says(
        'Even with `SoloListenable` a controller is not a '
        '`ChangeNotifier`: the method is `close()`, not `dispose()`',
      );
    });
  });

  group('Outcomes', () {
    Future<List<String>> tapped(
      WidgetTester tester,
      ProfileApi api, {
      bool closeMeanwhile = false,
      bool leaveMeanwhile = false,
    }) async {
      final controller = ProfileController(api);
      final toasts = <String>[];
      await tester.pumpWidget(
        _app(LoadButton(controller: controller, toasts: toasts)),
      );
      await tester.tap(find.text('Load'));
      await tester.pump();
      if (closeMeanwhile) {
        unawaited(controller.close());
      }
      if (leaveMeanwhile) {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      return toasts;
    }

    testWidgets('the outcome of the tap is what the toast says', (
      tester,
    ) async {
      expect(await tapped(tester, ProfileApi()), ['hello Ada Lovelace']);
      expect(
        await tapped(tester, ProfileApi(error: StateError('no network'))),
        ['Bad state: no network'],
      );
      expect(tester.takeException(), isNull);
      expect(await tapped(tester, ProfileApi(), closeMeanwhile: true), isEmpty);
      _says(
        'A method hands back its job, so the screen can wait for the end '
        'of the work it started',
      );
    });

    testWidgets('mounted holds the toast back once the screen is gone', (
      tester,
    ) async {
      expect(await tapped(tester, ProfileApi(), leaveMeanwhile: true), isEmpty);
      _says(
        '`mounted` after an `await` is the usual Flutter rule, and it '
        'applies here too.',
      );
    });

    test('done never throws, value rethrows', () async {
      final failing = ProfileController(
        ProfileApi(error: StateError('no network')),
      );
      final failed = failing.load();
      expect(await failed.done, isA<Failed>());
      await expectLater(failed.value, throwsStateError);

      final cancelling = ProfileController(ProfileApi());
      final cancelled = cancelling.load();
      unawaited(cancelled.cancel());
      expect(await cancelled.done, isA<Cancelled>());
      await expectLater(cancelled.value, throwsA(isA<Cancelled>()));

      final loading = ProfileController(ProfileApi());
      final done = loading.load();
      expect(await done.done, isA<Done<String>>());
      expect(await done.value, 'Ada Lovelace');

      await failing.close();
      await cancelling.close();
      await loading.close();
      _says(
        '`done` never throws. `value` gives the value, rethrows the '
        'failure of a job that failed and throws the `Cancelled` of one '
        'that was cancelled.',
      );
    });

    testWidgets('an unobserved Failed reaches the zone that created the job', (
      tester,
    ) async {
      Future<List<Object>> inZone(
        Object error,
        void Function(ProfileController controller) use,
      ) async {
        final errors = <Object>[];
        // The controller belongs to the zone of the test; the job is
        // created in a zone of its own.
        final controller = ProfileController(ProfileApi(error: error));
        runZonedGuarded(
          () => use(controller),
          (error, stackTrace) => errors.add(error),
        );
        await tester.pump(const Duration(milliseconds: 10));
        await controller.close();
        return errors;
      }

      const expected = ApiException('no network');
      final bug = StateError('a bug');
      expect(
        await inZone(expected, (controller) => controller.load()),
        isEmpty,
      );
      expect(await inZone(bug, (controller) => controller.load()), [
        isA<StateError>(),
      ]);
      expect(
        await inZone(bug, (controller) => controller.load().ignoreFailure()),
        isEmpty,
      );
      expect(
        await inZone(bug, (controller) => unawaited(controller.load().done)),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      _says(
        'An unobserved `Failed` reaches the zone that created the job, '
        'unless the job names its error in `isExpectedError`.',
      );
      _says(
        'A job that names its expected errors, as `load` names '
        '`ApiException`, needs nothing more: the call is '
        '`controller.load()`, and a bug still reaches the zone.',
      );
      _says(
        'A call that needs no outcome at all ends with `ignoreFailure()`: '
        "it says the outcome is nobody's business, even when a bug ended "
        'the job.',
      );
    });

    testWidgets('unattended work that fails takes the same road', (
      tester,
    ) async {
      Future<List<Object>> inZone(Background controller) async {
        final errors = <Object>[];
        runZonedGuarded(
          () => controller.ping().ignoreFailure(),
          (error, stackTrace) => errors.add(error),
        );
        await tester.pump(const Duration(milliseconds: 5));
        await controller.close();
        return errors;
      }

      expect(await inZone(Background()), [isA<StateError>()]);

      final answering = Background(answers: true);
      expect(await inZone(answering), isEmpty);
      expect(answering.answered, [isA<StateError>()]);

      final handled = <Object>[];
      addTearDown(() => Solo.unansweredHandler = null);
      Solo.unansweredHandler = (solo, job, error, stackTrace) =>
          handled.add(error);
      expect(await inZone(Background()), isEmpty);
      expect(handled, [isA<StateError>()]);
      handled.clear();
      final errors = <Object>[];
      final profile = ProfileController(
        ProfileApi(error: StateError('no network')),
      );
      runZonedGuarded(profile.load, (error, stackTrace) => errors.add(error));
      await tester.pump(const Duration(milliseconds: 10));
      await profile.close();
      expect(errors, isEmpty);
      expect(handled, [isA<StateError>()], reason: 'an unobserved Failed');
      Solo.unansweredHandler = null;

      _says(
        'The same road carries the errors no outcome holds, such as the '
        'failure of work a body handed to `ctx.unattended`. A controller '
        'that overrides `onUnanswered`, or a `Solo.unansweredHandler`, '
        'answers for them instead, and for an unobserved `Failed` as '
        'well.',
      );
    });

    testWidgets('an observer sees such a failure and does not take it', (
      tester,
    ) async {
      final watching = Watching();
      addTearDown(() => Solo.observer = null);
      Solo.observer = watching;
      final errors = <Object>[];
      final controller = Background();
      runZonedGuarded(
        () => controller.ping().ignoreFailure(),
        (error, stackTrace) => errors.add(error),
      );
      await tester.pump(const Duration(milliseconds: 5));

      expect(watching.seen, [isA<StateError>()]);
      expect(errors, [isA<StateError>()]);
      await controller.close();
      _says(
        'A `SoloObserver` sees such a failure and does not take it: '
        'watching is not answering.',
      );
    });

    test(
      'an error zone of your own comes before PlatformDispatcher.onError',
      () async {
        final dispatcher = PlatformDispatcher.instance;
        final onError = dispatcher.onError;
        addTearDown(() => dispatcher.onError = onError);
        final reached = <Object>[];
        dispatcher.onError = (error, stackTrace) {
          reached.add(error);
          return true;
        };
        ProfileController failing() =>
            ProfileController(ProfileApi(error: StateError('no network')));

        // With nothing between the job and the root zone.
        final bare = Zone.root.run(failing);
        Zone.root.run(bare.load);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(reached, [isA<StateError>()]);

        // With an error zone of one's own in between.
        reached.clear();
        final own = <Object>[];
        final guarded = Zone.root.run(failing);
        Zone.root.run(
          () => runZonedGuarded(
            guarded.load,
            (error, stackTrace) => own.add(error),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(own, [isA<StateError>()]);
        expect(reached, isEmpty);

        await bare.close();
        await guarded.close();
        _says('An error zone of your own around `runApp` sees it first.');
        _says(
          'Past that it reaches `PlatformDispatcher.instance.onError`, if '
          'you set one.',
        );
      },
    );
  });

  group('Notes', () {
    test('listeners run synchronously, in subscription order', () async {
      final bench = Bench();
      final log = <String>[];
      bench
        ..addListener(() => log.add('first hears ${show(bench.value)}'))
        ..addListener(() => log.add('second hears ${show(bench.value)}'));

      log.add('before the write');
      bench.set(Loading());
      log.add('after the write');

      expect(log, [
        'before the write',
        'first hears Loading',
        'second hears Loading',
        'after the write',
      ]);
      expect(identical(bench.value, bench.currentState), isTrue);
      expect(bench, isNot(isA<SoloStream<Profile>>()));
      await bench.close();
      _says(
        'Synchronously, in subscription order, on every state change. '
        'With `SoloListenable`, `value` and `currentState` are the same '
        'object.',
      );
    });

    test('a failure of a listener takes the route of the mixin', () async {
      /// Where the failures went, outside the zone the writes were made in:
      /// of a listener of [controller], of a selector over it, and of a
      /// listener of a selection over it.
      Future<(List<String>, List<String>)> route(
        Solo<Profile> controller,
        void Function(Profile state) write,
      ) async {
        final flutter = <String>[];
        final zone = <String>[];
        final reporter = FlutterError.onError;
        FlutterError.onError = (details) => flutter.add('${details.exception}');
        final loading = SoloSelection.from(
          controller,
          (state) => state is Loading,
        );
        final throwing = SoloSelection.from(
          controller,
          (state) => state is Loaded ? throw StateError('selector') : false,
        );
        void picked() {}
        void refuse() => throw StateError('selection listener');
        try {
          runZonedGuarded(() {
            controller.addListener(() => throw StateError('listener'));
            loading.addListener(refuse);
            write(Loading());
            throwing.addListener(picked);
            write(Loaded('Ada'));
          }, (error, _) => zone.add('$error'));
        } finally {
          FlutterError.onError = reporter;
          loading.removeListener(refuse);
          throwing.removeListener(picked);
        }
        await controller.close();
        return (flutter, zone);
      }

      const ofController = [
        'Bad state: listener',
        'Bad state: listener',
        'Bad state: selector',
      ];
      const ofSelection = [
        'Bad state: selection listener',
        'Bad state: selection listener',
      ];
      final bench = Bench();
      final (benchFlutter, benchZone) = await route(bench, bench.set);
      expect(benchFlutter, unorderedEquals([...ofController, ...ofSelection]));
      expect(benchZone, isEmpty);
      final plain = Plain();
      final (plainFlutter, plainZone) = await route(plain, plain.set);
      expect(plainFlutter, ofSelection);
      expect(plainZone, ofController);
      _says(
        '| A listener of a controller with `SoloListenable` | To '
        '`FlutterError.reportError`,',
      );
      _says('| A listener of a controller without it | To the zone, as ');
      _says(
        'but `FlutterError.onError` never hears of a failure of its '
        'listeners. |',
      );
      _says(
        '| A listener of a selection | Through `FlutterError`, whether the '
        'controller has `SoloListenable` or not: a selection reports its '
        'own listeners. |',
      );
      _says(
        "| The selector of a selection | The controller's route, one of the "
        'two rows above: the selector runs inside a listener of the '
        'controller. |',
      );
    });

    testWidgets('the builders listen to the controller itself', (tester) async {
      final plain = Plain();
      final bench = Bench();
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SoloBuilder<Profile>(
                solo: plain,
                builder: (context, state, _) => Text(show(state)),
              ),
              ValueListenableBuilder<Profile>(
                valueListenable: bench,
                builder: (context, state, _) => Text(show(state)),
              ),
            ],
          ),
        ),
      );
      expect((plain.added, bench.added), (1, 1));
      expect(plain, isNot(isA<SoloStream<Profile>>()));
      expect(bench, isNot(isA<SoloStream<Profile>>()));

      await tester.pumpWidget(const SizedBox());
      expect((plain.removed, bench.removed), (1, 1));
      await plain.close();
      await bench.close();
      _says(
        'There is no `stream` unless `SoloStream` is mixed in: the '
        'builders listen to the controller itself.',
      );
    });

    testWidgets('equal states are not filtered, and a frame swallows several', (
      tester,
    ) async {
      final bench = Bench();
      var heard = 0;
      final picked = <bool>[];
      final canSave = bench.select((state) => state.canSave);
      final group = SoloSubscriptions();
      bench.listen(() => heard++).addTo(group);
      canSave.listen(() => picked.add(canSave.value)).addTo(group);
      final built = <String>[];
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<Profile>(
            valueListenable: bench,
            builder: (context, state, _) {
              built.add(show(state));
              return const SizedBox();
            },
          ),
        ),
      );

      final same = Loaded('Ada');
      bench.go<Profile, void>((ctx) async {
        ctx
          ..emit(same)
          ..emit(same)
          ..emit(Loaded('Ada'))
          ..emit(Loaded('Bob'));
      }).ignoreFailure();
      await tester.pump();
      await tester.pump();

      expect(heard, 4);
      expect(picked, [true]);
      expect(built, ['Empty', 'Loaded(Bob)']);
      group.cancel();
      await bench.close();
      _says('`emit` of a state equal to the current one still notifies');
      _says(
        'A frame may swallow several of them, a listener will not. A '
        'selection filters its own value',
      );
    });

    testWidgets('one widget over two controllers takes a merge', (
      tester,
    ) async {
      final a = Bench();
      final b = Bench();
      final built = <String>[];
      await tester.pumpWidget(
        _app(
          ListenableBuilder(
            listenable: Listenable.merge([a, b]),
            builder: (context, _) {
              built.add('${show(a.value)} ${show(b.value)}');
              return const SizedBox();
            },
          ),
        ),
      );
      a.set(Loading());
      await tester.pump();
      b.set(Loaded('Bob'));
      await tester.pump();

      expect(built, ['Empty Empty', 'Loading Empty', 'Loading Loaded(Bob)']);
      await a.close();
      await b.close();
      expect(Plain(), isNot(isA<Listenable>()));
      _says(
        '`Listenable.merge([a, b])` in a `ListenableBuilder` covers the '
        'case where one widget depends on two; it takes controllers with '
        '`SoloListenable`, as [The controller as a '
        '`ValueListenable`](#the-controller-as-a-valuelistenable) shows.',
      );
    });

    test('the mixin gives value no setter', () {
      final mixin = File('lib/src/solo_listenable.dart').readAsStringSync();

      expect(mixin, contains('S get value => currentState;'));
      expect(mixin, isNot(contains('set value')));
      _says('There is no setter.');
    });

    testWidgets('a timer of a job fires when the test moves the clock', (
      tester,
    ) async {
      final controller = ProfileController(ProfileApi());
      final job = controller.load()..ignoreFailure();
      await tester.pump();
      await tester.idle();
      expect(job.outcome, isNull);

      await tester.pump(const Duration(milliseconds: 10));
      expect(job.outcome, isA<Done<String>>());
      await controller.close();
      _says(
        'On the fake clock of `testWidgets`: a timer a job waits on, '
        'such as the delay of a fake API, fires only when the test moves '
        'the clock.',
      );
    });
  });

  group('solo', () {
    test('SoloStream comes with the same import', () async {
      final both = Both();
      final streamed = <String>[];
      final subscription = both.stream.map(show).listen(streamed.add);
      final heard = <String>[];
      both
        ..addListener(() => heard.add(show(both.value)))
        ..set(Loading());

      expect(heard, ['Loading']);
      expect(streamed, isEmpty, reason: 'the stream is a microtask behind');
      await Future<void>.delayed(Duration.zero);
      expect(streamed, ['Loading']);

      await subscription.cancel();
      await both.close();
      expect(arrivesWithOneImport, contains(SoloStream<Object>));
      _says(
        'the rest of the API. This package re-exports all of it, '
        '`SoloStream` included',
      );
    });
  });
}

var _picks = 0;

/// The selector of the page as a function that is held, counting its calls.
bool _counted(Profile state) {
  _picks++;
  return state.canSave;
}

/// How long the name of the profile is.
int _length(Profile state) => state is Loaded ? state.name.length : 0;

/// A `changed` of the test's own: fewer than three letters apart is no
/// change.
bool _far(int previous, int current) => (current - previous).abs() >= 3;
