// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/release_on_the_call.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ReleaseOnTheCallTest);
  });
}

const _core = '''
import 'package:async_job/async_job.dart';

abstract interface class Database {
  static late Future<Database> Function() open;

  Future<void> close();
}
''';

@reflectiveTest
class ReleaseOnTheCallTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => ReleaseOnTheCall();

  Future<void> test_tear_off_on_the_next_line() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.onDispose(db.close);
});
''',
    ['ctx.onDispose(db.close)'],
  );

  Future<void> test_release_on_the_call() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  await db.close();
});
''', []);

  Future<void> test_literal_and_other_calls() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  final a = await ctx.abandonable(Database.open);
  ctx.onDiscard(() => a.close());
  final b = await ctx.run(ctx.child((_) => Database.open()));
  ctx.onDispose(() async => b.close());
});
''',
    ['ctx.onDiscard(() => a.close())', 'ctx.onDispose(() async => b.close())'],
  );

  Future<void> test_code_in_between() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.log('opened');
  ctx.onDispose(db.close);
});
''', []);

  Future<void> test_release_of_something_else() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  final other = await Database.open();
  final db = await ctx.join(Database.open);
  ctx.onDispose(other.close);
  await db.close();
});
''', []);

  Future<void> test_discard_on_the_call() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open, discard: (db) => db.close());
  ctx.onDispose(db.close);
});
''', []);

  Future<void> test_another_context() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  await ctx.run(
    ctx.child((child) async {
      final db = await ctx.join(Database.open);
      child.onDispose(db.close);
    }),
  );
});
''', []);
}
