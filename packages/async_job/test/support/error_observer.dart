import 'package:async_job/async_job.dart';

/// Collects the errors a job hands to its observer.
///
/// It watches and answers for nothing: an error no outcome carries goes on
/// to the zone the job was created in, as it would with no observer. A test
/// whose subject is not where such an error goes, and that does not want it
/// in the zone, takes [ErrorObserver.answering] and says why.
final class ErrorObserver extends JobObserver {
  final List<Object> errors;
  final bool _answers;

  ErrorObserver(this.errors) : _answers = false;

  /// Answers for every error it collects: nothing reaches the zone.
  ErrorObserver.answering(this.errors) : _answers = true;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (!_answers) {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}
