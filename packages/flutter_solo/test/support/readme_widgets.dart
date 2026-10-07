// The code of `README.md` between "Why" and "Outcomes", verbatim, each
// fragment inside what a fragment needs around it: a function for a line of
// statements, a `State` for the members of one. The imports are the ones
// the page shows next to the code that needs them, and nothing else is
// imported here but the model. `test/readme_rakes_test.dart` runs it.
//
// A widget expression of the page ends with `)` on a line of its own, where
// a function that returned it would end with `);`. It stands as the one
// element of a list instead, which leaves the line as the page has it, and
// the comma a list would otherwise be asked for is what the rule below is
// switched off for.
//
// ignore_for_file: require_trailing_commas

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

import 'readme_profile.dart';

/// The fragment of "Why", as the body of a function that has a controller.
Future<void> why(ProfileController controller) async {
  final job = controller.load();

  await job.cancel(); // returns when the job has actually stopped
  // ignore: avoid_print
  print(job.outcome); // Cancelled(manual)
}

/// The selector of "Selecting one value".
Widget saveSelector(ProfileController controller) => [
      SoloSelector<Profile, bool>(
        solo: controller,
        selector: (state) => state.canSave,
        builder: (context, canSave, _) => ElevatedButton(
          onPressed: canSave ? controller.save : null,
          child: const Text('Save'),
        ),
      )
    ].single;

/// The widget whose `State` holds a selection in a field.
class SaveButton extends StatefulWidget {
  /// The controller the button saves to.
  final ProfileController controller;

  /// A Save button over [controller].
  const SaveButton({required this.controller, super.key});

  @override
  State<SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<SaveButton> {
  late SoloSelection<Profile, bool> canSave = _select();

  SoloSelection<Profile, bool> _select() =>
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  void didUpdateWidget(SaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      canSave = _select();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: canSave,
        builder: (context, enabled, _) => ElevatedButton(
          onPressed: enabled ? widget.controller.save : null,
          child: const Text('Save'),
        ),
      );
}

/// The builder of "Builders for any controller".
Widget anyBuilder(Solo<Profile> controller) => [
      SoloBuilder<Profile>(
        solo: controller,
        builder: (context, state, _) => Text(
          switch (state) {
            Empty() => 'no profile',
            Loading() => 'loading',
            Loaded(:final name) => name,
          },
        ),
      )
    ].single;

/// The widget of "Listening without keeping the callback": what its `State`
/// hears goes to [heard].
class Listening extends StatefulWidget {
  /// The controller listened to.
  final ProfileController controller;

  /// What the `State` was told, in order.
  final List<String> heard;

  /// Whether the `State` is the first attempt of the section.
  final bool firstAttempt;

  /// A widget that listens to [controller].
  const Listening({
    required this.controller,
    required this.heard,
    this.firstAttempt = false,
    super.key,
  });

  @override
  State<Listening> createState() =>
      // The switch is the test's: one widget for both versions of the page.
      // ignore: no_logic_in_create_state
      firstAttempt ? _FirstAttemptState() : _ListeningState();
}

class _FirstAttemptState extends State<Listening> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => _onState(widget.controller.value));
  }

  @override
  void dispose() {
    widget.controller.removeListener(() => _onState(widget.controller.value));
    super.dispose();
  }

  void _onState(Profile state) => widget.heard.add('state ${show(state)}');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _ListeningState extends State<Listening> {
  late final canSave =
      SoloSelection(widget.controller, (state) => state.canSave);

  final _listening = SoloSubscriptions();

  @override
  void initState() {
    super.initState();
    widget.controller
        .listen(() => _onState(widget.controller.value))
        .addTo(_listening);
    canSave.listen(() => _onCanSave(canSave.value)).addTo(_listening);
  }

  @override
  void dispose() {
    _listening.cancel();
    super.dispose();
  }

  void _onState(Profile state) => widget.heard.add('state ${show(state)}');

  void _onCanSave(bool canSave) => widget.heard.add('canSave $canSave');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// What the callback of [secondImport] was told.
final heardBySecondImport = <bool>[];

void _onCanSave(bool canSave) => heardBySecondImport.add(canSave);

/// The two lines of "Methods from a second import".
(SoloSelection<Profile, bool>, SoloSubscription) secondImport(
  ProfileController controller,
) {
  final canSave = controller.select((state) => state.canSave);
  final subscription = canSave.listen(() => _onCanSave(canSave.value));

  return (canSave, subscription);
}

/// The screen of "The controller's life".
class ProfileScreen extends StatefulWidget {
  /// A screen that owns its controller.
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final controller = ProfileController(ProfileApi());

  @override
  void initState() {
    super.initState();
    controller.load().ignoreFailure();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProfileView(controller: controller);
}

/// The controller [screen] owns: its `State` is private to this library.
ProfileController controllerOf(State<ProfileScreen> screen) =>
    (screen as _ProfileScreenState).controller;

/// The widget of "Outcomes": what `_toast` is given goes to [toasts].
class LoadButton extends StatefulWidget {
  /// The controller whose `load` the button calls.
  final ProfileController controller;

  /// Every toast, in order.
  final List<String> toasts;

  /// A Load button over [controller].
  const LoadButton({
    required this.controller,
    required this.toasts,
    super.key,
  });

  @override
  State<LoadButton> createState() => _LoadButtonState();
}

class _LoadButtonState extends State<LoadButton> {
  ProfileController get controller => widget.controller;

  void _toast(String message) => widget.toasts.add(message);

  Future<void> _load() async {
    switch (await controller.load().done) {
      case Done(:final value):
        if (mounted) _toast('hello $value');
      case Failed(:final error):
        if (mounted) _toast('$error');
      case Cancelled():
        break; // left the screen, and close() cancelled the job
    }
  }

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: _load, child: const Text('Load'));
}
