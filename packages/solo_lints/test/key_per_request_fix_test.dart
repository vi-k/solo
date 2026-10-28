// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/fixes/key_per_request.dart';
import 'package:solo_lints/src/rules/key_per_request.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fix_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(KeyPerRequestFixTest);
  });
}

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
''';

@reflectiveTest
class KeyPerRequestFixTest extends FixTest {
  @override
  AbstractAnalysisRule get underTest => KeyPerRequest();

  @override
  ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  get producer => PutArgumentsIntoKey.new;

  Future<void> test_one_parameter() => assertFix(
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
    'key: [[_Op.load]]',
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: (_Op.load, id),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
  );

  Future<void> test_enqueue_job_form() => assertFix(
    '''
$_profiles
  Job<Profile> load(String id) => enqueueJob(
    job<Ready, Profile>(key: _Op.load, (ctx) => api.load(id)),
    policy: Policy.droppable,
  );
}
''',
    'key: [[_Op.load]]',
    '''
$_profiles
  Job<Profile> load(String id) => enqueueJob(
    job<Ready, Profile>(key: (_Op.load, id), (ctx) => api.load(id)),
    policy: Policy.droppable,
  );
}
''',
  );

  Future<void> test_two_parameters_in_order() => assertFix(
    '''
$_profiles
  Job<Profile> load(String id, int page) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load('\$page\$id')),
  );
}
''',
    'key: [[_Op.load]]',
    '''
$_profiles
  Job<Profile> load(String id, int page) => enqueue<Ready, Profile>(
    key: (_Op.load, id, page),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load('\$page\$id')),
  );
}
''',
  );

  Future<void> test_unread_parameter_left_out() => assertFix(
    '''
$_profiles
  Job<Profile> load(String id, bool force) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
    'key: [[_Op.load]]',
    '''
$_profiles
  Job<Profile> load(String id, bool force) => enqueue<Ready, Profile>(
    key: (_Op.load, id),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
  );

  Future<void> test_record_key() => assertFix(
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: (_Op.load, 1),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
    'key: [[(_Op.load, 1)]]',
    '''
$_profiles
  Job<Profile> load(String id) => enqueue<Ready, Profile>(
    key: ((_Op.load, 1), id),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );
}
''',
  );

  Future<void> test_enum_and_nullable() => assertFix(
    '''
$_profiles
  Job<Profile> load(_Op kind, String? id) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load('\$kind\$id')),
  );
}
''',
    'key: [[_Op.load]]',
    '''
$_profiles
  Job<Profile> load(_Op kind, String? id) => enqueue<Ready, Profile>(
    key: (_Op.load, kind, id),
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load('\$kind\$id')),
  );
}
''',
  );

  Future<void> test_no_fix_for_list() => assertNoFix('''
$_profiles
  Job<Profile> load(List<String> ids) => enqueue<Ready, Profile>(
    key: _Op.load,
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(ids.first)),
  );
}
''', 'key: [[_Op.load]]');

  Future<void> test_no_fix_for_callback() => assertNoFix('''
$_profiles
  Job<Profile> load(String id, void Function() onDone) =>
      enqueue<Ready, Profile>(
        key: _Op.load,
        policy: Policy.droppable,
        (ctx) async {
          onDone();
          return api.load(id);
        },
      );
}
''', 'key: [[_Op.load]]');
}
