// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/bare_await.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(BareAwaitTest);
  });
}

@reflectiveTest
class BareAwaitTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => BareAwait();

  Future<void> test_join_action() => assertAt('''
import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

final job = Job<void>((ctx) async {
  await ctx.join(() async {
    final receipt = await commit();
    print(receipt);
  });
});
''', []);

  Future<void> test_plain() => assertAt(
    '''
import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

final job = Job<void>((ctx) async {
  await commit();
});
''',
    ['await'],
  );
}
