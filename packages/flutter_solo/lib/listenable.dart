/// `select` and `listen` as methods, for an app that wants them.
///
/// Both are extensions on the framework's own types — [ValueListenable]
/// and [Listenable] — and that is why they live here, together with the
/// [SoloSubscription] and [SoloSubscriptions] that `listen` hands back,
/// rather than in `flutter_solo.dart`: two extensions with the same
/// member name on one type are ambiguous at every call site, so a
/// package that puts a `listen` of its own on [Listenable] would stop
/// compiling beside this one. The import is the choice — take it
/// alongside `flutter_solo.dart` where the methods are wanted.
///
/// ```dart
/// import 'package:flutter_solo/flutter_solo.dart';
/// import 'package:flutter_solo/listenable.dart';
///
/// final canSave = controller.select((state) => state.canSave);
/// final subscription = canSave.listen(() => print(canSave.value));
/// ```
///
/// Neither method is the only way in: without this import
/// `SoloSelection(controller, (state) => state.canSave)` builds the same
/// selection, and [SoloSelector] picks without holding one at all.
library;

import 'package:flutter/foundation.dart';

import 'flutter_solo.dart';
import 'src/subscription.dart';

export 'src/solo_selection.dart' show SoloSelect;
export 'src/subscription.dart';
