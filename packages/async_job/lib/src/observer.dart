part of 'job_base.dart';

/// Cross-cutting hooks of a single job: analytics, error reporting, a log.
///
/// Given to a job by whoever runs it — in `solo`, by the controller. A hook
/// that throws hands its error to the current zone and changes nothing
/// else: not the job's outcome, not the hook standing next to it. A
/// [Cancelled] a hook throws neither reaches the zone nor cancels the job: a
/// hook that has to calls [Job.cancel].
///
/// An observer watches: [onError] is told about the errors the job catches,
/// all but its own cancellation, and answers for none. The errors no outcome
/// carries are answered by an observer that is also a [JobAnswerer], and
/// without one they go to the zone the job was created in — the same place
/// they go when the job has no observer at all. An observer written to
/// watch changes nowhere an error goes.
///
/// A class that already extends another one mixes this in, `with JobObserver`,
/// and overrides the hooks it needs the same way. Several observers watch one
/// job through [JobObserver.all].
abstract mixin class JobObserver {
  /// Creates an observer; a subclass calls it implicitly.
  JobObserver();

  /// One observer made of [observers], in their order.
  ///
  /// Every hook of this class goes to each of [observers] in turn, each call
  /// on its own: one that throws hands its error to the current zone, and the
  /// next is called all the same. The one among them that is a [JobAnswerer]
  /// watches in its place and answers as well: [JobAnswerer.onUnanswered]
  /// goes to it alone, after every observer has heard [onError]. With no
  /// [JobAnswerer] among them the errors no outcome carries go to the zone
  /// the job was created in, once, as they do for a job with no observer.
  ///
  /// ```dart
  /// final class Crashes extends JobObserver with JobAnswerer { ... }
  ///
  /// Job<void>(observer: JobObserver.all([Log(), Crashes()]), body);
  /// ```
  ///
  /// An observer made this way is a [JobAnswerer] when one of [observers] is,
  /// so one of them may itself be made by [JobObserver.all]. Throws
  /// [ArgumentError] when more than one of [observers] answers, or when the
  /// same observer comes twice, counting those inside one made by
  /// [JobObserver.all]: it would hear every hook twice. [observers] is walked
  /// once, here, and kept as a copy.
  ///
  /// A lazy message of [onLog] is built by every observer that builds one:
  /// as many times as there are such observers.
  factory JobObserver.all(Iterable<JobObserver> observers) {
    final all = List<JobObserver>.unmodifiable(observers);
    final seen = HashSet<JobObserver>.identity();
    void visit(JobObserver observer) {
      if (!seen.add(observer)) {
        throw ArgumentError.value(
          observers,
          'observers',
          '$observer comes twice and would hear every hook twice',
        );
      }
      if (observer is _AllObservers) {
        observer._observers.forEach(visit);
      }
    }

    all.forEach(visit);
    final answerers = all.whereType<JobAnswerer>().toList();
    return switch (answerers) {
      [] => _AllObservers(all),
      [final answerer] => _AllObserversAnswering(all, answerer),
      _ => throw ArgumentError.value(
          observers,
          'observers',
          'more than one answers: ${answerers.join(', ')}',
        ),
    };
  }

  /// A job body is about to run.
  void onStart(Job<Object?> job) {}

  /// A job has an outcome, including jobs dropped before start.
  void onFinish(Job<Object?> job) {}

  /// Something the job did threw.
  ///
  /// The job's failure — its body's, or one an engine of a domain ended it with
  /// by hand — or one of the errors with no outcome to carry them: an action
  /// abandoned by [JobContext.abandonable] failing later, a disposer, a
  /// cancellation callback, work handed over with [JobContext.unattended], a
  /// failure while formatting a child's cancellation description, or a failure
  /// an engine of a domain handed to a job already over. Each is told here
  /// once.
  ///
  /// Notification only: overriding it changes nothing about where the error
  /// goes. The errors with no outcome go on to [JobAnswerer.onUnanswered] of an
  /// observer that answers, and so do two failures of the body: that of a
  /// branch of [JobContext.runAll] the group did not throw, and one a
  /// cancellation covered afterwards. [Job.ignoreFailure] on the job stops
  /// these two here. Any other failure of the job is carried by the outcome,
  /// and one nobody observes reaches the zone — all but a failure that happened
  /// after the job accepted a cancellation: an operation stopping at the job's
  /// token looks like that, and only this hook hears it.
  ///
  /// A [Cancelled] reaches this hook whenever one is thrown where there is
  /// no outcome to carry it — never the job giving up, which is not an
  /// error and never comes here. A disposer or a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled] that throws one;
  /// `throw Cancelled(...)` inside unattended work, where there is nobody
  /// left to cancel and the object is new; a fresh `Cancelled` built by
  /// the rules of a domain for a context that outlived its job; a child's
  /// cancellation taken through `child.value` from one of those places
  /// rather than from the body, where it becomes the outcome instead and
  /// never comes here.
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// A job called [JobContext.log], with what it passed.
  ///
  /// [message] arrives as the body gave it, untouched: making a line out
  /// of it is this listener's business, and a `toString` that throws while
  /// it does is a hook that throws — the error goes to the current zone
  /// and nothing else changes. A body that wants its message built only
  /// when somebody listens passes a closure, and calling it is this
  /// listener's convention: one that prints the message as it came prints
  /// the closure itself.
  void onLog(Job<Object?> job, Object? message) {}
}

/// An observer that answers for the errors no outcome carries.
///
/// The job asks [onUnanswered] of its observer only when the observer is a
/// [JobAnswerer]; otherwise those errors go to the zone the job was created
/// in. A class mixes it in after [JobObserver]:
///
/// ```dart
/// final class Crashes extends JobObserver with JobAnswerer {
///   @override
///   void onUnanswered(
///     Job<Object?> job,
///     Object error,
///     StackTrace stackTrace,
///   ) =>
///       Job.visitErrors(error, stackTrace, onFailure: report);
/// }
/// ```
///
/// or `with JobObserver, JobAnswerer` when it extends another class. An
/// `onUnanswered` written on an observer that does not mix this in is a
/// method of its own: the job never calls it.
///
/// [Job.visitErrors] hands `report` each failure inside a
/// `ParallelWaitError` on its own and drops each uncaught [Cancelled], alone
/// or inside one.
mixin JobAnswerer on JobObserver {
  /// Nobody answered for this error, and this observer is the last one
  /// holding it.
  ///
  /// The errors no outcome carries: an action abandoned by
  /// [JobContext.abandonable] failing later, a disposer, a callback of
  /// [JobContext.onCancel] or [Job.whenCancelled], work handed over with
  /// [JobContext.unattended], a failure while formatting a child's cancellation
  /// description, the failure of a branch of [JobContext.runAll] that the group
  /// did not throw, and a failure of the body that a cancellation covered
  /// afterwards — the outcome carries the cancellation, whoever reads it.
  /// [Job.ignoreFailure] keeps the last two from coming here. So does a failure
  /// an engine of a domain hands to a job already over, and [Job.ignoreFailure]
  /// keeps that one away as well. Any other failure of a body does not come
  /// here: it has an outcome, and one nobody observes reaches the zone by
  /// itself. Every error that comes here has been through [onError] already.
  ///
  /// **What the default body does.** It hands the error to the zone the
  /// job was created in — where the error goes when the job has no
  /// observer, or one that does not answer. A cancellation is the exception
  /// and goes nowhere: a [Cancelled], and a `ParallelWaitError` carrying
  /// nothing but cancellations. A cancellation is a decision somebody made,
  /// not a failure.
  ///
  /// **Override it to answer here instead** — an observer that reports to
  /// its own system and stops there. An override that says nothing keeps
  /// these errors out of the zone. Call
  /// `super.onUnanswered(job, error, stackTrace)` to keep the zone as well.
  /// [Job.visitErrors] tells each uncaught [Cancelled] from the failures,
  /// those inside a `ParallelWaitError` too.
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (job is JobBase<Object?>) {
      job._toZone(error, stackTrace);
    } else if (!JobBase._isCancellation(error)) {
      // Called by hand with a job of another kind: the core always passes
      // its own, so the zone it was created in is not known here.
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}

/// [JobObserver.all] with no [JobAnswerer] among its observers. Not one
/// itself: the job sends what nobody answers for to the zone it was created
/// in, once.
final class _AllObservers with JobObserver {
  final List<JobObserver> _observers;

  _AllObservers(this._observers);

  // Each call on its own, the way the core calls a single observer: one
  // that throws must not switch off the ones after it.
  void _each(void Function(JobObserver observer) hook) {
    for (final observer in _observers) {
      JobBase._notify(() => hook(observer));
    }
  }

  @override
  void onStart(Job<Object?> job) => _each((o) => o.onStart(job));

  @override
  void onFinish(Job<Object?> job) => _each((o) => o.onFinish(job));

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _each((o) => o.onError(job, error, stackTrace));

  @override
  void onLog(Job<Object?> job, Object? message) =>
      _each((o) => o.onLog(job, message));

  @override
  String toString() => 'JobObserver.all($_observers)';
}

/// [JobObserver.all] with one [JobAnswerer] among its observers, which
/// answers for all of them.
final class _AllObserversAnswering extends _AllObservers with JobAnswerer {
  final JobAnswerer _answerer;

  _AllObserversAnswering(super._observers, this._answerer);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _answerer.onUnanswered(job, error, stackTrace);
}
