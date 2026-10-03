// The first and second attempts of `doc/children.md`, verbatim: every piece
// of those blocks is a run of lines of this file, and
// `children_rakes_test.dart` runs it to see what the page says each of them
// does. A method the page writes more than once has a class for each
// version.
import 'package:solo/solo.dart';

import 'children_page.dart' as page;
import 'children_stubs.dart';

/// Not on the page: the keys of the page's jobs.
enum _Op { syncAndRecord }

/// "Processing a stream", the first attempt.
final class Listening extends page.Syncer {
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

/// "Steps in a row", the first attempt.
final class Chained extends page.Syncer {
  Job<void> syncAndRecord(int item) =>
      sync(item).then((ctx, path) => recordPath(path).value);
}

/// "Steps in a row", the second attempt.
final class Queued extends page.Syncer {
  SoloJob<void> syncAndRecord(int item) => run<Ready, void>(
        key: _Op.syncAndRecord,
        (ctx) async {
          final path = await sync(item).value;
          await recordPath(path).value;
        },
      );
}
