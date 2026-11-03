/// The analyzer plugin of async_job_lints.
///
/// The analysis server loads this library by its name and reads [plugin].
library;

import 'async_job_lints.dart';

/// The plugin the analysis server runs.
final plugin = AsyncJobLintsPlugin();
