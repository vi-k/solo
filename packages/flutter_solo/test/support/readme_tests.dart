// The code of "Testing" in `README.md`, verbatim. The page writes a test and
// two fragments of one: the test is declared by a function, so that
// `test/readme_rakes_test.dart` decides where it stands in the suite, and
// each fragment is the body of a function that has a tester and a
// controller.

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'readme_profile.dart';

/// The two lines of "The first attempt".
Future<void> firstAttempt(
  WidgetTester tester,
  ProfileController controller,
) async {
  await controller.load().done;
  await tester.pump();
}

/// Declares the test of "Moving the clock", as the page writes it.
void theProfileAppears() {
  testWidgets('the profile appears', (tester) async {
    final controller = ProfileController(FakeApi());
    await tester.pumpWidget(
      MaterialApp(home: ProfileView(controller: controller)),
    );

    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    await controller.close();
  });
}

/// The three lines of the handle.
Future<Outcome<String>> theHandle(
  WidgetTester tester,
  ProfileController controller,
) async {
  final done = controller.load().done; // before the job can end
  await tester.pump(const Duration(milliseconds: 20)); // let the clock run
  final outcome = await done;

  return outcome;
}
