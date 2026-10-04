import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mixins_app.dart' as answer;
import 'support/mixins_app_first.dart' as first;
import 'support/mixins_app_shared.dart' as shared;
import 'support/mixins_base.dart' as answer_base;
import 'support/mixins_base_first.dart' as first_base;
import 'support/mixins_log.dart';
import 'support/mixins_session.dart';
import 'support/page_code.dart';
import 'support/readme_profile.dart' show Empty, Loading, Profile;

/// The sentinel of `doc/mixins.md`.
///
/// The code of the page stands verbatim in `test/support/`:
/// `mixins_session.dart` holds the two sections on the session, and the
/// section on a base class is five files, because a block of it shows two
/// libraries and its versions declare the same names — `mixins_base_first`
/// and `mixins_base` are the package without Flutter, `mixins_app_first`,
/// `mixins_app` and `mixins_app_shared` the app. The tests below run that
/// code. What the page says in prose about a version it does not show is
/// run from the classes at the foot of this file, and a test that checks a
/// sentence holds the page to it through [_says]. The lines the page
/// quotes under a block are compared with what the run shows, through
/// [_quotes].
///
/// The bench `tool/flutter_snippets.py` builds the same code out of the
/// markdown itself, in a package of its own, and it is the bench that holds
/// the page to what it says of the analyzer; this file is what `flutter
/// test` of the package knows about the page.

const _doc = 'doc/mixins.md';
const _session = 'test/support/mixins_session.dart';
const _baseFirst = 'test/support/mixins_base_first.dart';
const _appFirst = 'test/support/mixins_app_first.dart';
const _base = 'test/support/mixins_base.dart';
const _app = 'test/support/mixins_app.dart';
const _appShared = 'test/support/mixins_app_shared.dart';

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

/// The blocks of the page under [fence], in order.
List<String> _blocks(String fence) => [
      for (final block
          in RegExp('```$fence\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block[1]!,
    ];

/// The lines the page quotes under its code, block by block.
List<String> _quotes() => _blocks('text');

List<String?> _imports(String file) => [
      for (final match in RegExp("^import '([^']+)'", multiLine: true)
          .allMatches(File(file).readAsStringSync()))
        match[1],
    ];

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

String _shown(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first).data!;

/// The badge among the texts of a whole app.
String _badge(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data!)
    .lastWhere((text) => text.startsWith('signed') || text == 'nothing yet');

/// A session of the page, signed in and closed when the test is over.
///
/// One the body has closed is left alone. The future of that close belongs
/// to the fake clock of the body, and a tear-down runs outside it: awaiting
/// the future there waits for a clock nobody turns any more.
Future<Session> _signedIn([String name = 'Ada']) async {
  final session = Session(const SignedOut());
  addTearDown(() async {
    if (!session.isFinished) {
      await session.close();
    }
  });
  await session.signIn(name).done;
  return session;
}

/// The three steps the page quotes under a badge, taken over [badge]: what
/// the screen shows after each, as the lines of the page.
Future<String> _threeLines(
  WidgetTester tester,
  Widget Function(Session session) badge, {
  Session? another,
}) async {
  final session = await _signedIn();
  final other = another ?? await _signedIn('Cy');
  final lines = <String>[];

  await tester.pumpWidget(_wrap(badge(session)));
  lines.add('mounted over a session signed in as Ada: ${_shown(tester)}');
  await session.signIn('Bob').done;
  await tester.pump();
  lines.add('after Bob signs in: ${_shown(tester)}');
  await tester.pumpWidget(_wrap(badge(other)));
  lines.add('handed another session, signed in as Cy: ${_shown(tester)}');
  return lines.join('\n');
}

/// What a failure of a listener of [profile] reaches, as the two lines the
/// page quotes under a block of "A base class without Flutter".
Future<String> _reached(
  Solo<Profile> profile,
  void Function(Profile state) set,
) async {
  String said(List<Object> errors) =>
      errors.isEmpty ? 'nothing' : errors.join(', ');

  AppLog.errors.clear();
  final reports = <Object>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => reports.add(details.exception);
  try {
    profile.addListener(() => throw StateError('the listener blew up'));
    set(Loading());
    await profile.close();
  } finally {
    FlutterError.onError = previous;
  }
  return 'AppLog: ${said(AppLog.errors)}\nFlutterError: ${said(reports)}';
}

const _toBoth = 'AppLog: Bad state: the listener blew up\n'
    'FlutterError: Bad state: the listener blew up';

void main() {
  // A widget test is given ten minutes by default, and a sentinel that
  // takes that long to say a wait never ended is one nobody runs.
  (TestWidgetsFlutterBinding.ensureInitialized()
          as AutomatedTestWidgetsFlutterBinding)
      .defaultTestTimeout = const Timeout(Duration(seconds: 30));

  group('The page', () {
    test('every piece of its code stands in the files of its heading', () {
      for (final (under, files) in [
        ('## A controller with both deliveries', [_session]),
        ('### The first attempt', [_session, _baseFirst, _appFirst]),
        ('### The second attempt', [_session]),
        ('### A builder that takes the controller', [_session]),
        ('### A report under another name', [_base, _app, _appShared]),
      ]) {
        expect(
          codeMissingFrom(
            _doc,
            files.first,
            alsoIn: files.skip(1).toList(),
            under: under,
          ),
          isEmpty,
          reason: under,
        );
      }
    });

    test('its blocks are dart and text, seven and six', () {
      expect(strayFences(_doc), isEmpty);
      expect(
        _blocks('dart'),
        hasLength(7),
        reason: 'a new block of the page needs a place in the support files '
            'and a test that runs it',
      );
      expect(_quotes(), hasLength(6));
    });

    test('the package without Flutter imports meta and solo, no Flutter', () {
      // `flutter_solo` takes the annotation from Flutter; `meta` is a dev
      // dependency of the package so that these two files need not.
      for (final file in [_baseFirst, _base]) {
        expect(
          _imports(file),
          [
            'package:meta/meta.dart',
            'package:solo/solo.dart',
            'mixins_log.dart',
          ],
          reason: file,
        );
      }
      expect(_imports('test/support/mixins_log.dart'), isEmpty);
      _says('can live in a package with no Flutter in it');
    });

    test('every override of the hook it shows repeats @protected', () {
      // Dart does not inherit the annotation, and the analyzer is the only
      // place a missing one shows: a runtime call cannot tell the two
      // apart, so the guard reads the code of the page.
      final code = _blocks('dart').join('\n');
      final overrides = RegExp(r'@override\s+void onListenerError\(');
      final annotated =
          RegExp(r'@protected\s+@override\s+void onListenerError\(');
      expect(overrides.allMatches(code), hasLength(4));
      expect(annotated.allMatches(code), hasLength(4));
      _says('`@protected` is repeated on every override');
    });
  });

  group('A controller with both deliveries', () {
    test('the listener is inside the change, the event a microtask later',
        () async {
      final session = DrivenSession(const SignedOut());
      addTearDown(session.close);
      final log = <String>[];
      session.addListener(() => log.add('the listener'));
      session.stream.listen((_) => log.add('the event'));

      scheduleMicrotask(() => log.add('a microtask from before the change'));
      session.set(const SignedIn('Ada'));
      log.add('the change is made');
      scheduleMicrotask(() => log.add('a microtask from after the change'));
      await Future<void>.delayed(Duration.zero);

      expect(log, [
        'the listener',
        'the change is made',
        'a microtask from before the change',
        'the event',
        'a microtask from after the change',
      ]);
      _says('fires synchronously, inside the change, and the `stream` event '
          'arrives a microtask later');
    });

    test('one change has two error routes', () async {
      final flutterErrors = <Object>[];
      final subscribedIn = <Object>[];
      final changedIn = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => flutterErrors.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      final session = Session(const SignedOut());
      addTearDown(session.close);
      session.addListener(() => throw StateError('the listener'));
      runZonedGuarded(
        () => session.stream.listen((_) => throw StateError('the subscriber')),
        (error, stackTrace) => subscribedIn.add(error),
      );
      late Job<void> job;
      runZonedGuarded(
        () => job = session.signIn('Ada'),
        (error, stackTrace) => changedIn.add(error),
      );
      await job.done;
      await Future<void>.delayed(Duration.zero);

      expect(flutterErrors.map((e) => '$e'), ['Bad state: the listener']);
      expect(subscribedIn.map((e) => '$e'), ['Bad state: the subscriber']);
      expect(
        changedIn,
        isEmpty,
        reason: 'the zone is the one the subscriber subscribed in, not the '
            'one the change was made in',
      );
      _says("a listener's failure goes to `FlutterError`, and a failure of a "
          '`stream` subscriber goes to the zone it subscribed in');
    });

    test('an await for over the stream holds close() while its body awaits',
        () async {
      final session = Session(const SignedOut());
      final body = Completer<void>();
      final loop = () async {
        await for (final _ in session.stream) {
          await body.future;
        }
      }();
      await session.signIn('Ada').done;
      await Future<void>.delayed(Duration.zero);

      var closed = false;
      final closing = session.close().then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse);
      expect(session.isFinished, isTrue);
      expect(session.pending, isA<SoloPendingStream>());

      body.complete();
      await closing;
      await loop;
      expect(closed, isTrue);
      expect(session.pending, isNull);
      _says('an `await for` over the `stream` holds `close()` while its body '
          'is still awaiting');
      _says('`pending` is a `SoloPendingStream` all that time');
    });

    test('a controller with SoloListenable alone waits for no listener',
        () async {
      final session = _ListenableOnly(const SignedOut())..addListener(() {});
      await session.signIn('Ada').done;

      var closed = false;
      final closing = session.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue);
      await closing;
      _says('a controller with `SoloListenable` alone waits for none of its '
          'listeners');
    });

    test('the order of the two mixins makes no difference', () async {
      final flutterErrors = <Object>[];
      final zoneErrors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => flutterErrors.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      final session = _Reversed(const SignedOut());
      final order = <String>[];
      final body = Completer<void>();
      late Future<void> loop;
      session.addListener(() {
        order.add('the listener');
        throw StateError('the listener');
      });
      runZonedGuarded(
        () {
          session.stream.listen((_) {
            order.add('the event');
            throw StateError('the subscriber');
          });
          loop = () async {
            await for (final _ in session.stream) {
              await body.future;
            }
          }();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await session.signIn('Ada').done;
      await Future<void>.delayed(Duration.zero);

      var closed = false;
      final closing = session.close().then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final held = !closed && session.pending is SoloPendingStream;
      body.complete();
      await closing;
      await loop;

      expect(session, isA<ValueListenable<SessionState>>());
      expect(order, ['the listener', 'the event']);
      expect(flutterErrors.map((e) => '$e'), ['Bad state: the listener']);
      expect(zoneErrors.map((e) => '$e'), ['Bad state: the subscriber']);
      expect(held, isTrue);
      _says('The order of the two mixins makes no difference');
    });

    testWidgets('both deliveries are live', (tester) async {
      final session = Session(const SignedOut());
      addTearDown(session.close);
      final events = <SessionState>[];
      final subscription = session.stream.listen(events.add);
      addTearDown(subscription.cancel);

      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SessionState>(
            valueListenable: session,
            builder: (context, state, _) => Text('${state.runtimeType}'),
          ),
        ),
      );
      expect(_shown(tester), 'SignedOut');

      await session.signIn('Ada').done;
      await tester.pump();
      expect(_shown(tester), 'SignedIn');
      expect(events.single, isA<SignedIn>());
      _says('Both deliveries are live');
    });
  });

  group('A screen built on the stream', () {
    testWidgets('the first attempt opens with nothing', (tester) async {
      final session = await _signedIn();
      final lines = <String>[];

      await tester.pumpWidget(_wrap(SessionBadge(session)));
      lines.add('mounted over a session signed in as Ada: ${_shown(tester)}');
      await tester.pump(const Duration(hours: 8));
      expect(
        _shown(tester),
        'nothing yet',
        reason: 'no change, no event, however long the wait',
      );
      await session.signIn('Bob').done;
      await tester.pump();
      lines.add('after Bob signs in: ${_shown(tester)}');

      expect(lines.join('\n'), _quotes()[0]);
      _says('the wait is as long as the next change');
    });

    testWidgets('while currentState holds the state in the same builder',
        (tester) async {
      final session = await _signedIn();
      final seen = <String>[];
      await tester.pumpWidget(
        _wrap(
          StreamBuilder<SessionState>(
            stream: session.stream,
            builder: (context, snapshot) {
              seen.add(
                '${snapshot.data.runtimeType} ${session.currentState}',
              );
              return SessionBadge(session);
            },
          ),
        ),
      );
      expect(seen, ["Null Instance of 'SignedIn'"]);
      expect(_shown(tester), 'nothing yet');
      _says('`currentState` holds `SignedIn` in the same builder that renders '
          '`nothing yet`');
    });

    testWidgets('a route pushed and a tab switched back build it anew',
        (tester) async {
      final session = await _signedIn();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: SessionBadge(session)),
        ),
      );
      await session.signIn('Bob').done;
      await tester.pump();

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('another screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        _badge(tester),
        'signed in as Bob',
        reason: 'a screen popped back to was never taken down',
      );

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: SessionBadge(session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_badge(tester), 'nothing yet', reason: 'its route pushed');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: const TabBar(
                tabs: [Tab(text: 'badge'), Tab(text: 'other')],
              ),
              body: TabBarView(
                children: [SessionBadge(session), const Text('another tab')],
              ),
            ),
          ),
        ),
      );
      await session.signIn('Cy').done;
      await tester.pump();
      expect(_badge(tester), 'signed in as Cy');
      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('badge'));
      await tester.pumpAndSettle();
      expect(_badge(tester), 'nothing yet', reason: 'a tab switched back');
      _says('its route pushed, a tab switched away and back');
    });

    testWidgets('closing makes the wait endless', (tester) async {
      final session = await _signedIn();
      final lines = <String>[];

      await tester.pumpWidget(_wrap(SessionBadge(session)));
      lines.add('mounted over a session signed in as Ada: ${_shown(tester)}');
      await session.close();
      await tester.pump();
      lines.add('after close(): ${_shown(tester)}');

      expect(lines.join('\n'), _quotes()[1]);
      expect(session.currentState, isA<SignedIn>());
      _says('while `currentState` still holds the state the badge never '
          'showed');
    });

    testWidgets('the second attempt keeps the data of the old stream',
        (tester) async {
      final other = await _signedIn('Cy');
      expect(
        await _threeLines(tester, withInitialData, another: other),
        _quotes()[2],
      );

      await tester.pump(const Duration(hours: 1));
      expect(_shown(tester), 'signed in as Bob');
      await other.signIn('Dan').done;
      await tester.pump();
      expect(_shown(tester), 'signed in as Dan');
      _says("the badge shows Bob over Cy's session until that session "
          'changes');
    });

    testWidgets('and a key made of the session repairs it', (tester) async {
      final lines = await _threeLines(tester, _withInitialDataAndKey);
      expect(lines, _quotes()[3], reason: 'the lines of the answer');
      _says('With `key: ObjectKey(session)` next to `initialData`');
      _says('the badge shows Cy at once');
    });

    testWidgets('a builder over the controller needs nothing passed',
        (tester) async {
      final other = await _signedIn('Cy');
      expect(
        await _threeLines(tester, overTheController, another: other),
        _quotes()[3],
      );

      await other.signIn('Dan').done;
      await tester.pump();
      expect(_shown(tester), 'signed in as Dan');
      await other.close();
      await tester.pump();
      expect(
        _shown(tester),
        'signed in as Dan',
        reason: 'a closed controller still has its state to show',
      );
    });

    testWidgets('and ValueListenableBuilder shows the same three lines',
        (tester) async {
      expect(await _threeLines(tester, _overTheListenable), _quotes()[3]);
      _says('with `valueListenable: session` it shows the same three lines');
    });
  });

  group('A base class without Flutter', () {
    test('the first attempt reports past the base', () async {
      final profile = first.DrivenProfile();
      expect(await _reached(profile, profile.set), _quotes()[4]);
      expect(profile, isA<ValueListenable<Profile>>());
    });

    test('whose override runs where nothing is mixed in', () async {
      final profile = _PlainFirst();
      expect(await _reached(profile, profile.set), _quotes()[5]);
      _says('so its override wins, with a report through `FlutterError`, and '
          "the base's override never runs");
    });

    test('super in the leaf is the mixin', () async {
      final profile = _SuperFirst();
      expect(await _reached(profile, profile.set), _quotes()[4]);
      _says('`super` there is the mixin');
    });

    test('the report under another name reaches the log', () async {
      final profile = answer.DrivenProfile();
      expect(await _reached(profile, profile.set), _quotes()[5]);
      expect(profile, isA<ValueListenable<Profile>>());
    });

    test('the base reports for a controller that mixes nothing in', () async {
      final profile = _Plain();
      expect(await _reached(profile, profile.set), _quotes()[5]);
      _says("The base's hook reports for a controller that mixes nothing in");
    });

    test('super next to the report reaches FlutterError as well', () async {
      final profile = _BothReports();
      expect(await _reached(profile, profile.set), _toBoth);
      _says('calls `super.onListenerError` next to `reportListenerError`');
    });

    test('a leaf without the override reports as in the first attempt',
        () async {
      final profile = _Forgetful();
      expect(await _reached(profile, profile.set), _quotes()[4]);
      _says('a leaf that mixes `SoloListenable` in without it reports through '
          '`FlutterError` as in the first attempt');
    });

    test('the override of the class between runs in every leaf', () async {
      final profile = shared.DrivenProfile();
      expect(await _reached(profile, profile.set), _quotes()[5]);
      expect(profile, isA<ValueListenable<Profile>>());
      final settings = _Settings();
      expect(await _reached(settings, settings.set), _quotes()[5]);
      _says('`ProfileController` here reports to `AppLog` and not through '
          '`FlutterError`');
      _says('in every leaf that extends it');
    });

    test('a base with Flutter in it keeps its own override', () async {
      final profile = _OverFlutterBase();
      expect(await _reached(profile, profile.set), _quotes()[5]);
      _says('A base with Flutter in it mixes `SoloListenable` in itself and '
          'keeps its own override the same way');
    });

    test('mixed in again on a leaf, the mixin silences the override', () async {
      final profile = _Twice();
      expect(await _reached(profile, profile.set), _quotes()[4]);
      _says('mixed in again on a leaf over such a class, it sits above that '
          'override and silences it as in the first attempt');
    });
  });
}

// What the page says in prose about code it does not show. None of this is
// page code, and the first test never looks for the page's code here.

/// The session of the page with its two mixins the other way round.
final class _Reversed extends Solo<SessionState>
    with SoloListenable, SoloStream {
  _Reversed(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}

/// The session of the page without the stream.
final class _ListenableOnly extends Solo<SessionState> with SoloListenable {
  _ListenableOnly(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}

/// The second attempt with the key the page names.
Widget _withInitialDataAndKey(Session session) => StreamBuilder<SessionState>(
      key: ObjectKey(session),
      stream: session.stream,
      initialData: session.currentState,
      builder: (context, snapshot) => Text(
        switch (snapshot.requireData) {
          SignedIn(:final name) => 'signed in as $name',
          SignedOut() => 'signed out',
        },
      ),
    );

/// The builder of the framework the page says `Session` fits as well.
Widget _overTheListenable(Session session) =>
    ValueListenableBuilder<SessionState>(
      valueListenable: session,
      builder: (context, state, _) => Text(
        switch (state) {
          SignedIn(:final name) => 'signed in as $name',
          SignedOut() => 'signed out',
        },
      ),
    );

/// A controller of the first attempt's base that mixes nothing in.
final class _PlainFirst extends first_base.AppController<Profile> {
  _PlainFirst() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// The leaf of the first attempt with the `super` the page says is no help.
final class _SuperFirst extends first_base.AppController<Profile>
    with SoloListenable {
  _SuperFirst() : super(Empty());

  void set(Profile state) => externalSetState(state);

  @protected
  @override
  // What the page says the analyzer calls it; the bench holds it to that.
  // ignore: unnecessary_overrides
  void onListenerError(Object error, StackTrace stackTrace) =>
      super.onListenerError(error, stackTrace);
}

/// A controller of the answer's base that mixes nothing in.
final class _Plain extends answer_base.AppController<Profile> {
  _Plain() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A leaf that wants the report through `FlutterError` as well.
final class _BothReports extends answer_base.AppController<Profile>
    with SoloListenable {
  _BothReports() : super(Empty());

  void set(Profile state) => externalSetState(state);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    reportListenerError(error, stackTrace);
    super.onListenerError(error, stackTrace);
  }
}

/// A leaf over the answer's base that mixes the mixin in and writes no
/// override.
final class _Forgetful extends answer_base.AppController<Profile>
    with SoloListenable {
  _Forgetful() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A second leaf of the class between, with no override of its own either.
final class _Settings extends shared.ListenableController<Profile> {
  _Settings() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// The mixin once more, on a leaf over the class that already has it.
final class _Twice extends shared.ListenableController<Profile>
    with SoloListenable {
  _Twice() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A base with Flutter in it, which mixes the mixin in itself.
abstract class _FlutterBase<S extends Object> extends Solo<S>
    with SoloListenable {
  _FlutterBase(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);
}

final class _OverFlutterBase extends _FlutterBase<Profile> {
  _OverFlutterBase() : super(Empty());

  void set(Profile state) => externalSetState(state);
}
