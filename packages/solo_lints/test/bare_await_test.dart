// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:solo_lints/src/rules/bare_await.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(BareAwaitTest);
  });
}

/// The calls a body waits for, plain or through its context.
const _api = '''
import 'dart:async';

import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

Future<void> reset() async {}

Stream<int> ticks() => Stream.value(1);

final class DeviceError implements Exception {}

final class Database {
  static Future<Database> open() async => Database();

  Future<void> close() async {}
}
''';

@reflectiveTest
class BareAwaitTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => BareAwait();

  Future<void> test_plain() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  await commit();
});
''',
    ['[[await]] commit()'],
  );

  Future<void> test_expression_body() => assertAt(
    '''
$_api
final job = Job<int>((ctx) async => await commit());
''',
    ['[[await]] commit()'],
  );

  Future<void> test_solo_body() => assertAt(
    '''
import 'package:solo/solo.dart';

Future<int> commit() async => 1;

final class Desk extends Solo<int> {
  Desk() : super(0);

  Job<void> save() => enqueue<int, void>((ctx) async {
    await commit();
  });
}
''',
    ['[[await]] commit()'],
  );

  Future<void> test_top_level_function() => assertAt(
    '''
$_api
Future<void> body(JobContext ctx) async {
  await commit();
}
''',
    ['[[await]] commit()'],
  );

  Future<void> test_delay() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  await Future<void>.delayed(const Duration(seconds: 1));
});
''',
    ['[[await]] Future'],
  );

  Future<void> test_dynamic() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final dynamic pending = commit();
  await pending;
});
''',
    ['[[await]] pending'],
  );

  Future<void> test_await_for() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  await for (final tick in ticks()) {
    print(tick);
  }
});
''',
    ['[[await]] for'],
  );

  Future<void> test_await_for_element() => assertAt(
    '''
$_api
final job = Job<List<int>>((ctx) async => [await for (final t in ticks()) t]);
''',
    ['[[await]] for'],
  );

  Future<void> test_conditional_with_a_plain_branch() => assertAt(
    '''
$_api
Job<int> load(bool fresh) => Job<int>((ctx) async {
  return await (fresh ? ctx.join(commit) : commit());
});
''',
    ['[[await]] (fresh'],
  );

  Future<void> test_future_wait_with_a_plain_part() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  await Future.wait([ctx.join(commit), commit()]);
});
''',
    ['[[await]] Future'],
  );

  Future<void> test_variable_not_final() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  var pending = ctx.join(commit);
  pending = commit();
  await pending;
});
''',
    ['[[await]] pending'],
  );

  Future<void> test_release_of_another_value() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final kept = await ctx.join(Database.open);
  final other = await ctx.join(Database.open);
  ctx.disown(kept);
  await other.close();
});
''',
    ['[[await]] other'],
  );

  Future<void> test_release_before_disown() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final database = await ctx.join(Database.open);
  await database.close();
  ctx.disown(database);
});
''',
    ['[[await]] database'],
  );

  Future<void> test_context_members() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  await ctx.join(commit);
  await ctx.abandonable(commit);
  await ctx.uncancellable(commit);
  await ctx.pause(const Duration(seconds: 1));
  await ctx.run(Job.deferred<int>((c) => c.join(commit)));
  await ctx.runAll([Job.deferred<int>((c) => c.join(commit))]);
});
''', []);

  Future<void> test_children() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  final counting = ctx.each(ticks(), (c, tick) => c.join(commit));
  await ctx.pause();
  await counting.cancel();
  await counting.done;
  await ctx.each(ticks(), (c, tick) => c.join(commit)).value;
  final rows = ctx.child((c) => c.join(commit));
  ctx.start(rows);
  await rows.value;
});
''', []);

  Future<void> test_child_replaced_after_start() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  var rows = ctx.child((child) => child.join(commit));
  ctx.start(rows);
  rows = ctx.child((child) => child.join(commit));
  await rows.value;
});
''',
    ['[[await]] rows.value'],
  );

  Future<void> test_unstarted_child() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final rows = ctx.child((c) => c.join(commit));
  await rows.value;
});
''',
    ['[[await]] rows'],
  );

  // The SDK of the analyzer tests has no `wait` of `dart:async` on lists and
  // records, so the fixture declares both.
  Future<void> test_together() => assertAt('''
$_api
extension<T> on Iterable<Future<T>> {
  Future<List<T>> get wait => Future.wait(this);
}

extension<A, B> on (Future<A>, Future<B>) {
  Future<(A, B)> get wait async => (await \$1, await \$2);
}

final job = Job<void>((ctx) async {
  await Future.wait([ctx.join(commit), ctx.abandonable(commit)]);
  await [ctx.join(commit), ctx.join(commit)].wait;
  await (ctx.join(commit), ctx.abandonable(reset)).wait;
});
''', []);

  Future<void> test_conditional_and_final_local() => assertAt('''
$_api
Job<int> load(bool fresh) => Job<int>((ctx) async {
  final pending = fresh ? ctx.join(commit) : ctx.abandonable(commit);
  return await pending;
});
''', []);

  Future<void> test_hands_over_the_context() => assertAt('''
$_api
Future<int> inIsolate(JobContext ctx, int Function() work) =>
    ctx.join(() async => work());

Future<int> named({required JobContext ctx}) => ctx.join(commit);

final job = Job<int>((ctx) async {
  await named(ctx: ctx);
  return await inIsolate(ctx, () => 1);
});
''', []);

  Future<void> test_release_after_disown() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  final database = await ctx.join(
    Database.open,
    dispose: (database) => database.close(),
  );
  ctx.disown(database);
  await database.close();
});
''', []);

  Future<void> test_not_a_future() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  await null;
  await 42;
});
''', []);

  Future<void> test_catch_and_finally() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  try {
    await ctx.join(commit);
  } on Object {
    ctx.check();
    await reset();
    rethrow;
  } finally {
    await reset();
  }
});
''', []);

  Future<void> test_nested_functions() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  await ctx.join(() async {
    final receipt = await commit();
    print(receipt);
  });
  await ctx.uncancellable(() async {
    await commit();
    await reset();
  });
  ctx.onDispose(() async {
    await reset();
  });
  ctx.unattended(() async {
    await reset();
  });
});
''', []);

  Future<void> test_not_cancellable() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  await commit();
}, cancellable: false);
''', []);

  Future<void> test_hands_over_to_an_object() => assertAt(
    '''
$_api
Future<void> track(Object anything) async {}

final job = Job<void>((ctx) async {
  await track(ctx);
});
''',
    ['[[await]] track'],
  );

  Future<void> test_release_later_than_disown() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final database = await ctx.join(Database.open);
  ctx.disown(database);
  print(database);
  await database.close();
});
''',
    ['[[await]] database'],
  );

  Future<void> test_release_after_disown_in_a_condition() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  final database = await ctx.join(Database.open);
  if (ctx.disown(database)) await database.close();
  if (ctx.disown(database)) {
    await database.close();
  }
});
''', []);

  Future<void> test_release_after_disown_in_a_cascade() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  final database = await ctx.join(Database.open);
  ctx
    ..check()
    ..disown(database);
  await database.close();
});
''', []);

  Future<void> test_retry_delay_in_a_catch() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(commit);
      return;
    } on DeviceError {
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
});
''',
    ['[[await]] Future'],
  );

  Future<void> test_broad_catch_that_goes_on() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  try {
    await ctx.join(commit);
  } on Object {
    await reset();
  }
  await for (final tick in ticks()) {
    print(tick);
  }
});
''',
    ['[[await]] reset', '[[await]] for'],
  );

  Future<void> test_await_for_in_a_catch() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  try {
    await ctx.join(commit);
  } on DeviceError {
    await for (final tick in ticks()) {
      print(tick);
    }
  }
});
''',
    ['[[await]] for'],
  );

  Future<void> test_catch_that_handles_a_cancellation() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  try {
    await ctx.join(commit);
  } on Cancelled {
    await reset();
    return;
  } on Object {
    ctx.check();
    await reset();
    rethrow;
  }
});
''', []);

  // A check hears a cancellation that has come, not one that comes during
  // the wait after it; a narrow catch does not take a cancellation, so its
  // release waits as the body does.
  Future<void> test_catch_that_lets_a_cancellation_wait() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(commit);
      return;
    } on DeviceError {
      await reset();
      rethrow;
    } on Exception {
      if (ctx.job.isCancelled) rethrow;
      await reset();
    } on Object {
      ctx.check();
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
});
''',
    ['[[await]] reset', '[[await]] reset', '[[await]] Future'],
  );

  Future<void> test_wildcard_context() async {
    const code =
        '''
$_api
final job = Job<void>((_) async {
  await commit();
});
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('await'),
        'await'.length,
        messageContainsAll: ["through 'ctx'"],
      ),
    ]);
  }

  Future<void> test_context_of_the_parent() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  await ctx.each(ticks(), (child, tick) async {
    await ctx.join(commit);
  }).value;
});
''',
    ['[[await]] ctx.join(commit);'],
  );

  Future<void> test_hidden_futures() => assertAt(
    '''
$_api
Job<void> wait<F extends Future<void>>(F pending) => Job<void>((ctx) async {
  await pending;
  final Object saving = commit();
  await saving;
});
''',
    ['[[await]] pending', '[[await]] saving'],
  );

  // A variable read in its own initializer is an error, but the editor
  // analyzes the code while it is typed, so the rule must not loop on it.
  Future<void> test_read_in_its_own_initializer() async {
    const code =
        '''
$_api
final job = Job<void>((ctx) async {
  late final Future<void> pending = pending;
  await pending;
});
''';
    testFile.writeAsStringSync(code);
    result = await resolveFile(testFile.path);
    assertDiagnosticsIn(
      [
        for (final diagnostic in result.diagnostics)
          if (diagnostic.diagnosticCode is LintCode) diagnostic,
      ],
      [lint(code.indexOf('await pending;'), 'await'.length)],
    );
  }

  Future<void> test_body_declared_at_the_top_level() => assertAt('''
$_api
const refuse = false;

Future<void> backup(JobContext ctx) async {
  await commit();
}

final first = Job<void>(backup, cancellable: false);

final second = Job<void>((ctx) async {
  await commit();
}, cancellable: refuse);
''', []);

  Future<void> test_body_declared_at_the_top_level_and_passed_twice() =>
      assertAt(
        '''
$_api
Future<void> backup(JobContext ctx) async {
  await commit();
}

final first = Job<void>(backup, cancellable: false);

final second = Job<void>(backup);
''',
        ['[[await]] commit()'],
      );

  Future<void> test_collection_elements() => assertAt('''
$_api
Job<void> runAll(List<ChildJob<int>> jobs) => Job<void>((ctx) async {
  await Future.wait([
    for (final job in jobs) ctx.run(job),
    if (jobs.isEmpty) ctx.join(commit),
  ]);
  await Future.wait(<Future<void>>[]);
});
''', []);

  Future<void> test_prefixed_future() => assertAt('''
import 'dart:async' as async;

import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

final job = Job<void>((ctx) async {
  await async.Future.wait([ctx.join(commit)]);
});
''', []);

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
