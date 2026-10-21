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
  /// Every error the job catches comes here, except a [Cancelled] the job ends
  /// with, and the hook only hears it: overriding it moves the error nowhere.
  /// That is the job's failure — its body's, or one an engine ended it with by
  /// hand — or an error with no outcome to carry it: an action
  /// [JobContext.abandonable] stopped waiting for failing later, a disposer, a
  /// cancellation callback, work handed over with [JobContext.unattended], the
  /// name of a child failing to format, a failure an engine handed to a job
  /// already over. A [Cancelled] comes here only when it is thrown where no
  /// outcome carries it, such as from a disposer or a callback, and never as
  /// the job giving up. Each error is told once per job, and one at a time:
  /// each failure and each cancellation inside a `ParallelWaitError` comes in a
  /// call of its own, with its own stack trace, as [Job.visitErrors] walks it.
  ///
  /// A failure can be the outcome of several jobs, and then it comes here once
  /// on each of them. A child of [JobContext.run] fails, its parent lets the
  /// failure out of its body, and an observer the child inherited hears the
  /// same object on the child and then on the parent. A branch of
  /// [JobContext.runAll] and its parent do the same, and so do a source and its
  /// continuation of [Job.then] given one observer. An observer that counts
  /// failures tells the second call from a new error by [identical], and an
  /// [Expando] remembers the errors it has heard without keeping them alive. An
  /// error thrown as a constant is the same object at every throw, and two such
  /// failures count as one. An [Expando] takes no string, number, boolean or
  /// record and throws when given one: such a value has no identity of its own
  /// to tell two calls apart, and the observer counts it at every call.
  ///
  /// Where each error goes from here, and what keeps it out of the answer, is
  /// in [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#where-each-error-goes)
  /// on the errors page.
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
  /// The default hands the error to the zone the job was created in, the way a
  /// job without a [JobAnswerer] does; an override that returns without calling
  /// `super` keeps it from the zone, and
  /// `super.onUnanswered(job, error, stackTrace)` sends it on as well. Every
  /// error that comes here has been through [onError] already. The job asks
  /// about one failure at a time: it walks a `ParallelWaitError` the way
  /// [Job.visitErrors] does and makes a call for each failure inside it, with
  /// that failure's stack trace. A cancellation never comes here — a
  /// [Cancelled], alone or inside a `ParallelWaitError`: it is a decision
  /// somebody made, not a failure.
  ///
  /// What comes: the errors no outcome carries — an action of
  /// [JobContext.abandonable] failing late, a disposer, a callback, work of
  /// [JobContext.unattended], a failure of the body of a job that ends
  /// [Cancelled], those an engine brings through [JobBase.finish] — and a
  /// failure a [Failed] outcome carries when nobody observes that outcome, a
  /// microtask after the job ends; [Job.ignoreFailure], or reading [Job.done]
  /// or [Job.value], keeps that one away. A [Failed] made of a cancellation
  /// goes to the zone past this hook: somebody made that outcome a failure on
  /// purpose. **An override that throws** does not take the error with it: the
  /// error goes to the zone the job was created in, and then what the override
  /// threw goes to the current zone.
  ///
  /// See [Answering for errors](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#answering-for-errors)
  /// on the errors page, and [Where each error goes](https://github.com/vi-k/solo/blob/main/packages/async_job/doc/errors.md#where-each-error-goes)
  /// for which error comes by which route.
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
