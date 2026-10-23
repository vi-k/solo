// The code of `README.md` that takes scopo, verbatim: the two scopes of
// "The controller's life", each as a function that returns it.
// `test/readme_scopo_test.dart` runs it.
//
// It stands apart from `readme_widgets.dart`, which imports the second
// import of this package: scopo declares a `listen` on `Listenable` of its
// own, and a library that imports both cannot call either.
//
// A widget expression of the page ends with `)` on a line of its own; it
// stands as the one element of a list, as in `readme_widgets.dart`.
//
// The page builds its API with `ProfileApi()`, and here that is the fake of
// `readme_profile.dart` as [ProfileApi.next] says: a test sets what the
// next API does before the page's code builds it.
//
// ignore_for_file: require_trailing_commas

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'readme_profile.dart' hide ProfileApi;
import 'readme_profile.dart' as profile show ProfileApi;

/// The `ProfileApi()` the page's code calls.
class ProfileApi extends profile.ProfileApi {
  /// The fake with the settings of [next].
  ProfileApi() : super(delay: next.delay, error: next.error) {
    last = this;
  }

  /// What the next API is built with; a test resets it when it is over.
  static profile.ProfileApi next = profile.ProfileApi();

  /// The API built last.
  static ProfileApi? last;
}

/// The scope that owns the controller of one screen.
Widget screenScope() => [
      ScopeModel<ProfileController>(
        create: (context) {
          final controller = ProfileController(ProfileApi());
          controller.load().ignoreFailure();

          return controller;
        },
        dispose: (controller) => unawaited(controller.close()),
        builder: (context) => ProfileView(
          controller: ScopeModel.of<ProfileController>(context, listen: false),
        ),
      )
    ].single;

/// The scope that loads a shared controller and waits for its close.
Widget sharedScope() => [
      AsyncDataScope<ProfileController>(
        initData: (context, ctx) async {
          final controller = ProfileController(ProfileApi());
          final unregister = ctx.onDiscard(controller.close);
          await ctx.abandonable(() => controller.load().value);
          unregister(); // from here on, disposeData closes it

          return controller;
        },
        disposeData: (controller) => controller.close(),
        progressBuilder: (context, _) => const CircularProgressIndicator(),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context, controller) => ProfileView(controller: controller),
      )
    ].single;
