// The app of "A base class without Flutter" in `doc/mixins.md`, as "The
// first attempt" writes it, over the base of `mixins_base_first.dart`.
// `test/mixins_rakes_test.dart` runs it.
//
// The page shows no import for the app, and its states are the ones the
// README declares under "Usage".

import 'package:flutter_solo/flutter_solo.dart';

import 'mixins_base_first.dart';
import 'readme_profile.dart' show Empty, Profile;

// The app.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());
}

/// The leaf of the page with a way to change its state: the page gives it
/// no operation, and a final class is extended in its own library only.
final class DrivenProfile extends ProfileController {
  void set(Profile state) => externalSetState(state);
}
