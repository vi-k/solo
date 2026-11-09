// The code of `README.md` between "Why" and "Outcomes", verbatim, each
// fragment inside what a fragment needs around it: a function for a line of
// statements, a `State` for the members of one. The imports are the ones
// the page shows next to the code that needs them, and nothing else is
// imported here but the model and, under a prefix, the controller the page
// mixes `SoloListenable` into: the fragments that need a `ValueListenable`
// are handed that one. `test/readme_rakes_test.dart` runs it.
//
// A widget expression of the page ends with `),` on a line of its own, as an
// argument of a tree would, where a function that returned it would end
// with `);`. It stands as the one element of a list instead, which leaves
// the line as the page has it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

import 'readme_listenable.dart' as listenable;
import 'readme_profile.dart';

/// The fragment of "Why", as the body of a function that has a controller.
Future<void> why(ProfileController controller) async {
  final job = controller.load();

  await job.cancel(); // returns when the job has actually stopped
  // ignore: avoid_print
  print(job.outcome); // Cancelled(manual)
}

/// The builder of "The controller as a `ValueListenable`".
Widget listenableBuilder(listenable.ProfileController controller) => [
  ValueListenableBuilder<Profile>(
    valueListenable: controller,
    builder: (context, state, _) => Text(switch (state) {
      Empty() => 'no profile',
      Loading() => 'loading',
      Loaded(:final name) => name,
    }),
  ),
].single;

/// The merge of "The controller as a `ValueListenable`".
Widget mergedBuilder(
  listenable.ProfileController left,
  listenable.ProfileController right,
) => [
  ListenableBuilder(
    listenable: Listenable.merge([left, right]),
    builder: (context, _) => Text(
      left.value.canSave && right.value.canSave ? 'both loaded' : 'waiting',
    ),
  ),
].single;

/// The selector of "Selecting one value".
Widget saveSelector(ProfileController controller) => [
  SoloSelector<Profile, bool>(
    solo: controller,
    selector: (state) => state.canSave,
    builder: (context, canSave, _) => ElevatedButton(
      onPressed: canSave ? controller.save : null,
      child: const Text('Save'),
    ),
  ),
].single;

/// The widget whose `State` holds a selection in a field.
class SaveButton extends StatefulWidget {
  /// The controller the button saves to.
  final listenable.ProfileController controller;

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
    if (!identical(widget.controller, oldWidget.controller)) {
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

/// The widget of "Listening without keeping the callback": what its `State`
/// hears goes to [heard].
class Listening extends StatefulWidget {
  /// The controller listened to.
  final listenable.ProfileController controller;

  /// What the `State` was told, in order.
  final List<String> heard;

  /// Whether the `State` is the first attempt of the section.
  final bool firstAttempt;

  /// Whether the `State` listens with a method of its own.
  final bool withMethod;

  /// A widget that listens to [controller].
  const Listening({
    required this.controller,
    required this.heard,
    this.firstAttempt = false,
    this.withMethod = false,
    super.key,
  });

  @override
  State<Listening> createState() =>
      // The switch is the test's: one widget for the versions of the page.
      // ignore: no_logic_in_create_state
      firstAttempt
      ? _FirstAttemptState()
      : withMethod
      ? _MethodState()
      : _ListeningState();
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

class _MethodState extends State<Listening> {
  void _onChange() => _onState(widget.controller.value);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onState(Profile state) => widget.heard.add('state ${show(state)}');

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _ListeningState extends State<Listening> {
  late final canSave = SoloSelection(
    widget.controller,
    (state) => state.canSave,
  );

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

/// The state of the connection "Reacting to a change" follows, which the page
/// takes as the application's own.
enum Connection {
  /// The network is there.
  online,

  /// The network is gone.
  offline,
}

/// The controller of [Connection] the page names `connection`: the
/// application writes it from wherever it learns of the network.
final class ConnectionController extends Solo<Connection> {
  /// A connection that starts [Connection.online].
  ConnectionController() : super(Connection.online);

  /// Writes [state] as the application would.
  void set(Connection state) => externalSetState(state);
}

/// The first attempt of "Reacting to a change".
Widget snackBarInBuild(
  ConnectionController connection,
  ProfileController controller,
) => [
  SoloBuilder<Connection>(
    solo: connection,
    builder: (context, state, child) {
      if (state == Connection.offline) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No connection')));
      }

      return child!;
    },
    child: ProfileView(controller: controller),
  ),
].single;

/// The answer of "Reacting to a change".
Widget snackBarInReaction(
  ConnectionController connection,
  ProfileController controller,
) => [
  SoloListener<Connection>(
    solo: connection,
    listenWhen: (previous, current) =>
        previous == Connection.online && current == Connection.offline,
    listener: (ctx, context, state) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No connection')));
    },
    child: ProfileView(controller: controller),
  ),
].single;

/// The text a search field writes, which "A reaction the next change
/// replaces" names `query`.
final class QueryController extends Solo<String> {
  /// A query that starts empty.
  QueryController() : super('');

  /// Writes [text] as the search field would.
  void type(String text) => externalSetState(text);
}

/// The call of the application the page names `api.suggest`: it answers
/// [delay] after the call, and says what it did in [log].
class SearchApi {
  /// How long a call takes.
  final Duration delay;

  /// `load <text>` when a call starts, `loaded <text>` when it answers.
  final List<String> log;

  /// An API that answers [delay] after the call.
  SearchApi(this.log, {this.delay = const Duration(milliseconds: 100)});

  /// The suggestions for [text].
  Future<List<String>> suggest(String text) async {
    log.add('load $text');
    await Future<void>.delayed(delay);
    log.add('loaded $text');
    return ['$text.'];
  }
}

/// The list under the search field, which the page takes as the
/// application's own.
class SuggestionList extends StatelessWidget {
  /// What the list shows.
  final List<String> suggestions;

  /// A list of [suggestions].
  const SuggestionList({required this.suggestions, super.key});

  @override
  Widget build(BuildContext context) => Text(suggestions.join(' '));
}

/// The versions of `_suggest` in "A reaction the next change replaces".
enum Suggesting {
  /// A plain `await`.
  firstAttempt,

  /// `ctx.join`.
  join,

  /// `ctx.pause` and `ctx.abandonable`.
  abandonable,
}

/// The screen of "A reaction the next change replaces".
class Search extends StatefulWidget {
  /// What the search field writes.
  final QueryController query;

  /// Where the suggestions come from.
  final SearchApi api;

  /// The version of `_suggest` the screen takes.
  final Suggesting how;

  /// A screen that suggests for [query] the way [how] says.
  const Search({
    required this.query,
    required this.api,
    required this.how,
    super.key,
  });

  @override
  State<Search> createState() =>
      // The switch is the test's: one widget for the versions of the page.
      // ignore: no_logic_in_create_state
      switch (how) {
        Suggesting.firstAttempt => _FirstAttemptSearchState(),
        Suggesting.join => _JoinSearchState(),
        Suggesting.abandonable => _AbandonableSearchState(),
      };
}

abstract class _SearchState extends State<Search> {
  var _suggestions = const <String>[];

  QueryController get query => widget.query;

  SearchApi get api => widget.api;

  Future<void> _suggest(JobContext ctx, BuildContext context, String text);

  @override
  Widget build(BuildContext context) => [
    SoloListener<String>(
      solo: query,
      mode: SoloListenerMode.restart,
      listener: _suggest,
      child: SuggestionList(suggestions: _suggestions),
    ),
  ].single;
}

class _FirstAttemptSearchState extends _SearchState {
  @override
  Future<void> _suggest(
    JobContext ctx,
    BuildContext context,
    String text,
  ) async {
    final found = await api.suggest(text);
    setState(() => _suggestions = found);
  }
}

class _JoinSearchState extends _SearchState {
  @override
  Future<void> _suggest(
    JobContext ctx,
    BuildContext context,
    String text,
  ) async {
    final found = await ctx.join(() => api.suggest(text));
    setState(() => _suggestions = found);
  }
}

class _AbandonableSearchState extends _SearchState {
  @override
  Future<void> _suggest(
    JobContext ctx,
    BuildContext context,
    String text,
  ) async {
    await ctx.pause(const Duration(milliseconds: 300));
    final found = await ctx.abandonable(() => api.suggest(text));
    setState(() => _suggestions = found);
  }
}

/// What the callback of [secondImport] was told.
final heardBySecondImport = <bool>[];

void _onCanSave(bool canSave) => heardBySecondImport.add(canSave);

/// The two lines of "Methods from a second import".
(SoloSelection<Profile, bool>, SoloSubscription) secondImport(
  listenable.ProfileController controller,
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
    controller.load();
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
  const LoadButton({required this.controller, required this.toasts, super.key});

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
