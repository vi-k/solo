/// A cancellable `Future`: a job with an outcome, children and a
/// cooperative cancellation.
///
/// This is the import for code that runs jobs. The protocol for building an
/// engine of your own on the kernel — `JobBase`, `JobContextBase` and
/// `JobStatus` — is in `package:async_job/engine.dart`.
library;

export 'src/job_base.dart' hide JobBase, JobContextBase, JobStatus;
export 'src/observer.dart';
