// The first attempts of `doc/streams.md`, verbatim: every piece of those
// blocks is a run of lines of this file, and `streams_rakes_test.dart` runs
// it to see what the page says each of them does.
import 'package:solo/solo.dart';

import 'children_stubs.dart';
import 'streams_page.dart' as page;

/// "Processing a stream", the first attempt.
final class Listening extends page.Tracker {
  @override
  Job<void> track() => run<Ready, void>(
        key: 'track',
        (ctx) async {
          hw.positions.listen(
            (p) => ctx.emit(ctx.state.copyWith(position: p)),
          );
        },
      );
}

/// "Following another controller", the first attempt.
final class ScreenController extends Solo<Screen> {
  final SoloStream<Session> session;

  ScreenController(this.session) : super(const Screen());

  Job<void> follow() => run<Screen, void>(
        key: 'follow',
        (ctx) => ctx.each(session.stream, (childCtx, next) {
          childCtx.emit(childCtx.state.copyWith(signedIn: next.signedIn));
        }).value,
      );
}
