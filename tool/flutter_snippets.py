#!/usr/bin/env python3
"""Builds runnable screens from the README of flutter_solo and from its
doc/mixins.md.

Every snippet is copied out of the markdown and wrapped in a file that
runs: fakes above it, a driver below it. That is what keeps the document
honest -- the code in it is the code that ran.

Usage, from the repository root:

    python3 tool/flutter_snippets.py [workdir]

The default workdir is /tmp/solo-flutter-check. It creates one package,
flutter_check, with a path dependency on packages/flutter_solo and
overrides down to packages/solo and packages/async_job. Then:

    flutter pub get
    flutter analyze
    flutter test

The drivers are widget tests rather than programs under bin/, because
what this document shows are widgets: a screen needs a binding to be
built, pumped and read back. `flutter test` is what provides one.

One liberty is taken with the snippets, and it is the only one. Import
lines are hoisted to the head of the driver, verbatim, because a file
takes its directives before its declarations. Everything between the
imports is byte-identical to the document. The driver of the README adds
no import of its own but that of `flutter_test`, so a block that stops
showing an import it needs stops the driver compiling.

Every Dart block of the README of flutter_solo is built -- the first page
a user of the package copies from. That README went without a bench until
2026-09-19 and did not compile: the model it declared had neither the
`canSave` nor the `save` the rest of the page used. doc/mixins.md takes
the model of that README, the states of `Profile`, and is built against
them. A Dart block of either page that no driver takes stops the build:
a block nobody builds is a block nobody runs.

The section of doc/mixins.md on a base class shows two versions of the
same two classes, and a name declared twice in a section answers to
neither. Its blocks are addressed by the subsection they stand in instead,
`the-first-attempt/AppController`; the rest of the page by its sections.
A block of that section shows two libraries, a package without Flutter and
the app, and is built as two: the first under the imports the page shows
and no others, so the base the page calls free of Flutter is built without
it.
The section of the README on listening is addressed the same way: its
first attempt and its answer both declare `initState` and `dispose`.

The quick start of solo's README is built here as well. It is pure Dart
and belongs to no widget, and a Dart file compiles in a Flutter package the
same as anywhere -- with its import of `solo` read as one of flutter_solo,
which re-exports it. `packages/solo/test/readme_rakes_test.dart` runs the
code of that README too, inside the package; this bench keeps proving that
the quick start builds against flutter_solo.

What the drivers print is quoted by the document in `text` blocks, and
`tool/check_traces.py` holds the two together. The guards in them are
what makes a broken document red rather than merely quiet: a driver that
only printed would pass with an empty screen.
"""
import os
import re
import shutil
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/solo-flutter-check'
DOC = os.path.join(REPO, 'packages', 'flutter_solo', 'doc', 'mixins.md')
README = os.path.join(REPO, 'packages', 'solo', 'README.md')
FLUTTER_README = os.path.join(REPO, 'packages', 'flutter_solo', 'README.md')

PUBSPEC = """name: flutter_check
publish_to: none

environment:
  sdk: ^3.6.0
  flutter: '>=3.27.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_solo:
    path: {flutter_solo}
  # The package without Flutter of doc/mixins.md imports these two by name.
  meta: any
  solo: any

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter

# The bench must see the tree, not pub.dev: flutter_solo in the tree can
# depend on a solo that is not released yet, and without this the snippets
# run against a different engine than the package they document.
dependency_overrides:
  async_job:
    path: {async_job}
  solo:
    path: {solo}
""".format(
    flutter_solo=os.path.join(REPO, 'packages', 'flutter_solo'),
    solo=os.path.join(REPO, 'packages', 'solo'),
    async_job=os.path.join(REPO, 'packages', 'async_job'),
)

# The package's own rules, so a fragment that passes here is a fragment
# that would pass inside packages/flutter_solo. Three rules are off, and
# each is about a driver rather than about a snippet: a test file names
# its fakes without dartdoc, it prints, and it carries the states a
# snippet needs whether or not the driver mentions every one of them.
#
# One rule is on that the package does not ask for. doc/mixins.md says what
# the analyzer calls an override that only calls `super`, and what
# `@protected` keeps out of reach; with `unnecessary_ignore` every
# `// ignore:` of a driver is a statement the analyzer checks, and a line
# without one is a line it has nothing to say about.
OPTIONS = """include: flutter_rules.yaml

linter:
  rules:
    avoid_print: false
    public_member_api_docs: false
    unnecessary_ignore: true
    unreachable_from_main: false
"""

class Blocks(dict):
    """The blocks of one document by key, remembering which were taken.

    What a driver takes it builds. A block nobody took is found at the end
    of this script, and a key that two blocks of a section answer to is
    refused here rather than handed over as either of them.
    """

    def __init__(self, found, taken):
        super().__init__(found)
        self.taken = taken

    def __getitem__(self, key):
        block = super().__getitem__(key)
        if block is doc_blocks.POISONED:
            raise KeyError(f'{key} is declared twice in its section')
        self.taken.add(block)
        return block


_taken_doc = set()
_taken_readme = set()
snips = Blocks(doc_blocks.blocks(
    open(DOC).read(), 'dart', doc_blocks.DECLARES['dart']), _taken_doc)
# Two blocks of the quick start and no more: the rest of that README is
# built and run inside `packages/solo`, by its own sentinel.
readme = doc_blocks.blocks(
    open(README).read(), 'dart', doc_blocks.DECLARES['dart'])
_fr = Blocks(doc_blocks.blocks(
    open(FLUTTER_README).read(), 'dart', doc_blocks.DECLARES['dart']),
    _taken_readme)


def subsections(text, section, taken):
    """{key: source} of one `## ` section, keyed by its `### ` headings."""
    for key, body in doc_blocks.sections(text):
        if key == section:
            return Blocks(doc_blocks.blocks(
                '\n## ' + body.replace('\n### ', '\n## '),
                'dart', doc_blocks.DECLARES['dart']), taken)
    raise KeyError(section)


base = subsections(
    open(DOC).read(), 'a-base-class-without-flutter', _taken_doc)


def split_imports(block):
    """(import lines, the rest of the block)."""
    lines = block.split('\n')
    imports = [line for line in lines if line.startswith('import ')]
    rest = '\n'.join(line for line in lines if not line.startswith('import '))
    return imports, rest.strip('\n') + '\n'


def wrap(name, block, parameter='Session session'):
    """A widget expression from the document, as a function that returns it."""
    return f'Widget {name}({parameter}) =>\n    {block.strip()};\n'


# The states the README of flutter_solo declares under Usage, which the
# page takes as its model: the head of that block, up to the controller.
_usage = _fr['usage/ProfileController']
PROFILE_STATES = _usage[_usage.index('sealed class Profile'):
                        _usage.index('final class ProfileController')]
PROFILE_STATES = PROFILE_STATES.strip('\n') + '\n'

WRAP = """
Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

String onScreen(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first).data!;

void show(WidgetTester tester, String label) =>
    debugPrint('$label: ${onScreen(tester)}');
"""

FILES = {}

# ------------------------------------------------- the quick start of solo
# The import of `solo` is the one line not taken over: this package depends
# on flutter_solo, which re-exports it.
_states_imports, _states_body = split_imports(
    readme['quick-start/ProfileState'])
assert _states_imports == ["import 'package:solo/solo.dart';"], _states_imports

FILES['quick_start_test'] = '\n'.join([
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    _states_body,
    readme['quick-start/ProfileApi'],
    '''
void main() {
  test('the quick start loads, and a second call gets the same job',
      () async {
    final profile = ProfileController(ProfileApi());
    addTearDown(profile.close);

    final job = profile.load();
    expect(identical(profile.load(), job), isTrue);
    expect(await job.value, 'Ada Lovelace');
    expect(profile.currentState, isA<Loaded>());
  });
}
''',
])

# ---------------------------------------------------------- both deliveries
# The drivers of this page close a controller in `addTearDown` and wait for
# it, where the drivers of the README go through `closing`, which does not
# wait. Waiting is right here. A job of this page is one `ctx.emit` and
# holds no timer, so nothing is running when a test body ends, and a red
# driver under `testWidgets` still closes at once: probed 2026-10-04 with a
# mounted `StreamBuilder`, a `SoloBuilder`, a subscription of the test's
# own and a job started and not awaited. The one driver that closes inside
# its body registers no tear-down, and must not: the future of a close made
# under the fake clock is never delivered to a tear-down, which runs outside
# that clock, and the test waits out its timeout.
_session = snips['a-controller-with-both-deliver/Session']

FILES['deliveries_test'] = '\n'.join([
    "import 'dart:async';",
    '',
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    _session,
    '''
/// A session without the stream, for what the section compares against.
final class PlainSession extends Solo<SessionState> with SoloListenable {
  PlainSession(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}

/// The session of the page with its two mixins the other way round.
final class Reversed extends Solo<SessionState>
    with SoloListenable, SoloStream {
  Reversed(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}
''',
    WRAP,
    '''
void main() {
  test('one change, two error routes', () async {
    final session = Session(const SignedOut());
    addTearDown(session.close);
    final flutterErrors = <Object>[];
    final zoneErrors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => flutterErrors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    session.addListener(() => throw StateError('the listener'));
    runZonedGuarded(
      () => session.stream.listen((_) => throw StateError('the subscriber')),
      (error, stackTrace) => zoneErrors.add(error),
    );
    await session.signIn('Ada').done;
    await Future<void>.delayed(Duration.zero);

    expect(
      flutterErrors.map((error) => '$error'),
      ['Bad state: the listener'],
      reason: 'a listener fails through FlutterError',
    );
    expect(
      zoneErrors.map((error) => '$error'),
      ['Bad state: the subscriber'],
      reason: 'a stream subscriber fails into the zone it subscribed in',
    );
  });

  test('an await for over the stream holds close while its body awaits',
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
    expect(session.isFinished, isTrue);
    expect(closed, isFalse, reason: 'the body is still awaiting');
    expect(
      session.pending,
      isA<SoloPendingStream>(),
      reason: 'what holds the close has a name',
    );

    body.complete();
    await closing;
    await loop;
    expect(closed, isTrue);
    expect(session.pending, isNull);
  });

  test('the order of the two mixins makes no difference', () async {
    final session = Reversed(const SignedOut());
    final order = <String>[];
    final flutterErrors = <Object>[];
    final zoneErrors = <Object>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => flutterErrors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);

    session.addListener(() {
      order.add('listener');
      throw StateError('the listener');
    });
    final body = Completer<void>();
    late Future<void> loop;
    runZonedGuarded(
      () {
        session.stream.listen((_) {
          order.add('stream');
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

    expect(order, ['listener', 'stream']);
    expect(flutterErrors.map((error) => '$error'), ['Bad state: the listener']);
    expect(zoneErrors.map((error) => '$error'), ['Bad state: the subscriber']);

    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, isFalse);
    expect(session.pending, isA<SoloPendingStream>());
    body.complete();
    await closing;
    await loop;
  });

  test('a plain SoloListenable closes without waiting for its listeners',
      () async {
    final session = PlainSession(const SignedOut())..addListener(() {});
    await session.signIn('Ada').done;

    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isTrue);
    await closing;
  });

  testWidgets('the listener is inside the change, the event a turn later',
      (tester) async {
    final session = Session(const SignedOut());
    addTearDown(session.close);
    final order = <String>[];
    final subscription = session.stream.listen(
      (state) => order.add('stream'),
    );
    addTearDown(subscription.cancel);
    session.addListener(() => order.add('listener'));

    await tester.pumpWidget(
      wrap(
        ValueListenableBuilder<SessionState>(
          valueListenable: session,
          builder: (context, state, _) => Text(
            switch (state) {
              SignedIn(:final name) => 'signed in as $name',
              SignedOut() => 'signed out',
            },
          ),
        ),
      ),
    );

    await session.signIn('Ada').done;
    await tester.pumpAndSettle();

    expect(
      order,
      ['listener', 'stream'],
      reason: 'the listener runs inside the change itself and the stream '
          'event arrives after it, which is what the section says the '
          'combination costs',
    );
    expect(onScreen(tester), 'signed in as Ada');
    show(tester, 'both deliveries, ${order.join(' then ')}');
  });
}
''',
])

# ------------------------------------------------------ a screen on the stream
FILES['stream_screen_test'] = '\n'.join([
    "import 'dart:async';",
    '',
    "import 'package:flutter/material.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    _session,
    snips['a-screen-built-on-the-stream/SessionBadge'],
    wrap('withInitialData',
         snips['a-screen-built-on-the-stream/streambuilder-sessionstate']),
    wrap('overTheController',
         snips['a-screen-built-on-the-stream/solobuilder-sessionstate']),
    WRAP,
    '''
/// The second attempt with the key the page names in prose.
Widget withInitialDataAndKey(Session session) => StreamBuilder<SessionState>(
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
Widget overTheListenable(Session session) =>
    ValueListenableBuilder<SessionState>(
      valueListenable: session,
      builder: (context, state, _) => Text(
        switch (state) {
          SignedIn(:final name) => 'signed in as $name',
          SignedOut() => 'signed out',
        },
      ),
    );

Future<Session> signedIn([String name = 'Ada']) async {
  final session = Session(const SignedOut());
  await session.signIn(name).done;

  return session;
}

String badge(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data!)
    .singleWhere(
      (text) => text.startsWith('signed') || text == 'nothing yet',
    );

void main() {
  testWidgets('the first attempt shows what it was told', (tester) async {
    final session = await signedIn();
    addTearDown(session.close);

    await tester.pumpWidget(wrap(SessionBadge(session)));
    show(tester, 'mounted over a session signed in as Ada');
    expect(
      onScreen(tester),
      'nothing yet',
      reason: 'a broadcast stream replays nothing, so the badge has no '
          'state to show until the next change',
    );

    await session.signIn('Bob').done;
    await tester.pump();
    show(tester, 'after Bob signs in');
    expect(onScreen(tester), 'signed in as Bob');
  });

  testWidgets('and closing makes the wait endless', (tester) async {
    final session = await signedIn();

    await tester.pumpWidget(wrap(SessionBadge(session)));
    show(tester, 'mounted over a session signed in as Ada');

    await session.close();
    await tester.pump();
    show(tester, 'after close()');
    expect(
      onScreen(tester),
      'nothing yet',
      reason: 'the stream is done, and no event is ever coming',
    );
    expect(
      session.currentState,
      isA<SignedIn>(),
      reason: 'the state the screen never showed is right here',
    );
  });

  testWidgets('a pushed route and a tab switched back build it anew',
      (tester) async {
    final session = await signedIn();
    addTearDown(session.close);
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
      badge(tester),
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
    expect(
      tester.widget<Text>(find.byType(Text).last).data,
      'nothing yet',
      reason: 'a route pushed builds the badge anew',
    );

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
              children: [
                SessionBadge(session),
                const Text('another tab'),
              ],
            ),
          ),
        ),
      ),
    );
    await session.signIn('Cy').done;
    await tester.pump();
    expect(badge(tester), 'signed in as Cy');

    await tester.tap(find.text('other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('badge'));
    await tester.pumpAndSettle();
    expect(
      badge(tester),
      'nothing yet',
      reason: 'a tab switched away and back builds the badge anew',
    );
  });

  testWidgets('initialData opens with the state, and only once',
      (tester) async {
    final session = await signedIn();
    addTearDown(session.close);
    final other = await signedIn('Cy');
    addTearDown(other.close);

    await tester.pumpWidget(wrap(withInitialData(session)));
    show(tester, 'mounted over a session signed in as Ada');
    expect(onScreen(tester), 'signed in as Ada');

    await session.signIn('Bob').done;
    await tester.pump();
    show(tester, 'after Bob signs in');
    expect(onScreen(tester), 'signed in as Bob');

    await tester.pumpWidget(wrap(withInitialData(other)));
    show(tester, 'handed another session, signed in as Cy');
    expect(
      onScreen(tester),
      'signed in as Bob',
      reason: 'a new stream is subscribed to with the data of the old one, '
          'and initialData is not read again',
    );

    await other.signIn('Dan').done;
    await tester.pump();
    expect(
      onScreen(tester),
      'signed in as Dan',
      reason: 'the badge catches up when the new session changes',
    );
  });

  testWidgets('a key made of the session repairs the second attempt',
      (tester) async {
    final session = await signedIn();
    addTearDown(session.close);
    final other = await signedIn('Cy');
    addTearDown(other.close);

    await tester.pumpWidget(wrap(withInitialDataAndKey(session)));
    await session.signIn('Bob').done;
    await tester.pump();
    expect(onScreen(tester), 'signed in as Bob');

    await tester.pumpWidget(wrap(withInitialDataAndKey(other)));
    expect(
      onScreen(tester),
      'signed in as Cy',
      reason: 'built anew for another session, the StreamBuilder reads '
          'initialData again',
    );
  });

  testWidgets('a builder over the controller needs nothing passed',
      (tester) async {
    final session = await signedIn();
    addTearDown(session.close);

    await tester.pumpWidget(wrap(overTheController(session)));
    show(tester, 'mounted over a session signed in as Ada');
    expect(onScreen(tester), 'signed in as Ada');

    await session.signIn('Bob').done;
    await tester.pump();
    show(tester, 'after Bob signs in');
    expect(onScreen(tester), 'signed in as Bob');

    final other = await signedIn('Cy');
    addTearDown(other.close);
    await tester.pumpWidget(wrap(overTheController(other)));
    show(tester, 'handed another session, signed in as Cy');
    expect(onScreen(tester), 'signed in as Cy');

    await other.signIn('Dan').done;
    await tester.pump();
    expect(
      onScreen(tester),
      'signed in as Dan',
      reason: 'the builder listens to the session it was handed',
    );
  });

  testWidgets('ValueListenableBuilder shows the same three lines',
      (tester) async {
    final session = await signedIn();
    addTearDown(session.close);
    final other = await signedIn('Cy');
    addTearDown(other.close);
    final lines = <String>[];

    await tester.pumpWidget(wrap(overTheListenable(session)));
    lines.add(onScreen(tester));
    await session.signIn('Bob').done;
    await tester.pump();
    lines.add(onScreen(tester));
    await tester.pumpWidget(wrap(overTheListenable(other)));
    lines.add(onScreen(tester));

    expect(
      lines,
      ['signed in as Ada', 'signed in as Bob', 'signed in as Cy'],
    );
  });
}
''',
])

# ------------------------------------------------- a base class without Flutter
# The page names `AppLog` as the app's own log and shows no more of it: this
# one keeps what it was handed, for the driver to print. It is a library of
# its own that imports nothing, so a base that reports to it stays without
# Flutter.
FILES['app_log'] = """// The page calls `AppLog.error` statically, so the fake is all statics.
// ignore: avoid_classes_with_only_static_members
abstract final class AppLog {
  static final errors = <Object>[];

  static void error(Object error, StackTrace stackTrace) => errors.add(error);
}
"""

# A block of this section shows two libraries, the package without Flutter
# and the app, and they are built as two. Until 2026-10-04 both stood in one
# test file under `package:flutter/foundation.dart`: the base the page calls
# free of Flutter was never built without it, and nothing held the page to
# where its `@protected` comes from.
APP = '// The app.\n'


def without_flutter(block):
    """(the library of the package without Flutter, the code of the app)."""
    package, app = block.split(APP)
    imports, body = split_imports(package)
    assert imports and not any('flutter' in line for line in imports), imports
    return (
        '\n'.join([*imports, '', "import 'app_log.dart';", '', body]),
        APP + app,
    )


# Every version is driven the same way: a listener of a controller throws on
# a change, and the driver prints what reached `AppLog` and `FlutterError`.
# `ProfileController` has no operation of its own, so a subclass in the
# same library changes the state.
BASE_DRIVER = """
final class DrivenProfile extends ProfileController {
  void set(Profile state) => externalSetState(state);
}

String said(Iterable<Object> errors) =>
    errors.isEmpty ? 'nothing' : errors.join(', ');

/// What a failure of a listener of [profile] reaches: (AppLog, FlutterError).
Future<(List<Object>, List<Object>)> failListener(
  Solo<Profile> profile,
  void Function(Profile state) set,
) async {
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
  return ([...AppLog.errors], reports);
}

void show((List<Object>, List<Object>) reached) {
  debugPrint('AppLog: ${said(reached.$1)}');
  debugPrint('FlutterError: ${said(reached.$2)}');
}
"""

# The app of the page shows no import. `package:flutter/foundation.dart` is
# where the page says the app takes `@protected` from, and two of the three
# drivers import nothing else of Flutter.
BASE_IMPORTS = [
    "import 'package:flutter/foundation.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    "import 'app_log.dart';",
]

FILES['base_first'], _first_app = without_flutter(
    base['the-first-attempt/AppController'])

FILES['base_first_attempt_test'] = '\n'.join([
    *BASE_IMPORTS,
    "import 'base_first.dart';",
    '',
    PROFILE_STATES,
    _first_app,
    BASE_DRIVER,
    """
/// The leaf the section says `super` does not help: `super` is the mixin.
final class SuperProfile extends AppController<Profile> with SoloListenable {
  SuperProfile() : super(Empty());

  void set(Profile state) => externalSetState(state);

  @protected
  @override
  // What the page says the analyzer calls this, and why it is right.
  // ignore: unnecessary_overrides
  void onListenerError(Object error, StackTrace stackTrace) =>
      super.onListenerError(error, stackTrace);
}

/// A controller of the same base that mixes nothing in.
final class PlainProfile extends AppController<Profile> {
  PlainProfile() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

void main() {
  test('the mixin on the leaf reports over the base', () async {
    final profile = DrivenProfile();
    final reached = await failListener(profile, profile.set);
    show(reached);
    expect(reached.$1, isEmpty, reason: 'the base never runs');
    expect(reached.$2.single, isA<StateError>());
  });

  test('the override of the base runs where nothing is mixed in', () async {
    final profile = PlainProfile();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1.single, isA<StateError>());
  });

  test('super in the leaf lands in the mixin', () async {
    final profile = SuperProfile();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1, isEmpty, reason: 'the base stays out of reach');
    expect(reached.$2.single, isA<StateError>());
  });

  test('the leaf is a ValueListenable', () {
    final profile = DrivenProfile();
    addTearDown(profile.close);
    expect(profile, isA<ValueListenable<Profile>>());
    expect(profile, isA<AppController<Profile>>());
  });
}
""",
])

FILES['base_answer'], _answer_app = without_flutter(
    base['a-report-under-another-name/AppController'])

FILES['base_class_test'] = '\n'.join([
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    "import 'app_log.dart';",
    "import 'base_answer.dart';",
    '',
    PROFILE_STATES,
    _answer_app,
    BASE_DRIVER,
    """
/// A controller of the same base that mixes nothing in.
final class PlainProfile extends AppController<Profile> {
  PlainProfile() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A leaf that wants the report through FlutterError as well.
final class BothReports extends AppController<Profile> with SoloListenable {
  BothReports() : super(Empty());

  void set(Profile state) => externalSetState(state);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    reportListenerError(error, stackTrace);
    super.onListenerError(error, stackTrace);
  }
}

/// A leaf that mixes the mixin in and writes no override. The analyzer has
/// nothing to say about it, which is what the page says.
final class Forgetful extends AppController<Profile> with SoloListenable {
  Forgetful() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A leaf whose override leaves `@protected` off, and a class that inherits
/// that override: `analyzer_says.dart` calls the hook of both.
class Unprotected extends AppController<Profile> with SoloListenable {
  Unprotected() : super(Empty());

  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}

final class UnderUnprotected extends Unprotected {}

void main() {
  test('the leaf calls the report of another name', () async {
    final profile = DrivenProfile();
    final reached = await failListener(profile, profile.set);
    show(reached);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2, isEmpty);
  });

  test('the base reports for a controller that mixes nothing in', () async {
    final profile = PlainProfile();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2, isEmpty);
  });

  test('super next to it reports through FlutterError as well', () async {
    final profile = BothReports();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2.single, isA<StateError>());
  });

  test('a leaf without the override reports as in the first attempt',
      () async {
    final profile = Forgetful();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1, isEmpty, reason: 'the report of the base is not run');
    expect(reached.$2.single, isA<StateError>());
  });

  testWidgets('the leaf drives a builder', (tester) async {
    final profile = DrivenProfile();
    addTearDown(profile.close);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SoloBuilder<Profile>(
          solo: profile,
          builder: (context, state, _) => Text('${state.runtimeType}'),
        ),
      ),
    );
    expect(find.text('Empty'), findsOne);
  });
}
""",
])

# What the page says the analyzer does about `@protected`, held by the
# analyzer. Nothing runs this file: `flutter analyze` reads it, and with
# `unnecessary_ignore` on, an `// ignore:` below that the analyzer does not
# need is a finding, as is a call without one that it does not let through.
# The calls stand in a library of their own because a protected member is
# free to use in the library that declares it.
FILES['analyzer_says'] = """import 'base_class_test.dart';

void fromAnotherLibrary(
  ProfileController leaf,
  PlainProfile plain,
  Forgetful forgetful,
  Unprotected unprotected,
  UnderUnprotected under,
) {
  final error = StateError('a listener');
  // `@protected` is repeated on the override of the leaf, and the hook is
  // not a public member of it.
  // ignore: invalid_use_of_protected_member
  leaf.onListenerError(error, StackTrace.empty);
  // Nor is it one of a controller that has the override of the base alone,
  // and the report under another name is annotated the same way.
  // ignore: invalid_use_of_protected_member
  plain.onListenerError(error, StackTrace.empty);
  // ignore: invalid_use_of_protected_member
  leaf.reportListenerError(error, StackTrace.empty);
  // A leaf that writes no override has the one of the mixin, annotated too.
  // ignore: invalid_use_of_protected_member
  forgetful.onListenerError(error, StackTrace.empty);
  // Left off, the hook is a public member of that class and of every class
  // that inherits the override.
  unprotected.onListenerError(error, StackTrace.empty);
  under.onListenerError(error, StackTrace.empty);
}
"""

# The last block of the section is the app alone, over the base of the
# block above it. It quotes no trace, so the guards of the driver are all
# that holds it.
_shared = base['a-report-under-another-name/ListenableController']
assert _shared.startswith(APP), _shared

FILES['base_shared_test'] = '\n'.join([
    *BASE_IMPORTS,
    "import 'base_answer.dart';",
    '',
    PROFILE_STATES,
    _shared,
    BASE_DRIVER,
    """
/// A second leaf of the class between, with no override of its own either.
final class SettingsController extends ListenableController<Profile> {
  SettingsController() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// The mixin once more, on a leaf over the class that already has it.
final class Twice extends ListenableController<Profile> with SoloListenable {
  Twice() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

/// A base with Flutter in it, which mixes the mixin in itself.
abstract class FlutterBase<S extends Object> extends Solo<S>
    with SoloListenable {
  FlutterBase(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);
}

final class OverFlutterBase extends FlutterBase<Profile> {
  OverFlutterBase() : super(Empty());

  void set(Profile state) => externalSetState(state);
}

void main() {
  test('the override of the class between runs for its leaf', () async {
    final profile = DrivenProfile();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2, isEmpty);
    expect(profile, isA<ValueListenable<Profile>>());
  });

  test('and for every other leaf that extends it', () async {
    final settings = SettingsController();
    final reached = await failListener(settings, settings.set);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2, isEmpty);
  });

  test('a base with Flutter in it keeps its own override', () async {
    final profile = OverFlutterBase();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1.single, isA<StateError>());
    expect(reached.$2, isEmpty);
  });

  test('mixed in again on a leaf, the mixin silences that override',
      () async {
    final profile = Twice();
    final reached = await failListener(profile, profile.set);
    expect(reached.$1, isEmpty);
    expect(reached.$2.single, isA<StateError>());
  });
}
""",
])

# ------------------------------------------------- the README of flutter_solo
# Every Dart block of the package's README, built into one file. The README
# declares the model once, under Usage, and the rest of the page leans on
# it; what the page takes as the reader's own -- the API behind the
# controller, the widgets a `State` belongs to, a toast -- is supplied here,
# and nothing the page itself names is.
#
# That goes for imports too. `dart:async` is hoisted out of the block of
# "The controller's life", whose `unawaited` needs it, and the drivers below
# lean on the same line: a page that stops showing the import leaves nothing
# here to supply it, and the build fails. The import of `flutter_test` is
# the one the drivers add: the page writes a test and leaves the head of the
# test file to the reader.
#
# Two sections show a first attempt and an answer that declare the same
# members, so their blocks are addressed by the subsection they stand in.
_install_imports, _install_rest = split_imports(
    _fr['install/import-package-flutter_solo-fl'])
assert _install_rest.strip() == '', _install_rest
_usage_imports, _usage_body = split_imports(_usage)
_listening = subsections(
    open(FLUTTER_README).read(), doc_blocks.slug(
        'Listening without keeping the callback'), _taken_readme)
_leaking_imports, _leaking_body = split_imports(
    _listening[doc_blocks.slug('The first attempt') + '/initState'])
assert _leaking_imports == [], _leaking_imports
_listening_imports, _listening_body = split_imports(
    _listening[doc_blocks.slug('A subscription that keeps the callback')
               + '/initState'])
_second_imports, _second_body = split_imports(
    _fr['methods-from-a-second-import/import-package-flutter_solo-fl'])
_life_imports, _life_body = split_imports(
    _fr['the-controller-s-life/_ProfileScreenState'])
assert _life_imports == ["import 'dart:async';"], _life_imports

FILES['readme_test'] = '\n'.join([
    *sorted(set(
        _install_imports + _usage_imports + _listening_imports
        + _second_imports + _life_imports + [
            "import 'package:flutter_test/flutter_test.dart';",
        ])),
    '',
    _usage_body,
    '''
/// The API the README takes as the application's own: it answers ten
/// milliseconds after the call.
class ProfileApi {
  final saved = <String>[];

  Future<String> fetchName() => Future<String>.delayed(
        const Duration(milliseconds: 10),
        () => 'Ada Lovelace',
      );

  Future<void> saveName(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    saved.add(name);
  }
}

/// The fake of the testing section: "it answers with the name ten
/// milliseconds after the call".
class FakeApi extends ProfileApi {}

/// The same API with nobody at the other end.
class FailingApi extends ProfileApi {
  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('no network');
  }
}
''',
    # Why: the fragment is the body of a function that has a controller.
    'Future<void> why(ProfileController controller) async {\n'
    + _fr['why/final-job-controller-load'] + '}\n',
    wrap('saveSelector', _fr['selecting-one-value/soloselector-profile-bool'],
         'ProfileController controller'),
    '''
class SaveButton extends StatefulWidget {
  final ProfileController controller;

  const SaveButton({required this.controller, super.key});

  @override
  State<SaveButton> createState() => _SaveButtonState();
}
''',
    _fr['selecting-one-value/_SaveButtonState'],
    wrap('anyBuilder', _fr['builders-for-any-controller/solobuilder-profile'],
         'Solo<Profile> controller'),
    '''
/// The first attempt of the section on listening.
class Leaking extends StatefulWidget {
  final ProfileController controller;
  final List<String> heard;

  const Leaking({required this.controller, required this.heard, super.key});

  @override
  State<Leaking> createState() => _LeakingState();
}

class _LeakingState extends State<Leaking> {''',
    _leaking_body,
    '''
  void _onState(Profile state) =>
      widget.heard.add('state ${state.runtimeType}');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class Listening extends StatefulWidget {
  final ProfileController controller;
  final List<String> heard;

  const Listening({required this.controller, required this.heard, super.key});

  @override
  State<Listening> createState() => _ListeningState();
}

class _ListeningState extends State<Listening> {
  late final canSave =
      SoloSelection(widget.controller, (state) => state.canSave);
''',
    _listening_body,
    '''
  void _onState(Profile state) =>
      widget.heard.add('state ${state.runtimeType}');

  void _onCanSave(bool canSave) => widget.heard.add('canSave $canSave');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

final _heardBySecondImport = <bool>[];

void _onCanSave(bool canSave) => _heardBySecondImport.add(canSave);

(SoloSelection<Profile, bool>, SoloSubscription) secondImport(
  ProfileController controller,
) {''',
    _second_body,
    '''  return (canSave, subscription);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}
''',
    _life_body,
    '''
class LoadButton extends StatefulWidget {
  final ProfileController controller;
  final List<String> toasts;

  const LoadButton({
    required this.controller,
    required this.toasts,
    super.key,
  });

  @override
  State<LoadButton> createState() => _LoadButtonState();
}

class _LoadButtonState extends State<LoadButton> {
  ProfileController get controller => widget.controller;

  void _toast(String message) => widget.toasts.add(message);
''',
    _fr['outcomes/_load'],
    '''
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: _load, child: const Text('Load'));
}

/// The two lines of the first attempt of the testing section.
Future<void> firstAttempt(
  WidgetTester tester,
  ProfileController controller,
) async {''',
    _fr['testing/await-controller-load-done'],
    '''}

/// The three lines of the handle.
Future<Outcome<String>> theHandle(
  WidgetTester tester,
  ProfileController controller,
) async {''',
    _fr['testing/final-done-controller-load-don'],
    '''  return outcome;
}

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

VoidCallback? pressable(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed;

/// Closes [controller] once the test is over, without waiting for it.
///
/// A tear-down runs after the fake clock has stopped, and a `close()`
/// awaited there with a job still running never comes back: a driver that
/// went red halfway through a load would stand until its timeout and take
/// the next one with it, instead of saying what failed.
void closing(Solo<Object> controller) =>
    addTearDown(() => unawaited(controller.close()));

Future<ProfileController> loaded(WidgetTester tester) async {
  final controller = ProfileController(ProfileApi());
  closing(controller);
  controller.load().ignoreFailure();
  await tester.pump(const Duration(milliseconds: 20));

  return controller;
}

void main() {
  testWidgets('a handle stops the job it stands for', (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    final printed = <String>[];
    await runZoned(
      () => why(controller),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );

    expect(
      printed,
      ['Cancelled(manual)'],
      reason: 'the comment the Why section prints next to the call',
    );
    debugPrint('the handle: ${printed.single}');
  });

  testWidgets('the first attempt stands until the clock moves',
      (tester) async {
    final controller = ProfileController(FakeApi());
    closing(controller);
    await tester.pumpWidget(
      MaterialApp(home: ProfileView(controller: controller)),
    );

    var through = false;
    unawaited(firstAttempt(tester, controller).then((_) => through = true));
    await tester.pump();
    await tester.pump();
    await tester.idle();
    expect(
      through,
      isFalse,
      reason: 'nothing has moved the clock, and the fake waits on a timer',
    );

    // The clock is moved without a pump: the attempt pumps a frame of its
    // own as it comes through, and the tester takes one call at a time.
    await tester.binding.delayed(const Duration(milliseconds: 10));
    await tester.idle();
    expect(through, isTrue);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    debugPrint('the first attempt: stands until the test moves the clock');
  });
''',
    _fr['testing/testwidgets-the-profile-appear'],
    '''
  testWidgets('the handle waits for the end of the work', (tester) async {
    final controller = ProfileController(FakeApi());
    closing(controller);
    await tester.pumpWidget(
      MaterialApp(home: ProfileView(controller: controller)),
    );

    final outcome = await theHandle(tester, controller);

    expect(outcome, isA<Done<String>>());
    expect(
      find.text('Ada Lovelace'),
      findsOneWidget,
      reason: 'the pump moves the clock and then draws',
    );
  });

  testWidgets('read before the clock moves, a failed load is an outcome',
      (tester) async {
    final controller = ProfileController(FailingApi());
    closing(controller);
    await tester.pumpWidget(
      MaterialApp(home: ProfileView(controller: controller)),
    );

    final outcome = await theHandle(tester, controller);

    expect(
      outcome,
      isA<Failed>(),
      reason: 'done was asked for before the job ended, so the failure '
          'belongs to the test that reads it and not to the zone',
    );
    expect(find.text('Load'), findsOneWidget);
    debugPrint('the handle: $outcome');
  });

  testWidgets('save starts on a loaded profile and nowhere else',
      (tester) async {
    final api = ProfileApi();
    final controller = ProfileController(api);
    closing(controller);

    final early = controller.save();
    await tester.pump(const Duration(milliseconds: 20));
    expect(early.outcome, isA<Cancelled>(), reason: 'Empty is no Loaded');
    expect(api.saved, isEmpty);

    controller.load().ignoreFailure();
    await tester.pump(const Duration(milliseconds: 20));
    final save = controller.save();
    await tester.pump(const Duration(milliseconds: 20));
    expect(save.outcome, isA<Done<void>>());
    expect(api.saved, ['Ada Lovelace']);
    debugPrint('save: refused on ${early.outcome}, then saved');
  });

  testWidgets('the selector lets Save be pressed once there is a profile',
      (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    await tester.pumpWidget(app(saveSelector(controller)));
    expect(pressable(tester), isNull);

    controller.load().ignoreFailure();
    await tester.pumpAndSettle();
    expect(pressable(tester), isNotNull);
  });

  testWidgets('the selection in a field follows a new controller',
      (tester) async {
    final first = await loaded(tester);
    final second = ProfileController(ProfileApi());
    closing(second);

    await tester.pumpWidget(app(SaveButton(controller: first)));
    expect(pressable(tester), isNotNull);

    await tester.pumpWidget(app(SaveButton(controller: second)));
    expect(
      pressable(tester),
      isNull,
      reason: 'the new controller has nothing to save; a selection left on '
          'the old one would say otherwise and send its tap to the new one',
    );
    debugPrint('the field: follows the controller it is handed');
  });

  testWidgets('the builder takes the controller itself', (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    await tester.pumpWidget(app(anyBuilder(controller)));
    expect(find.text('no profile'), findsOne);

    controller.load().ignoreFailure();
    await tester.pump();
    await tester.pump();
    expect(find.text('loading'), findsOne);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Ada Lovelace'), findsOne);
  });

  testWidgets('a closure handed to removeListener again removes nothing',
      (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    final heard = <String>[];
    await tester.pumpWidget(Leaking(controller: controller, heard: heard));
    await tester.pumpWidget(const SizedBox());

    controller.load().ignoreFailure();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      heard,
      ['state Loading', 'state Loaded'],
      reason: 'the first attempt: its State is gone and its closure is still '
          'called',
    );
    debugPrint('the first attempt: heard $heard after dispose()');
  });

  testWidgets('a group of subscriptions goes with the State', (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    final heard = <String>[];
    await tester.pumpWidget(Listening(controller: controller, heard: heard));

    controller.load().ignoreFailure();
    await tester.pumpAndSettle();
    expect(heard, ['state Loading', 'state Loaded', 'canSave true']);

    await tester.pumpWidget(const SizedBox());
    controller.load().ignoreFailure();
    await tester.pumpAndSettle();
    expect(
      heard,
      hasLength(3),
      reason: 'dispose cancelled the group, so nothing is heard after it',
    );
  });

  testWidgets('the second import brings select and listen', (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    final (canSave, subscription) = secondImport(controller);

    controller.load().ignoreFailure();
    await tester.pumpAndSettle();
    expect(canSave.value, isTrue);
    expect(_heardBySecondImport, [true]);
    subscription.cancel();
  });

  testWidgets('the screen owns its controller and closes it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    final controller = tester
        .state<_ProfileScreenState>(find.byType(ProfileScreen))
        .controller;
    await tester.pumpAndSettle();
    expect(find.text('Ada Lovelace'), findsOne);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(controller.isClosed, isTrue);
  });

  testWidgets('the outcome of a tap is what the toast says', (tester) async {
    final controller = ProfileController(ProfileApi());
    closing(controller);
    final toasts = <String>[];
    await tester.pumpWidget(
      app(LoadButton(controller: controller, toasts: toasts)),
    );

    await tester.tap(find.text('Load'));
    await tester.pump();
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(
      toasts,
      ['hello Ada Lovelace', 'hello Ada Lovelace'],
      reason: 'droppable hands the second tap the first job, so both taps '
          'wait for the same outcome',
    );
    debugPrint('the outcome: ${toasts.join(', ')}');
  });

  testWidgets('a failed load is what the toast says too', (tester) async {
    final controller = ProfileController(FailingApi());
    closing(controller);
    final toasts = <String>[];
    await tester.pumpWidget(
      app(LoadButton(controller: controller, toasts: toasts)),
    );

    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(toasts, ['Bad state: no network']);
  });

  testWidgets('a closed controller leaves nothing to say', (tester) async {
    final controller = ProfileController(ProfileApi());
    final toasts = <String>[];
    await tester.pumpWidget(
      app(LoadButton(controller: controller, toasts: toasts)),
    );

    await tester.tap(find.text('Load'));
    await tester.pump();
    await controller.close();
    await tester.pumpAndSettle();
    expect(
      toasts,
      isEmpty,
      reason: 'the job ends Cancelled, and that branch says nothing',
    );
  });
}
''',
])

# A block of either page that no driver took is a block nobody builds: it
# could stop compiling, or stop being true, and every step after this one
# would stay green.
for _path, _taken in ((DOC, _taken_doc), (FLUTTER_README, _taken_readme)):
    _left = [
        block for block in re.findall(
            r'```dart\n(.*?)```', open(_path).read(), re.S)
        if block not in _taken
    ]
    if _left:
        sys.exit(
            f'{_path}: {len(_left)} dart block(s) that no driver takes, '
            'the first of them beginning\n    '
            + _left[0].split('\n')[0])

for key, body in FILES.items():
    directory = f'{ROOT}/flutter_check/test/v'
    os.makedirs(directory, exist_ok=True)
    open(f'{directory}/{key}.dart', 'w').write(body)

open(f'{ROOT}/flutter_check/pubspec.yaml', 'w').write(PUBSPEC)
shutil.copyfile(
    os.path.join(REPO, 'packages', 'flutter_solo', 'analysis_options.yaml'),
    f'{ROOT}/flutter_check/flutter_rules.yaml',
)
open(f'{ROOT}/flutter_check/analysis_options.yaml', 'w').write(OPTIONS)
print('wrote', len(FILES), 'files under', ROOT)
