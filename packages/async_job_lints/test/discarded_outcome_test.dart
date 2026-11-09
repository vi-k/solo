// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:async_job_lints/src/rules/discarded_outcome.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DiscardedOutcomeTest);
  });
}

/// A job to wait for, and a callback that takes a `Future<void>` function.
const _api = '''
import 'dart:async';

import 'package:async_job/async_job.dart';

Future<int> commit() async => 1;

Job<int> load() => Job<int>((ctx) => ctx.join(commit));

Future<Outcome<int>> loadOutcome() => load().done;

void refresh(Future<void> Function() action) {}

void refreshNamed({required Future<void> Function() onRefresh}) {}

class Indicator {
  Indicator({required Future<void> Function() onRefresh});
}
''';

@reflectiveTest
class DiscardedOutcomeTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => DiscardedOutcome();

  Future<void> test_await_done() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await job.done;
}
''',
    ['await job.[[done]];'],
  );

  Future<void> test_done_without_await() => assertAt(
    '''
$_api
void run() {
  final job = load();
  job.done;
}
''',
    ['  job.[[done]];'],
  );

  Future<void> test_parenthesized() => assertAt(
    '''
$_api
Future<void> run() async {
  await (load().done);
}
''',
    ['await (load().[[done]]);'],
  );

  Future<void> test_chain() => assertAt(
    '''
$_api
Future<void> run() async {
  await Job<int>((ctx) => ctx.join(commit)).done;
}
''',
    ['commit)).[[done]];'],
  );

  // The type, not the name: a wrapper drops the same outcome the same way.
  Future<void> test_wrapper() => assertAt(
    '''
$_api
Future<void> run() async {
  await loadOutcome();
}
''',
    ['await [[loadOutcome()]];'],
  );

  Future<void> test_waiting_call_action() => assertAt(
    '''
$_api
final job = Job<void>((ctx) async {
  final other = load();
  await ctx.abandonable(() => other.done);
});
''',
    ['await [[ctx.abandonable(() => other.done)]];'],
  );

  Future<void> test_returned_into_future_void() => assertAt(
    '''
$_api
Future<void> reload() => load().done;
''',
    ['reload() => load().[[done]];'],
  );

  Future<void> test_return_statement_into_future_void() => assertAt(
    '''
$_api
Future<void> reload() {
  return load().done;
}
''',
    ['return load().[[done]];'],
  );

  Future<void> test_returned_into_a_callback() => assertAt(
    '''
$_api
void run() {
  refresh(() => load().done);
}
''',
    ['() => load().[[done]])'],
  );

  Future<void> test_returned_into_a_named_callback() => assertAt(
    '''
$_api
void run() {
  refreshNamed(onRefresh: () => load().done);
}
''',
    ['() => load().[[done]])'],
  );

  Future<void> test_returned_from_a_block_into_a_named_callback() => assertAt(
    '''
$_api
void run() {
  refreshNamed(
    onRefresh: () {
      return load().done;
    },
  );
}
''',
    ['return load().[[done]];'],
  );

  Future<void> test_returned_into_a_named_constructor_argument() => assertAt(
    '''
$_api
void run() {
  Indicator(onRefresh: () => load().done);
}
''',
    ['() => load().[[done]])'],
  );

  Future<void> test_returned_into_a_typed_variable() => assertAt(
    '''
$_api
void run() {
  final Future<void> Function() reload = () => load().done;
  refresh(reload);
}
''',
    ['reload = () => load().[[done]];'],
  );

  Future<void> test_awaited_and_returned_into_future_void() => assertAt(
    '''
$_api
Future<void> reload() async => await load().done;
''',
    ['await load().[[done]];'],
  );

  Future<void> test_awaited_and_returned_into_a_callback() => assertAt(
    '''
$_api
void run() {
  refresh(() async => await load().done);
}
''',
    ['await load().[[done]])'],
  );

  Future<void> test_awaited_and_returned_as_an_outcome() => assertAt('''
$_api
Future<Outcome<int>> reload() async => await load().done;
''', []);

  // Outside a body the queue does not wait for itself, and the outcome is
  // still dropped.
  Future<void> test_controller_method() => assertAt(
    '''
import 'package:solo/solo.dart';

Future<int> commit() async => 1;

final class Desk extends Solo<int> {
  Desk() : super(0);

  Job<void> save() => enqueue<int, void>((ctx) async {
    await ctx.join(commit);
  });

  Future<void> logout() async {
    await save().done;
    await close();
  }
}
''',
    ['save().[[done]];'],
  );

  Future<void> test_outcome_read_later() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  await job.done;
  print(job.outcome);
}
''', []);

  Future<void> test_value_read_later() => assertAt('''
$_api
Future<void> run(Job<int> job) async {
  await job.done;
  print(await job.value);
}
''', []);

  Future<void> test_done_read_later() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await (job.done);
  await job.done;
}
''',
    ['await job.[[done]];'],
  );

  Future<void> test_read_later_after_a_waiting_call() => assertAt('''
$_api
final job = Job<void>((ctx) async {
  final other = load();
  await ctx.abandonable(() => other.done);
  print(other.outcome);
});
''', []);

  Future<void> test_read_before_does_not_count() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  print(job.outcome);
  await job.done;
}
''',
    ['await job.[[done]];'],
  );

  Future<void> test_ignore_failure_before() => assertAt('''
$_api
Future<void> run() async {
  final job = load();
  job.ignoreFailure();
  await job.done;
}
''', []);

  Future<void> test_ignore_failure_in_a_cascade() => assertAt('''
$_api
Future<void> run() async {
  final job = load()..ignoreFailure();
  await job.done;
}
''', []);

  Future<void> test_ignore_failure_after() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  await job.done;
  job.ignoreFailure();
}
''',
    ['await job.[[done]];'],
  );

  Future<void> test_ignore_failure_of_another_job() => assertAt(
    '''
$_api
Future<void> run() async {
  final job = load();
  final other = load()..ignoreFailure();
  await job.done;
  await other.done;
}
''',
    ['await job.[[done]];'],
  );

  // bare_await and await_own_queue name this wait already.
  Future<void> test_own_queue_in_a_body() => assertAt('''
import 'package:solo/solo.dart';

Future<int> commit() async => 1;

final class Desk extends Solo<int> {
  Desk() : super(0);

  Job<void> save() => enqueue<int, void>((ctx) async {
    await ctx.join(commit);
  });

  Job<void> logout() => enqueue<int, void>((ctx) async {
    await save().done;
  });
}
''', []);

  Future<void> test_outcome_kept() => assertAt('''
$_api
Future<void> run() async {
  final outcome = await load().done;
  print(outcome);
  final pending = load().done;
  print(await pending);
}
''', []);

  Future<void> test_returned_as_an_outcome() => assertAt('''
$_api
Future<Outcome<int>> reload() => load().done;

Future<Outcome<int>> again() async {
  return load().done;
}
''', []);

  Future<void> test_value_and_end() => assertAt('''
$_api
Future<void> run() async {
  await load().value;
  load().whenFinished((outcome) {});
}
''', []);

  Future<void> test_outcome_of_another_package() => assertAt('''
final class Outcome {}

Future<Outcome> fetch() async => Outcome();

Future<void> run() async {
  await fetch();
}
''', []);
}
