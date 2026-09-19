import 'package:solo/solo.dart';

import 'test_state.dart';

/// Opens the protected surface of [Solo] for tests: the five members a
/// controller builds its operations from, and what a subclass reads of its
/// queue and state.
mixin OpenSolo<S extends Object> on Solo<S> {
  @override
  SoloJob<T> job<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
    S Function(S state, Object error, StackTrace stackTrace)? onError,
    S Function(S state, Cancelled cancelled)? onCancel,
  }) =>
      super.job<W, T>(
        body,
        key: key,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
        onError: onError,
        onCancel: onCancel,
      );

  @override
  SoloAccumulator<E, T> collect<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, List<E> events) handler, {
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      super.collect<W, E, T>(
        handler,
        key: key,
        policy: policy,
        timing: timing,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
      );

  @override
  SoloAccumulator<E, T> accumulate<W extends S, E, T>(
    Future<T> Function(SoloContext<S, W> ctx, E value) handler, {
    required E Function(E accumulated, E incoming) merge,
    Object? key,
    AccumulationPolicy policy = AccumulationPolicy.join,
    AccumulationTiming? timing,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
  }) =>
      super.accumulate<W, E, T>(
        handler,
        merge: merge,
        key: key,
        policy: policy,
        timing: timing,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
      );

  @override
  SoloJob<T> add<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  }) =>
      super.add<T>(job, first: first, policy: policy);

  @override
  SoloJob<T> run<W extends S, T>(
    Future<T> Function(SoloContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
    Policy policy = Policy.sequential,
    S Function(S state, Object error, StackTrace stackTrace)? onError,
    S Function(S state, Cancelled cancelled)? onCancel,
  }) =>
      super.run<W, T>(
        body,
        key: key,
        canStart: canStart,
        keepWhile: keepWhile,
        cancellable: cancellable,
        describe: describe,
        policy: policy,
        onError: onError,
        onCancel: onCancel,
      );

  @override
  SoloQueue get queue => super.queue;

  @override
  Job<Object?>? get current => super.current;

  @override
  SoloJob<Object?>? lastJobWhere(bool Function(Job<Object?> job) test) =>
      super.lastJobWhere(test);

  @override
  bool get hasListeners => super.hasListeners;

  @override
  void externalSetState(S state) => super.externalSetState(state);
}

/// A controller over [TestState] with its protected surface open.
final class TestSolo extends Solo<TestState> with OpenSolo<TestState> {
  TestSolo([super.initialState = const Initial()]);
}

/// [TestSolo] with a stream, for the few tests that read one.
final class TestSoloStream extends Solo<TestState>
    with SoloStream, OpenSolo<TestState> {
  TestSoloStream([super.initialState = const Initial()]);
}
