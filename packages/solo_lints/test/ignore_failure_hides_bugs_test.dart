// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/ignore_failure_hides_bugs.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(IgnoreFailureHidesBugsTest);
  });
}

/// The declarations a controller with expected errors needs.
const _header = '''
import 'package:solo/solo.dart';

sealed class State {}

final class Ready extends State {}

class Profile {}

class ApiException implements Exception {}

abstract interface class Api {
  Future<Profile> load();
  Future<void> save(List<String> names);
}

late final Api api;
''';

/// A controller to be completed whose `load` names its expected errors, and
/// a `profiles` to call it on.
const _profiles =
    '''
$_header
late final Profiles profiles;

final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  SoloJob<Profile> load() => enqueue<Ready, Profile>(
    (ctx) => api.load(),
    isExpectedError: (e) => e is ApiException,
  );
''';

@reflectiveTest
class IgnoreFailureHidesBugsTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => IgnoreFailureHidesBugs();

  /// Asserts one diagnostic at the `ignoreFailure` of [span], naming
  /// [owner]'s predicate.
  Future<void> _assertOne(String code, String span, String owner) =>
      assertDiagnostics(code, [
        lint(
          code.indexOf(span) + span.indexOf('ignoreFailure'),
          'ignoreFailure'.length,
          messageContainsAll: ["'$owner's isExpectedError'"],
        ),
      ]);

  Future<void> test_method_of_same_library() => _assertOne(
    '''
$_profiles
}

void reload() {
  profiles.load().ignoreFailure();
}
''',
    'profiles.load().ignoreFailure()',
    'load',
  );

  Future<void> test_direct_call() => _assertOne(
    '''
$_profiles
  void reload() {
    enqueue<Ready, Profile>(
      (ctx) => api.load(),
      isExpectedError: (e) => e is ApiException,
    ).ignoreFailure();
  }
}
''',
    'ignoreFailure()',
    'enqueue',
  );

  Future<void> test_job_through_enqueue_job() => _assertOne(
    '''
$_header
final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  SoloJob<Profile> load() => enqueueJob(
    job<Ready, Profile>(
      (ctx) => api.load(),
      isExpectedError: (e) => e is ApiException,
    ),
  );

  void reload() {
    load().ignoreFailure();
  }
}
''',
    'load().ignoreFailure()',
    'load',
  );

  Future<void> test_chain() => _assertOne(
    '''
$_header
final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  SoloJob<Profile> load() => _load();

  SoloJob<Profile> _load() => enqueue<Ready, Profile>(
    (ctx) => api.load(),
    isExpectedError: (e) => e is ApiException,
  );

  void reload() {
    load().ignoreFailure();
  }
}
''',
    'load().ignoreFailure()',
    'load',
  );

  Future<void> test_single_return() => _assertOne(
    '''
$_header
final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  SoloJob<Profile> load() {
    return enqueue<Ready, Profile>(
      (ctx) => api.load(),
      isExpectedError: (e) => e is ApiException,
    );
  }

  void reload() {
    load().ignoreFailure();
  }
}
''',
    'load().ignoreFailure()',
    'load',
  );

  Future<void> test_accumulator_field() => _assertOne(
    '''
$_header
final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  late final _saves = collect<Ready, String, void>(
    (ctx, names) => api.save(names),
    isExpectedError: (e) => e is ApiException,
  );

  void save(String name) {
    _saves.add(name).ignoreFailure();
  }
}
''',
    '_saves.add(name).ignoreFailure()',
    '_saves',
  );

  Future<void> test_cascade_statement() => _assertOne(
    '''
$_profiles
}

void reload() {
  profiles.load()..ignoreFailure();
}
''',
    'profiles.load()..ignoreFailure()',
    'load',
  );

  Future<void> test_cascade_in_void_callback() => _assertOne(
    '''
$_profiles
}

void button({required void Function() onPressed}) {}

void build() {
  button(onPressed: () => profiles.load()..ignoreFailure());
}
''',
    'profiles.load()..ignoreFailure()',
    'load',
  );

  Future<void> test_cascade_in_void_variable() => _assertOne(
    '''
$_profiles
}

final void Function() reload = () => profiles.load()..ignoreFailure();
''',
    'profiles.load()..ignoreFailure()',
    'load',
  );

  Future<void> test_cascade_in_void_declaration() => _assertOne(
    '''
$_profiles
}

void reload() => profiles.load()..ignoreFailure();
''',
    'profiles.load()..ignoreFailure()',
    'load',
  );

  Future<void> test_cascade_returned() => assertAt('''
$_profiles
}

SoloJob<Profile> reload() => profiles.load()..ignoreFailure();

final SoloJob<Profile> Function() reloader = () =>
    profiles.load()..ignoreFailure();

void keep(SoloJob<Profile> Function() reload) {}

void build() {
  keep(() => profiles.load()..ignoreFailure());
}
''', []);

  Future<void> test_cascade_kept() => assertAt('''
$_profiles
}

SoloJob<Profile> reload() {
  final job = profiles.load()..ignoreFailure();
  return job;
}
''', []);

  Future<void> test_parentheses_and_this() => assertAt(
    '''
$_profiles
  void reload() {
    (load()).ignoreFailure();
    this.load().ignoreFailure();
  }
}
''',
    ['(load()).[[ignoreFailure]]', 'this.load().[[ignoreFailure]]'],
  );

  Future<void> test_no_predicate() => assertAt('''
$_header
final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  SoloJob<Profile> load() => enqueue<Ready, Profile>((ctx) => api.load());

  void reload() {
    load().ignoreFailure();
  }
}
''', []);

  Future<void> test_variable() => assertAt('''
$_profiles
  void reload() {
    final job = load();
    job.ignoreFailure();
  }
}
''', []);

  Future<void> test_other_library() {
    newFile('$testPackageLibPath/profiles.dart', '''
$_profiles
}
''');
    return assertAt('''
import 'profiles.dart';

void reload() {
  profiles.load().ignoreFailure();
}
''', []);
  }

  Future<void> test_recursion() => assertAt('''
$_profiles
}

SoloJob<Profile> a() => b();

SoloJob<Profile> b() => a();

void reload() {
  a().ignoreFailure();
}
''', []);
}
