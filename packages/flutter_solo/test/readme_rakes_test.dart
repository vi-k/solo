import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/page_code.dart';
import 'support/readme_install.dart';
import 'support/readme_profile.dart';
import 'support/readme_tests.dart';
import 'support/readme_variants.dart';
import 'support/readme_widgets.dart';

/// The sentinel of `README.md`.
///
/// The code of the page stands verbatim in three files of `test/support/`:
/// `readme_profile.dart` holds the model of "Usage",
/// `readme_widgets.dart` the fragments between "Why" and "Outcomes", and
/// `readme_tests.dart` the code of "Testing". The tests below run it. What
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
const _support = [
  'test/support/readme_profile.dart',
  'test/support/readme_widgets.dart',
  'test/support/readme_tests.dart',
  'test/support/readme_install.dart',
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

List<String?> _texts(WidgetTester tester) =>
    [for (final text in tester.widgetList<Text>(find.byType(Text))) text.data];

/// A controller of the page with its profile loaded.
Future<ProfileController> _loaded(WidgetTester tester) async {
  final controller = ProfileController(ProfileApi());
  controller.load().ignore();
  await tester.pump(const Duration(milliseconds: 10));
  expect(controller.value, isA<Loaded>());
  return controller;
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
      .defaultTestTimeout = const Timeout(Duration(seconds: 30));

  group('The page', () {
    test('every piece of its code stands in the support files', () {
      expect(
        codeMissingFrom(
          _doc,
          _support.first,
          alsoIn: _support.skip(1).toList(),
        ),
        isEmpty,
      );
    });

    test('its blocks are dart, but for one line of shell', () {
      expect(strayFences(_doc), ['```sh']);
      expect(
        RegExp(r'^```dart$', multiLine: true).allMatches(_page()),
        hasLength(14),
        reason: 'a new block of the page needs a place in the support files '
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
      expect(controller.value, isA<Loading>());

      await job.cancel();

      expect('${job.outcome}', 'Cancelled(manual)');
      expect(controller.value, isA<Empty>());
      // The request the job walked away from is still on its way.
      expect(api.trace, ['fetch begins']);
      await tester.pump(const Duration(milliseconds: 10));
      expect(api.trace, ['fetch begins', 'fetch ends']);
      expect(controller.value, isA<Empty>());
      await controller.close();
    });

    testWidgets('root jobs run one at a time, in queue order', (tester) async {
      final bench = Bench();
      final log = <String>[];
      Job<void> step(String name) => bench.go<Profile, void>((ctx) async {
            log.add('$name begins');
            await ctx.pause(const Duration(milliseconds: 5));
            log.add('$name ends');
          });

      step('a').ignore();
      step('b').ignore();
      step('c').ignore();
      await tester.pump(const Duration(milliseconds: 15));

      expect(
        log,
        ['a begins', 'a ends', 'b begins', 'b ends', 'c begins', 'c ends'],
      );
      await bench.close();
      _says('one root job of a controller at a time, in queue order');
    });

    testWidgets('a job is cancelled when its rules stop holding',
        (tester) async {
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
      _says('a job declares the states it works with and the condition it '
          'lives under, and it is cancelled when they stop holding');
    });

    testWidgets('the body cannot walk past a cancellation', (tester) async {
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
      _says('a cancellation the caller can ask for and the body cannot walk '
          'past by forgetting a check');
    });

    testWidgets('every job ends with one of three outcomes', (tester) async {
      final done = ProfileController(ProfileApi()).load();
      final failed = ProfileController(
        ProfileApi(error: StateError('no network')),
      ).load()
        ..ignore();
      final cancelled = ProfileController(ProfileApi()).load();
      unawaited(cancelled.cancel());
      await tester.pump(const Duration(milliseconds: 10));

      expect(done.outcome, isA<Done<String>>());
      expect(failed.outcome, isA<Failed>());
      expect(cancelled.outcome, isA<Cancelled>());
      _says('an outcome for every job — `Done`, `Failed` or `Cancelled` —');
    });
  });

  group('Install', () {
    test('one import brings the engine, the mixin and the widgets', () {
      expect(arrivesWithOneImport, hasLength(10));
      expect(
        File('lib/flutter_solo.dart').readAsStringSync(),
        contains("export 'package:solo/solo.dart';"),
      );
      _says('`Solo`, `SoloContext`, `Job`, `Outcome` and `Policy` all arrive '
          'with');
      _says('`SoloBuilder`, `SoloSelector` and `SoloSelection` come with it');
    });

    test('select, listen and the subscriptions are in the second import', () {
      final first = File('lib/flutter_solo.dart').readAsStringSync();
      final second = File('lib/listenable.dart').readAsStringSync();

      expect(first, isNot(contains('subscription.dart')));
      expect(first, contains("'src/solo_selection.dart' show SoloSelection;"));
      expect(second, contains("'src/solo_selection.dart' show SoloSelect;"));
      expect(second, contains("export 'src/subscription.dart';"));
      _says('a second import next door adds `select` and `listen` as '
          'methods, with the subscriptions `listen` hands back');
      _says('`SoloSubscription` and `SoloSubscriptions` come with the second '
          'import only');
    });
  });

  group('Usage', () {
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

    testWidgets('the handlers take a failed or cancelled load back to Empty',
        (tester) async {
      final failing = ProfileController(
        ProfileApi(error: StateError('no network')),
      );
      failing.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(failing.value, isA<Empty>());

      final cancelled = ProfileController(ProfileApi());
      final job = cancelled.load();
      await tester.pump(const Duration(milliseconds: 3));
      await job.cancel();
      expect(cancelled.value, isA<Empty>());

      await tester.pump(const Duration(milliseconds: 10));
      _says('they say what state a load that failed or was cancelled leaves '
          'behind');
    });

    testWidgets('without them the state stays on Loading', (tester) async {
      final failing = Handlerless(ProfileApi(error: StateError('no network')));
      failing.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(failing.value, isA<Loading>());

      final cancelled = Handlerless(ProfileApi());
      final job = cancelled.load();
      await tester.pump(const Duration(milliseconds: 3));
      await job.cancel();
      expect(cancelled.value, isA<Loading>());

      await tester.pump(const Duration(milliseconds: 10));
      _says('without them the screen would keep the spinner of a job that is '
          'no longer running');
    });

    testWidgets('save does not start over a state that is not Loaded',
        (tester) async {
      final api = ProfileApi();
      final controller = ProfileController(api);

      final early = controller.save();
      await tester.pump();
      expect('${early.outcome}', 'Cancelled(rules: is not Loaded)');
      expect(api.trace, isEmpty);

      // Asked for while the load is ahead of it, it starts once the state
      // is Loaded.
      controller.load().ignore();
      final queued = controller.save();
      await tester.pump(const Duration(milliseconds: 20));
      expect(queued.outcome, isA<Done<void>>());
      expect(api.saved, ['Ada Lovelace']);

      await controller.close();
      _says('`save` narrows that to `Loaded`, so it does not start in any '
          'other state — it ends `Cancelled` there — and its body reads a '
          '`Loaded` with a `name` in it');
    });

    testWidgets('abandonable gives up at once, join waits its call out',
        (tester) async {
      final api = ProfileApi();
      final controller = ProfileController(api);

      final load = controller.load();
      await tester.pump(const Duration(milliseconds: 3));
      unawaited(load.cancel());
      await tester.pump();
      expect('${load.outcome}', 'Cancelled(manual)');
      expect(api.trace, ['fetch begins']);
      await tester.pump(const Duration(milliseconds: 10));

      controller.load().ignore();
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
      _says('`ctx.abandonable` awaits like `await` except that it gives up the '
          'moment the job is cancelled, and `ctx.join` waits its call out '
          'either way — a save is not cut in half');
    });
  });

  group('Selecting one value', () {
    testWidgets('the selector rebuilds only when the pick changes',
        (tester) async {
      final controller = ProfileController(ProfileApi());
      await tester.pumpWidget(_app(saveSelector(controller)));
      expect(_save(tester), isNull);

      controller.load().ignore();
      await tester.pump();
      await tester.pump();
      expect(controller.value, isA<Loading>());
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
      _says('`SoloSelector` picks the field and rebuilds only when that field '
          'changes');
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
      _says('Picks count as changed when they are `!=`, unless `changed:` '
          'answers that question itself.');
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

    testWidgets('an inline selector makes a new selection on every build',
        (tester) async {
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
      expect((inline.added, inline.removed), (4, 3));
      final held = await rebuilt(inline: false);
      expect((held.added, held.removed), (1, 0));
      expect(_picks, 0);

      // One pick for each new selection.
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
      _says('an inline closure is a new one on every such build and makes a '
          'new selection each time: one `removeListener`, one `addListener` '
          'and one pick');
    });

    testWidgets('a new selection forgets what changed was comparing with',
        (tester) async {
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
        await tester.pumpWidget(const SizedBox());
        await plain.close();
        return [before, after];
      }

      expect(await shown(inline: false), ['0', '0']);
      expect(await shown(inline: true), ['0', '2']);
      _says('with a `changed:` of your own the value it compares against '
          'starts over');
    });

    testWidgets('the selection in a field follows a new controller',
        (tester) async {
      final loaded = await _loaded(tester);
      final empty = ProfileController(ProfileApi());

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
      _says('What the widget holds for you is a `SoloSelection`');
    });

    testWidgets('without didUpdateWidget it stays with the old one',
        (tester) async {
      final loaded = await _loaded(tester);
      final empty = ProfileController(ProfileApi());

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
      _says('without `didUpdateWidget` the button would go on taking its '
          'permission from the old controller while its tap went to the new '
          'one');
    });

    testWidgets('a selection built inside build is a new one every build',
        (tester) async {
      final bench = Bench();
      final parent = GlobalKey<ParentState>();
      final built = <int>[];
      await tester.pumpWidget(
        _app(
          Parent(
            key: parent,
            (context) => ValueListenableBuilder<int>(
              valueListenable:
                  SoloSelection<Profile, int>(bench, _length, changed: _far),
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
      _says('One built inside `build` is a new object on every build: the '
          'builder under it unsubscribes from the old one and subscribes to '
          'the new, and the value a selection holds notifications back with '
          'starts over each time.');
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
      _says('The source is subscribed to only while the selection has '
          'listeners, and there is nothing to dispose of.');
    });
  });

  group('Builders for any controller', () {
    testWidgets('the builder takes a controller that is not a listenable',
        (tester) async {
      final plain = Plain();
      await tester.pumpWidget(_app(anyBuilder(plain)));
      expect(_texts(tester), ['no profile']);
      plain.set(Loading());
      await tester.pump();
      expect(_texts(tester), ['loading']);
      plain.set(Loaded('Ada Lovelace'));
      await tester.pump();
      expect(_texts(tester), ['Ada Lovelace']);

      final streamed = StreamOnly();
      await tester.pumpWidget(_app(anyBuilder(streamed)));
      streamed.set(Loaded('Bob'));
      await tester.pump();
      expect(_texts(tester), ['Bob']);

      await plain.close();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(streamed.close);
      _says('A controller without it is not — a plain `Solo`, or one `with '
          'SoloStream` only — and for those `SoloBuilder` takes the '
          'controller itself');
    });

    testWidgets('it rebuilds on every change and leaves child alone',
        (tester) async {
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
      _says('It rebuilds on every change of the state and hands `child` '
          'through untouched.');
    });

    testWidgets('it moves to a controller that == calls the old one',
        (tester) async {
      final first = Same(Loaded('first'));
      final second = Same(Loaded('second'));
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
      _says('Handed a new controller whose `==` says it is the old one, '
          '`SoloBuilder` moves to it and `ValueListenableBuilder` goes on '
          'listening to the old one.');
    });

    test('from is the selection of such a controller without a widget',
        () async {
      final plain = Plain();
      final selection = SoloSelection.from(plain, (state) => state.canSave);
      final heard = <bool>[];
      void listener() => heard.add(selection.value);
      selection.addListener(listener);

      plain
        ..set(Loading())
        ..set(Loaded('Ada'))
        ..set(Loaded('Bob'));

      expect(heard, [true]);
      selection.removeListener(listener);
      await plain.close();
      _says('`SoloSelector` takes any controller, and '
          '`SoloSelection.from(controller, selector)` is its selection '
          'without a widget around it');
    });
  });

  group('Listening without keeping the callback', () {
    testWidgets('the first attempt goes on being called after dispose()',
        (tester) async {
      final controller = await _loaded(tester);
      final heard = <String>[];
      await tester.pumpWidget(
        Listening(controller: controller, heard: heard, firstAttempt: true),
      );
      await tester.pumpWidget(const SizedBox());

      controller.save().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      heard.clear();
      controller.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        heard,
        ['state Loading', 'state Loaded(Ada Lovelace)'],
        reason: 'the closure handed to removeListener was another object',
      );

      // Closing the controller is what lets it go.
      await controller.close();
      _says('`removeListener` has to be given the very callback '
          '`addListener` took; given anything else it removes nothing and '
          'says nothing.');
      _says('The first closure stays registered and goes on being called, '
          'over a `State` that is gone, until the controller is closed.');
    });

    testWidgets('a group of subscriptions goes with the State', (tester) async {
      final controller = ProfileController(ProfileApi());
      final heard = <String>[];
      await tester.pumpWidget(Listening(controller: controller, heard: heard));

      controller.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        heard,
        ['state Loading', 'state Loaded(Ada Lovelace)', 'canSave true'],
      );

      await tester.pumpWidget(const SizedBox());
      heard.clear();
      controller.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, isEmpty);

      await controller.close();
      _says('`listen` keeps the callback instead and hands back a '
          '`SoloSubscription`; `SoloSubscriptions` cancels a group of them '
          'at once');
    });

    test('listen takes a selection and a listenable of the framework',
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
      _says('`listen` works on any `Listenable` — a controller with '
          '`SoloListenable`, a selection, a `ScrollController` of the '
          "framework's own.");
    });

    test('a second cancel does nothing, a cancelled group cancels at once',
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
      _says('Cancelling twice does nothing the second time, and a group that '
          'has been cancelled cancels what it is handed rather than keeping '
          'it.');
    });

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
      _says('If one member refuses to let go, the others are cancelled all '
          'the same and every failure goes to `FlutterError.reportError`.');
      _says('Cancelling a group never throws');
    });

    testWidgets('a throw out of dispose() costs the elements behind it theirs',
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
      _says('an exception out of there costs the elements behind it in that '
          'frame their own `dispose()`, listeners and all');
    });

    testWidgets('handed another controller, initState goes on hearing the old',
        (tester) async {
      final first = ProfileController(ProfileApi());
      final second = ProfileController(ProfileApi());
      final heard = <String>[];
      await tester.pumpWidget(Listening(controller: first, heard: heard));
      await tester.pumpWidget(Listening(controller: second, heard: heard));

      second.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, isEmpty, reason: 'nobody listens to the new controller');
      first.load().ignore();
      await tester.pump(const Duration(milliseconds: 10));
      expect(heard, isNotEmpty, reason: 'the old one is still listened to');

      await tester.pumpWidget(const SizedBox());
      await first.close();
      await second.close();
      _says('What `initState` subscribes to stays subscribed when the widget '
          'is handed another controller.');
    });

    testWidgets('the subscriptions are taken again into a new group',
        (tester) async {
      Future<List<String>> followed({required bool newGroup}) async {
        final first = ProfileController(ProfileApi());
        final second = ProfileController(ProfileApi());
        final heard = <String>[];
        Widget over(ProfileController controller) => Following(
              controller: controller,
              heard: heard,
              newGroup: newGroup,
            );
        await tester.pumpWidget(over(first));
        await tester.pumpWidget(over(second));

        first.load().ignore();
        await tester.pump(const Duration(milliseconds: 10));
        expect(heard, isEmpty, reason: 'the old controller was let go');
        second.load().ignore();
        await tester.pump(const Duration(milliseconds: 10));

        await tester.pumpWidget(const SizedBox());
        await first.close();
        await second.close();
        return heard;
      }

      expect(
        await followed(newGroup: true),
        ['Loading', 'Loaded(Ada Lovelace)'],
      );
      expect(await followed(newGroup: false), isEmpty);
      _says('cancels the group in `didUpdateWidget` and takes its '
          'subscriptions again, into a new group: the cancelled one would '
          'cancel them on the spot');
    });
  });

  group('Methods from a second import', () {
    test('select and listen arrive as methods', () async {
      final controller = ProfileController(ProfileApi());
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
      _says("They are extensions, and they sit on the framework's own "
          '`ValueListenable` and `Listenable`');
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
      _says('`SoloSelection(controller, (state) => state.canSave)` is the '
          'same selection, `SoloSelector` needs no method at all, and '
          '`addListener` with a callback you keep yourself is what `listen` '
          'does for you');
    });

    test('a select of the controller itself wins over the extension', () async {
      final picker = Picker()..select(7);

      expect(picker.picked, [7]);
      await picker.close();
      _says('Being extensions is also why a controller of your own with a '
          '`select` method keeps it: an extension always steps aside for a '
          'member.');
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

    testWidgets('close() is safe on either side of super.dispose()',
        (tester) async {
      // The page's side, over a load that is still running.
      await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
      final first = controllerOf(
        tester.state<State<ProfileScreen>>(find.byType(ProfileScreen)),
      );
      await tester.pump(const Duration(milliseconds: 3));
      await tester.pumpWidget(const SizedBox());
      expect(first.isFinished, isTrue);
      expect(first.value, isA<Empty>());

      // The other side.
      final second = ProfileController(ProfileApi());
      await tester.pumpWidget(
        MaterialApp(home: LateCloseScreen(controller: second)),
      );
      await tester.pump(const Duration(milliseconds: 3));
      await tester.pumpWidget(const SizedBox());
      expect(second.isFinished, isTrue);
      expect(second.value, isA<Empty>());

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 10));
      _says('It is safe on either side of `super.dispose()`.');
    });

    testWidgets('close() cancels what is queued and what is running',
        (tester) async {
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
      _says('it returns a `Future` that completes when the job has actually '
          'stopped');
    });

    testWidgets('a running body stops at its next context call',
        (tester) async {
      final bench = Bench();
      final log = <String>[];
      bench.go<Profile, void>((ctx) async {
        log.add('first step');
        // A wait the context knows nothing about.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('second step');
        await ctx.pause(const Duration(milliseconds: 10));
        log.add('third step');
      }).ignore();
      await tester.pump(const Duration(milliseconds: 3));

      var closed = false;
      unawaited(bench.close().then((_) => closed = true));
      await tester.pump();
      expect(closed, isFalse);
      await tester.pump(const Duration(milliseconds: 10));

      expect(log, ['first step', 'second step']);
      expect(closed, isTrue);
      _says('a running body stops at its next context call');
    });

    testWidgets('it drops every listener and stops notifying for good',
        (tester) async {
      // What the closing itself changes is still heard: the handler of the
      // load it cancels publishes `Empty`.
      final controller = ProfileController(ProfileApi());
      final heard = <String>[];
      controller
        ..addListener(() => heard.add(show(controller.value)))
        ..load().ignore();
      await tester.pump(const Duration(milliseconds: 3));
      await controller.close();
      expect(heard, ['Loading', 'Empty']);
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

    testWidgets('the outcome of the tap is what the toast says',
        (tester) async {
      expect(await tapped(tester, ProfileApi()), ['hello Ada Lovelace']);
      expect(
        await tapped(tester, ProfileApi(error: StateError('no network'))),
        ['Bad state: no network'],
      );
      expect(tester.takeException(), isNull);
      expect(await tapped(tester, ProfileApi(), closeMeanwhile: true), isEmpty);
      _says('A method hands back its job, so the screen can wait for the end '
          'of the work it started');
    });

    testWidgets('mounted holds the toast back once the screen is gone',
        (tester) async {
      expect(await tapped(tester, ProfileApi(), leaveMeanwhile: true), isEmpty);
      _says('`mounted` after an `await` is the usual Flutter rule and it '
          'applies here too.');
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
      _says('`done` never throws; `value` gives the value, rethrows the '
          'failure of a job that failed and throws the `Cancelled` of one '
          'that was cancelled.');
    });

    testWidgets('an unobserved Failed reaches the zone that created the job',
        (tester) async {
      Future<List<Object>> inZone(
        void Function(ProfileController controller) use,
      ) async {
        final errors = <Object>[];
        // The controller belongs to the zone of the test; the job is
        // created in a zone of its own.
        final controller = ProfileController(
          ProfileApi(error: StateError('no network')),
        );
        runZonedGuarded(
          () => use(controller),
          (error, stackTrace) => errors.add(error),
        );
        await tester.pump(const Duration(milliseconds: 10));
        await controller.close();
        return errors;
      }

      expect(await inZone((controller) => controller.load()), [
        isA<StateError>(),
      ]);
      expect(await inZone((controller) => controller.load().ignore()), isEmpty);
      expect(
        await inZone((controller) => unawaited(controller.load().done)),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      _says('an unobserved `Failed` reaches the zone that created the job, so '
          'a fire-and-forget call is `controller.load().ignore()`');
    });

    testWidgets('unattended work that fails takes the same road',
        (tester) async {
      Future<List<Object>> inZone(Background controller) async {
        final errors = <Object>[];
        runZonedGuarded(
          () => controller.ping().ignore(),
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
      addTearDown(() => Solo.errorHandler = null);
      Solo.errorHandler = (solo, job, error, stackTrace) => handled.add(error);
      expect(await inZone(Background()), isEmpty);
      expect(handled, [isA<StateError>()]);
      Solo.errorHandler = null;

      _says('The same road carries the errors no outcome holds — the failure '
          'of work a body handed to `ctx.unattended`, say — unless the '
          'controller overrides `onUnanswered` or a `Solo.errorHandler` is '
          'set to answer for them');
    });

    testWidgets('an observer sees such a failure and does not take it',
        (tester) async {
      final watching = Watching();
      addTearDown(() => Solo.observer = null);
      Solo.observer = watching;
      final errors = <Object>[];
      final controller = Background();
      runZonedGuarded(
        () => controller.ping().ignore(),
        (error, stackTrace) => errors.add(error),
      );
      await tester.pump(const Duration(milliseconds: 5));

      expect(watching.seen, [isA<StateError>()]);
      expect(errors, [isA<StateError>()]);
      await controller.close();
      _says('A `SoloObserver` sees such a failure and does not take it: '
          'watching is not answering.');
    });

    test('an error zone of your own comes before PlatformDispatcher.onError',
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
      _says('the error travels the zones outwards, so an error zone of your '
          'own around `runApp` sees it first. Past that it reaches '
          '`PlatformDispatcher.instance.onError` if you set one.');
    });
  });

  group('Testing', () {
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
      expect(controller.value, isA<Loading>());

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
      _says('nothing inside it moves that clock but the test');
    });

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
      expect(quiet.value, isA<Loading>());
      expect(find.text('Loading'), findsOneWidget);

      await tester.pump(second);
      await spinning.close();
      await quiet.close();
      _says('`pumpAndSettle` pumps a frame every hundred milliseconds for as '
          'long as another frame is asked for.');
      _says('a slower one would be waited for as well, because the spinner '
          'of `Loading` keeps asking for frames');
      _says('with nothing animating, `pumpAndSettle` stops after a frame or '
          'two, and a load that takes longer than that is still waiting');
    });

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
      _says('a `Failed` nobody has asked about is reported as the job ends, '
          'to the zone it was created in. Here that is the zone of the test, '
          'which fails the test on the spot, and `tester.takeException()` '
          'has nothing to take afterwards.');
      _says('A load that fails makes a test red even though it reads `done`, '
          'if it reads it after the pump.');
    });

    testWidgets('a job the test drops says so with ignore()', (tester) async {
      final controller = ProfileController(
        FakeApi(error: StateError('no network')),
      );
      controller.load().ignore();
      await tester.pump(const Duration(milliseconds: 20));

      expect(controller.value, isA<Empty>());
      await controller.close();
      _says('A job the test starts and drops says so with `ignore()`.');
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

      controller.load().ignore();
      await tester.pump();
      expect(controller.value, isA<Loading>());
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

      controller.load().ignore();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 10));
      await controller.close();
      _says('unless a frame was already asked for, as one is right after a '
          '`MaterialApp` has been pumped');
    });

    testWidgets('closed in the body, a controller with a load running lets go',
        (tester) async {
      final controller = ProfileController(FakeApi());
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(controller: controller)),
      );
      await tester.tap(find.text('Load'));
      await tester.pump();
      expect(controller.value, isA<Loading>());

      await controller.close();

      expect(controller.isFinished, isTrue);
      // The call the load walked away from is the fake's own timer.
      await tester.pump(const Duration(milliseconds: 10));
      _says('And the controller is closed in the body of the test, not in '
          '`addTearDown`');
    });

    test('awaited once the clock has stopped, the same close() never returns',
        () async {
      late ProfileController controller;
      final reported = await _asWidgetTest((binding) async {
        // The answer of this API never comes, so the load is still running
        // when the body ends, as it is when an expectation fails halfway
        // through one.
        controller = ProfileController(SilentApi());
        controller.load().ignore();
        await binding.pump();
        expect(controller.value, isA<Loading>());
      });
      expect(reported, isEmpty);

      // What a tear-down does next.
      var back = false;
      unawaited(controller.close().then((_) => back = true));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(back, isFalse);
      expect(controller.isFinished, isFalse);
      _says('a tear-down runs after the fake clock has stopped, and a '
          '`close()` awaited there with a job still running — an '
          'expectation that failed halfway through a load is enough — never '
          'comes back.');
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
            load.load().ignore();
          } else {
            final load = ProfileController(SilentApi());
            controller = load;
            load.load().ignore();
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
            'disposed`, where the same job without a deadline lets the test '
            'pass.');
        unawaited(controller.close());
      });
    }

    test('closed in the body, a job with a deadline takes its timer along',
        () async {
      late TimedLoad controller;
      final reported = await _asWidgetTest((binding) async {
        controller = TimedLoad(SilentApi());
        final job = controller.load()..ignore();
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
      _says('Synchronously, in subscription order, on every state change. '
          '`value` and `currentState` are the same object.');
    });

    testWidgets('equal states are not filtered, and a frame swallows several',
        (tester) async {
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
      }).ignore();
      await tester.pump();
      await tester.pump();

      expect(heard, 4);
      expect(picked, [true]);
      expect(built, ['Empty', 'Loaded(Bob)']);
      group.cancel();
      await bench.close();
      _says('`emit` of a state equal to the current one still notifies');
      _says('A frame may swallow several of them, a listener will not. A '
          'selection filters its own value');
    });

    testWidgets('one widget over two controllers takes a merge',
        (tester) async {
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
      _says('`Listenable.merge([a, b])` in a `ListenableBuilder` covers the '
          'case where one widget depends on two.');
    });

    test('the mixin gives value no setter', () {
      final mixin = File('lib/src/solo_listenable.dart').readAsStringSync();

      expect(mixin, contains('S get value => currentState;'));
      expect(mixin, isNot(contains('set value')));
      _says('There is no setter.');
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
      _says('the rest of the API, which this package re-exports whole — '
          '`SoloStream` included');
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
