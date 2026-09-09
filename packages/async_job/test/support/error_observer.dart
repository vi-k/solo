import 'package:async_job/async_job.dart';

/// Collects the errors a job hands to its observer.
final class ErrorObserver extends JobObserver {
  final List<Object> errors;

  ErrorObserver(this.errors);

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}
