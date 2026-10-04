// The code of `doc/mixins.md` above "A base class without Flutter",
// verbatim: the session of "A controller with both deliveries" and the
// three badges of "A screen built on the stream".
// `test/mixins_rakes_test.dart` runs it.
//
// A widget expression of the page ends with `)` on a line of its own, where
// a function that returned it would end with `);`. It stands as the one
// element of a list instead, which leaves the line as the page has it, and
// the comma a list would otherwise be asked for is what the rule below is
// switched off for.
//
// ignore_for_file: require_trailing_commas

import 'package:flutter/widgets.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class SessionState {
  const SessionState();
}

final class SignedOut extends SessionState {
  const SignedOut();
}

final class SignedIn extends SessionState {
  final String name;

  const SignedIn(this.name);
}

final class Session extends Solo<SessionState> with SoloStream, SoloListenable {
  Session(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}

class SessionBadge extends StatelessWidget {
  final Session session;

  const SessionBadge(this.session, {super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<SessionState>(
        stream: session.stream,
        builder: (context, snapshot) => Text(
          switch (snapshot.data) {
            SignedIn(:final name) => 'signed in as $name',
            SignedOut() => 'signed out',
            null => 'nothing yet',
          },
        ),
      );
}

/// The widget of "The second attempt".
Widget withInitialData(Session session) => [
      StreamBuilder<SessionState>(
        stream: session.stream,
        initialData: session.currentState,
        builder: (context, snapshot) => Text(
          switch (snapshot.requireData) {
            SignedIn(:final name) => 'signed in as $name',
            SignedOut() => 'signed out',
          },
        ),
      )
    ].single;

/// The widget of "A builder that takes the controller".
Widget overTheController(Session session) => [
      SoloBuilder<SessionState>(
        solo: session,
        builder: (context, state, _) => Text(
          switch (state) {
            SignedIn(:final name) => 'signed in as $name',
            SignedOut() => 'signed out',
          },
        ),
      )
    ].single;

/// The session of the page with a way to change its state inside one
/// synchronous call: the page changes it from a job, and a final class is
/// extended in its own library only.
final class DrivenSession extends Session {
  DrivenSession(super.initialState);

  void set(SessionState state) => externalSetState(state);
}
