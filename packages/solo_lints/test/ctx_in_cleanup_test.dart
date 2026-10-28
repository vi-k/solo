// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/ctx_in_cleanup.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CtxInCleanupTest);
  });
}

const _core = '''
import 'package:async_job/async_job.dart';

abstract interface class Device {
  Future<void> flush();
}

late final Device device;
late final Stream<int> events;
''';

const _solo = '''
import 'package:solo/solo.dart';

final class Counter extends Solo<int> {
  Counter() : super(0);
''';

@reflectiveTest
class CtxInCleanupTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => CtxInCleanup();

  Future<void> test_join_in_on_dispose() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  ctx.onDispose(() async {
    await ctx.join(() => device.flush());
  });
});
''',
    ['ctx.join(() => device.flush())'],
  );

  Future<void> test_plain_await_in_on_dispose() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  ctx.onDispose(() async {
    await device.flush();
  });
});
''', []);

  Future<void> test_every_throwing_member() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  ctx.onDiscard(() async {
    ctx.check();
    await ctx.abandonable(device.flush);
    // ignore: deprecated_member_use
    await ctx.wait(device.flush);
    await ctx.uncancellable(device.flush);
    await ctx.pause();
    ctx.onCancel(() {});
    await ctx.run(ctx.child((_) async {}));
    await ctx.runAll([ctx.child((_) async {})]);
    ctx.start(ctx.child<void>((_) async {}));
    ctx.each(events, (_, _) {});
  });
});
''',
    [
      'ctx.check()',
      'ctx.abandonable(device.flush)',
      'ctx.wait(device.flush)',
      'ctx.uncancellable(device.flush)',
      'ctx.pause()',
      'ctx.onCancel(() {})',
      'ctx.run(ctx.child((_) async {}))',
      'ctx.runAll([ctx.child((_) async {})])',
      'ctx.start(ctx.child<void>((_) async {}))',
      'ctx.each(events, (_, _) {})',
    ],
  );

  Future<void> test_members_legal_in_cleanup() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  ctx.onDispose(() {
    ctx.onDispose(() {});
    ctx.onDiscard(() {});
    ctx.disown(device);
    ctx.log('flushing');
    ctx.unattended(device.flush);
  });
});
''', []);

  Future<void> test_release_of_a_waiting_call() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  await ctx.join(
    () => device,
    dispose: (device) => ctx.join(device.flush),
    discard: (device) async => ctx.check(),
  );
});
''',
    ['ctx.join(device.flush)', 'ctx.check()'],
  );

  Future<void> test_local_function_by_name() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  Future<void> flush() => ctx.join(device.flush);
  ctx.onDispose(flush);
});
''',
    ['ctx.join(device.flush)'],
  );

  Future<void> test_parent_context_in_child_cleanup() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  await ctx.run(
    ctx.child((child) async {
      child.onDispose(() => ctx.join(device.flush));
    }),
  );
});
''', []);

  Future<void> test_nested_cleanup_reported_once() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  ctx.onDispose(() {
    ctx.onDispose(ctx.check);
    ctx.onDiscard(() => ctx.check());
  });
});
''',
    ['ctx.check()'],
  );

  Future<void> test_waiting_member_outside_cleanup() => assertAt('''
$_core
final job = Job<void>((ctx) async {
  await ctx.join(device.flush);
  ctx.onDispose(device.flush);
});
''', []);

  Future<void> test_solo_members() => assertAt(
    '''
$_solo
  Job<void> count() => enqueue<int, void>((ctx) async {
    ctx.onDispose(() {
      ctx.emit(ctx.state + 1);
      ctx.stateAs<int>();
    });
  });
}
''',
    ['ctx.emit(ctx.state + 1)', 'ctx.state', 'ctx.stateAs<int>()'],
  );

  Future<void> test_closure_in_a_final_variable() => assertAt(
    '''
$_core
final job = Job<void>((ctx) async {
  final flush = () => ctx.check();
  ctx.onDispose(flush);
});
''',
    ['() => [[ctx.check()]]'],
  );
}
