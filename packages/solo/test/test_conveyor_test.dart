// ignore_for_file: lines_longer_than_80_chars

@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:conveyor/conveyor.dart';
import 'package:conveyor/src/debug_logger.dart';
import 'package:conveyor/utils.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conveyors/test_conveyor/event.dart';
import 'conveyors/test_conveyor/state.dart';
import 'conveyors/test_conveyor/test_conveyor.dart';
import 'utils/fake_async.dart';
import 'utils/result.dart';

void main() {
  debug = const PrintConveyorDebugLogger(prefix: '[Conveyor] * ');

  group('Conveyor.', () {
    late TestConveyor conveyor;
    late List<(TestState, TestState)> states;
    late List<(String, ConveyorResult)> results;

    List<String> resultsToStrings() =>
        results.map((e) => '${e.$1} ${e.$2}').toList();

    bool identicalResults(int index1, int index2) =>
        identical(results[index1].$2, results[index2].$2);

    Future<void> awaitResults() => results.map((e) => e.$2.done).wait;

    setUp(() async {
      states = [];
      results = [];
      conveyor = TestConveyor(const Initial())
        ..stream.listen((state) {
          final realState = conveyor.state;
          conveyor.log(
            'state: $state'
            '${realState == state ? '' : ', but real state: $realState'}',
          );
          states.add((state, realState));
        });
      await Future(() {});
    });

    tearDown(() => conveyor.close());

    group('State.', () {
      test(
        'Simple test',
        () => fakeAsync((async) {
          final event = TestEvent<TestState>(
            key: 'test',
            (state) async* {
              yield const Preparing();
              yield const Preparing(progress: 50);
              yield const Preparing(progress: 100);
              yield const Working();
              yield const Disposed();
            },
          );

          conveyor.queue.add(event).saveToResults(results);

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test] started',
            'state: $Preparing(progress: 0)',
            'state: $Preparing(progress: 50)',
            'state: $Preparing(progress: 100)',
            'state: $Working(a: 0, b: 0)',
            'state: $Disposed()',
            '[test] done',
          ]);

          expect(resultsToStrings(), [
            '[test] completed',
          ]);
        }),
      );

      group('Closing.', () {
        void addEvents() {
          final initEvent = TestEvent<NotDisposed>(
            key: 'init',
            checkStateBeforeProcessing: (state) => state is Initial,
            // Отменяем при любом внешнем изменении состояния.
            checkStateOnExternalChange: (state) => false,
            (state) async* {
              yield const Preparing();

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 0)
                  .use((it) => it.copyWith(progress: 50));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 50)
                  .use((it) => it.copyWith(progress: 100));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 100)
                  .use((_) => const Working());
            },
          );
          final incrementAEvent = TestEvent<Working>(
            key: 'incrementA',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(a: it.a + 1));
            },
          );
          final incrementBEvent = TestEvent<Working>(
            key: 'incrementB',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(b: it.b + 1));
            },
          );
          final finishEvent = TestEvent<TestState>(
            key: 'finish',
            checkStateBeforeProcessing: (state) => state is! Disposed,
            checkStateOnExternalChange: (state) => state is! Disposed,
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield const Disposed();
            },
          );

          conveyor.queue
            ..add(initEvent).saveToResults(results)
            ..add(incrementAEvent).saveToResults(results)
            ..add(incrementBEvent).saveToResults(results)
            ..add(finishEvent).saveToResults(results);
        }

        test(
          'Close immediately',
          () => fakeAsync((async) {
            addEvents();

            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] removed $RemovedAsClosed()',
              '[incrementA] removed $RemovedAsClosed()',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] $RemovedAsClosed()',
              '[incrementA] $RemovedAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close by microtask',
          () => fakeAsync((async) {
            addEvents();

            Future.microtask(conveyor.close);
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] started',
              '[incrementA] removed $RemovedAsClosed()',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
              '[init] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledAsClosed()',
              '[incrementA] $RemovedAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 50 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 50));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 100));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              '[incrementA] removed $RemovedAsClosed()',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
              '[init] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledAsClosed()',
              '[incrementA] $RemovedAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 150 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 150));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 200));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              '[incrementA] removed $RemovedAsClosed()',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
              '[init] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledAsClosed()',
              '[incrementA] $RemovedAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 250 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 250));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 300));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              '[incrementA] removed $RemovedAsClosed()',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
              '[init] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledAsClosed()',
              '[incrementA] $RemovedAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 350 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 400));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              '[incrementB] removed $RemovedAsClosed()',
              '[finish] removed $RemovedAsClosed()',
              '[incrementA] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] $CancelledAsClosed()',
              '[incrementB] $RemovedAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 450 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 500));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              '[finish] removed $RemovedAsClosed()',
              '[incrementB] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] $CancelledAsClosed()',
              '[finish] $RemovedAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 550 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 550));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              '[finish] cancelled $CancelledAsClosed()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] $CancelledAsClosed()',
            ]);
          }),
        );

        test(
          'Close after 650 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 650));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 650));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );
      });

      group('externalSetState.', () {
        void addEvents() {
          final initEvent = TestEvent<NotDisposed>(
            key: 'init',
            checkStateBeforeProcessing: (state) => state is Initial,
            // Отменяем при любом внешнем изменении состояния.
            checkStateOnExternalChange: (state) => false,
            (state) async* {
              yield const Preparing();

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 0)
                  .use((it) => it.copyWith(progress: 50));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 50)
                  .use((it) => it.copyWith(progress: 100));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 100)
                  .use((_) => const Working());
            },
          );
          final incrementAEvent = TestEvent<Working>(
            key: 'incrementA',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(a: it.a + 1));
            },
          );
          final incrementBEvent = TestEvent<Working>(
            key: 'incrementB',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(b: it.b + 1));
            },
          );
          final finishEvent = TestEvent<TestState>(
            key: 'finish',
            checkStateBeforeProcessing: (state) => state is! Disposed,
            checkStateOnExternalChange: (state) => state is! Disposed,
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield const Disposed();
            },
          );

          conveyor.queue
            ..add(initEvent).saveToResults(results)
            ..add(incrementAEvent).saveToResults(results)
            ..add(incrementBEvent).saveToResults(results)
            ..add(finishEvent).saveToResults(results);
        }

        test(
          'Change state immediately',
          () => fakeAsync((async) {
            addEvents();

            conveyor.externalSetState(const Disposed());
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[init] removed $RemovedByEventRules(is not $NotDisposed)',
              '[incrementA] removed $RemovedByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] $RemovedByEventRules(is not $NotDisposed)',
              '[incrementA] $RemovedByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state by microtask',
          () => fakeAsync((async) {
            addEvents();

            Future.microtask(() {
              conveyor.externalSetState(const Disposed());
            });
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] started',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] removed $RemovedByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] $RemovedByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 50 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 50));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 100));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] removed $RemovedByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] $RemovedByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 150 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 150));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 200));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] removed $RemovedByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] $RemovedByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 250 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 250));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 300));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] removed $RemovedByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRules(is not $NotDisposed)',
              '[incrementA] $RemovedByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 350 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 400));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[incrementA] cancelled $CancelledByEventRules(is not $Working)',
              '[incrementB] removed $RemovedByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] $CancelledByEventRules(is not $Working)',
              '[incrementB] $RemovedByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 450 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 500));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[incrementB] cancelled $CancelledByEventRules(is not $Working)',
              '[finish] removed $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] $CancelledByEventRules(is not $Working)',
              '[finish] $RemovedByEventRules(checkStateBeforeProcessing)',
            ]);
          }),
        );

        test(
          'Change state after 550 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 550));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[finish] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] $CancelledByEventRules(checkStateOnExternalChange)',
            ]);
          }),
        );

        test(
          'Change state after 650 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 650));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 650));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
              'externalSetState: $Disposed()',
              'state: $Disposed()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Change state during incrementA',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.externalSetState(const Working(a: 10, b: 10));

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'externalSetState: $Working(a: 10, b: 10)',
              'state: $Working(a: 10, b: 10)',
              'state: $Working(a: 11, b: 10)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 11, b: 11)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Change state during incrementB',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.externalSetState(const Working(a: 10, b: 10));

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'externalSetState: $Working(a: 10, b: 10)',
              'state: $Working(a: 10, b: 10)',
              'state: $Working(a: 10, b: 11)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Extremal test',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'extremalTest',
              (state) async* {
                conveyor.externalSetState(const Working());
                scheduleMicrotask(() {
                  debug('microtask');
                  conveyor.externalSetState(const Working(a: 2, b: 2));
                });
                yield state.isA<Working>().use((it) => it.copyWith(a: 1, b: 1));
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            // async.flushMicrotasks();

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[extremalTest] started',
              'externalSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              'state: $Working(a: 1, b: 1)',
              'externalSetState: $Working(a: 2, b: 2)',
              'state: $Working(a: 2, b: 2)',
              '[extremalTest] done',
            ]);

            expect(resultsToStrings(), [
              '[extremalTest] completed',
            ]);
          }),
        );
      });

      group('WorkingState.', () {
        void addEvents() {
          final event1 = TestEvent<Initial>(
            key: 'test1',
            (state) async* {},
          );
          final event2 = TestEvent<Preparing>(
            key: 'test2',
            (state) async* {},
          );
          final event3 = TestEvent<Working>(
            key: 'test3',
            (state) async* {},
          );

          conveyor.queue
            ..add(event1).saveToResults(results)
            ..add(event2).saveToResults(results)
            ..add(event3).saveToResults(results);
        }

        test(
          'Initial',
          () => fakeAsync((async) {
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] removed $RemovedByEventRules(is not $Preparing)',
              '[test3] removed $RemovedByEventRules(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $RemovedByEventRules(is not $Preparing)',
              '[test3] $RemovedByEventRules(is not $Working)',
            ]);
          }),
        );

        test(
          'Preparing',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Preparing());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'externalSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] removed $RemovedByEventRules(is not $Initial)',
              '[test2] started',
              '[test2] done',
              '[test3] removed $RemovedByEventRules(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedByEventRules(is not $Initial)',
              '[test2] completed',
              '[test3] $RemovedByEventRules(is not $Working)',
            ]);
          }),
        );

        test(
          'Working',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Working());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'externalSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test1] removed $RemovedByEventRules(is not $Initial)',
              '[test2] removed $RemovedByEventRules(is not $Preparing)',
              '[test3] started',
              '[test3] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedByEventRules(is not $Initial)',
              '[test2] $RemovedByEventRules(is not $Preparing)',
              '[test3] completed',
            ]);
          }),
        );

        test(
          'Disposed',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Disposed());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'externalSetState: $Disposed()',
              'state: $Disposed()',
              '[test1] removed $RemovedByEventRules(is not $Initial)',
              '[test2] removed $RemovedByEventRules(is not $Preparing)',
              '[test3] removed $RemovedByEventRules(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedByEventRules(is not $Initial)',
              '[test2] $RemovedByEventRules(is not $Preparing)',
              '[test3] $RemovedByEventRules(is not $Working)',
            ]);
          }),
        );

        test(
          'Initial > Preparing > Working > Disposed',
          () => fakeAsync((async) {
            final event1 = TestEvent<InitialAndPreparing>(
              key: 'test1',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
              },
            );
            final event2 = TestEvent<PreparingAndWorking>(
              key: 'test2',
              (state) async* {
                yield const Working();
              },
            );
            final event3 = TestEvent<WorkingAndDisposed>(
              key: 'test3',
              (state) async* {
                yield const Disposed();
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'state: $Working(a: 0, b: 0)',
              '[test2] done',
              '[test3] started',
              'state: $Disposed()',
              '[test3] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
            ]);
          }),
        );
      });

      group('State providers.', () {
        test(
          'check event rules - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                conveyor.testSetState(const Preparing());
                // Nothing happens because there is no consumer.
                state.test((it) => false).isA<Disposed>().map((it) => it);
              },
            );
            final event2 = TestEvent<Preparing>(
              key: 'test2',
              (state) async* {
                conveyor.testSetState(const Working());
                state.check();
              },
            );
            final event3 = TestEvent<Working>(
              key: 'test3',
              (state) async* {
                conveyor.testSetState(const Disposed());
                yield state.it;
              },
            );
            final event4 = TestEvent<Disposed>(
              key: 'test4',
              (state) async* {
                conveyor.testSetState(const Initial());
                yield state.use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'testSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'testSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test2] cancelled $CancelledByEventRules(is not $Preparing)',
              '[test3] started',
              'testSetState: $Disposed()',
              'state: $Disposed()',
              '[test3] cancelled $CancelledByEventRules(is not $Working)',
              '[test4] started',
              'testSetState: $Initial()',
              'state: $Initial()',
              '[test4] cancelled $CancelledByEventRules(is not $Disposed)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByEventRules(is not $Preparing)',
              '[test3] $CancelledByEventRules(is not $Working)',
              '[test4] $CancelledByEventRules(is not $Disposed)',
            ]);
          }),
        );

        test(
          'check event rules - ok',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.test((it) => false).isA<Disposed>().map((it) => it);
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state.use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );

        test(
          'test - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                conveyor.testSetState(const Preparing());
                // Nothing happens because there is no consumer.
                state.test((it) => false);
              },
            );
            final event2 = TestEvent<Preparing>(
              key: 'test2',
              (state) async* {
                conveyor.testSetState(const Working());
                state.test((it) => true).check();
              },
            );
            final event3 = TestEvent<Working>(
              key: 'test3',
              (state) async* {
                conveyor.testSetState(const Disposed());
                yield state.test((it) => true).it;
              },
            );
            final event4 = TestEvent<Disposed>(
              key: 'test4',
              (state) async* {
                conveyor.testSetState(const Initial());
                yield state.test((it) => true).use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'testSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'testSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test2] cancelled $CancelledByEventRules(is not $Preparing)',
              '[test3] started',
              'testSetState: $Disposed()',
              'state: $Disposed()',
              '[test3] cancelled $CancelledByEventRules(is not $Working)',
              '[test4] started',
              'testSetState: $Initial()',
              'state: $Initial()',
              '[test4] cancelled $CancelledByEventRules(is not $Disposed)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByEventRules(is not $Preparing)',
              '[test3] $CancelledByEventRules(is not $Working)',
              '[test4] $CancelledByEventRules(is not $Disposed)',
            ]);
          }),
        );

        test(
          'test - ok',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.test((it) => false);
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.test((it) => true).check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.test((it) => true).it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state.test((it) => true).use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );

        test(
          'isA - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                conveyor.testSetState(const Preparing());
                // Nothing happens because there is no consumer.
                state.isA<Preparing>();
              },
            );
            final event2 = TestEvent<Preparing>(
              key: 'test2',
              (state) async* {
                conveyor.testSetState(const Working());
                state.isA<Working>().check();
              },
            );
            final event3 = TestEvent<Working>(
              key: 'test3',
              (state) async* {
                conveyor.testSetState(const Disposed());
                yield state.isA<Disposed>().it as Working;
              },
            );
            final event4 = TestEvent<Disposed>(
              key: 'test4',
              (state) async* {
                conveyor.testSetState(const Initial());
                yield state.isA<Initial>().use((it) => const Disposed());
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'testSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'testSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test2] cancelled $CancelledByEventRules(is not $Preparing)',
              '[test3] started',
              'testSetState: $Disposed()',
              'state: $Disposed()',
              '[test3] cancelled $CancelledByEventRules(is not $Working)',
              '[test4] started',
              'testSetState: $Initial()',
              'state: $Initial()',
              '[test4] cancelled $CancelledByEventRules(is not $Disposed)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByEventRules(is not $Preparing)',
              '[test3] $CancelledByEventRules(is not $Working)',
              '[test4] $CancelledByEventRules(is not $Disposed)',
            ]);
          }),
        );

        test(
          'isA - ok',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.isA<Preparing>();
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.isA<Initial>().check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.isA<Initial>().it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state.isA<Initial>().use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );

        test(
          'map - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                conveyor.testSetState(const Preparing());
                // Nothing happens because there is no consumer.
                state.map<Initial>((it) => it);
              },
            );
            final event2 = TestEvent<Preparing>(
              key: 'test2',
              (state) async* {
                conveyor.testSetState(const Working());
                state.map<Preparing>((it) => it).check();
              },
            );
            final event3 = TestEvent<Working>(
              key: 'test3',
              (state) async* {
                conveyor.testSetState(const Disposed());
                yield state.map<Working>((it) => it).it;
              },
            );
            final event4 = TestEvent<Disposed>(
              key: 'test4',
              (state) async* {
                conveyor.testSetState(const Initial());
                yield state.map<Disposed>((it) => it).use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'testSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'testSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test2] cancelled $CancelledByEventRules(is not $Preparing)',
              '[test3] started',
              'testSetState: $Disposed()',
              'state: $Disposed()',
              '[test3] cancelled $CancelledByEventRules(is not $Working)',
              '[test4] started',
              'testSetState: $Initial()',
              'state: $Initial()',
              '[test4] cancelled $CancelledByEventRules(is not $Disposed)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByEventRules(is not $Preparing)',
              '[test3] $CancelledByEventRules(is not $Working)',
              '[test4] $CancelledByEventRules(is not $Disposed)',
            ]);
          }),
        );

        test(
          'map - ok',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.map<Initial>((it) => it);
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.map<Initial>((it) => it).check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.map<Initial>((it) => it).it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state.map<Initial>((it) => it).use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );

        test(
          'isA.test - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                conveyor.testSetState(const Preparing());
                // Nothing happens because there is no consumer.
                state.isA<Preparing>().test((it) => false);
              },
            );
            final event2 = TestEvent<Preparing>(
              key: 'test2',
              (state) async* {
                conveyor.testSetState(const Working());
                state.isA<TestState>().test((it) => true).check();
              },
            );
            final event3 = TestEvent<Working>(
              key: 'test3',
              (state) async* {
                conveyor.testSetState(const Disposed());
                yield state.isA<TestState>().test((it) => true).it as Working;
              },
            );
            final event4 = TestEvent<Disposed>(
              key: 'test4',
              (state) async* {
                conveyor.testSetState(const Initial());
                yield state
                    .isA<Preparing>()
                    .test((it) => true)
                    .use((it) => const Disposed());
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'testSetState: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'testSetState: $Working(a: 0, b: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test2] cancelled $CancelledByEventRules(is not $Preparing)',
              '[test3] started',
              'testSetState: $Disposed()',
              'state: $Disposed()',
              '[test3] cancelled $CancelledByEventRules(is not $Working)',
              '[test4] started',
              'testSetState: $Initial()',
              'state: $Initial()',
              '[test4] cancelled $CancelledByEventRules(is not $Disposed)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByEventRules(is not $Preparing)',
              '[test3] $CancelledByEventRules(is not $Working)',
              '[test4] $CancelledByEventRules(is not $Disposed)',
            ]);
          }),
        );

        test(
          'isA.test - ok',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.isA<Initial>().test((it) => false);
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.isA<Initial>().test((it) => true).check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.isA<Initial>().test((it) => true).it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state.isA<Initial>().test((it) => true).use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );

        test(
          'isA.isA.isA - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.isA<Initial>().isA<Working>().isA<Initial>();
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.isA<Initial>().isA<Working>().isA<Initial>().check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.isA<Initial>().isA<Working>().isA<Initial>().it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state
                    .isA<Initial>()
                    .isA<Working>()
                    .isA<Initial>()
                    .use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] cancelled $CancelledByCheckState(is not $Working)',
              '[test3] started',
              '[test3] cancelled $CancelledByCheckState(is not $Working)',
              '[test4] started',
              '[test4] cancelled $CancelledByCheckState(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $CancelledByCheckState(is not $Working)',
              '[test3] $CancelledByCheckState(is not $Working)',
              '[test4] $CancelledByCheckState(is not $Working)',
            ]);
          }),
        );

        test(
          'isA.isA.isA - cancel',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial>(
              key: 'test1',
              (state) async* {
                // Nothing happens because there is no consumer.
                state.isA<Initial>().isA<TestState>().isA<Initial>();
              },
            );
            final event2 = TestEvent<Initial>(
              key: 'test2',
              (state) async* {
                state.isA<Initial>().isA<TestState>().isA<Initial>().check();
              },
            );
            final event3 = TestEvent<Initial>(
              key: 'test3',
              (state) async* {
                yield state.isA<Initial>().isA<TestState>().isA<Initial>().it;
              },
            );
            final event4 = TestEvent<Initial>(
              key: 'test4',
              (state) async* {
                yield state
                    .isA<Initial>()
                    .isA<TestState>()
                    .isA<Initial>()
                    .use((it) => it);
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results)
              ..add(event4).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] started',
              '[test2] done',
              '[test3] started',
              'state: $Initial()',
              '[test3] done',
              '[test4] started',
              'state: $Initial()',
              '[test4] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
              '[test4] completed',
            ]);
          }),
        );
      });

      group('checkStateBeforeProcessing.', () {
        test(
          'it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'test.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'test.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().test((it) => it.progress == 0).it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .test((it) => it.progress == 0)
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not $Working)',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not $Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not $Working)',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.it',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().it;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );
      });

      group('checkState.', () {
        setUp(() {
          conveyor.externalSetState(const Preparing());
          conveyor.log.log;
        });

        test(
          'yield',
          () => fakeAsync((async) {
            final event = TestEvent<TestState>(
              key: 'test',
              checkState: (state) => state is Preparing,
              (state) async* {
                yield const Working();
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              '[test] cancelled $CancelledByEventRules(checkState)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByEventRules(checkState)',
            ]);
          }),
        );

        /// Суть ровно та же, что и в предыдущем тесте: yield не пропускает
        /// неправильное состояние. Но при отладке видно, что map.it пропускают
        /// неправильное значение.
        test(
          'it/use/check',
          () => fakeAsync((async) {
            final event1 = TestEvent<TestState>(
              key: 'test1',
              checkState: (state) => state is Preparing,
              (state) async* {
                final newState = state.map((_) => const Working()).it;
                state.log('map.it - ok');
                yield newState;
              },
            );
            final event2 = TestEvent<TestState>(
              key: 'test2',
              checkState: (state) => state is Preparing,
              (state) async* {
                final newState =
                    state.map((_) => const Working()).use((it) => it);
                state.log('map.use - ok');
                yield newState;
              },
            );
            final event3 = TestEvent<TestState>(
              key: 'test3',
              checkState: (state) => state is Preparing,
              (state) async* {
                state.map((_) => const Working()).check();
                state.log('map.check - ok');
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] map.it - ok',
              '[test1] cancelled $CancelledByEventRules(checkState)',
              '[test2] started',
              '[test2] map.use - ok',
              '[test2] cancelled $CancelledByEventRules(checkState)',
              '[test3] started',
              '[test3] map.check - ok',
              '[test3] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] $CancelledByEventRules(checkState)',
              '[test2] $CancelledByEventRules(checkState)',
              '[test3] completed',
            ]);
          }),
        );
      });
    });

    group('Queue.', () {
      TestEvent<TestState> noop(int num) {
        final event = TestEvent<Special>(
          key: 'noop$num',
          (state) async* {
            await Future(() {});
            yield state.use(
              (it) => it.copyWith(
                noopCount: it.noopCount + 1,
              ),
            );
          },
        );

        conveyor.queue.add(event);

        return event;
      }

      TestEvent<TestState> sequential(int num) {
        final event = TestEvent<Special>(
          key: 'sequential$num',
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.use(
              (state) => state.copyWith(
                sequentialCount: state.sequentialCount + 1,
              ),
            );
          },
        );

        conveyor.queue.add(event);

        return event;
      }

      TestEvent<TestState> droppable(int num) => conveyor.addEventOrDrop(
            check: (e) => e.key.startsWith('droppable'),
            create: () => TestEvent<Special>(
              key: 'droppable$num',
              (state) async* {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (it) => it.copyWith(
                    droppableCount: it.droppableCount + 1,
                  ),
                );
              },
            ),
          );

      TestEvent<TestState> droppableReturnPrevious(int num) =>
          conveyor.addEventOrDrop(
            returnPreviousIfExists: true,
            check: (e) => e.key.startsWith('droppable'),
            create: () => TestEvent<Special>(
              key: 'droppable$num',
              (state) async* {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (it) => it.copyWith(
                    droppableCount: it.droppableCount + 1,
                  ),
                );
              },
            ),
          );

      TestEvent<TestState> restartable(int num) => conveyor.addEventAndRestart(
            check: (e) => e.key.startsWith('restartable'),
            create: () => TestEvent<Special>(
              key: 'restartable$num',
              (state) async* {
                yield state.use(
                  (state) => state.copyWith(
                    restartableCount: state.restartableCount + 1,
                  ),
                );
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (state) => state.copyWith(
                    restartableCount: state.restartableCount + 1,
                  ),
                );
              },
            ),
          );

      setUp(() {
        conveyor.externalSetState(const Special());
        conveyor.log.log;
      });

      group('Sequential.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Droppable.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[droppable2] removed $RemovedManually()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] $RemovedManually()',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[droppable2] removed $RemovedManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] $RemovedManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[droppable1] started',
              '[droppable2] removed $RemovedManually()',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] $RemovedManually()',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              '[droppable2] removed $RemovedManually()',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] $RemovedManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
              '[droppable2] started',
              'state: $Special(droppable: 2)',
              '[droppable2] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[droppable2] started',
              'state: $Special(noop: 2, droppable: 2)',
              '[droppable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Droppable with return previous event when dropped.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable1]#2 completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 50));
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable1]#2 completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 150));
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
              '[droppable2] started',
              'state: $Special(droppable: 2)',
              '[droppable2] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable2]#2 completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[droppable2] started',
              'state: $Special(noop: 2, droppable: 2)',
              '[droppable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable2]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Restartable.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 2);

            expect(conveyor.log.log, [
              '[restartable1] removed $RemovedManually()',
              '[restartable2] started',
              'state: $Special(restartable: 1)',
              'state: $Special(restartable: 2)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] $RemovedManually()',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 2);

            expect(conveyor.log.log, [
              '[restartable1] removed $RemovedManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[noop2] started',
              'state: $Special(noop: 2)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 1)',
              'state: $Special(noop: 2, restartable: 2)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] $RemovedManually()',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 3);

            expect(conveyor.log.log, [
              '[restartable1] started',
              'state: $Special(restartable: 1)',
              '[restartable1] cancelled $CancelledManually()',
              '[restartable2] started',
              'state: $Special(restartable: 2)',
              'state: $Special(restartable: 3)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] $CancelledManually()',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 3);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[restartable1] started',
              'state: $Special(noop: 1, restartable: 1)',
              '[restartable1] cancelled $CancelledManually()',
              '[noop2] started',
              'state: $Special(noop: 2, restartable: 1)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 2)',
              'state: $Special(noop: 2, restartable: 3)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 3)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] $CancelledManually()',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 4);

            expect(conveyor.log.log, [
              '[restartable1] started',
              'state: $Special(restartable: 1)',
              'state: $Special(restartable: 2)',
              '[restartable1] done',
              '[restartable2] started',
              'state: $Special(restartable: 3)',
              'state: $Special(restartable: 4)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] completed',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 4);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[restartable1] started',
              'state: $Special(noop: 1, restartable: 1)',
              'state: $Special(noop: 1, restartable: 2)',
              '[restartable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, restartable: 2)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 3)',
              'state: $Special(noop: 2, restartable: 4)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 4)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] completed',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Debounce.', () {
        late Debouncer<void> debouncer;

        TestEvent<TestState> debounce(int num) {
          final lastEvent = conveyor.lastEventWhere(
            (e) => e.key.startsWith('debounce'),
          );

          final event = conveyor.queue.add(
            TestEvent<Special>(
              key: 'debounce$num',
              (state) async* {
                yield state.use(
                  (state) => state.copyWith(
                    debounceCount: state.debounceCount + 1,
                  ),
                );
              },
            ),
          );

          if (lastEvent != null || !debouncer.start()) {
            event.unlink();
          }

          return event;
        }

        setUp(() {
          debouncer = Debouncer<void>(const Duration(milliseconds: 100));
        });

        test(
          'One by one',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[debounce2] removed $RemovedManually()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] $RemovedManually()',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[debounce2] removed $RemovedManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] $RemovedManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] removed $RemovedManually()',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] $RemovedManually()',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] removed $RemovedManually()',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] $RemovedManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] started',
              'state: $Special(debounce: 2)',
              '[debounce2] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] started',
              'state: $Special(noop: 2, debounce: 2)',
              '[debounce2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Debounce with return previous event when dropped.', () {
        late Debouncer<TestEvent<TestState>> debouncerWithPrevious;

        TestEvent<TestState> debounceReturnPrevious(int num) {
          final lastEvent = conveyor.lastEventWhere(
            (e) => e.key.startsWith('debounce'),
          );
          if (lastEvent != null) {
            return lastEvent;
          }

          return debouncerWithPrevious.startWithData(
            onStart: () => conveyor.queue.add(
              TestEvent<Special>(
                key: 'debounce$num',
                (state) async* {
                  yield state.use(
                    (it) => it.copyWith(
                      debounceCount: it.debounceCount + 1,
                    ),
                  );
                },
              ),
            ),
          );
        }

        setUp(() {
          debouncerWithPrevious = Debouncer<TestEvent<TestState>>(
            const Duration(milliseconds: 100),
          );
        });

        test(
          'One by one',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce1]#2 completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 50));
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce1]#2 completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 150));
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] started',
              'state: $Special(debounce: 2)',
              '[debounce2] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce2]#2 completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] started',
              'state: $Special(noop: 2, debounce: 2)',
              '[debounce2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce2]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );
      });
    });

    group('Inner events.', () {
      void addEvents() {
        final event3 = TestEvent<Preparing>(
          key: 'test3',
          checkState: (state) => state.progress <= 100,
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.use((it) => it.copyWith(progress: 100));
          },
        );

        final event2 = TestEvent<PreparingAndWorking>(
          key: 'test2',
          checkStateBeforeProcessing: (state) => state is Preparing,
          checkStateOnExternalChange: (state) => state is Preparing,
          checkState: (state) => state is! Preparing || state.progress <= 100,
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.isA<Preparing>().use((it) => it.copyWith(progress: 50));

            event3.saveToResults(results);
            yield* state.run(event3);

            yield const Working();
          },
        );

        final event1 = TestEvent<TestState>(
          key: 'test1',
          checkStateBeforeProcessing: (state) => state is Initial,
          checkStateOnExternalChange: (state) => state is! Disposed,
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield const Preparing();

            event2.saveToResults(results);
            yield* state.run(event2);

            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state
                .isA<Working>()
                .use((it) => it.copyWith(a: it.a + 1, b: it.b + 1));

            yield const Disposed();
          },
        );

        conveyor.queue.add(event1).saveToResults(results);
      }

      test(
        'Simple test',
        () => fakeAsync((async) {
          addEvents();
          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Close after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Close after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            '> [test2] cancelled $CancelledByParent()',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
            '[test2] $CancelledByParent()',
          ]);
        }),
      );

      test(
        'Close after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            '>> [test3] cancelled $CancelledByParent()',
            '> [test2] cancelled $CancelledByParent()',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
            '[test2] $CancelledByParent()',
            '[test3] $CancelledByParent()',
          ]);
        }),
      );

      test(
        'Close after 350 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 350), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'externalSetState: $Disposed()',
            'state: $Disposed()',
            '[test1] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRules(checkStateOnExternalChange)',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'externalSetState: $Disposed()',
            'state: $Disposed()',
            '> [test2] cancelled $CancelledByEventRules(is not $PreparingAndWorking)',
            '[test1] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRules(checkStateOnExternalChange)',
            '[test2] $CancelledByEventRules(is not $PreparingAndWorking)',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'externalSetState: $Disposed()',
            'state: $Disposed()',
            '>> [test3] cancelled $CancelledByEventRules(is not $Preparing)',
            '> [test2] cancelled $CancelledByEventRules(is not $PreparingAndWorking)',
            '[test1] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRules(checkStateOnExternalChange)',
            '[test2] $CancelledByEventRules(is not $PreparingAndWorking)',
            '[test3] $CancelledByEventRules(is not $Preparing)',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 350 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 350), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'externalSetState: $Disposed()',
            'state: $Disposed()',
            '[test1] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRules(checkStateOnExternalChange)',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(100) after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.externalSetState(const Preparing(progress: 100));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'externalSetState: $Preparing(progress: 100)',
            'state: $Preparing(progress: 100)',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(100) after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.externalSetState(const Preparing(progress: 100));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'externalSetState: $Preparing(progress: 100)',
            'state: $Preparing(progress: 100)',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(100) after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Preparing(progress: 100));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'externalSetState: $Preparing(progress: 100)',
            'state: $Preparing(progress: 100)',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(100) after 350 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 350), () {
            conveyor.externalSetState(const Preparing(progress: 100));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'externalSetState: $Preparing(progress: 100)',
            'state: $Preparing(progress: 100)',
            '[test1] cancelled $CancelledByCheckState(is not $Working)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByCheckState(is not $Working)',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(999) after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.externalSetState(const Preparing(progress: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'externalSetState: $Preparing(progress: 999)',
            'state: $Preparing(progress: 999)',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Preparing(999) after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.externalSetState(const Preparing(progress: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'externalSetState: $Preparing(progress: 999)',
            'state: $Preparing(progress: 999)',
            '> [test2] cancelled $CancelledByEventRules(checkState)',
            '[test1] cancelled $CancelledByCheckState(is not $Working)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByCheckState(is not $Working)',
            '[test2] $CancelledByEventRules(checkState)',
          ]);
        }),
      );

      test(
        'Change state to Preparing(999) after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Preparing(progress: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'externalSetState: $Preparing(progress: 999)',
            'state: $Preparing(progress: 999)',
            '>> [test3] cancelled $CancelledByEventRules(checkState)',
            '> [test2] cancelled $CancelledByEventRules(checkState)',
            '[test1] cancelled $CancelledByCheckState(is not $Working)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByCheckState(is not $Working)',
            '[test2] $CancelledByEventRules(checkState)',
            '[test3] $CancelledByEventRules(checkState)',
          ]);
        }),
      );

      test(
        'Change state to Preparing(999) after 350 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 350), () {
            conveyor.externalSetState(const Preparing(progress: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'externalSetState: $Preparing(progress: 999)',
            'state: $Preparing(progress: 999)',
            '[test1] cancelled $CancelledByCheckState(is not $Working)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByCheckState(is not $Working)',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Working after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.externalSetState(const Working(a: 999, b: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'externalSetState: $Working(a: 999, b: 999)',
            'state: $Working(a: 999, b: 999)',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Working(a: 1, b: 1)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Change state to Working after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.externalSetState(const Working(a: 999, b: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'externalSetState: $Working(a: 999, b: 999)',
            'state: $Working(a: 999, b: 999)',
            '> [test2] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
            'state: $Working(a: 1000, b: 1000)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] $CancelledByEventRules(checkStateOnExternalChange)',
          ]);
        }),
      );

      test(
        'Change state to Working after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Working(a: 999, b: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'externalSetState: $Working(a: 999, b: 999)',
            'state: $Working(a: 999, b: 999)',
            '>> [test3] cancelled $CancelledByEventRules(is not $Preparing)',
            '> [test2] cancelled $CancelledByEventRules(checkStateOnExternalChange)',
            'state: $Working(a: 1000, b: 1000)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] $CancelledByEventRules(checkStateOnExternalChange)',
            '[test3] $CancelledByEventRules(is not $Preparing)',
          ]);
        }),
      );

      test(
        'Change state to Working after 350 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 350), () {
            conveyor.externalSetState(const Working(a: 999, b: 999));
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'externalSetState: $Working(a: 999, b: 999)',
            'state: $Working(a: 999, b: 999)',
            'state: $Working(a: 1000, b: 1000)',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );
    });

    group('Check state on yield.', () {
      void addEvents({
        bool Function(Preparing state)? parentCheckState,
        bool Function(Preparing state)? childCheckState,
        TestEvent<TestState>? innerEvent,
      }) {
        final event = TestEvent<Preparing>(
          key: 'parent',
          checkState: parentCheckState,
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));

            final innerEvent_ = innerEvent ??
                TestEvent<Preparing>(
                  key: 'child',
                  checkState: childCheckState,
                  (state) async* {
                    yield const Preparing(progress: 25);
                    yield const Preparing(progress: 50);
                    yield const Preparing(progress: 75);
                  },
                )
              ..saveToResults(results);

            yield* state.run(innerEvent_);

            yield const Preparing(progress: 100);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          },
        );

        conveyor.queue.add(event).saveToResults(results);
      }

      setUp(() {
        conveyor.externalSetState(const Preparing());
        conveyor.log.log;
      });

      test(
        'Standart flow',
        () => fakeAsync((async) {
          addEvents();

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 200));

          expect(conveyor.log.log, [
            '[parent] started',
            '> [child] started',
            'state: $Preparing(progress: 25)',
            'state: $Preparing(progress: 50)',
            'state: $Preparing(progress: 75)',
            '> [child] done',
            'state: $Preparing(progress: 100)',
            '[parent] done',
          ]);

          expect(resultsToStrings(), [
            '[parent] completed',
            '[child] completed',
          ]);
        }),
      );

      test(
        "Child sends an invalid parents's state (checkState)",
        () => fakeAsync((async) {
          addEvents(
            parentCheckState: (state) => state.progress != 50,
          );

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 100));

          expect(conveyor.log.log, [
            '[parent] started',
            '> [child] started',
            'state: Preparing(progress: 25)',
            '> [child] cancelled $CancelledByParent()',
            '[parent] cancelled $CancelledByEventRules(checkState)',
          ]);

          expect(resultsToStrings(), [
            '[parent] $CancelledByEventRules(checkState)',
            '[child] $CancelledByParent()',
          ]);
        }),
      );

      test(
        "Child sends an invalid parents's state (another state type)",
        () => fakeAsync((async) {
          addEvents(
            innerEvent: TestEvent<PreparingAndWorking>(
              key: 'child',
              (state) async* {
                yield const Working();
              },
            ),
          );

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 100));

          expect(conveyor.log.log, [
            '[parent] started',
            '> [child] started',
            '> [child] cancelled $CancelledByParent()',
            '[parent] cancelled $CancelledByEventRules(is not Preparing)',
          ]);

          expect(resultsToStrings(), [
            '[parent] $CancelledByEventRules(is not Preparing)',
            '[child] $CancelledByParent()',
          ]);
        }),
      );

      test(
        'Child yield an invalid state',
        () => fakeAsync((async) {
          addEvents(
            childCheckState: (state) => state.progress != 50,
          );

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 200));

          expect(conveyor.log.log, [
            '[parent] started',
            '> [child] started',
            'state: $Preparing(progress: 25)',
            '> [child] cancelled $CancelledByEventRules(checkState)',
            'state: $Preparing(progress: 100)',
            '[parent] done',
          ]);

          expect(resultsToStrings(), [
            '[parent] completed',
            '[child] $CancelledByEventRules(checkState)',
          ]);
        }),
      );

      test(
        "Invalid parents's and child's state",
        () => fakeAsync((async) {
          addEvents(
            parentCheckState: (state) => state.progress != 50,
            childCheckState: (state) => state.progress != 50,
          );

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 200));

          // Так как внутреннее событие прерывается при проверке собственного
          // [checkState], то проверка в родительском событии не
          // осуществляется, и оно продолжает успешно работать дальше.
          expect(conveyor.log.log, [
            '[parent] started',
            '> [child] started',
            'state: Preparing(progress: 25)',
            '> [child] cancelled $CancelledByEventRules(checkState)',
            'state: Preparing(progress: 100)',
            '[parent] done',
          ]);

          expect(resultsToStrings(), [
            '[parent] completed',
            '[child] $CancelledByEventRules(checkState)',
          ]);
        }),
      );

      test(
        'Change state after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          async.elapse(const Duration(milliseconds: 50));
          conveyor.testSetState(const Disposed());

          async.waitFuture(awaitResults());

          expect(async.elapsed, const Duration(milliseconds: 100));

          expect(conveyor.log.log, [
            '[parent] started',
            'testSetState: $Disposed()',
            'state: $Disposed()',
            '[child] removed $RemovedByEventRules(is not $Preparing)',
            '[parent] cancelled $CancelledByEventRules(is not $Preparing)',
          ]);

          expect(resultsToStrings(), [
            '[parent] $CancelledByEventRules(is not $Preparing)',
            '[child] $RemovedByEventRules(is not $Preparing)',
          ]);
        }),
      );
    });
  });
}
