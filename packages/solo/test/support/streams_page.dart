// The code of `doc/streams.md`, verbatim, less the first attempts: every
// piece of those blocks is a run of lines of this file, and
// `streams_rakes_test.dart` runs it. The page shows the methods of a
// controller; here each stands in a class.
import 'package:solo/solo.dart';

import 'children_stubs.dart';
import 'test_solo.dart';

/// The controller of "A child that owns the subscription".
base class Tracker extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Tracker([super.initialState = const Ready()]);

  Job<void> track() => enqueue<Ready, void>(
        key: 'track',
        (ctx) => ctx.each(hw.positions, (childCtx, p) {
          childCtx.emit(childCtx.state.copyWith(position: p));
        }).value,
      );
}

/// "The state first, then the stream".
final class ScreenController extends Solo<Screen> {
  /// Not on the page here: the field and the constructor, which the page
  /// shows in the first attempt.
  final SoloStream<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => enqueue<Screen, void>(
        key: 'follow',
        (ctx) async {
          void take(SoloContext<Screen, Screen> target, Session next) =>
              target.emit(target.state.copyWith(signedIn: next.signedIn));

          final following = ctx.each(session.stream, take); // what happens next
          take(ctx, session.currentState); // what has already happened
          await following.value;
        },
      );

  /// Not on the page: another job of the same controller.
  Job<void> other() => enqueue<Screen, void>(
        key: 'other',
        (ctx) async => stage.trace.add('other ran'),
      );
}
