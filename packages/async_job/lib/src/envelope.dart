part of 'job_base.dart';

/// The result of inspecting all branches of a [ParallelWaitError].
final class _EnvelopeAnalysis {
  const _EnvelopeAnalysis({
    this.firstCancelled,
    this.firstStackTrace,
    this.cancellationCount = 0,
    this.hasRealFailure = false,
    this.hasUnparsed = false,
  });

  final Cancelled? firstCancelled;
  final StackTrace? firstStackTrace;
  final int cancellationCount;
  final bool hasRealFailure;
  final bool hasUnparsed;

  bool get isCleanCancellation =>
      cancellationCount > 0 && !hasRealFailure && !hasUnparsed;
}

enum _EnvelopeNodeState { visiting, visited }

/// A frame for one supported error shape.
final class _EnvelopeFrame {
  final ParallelWaitError<Object?, Object?> envelope;
  final List<AsyncError?>? list;
  final List<Object?>? record;
  int index = 0;

  _EnvelopeFrame._list(this.envelope, this.list) : record = null;

  _EnvelopeFrame._record(this.envelope, this.record) : list = null;

  int get length => list?.length ?? record!.length;

  Object? read() {
    if (list case final values?) {
      return values[index++];
    }
    return record![index++];
  }

  static _EnvelopeFrame? tryCreate(
    ParallelWaitError<Object?, Object?> envelope,
  ) {
    try {
      final errors = envelope.errors;
      if (errors is List<AsyncError?>) {
        return _EnvelopeFrame._list(envelope, errors);
      }
      final record = switch (errors) {
        (final a, final b) => <Object?>[a, b],
        (final a, final b, final c) => <Object?>[a, b, c],
        (final a, final b, final c, final d) => <Object?>[a, b, c, d],
        (final a, final b, final c, final d, final e) => <Object?>[
            a,
            b,
            c,
            d,
            e,
          ],
        (final a, final b, final c, final d, final e, final f) => <Object?>[
            a,
            b,
            c,
            d,
            e,
            f,
          ],
        (final a, final b, final c, final d, final e, final f, final g) =>
          <Object?>[a, b, c, d, e, f, g],
        (
          final a,
          final b,
          final c,
          final d,
          final e,
          final f,
          final g,
          final h
        ) =>
          <Object?>[a, b, c, d, e, f, g, h],
        (
          final a,
          final b,
          final c,
          final d,
          final e,
          final f,
          final g,
          final h,
          final i,
        ) =>
          <Object?>[a, b, c, d, e, f, g, h, i],
        _ => null,
      };
      return record == null ? null : _EnvelopeFrame._record(envelope, record);
    } on Object {
      return null;
    }
  }
}

/// Analyzes a [ParallelWaitError], or returns `null` for an ordinary error.
///
/// The walk is iterative because this error is public and callers may build
/// arbitrarily deep envelopes. Every list access is guarded because a typed
/// view can defer its type check until an element is read.
_EnvelopeAnalysis? _analyzeEnvelope(Object error) {
  if (error is! ParallelWaitError<Object?, Object?>) {
    return null;
  }

  var cancellationCount = 0;
  Cancelled? firstCancelled;
  StackTrace? firstStackTrace;
  var hasRealFailure = false;
  var hasUnparsed = false;
  // По тождеству: `ParallelWaitError` — не `final`-класс, и подкласс
  // с переопределённым `==` иначе выдал бы вложенный конверт за цикл.
  final states = Map<Object, _EnvelopeNodeState>.identity();
  final root = _EnvelopeFrame.tryCreate(error);
  if (root == null) {
    return const _EnvelopeAnalysis(hasUnparsed: true);
  }
  states[error] = _EnvelopeNodeState.visiting;
  final stack = <_EnvelopeFrame>[root];

  void addCancellation(AsyncError branch, Cancelled cancelled) {
    cancellationCount++;
    firstCancelled ??= cancelled;
    firstStackTrace ??= branch.stackTrace;
  }

  while (stack.isNotEmpty) {
    final frame = stack.last;
    if (frame.index == frame.length) {
      states[frame.envelope] = _EnvelopeNodeState.visited;
      stack.removeLast();
      continue;
    }

    Object? branch;
    try {
      branch = frame.read();
    } on Object {
      hasUnparsed = true;
      continue;
    }
    if (branch == null) {
      continue;
    }

    if (branch is AsyncError) {
      final branchError = branch.error;
      if (branchError is Cancelled) {
        addCancellation(branch, branchError);
        continue;
      }
      if (branchError is ParallelWaitError<Object?, Object?>) {
        final state = states[branchError];
        if (state == _EnvelopeNodeState.visiting) {
          hasUnparsed = true;
          continue;
        }
        final nested = _EnvelopeFrame.tryCreate(branchError);
        if (nested == null) {
          hasUnparsed = true;
          continue;
        }
        states[branchError] = _EnvelopeNodeState.visiting;
        stack.add(nested);
        continue;
      }
      hasRealFailure = true;
      continue;
    }
    hasRealFailure = true;
  }

  return _EnvelopeAnalysis(
    firstCancelled: firstCancelled,
    firstStackTrace: firstStackTrace,
    cancellationCount: cancellationCount,
    hasRealFailure: hasRealFailure,
    hasUnparsed: hasUnparsed,
  );
}
