part of 'job_base.dart';

/// What the job reads off a [ParallelWaitError], by [Job.visitErrors].
final class _EnvelopeAnalysis {
  const _EnvelopeAnalysis({
    required this.firstCancelled,
    required this.firstStackTrace,
    required this.cancellationCount,
    required this.hasRealFailure,
  });

  final Cancelled? firstCancelled;
  final StackTrace? firstStackTrace;
  final int cancellationCount;
  final bool hasRealFailure;

  bool get isCleanCancellation => cancellationCount > 0 && !hasRealFailure;
}

enum _EnvelopeNodeState { visiting, visited }

/// A frame for one supported error shape.
final class _EnvelopeFrame {
  final ParallelWaitError<Object?, Object?> envelope;
  final List<AsyncError?>? list;
  final List<Object?>? record;

  /// Read once, on the way in: a callback of the walk may change the list,
  /// and a length that moved under the index would never be reached.
  final int length;
  int index = 0;

  _EnvelopeFrame._list(this.envelope, List<AsyncError?> this.list)
      : record = null,
        length = list.length;

  _EnvelopeFrame._record(this.envelope, List<Object?> this.record)
      : list = null,
        length = record.length;

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

/// The walk behind [Job.visitErrors].
void _visitErrors(
  Object error,
  StackTrace stackTrace, {
  required void Function(Object error, StackTrace stackTrace) onFailure,
  void Function(Cancelled cancelled, StackTrace stackTrace)? onCancelled,
}) {
  if (error is Cancelled) {
    onCancelled?.call(error, stackTrace);
    return;
  }
  if (error is! ParallelWaitError<Object?, Object?>) {
    onFailure(error, stackTrace);
    return;
  }
  final root = _EnvelopeFrame.tryCreate(error);
  if (root == null) {
    onFailure(error, stackTrace);
    return;
  }

  // The walk is iterative because this error is public and callers may
  // build arbitrarily deep envelopes. Every list access is guarded because
  // a typed view can defer its type check until an element is read.
  var found = false;
  // By identity: `ParallelWaitError` is not a `final` class, and a subclass
  // with an `==` of its own would otherwise pass a nested envelope off as a
  // cycle.
  final states = Map<Object, _EnvelopeNodeState>.identity();
  final handedWhole = Set<Object>.identity();
  states[error] = _EnvelopeNodeState.visiting;
  final stack = <(_EnvelopeFrame, StackTrace)>[(root, stackTrace)];

  void failure(Object error, StackTrace stackTrace) {
    found = true;
    onFailure(error, stackTrace);
  }

  void whole(Object envelope, StackTrace stackTrace) {
    if (handedWhole.add(envelope)) {
      failure(envelope, stackTrace);
    }
  }

  while (stack.isNotEmpty) {
    final (frame, frameStackTrace) = stack.last;
    if (frame.index == frame.length) {
      states[frame.envelope] = _EnvelopeNodeState.visited;
      stack.removeLast();
      continue;
    }

    Object? branch;
    try {
      branch = frame.read();
    } on Object {
      whole(frame.envelope, frameStackTrace);
      continue;
    }
    if (branch == null) {
      continue;
    }
    if (branch is! AsyncError) {
      if (branch is ParallelWaitError<Object?, Object?>) {
        whole(branch, frameStackTrace);
      } else {
        failure(branch, frameStackTrace);
      }
      continue;
    }

    final branchError = branch.error;
    if (branchError is Cancelled) {
      found = true;
      onCancelled?.call(branchError, branch.stackTrace);
      continue;
    }
    if (branchError is! ParallelWaitError<Object?, Object?>) {
      failure(branchError, branch.stackTrace);
      continue;
    }
    switch (states[branchError]) {
      case _EnvelopeNodeState.visiting:
        whole(branchError, branch.stackTrace);
      case _EnvelopeNodeState.visited:
        // Walked already, by another path into the same node: its errors
        // are heard once. Walking it again would cost a path per shape
        // instead of a node per shape, which on a graph that shares nodes
        // is the difference between linear and exponential.
        break;
      case null:
        final nested = _EnvelopeFrame.tryCreate(branchError);
        if (nested == null) {
          whole(branchError, branch.stackTrace);
        } else {
          states[branchError] = _EnvelopeNodeState.visiting;
          stack.add((nested, branch.stackTrace));
        }
    }
  }

  if (!found) {
    onFailure(error, stackTrace);
  }
}

/// Analyzes a [ParallelWaitError], or returns `null` for an ordinary error.
_EnvelopeAnalysis? _analyzeEnvelope(Object error) {
  if (error is! ParallelWaitError<Object?, Object?>) {
    return null;
  }
  var cancellationCount = 0;
  Cancelled? firstCancelled;
  StackTrace? firstStackTrace;
  var hasRealFailure = false;
  _visitErrors(
    error,
    StackTrace.empty,
    onFailure: (_, __) => hasRealFailure = true,
    onCancelled: (cancelled, stackTrace) {
      cancellationCount++;
      firstCancelled ??= cancelled;
      firstStackTrace ??= stackTrace;
    },
  );
  return _EnvelopeAnalysis(
    firstCancelled: firstCancelled,
    firstStackTrace: firstStackTrace,
    cancellationCount: cancellationCount,
    hasRealFailure: hasRealFailure,
  );
}
