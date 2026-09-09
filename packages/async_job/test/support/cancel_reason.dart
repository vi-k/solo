import 'package:async_job/async_job.dart';

/// A consumer-defined reason, including optional diagnostic data.
final class TestCancelReason extends CancelReason {
  @override
  final String name;

  /// The failure that prompted cancellation.
  final Object? error;

  /// The original failure's stack, separate from the cancellation stack.
  final StackTrace? stackTrace;

  /// Creates a reason with the given data.
  const TestCancelReason(this.name, {this.error, this.stackTrace});
}
