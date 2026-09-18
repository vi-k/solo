@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

/// The first attempts of `doc/state.md`, and what each one costs.
///
/// The page opens four of its sections with the version the vocabulary of
/// the API leads to, and states what that version does instead of what it
/// was meant to do. Nothing else guards those statements: the page has no
/// bench, so a trace quoted there rots silently. Every number and every
/// outcome the page names about a first attempt is pinned here, next to the
/// version the page then shows.

// --- State and rules ------------------------------------------------------

sealed class CamState {
  const CamState();
}

final class Ready extends CamState {
  final bool paused;

  const Ready({this.paused = false});
}

final class Cam extends Solo<CamState> {
  // ignore: close_sinks -- closed by the test that owns the scenario
  final frames = StreamController<int>.broadcast();
  final stored = <int>[];

  Cam() : super(const Ready());

  void pause() => externalSetState(const Ready(paused: true));

  /// The first attempt: the rule is a line at the top of the body.
  Job<void> recordByHand() => run<CamState, void>(
        key: 'record',
        (ctx) async {
          final state = ctx.state;
          if (state is! Ready || state.paused) return;
          // ignore: prefer_foreach -- the loop is the shape the page shows
          await for (final frame in frames.stream) {
            stored.add(frame);
          }
        },
      );

  /// The page's version: the rule belongs to the job.
  Job<void> recordByRule() => run<Ready, void>(
        key: 'record',
        keepWhile: (state) => !state.paused,
        (ctx) => ctx.each(frames.stream, (child, frame) {
          stored.add(frame);
        }).value,
      );
}

// --- Observing state ------------------------------------------------------

/// The controller of the order diagram under "Observing state".
///
/// One listener, one running job whose `keepWhile` records what it was
/// asked about, and a write made from inside the listener.
final class Order extends Solo<String> {
  final trace = <String>[];

  /// What the job's `keepWhile` answered, in order, next to the state it
  /// was asked about.
  final answers = <String>[];

  /// The job's rule. The diagram's job keeps on every state.
  final bool Function(Order order, String state) keep;

  /// Whether the listener sets [blocked] once it hears C.
  final bool blockOnC;

  /// A field of the controller, not of the state.
  bool blocked = false;

  var _nested = false;
  var _inNestedWrite = false;

  Order({this.keep = _keepAll, this.blockOnC = false}) : super('A') {
    addListener(() {
      final seen = currentState;
      trace.add('    listeners of $seen');
      if (!_nested && seen == 'B') {
        _nested = true;
        trace.add('        externalSetState(C)');
        // The flag is the test's own bookkeeping, and it is what turns
        // the sequence below into the diagram: it says which of the two
        // re-evaluations ran inside the nested write.
        _inNestedWrite = true;
        set('C');
        _inNestedWrite = false;
        trace.add('        next line of the listener');
      }
      if (blockOnC && seen == 'C') blocked = true;
    });
  }

  static bool _keepAll(Order order, String state) => true;

  void set(String next) => externalSetState(next);

  Job<void> watch() => run<String, void>(
        keepWhile: (state) {
          final indent = _inNestedWrite ? ' ' * 12 : ' ' * 4;
          trace.add('${indent}rules, against $state');
          final kept = keep(this, state);
          answers.add('$state: ${kept ? 'keep' : 'reject'}');
          return kept;
        },
        (ctx) async => ctx.wait(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        ),
      );
}

// --- A delivery of your own -----------------------------------------------

final class OwnList extends Solo<int> {
  final own = <void Function()>[];

  OwnList() : super(0);

  bool get engineSeesListeners => hasListeners;

  void set(int next) => externalSetState(next);

  /// The first attempt: a list of its own, and no `super`.
  @override
  void addListener(void Function() listener) => own.add(listener);

  @override
  void removeListener(void Function() listener) => own.remove(listener);
}

// --- External state -------------------------------------------------------

sealed class LinkState {
  const LinkState();
}

final class Connected extends LinkState {
  const Connected();
}

final class Lost extends LinkState {
  const Lost();
}

final class Link extends Solo<LinkState> {
  final answer = Completer<void>();
  final rulesSaw = <LinkState>[];

  Link() : super(const Connected());

  /// A job that waits for an answer the device will not give.
  Job<void> waitForAnswer() => run<LinkState, void>(
        key: 'wait',
        keepWhile: (state) {
          rulesSaw.add(state);
          return state is Connected;
        },
        (ctx) => ctx.wait(() => answer.future),
      );

  /// The first attempt: the fact is queued like work.
  Job<void> reportByJob() => run<LinkState, void>(
        key: 'report',
        (ctx) async => ctx.emit(const Lost()),
      );

  /// The page's version: the fact is reflected at once.
  void reportAtOnce() => externalSetState(const Lost());
}

// --- State after failure or cancellation ----------------------------------

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class Offline extends ProfileState {
  const Offline();
}

final class Profile extends Solo<ProfileState> {
  final api = Completer<String>();

  /// How the first attempt's `catch` behaved: entered, and what the
  /// `emit` inside it did.
  int caught = 0;
  Object? emitThrew;

  Profile() : super(const Initial());

  void goOffline() => externalSetState(const Offline());

  /// The first attempt: a `try`/`catch` around the call.
  Job<String> loadByHand() => run<ProfileState, String>(
        key: 'load',
        (ctx) async {
          ctx.emit(const Loading());
          try {
            final name = await ctx.wait(() => api.future);
            ctx.emit(Loaded(name));
            return name;
          } on Object {
            caught++;
            try {
              ctx.emit(const Initial());
            } on Object catch (error) {
              emitThrew = error;
            }
            rethrow;
          }
        },
      );

  /// The page's version: the handlers are parameters.
  Job<String> loadByHandler() => run<ProfileState, String>(
        key: 'load',
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(() => api.future);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  /// The first attempt of the last section: a handler with no rule over it.
  Job<String> loadWithoutRule() => run<ProfileState, String>(
        key: 'load',
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(() => api.future);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  /// The page's version: the rule says which states permit the correction.
  Job<String> loadWithRule() => run<ProfileState, String>(
        key: 'load',
        keepWhile: (state) => state is! Offline,
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(() => api.future);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}

void main() {
  group('a rule the body checks itself', () {
    test('the first attempt goes on recording after the pause', () async {
      final cam = Cam();
      final job = cam.recordByHand();
      await pump();
      cam.frames.add(1);
      await pump();
      cam.pause();
      cam.frames
        ..add(2)
        ..add(3);
      await pump();

      expect(cam.stored, [1, 2, 3], reason: 'the check does not come back');
      expect(
        job.isFinished,
        isFalse,
        reason: 'and the job is still running',
      );

      // And it holds the closing too: `await for` is no checkpoint, so
      // the body never hears the cancellation `close` sends it.
      var closed = false;
      unawaited(cam.close().then((_) => closed = true));
      await pump();
      expect(
        closed,
        isFalse,
        reason: 'close waits for a body that cannot stop',
      );

      await cam.frames.close();
      await pump();
      expect(closed, isTrue, reason: 'only the stream ending lets it go');
    });

    test('the rule stops the recording at the pause', () async {
      final cam = Cam();
      final job = cam.recordByRule();
      await pump();
      cam.frames.add(1);
      await pump();
      cam.pause();
      cam.frames
        ..add(2)
        ..add(3);
      await pump();

      expect(cam.stored, [1]);
      final outcome = await job.done;
      expect(outcome, isA<Cancelled>());
      expect('$outcome', contains('rules: keepWhile'));

      await cam.frames.close();
      await cam.close();
    });
  });

  group('the order a nested change gets', () {
    test('rules at once, the writer next, the listeners last', () async {
      final order = Order();
      final job = order.watch();
      await pump();
      order.trace.clear();

      order
        ..trace.add('externalSetState(B)')
        ..set('B')
        ..trace.add('next line of the writer');

      // The diagram under "Observing state" in doc/state.md, line for
      // line, its `//` annotations aside.
      expect(order.trace, [
        'externalSetState(B)',
        '    listeners of B',
        '        externalSetState(C)',
        '            rules, against C',
        '        next line of the listener',
        '    listeners of C',
        '    rules, against C',
        'next line of the writer',
      ]);

      await job.cancel();
      await order.close();
    });

    test('a rule of the state alone is not asked again once it has refused',
        () async {
      final order = Order(keep: (_, state) => state != 'C');
      final job = order.watch();
      await pump();
      order.answers.clear();

      order.set('B');

      expect(order.answers, ['C: reject']);
      expect('${await job.done}', contains('rules: keepWhile'));
      await order.close();
    });

    test('only the second question hears what the listeners of C set',
        () async {
      final order = Order(keep: (order, _) => !order.blocked, blockOnC: true);
      final job = order.watch();
      await pump();
      order.answers.clear();

      order.set('B');

      expect(order.answers, ['C: keep', 'C: reject']);
      expect('${await job.done}', contains('rules: keepWhile'));
      await order.close();
    });
  });

  group('a delivery of your own', () {
    test('a list of its own takes the registration away from the engine',
        () async {
      final solo = OwnList();
      var called = 0;
      solo.addListener(() => called++);

      expect(solo.own, hasLength(1), reason: 'it landed in the subclass');
      expect(
        solo.engineSeesListeners,
        isFalse,
        reason: 'and the engine does not know it exists',
      );

      solo.set(1);
      await pump();

      expect(called, 0, reason: 'so the change never reaches it');

      await solo.close();
    });
  });

  group('an external fact', () {
    test('queued as a job, it waits behind the job that needs it', () async {
      final link = Link();
      final waiting = link.waitForAnswer();
      await pump();
      final report = link.reportByJob();
      await pump();

      expect(
        link.currentState,
        isA<Connected>(),
        reason: 'the controller still reports the old fact',
      );
      expect(
        link.rulesSaw,
        everyElement(isA<Connected>()),
        reason: 'the waiting job is asked, but never about the new fact',
      );
      expect(report.isFinished, isFalse);
      expect(waiting.isFinished, isFalse);

      await link.close();
    });

    test('reflected at once, it frees the job that was waiting', () async {
      final link = Link();
      final waiting = link.waitForAnswer();
      await pump();
      link.reportAtOnce();
      await pump();

      expect(link.currentState, isA<Lost>());
      expect(link.rulesSaw, contains(isA<Lost>()));
      final outcome = await waiting.done;
      expect('$outcome', contains('rules: keepWhile'));

      await link.close();
    });
  });

  group('leaving a temporary state', () {
    test('a catch runs on a cancellation and its emit throws', () async {
      final profile = Profile();
      final job = profile.loadByHand();
      await pump();
      expect(profile.currentState, isA<Loading>());

      unawaited(job.cancel());
      await pump();

      expect(
        profile.currentState,
        isA<Loading>(),
        reason: 'the temporary state is where the controller stays',
      );
      expect(await job.done, isA<Cancelled>());
      expect(profile.caught, 1, reason: 'the cancellation reaches the catch');
      expect(
        profile.emitThrew,
        isA<Cancelled>(),
        reason: 'and the emit inside it is a checkpoint, so it throws',
      );

      await profile.close();
    });

    test('the page version reaches Loaded when the call answers', () async {
      final profile = Profile();
      final job = profile.loadByHandler();
      await pump();
      profile.api.complete('Ada');

      expect(await job.done, isA<Done<String>>());
      expect((profile.currentState as Loaded).name, 'Ada');

      await profile.close();
    });

    test('the handler leaves it', () async {
      final profile = Profile();
      final job = profile.loadByHandler();
      await pump();
      unawaited(job.cancel());
      await pump();

      expect(profile.currentState, isA<Initial>());
      expect(await job.done, isA<Cancelled>());

      await profile.close();
    });
  });

  group('a handler over an incompatible state', () {
    test('without a rule it writes over the fact that arrived', () async {
      final profile = Profile();
      final job = profile.loadWithoutRule();
      await pump();
      profile.goOffline();
      await pump();

      expect(profile.currentState, isA<Offline>());
      unawaited(job.cancel());
      await pump();

      expect(
        profile.currentState,
        isA<Initial>(),
        reason: 'the handler ran and replaced the external fact',
      );

      await profile.close();
    });

    test('the rule cancels the job and disables the handler', () async {
      final profile = Profile();
      final job = profile.loadWithRule();
      await pump();
      profile.goOffline();
      await pump();

      expect(
        profile.currentState,
        isA<Offline>(),
        reason: 'the fact stays where the device put it',
      );
      final outcome = await job.done;
      expect('$outcome', contains('rules: keepWhile'));

      await profile.close();
    });
  });
}

/// One turn of the microtask queue.
Future<void> pump() => Future<void>.delayed(Duration.zero);
