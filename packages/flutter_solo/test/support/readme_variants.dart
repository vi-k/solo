// What `README.md` says in prose about code it does not show: the versions
// a sentence compares the page's code with, and the controllers a test needs
// to reach what `ProfileController` keeps protected. None of this is page
// code, and `test/readme_rakes_test.dart` never looks for the page's code
// here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

import 'readme_profile.dart';

/// A controller over the states of the page that a test can steer: it
/// writes a state from outside, runs a body of the test's own and counts
/// its listeners.
final class Bench extends Solo<Profile> with SoloListenable {
  /// How many times `addListener` was called.
  int added = 0;

  /// How many times `removeListener` was called.
  int removed = 0;

  /// A controller in [state].
  Bench([Profile? state]) : super(state ?? Empty());

  /// Writes [state] from outside a job.
  void set(Profile state) => externalSetState(state);

  /// Runs [body] as a root job under the rules given.
  Job<T> go<W extends Profile, T>(
    Future<T> Function(SoloContext<Profile, W> ctx) body, {
    bool Function(W state)? keepWhile,
  }) =>
      run<W, T>(body, keepWhile: keepWhile);

  @override
  void addListener(void Function() listener) {
    added++;
    super.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    removed++;
    super.removeListener(listener);
  }
}

/// The same without `SoloListenable`: "a plain `Solo`".
final class Plain extends Solo<Profile> {
  /// How many times `addListener` was called.
  int added = 0;

  /// How many times `removeListener` was called.
  int removed = 0;

  /// A controller in [state].
  Plain([Profile? state]) : super(state ?? Empty());

  /// Writes [state] from outside a job.
  void set(Profile state) => externalSetState(state);

  @override
  void addListener(void Function() listener) {
    added++;
    super.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    removed++;
    super.removeListener(listener);
  }
}

/// "One `with SoloStream` only".
final class StreamOnly extends Solo<Profile> with SoloStream {
  /// A controller in `Empty`.
  StreamOnly() : super(Empty());

  /// Writes [state] from outside a job.
  void set(Profile state) => externalSetState(state);
}

/// Both deliveries, from the one import of the package.
final class Both extends Solo<Profile> with SoloStream, SoloListenable {
  /// A controller in `Empty`.
  Both() : super(Empty());

  /// Writes [state] from outside a job.
  void set(Profile state) => externalSetState(state);
}

/// A controller whose `==` says every one of its kind is the same.
final class Same extends Solo<Profile> with SoloListenable {
  /// A controller in [state].
  Same(super.state);

  /// Writes [state] from outside a job.
  void set(Profile state) => externalSetState(state);

  // The controller is mutable, and that is the point: two of them that
  // call themselves equal.
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) => other is Same;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => 0;
}

/// A controller of a domain with a `select` of its own.
final class Picker extends Solo<Profile> with SoloListenable {
  /// What `select` was called with.
  final picked = <int>[];

  /// A controller in `Empty`.
  Picker() : super(Empty());

  /// Picks an item of the list this controller would hold.
  void select(int id) => picked.add(id);
}

/// The `load` of the page without its `onError` and `onCancel`.
final class Handlerless extends Solo<Profile> with SoloListenable {
  /// The API behind the controller.
  final ProfileApi api;

  /// A controller over [api].
  Handlerless(this.api) : super(Empty());

  /// Loads the profile and leaves the state where the body left it.
  Job<String> load() => run<Profile, String>(
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
      );
}

/// A controller whose job hands failing work to `ctx.unattended`.
final class Background extends Solo<Profile> with SoloListenable {
  /// Whether this controller answers for what no outcome holds.
  final bool answers;

  /// What it answered for.
  final answered = <Object>[];

  /// A controller in `Empty`.
  Background({this.answers = false}) : super(Empty());

  /// A job that ends `Done` and leaves work behind that fails.
  Job<void> ping() => run<Profile, void>((ctx) async {
        ctx.unattended(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          throw StateError('the ping failed');
        });
      });

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    if (answers) {
      answered.add(error);
    } else {
      super.onUnanswered(job, error, stackTrace);
    }
  }
}

/// An API whose answer never comes: a load over it is still running whenever
/// the test looks, with no timer of a fake left behind.
class SilentApi extends ProfileApi {
  @override
  Future<String> fetchName() => Completer<String>().future;
}

/// The load of `ProfileController` with a deadline: "a job given a
/// `timeout`".
final class TimedLoad extends Solo<Profile> with SoloListenable {
  final ProfileApi api;

  TimedLoad(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        timeout: const Duration(seconds: 5),
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
        onCancel: (state, cancelled) => Empty(),
      );
}

/// An observer that writes down the errors it is told of.
final class Watching extends SoloObserver {
  /// Every error `onError` was given.
  final seen = <Object>[];

  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace,
  ) =>
      seen.add(error);
}

/// A listenable that refuses to let a listener go.
class Sticky extends ChangeNotifier {
  @override
  void removeListener(VoidCallback listener) =>
      throw StateError('will not let go');
}

/// A parent that rebuilds on demand, with whatever [build] returns under it.
class Parent extends StatefulWidget {
  /// Builds the subtree, anew on every build of the parent.
  final WidgetBuilder build;

  /// A parent over [build].
  const Parent(this.build, {super.key});

  @override
  State<Parent> createState() => ParentState();
}

/// The `State` of [Parent].
class ParentState extends State<Parent> {
  /// Rebuilds the parent.
  void again() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.build(context);
}

/// The Save button of the page with the selection in a field and no
/// `didUpdateWidget`.
class StuckSaveButton extends StatefulWidget {
  /// The controller the button saves to.
  final ProfileController controller;

  /// A Save button over [controller].
  const StuckSaveButton({required this.controller, super.key});

  @override
  State<StuckSaveButton> createState() => _StuckSaveButtonState();
}

class _StuckSaveButtonState extends State<StuckSaveButton> {
  late final canSave =
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: canSave,
        builder: (context, enabled, _) => ElevatedButton(
          onPressed: enabled ? widget.controller.save : null,
          child: const Text('Save'),
        ),
      );
}

/// The view of the page with nothing animating while the profile loads.
class QuietView extends StatelessWidget {
  /// The controller the view shows.
  final ProfileController controller;

  /// A view over [controller].
  const QuietView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Profile>(
        valueListenable: controller,
        builder: (context, state, _) => switch (state) {
          Empty() => TextButton(
              onPressed: controller.load,
              child: const Text('Load'),
            ),
          Loading() => const Text('Loading'),
          Loaded(:final name) => Text(name),
        },
      );
}

/// A `State` whose source can be replaced: it cancels its group in
/// `didUpdateWidget` and listens again, into a new group or into the
/// cancelled one.
class Following extends StatefulWidget {
  /// The controller listened to.
  final ProfileController controller;

  /// What the `State` was told, in order.
  final List<String> heard;

  /// Whether the subscriptions taken again go into a new group.
  final bool newGroup;

  /// A widget that follows [controller].
  const Following({
    required this.controller,
    required this.heard,
    required this.newGroup,
    super.key,
  });

  @override
  State<Following> createState() => _FollowingState();
}

class _FollowingState extends State<Following> {
  var _listening = SoloSubscriptions();

  void _listen() => widget.controller
      .listen(() => widget.heard.add(show(widget.controller.value)))
      .addTo(_listening);

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(Following oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _listening.cancel();
      if (widget.newGroup) {
        _listening = SoloSubscriptions();
      }
      _listen();
    }
  }

  @override
  void dispose() {
    _listening.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A widget whose `dispose()` says so in [log] and may throw.
class Disposing extends StatefulWidget {
  /// Where `dispose()` writes [name].
  final List<String> log;

  /// The name written.
  final String name;

  /// Whether `dispose()` throws after writing.
  final bool throws;

  /// A widget named [name].
  const Disposing(this.log, this.name, {this.throws = false, super.key});

  @override
  State<Disposing> createState() => _DisposingState();
}

class _DisposingState extends State<Disposing> {
  @override
  void dispose() {
    widget.log.add(widget.name);
    if (widget.throws) {
      throw StateError('out of dispose');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// The screen of "The controller's life" with `close()` on the other side
/// of `super.dispose()`.
class LateCloseScreen extends StatefulWidget {
  /// The controller the screen closes.
  final ProfileController controller;

  /// A screen over [controller].
  const LateCloseScreen({required this.controller, super.key});

  @override
  State<LateCloseScreen> createState() => _LateCloseScreenState();
}

class _LateCloseScreenState extends State<LateCloseScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load().ignore();
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.close().ignore();
  }

  @override
  Widget build(BuildContext context) =>
      ProfileView(controller: widget.controller);
}
