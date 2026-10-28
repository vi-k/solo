// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/fixes/add_check.dart';
import 'package:solo_lints/src/rules/catch_without_check.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fix_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddCheckFixTest);
  });
}

const _hardware = '''
import 'package:async_job/async_job.dart';

abstract interface class Hardware {
  Future<void> open();

  Future<void> reset();
}

late final Hardware hw;
''';

@reflectiveTest
class AddCheckFixTest extends FixTest {
  @override
  AbstractAnalysisRule get underTest => CatchWithoutCheck();

  @override
  ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  get producer => AddCheck.new;

  Future<void> test_on_object() => assertFix(
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } on Object catch (error) {
    await hw.reset();
    ctx.log(error);
  }
});
''',
    'on [[Object]] catch',
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } on Object catch (error) {
    ctx.check();
    await hw.reset();
    ctx.log(error);
  }
});
''',
  );

  Future<void> test_bare_catch() => assertFix(
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } catch (e) {
    await hw.reset();
  }
});
''',
    '} [[catch]] (e) {',
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } catch (e) {
    ctx.check();
    await hw.reset();
  }
});
''',
  );

  Future<void> test_empty_block() => assertFix(
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } on Object catch (_) {}
});
''',
    'on [[Object]] catch',
    '''
$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } on Object catch (_) {
    ctx.check();
  }
});
''',
  );

  Future<void> test_context_named_otherwise() => assertFix(
    '''
$_hardware
final job = Job<void>((c) async {
  try {
    await c.join(hw.open);
  } on Object {
    await hw.reset();
  }
});
''',
    'on [[Object]] {',
    '''
$_hardware
final job = Job<void>((c) async {
  try {
    await c.join(hw.open);
  } on Object {
    c.check();
    await hw.reset();
  }
});
''',
  );
}
