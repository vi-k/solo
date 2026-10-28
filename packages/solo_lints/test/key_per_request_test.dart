// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/key_per_request.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(KeyPerRequestTest);
  });
}

/// The harness of the key section of the mistakes page: a controller to be
/// completed with a `load` taking an id.
const _profiles = '''
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

  final _key = Object();

  Future<Profile> _load(SoloContext<State, Ready> ctx) => api.load('a');
''';

@reflectiveTest
class KeyPerRequestTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => KeyPerRequest();

  Future<void> test_enqueue() => assertAt(
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
    ['key: [[_Op.load]]'],
  );

  Future<void> test_enqueue_job() => assertAt(
    '''
$_profiles
  Job<Profile> load(String id) => enqueueJob(
    job<Ready, Profile>(key: _Op.load, (ctx) => api.load(id)),
    policy: Policy.droppable,
  );
}
''',
    ['key: [[_Op.load]]'],
  );

  Future<void> test_key_with_parameter() => assertAt('''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: (_Op.load, id),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''', []);

  Future<void> test_key_reads_parameter_otherwise() => assertAt('''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: 'load-\$id',
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );

  Job<Profile> hashed(String id) => enqueue<Ready, Profile>(
    key: id.hashCode,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''', []);

  Future<void> test_other_policy() => assertAt('''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.sequential,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );

  Job<Profile> bare(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''', []);

  Future<void> test_body_reads_no_parameter() => assertAt('''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load('ada')),
  );
}
''', []);

  Future<void> test_key_from_field() => assertAt(
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _key,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
    ['key: [[_key]]'],
  );

  Future<void> test_body_is_tear_off() => assertAt('''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    _load,
  );
}
''', []);

  Future<void> test_local_function() => assertAt(
    '''
$_profiles
  void run() {
    Job<Profile> load(String id) => enqueue<Ready, Profile>(
      key: _Op.load,
      policy: Policy.droppable,
      (ctx) => ctx.abandonable(() => api.load(id)),
    );
    load('ada');
  }
}
''',
    ['key: [[_Op.load]]'],
  );
}
