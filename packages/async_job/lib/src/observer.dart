part of 'job_base.dart';

/// Cross-cutting hooks of a single job: analytics, error reporting, a log.
///
/// Given to a job by whoever runs it — in `solo`, by the controller. A hook
/// that throws hands its error to the current zone and changes nothing
/// else: not the job's outcome, not the hook standing next to it. A
/// [Cancelled] a hook throws neither reaches the zone nor cancels the job: a
/// hook that has to calls [Job.cancel]. A [JobAnswerer.onUnanswered] that
/// throws does not take the error it was asked about with it: that error
/// goes to the zone first.
///
/// An observer watches: [onError] is told about the errors the job catches,
/// all but its own cancellation, and answers for none. The errors nobody else
/// has — those no outcome carries, and a failure whose outcome nobody
/// observes — are answered by an observer that is also a [JobAnswerer], and
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
  /// [JobAnswerer] among them the errors nobody answers for go to the zone
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
  /// Every error the job catches comes here once, except a [Cancelled] the
  /// job ends with: its failure, and the errors no outcome carries, such as
  /// those of cleanup, of callbacks and of work the job does not wait for. The
  /// hook only hears an error: overriding it moves the error nowhere, and a
  /// [JobAnswerer] is what answers for it. Each failure and each cancellation
  /// inside a `ParallelWaitError` comes in a call of its own, as
  /// [Job.visitErrors] walks it. One failure that is the outcome of several
  /// jobs, such as a child of [JobContext.run] and the parent it fails, comes
  /// once on each of them: tell the second call from a new error by
  /// [identical].
  ///
  /// [answer] says what the job does about this error: see [JobErrorAnswer].
  ///
  /// Which error comes by which route, and what keeps it out of the answer, is
  /// in [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/error-rules.md#where-each-error-goes)
  /// on the error rules page.
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) {}

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

/// What the job does about an error it hands to [JobObserver.onError].
///
/// Settled before the call and told with it, so an observer that reports in
/// both [JobObserver.onError] and [JobAnswerer.onUnanswered] can leave an
/// error to the hook that will hear it. Only [answered] promises an answer,
/// and only [cancellation] and [never] promise there is none; [later] promises
/// nothing.
///
/// See [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/error-rules.md#where-each-error-goes)
/// on the error rules page.
enum JobErrorAnswer {
  /// The job asks for an answer to the error: [JobAnswerer.onUnanswered] of
  /// an observer that answers, or the zone.
  ///
  /// Right after this call, or, for the failure of a body the job's
  /// cancellation covers, once the job has ended. A [Job.ignoreFailure] called
  /// before then takes that answer away. An overflow the body throws before
  /// its start has returned comes as [later] instead: if it cut the start
  /// short as well, the core ends the job with its failure ignored, and nobody
  /// answers for it.
  answered,

  /// The job never asks for an answer, because the error is a cancellation:
  /// a [Cancelled], or a failure of a job that has accepted a cancellation
  /// that [Job.isCancellationError] names.
  cancellation,

  /// The outcome that carries the error may still be read.
  ///
  /// The answer may be asked for later or never, and this value promises
  /// neither.
  later,

  /// The job never asks for an answer, and the error is not a cancellation.
  ///
  /// The failure of a job [Job.ignoreFailure] was called on, one this job
  /// carries for another that has been answered for already, or one inside a
  /// `ParallelWaitError` that the walk the job decided by did not meet. An
  /// ignored failure is never put to [Job.isCancellationError], so this may
  /// carry an error the filter would have called a cancellation.
  never,
}

/// An observer that answers for the errors nobody else has: those no
/// outcome carries, and a failure whose outcome nobody observes.
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
///       report(error, stackTrace);
/// }
/// ```
///
/// or `with JobObserver, JobAnswerer` when it extends another class. An
/// `onUnanswered` written on an observer that does not mix this in is a
/// method of its own: the job never calls it.
///
/// The job asks about one failure at a time: each failure inside a
/// `ParallelWaitError` on its own, with its own stack trace. About an
/// uncaught [Cancelled], alone or inside one, it does not ask.
mixin JobAnswerer on JobObserver {
  /// Answers for an error nobody else has answered for.
  ///
  /// Comes after [JobObserver.onError] for an error no outcome carries, and
  /// for the error of a [Failed] nobody observes by the microtask after the
  /// job ends. The default hands the error to the zone the job was created in;
  /// an override that returns without calling `super` keeps it from the zone.
  /// Each failure inside a `ParallelWaitError` comes in a call of its own, and
  /// a cancellation never comes. **An override that throws** does not take the
  /// error with it: the error goes to the zone the job was created in, and
  /// then what the override threw goes to the current zone.
  ///
  /// See [Answering for errors](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#answering-for-errors)
  /// on the errors page, and [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/error-rules.md#where-each-error-goes)
  /// on the error rules page for which error comes by which route.
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (job is JobBase<Object?> && (JobBase._builtOnCore[job] ?? false)) {
      job._toZone(error, stackTrace);
    } else if (!JobBase._isCancellation(error)) {
      // Called by hand with a job of another kind, or with one that
      // implements `JobBase` instead of extending it, the way a mock does:
      // the core always passes its own, so the zone it was created in is
      // not known here.
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
  void onError(
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => _each((o) => o.onError(job, error, stackTrace, answer: answer));

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
