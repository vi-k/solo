import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
// The registry is not exported; analyzer_testing reaches it the same way.
// Only this test may import it: it reads a page of package:solo and stays
// out of the archive, so the floor job never runs it.
// ignore: implementation_imports
import 'package:analyzer/src/lint/registry.dart';
import 'package:analyzer_testing/utilities/utilities.dart';
import 'package:collection/collection.dart';
import 'package:solo_lints/src/rules/await_own_queue.dart';
import 'package:solo_lints/src/rules/catch_without_check.dart';
import 'package:solo_lints/src/rules/ctx_in_cleanup.dart';
import 'package:solo_lints/src/rules/ignore_failure_hides_bugs.dart';
import 'package:solo_lints/src/rules/key_per_request.dart';
import 'package:solo_lints/src/rules/release_on_the_call.dart';
import 'package:solo_lints/src/rules/sync_fake_async.dart';
import 'package:test/test.dart';

import 'support/rule_base.dart';

/// The page of mistakes, as seen from the package directory.
const _pagePath = '../solo/doc/mistakes.md';

/// The rule each pair of the page shows, by section and by the number of the
/// pair in it; `null` for a pair no rule of the package reports.
///
/// A pair missing here fails its test, so a new section of the page does not
/// go by unchecked; a pair that a rule starts to report on must name it here.
const _table = <(String, int), String?>{
  ('Each wait in its place', 1): null,
  ('Each wait in its place', 2): 'ctx_in_cleanup',
  ('Registering a release on the call', 1): 'release_on_the_call',
  ('Letting cancellation through a catch', 1): 'catch_without_check',
  ('Steps as children', 1): 'await_own_queue',
  ('Answering for every failure', 1): null,
  ('Moving the clock in fakeAsync', 1): 'sync_fake_async',
  ('A key for each request', 1): 'key_per_request',
};

void main() {
  final sections = _Section.parse(File(_pagePath).readAsStringSync());

  test('every row of the table has its pair on the page', () {
    final onPage = {
      for (final section in sections)
        for (final pair in section.pairs) (section.name, pair.number),
    };
    final missing = [
      for (final (section, number) in _table.keys)
        if (!onPage.contains((section, number))) '$section, pair $number',
    ];
    expect(missing, isEmpty, reason: 'rows with no pair on the page');
  });

  // No block of the page shows ignore_failure_hides_bugs reporting, while its
  // silence on two of them is what the guard checks: this shows it is on.
  test('ignore_failure_hides_bugs reports in the guard', () async {
    final guard = _Guard()..setUp();
    try {
      await guard.check(
        'a load with isExpectedError',
        _refresh('profile.load().ignoreFailure();', expectedErrors: true),
        'ignore_failure_hides_bugs',
      );
    } finally {
      await guard.tearDown();
    }
  });

  for (final section in sections) {
    group(section.name, () {
      test('pairs each "Don\'t do this" with a "Do this"', () {
        final sides = [for (final block in section.blocks) block.side];
        final paired = [
          for (var i = 0; i < sides.length; i++) _Side.values[i % 2],
        ];
        final wrong = sides.where((side) => side == _Side.wrong).length;
        expect(
          sides.length.isEven &&
              const ListEquality<_Side>().equals(sides, paired),
          isTrue,
          reason:
              '${section.name}: $wrong "Don\'t do this" and '
              '${sides.length - wrong} "Do this", in the order '
              '${sides.map((side) => side.label).join(', ')}',
        );
        expect(
          section.unblocked,
          isEmpty,
          reason: '${section.name}: markers with no dart block after them',
        );
        expect(
          section.unclaimed,
          0,
          reason: '${section.name}: dart blocks with no marker before them',
        );
        // Every section of the page shows a mistake: one without a pair has
        // a marker spelt some other way, and its blocks would go unchecked.
        expect(
          section.pairs,
          isNotEmpty,
          reason: '${section.name}: no pair of "Don\'t do this" and "Do this"',
        );
      });

      for (final pair in section.pairs) {
        for (final block in [pair.wrong, pair.right]) {
          test('pair ${pair.number}: ${block.side.label}', () async {
            final where = '${section.name}, pair ${pair.number}';
            if (!_table.containsKey((section.name, pair.number))) {
              fail('$where is not in the table of the test');
            }
            final expected = block.side == _Side.wrong
                ? _table[(section.name, pair.number)]
                : null;
            final guard = _Guard()..setUp();
            try {
              await guard.check(
                '$where, ${block.side.label}',
                _wrap(section.name, pair.number, block.side, block.code),
                expected,
              );
            } finally {
              await guard.tearDown();
            }
          });
        }
      }
    });
  }
}

/// The side of a pair: the mistake or the right way.
enum _Side {
  wrong("Don't do this"),
  right('Do this');

  const _Side(this.label);

  /// The words that put a block on this side.
  final String label;
}

/// A dart block of the page and the side it stands on.
final class _Block {
  _Block(this.side, this.code);

  final _Side side;
  final String code;
}

/// The n-th "Don't do this" of a section and its n-th "Do this".
final class _Pair {
  _Pair(this.number, this.wrong, this.right);

  final int number;
  final _Block wrong;
  final _Block right;
}

/// A `## ` section of the page and the blocks of its pairs, in page order.
final class _Section {
  _Section(this.name);

  final String name;
  final List<_Block> blocks = [];

  /// The markers of this section that no dart block follows.
  final List<String> unblocked = [];

  /// The number of dart blocks of this section that no marker claims.
  int unclaimed = 0;

  /// The pairs of this section: the n-th block of each side together, as far
  /// as both sides go.
  List<_Pair> get pairs {
    final wrong = [
      for (final block in blocks)
        if (block.side == _Side.wrong) block,
    ];
    final right = [
      for (final block in blocks)
        if (block.side == _Side.right) block,
    ];
    return [
      for (var i = 0; i < wrong.length && i < right.length; i++)
        _Pair(i + 1, wrong[i], right[i]),
    ];
  }

  /// The sections of [page]: a marker line takes the nearest ```dart block
  /// after it.
  static List<_Section> parse(String page) {
    final sections = <_Section>[];
    _Side? pending;
    List<String>? code;
    var fenced = false;
    void unblock() {
      if (pending case final side?) sections.last.unblocked.add(side.label);
      pending = null;
    }

    for (final line in page.split('\n')) {
      if (line.startsWith('```')) {
        if (fenced) {
          if (code != null) {
            sections.last.blocks.add(_Block(pending!, code.join('\n')));
            pending = null;
            code = null;
          }
        } else if (line.trim() == '```dart') {
          if (pending != null) {
            code = [];
          } else if (sections.isNotEmpty) {
            sections.last.unclaimed++;
          }
        }
        fenced = !fenced;
        continue;
      }
      if (fenced) {
        code?.add(line);
        continue;
      }
      if (line.startsWith('## ')) {
        if (sections.isNotEmpty) unblock();
        sections.add(_Section(line.substring(3).trim()));
        continue;
      }
      if (sections.isEmpty) continue;
      for (final side in _Side.values) {
        if (line.trim() == '${side.label}:') {
          unblock();
          pending = side;
        }
      }
    }
    if (sections.isNotEmpty) unblock();
    return sections;
  }
}

/// [code], a block of [section], in the declarations it needs to resolve.
///
/// The blocks stand in different places: most are statements of a job body,
/// two sections show members of a controller, and the wrong way of
/// "Answering for every failure" is a top-level class.
String _wrap(String section, int pair, _Side side, String code) =>
    switch ((section, pair, side)) {
      ('Each wait in its place', _, _) => _upload(code),
      ('Registering a release on the call', _, _) => _session(code),
      ('Letting cancellation through a catch', _, _) => _camera(code),
      ('Steps as children', _, _) => _syncer(code),
      ('Answering for every failure', _, _Side.wrong) => _failures(code),
      ('Answering for every failure', _, _Side.right) => _refresh(code),
      ('Moving the clock in fakeAsync', _, _) => _fakeClock(code),
      ('A key for each request', _, _) => _profiles(code),
      _ => fail('$section, pair $pair has no harness'),
    };

String _upload(String code) =>
    '''
import 'package:async_job/async_job.dart';

abstract interface class Device {
  Future<void> write(List<int> chunk);

  Future<void> flush();
}

late final Device device;
late final List<List<int>> chunks;

final upload = Job<void>((ctx) async {
$code
});
''';

String _session(String code) =>
    '''
import 'package:async_job/async_job.dart';

abstract interface class Database {
  static late Future<Database> Function() open;

  Future<void> close();
}

final session = Job<void>((ctx) async {
$code
});
''';

String _camera(String code) =>
    '''
import 'package:solo/solo.dart';

sealed class CameraState {}

final class Idle extends CameraState {}

final class Broken extends CameraState {
  Broken(this.error);

  final Object error;
}

abstract interface class Hardware {
  Future<void> open();

  Future<void> setZoom(int zoom);

  Future<void> reset();
}

late final Hardware hw;

final class Camera extends Solo<CameraState> {
  Camera() : super(Idle());

  Job<void> zoomTo(int zoom) => enqueue<CameraState, void>((ctx) async {
$code
  });
}
''';

String _syncer(String code) =>
    '''
import 'package:solo/solo.dart';

sealed class State {}

final class Ready extends State {}

enum _Op { syncAndRecord }

final class Syncer extends Solo<State> {
  Syncer() : super(Ready());

  SoloJob<String> _sync(int item) =>
      job<Ready, String>((ctx) async => '\$item');

  Job<String> sync(int item) => enqueueJob(_sync(item));

  SoloJob<void> _recordPath(String path) => job<Ready, void>((ctx) async {});

  Job<void> recordPath(String path) => enqueueJob(_recordPath(path));

$code
}
''';

String _failures(String code) =>
    '''
import 'package:solo/solo.dart';

void reportCrash(Object error, StackTrace stackTrace) {}

$code
''';

/// The load names no `isExpectedError`: the page speaks of a job whose
/// outcome nobody needs, not of its expected errors.
///
/// With [expectedErrors] the load names them, for the test that sees
/// `ignore_failure_hides_bugs` report in this harness.
String _refresh(String code, {bool expectedErrors = false}) =>
    '''
import 'package:solo/solo.dart';

sealed class State {}

final class Ready extends State {}

class Profile {}

class ApiException implements Exception {}

abstract interface class Api {
  Future<Profile> load();
}

late final Api api;

final class ProfileController extends Solo<State> {
  ProfileController() : super(Ready());

  Job<Profile> load() => enqueue<Ready, Profile>(
    (ctx) => api.load(),
    ${expectedErrors ? 'isExpectedError: (e) => e is ApiException,' : ''}
  );
}

late final ProfileController profile;

void refresh() {
$code
}
''';

/// package:test is not among the sources of the analyzed package, so the
/// harness declares the three names the blocks use.
String _fakeClock(String code) =>
    '''
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

void test(String description, Object? Function() body) {}

void expect(Object? actual, Object? matcher) {}

Object isA<T>() => Object();

abstract interface class ProfileApi {
  Future<String> loadName();
}

final class FakeProfileApi implements ProfileApi {
  @override
  Future<String> loadName() =>
      Future.delayed(const Duration(milliseconds: 10), () => 'Ada');
}

sealed class ProfileState {}

final class Empty extends ProfileState {}

final class Loaded extends ProfileState {}

final class ProfileController extends Solo<ProfileState> {
  ProfileController(this._api) : super(Empty());

  final ProfileApi _api;

  Job<String> load() =>
      enqueue<ProfileState, String>((ctx) => _api.loadName());
}

void main() {
$code
}
''';

String _profiles(String code) =>
    '''
import 'package:solo/solo.dart';

sealed class State {}

final class Ready extends State {}

class Profile {}

enum _Op { load }

abstract interface class Api {
  Future<Profile> load(String id);
}

late final Api api;

final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

$code
}
''';

/// Analyzes code with every rule of the package on.
///
/// [RuleTest] puts the packages in and turns one rule on; this test registers
/// the other six as the plugin does, each with its own kind, and enables all
/// seven.
final class _Guard extends RuleTest {
  static final _warnings = <AbstractAnalysisRule>[
    CtxInCleanup(),
    ReleaseOnTheCall(),
    SyncFakeAsync(),
    AwaitOwnQueue(),
  ];

  static final _lints = <AbstractAnalysisRule>[
    CatchWithoutCheck(),
    KeyPerRequest(),
    IgnoreFailureHidesBugs(),
  ];

  @override
  AbstractAnalysisRule get underTest => _lints.first;

  @override
  void setUp() {
    super.setUp();
    _warnings.forEach(Registry.ruleRegistry.registerWarningRule);
    _lints.skip(1).forEach(Registry.ruleRegistry.registerLintRule);
    newAnalysisOptionsYamlFile(
      testPackageRootPath,
      analysisOptionsContent(
        rules: [
          for (final rule in [..._warnings, ..._lints]) rule.name,
        ],
      ),
    );
  }

  /// Checks that [code] resolves without a compile error and that the rules
  /// of the package report on it [expected] alone, or nothing when
  /// [expected] is `null`.
  ///
  /// [where] names the block in the failures.
  Future<void> check(String where, String code, String? expected) async {
    testFile.writeAsStringSync(code);
    result = await resolveFile(testFile.path);
    final diagnostics = result.diagnostics;
    // A warning such as an unused variable is no reason to fail: only the
    // errors of the compiler are, and a rule never reports one.
    final errors = [
      for (final d in diagnostics)
        if (d.diagnosticCode.severity == DiagnosticSeverity.ERROR &&
            d.diagnosticCode is! LintCode)
          d,
    ];
    if (errors.isNotEmpty) {
      fail(
        '$where does not compile in its harness:\n'
        '${errors.map((d) => '  ${d.offset}: ${d.message}').join('\n')}\n'
        '$code',
      );
    }
    final reported = <String>{};
    final lines = <String>[];
    for (final d in diagnostics) {
      for (final rule in [..._warnings, ..._lints]) {
        if (rule.diagnosticCodes.contains(d.diagnosticCode)) {
          reported.add(rule.name);
          lines.add('  ${rule.name} at ${d.offset}: ${d.message}');
        }
      }
    }
    final report = lines.isEmpty ? '' : ':\n${lines.join('\n')}';
    if (expected == null) {
      expect(reported, isEmpty, reason: '$where: a rule reports it$report');
    } else {
      expect(reported, {
        expected,
      }, reason: '$where: only $expected is to report it$report');
    }
  }
}
