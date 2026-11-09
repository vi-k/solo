// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:async_job_lints/src/rules/outcome_after_await.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(OutcomeAfterAwaitTest);
  });
}

/// Jobs to make and calls to wait for.
const _api = '''
import 'dart:async';

import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

Stream<int> ticks() => Stream.value(1);

Job<int> load() => Job<int>((ctx) => ctx.join(commit));

Future<Job<int>> loadLater() async => load();

final Job<int> current = load();

void keep(Object job) {}
''';

@reflectiveTest
class OutcomeAfterAwaitTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => OutcomeAfterAwait();

  Future<void> test_done() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_value() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  print(await job.value);
}
''',
    ['job.[[value]])'],
  );

  Future<void> test_ignore_failure() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  job.ignoreFailure();
}
''',
    ['job.[[ignoreFailure]]()'],
  );

  Future<void> test_then() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  final next = job.then((ctx, value) => value + 1);
  print(await next.value);
}
''',
    ['job.[[then]]('],
  );

  Future<void> test_shared() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  final handle = job.shared();
  print(await handle.value);
}
''',
    ['job.[[shared]]()'],
  );

  Future<void> test_message_names_the_member() async {
    await assertAt(
      '''
$_api
Future<void> run() async {
  final job = load();
  await commit();
  job.ignoreFailure();
}
''',
      ['job.[[ignoreFailure]]()'],
    );
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.message, contains("reads 'ignoreFailure()'"));
    expect(diagnostic.correctionMessage, contains('after the job is made'));
  }

  Future<void> test_await_for() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await for (final tick in ticks()) {
    print(tick);
  }
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_yield() => assertAt(
    '''
$_api
Stream<int> run() async* {
  final job = load();
  yield 1;
  yield await job.value;
}
''',
    ['job.[[value]];'],
  );

  // The action of a waiting call runs when the call is made, so the read in
  // it comes after the wait above.
  Future<void> test_action_of_a_waiting_call() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final inner = load();
  await ctx.join(commit);
  await ctx.abandonable(() => inner.value);
});
''',
    ['inner.[[value]])'],
  );

  Future<void> test_started_later() => assertAt(
    '''
$_api
Future<void> run() async {
  final child = Job.deferred<int>((ctx) => ctx.join(commit));
  await commit();
  child.start();
  await commit();
  print(await child.done);
}
''',
    ['child.[[done]])'],
  );

  Future<void> test_started_later_message() async {
    await assertAt(
      '''
$_api
Future<void> run() async {
  final child = Job.deferred<int>((ctx) => ctx.join(commit));
  child.start();
  await commit();
  print(await child.value);
}
''',
      ['child.[[value]])'],
    );
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.correctionMessage, contains("after 'start()'"));
    expect(diagnostic.correctionMessage, contains('child.value'));
  }

  Future<void> test_cancel_of_another_job() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  final other = load();
  await other.cancel();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_members_that_do_not_observe() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  job.whenFinished((outcome) {});
  job.whenCancelled((cancelled) {});
  print(job.isRunning);
  print(job.isFinished);
  print(job.isCancelled);
  print(job.outcome);
  print(job.key);
  print(job.describe());
  print(job.level);
  print(job.isChild);
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_observed_early() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  final outcome = job.done;
  await commit();
  print(await outcome);
  print(await job.done);
}
''', []);

  Future<void> test_no_wait_between() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  print(await job.done);
}
''', []);

  Future<void> test_cancel_of_the_same_job() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  await job.cancel();
  print(await job.done);
}
''', []);

  Future<void> test_started_after_the_wait() => assertAt('''
$_api
Future<void> run() async {
  final child = Job.deferred<int>((ctx) => ctx.join(commit));
  await commit();
  child.start();
  print(await child.done);
}
''', []);

  Future<void> test_solo_job_not_queued_yet() => assertAt('''
import 'package:solo/solo.dart';

Future<int> commit() async => 1;

final class Desk extends Solo<int> {
  Desk() : super(0);

  Future<void> save() async {
    final step = job<int, int>((ctx) => ctx.join(commit));
    await commit();
    step.ignoreFailure();
    enqueueJob(step);
  }
}
''', []);

  Future<void> test_enqueued_job() => assertAt(
    '''
import 'package:solo/solo.dart';

Future<int> commit() async => 1;

final class Desk extends Solo<int> {
  Desk() : super(0);

  Future<void> save() async {
    final step = enqueue<int, int>((ctx) => ctx.join(commit));
    await commit();
    print(await step.value);
  }
}
''',
    ['step.[[value]])'],
  );

  Future<void> test_late() => assertAt('''
$_api
Future<void> run() async {
  late final job = load();
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_before_the_wait() => assertAt(
    '''
$_api
Future<void> run() async {
  late final job = load();
  print(job.isRunning);
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_read_in_a_branch_that_returns() => assertAt('''
$_api
Future<void> run(bool fast) async {
  late final job = load();
  if (fast) {
    print(job.isRunning);
    return;
  }
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_the_other_branch() => assertAt('''
$_api
Future<void> run(bool peek) async {
  late final job = load();
  if (peek) {
    print(job.isRunning);
  } else {
    await commit();
    print(await job.done);
  }
}
''', []);

  Future<void> test_late_read_in_another_late_initializer() => assertAt('''
$_api
Future<void> run() async {
  late final job = load();
  late final running = job.isRunning;
  await commit();
  print(running);
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_short_circuit() => assertAt('''
$_api
Future<void> run(bool check) async {
  late final job = load();
  if (check && job.isRunning) return;
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_condition() => assertAt(
    '''
$_api
Future<void> run() async {
  late final job = load();
  if (!job.isRunning) return;
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_read_in_an_initializer() => assertAt(
    '''
$_api
Future<void> run() async {
  late final job = load();
  final running = job.isRunning;
  await commit();
  print(running);
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_read_in_a_named_argument() => assertAt(
    '''
$_api
void log({required bool running}) {}

Future<void> run() async {
  late final job = load();
  log(running: job.isRunning);
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_read_in_a_null_aware_call() => assertAt('''
$_api
class Log {
  void put(bool running) {}
}

Future<void> run(Log? log) async {
  late final job = load();
  log?.put(job.isRunning);
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_null_aware_property_assignment() =>
      assertAt('''
$_api
class Log {
  bool flag = false;
  int count = 0;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log? log, List<bool>? list) async {
  late final job = load();
  log?.flag = job.isRunning;
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_null_aware_index_assignment() => assertAt('''
$_api
class Log {
  bool flag = false;
  int count = 0;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log? log, List<bool>? list) async {
  late final job = load();
  list?[0] = job.isRunning;
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_null_aware_compound_assignment() =>
      assertAt('''
$_api
class Log {
  bool flag = false;
  int count = 0;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log? log, List<bool>? list) async {
  late final job = load();
  log?.count += job.isRunning ? 1 : 0;
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_after_a_null_assertion_in_a_chain() =>
      assertAt('''
$_api
class Log {
  bool flag = false;
  int count = 0;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log? log, List<bool>? list) async {
  late final job = load();
  log?.inner!.put(job.isRunning);
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_late_read_in_a_property_assignment() => assertAt(
    '''
$_api
class Log {
  bool flag = false;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log log) async {
  late final job = load();
  log.flag = job.isRunning;
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_read_after_a_null_assertion() => assertAt(
    '''
$_api
class Log {
  bool flag = false;
  Log? inner;
  void put(bool running) {}
}

Future<void> run(Log log) async {
  late final job = load();
  log.inner!.put(job.isRunning);
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_late_made_after_the_wait() => assertAt('''
$_api
Future<void> run() async {
  late final job = load();
  await commit();
  print(job.isRunning);
  print(await job.done);
}
''', []);

  Future<void> test_cancel_does_not_observe() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await job.cancel();
  await commit();
  print(await job.done);
}
''',
    ['job.[[done]])'],
  );

  Future<void> test_returned() => assertAt('''
$_api
Future<Job<int>> run() async {
  final job = load();
  if (job.isRunning) return job;
  await commit();
  print(await job.done);
  return job;
}
''', []);

  Future<void> test_collection_element() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  final jobs = [job];
  await commit();
  print(await job.done);
  print(jobs);
}
''', []);

  Future<void> test_interpolated() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  print('\$job');
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_passed_on() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  keep(job);
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_captured() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  void show() => print(job.isRunning);
  show();
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_reassigned() => assertAt('''
$_api
Future<void> run() async {
  var job = load();
  job = load();
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_read_not_made() => assertAt('''
$_api
Future<void> run() async {
  final job = current;
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_cascade() => assertAt('''
$_api
Future<void> run() async {
  final job = load()..ignoreFailure();
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_awaited_initializer() => assertAt('''
$_api
Future<void> run() async {
  final job = await loadLater();
  await commit();
  print(await job.done);
}
''', []);

  Future<void> test_wait_in_another_function() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  final later = () async {
    await commit();
  };
  print(later);
  print(await job.done);
}
''', []);

  Future<void> test_yield_in_a_sync_generator() => assertAt('''
$_api
Iterable<int> run() sync* {
  final job = load();
  yield 1;
  job.ignoreFailure();
}
''', []);

  Future<void> test_not_a_job() => assertAt('''
$_api
Future<void> run() async {
  final pending = commit();
  await commit();
  print(await pending);
}
''', []);
}
