// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/src/rules/bare_await.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(BareAwaitTest);
    defineReflectiveTests(BareAwaitOwnQueueReportedElsewhereTest);
    defineReflectiveTests(BareAwaitOwnLaneReportedElsewhereTest);
    defineReflectiveTests(BareAwaitOwnLaneAloneTest);
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

class Host {
  late final ChildJob<int> rows;

  Job<void> work() => Job<void>((ctx) async {
    rows = ctx.child((c) => c.join(commit));
    ctx.start(rows);
    await rows.value;
  });
}
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

Future<void> body(JobContext ctx, [ChildJob<int>? rows]) async {
  rows = ctx.child((child) => child.join(commit));
  ctx.start(rows);
  rows = ctx.child((child) => child.join(commit));
  await rows.value;
}

final second = Job<void>(body);

class Host {
  late ChildJob<int> rows;

  Job<void> work() => Job<void>((ctx) async {
    rows = ctx.child((child) => child.join(commit));
    ctx.start(rows);
    rows = ctx.child((child) => child.join(commit));
    await rows.value;
  });
}

ChildJob<int> get fresh => throw 0;

final third = Job<void>((ctx) async {
  ctx.start(fresh);
  await fresh.value;
});
''',
    [
      '[[await]] rows.value',
      '[[await]] rows.value',
      '[[await]] rows.value',
      '[[await]] fresh.value',
    ],
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
  try {
    await ctx.join(commit);
  } catch (_) {
    for (var i = 0; i < 2; i++) {
      if (i == 1) break;
      await reset();
    }
    rethrow;
  }
  try {
    await ctx.join(commit);
  } on Exception {
    void skip() {
      return;
    }

    skip();
    await reset();
    rethrow;
  }
  try {
    await ctx.join(commit);
  } on Outcome<Object?> {
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

  // A catch that ends in `rethrow;` but goes on before it, by `continue` or
  // `return`, waits on the way there, not on the way out.
  Future<void> test_catch_that_goes_on_before_rethrow() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(commit);
      return;
    } on Object {
      ctx.check();
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt));
        continue;
      }
      rethrow;
    }
  }
});

final fallback = Job<int>((ctx) async {
  try {
    return await ctx.join(commit);
  } on Exception {
    if (!ctx.job.isCancelled) {
      await reset();
      return 0;
    }
    rethrow;
  }
});
''',
    ['[[await]] Future', '[[await]] reset'],
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

  // Nothing else reports this deadlock unless a plugin on top says so.
  Future<void> test_own_queue() => assertAt(_ownQueue, ['[[await]] close()']);

  Future<void> test_lanes() => assertAt(_lanes, _lanesAwaits);
}

/// A wait for a job of the controller's own queue.
const _ownQueue = '''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> {
  Desk() : super(0);

  Job<void> logout() => enqueue<int, void>((ctx) async {
    await close();
  });
}
''';

@reflectiveTest
class BareAwaitOwnQueueReportedElsewhereTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest =>
      BareAwait(ownQueueReportedElsewhere: true);

  Future<void> test_own_queue() => assertAt(_ownQueue, []);

  // A plugin of the old API leaves a wait for a lane to bare_await: its rule
  // of the own queue does not see the lanes.
  Future<void> test_lanes() => assertAt(_lanes, _lanesAwaits);

  // The close of a SoloStream mixed into a Solo is the controller's own.
  Future<void> test_close_of_a_solo_stream() => assertAt(_soloStream, []);

  // The answer of 0.2.0: a wait for the own queue of a Solo is left to the
  // plugin on top from any body, though await_own_queue reports it only from
  // a body queued here. Reporting it here would add diagnostics in a patch.
  Future<void> test_own_queue_from_bodies_not_queued_here() =>
      assertAt(_ownQueueElsewhere, []);
}

/// Waits for the own queue of a `Solo` from bodies it does not queue: one
/// given to another controller, one of a core job and one that takes a
/// `JobContext`.
const _ownQueueElsewhere = '''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> {
  Desk() : super(0);

  late final Desk other;

  Job<void> relay() => other.enqueue<int, void>((ctx) async {
    await close();
  });

  Job<void> later() => Job<void>((ctx) async {
    await close();
  });

  Job<void> plain() => enqueue<int, void>((JobContext ctx) async {
    await close();
  });
}
''';

/// Every wait of [_ownQueueElsewhere].
const _ownQueueElsewhereAwaits = [
  '[[await]] close()',
  '[[await]] close()',
  '[[await]] close()',
];

/// `bare_await` with only the lane left to another rule: the own queue of a
/// `Solo` is still its own to report.
@reflectiveTest
class BareAwaitOwnLaneAloneTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest =>
      BareAwait(ownLaneReportedElsewhere: true);

  Future<void> test_own_queue() => assertAt(_ownQueue, ['[[await]] close()']);

  Future<void> test_own_queue_from_bodies_not_queued_here() =>
      assertAt(_ownQueueElsewhere, _ownQueueElsewhereAwaits);
}

/// Waits from a body of the lane `_likes`: for a job of the other lane, then
/// for jobs of its own lane through a method and directly, then for `close`.
const _lanes = '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  late final SoloLane<int> _reload;
  late final SoloLane<int> _likes;

  Job<void> reload() => _reload.enqueue<int, void>((ctx) async {});

  SoloJob<void> like() => _likes.enqueue<int, void>((ctx) async {});

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await reload().done;
    await like().done;
    await _likes.enqueue<int, void>((ctx) async {}).done;
    await close();
  });
}
''';

/// Every wait of [_lanes].
const _lanesAwaits = [
  '[[await]] reload()',
  '[[await]] like()',
  '[[await]] _likes',
  '[[await]] close()',
];

/// A close of a `Solo` with `SoloStream` awaited from its body.
const _soloStream = '''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> with SoloStream<int> {
  Desk() : super(0);

  Job<void> logout() => enqueue<int, void>((ctx) async {
    await close();
  });
}
''';

/// `bare_await` as solo_lints registers it: both the own queue and the own
/// lane are reported by `await_own_queue`.
@reflectiveTest
class BareAwaitOwnLaneReportedElsewhereTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => BareAwait(
    ownQueueReportedElsewhere: true,
    ownLaneReportedElsewhere: true,
  );

  Future<void> test_own_queue() => assertAt(_ownQueue, []);

  // Only the wait for the other lane is left: it is no deadlock, and the
  // cancellation of the job does not reach it.
  Future<void> test_lanes() => assertAt(_lanes, ['[[await]] reload()']);

  // A body queued in a lane of another controller is not this one's:
  // await_own_queue does not report it, so bare_await does.
  Future<void> test_close_from_a_lane_of_another_controller() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  late final SoloLane<int> _likes;

  late final Feed other;

  Job<void> relay() => other._likes.enqueue<int, void>((ctx) async {
    await close();
  });
}
''',
    ['[[await]] close()'],
  );

  // The answer of 0.2.0, as with bare_await alone.
  Future<void> test_own_queue_from_bodies_not_queued_here() =>
      assertAt(_ownQueueElsewhere, []);

  // A lane the controller does not declare by lane(...) is not seen as its
  // own, even waited from a body queued in it: bare_await reports both waits.
  Future<void> test_injected_lane() =>
      assertAt(_injectedLane, ['[[await]] close()', '[[await]] _audit']);

  // In a Solo the close is the own queue's and left as 0.2.0 left it; the
  // job of the injected lane is reported, as 0.2.0 reported it.
  Future<void> test_injected_lane_of_a_solo() =>
      assertAt(_injectedLaneOfASolo, ['[[await]] foreign']);

  // A field a second constructor takes from outside may hold another
  // controller's lane, though one constructor declares it: bare_await reports
  // the wait, as 0.2.0 does.
  Future<void> test_lane_also_taken_by_a_constructor() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  Feed.shared(this._likes) : super(0);

  late SoloLane<int> _likes;

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    ['[[await]] _likes'],
  );

  // A method that queues in one lane on one path and in another on a second
  // has no lane that is seen: the wait is reported as any other.
  Future<void> test_method_queueing_in_two_lanes() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  late final SoloLane<int> _reload;
  late final SoloLane<int> _likes;

  Job<void> pick(bool first) {
    if (first) {
      return _likes.enqueue<int, void>((ctx) async {});
    }
    return _reload.enqueue<int, void>((ctx) async {});
  }

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await pick(true).done;
  });
}
''',
    ['[[await]] pick(true)'],
  );

  // A field with an initializer is written by it, so a declaration in a
  // constructor does not make it the controller's own lane.
  Future<void> test_lane_field_with_an_initializer() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  static late final SoloLane<int> shared;

  SoloLane<int> _likes = shared;

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    ['[[await]] _likes'],
  );

  // The same for a field a constructor sets in its initializer list.
  Future<void> test_lane_also_set_by_an_initializer() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  Feed.shared(SoloLane<int> lane) : _likes = lane, super(0);

  late SoloLane<int> _likes;

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    ['[[await]] _likes'],
  );

  // The same for a field a setter writes.
  Future<void> test_lane_also_set_by_a_setter() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  late SoloLane<int> _likes;

  set likes(SoloLane<int> value) {
    _likes = value;
  }

  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    ['[[await]] _likes'],
  );

  // A getter is no lane field: which lane it gives is not seen.
  Future<void> test_lane_from_a_getter() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  late final SoloLane<int> _likes;

  SoloLane<int> get current => _likes;

  Job<void> likeTwice() => current.enqueue<int, void>((ctx) async {
    await current.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    ['[[await]] current'],
  );

  Future<void> test_lane_of_a_job_from_a_parameter() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  late final SoloLane<int> _likes;

  Job<void> after(SoloJob<void> job) => _likes.enqueue<int, void>((ctx) async {
    await job.done;
  });
}
''',
    ['[[await]] job.done'],
  );
}

/// A `SoloLanes` with a lane it takes rather than declares, waited from a
/// body queued in that lane.
const _injectedLane = '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed(this._audit) : super(0) {
    _likes = lane('likes');
  }

  final SoloLane<int> _audit;
  late final SoloLane<int> _likes;

  SoloJob<void> like() => _likes.enqueue<int, void>((ctx) async {});

  Job<void> record() => _audit.enqueue<int, void>((ctx) async {
    await close();
    await _audit.enqueue<int, void>((ctx) async {}).done;
  });
}
''';

/// A `Solo` with an injected lane, waited from a body queued in it.
const _injectedLaneOfASolo = '''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> {
  Desk(this.foreign) : super(0);

  final SoloLane<int> foreign;

  Job<void> record() => foreign.enqueue<int, void>((ctx) async {
    await close();
    await foreign.enqueue<int, void>((ctx) async {}).done;
  });
}
''';
