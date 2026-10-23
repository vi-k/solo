import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'support/readme_profile.dart' hide ProfileApi;
import 'support/readme_profile.dart' as profile show ProfileApi;
import 'support/readme_scopo.dart';

/// The sentinel of the two blocks of `README.md` that take scopo, in
/// "The controller's life".
///
/// Their code stands verbatim in `support/readme_scopo.dart`, and
/// `readme_rakes_test.dart` holds the page to that file. The tests run here,
/// apart from the rest of the page: scopo is a dev dependency built against a
/// released `async_job`, and a change it does not build against fails the
/// loading of this file alone. Up to scopo 0.18.0 the two could not share a
/// library either: its main import declared a `listen` on `Listenable`, as
/// the second import of this package does.

const _doc = 'README.md';

/// The page without its code, every run of whitespace turned into one
/// space, so that a phrase is found wherever its lines were broken.
String _prose() => File(_doc)
    .readAsStringSync()
    .replaceAll(RegExp('```.*?```', dotAll: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says.
void _says(String phrase) => expect(
      _prose().contains(phrase),
      isTrue,
      reason: '$_doc no longer says: $phrase',
    );

/// [child] under a parent asynchronous scope of scopo, which writes
/// `parent released` to [parentTrace] when it is released.
Widget underParent(Widget child) => AsyncScope(
      initScope: (context, ctx) async {},
      disposeScope: () => parentTrace?.add('parent released'),
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
      builder: (context) => child,
    );

/// The trace the parent of [underParent] writes to: that of the API of the
/// controller below it, which a test sets once the page's code has built
/// that controller.
List<String>? parentTrace;

/// Pumps until [finder] finds a widget: a scope of scopo builds its ready
/// branch some time after its initialization ends.
Future<void> ready(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 50 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

/// Every controller made while a test runs, the ones a scope never returned
/// included.
List<ProfileController> made() {
  final controllers = <ProfileController>[];
  Solo.observer = _Made(controllers);
  addTearDown(() => Solo.observer = null);

  return controllers;
}

class _Made extends SoloObserver {
  final List<ProfileController> controllers;

  _Made(this.controllers);

  @override
  void onCreate(Solo<Object> solo) =>
      controllers.add(solo as ProfileController);
}

void main() {
  // A widget test is given ten minutes by default.
  (TestWidgetsFlutterBinding.ensureInitialized()
          as AutomatedTestWidgetsFlutterBinding)
      .defaultTestTimeout = const Timeout(Duration(seconds: 30));

  group("The controller's life", () {
    testWidgets('a ScopeModel owns the controller of one screen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: screenScope()));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Ada Lovelace'), findsOneWidget);
      final controller = ScopeModel.of<ProfileController>(
        tester.element(find.byType(ProfileView)),
        listen: false,
      );
      expect(controller.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(controller.isClosed, isTrue);
      _says('`ScopeModel` creates the controller once it is mounted and '
          'hands it to `dispose` when it leaves the tree, and the subtree '
          'reads it with `ScopeModel.of`');
    });

    testWidgets('under ScopeModel the parent goes first', (tester) async {
      await tester.pumpWidget(MaterialApp(home: underParent(screenScope())));
      await ready(tester, find.text('Ada Lovelace'));
      final controller = ScopeModel.of<ProfileController>(
        tester.element(find.byType(ProfileView)),
        listen: false,
      );
      parentTrace = controller.api.trace;
      addTearDown(() => parentTrace = null);
      final save = controller.save();
      await tester.pump(const Duration(milliseconds: 3));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(controller.api.trace.skip(2), [
        'save begins',
        'parent released',
        'save ends',
      ]);
      expect('${save.outcome}', 'Cancelled(closed)');
      _says('That `dispose` is synchronous, as in a `State`, and nothing '
          'waits for the close.');
      _says('Under `ScopeModel` the parent releases it while that save is '
          'still running.');
    });

    testWidgets('AsyncDataScope is ready once the profile is loaded',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: sharedScope()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProfileView), findsNothing);

      await ready(tester, find.text('Ada Lovelace'));
      expect(ProfileApi.last!.trace, ['fetch begins', 'fetch ends']);
      _says('The scope is ready once the profile is loaded: until then it '
          'shows `progressBuilder`');
    });

    testWidgets('a load that fails closes the controller', (tester) async {
      final controllers = made();
      ProfileApi.next = profile.ProfileApi(error: StateError('no network'));
      addTearDown(() => ProfileApi.next = profile.ProfileApi());
      await tester.pumpWidget(MaterialApp(home: sharedScope()));

      await ready(tester, find.text('Bad state: no network'));
      expect(controllers.single.isClosed, isTrue);
      _says('a load that fails is what `errorBuilder` shows');
      _says('`ctx.onDiscard` closes it on the two other paths: a failed load');
    });

    testWidgets('a scope removed while it loads closes the controller at once',
        (tester) async {
      final controllers = made();
      ProfileApi.next = profile.ProfileApi(delay: const Duration(seconds: 1));
      addTearDown(() => ProfileApi.next = profile.ProfileApi());
      await tester.pumpWidget(MaterialApp(home: sharedScope()));
      await tester.pump(const Duration(milliseconds: 50));
      final controller = controllers.single;
      expect(controller.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      expect(controller.isClosed, isTrue);
      expect(ProfileApi.last!.trace, ['fetch begins']);
      await tester.pump(const Duration(seconds: 1));
      _says('a scope removed while it loads, where `ctx.abandonable` stops '
          'waiting at once and the close cancels the load.');
    });

    testWidgets('AsyncDataScope holds the parent until the close is over',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: underParent(sharedScope())));
      await ready(tester, find.text('Ada Lovelace'));
      final controller = AsyncDataScope.of<ProfileController>(
        tester.element(find.byType(ProfileView)),
        listen: false,
      ).data;
      parentTrace = controller.api.trace;
      addTearDown(() => parentTrace = null);
      final save = controller.save();
      await tester.pump(const Duration(milliseconds: 3));

      await tester.pumpWidget(const SizedBox());
      expect(controller.isClosed, isTrue);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(controller.api.trace.skip(2), [
        'save begins',
        'save ends',
        'parent released',
      ]);
      expect(controller.api.saved, ['Ada Lovelace']);
      expect('${save.outcome}', 'Cancelled(closed)');
      _says('It awaits the future `disposeData` returns, and a parent '
          'asynchronous scope of scopo is released only after its children');
      _says('What the parent releases outlives the jobs of the controller, a '
          'save it waits out with `ctx.join` included.');
      _says('A screen further down reads the controller with '
          '`AsyncDataScope.of<ProfileController>(context, listen: '
          'false).data`.');
    });

    test('both waits have a bound of three seconds by default', () {
      expect(
        ScopeConfig.defaultDisposeScopeTimeout,
        const Duration(seconds: 3),
      );
      expect(
        ScopeConfig.defaultWaitForChildrenTimeout,
        const Duration(seconds: 3),
      );
      _says('Both waits have a bound, `disposeScopeTimeout` of the scope and '
          '`waitForChildrenTimeout` of its parent, three seconds by default.');
      _says('`ScopeTimeout.none` takes the bound off for one scope.');
    });
  });
}
