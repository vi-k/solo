// What "Install" of `README.md` says arrives with one import, named here
// under that import and no other: that this file compiles is the test.

import 'package:flutter_solo/flutter_solo.dart';

/// The names the page lists as arriving with the import, the widgets and
/// the selection it says come with the mixin, and `SoloStream`, which the
/// last section says the package re-exports with the rest of `solo`.
const arrivesWithOneImport = <Type>[
  Solo<Object>,
  SoloContext<Object, Object>,
  Job<Object>,
  Outcome<Object>,
  Policy,
  SoloListenable<Object>,
  SoloBuilder<Object>,
  SoloSelector<Object, Object>,
  SoloSelection<Object, Object>,
  SoloStream<Object>,
];
