// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart' // ignore: implementation_imports
    as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/fixes/release_on_the_call.dart';
import 'package:solo_lints/src/rules/release_on_the_call.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fix_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ReleaseOnTheCallFixTest);
  });
}

// The core of release_on_the_call_test.dart, with a `pool` getter and a
// function that closes a database.
const _core = '''
import 'package:async_job/async_job.dart';

abstract interface class Database {
  static late Future<Database> Function() open;

  Future<void> close();

  Database get pool;
}

Future<void> Function() closerFor(Database db) => db.close;
''';

@reflectiveTest
class ReleaseOnTheCallFixTest extends FixTest {
  @override
  AbstractAnalysisRule get underTest => ReleaseOnTheCall();

  @override
  ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  get producer => PassReleaseToCall.new;

  Future<void> test_tear_off() => assertFix(
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.onDispose(db.close);
  print(db);
});
''',
    '[[ctx.onDispose(db.close)]]',
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  print(db);
});
''',
    arguments: ['dispose'],
  );

  Future<void> test_literal_without_parameters() => assertFix(
    '''
$_core
final job = Job<void>((ctx) async {
  final a = await ctx.abandonable(Database.open);
  ctx.onDiscard(() => a.close());
  print(a);
});
''',
    '[[ctx.onDiscard(() => a.close())]]',
    '''
$_core
final job = Job<void>((ctx) async {
  final a = await ctx.abandonable(Database.open, discard: (a) => a.close());
  print(a);
});
''',
    arguments: ['discard'],
  );

  Future<void> test_async_block_literal() => assertFix(
    '''
$_core
final job = Job<void>((ctx) async {
  final b = await ctx.run(ctx.child((_) => Database.open()));
  ctx.onDispose(() async { await b.close(); });
  print(b);
});
''',
    '[[ctx.onDispose(() async { await b.close(); })]]',
    '''
$_core
final job = Job<void>((ctx) async {
  final b = await ctx.run(ctx.child((_) => Database.open()), dispose: (b) async { await b.close(); });
  print(b);
});
''',
    arguments: ['dispose'],
  );

  Future<void> test_trailing_comma() => assertFix(
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(
    Database.open,
  );
  ctx.onDispose(db.close);
  print(db);
});
''',
    '[[ctx.onDispose(db.close)]]',
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(
    Database.open,
    dispose: (db) => db.close(),
  );
  print(db);
});
''',
  );

  Future<void> test_trailing_comma_on_the_line_of_the_paren() => assertFix(
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open,);
  ctx.onDispose(db.close);
  print(db);
});
''',
    '[[ctx.onDispose(db.close)]]',
    '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open, dispose: (db) => db.close(),);
  print(db);
});
''',
  );

  Future<void> test_no_fix_for_other_forms() async {
    await assertNoFix('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.onDispose(db.pool.close);
  print(db);
});
''', '[[ctx.onDispose(db.pool.close)]]');
    await assertNoFix('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.onDispose(closerFor(db));
  print(db);
});
''', '[[ctx.onDispose(closerFor(db))]]');
  }

  Future<void> test_no_fix_for_literal_with_optional_parameters() =>
      assertNoFix('''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join(Database.open);
  ctx.onDispose(([_]) => db.close());
  print(db);
});
''', '[[ctx.onDispose(([_]) => db.close())]]');

  // The call has no arguments, which does not compile: the rule still
  // reports, and the fix has no argument list to extend.
  Future<void> test_no_fix_for_call_without_arguments() {
    const code =
        '''
$_core
final job = Job<void>((ctx) async {
  final db = await ctx.join();
  ctx.onDispose(db.close);
  print(db);
});
''';
    // The missing argument is reported at the closing parenthesis.
    final close = code.indexOf('ctx.join(') + 'ctx.join('.length;
    return assertNoFix(
      code,
      '[[ctx.onDispose(db.close)]]',
      alsoExpected: [
        error(diag.notEnoughPositionalArgumentsNameSingular, close, 1),
      ],
    );
  }
}
