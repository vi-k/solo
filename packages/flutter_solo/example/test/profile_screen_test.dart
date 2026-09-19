import 'package:flutter/material.dart';
import 'package:flutter_solo_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the fake service takes to answer.
const _fetch = Duration(seconds: 2);

Future<ProfileApi> _open(WidgetTester tester) async {
  final api = ProfileApi();
  await tester.pumpWidget(MaterialApp(home: ProfileScreen(api: api)));

  return api;
}

/// Taps [finder] and lets the fetch it starts answer.
Future<void> _loadWith(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  await tester.pump(_fetch);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a load shows the name and says hello', (tester) async {
    await _open(tester);
    await _loadWith(tester, find.text('Load'));

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('hello Ada Lovelace'), findsOneWidget);
  });

  testWidgets('a failed load says why and offers the load again', (
    tester,
  ) async {
    await _open(tester);
    await _loadWith(tester, find.text('Load'));
    await _loadWith(tester, find.byTooltip('Reload'));
    // The third call is the one the service fails.
    await _loadWith(tester, find.byTooltip('Reload'));

    expect(find.text('Bad state: the network is having a day'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await _loadWith(tester, find.text('Load'));
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('Cancel stops the load and offers it again', (tester) async {
    final api = await _open(tester);
    await tester.tap(find.text('Load'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Load'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'Cancelled says nothing');

    // The call the job gave up on still answers, to nobody.
    await tester.pump(_fetch);
    await tester.pumpAndSettle();
    expect(find.text('Load'), findsOneWidget);
    expect(api.calls, 1);
  });

  testWidgets('a tap while the load runs gets the running job', (
    tester,
  ) async {
    final api = await _open(tester);
    await tester.tap(find.text('Load'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reload'));
    await tester.pump(_fetch);
    await tester.pumpAndSettle();

    expect(api.calls, 1, reason: 'one fetch for the two taps');
    expect(find.text('hello Ada Lovelace'), findsOneWidget);
  });
}
