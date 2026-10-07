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

/// "Steps in a row", the first attempt.
final class Chained extends page.Syncer {
  Job<void> syncAndRecord(int item) =>
      sync(item).then((ctx, path) => recordPath(path).value);
}

/// "Steps in a row", the second attempt.
final class Queued extends page.Syncer {
  Job<void> syncAndRecord(int item) => run<Ready, void>(
        key: _Op.syncAndRecord,
        (ctx) async {
          final path = await sync(item).value;
          await recordPath(path).value;
        },
      );
}
