// What `doc/testing.md` says in prose about code it does not show: an API
// that never answers, the load of the page with a deadline, and a view with
// nothing animating. None of this is page code, and
// `test/testing_rakes_test.dart` never looks for the page's code here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

import 'readme_profile.dart';

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

  Job<String> load() => enqueue<Profile, String>(
    key: 'load',
    timeout: const Duration(seconds: 5),
    (ctx) async {
      ctx.emit(Loading());
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));

      return name;
    },
    ifCancelled: (state, cancelled) => Empty(),
  );
}

/// The view of the page with nothing animating while the profile loads.
class QuietView extends StatelessWidget {
  /// The controller the view shows.
  final ProfileController controller;

  /// A view over [controller].
  const QuietView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => SoloBuilder<Profile>(
    solo: controller,
    builder: (context, state, _) => switch (state) {
      Empty() => TextButton(
        onPressed: () => controller.load().ignoreFailure(),
        child: const Text('Load'),
      ),
      Loading() => const Text('Loading'),
      Loaded(:final name) => Text(name),
    },
  );
}
