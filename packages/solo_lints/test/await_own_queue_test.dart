// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/await_own_queue.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AwaitOwnQueueTest);
  });
}

/// The pairs of methods of the children page: `_sync` and `_recordPath` make
/// a job and start nothing, `sync` and `recordPath` queue it.
const _syncer = r'''
import 'package:solo/solo.dart';

final class Syncer extends Solo<int> {
  Syncer() : super(0);

  SoloJob<String> _sync(int item) => job<int, String>((ctx) async => '$item');

  Job<String> sync(int item) => enqueueJob(_sync(item));

  SoloJob<void> _recordPath(String path) => job<int, void>((ctx) async {});

  Job<void> recordPath(String path) => enqueueJob(_recordPath(path));
''';

@reflectiveTest
class AwaitOwnQueueTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => AwaitOwnQueue();

  Future<void> test_mistakes_page_wrong() => assertAt(
    '''
$_syncer
  Job<void> syncAndRecord(int item) => enqueue<int, void>((ctx) async {
    final path = await sync(item).value;
    await recordPath(path).value;
  });
}
''',
    ['await [[sync(item)]]', 'await [[recordPath(path)]]'],
  );

  Future<void> test_mistakes_page_right() => assertAt('''
$_syncer
  Job<void> syncAndRecord(int item) => enqueue<int, void>((ctx) async {
    final path = await ctx.run(_sync(item));
    await ctx.run(_recordPath(path));
  });
}
''', []);

  Future<void> test_unstarted_job() => assertAt(
    '''
$_syncer
  Job<void> syncTwice(int item) => enqueue<int, void>((ctx) async {
    await this._sync(item).done;
  });
}
''',
    ['await [[this._sync(item)]]'],
  );

  Future<void> test_close_and_cancel_all() => assertAt(
    '''
$_syncer
  Job<void> stop() => enqueue<int, void>((ctx) async {
    await cancelAll();
    await this.close();
  });
}
''',
    ['cancelAll()', 'this.close()'],
  );

  Future<void> test_actions_the_body_waits_for() => assertAt(
    '''
$_syncer
  Job<void> syncAll(int item) => enqueue<int, void>((ctx) async {
    await ctx.join(() => sync(item).value);
    await ctx.abandonable(() async {
      return recordPath('').done;
    });
    ctx.unattended(() async {
      await sync(item).done;
    });
  });
}
''',
    ['=> [[sync(item)]].value', "return [[recordPath('')]]"],
  );

  Future<void> test_method_with_a_block_body() => assertAt(
    '''
$_syncer
  Job<int> count() {
    return enqueue<int, int>((ctx) async => 1);
  }

  Job<void> countTwice() => enqueue<int, void>((ctx) async {
    await count().value;
  });
}
''',
    ['await [[count()]]'],
  );

  Future<void> test_core_job_starts_at_once() => assertAt('''
$_syncer
  Job<int> tick() => Job((ctx) async => 1);

  Job<void> ticks() => enqueue<int, void>((ctx) async {
    await tick().value;
  });

  Job<void> outside() => Job((ctx) async {
    await sync(1).value;
  });
}
''', []);

  Future<void> test_another_controller() => assertAt('''
$_syncer
  late final Syncer other;

  Job<void> syncOther(int item) => enqueue<int, void>((ctx) async {
    await other.sync(item).value;
    await other.close();
  });
}
''', []);

  Future<void> test_getter() => assertAt('''
$_syncer
  SoloJob<String> get first => _sync(1);

  Job<void> syncFirst() => enqueue<int, void>((ctx) async {
    await first.value;
  });
}
''', []);
}
