import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Counter extends Solo<int> {
  final void Function(_Counter counter)? onClosing;

  _Counter([super.initialState = 0, this.onClosing]);

  void set(int next) => externalSetState(next);

  @override
  void onClose() => onClosing?.call(this);
}

/// When the writer of [_Writer] writes to its controller.
enum _When { initState, build, dispose }

/// Another widget of the screen that writes to the controller in [when].
final class _Writer extends StatefulWidget {
  final _Counter counter;
  final _When when;

  const _Writer(this.counter, this.when);

  @override
  State<_Writer> createState() => _WriterState();
}

final class _WriterState extends State<_Writer> {
  @override
  void initState() {
    super.initState();
    if (widget.when == _When.initState) {
      widget.counter.set(1);
    }
  }

  @override
  void dispose() {
    if (widget.when == _When.dispose) {
      widget.counter.set(1);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.when == _When.build) {
      widget.counter.set(1);
    }
    return const SizedBox();
  }
}

/// A controller of somebody's own whose `addChangeListener` registers the
/// listener and then throws, once.
final class _FailingCounter extends Solo<int> {
  _FailingCounter() : super(0);

  var _fail = true;
  int adds = 0;
  int removes = 0;

  int get live => adds - removes;

  @override
  void addChangeListener(void Function(int previous, int current) listener) {
    adds++;
    super.addChangeListener(listener);
    if (_fail) {
      _fail = false;
      throw StateError('could not start');
    }
  }

  @override
  void removeChangeListener(void Function(int previous, int current) listener) {
    removes++;
    super.removeChangeListener(listener);
  }
}

const _wait = Duration(milliseconds: 100);

/// A reaction that writes `s<N>` when it starts and `e<N>` when it ends,
/// waiting in between through `ctx.pause`.
Future<void> Function(JobContext ctx, BuildContext context, int state)
_reaction(List<String> log, {String prefix = ''}) =>
    (ctx, context, state) async {
      log.add('${prefix}s$state');
      await ctx.pause(_wait);
      log.add('${prefix}e$state');
    };

SoloListener<int> _listener(
  Solo<int> solo,
  List<String> log, {
  SoloListenerMode mode = SoloListenerMode.concurrent,
  bool Function(int previous, int current)? listenWhen,
  FutureOr<void> Function(JobContext ctx, BuildContext context, int state)?
  listener,
}) => SoloListener<int>(
  solo: solo,
  mode: mode,
  listenWhen: listenWhen,
  listener: listener ?? _reaction(log),
  child: const SizedBox(),
);

/// The trace of the modes: 1, then 2 and 3 in a row 10 ms later, each
/// reaction waiting 100 ms.
Future<List<String>> _modeTrace(
  WidgetTester tester,
  SoloListenerMode mode,
) async {
  final counter = _Counter();
  addTearDown(counter.close);
  final log = <String>[];
  await tester.pumpWidget(_listener(counter, log, mode: mode));

  counter.set(1);
  await tester.pump(const Duration(milliseconds: 10));
  counter
    ..set(2)
    ..set(3);
  await tester.pump(const Duration(milliseconds: 400));
  return log;
}

void main() {
  group('SoloListener', () {
    testWidgets('no reaction on start', (tester) async {
      final counter = _Counter(5);
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(_listener(counter, log));
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, isEmpty);
    });

    // The framework drops a `State` that threw in `initState` without
    // disposing of it.
    testWidgets('a throwing addChangeListener leaves no registration', (
      tester,
    ) async {
      final counter = _FailingCounter();
      addTearDown(counter.close);
      await tester.pumpWidget(_listener(counter, []));
      expect(tester.takeException(), isStateError);
      await tester.pumpWidget(const SizedBox());
      expect(counter.live, 0);
    });

    testWidgets('listenWhen gets the pair of the change', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final pairs = <String>[];
      await tester.pumpWidget(
        _listener(
          counter,
          [],
          listenWhen: (previous, current) {
            pairs.add('$previous>$current');
            return false;
          },
        ),
      );
      counter
        ..set(1)
        ..set(2);
      await tester.pump();
      expect(pairs, ['0>1', '1>2']);
    });

    testWidgets('a skipped change starts no reaction', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          listenWhen: (previous, current) => current.isOdd,
        ),
      );
      counter
        ..set(1)
        ..set(2)
        ..set(3);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, ['s1', 's3', 'e1', 'e3']);
    });

    testWidgets('every change reacts without listenWhen, the same object too', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(_listener(counter, log));
      counter
        ..set(1)
        ..set(1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, ['s1', 's1', 'e1', 'e1']);
    });

    group('the trace of', () {
      const traces = {
        SoloListenerMode.concurrent: ['s1', 's2', 's3', 'e1', 'e2', 'e3'],
        SoloListenerMode.sequential: ['s1', 'e1', 's2', 'e2', 's3', 'e3'],
        SoloListenerMode.droppable: ['s1', 'e1'],
        SoloListenerMode.keepLatest: ['s1', 'e1', 's3', 'e3'],
        SoloListenerMode.restart: ['s1', 's3', 'e3'],
      };
      for (final MapEntry(key: mode, value: trace) in traces.entries) {
        testWidgets(mode.name, (tester) async {
          expect(await _modeTrace(tester, mode), trace);
        });
      }
    });

    group('restart starts the next reaction when the cancelled one ends', () {
      final waits = <String, (Future<void> Function(JobContext ctx), int)>{
        'a plain await': (
          (ctx) async {
            await Future<void>.delayed(_wait);
          },
          100,
        ),
        'ctx.join': ((ctx) => ctx.join(() => Future<void>.delayed(_wait)), 100),
        'ctx.abandonable': (
          (ctx) => ctx.abandonable(() => Future<void>.delayed(_wait)),
          10,
        ),
        'ctx.pause': ((ctx) => ctx.pause(_wait), 10),
      };
      for (final MapEntry(key: name, value: (wait, startsAt))
          in waits.entries) {
        testWidgets('after $name: at $startsAt ms', (tester) async {
          final counter = _Counter();
          addTearDown(counter.close);
          final log = <String>[];
          await tester.pumpWidget(
            _listener(
              counter,
              log,
              mode: SoloListenerMode.restart,
              listener: (ctx, context, state) async {
                log.add('s$state');
                await wait(ctx);
              },
            ),
          );

          counter.set(1);
          await tester.pump(const Duration(milliseconds: 10));
          counter
            ..set(2)
            ..set(3);
          var at = 10;
          await tester.pump();
          while (!log.contains('s3')) {
            await tester.pump(const Duration(milliseconds: 1));
            at++;
            expect(at, lessThan(500));
          }
          expect(at, startsAt);
          await tester.pump(const Duration(milliseconds: 300));
        });
      }
    });

    testWidgets('restart with two writes in one turn reacts to the second '
        'only', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(counter, log, mode: SoloListenerMode.restart),
      );
      counter
        ..set(1)
        ..set(2);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, ['s2', 'e2']);
    });

    testWidgets('restart cancels with ReplacedCancelReason', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final reasons = <Object>[];
      await tester.pumpWidget(
        _listener(
          counter,
          [],
          mode: SoloListenerMode.restart,
          listener: (ctx, context, state) async {
            try {
              await ctx.pause(_wait);
            } on Cancelled catch (cancelled) {
              reasons.add(cancelled.reason);
              rethrow;
            }
          },
        ),
      );
      counter.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      counter.set(2);
      await tester.pump(const Duration(milliseconds: 200));
      expect(reasons, [isA<ReplacedCancelReason>()]);
    });

    group('a reaction writing to its own controller', () {
      const traces = {
        SoloListenerMode.sequential: ['s1', 'e1', 's2', 'e2', 's3', 'e3'],
        SoloListenerMode.droppable: ['s1', 'e1'],
        SoloListenerMode.restart: ['s1', 's2', 's3', 'e3'],
      };
      for (final MapEntry(key: mode, value: trace) in traces.entries) {
        testWidgets(mode.name, (tester) async {
          final counter = _Counter();
          addTearDown(counter.close);
          final log = <String>[];
          await tester.pumpWidget(
            _listener(
              counter,
              log,
              mode: mode,
              listener: (ctx, context, state) async {
                log.add('s$state');
                if (state < 3) {
                  counter.set(state + 1);
                }
                await ctx.pause(_wait);
                log.add('e$state');
              },
            ),
          );
          counter.set(1);
          await tester.pump(const Duration(milliseconds: 500));
          expect(log, trace);
        });
      }
    });

    group('a mode change leaves living reactions alone', () {
      testWidgets('concurrent to sequential: the running ones go on, the '
          'next change waits for them', (tester) async {
        final counter = _Counter();
        addTearDown(counter.close);
        final log = <String>[];
        await tester.pumpWidget(_listener(counter, log));
        counter
          ..set(1)
          ..set(2)
          ..set(3);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pumpWidget(
          _listener(counter, log, mode: SoloListenerMode.sequential),
        );
        counter.set(4);
        await tester.pump(const Duration(milliseconds: 300));
        expect(log, ['s1', 's2', 's3', 'e1', 'e2', 'e3', 's4', 'e4']);
      });

      testWidgets('sequential to droppable: the waiting ones start one at a '
          'time', (tester) async {
        final counter = _Counter();
        addTearDown(counter.close);
        final log = <String>[];
        await tester.pumpWidget(
          _listener(counter, log, mode: SoloListenerMode.sequential),
        );
        counter
          ..set(1)
          ..set(2)
          ..set(3);
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pumpWidget(
          _listener(counter, log, mode: SoloListenerMode.droppable),
        );
        counter.set(4);
        await tester.pump(const Duration(milliseconds: 400));
        expect(log, ['s1', 'e1', 's2', 'e2', 's3', 'e3']);
      });
    });

    testWidgets('the next change applies the new mode to the waiting ones', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(counter, log, mode: SoloListenerMode.sequential),
      );
      counter
        ..set(1)
        ..set(2)
        ..set(3);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        _listener(counter, log, mode: SoloListenerMode.keepLatest),
      );
      counter.set(4);
      await tester.pump(const Duration(milliseconds: 400));
      expect(log, ['s1', 'e1', 's4', 'e4']);
    });

    testWidgets('the listener is read when the reaction starts', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(counter, log, mode: SoloListenerMode.sequential),
      );
      counter
        ..set(1)
        ..set(2);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          mode: SoloListenerMode.sequential,
          listener: _reaction(log, prefix: 'new '),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['s1', 'e1', 'new s2', 'new e2']);
    });

    testWidgets('listenWhen and mode are read at notification', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(_listener(counter, log));
      counter.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          mode: SoloListenerMode.droppable,
          listenWhen: (previous, current) => current != 2,
        ),
      );
      // 2 is skipped by the new listenWhen, and 3 is dropped by the new
      // mode: the reaction to 1 is running.
      counter
        ..set(2)
        ..set(3);
      await tester.pump(const Duration(milliseconds: 200));
      counter.set(4);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, ['s1', 'e1', 's4', 'e4']);
    });

    group('a nested write from a plain listener reaches listenWhen as the '
        'next pair', () {
      for (final plainFirst in [true, false]) {
        final order = plainFirst ? 'plain first' : 'widget first';
        for (final (nested, reactions) in [
          (2, ['r1', 'r2']),
          (0, ['r1', 'r0']),
        ]) {
          testWidgets('1 then $nested, $order', (tester) async {
            final counter = _Counter();
            addTearDown(counter.close);
            final pairs = <String>[];
            final log = <String>[];
            void plain() {
              if (counter.currentState == 1) {
                counter.set(nested);
              }
            }

            if (plainFirst) {
              counter.addListener(plain);
            }
            await tester.pumpWidget(
              _listener(
                counter,
                log,
                listenWhen: (previous, current) {
                  pairs.add('$previous>$current');
                  return true;
                },
                listener: (ctx, context, state) => log.add('r$state'),
              ),
            );
            if (!plainFirst) {
              counter.addListener(plain);
            }
            counter.set(1);
            await tester.pump();
            expect(pairs, ['0>1', '1>$nested']);
            expect(log, reactions);
          });
        }
      }
    });

    testWidgets('listenWhen writing to the controller', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final pairs = <String>[];
      final log = <String>[];
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          listenWhen: (previous, current) {
            pairs.add('$previous>$current');
            if (current == 1) {
              counter.set(2);
            }
            return true;
          },
          listener: (ctx, context, state) => log.add('r$state'),
        ),
      );
      counter.set(1);
      await tester.pump();
      expect(pairs, ['0>1', '1>2']);
      expect(log, ['r1', 'r2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose cancels a running reaction with ManualCancelReason', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      final reasons = <Object>[];
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          listener: (ctx, context, state) async {
            try {
              await ctx.pause(const Duration(seconds: 5));
              log.add('after the wait');
            } on Cancelled catch (cancelled) {
              reasons.add(cancelled.reason);
              rethrow;
            }
          },
        ),
      );
      counter.set(1);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(reasons, [isA<ManualCancelReason>()]);
      expect(log, isEmpty);
    });

    testWidgets('dispose before the start calls no reaction', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(_listener(counter, log));
      // The write and the leaving in one frame: the build that replaces the
      // listener writes.
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            counter.set(1);
            return const SizedBox();
          },
        ),
      );
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('dispose drops the waiting states', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(counter, log, mode: SoloListenerMode.sequential),
      );
      counter
        ..set(1)
        ..set(2)
        ..set(3);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['s1']);
    });

    testWidgets('a new controller cancels the reactions of the old one', (
      tester,
    ) async {
      final first = _Counter();
      final next = _Counter(5);
      addTearDown(first.close);
      addTearDown(next.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(first, log, mode: SoloListenerMode.sequential),
      );
      first
        ..set(1)
        ..set(2);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        _listener(next, log, mode: SoloListenerMode.sequential),
      );
      first.set(3);
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['s1']);
    });

    testWidgets('the reactions of the new controller wait for the cancelled '
        'ones', (tester) async {
      final first = _Counter();
      final next = _Counter();
      addTearDown(first.close);
      addTearDown(next.close);
      final log = <String>[];
      Widget tree(Solo<int> solo) => _listener(
        solo,
        log,
        mode: SoloListenerMode.sequential,
        listener: (ctx, context, state) async {
          log.add('s$state');
          await Future<void>.delayed(_wait);
        },
      );
      await tester.pumpWidget(tree(first));
      first.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(tree(next));
      next.set(7);
      var at = 10;
      await tester.pump();
      while (!log.contains('s7')) {
        await tester.pump(const Duration(milliseconds: 1));
        at++;
        expect(at, lessThan(500));
      }
      expect(at, 100);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('droppable drops a change of the new controller while a '
        'cancelled reaction of the old one runs', (tester) async {
      final first = _Counter();
      final next = _Counter();
      addTearDown(first.close);
      addTearDown(next.close);
      final log = <String>[];
      Widget tree(Solo<int> solo) => _listener(
        solo,
        log,
        mode: SoloListenerMode.droppable,
        listener: (ctx, context, state) async {
          log.add('s$state');
          await Future<void>.delayed(_wait);
        },
      );
      await tester.pumpWidget(tree(first));
      first.set(1);
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpWidget(tree(next));
      await tester.pump(const Duration(milliseconds: 5));
      next.set(7);
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['s1']);
    });

    testWidgets('A to B and back to A reacts once per write', (tester) async {
      final a = _Counter();
      final b = _Counter();
      addTearDown(a.close);
      addTearDown(b.close);
      final log = <String>[];
      Widget tree(Solo<int> solo) => _listener(
        solo,
        log,
        listener: (ctx, context, state) => log.add('r$state'),
      );
      await tester.pumpWidget(tree(a));
      await tester.pumpWidget(tree(b));
      await tester.pumpWidget(tree(a));
      a.set(1);
      b.set(2);
      await tester.pump();
      expect(log, ['r1']);
    });

    testWidgets('a finished controller gives neither error nor reaction', (
      tester,
    ) async {
      final finished = _Counter();
      await finished.close();
      final live = _Counter();
      addTearDown(live.close);
      final log = <String>[];
      await tester.pumpWidget(_listener(finished, log));
      await tester.pump();
      await tester.pumpWidget(_listener(live, log));
      await tester.pumpWidget(_listener(finished, log));
      live.set(1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reparenting with a GlobalKey keeps the reactions', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      final key = GlobalKey();
      Widget listener() => SoloListener<int>(
        key: key,
        solo: counter,
        listener: _reaction(log),
        child: const SizedBox(),
      );
      await tester.pumpWidget(Center(child: listener()));
      counter.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(Align(child: listener()));
      await tester.pump(const Duration(milliseconds: 200));
      counter.set(2);
      await tester.pump(const Duration(milliseconds: 200));
      expect(log, ['s1', 'e1', 's2', 'e2']);
    });

    testWidgets('closing the controller does not cancel a reaction', (
      tester,
    ) async {
      // No `addTearDown(counter.close)`: the body closes it, and the future of
      // that close, made under the clock of the test, does not complete in
      // the teardown.
      final counter = _Counter(0, (counter) => counter.set(9));
      final log = <String>[];
      await tester.pumpWidget(_listener(counter, log));
      counter.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      unawaited(counter.close());
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['s1', 's9', 'e1', 'e9']);
    });

    testWidgets('a throwing listenWhen goes to FlutterError and starts no '
        'reaction', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      final log = <String>[];
      await tester.pumpWidget(
        _listener(
          counter,
          log,
          listenWhen: (previous, current) =>
              current == 1 ? throw StateError('when') : true,
          listener: (ctx, context, state) => log.add('r$state'),
        ),
      );
      counter.set(1);
      await tester.pump();
      expect(tester.takeException(), isStateError);
      expect(log, isEmpty);
      counter.set(2);
      await tester.pump();
      expect(log, ['r2']);
    });

    testWidgets(
      'a failed reaction goes to FlutterError and the next one runs',
      (tester) async {
        final counter = _Counter();
        addTearDown(counter.close);
        final log = <String>[];
        await tester.pumpWidget(
          _listener(
            counter,
            log,
            listener: (ctx, context, state) async {
              await ctx.pause();
              if (state == 1) {
                throw StateError('reaction');
              }
              log.add('r$state');
            },
          ),
        );
        counter.set(1);
        await tester.pump(const Duration(milliseconds: 10));
        expect(tester.takeException(), isStateError);
        counter.set(2);
        await tester.pump(const Duration(milliseconds: 10));
        expect(log, ['r2']);
      },
    );

    testWidgets('a listener throwing synchronously goes to FlutterError', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.close);
      await tester.pumpWidget(
        _listener(
          counter,
          [],
          listener: (ctx, context, state) => throw StateError('at once'),
        ),
      );
      counter.set(1);
      await tester.pump();
      expect(tester.takeException(), isStateError);
    });

    group('a failure after the screen left goes to FlutterError', () {
      final failures = <String, void Function(BuildContext context)>{
        'a throw': (context) => throw StateError('late'),
        'ScaffoldMessenger.of': ScaffoldMessenger.of,
      };
      for (final MapEntry(key: name, value: fail) in failures.entries) {
        testWidgets(name, (tester) async {
          final counter = _Counter();
          addTearDown(counter.close);
          await tester.pumpWidget(
            _listener(
              counter,
              [],
              listener: (ctx, context, state) async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
                // ignore: use_build_context_synchronously, the case itself.
                fail(context);
              },
            ),
          );
          counter.set(1);
          await tester.pump(const Duration(milliseconds: 10));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNotNull);
        });
      }
    });

    testWidgets('a cancellation reports nothing', (tester) async {
      final counter = _Counter();
      addTearDown(counter.close);
      await tester.pumpWidget(_listener(counter, []));
      counter.set(1);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    group('writes from initState, build and dispose of another widget', () {
      final reactions =
          <String, (void Function(BuildContext context, int state), String)>{
            'showSnackBar': (
              (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('saw $state'))),
              'saw 1',
            ),
            'Navigator.push': (
              (context, state) => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Text('page $state'),
                  ),
                ),
              ),
              'page 1',
            ),
          };
      for (final when in _When.values) {
        for (final MapEntry(key: name, value: (react, shown))
            in reactions.entries) {
          testWidgets('${when.name}, $name', (tester) async {
            final counter = _Counter();
            addTearDown(counter.close);
            Widget screen({required bool writer}) => MaterialApp(
              home: Scaffold(
                body: _listener(
                  counter,
                  [],
                  listener: (ctx, context, state) => react(context, state),
                ),
              ),
              builder: (context, child) => Column(
                children: [
                  Expanded(child: child!),
                  if (writer) _Writer(counter, when),
                ],
              ),
            );
            await tester.pumpWidget(screen(writer: true));
            if (when == _When.dispose) {
              await tester.pumpWidget(screen(writer: false));
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text(shown), findsOneWidget);
          });
        }
      }
    });
  });
}
