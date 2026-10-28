// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/sync_fake_async.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SyncFakeAsyncTest);
  });
}

@reflectiveTest
class SyncFakeAsyncTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => SyncFakeAsync();

  Future<void> test_async_callback() => assertAt(
    '''
import 'package:fake_async/fake_async.dart';

Future<void> load() async {
  await fakeAsync((async) async {
    await Future<void>.value();
  });
}
''',
    ['(async) [[async]] {'],
  );

  Future<void> test_sync_callback() => assertAt('''
import 'package:fake_async/fake_async.dart';

void load() {
  fakeAsync((async) {
    async.elapse(const Duration(milliseconds: 20));
  });
}
''', []);

  Future<void> test_run_of_fake_async() => assertAt(
    '''
import 'package:fake_async/fake_async.dart';

void load() {
  FakeAsync().run((async) async => async.flushTimers());
}
''',
    ['(async) [[async]] =>'],
  );

  Future<void> test_function_of_another_library() => assertAt('''
void fakeAsync(Future<void> Function(Object async) callback) {}

void load() {
  fakeAsync((async) async {});
}
''', []);
}
