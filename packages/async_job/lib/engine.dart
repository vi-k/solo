/// The protocol for building an engine on the kernel: `JobBase`,
/// `JobContextBase` and `JobStatus`, together with everything
/// `package:async_job/async_job.dart` exports.
///
/// An engine imports this library in place of the main one. An app that
/// only runs jobs never needs it, and keeping it apart keeps the protected
/// machinery of the kernel out of every file that merely starts a job.
library;

export 'async_job.dart';
export 'src/job_base.dart' show JobBase, JobContextBase, JobStatus;
