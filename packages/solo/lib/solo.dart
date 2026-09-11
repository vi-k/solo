/// One job at a time: sequential jobs with exclusive state ownership,
/// declarative rules and cooperative cancellation.
library;

export 'package:async_job/async_job.dart';

export 'src/observer.dart';
export 'src/policy.dart';
export 'src/solo.dart';
export 'src/solo_base.dart';
export 'src/solo_cancel_reason.dart';
export 'src/transition.dart';
