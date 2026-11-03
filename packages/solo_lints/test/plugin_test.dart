// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/solo_lints.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/recording_registry.dart';
import 'support/rule_base.dart';

/// What [SoloLintsPlugin] registers.
RecordingRegistry _registered() {
  final registry = RecordingRegistry();
  SoloLintsPlugin().register(registry);
  return registry;
}

void main() {
  // A user of solo_lints keeps every rule after the rules of the core moved
  // to async_job_lints: a forgotten call, a rule of the wrong kind or a lost
  // fix shows here, while the tests of the rules make the classes directly.
  test('the plugin registers the eight rules, each with its kind', () {
    final registry = _registered();
    expect(SoloLintsPlugin().name, 'solo_lints');
    expect(
      registry.warnings.map((rule) => rule.name),
      unorderedEquals([
        'ctx_in_cleanup',
        'release_on_the_call',
        'sync_fake_async',
        'await_own_queue',
      ]),
    );
    expect(
      registry.lints.map((rule) => rule.name),
      unorderedEquals([
        'catch_without_check',
        'key_per_request',
        'ignore_failure_hides_bugs',
        'bare_await',
      ]),
    );
    expect(registry.fixedRules, {
      'release_on_the_call',
      'catch_without_check',
      'key_per_request',
    });
  });

  defineReflectiveSuite(() {
    defineReflectiveTests(OwnQueueTest);
  });
}

/// `bare_await` as the plugin registers it, at a wait for the own queue.
@reflectiveTest
class OwnQueueTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => _registered().rule('bare_await');

  // await_own_queue reports this wait; bare_await stays quiet.
  Future<void> test_own_queue() => assertAt('''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> {
  Desk() : super(0);

  Job<void> logout() => enqueue<int, void>((ctx) async {
    await close();
  });
}
''', []);
}
