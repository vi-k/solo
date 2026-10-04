// The first attempts of `doc/accumulation.md`, verbatim: every piece of those
// blocks is a run of lines of this file, and `accumulation_rakes_test.dart`
// runs it. The second attempts stand in a file of their own, so that a
// second attempt turned into the first one on the page is found missing.
import 'package:solo/solo.dart';

import 'accumulation_page.dart';

final class QueuedSearch extends Solo<SearchState> {
  final SearchApi api;

  QueuedSearch(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => run<SearchState, void>(
        key: 'query',
        (ctx) async {
          final results = await ctx.wait(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
}

final class EagerSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  EagerSettingsController(this._api, Settings initial) : super(initial);

  SoloJob<void> update(SettingsPatch patch) => run<Settings, void>(
        key: 'settings',
        (ctx) async {
          final next = patch.apply(ctx.state);
          await ctx.join(() => _api.save(next));
          ctx.emit(next);
        },
      );
}

final class EagerLogController extends Solo<int> {
  final LogApi _api;

  EagerLogController(this._api) : super(0);

  SoloJob<void> logEvent(LogEntry entry) => run<int, void>(
        key: 'logs',
        (ctx) async {
          await ctx.join(() => _api.send([entry]));
          ctx.emit(ctx.state + 1);
        },
      );
}

final class QueuedPlayer extends Solo<Playback> {
  final PlayerDevice device;

  QueuedPlayer(this.device) : super(const Paused());

  SoloJob<void> resume() => run<Playback, void>(
        key: Command.resume,
        (ctx) async {
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        },
      );

  SoloJob<void> pause() => run<Playback, void>(
        key: Command.pause,
        (ctx) async {
          await ctx.join(device.pause);
          ctx.emit(const Paused());
        },
      );
}
