// The code of `README.md` that takes scopo, verbatim: the two scopes of
// "The controller's life", each as a function that returns it.
// `test/readme_rakes_test.dart` runs it.
//
// It stands apart from `readme_widgets.dart`, which imports the second
// import of this package: scopo declares a `listen` on `Listenable` of its
// own, and a library that imports both cannot call either.
//
// A widget expression of the page ends with `)` on a line of its own; it
// stands as the one element of a list, as in `readme_widgets.dart`.
//
// ignore_for_file: require_trailing_commas

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'readme_profile.dart';

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

/// The scope that waits for the close of a shared controller.
Widget sharedScope() => [
      AsyncDataScope<ProfileController>(
        initData: (context, ctx) async => ProfileController(ProfileApi()),
        disposeData: (controller) => controller.close(),
        progressBuilder: (context, progress) => const SizedBox.shrink(),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context, controller) => ProfileView(controller: controller),
      )
    ].single;
