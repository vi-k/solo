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

  // cancellation.md of solo: close() awaited from the job's cleanup waits
  // the same way.
  Future<void> test_cleanup() => assertAt(
    '''
$_syncer
  Job<void> logout() => enqueue<int, void>((ctx) async {
    ctx.onDispose(() async {
      await close();
    });
  });
}
''',
    ['await [[close()]]'],
  );

  Future<void> test_body_returns_the_job() => assertAt(
    '''
$_syncer
  Job<String> again(int item) =>
      enqueue<int, String>((ctx) => sync(item).value);
}
''',
    ['(ctx) => [[sync(item)]]'],
  );

  Future<void> test_body_queued_on_another_controller() => assertAt('''
$_syncer
  late final Syncer other;

  Job<void> relay(int item) => other.enqueue<int, void>((ctx) async {
    await sync(item).value;
  });
}
''', []);

  Future<void> test_mixin_on_solo() => assertAt(
    '''
import 'package:solo/solo.dart';

mixin Steps on Solo<int> {
  Job<String> sync(int item) =>
      enqueueJob(job<int, String>((ctx) async => 'x'));

  Job<void> twice(int item) => enqueue<int, void>((ctx) async {
    await sync(item).value;
  });
}
''',
    ['await [[sync(item)]]'],
  );

  Future<void> test_lane() => _assertLane(
    '''
$_feed
  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
  });
}
''',
    '_likes.enqueue<int, void>((ctx) async {})',
    'enqueue',
  );

  Future<void> test_another_lane() => assertAt('''
$_feed
  Job<void> reloadAndLike() => _reload.enqueue<int, void>((ctx) async {
    await _likes.enqueue<int, void>((ctx) async {}).done;
    await like().value;
  });
}
''', []);

  // The lane of a method is read in its body, the declared SoloJob too.
  Future<void> test_method_of_the_lane() => _assertLane(
    '''
$_feed
  Job<void> likeTwice() => _likes.enqueue<int, void>((ctx) async {
    await this.like().value;
    await reload().done;
  });
}
''',
    'this.like()',
    'like',
  );

  Future<void> test_job_from_a_parameter() => assertAt('''
$_feed
  Job<void> after(SoloJob<void> job) => _likes.enqueue<int, void>((ctx) async {
    await job.done;
  });
}
''', []);

  // A child runs in the lane of its parent and a handler in the lane of the
  // accumulator, neither seen at the body.
  Future<void> test_child_and_handler() => assertAt('''
$_feed
  late final _batch = _likes.collect<int, int, void>((ctx, events) async {
    await like().done;
  });

  Job<void> nested() => _likes.enqueue<int, void>((ctx) async {
    await ctx.run(ctx.child((child) async {
      await like().done;
    }));
  });
}
''', []);

  Future<void> test_body_queued_in_a_lane_of_another_controller() =>
      assertAt('''
$_feed
  late final Feed other;

  Job<void> relay() => other._likes.enqueue<int, void>((ctx) async {
    await like().done;
  });
}
''', []);

  // A getter is no lane field: which lane it gives is not seen.
  Future<void> test_lane_from_a_getter() => assertAt('''
$_feed
  SoloLane<int> get current => _likes;

  Job<void> likeTwice() => current.enqueue<int, void>((ctx) async {
    await current.enqueue<int, void>((ctx) async {}).done;
    await like().done;
  });

  Job<void> likeAgain() => _likes.enqueue<int, void>((ctx) async {
    await current.enqueue<int, void>((ctx) async {}).done;
  });
}
''', []);

  Future<void> test_close_of_lanes() => assertAt(
    '''
$_feed
  Job<void> stop() => _likes.enqueue<int, void>((ctx) async {
    await cancelAll();
    await this.close();
  });
}
''',
    ['cancelAll()', 'this.close()'],
  );

  Future<void> test_close_of_a_solo_stream() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Desk extends Solo<int> with SoloStream<int> {
  Desk() : super(0);

  Job<void> logout() => enqueue<int, void>((ctx) async {
    await close();
  });
}
''',
    ['await [[close()]]'],
  );

  Future<void> test_close_of_lanes_with_a_stream() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> with SoloStream<int> {
  Feed() : super(0) {
    _likes = lane('likes');
  }

  late final SoloLane<int> _likes;

  Job<void> logout() => _likes.enqueue<int, void>((ctx) async {
    await close();
  });
}
''',
    ['await [[close()]]'],
  );

  /// Asserts one diagnostic at [span], the first one awaited in [code],
  /// that names [member] and the lane `_likes`.
  Future<void> _assertLane(String code, String span, String member) =>
      assertDiagnostics(code, [
        lint(
          code.indexOf('await $span') + 'await '.length,
          span.length,
          messageContainsAll: ["'$member' waits", "the lane '_likes'"],
        ),
      ]);
}

/// A controller of two lanes, to be completed: `reload` queues in `_reload`
/// and `like` in `_likes`.
const _feed = '''
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
''';
