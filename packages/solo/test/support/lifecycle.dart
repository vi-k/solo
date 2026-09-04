import 'run_solo.dart';
import 'test_solo.dart';
import 'test_state.dart';

/// Queues the lifecycle fixture ported from 1.x: `init` runs 0..300 ms
/// (`Preparing` 0, 50, 100, then `Working`), `incrementA` 300..400,
/// `incrementB` 400..500, `finish` 500..600 (`Disposed`).
///
/// Every body waits on a bare [delay], so it notices cancellation only on
/// its next context access. Pass `cancellableA: false` for the variant
/// where `incrementA` survives `close`.
void addLifecycle(TestSolo solo, {bool cancellableA = true}) {
  solo
    ..run<NotDisposed, void>(
      key: 'init',
      canStart: (state) => state is Initial,
      (ctx) async {
        ctx.emit(const Preparing());
        await delay(100);
        ctx.emit(ctx.stateAs<Preparing>().copyWith(progress: 50));
        await delay(100);
        ctx.emit(ctx.stateAs<Preparing>().copyWith(progress: 100));
        await delay(100);
        ctx
          ..stateAs<Preparing>()
          ..emit(const Working());
      },
    )
    ..run<Working, void>(
      key: 'incrementA',
      cancellable: cancellableA,
      (ctx) async {
        await delay(100);
        ctx.emit(ctx.state.copyWith(a: ctx.state.a + 1));
      },
    )
    ..run<Working, void>(key: 'incrementB', (ctx) async {
      await delay(100);
      ctx.emit(ctx.state.copyWith(b: ctx.state.b + 1));
    })
    ..run<NotDisposed, void>(key: 'finish', (ctx) async {
      await delay(100);
      ctx.emit(const Disposed());
    });
}

/// The journal of [addLifecycle] when nothing interferes: 15 lines, the
/// last one at 600 ms.
const happyPath = [
  '[init] started',
  'state: Preparing(progress: 0)',
  'state: Preparing(progress: 50)',
  'state: Preparing(progress: 100)',
  'state: Working(a: 0, b: 0)',
  '[init] finished Done(null)',
  '[incrementA] started',
  'state: Working(a: 1, b: 0)',
  '[incrementA] finished Done(null)',
  '[incrementB] started',
  'state: Working(a: 1, b: 1)',
  '[incrementB] finished Done(null)',
  '[finish] started',
  'state: Disposed()',
  '[finish] finished Done(null)',
];
