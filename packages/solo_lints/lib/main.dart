/// The analyzer plugin of solo_lints.
///
/// The analysis server loads this library by its name and reads [plugin].
library;

import 'solo_lints.dart';

/// The plugin the analysis server runs.
final plugin = SoloLintsPlugin();
