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
imports is byte-identical to the document.

Every Dart block of the README of flutter_solo is built, but the lone
import line under Install, which Usage repeats -- the first page a user
of the package copies from. That README went without a bench until
2026-09-19 and did not compile: the model it declared had neither the
`canSave` nor the `save` the rest of the page used. doc/mixins.md takes
the model of that README, the states of `Profile`, and is built against
them.

The quick start of solo's README is built here as well. It is pure Dart
and belongs to no widget, but no other bench builds it, and a Dart file
compiles in a Flutter package the same as anywhere -- with its import of
`solo` read as one of flutter_solo, which re-exports it.

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
    open(DOC).read(), 'dart', doc_blocks.DECLARES['dart'])
readme = doc_blocks.blocks(
    open(README).read(), 'dart', doc_blocks.DECLARES['dart'])
_fr = doc_blocks.blocks(
    open(FLUTTER_README).read(), 'dart', doc_blocks.DECLARES['dart'])


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
    "import 'package:flutter/foundation.dart';",
    "import 'package:flutter/widgets.dart';",
    "import 'package:flutter_solo/flutter_solo.dart';",
    "import 'package:flutter_test/flutter_test.dart';",
    '',
    PROFILE_STATES,
    _base_body,
    WRAP,
    '''
void main() {
  testWidgets('the leaf is a ValueListenable, the base is not',
      (tester) async {
    final profile = ProfileController();
    addTearDown(profile.close);

    expect(profile, isA<ValueListenable<Profile>>());
    expect(profile, isA<AppController<Profile>>());

    await tester.pumpWidget(
      wrap(
        SoloBuilder<Profile>(
          solo: profile,
          builder: (context, state, _) => Text('${state.runtimeType}'),
        ),
      ),
    );
    expect(onScreen(tester), 'Empty');
    show(tester, 'the base class, through a leaf that is listenable');
  });
}
''',
])

# ------------------------------------------------- the README of flutter_solo
# Every Dart block of the package's README but the import line under
# Install, which Usage repeats, built into one file. The README
# declares the model once, under Usage, and the rest of the page leans on
# it; what the page takes as the reader's own -- the API behind the
# controller, the widgets a `State` belongs to, a toast -- is supplied here,
# and nothing the page itself names is.
_usage_imports, _usage_body = split_imports(_usage)
_listening_imports, _listening_body = split_imports(
    _fr['listening-without-keeping-the-/initState'])
_second_imports, _second_body = split_imports(
    _fr['methods-from-a-second-import/import-package-flutter_solo-fl'])

FILES['readme_test'] = '\n'.join([
    *sorted(set(_usage_imports + _listening_imports + _second_imports + [
        "import 'dart:async';",
        "import 'package:flutter_test/flutter_test.dart';",
    ])),
    '',
    _usage_body,
    '''
/// The API the README takes as the application's own.
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

/// The API of the testing section, standing in for the real one.
class FakeApi extends ProfileApi {}
''',
    # Why: the fragment is the body of a function that has a controller.
    'Future<void> why(ProfileController profile) async {\n'
    + _fr['why/final-job-profile-load'] + '}\n',
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
  void _onState() =>
      widget.heard.add('state ${widget.controller.value.runtimeType}');

  void _onCanSave() => widget.heard.add('canSave ${canSave.value}');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

var _heardBySecondImport = 0;

void _onCanSave() => _heardBySecondImport++;

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
    _fr['the-controller-s-life/_ProfileScreenState'],
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

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

VoidCallback? pressable(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed;

Future<ProfileController> loaded(WidgetTester tester) async {
  final controller = ProfileController(ProfileApi());
  addTearDown(controller.close);
  controller.load().ignore();
  await tester.pump(const Duration(milliseconds: 20));

  return controller;
}

void main() {
  testWidgets('a handle stops the job it stands for', (tester) async {
    final profile = ProfileController(ProfileApi());
    addTearDown(profile.close);
    final printed = <String>[];
    await runZoned(
      () => why(profile),
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
''',
    _fr['testing/testwidgets-the-profile-appear'],
    '''
  testWidgets('the handle waits for the end of the work', (tester) async {
    final controller = ProfileController(FakeApi());
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(home: ProfileView(controller: controller)),
    );
''',
    _fr['testing/final-job-controller-load'],
    '''
    expect(job.outcome, isA<Done<String>>());
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('save starts on a loaded profile and nowhere else',
      (tester) async {
    final api = ProfileApi();
    final controller = ProfileController(api);
    addTearDown(controller.close);

    final early = controller.save();
    await tester.pump(const Duration(milliseconds: 20));
    expect(early.outcome, isA<Cancelled>(), reason: 'Empty is no Loaded');
    expect(api.saved, isEmpty);

    controller.load().ignore();
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
    addTearDown(controller.close);
    await tester.pumpWidget(app(saveSelector(controller)));
    expect(pressable(tester), isNull);

    controller.load().ignore();
    await tester.pumpAndSettle();
    expect(pressable(tester), isNotNull);
  });

  testWidgets('the selection in a field follows a new controller',
      (tester) async {
    final first = await loaded(tester);
    final second = ProfileController(ProfileApi());
    addTearDown(second.close);

    await tester.pumpWidget(app(SaveButton(controller: first)));
    expect(pressable(tester), isNotNull);

    await tester.pumpWidget(app(SaveButton(controller: second)));
    expect(
      pressable(tester),
      isNull,
      reason: 'the new controller has nothing to save; a selection left on '
          'the old one would say otherwise and save to the new one',
    );
    debugPrint('the field: follows the controller it is handed');
  });

  testWidgets('the builder takes the controller itself', (tester) async {
    final controller = ProfileController(ProfileApi());
    addTearDown(controller.close);
    await tester.pumpWidget(app(anyBuilder(controller)));
    expect(find.textContaining('Empty'), findsOne);

    controller.load().ignore();
    await tester.pumpAndSettle();
    expect(find.textContaining('Loaded'), findsOne);
  });

  testWidgets('a group of subscriptions goes with the State', (tester) async {
    final controller = ProfileController(ProfileApi());
    addTearDown(controller.close);
    final heard = <String>[];
    await tester.pumpWidget(Listening(controller: controller, heard: heard));

    controller.load().ignore();
    await tester.pumpAndSettle();
    expect(heard, ['state Loading', 'state Loaded', 'canSave true']);

    await tester.pumpWidget(const SizedBox());
    controller.load().ignore();
    await tester.pumpAndSettle();
    expect(
      heard,
      hasLength(3),
      reason: 'dispose cancelled the group, so nothing is heard after it',
    );
  });

  testWidgets('the second import brings select and listen', (tester) async {
    final controller = ProfileController(ProfileApi());
    addTearDown(controller.close);
    final (canSave, subscription) = secondImport(controller);

    controller.load().ignore();
    await tester.pumpAndSettle();
    expect(canSave.value, isTrue);
    expect(_heardBySecondImport, 1);
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
    addTearDown(controller.close);
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
