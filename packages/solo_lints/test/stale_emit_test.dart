// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/stale_emit.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(StaleEmitTest);
  });
}

/// A state with what the jobs below write.
const _state = '''
import 'package:solo/solo.dart';

final class Feed {
  const Feed();

  Feed confirm(String post) => this;

  Feed withPosts(List<String> posts) => this;

  Feed get settled => this;

  Feed? get previous => this;
}

Future<void> send(String post) async {}

Future<Feed> fetchFeed() async => const Feed();

Future<List<String>> fetchPosts() async => const [];

Stream<String> posts() async* {}
''';

/// A controller of two lanes, to be completed.
const _feed =
    '''
$_state
final class Likes extends SoloLanes<Feed> {
  Likes() : super(const Feed()) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;
''';

@reflectiveTest
class StaleEmitTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => StaleEmit();

  Future<void> test_copy_read_before_the_wait() {
    const code =
        '''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.join(() => send(post));
    ctx.emit(feed.confirm(post));
  });
}
''';
    const span = 'ctx.emit(feed.confirm(post))';
    return assertDiagnostics(code, [
      lint(
        code.indexOf(span),
        span.length,
        messageContainsAll: ["'feed' was read from the state before"],
      ),
    ]);
  }

  // The first attempt of "A write that keeps the other lane's work" on the
  // lanes page of solo: the write before the wait keeps the copy fresh.
  Future<void> test_lanes_page_first_attempt() => assertAt(
    '''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    ctx.emit(feed.confirm('first'));
    await ctx.join(() => send(post));
    ctx.emit(feed.confirm('second'));
  });
}
''',
    ["ctx.emit(feed.confirm('second'))"],
  );

  Future<void> test_read_at_the_write() => assertAt('''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    ctx.emit(ctx.state.confirm(post));
    await ctx.join(() => send(post));
    ctx.emit(ctx.state.confirm(post));
  });
}
''', []);

  Future<void> test_read_after_the_last_wait() => assertAt('''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    await ctx.join(() => send(post));
    final feed = ctx.state;
    ctx.emit(feed.confirm(post));
  });
}
''', []);

  // A Solo has no other lane: only a child or externalSetState writes while
  // its job waits.
  Future<void> test_solo() => assertAt('''
$_state
final class Desk extends Solo<Feed> {
  Desk() : super(const Feed());

  Job<void> like(String post) => enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.join(() => send(post));
    ctx.emit(feed.confirm(post));
  });
}
''', []);

  // The answer of the server written whole loses the other lane's writes
  // too, and the rule does not see it: nothing in it was read from the
  // state.
  Future<void> test_answer_of_the_server() => assertAt('''
$_feed
  Job<void> reload() => _reload.enqueue<Feed, void>((ctx) async {
    ctx.emit(await ctx.abandonable(fetchFeed));
  });
}
''', []);

  // The message names the variable the read went to, not the one written
  // after the wait.
  Future<void> test_value_built_on_the_copy() => _assertMessage(
    '''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.join(() => send(post));
    final next = feed.confirm(post);
    ctx.emit((next.previous!.settled)..confirm(post));
  });
}
''',
    'ctx.emit((next.previous!.settled)..confirm(post))',
    "'feed' was read from the state before an 'await'",
  );

  Future<void> test_variable_read_again() => assertAt('''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    var feed = ctx.state;
    await ctx.join(() => send(post));
    feed = ctx.state;
    ctx.emit(feed.confirm(post));
  });
}
''', []);

  // The receiver is read before the argument is waited for.
  Future<void> test_wait_inside_the_write() => _assertMessage(
    '''
$_feed
  Job<void> reload() => _reload.enqueue<Feed, void>((ctx) async {
    ctx.emit(ctx.state.withPosts(await ctx.abandonable(fetchPosts)));
    ctx.emit(ctx.state.withPosts(const []));
  });
}
''',
    'ctx.emit(ctx.state.withPosts(await ctx.abandonable(fetchPosts)))',
    "'ctx.state' is read before the 'await' inside this 'emit'",
  );

  // The action of join runs at once, and the body suspends after it: a write
  // in the action comes before the wait.
  Future<void> test_write_in_the_action_of_a_wait() => assertAt('''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.join(() async {
      ctx.emit(feed.confirm(post));
      await send(post);
    });
  });
}
''', []);

  Future<void> test_conditional_wait() => assertAt(
    '''
$_feed
  Job<void> like(String post, {required bool remote}) =>
      _likes.enqueue<Feed, void>((ctx) async {
        final feed = ctx.state;
        if (remote) await ctx.join(() => send(post));
        ctx.emit(feed.confirm(post));
      });
}
''',
    ['ctx.emit(feed.confirm(post))'],
  );

  // Each branch of ?:, ?? and a switch expression is a value the write may
  // be built on.
  Future<void> test_branches() => assertAt(
    '''
$_feed
  Job<void> like(String post, {required bool liked, Feed? next}) =>
      _likes.enqueue<Feed, void>((ctx) async {
        final feed = ctx.state;
        await ctx.join(() => send(post));
        ctx.emit(liked ? feed.confirm(post) : feed);
        ctx.emit(next ?? feed);
        ctx.emit(switch (liked) { true => ctx.state, false => feed.settled });
        ctx.emit(liked ? ctx.state.confirm(post) : (next ?? ctx.state));
      });
}
''',
    [
      'ctx.emit(liked ? feed.confirm(post) : feed)',
      'ctx.emit(next ?? feed)',
      'ctx.emit(switch (liked) { true => ctx.state, false => feed.settled })',
    ],
  );

  Future<void> test_state_as_and_await_for() => assertAt(
    '''
$_feed
  Job<void> likeAll() => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.stateAs<Feed>();
    await for (final post in posts()) {
      ctx.emit(feed.confirm(post));
    }
  });
}
''',
    ['ctx.emit(feed.confirm(post))'],
  );

  // A function the body does not wait for suspends nothing of the body.
  Future<void> test_wait_in_unattended_work() => assertAt('''
$_feed
  Job<void> like(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    ctx.unattended(() async {
      await send(post);
    });
    ctx.emit(feed.confirm(post));
  });
}
''', []);

  // A child, a body given to job and a body given to a lane the code does
  // not declare run in a lane too: whichever lane it is, it has neighbours.
  Future<void> test_child_job_and_mixin() => assertAt(
    '''
$_feed
  SoloJob<void> confirm(String post) => _likes.job<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.run(ctx.child((child) async {
      final copy = child.state;
      final parents = ctx.state;
      await child.join(() => send(post));
      child.emit(copy.confirm(post));
      child.emit(parents.confirm(post));
    }));
    ctx.emit(feed.confirm(post));
  });
}

mixin Steps on SoloLanes<Feed> {
  Job<void> step(SoloLane<Feed> lane, String post) =>
      lane.enqueue<Feed, void>((ctx) async {
        final feed = ctx.state;
        await ctx.join(() => send(post));
        ctx.emit(feed.confirm(post));
      });
}
''',
    [
      'child.emit(copy.confirm(post))',
      'child.emit(parents.confirm(post))',
      'ctx.emit(feed.confirm(post))',
      'ctx.emit(feed.confirm(post))',
    ],
  );

  // A body handed to a Solo runs in the Solo. A value read in the body of a
  // parent is not followed into the body of its child: the rule looks at
  // one body.
  Future<void> test_solo_and_another_context() => assertAt('''
$_feed
  late final Desk desk;

  Job<void> relay(String post) => desk.hand((ctx) async {
    final feed = ctx.state;
    await ctx.join(() => send(post));
    ctx.emit(feed.confirm(post));
  });

  Job<void> nested(String post) => _likes.enqueue<Feed, void>((ctx) async {
    final feed = ctx.state;
    await ctx.run(ctx.child((child) async {
      child.emit(feed.confirm(post));
    }));
  });
}

final class Desk extends Solo<Feed> {
  Desk() : super(const Feed());

  Job<void> hand(Future<void> Function(SoloContext<Feed, Feed> ctx) body) =>
      enqueue(body);
}
''', []);

  /// Asserts one diagnostic at [span] of [code] whose message has [message].
  Future<void> _assertMessage(String code, String span, String message) =>
      assertDiagnostics(code, [
        lint(code.indexOf(span), span.length, messageContainsAll: [message]),
      ]);
}
