// The app of "A base for both kinds" in `doc/mixins.md`, as its first
// block writes it: the base mixed in before `SoloListenable`, over the
// mixin of `mixins_base_both.dart`. `test/mixins_rakes_test.dart` runs it.
//
// The page shows no import for the app, and its states are the ones the
// README declares under "Usage".

import 'package:flutter_solo/flutter_solo.dart';

import 'mixins_base_both.dart';
import 'readme_profile.dart' show Empty, Profile;

// The app.
final class ProfileController extends Solo<Profile>
    with AppController, SoloListenable {
  ProfileController() : super(Empty());
}

/// The leaf of the page with a way to change its state: the page gives it
/// no operation, and a final class is extended in its own library only.
final class DrivenProfile extends ProfileController {
  void set(Profile state) => externalSetState(state);
}
