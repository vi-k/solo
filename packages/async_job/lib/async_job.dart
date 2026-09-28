/// Cancellation, child jobs and resource cleanup for asynchronous Dart code.
///
/// Start with `Job`, which runs a function called its body and records how
/// it ended, and `JobContext`, which the body is given: checkpoints,
/// children and cleanup. A `Job` is not a `Future` itself: await `job.done`
/// for its outcome or `job.value` for what the body returned.
///
/// The guides — outcomes, cancellation, children, cleanup, observing and
/// building on the core — are on the documentation site:
/// https://docs.yet-another.dev/async_job/
///
/// This is the import for code that runs jobs. The protocol for building an
/// engine of your own on the core — `JobBase`, `JobContextBase` and
/// `JobStatus` — is in `package:async_job/engine.dart`.
library;

export 'src/job_base.dart' hide JobBase, JobContextBase, JobStatus;
