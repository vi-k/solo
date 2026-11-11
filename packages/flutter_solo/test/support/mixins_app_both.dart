// The app of "A base for both kinds" in `doc/mixins.md`, as its second
// block writes it: the base mixed in after `SoloListenable`, on a `Solo`
// and on a `SoloLanes`, over the mixin of `mixins_base_both.dart`.
// `test/mixins_rakes_test.dart` runs it.
//
// The page shows no import for the app, and its states are the ones the
// README declares under "Usage".

import 'package:flutter_solo/flutter_solo.dart';

import 'mixins_base_both.dart';
import 'readme_profile.dart' show Empty, Profile;

// The app.
final class ProfileController extends Solo<Profile>
    with SoloListenable, AppController {
  ProfileController() : super(Empty());
}

final class ProfileLanes extends SoloLanes<Profile>
    with SoloListenable, AppController {
  ProfileLanes() : super(Empty());
}

/// The leaves of the page with a way to change their state: the page gives
/// them no operation, and a final class is extended in its own library only.
final class DrivenProfile extends ProfileController {
  void set(Profile state) => externalSetState(state);
}

final class DrivenLanes extends ProfileLanes {
  void set(Profile state) => externalSetState(state);
}
