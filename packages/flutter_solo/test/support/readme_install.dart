// What "Install" of `README.md` says arrives with one import, named here
// under that import and no other: that this file compiles is the test.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';

/// The names the page lists as arriving with the import, the mixin, the
/// widgets with the modes of one, and the selection it calls the package's
/// own part, and
/// `SoloStream`, which the last section says the package re-exports with
/// the rest of `solo`.
const arrivesWithOneImport = <Type>[
  Solo<Object>,
  SoloContext<Object, Object>,
  Job<Object>,
  Outcome<Object>,
  Policy,
  SoloListenable<Object>,
  SoloBuilder<Object>,
  SoloSelector<Object, Object>,
  SoloListener<Object>,
  SoloListenerMode,
  SoloSelection<Object, Object>,
  SoloStream<Object>,
];

/// The kinds the page gives the package's own part: a mixin on a
/// controller, three widgets and a class that is a listenable itself.
(SoloController<Object>, List<Widget>, ValueListenable<Object>) ownPart(
  SoloListenable<Object> controller,
  SoloBuilder<Object> builder,
  SoloSelector<Object, Object> selector,
  SoloListener<Object> listener,
  SoloSelection<Object, Object> selection,
) => (controller, [builder, selector, listener], selection);
