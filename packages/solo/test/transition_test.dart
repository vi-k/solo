@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

/// Records every transition the controller hook sees.
final class _Watched extends Solo<TestState> {
  final seen = <SoloTransition<TestState>>[];

  _Watched() : super(const Initial());

  void set(TestState next) => externalSetState(next);

  @override
  void onChange(SoloTransition<TestState> transition) => seen.add(transition);
}

void main() {
  test('a transition names the job that emitted', () {
    runSolo((solo, journal, async) {
      final seen = <SoloTransition<TestState>>[];
      final watcher = _TransitionObserver(seen);
      SoloBase.observer = watcher;
      final job = solo.run<TestState, void>(
        key: 'job',
        (ctx) async => ctx.emit(const Preparing()),
      );
      async.flushMicrotasks();
      expect(seen, hasLength(1));
      expect(identical(seen.single.job, job), isTrue);
      expect(seen.single.isExternal, isFalse);
      expect(seen.single.previous, const Initial());
      expect(seen.single.current, const Preparing());
      SoloBase.observer = journal;
    });
  });

  test('an external change belongs to no job', () {
    final solo = _Watched()..set(const Preparing());
    expect(solo.seen.single.job, isNull);
    expect(solo.seen.single.isExternal, isTrue);
  });

  test('a child of the running job is the child, not the root', () {
    runSolo((solo, journal, async) {
      final seen = <SoloTransition<TestState>>[];
      SoloBase.observer = _TransitionObserver(seen);
      late final Job<void> child;
      final root = solo.run<TestState, void>(
        key: 'root',
        (ctx) async {
          child = ctx.each<int>(
            Stream<int>.fromIterable([1]),
            (childCtx, event) => childCtx.emit(Preparing(progress: event)),
          );
          await child.done;
        },
      );
      async.flushTimers();
      expect(seen, hasLength(1));
      expect(identical(seen.single.job, child), isTrue);
      expect(identical(seen.single.job, root), isFalse);
      SoloBase.observer = journal;
    });
  });

  test('revisions grow by one, nested change included', () {
    final solo = _Nested()..set(const Preparing());
    expect(
      solo.seen.map((transition) => transition.revision).toList(),
      [1, 2],
      reason: 'the outer change is #1 and the one nested in it is #2',
    );
    expect(
      solo.seen.map((transition) => '${transition.current}').toList(),
      ['$Preparing(progress: 0)', '$Disposed()'],
      reason: 'the nested change is seen after the one it grew from',
    );
  });

  test('toString says the revision, the source and both states', () {
    final solo = _Watched()..set(const Preparing());
    expect(
      '${solo.seen.single}',
      'SoloTransition(#1, external: Initial() -> Preparing(progress: 0))',
    );
  });
}

/// Changes the state again from inside the hook of the first change.
final class _Nested extends Solo<TestState> {
  final seen = <SoloTransition<TestState>>[];

  _Nested() : super(const Initial());

  void set(TestState next) => externalSetState(next);

  @override
  void onChange(SoloTransition<TestState> transition) {
    seen.add(transition);
    if (transition.current is Preparing) {
      externalSetState(const Disposed());
    }
  }
}

/// Collects the transitions the global observer is given.
final class _TransitionObserver extends SoloObserver {
  final List<SoloTransition<TestState>> seen;

  _TransitionObserver(this.seen);

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      seen.add(transition as SoloTransition<TestState>);
}
