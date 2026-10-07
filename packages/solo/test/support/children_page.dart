// The code of `doc/children.md`, verbatim, less the first and second
// attempts: every piece of those blocks is a run of lines of this file, and
// `children_rakes_test.dart` runs it. The page shows the methods of a
// controller; here each stands in a class, and a method the page writes more
// than once has a class for each version.
import 'package:solo/solo.dart';

import 'children_stubs.dart';
import 'test_solo.dart';

/// Not on the page: the keys of the page's jobs.
enum _Op {
  sync,
  upload,
  trySync,
  syncAndAnnounce,
  resend,
  record,
  syncAndRecord,
}

/// The controller the page opens with, and what its other sections add to
/// it.
base class Syncer extends Solo<AppState> with OpenSolo<AppState>, Desk {
  Syncer([super.initialState = const Ready()]);

  // Made by the controller and started by nobody yet: the queue takes it
  // through `sync` below, a parent takes it through `ctx.run`.
  SoloJob<String> _sync(int item) => job<Ready, String>(
        key: _Op.sync,
        (ctx) async {
          // A stream child: the progress of the upload, which the API
          // closes when the upload ends. The parent waits for the child
          // even without an await, and cancelling the parent cancels it.
          ctx.each(
            api.progress(item),
            (childCtx, sent) =>
                childCtx.emit(childCtx.state.copyWith(sent: sent)),
          );

          // Created by the controller, started by the parent and outside
          // the queue: the parent holds the queue while it runs.
          final upload = job<Ready, String>(
            key: _Op.upload,
            (childCtx) => childCtx.join(() => api.push(item)),
          );
          return ctx.run(upload);
        },
      );

  SoloJob<String> sync(int item) => add(_sync(item));

  /// Not on the page: `_sync` made and handed out, started by nobody.
  SoloJob<String> made(int item) => _sync(item);

  // Runs after `sync` succeeds, outside the queue, with a plain JobContext.
  Job<void> syncAndReport(int item) =>
      sync(item).then((ctx, path) => analytics.send(path));

  // The same split as `sync`: the step itself, and the queue's way in.
  SoloJob<void> _recordPath(String path) => job<Ready, void>(
        key: _Op.record,
        (ctx) async => ctx.emit(ctx.state.copyWith(path: path)),
      );

  SoloJob<void> recordPath(String path) => add(_recordPath(path));
}

/// "The future of `ctx.run`".
final class Trying extends Syncer {
  // The parent answers for a failed upload itself.
  SoloJob<bool> trySync(int item) => run<Ready, bool>(
        key: _Op.trySync,
        (ctx) async {
          try {
            final path = await ctx.run(_sync(item));
            ctx.emit(ctx.state.copyWith(path: path));
            return true;
          } on ApiException {
            return false;
          }
        },
      );
}

/// "Working beside a child".
final class Announcing extends Syncer {
  SoloJob<String> syncAndAnnounce(int item) => run<Ready, String>(
        key: _Op.syncAndAnnounce,
        (ctx) async {
          // Kept, not awaited: the upload runs while the parent goes on.
          // A failure of the upload is ignored here, and the body fails
          // with it at the `return`.
          final uploading = ctx.run(_sync(item))..ignore();
          await ctx.join(() => analytics.send('started $item'));
          return uploading;
        },
      );
}

/// "A child the rules turn away".
final class Resending extends Syncer {
  Resending([super.initialState]);

  SoloJob<String> resend(int item) => run<Ready, String>(
        key: _Op.resend,
        (ctx) {
          // A child with a rule of its own: no upload while paused.
          final upload = job<Ready, String>(
            key: _Op.upload,
            canStart: (state) => !state.paused,
            (childCtx) => childCtx.join(() => api.push(item)),
          );
          return ctx.run(upload);
        },
      );
}

/// "Two children in a row".
final class Together extends Syncer {
  // `_sync` and `_recordPath` again, now children. The parent holds the
  // queue until its children are done, so a `save()` queued meanwhile
  // waits for both steps.
  SoloJob<void> syncAndRecord(int item) => run<Ready, void>(
        key: _Op.syncAndRecord,
        (ctx) async {
          final path = await ctx.run(_sync(item));
          await ctx.run(_recordPath(path));
        },
      );
}
