#!/usr/bin/env python3
"""Builds runnable screens from packages/solo/doc/flutter.md.

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

Two liberties are taken with the snippets, and they are the only ones.
Import lines are hoisted to the head of the driver, verbatim, because a
file takes its directives before its declarations. And the controller of
the opening section carries a comment where its jobs belong -- `// ...the
jobs from the quick start...` -- which is replaced here by that very
method, taken out of packages/solo/README.md. Everything between the
imports is byte-identical to the document.

So this bench guards two documents at once: the README's quick start is
built here as well, as the code flutter.md points at rather than a copy
of it.

What the drivers print is quoted by the document in `text` blocks, and
`tool/check_traces.py` holds the two together. The guards in them are
what makes a broken document red rather than merely quiet: a driver that
only printed would pass with an empty screen.
"""
import os
import shutil
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/solo-flutter-check'
DOC = os.path.join(REPO, 'packages', 'solo', 'doc', 'flutter.md')
README = os.path.join(REPO, 'packages', 'solo', 'README.md')

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
OPTIONS = """include: flutter_rules.yaml

linter:
  rules:
    avoid_print: false
    public_member_api_docs: false
    unreachable_from_main: false
"""

snips = doc_blocks.blocks(
    # A synthetic heading for the part of the page above its first `##`:
    # sections are keyed by the heading they sit under, and the opening
    # tour of this document sits under none.
    'x\n## quick start\n' + open(DOC).read(),
    'dart',
    doc_blocks.DECLARES['dart'],
)
readme = doc_blocks.blocks(
    open(README).read(), 'dart', doc_blocks.DECLARES['dart'])


def split_imports(block):
    """(import lines, the rest of the block)."""
    lines = block.split('\n')
    imports = [line for line in lines if line.startswith('import ')]
    rest = '\n'.join(line for line in lines if not line.startswith('import '))
    return imports, rest.strip('\n') + '\n'


def wrap(name, block, parameter='Session session'):
    """A widget expression from the document, as a function that returns it."""
    return f'Widget {name}({parameter}) =>\n    {block.strip()};\n'


# The quick start's states and API client, and the load job the opening
# controller of flutter.md leaves as a comment.
STATES = readme['quick-start/ProfileState']
_api_block = readme['quick-start/ProfileApi']
_head, _, _tail = _api_block.partition('final class ProfileController')
API = _head.strip('\n') + '\n'
LOAD = _tail[_tail.index('  Job<String> load()'):].rsplit('}', 1)[0].rstrip()

PROFILE_PAGE = """
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const Text('profile page');
}
"""

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

# --------------------------------------------------------------- the screen
_controller = snips['quick-start/ProfileController'].replace(
    '  // ...the jobs from the quick start...', LOAD)
_controller_imports, _controller_body = split_imports(_controller)
_screen_imports, _screen_body = split_imports(snips['quick-start/ProfileScreen'])

FILES['screen_test'] = '\n'.join([
    *sorted(set(_controller_imports + _screen_imports
                + ["import 'package:flutter_test/flutter_test.dart';"])),
    '',
    STATES.split("import 'package:solo/solo.dart';")[-1].strip('\n'),
    '',
    API,
    _controller_body,
    PROFILE_PAGE,
    _screen_body,
    # The selector of the same section, which the document shows as the
    # body of a build method: `profile` is the screen's controller and
    # `_open` its method, so the wrapper supplies both. A variable rather
    # than a function, because a tear-off of a top-level function would
    # make the button const and the document's is not.
    'void Function()? _open;',
    WRAP,
    wrap('selector', snips['quick-start/soloselectbuilder-profilestate'],
         'ProfileController profile'),
    '''
void main() {
  testWidgets('the screen loads, then navigates', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    expect(find.text('Open profile'), findsOne);

    await tester.tap(find.text('Open profile'));
    await tester.pump();
    expect(
      find.byType(CircularProgressIndicator),
      findsOne,
      reason: 'the state is Loading while the API is answering',
    );

    await tester.pumpAndSettle();
    expect(
      find.text('profile page'),
      findsOne,
      reason: 'the outcome of the job is what navigates, not the state',
    );
    debugPrint('the screen: load, then the profile page');
  });

  testWidgets('the selector rebuilds on the value it picks', (tester) async {
    final profile = ProfileController(ProfileApi());
    addTearDown(profile.close);

    await tester.pumpWidget(wrap(selector(profile)));
    expect(find.text('Open profile'), findsOne);

    profile.load();
    // The first pump lets the job start and emit Loading; the frame that
    // shows it is the next one.
    await tester.pump();
    await tester.pump();
    expect(
      find.byType(CircularProgressIndicator),
      findsOne,
      reason: 'Loading is what the picking function turns into true',
    );
    debugPrint('the selector: button, then spinner');

    await tester.pumpAndSettle();
  });
}
''',
])

# ---------------------------------------------------------- both deliveries
_session = snips['a-controller-with-both-deliver/Session']

FILES['deliveries_test'] = '\n'.join([
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    _session,
    WRAP,
    '''
void main() {
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
    "import 'package:flutter/widgets.dart';",
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
Future<Session> signedIn() async {
  final session = Session(const SignedOut());
  await session.signIn('Ada').done;

  return session;
}

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

  testWidgets('and closing takes the last state away', (tester) async {
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

  testWidgets('initialData closes the gap', (tester) async {
    final session = await signedIn();
    addTearDown(session.close);

    await tester.pumpWidget(wrap(withInitialData(session)));
    show(tester, 'mounted over a session signed in as Ada');
    expect(onScreen(tester), 'signed in as Ada');

    await session.signIn('Bob').done;
    await tester.pump();
    show(tester, 'after Bob signs in');
    expect(onScreen(tester), 'signed in as Bob');
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
  });
}
''',
])

# ------------------------------------------------- a base class without Flutter
_base_imports, _base_body = split_imports(
    snips['a-base-class-without-flutter/AppController'])

FILES['base_class_test'] = '\n'.join([
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    STATES.split("import 'package:solo/solo.dart';")[-1].strip('\n'),
    '',
    _base_body,
    WRAP,
    '''
void main() {
  testWidgets('the leaf is a ValueListenable, the base is not',
      (tester) async {
    final profile = ProfileController();
    addTearDown(profile.close);

    expect(profile, isA<ValueListenable<ProfileState>>());
    expect(profile, isA<AppController<ProfileState>>());

    await tester.pumpWidget(
      wrap(
        SoloBuilder<ProfileState>(
          solo: profile,
          builder: (context, state, _) => Text('${state.runtimeType}'),
        ),
      ),
    );
    expect(onScreen(tester), 'Initial');
    show(tester, 'the base class, through a leaf that is listenable');
  });
}
''',
])

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
