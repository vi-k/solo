// The second attempts of `doc/accumulation.md`, verbatim. A second attempt
// is a method on the page, "Only the method changes", so here it stands in
// the class of the first attempt, under a name of its own.
import 'package:solo/solo.dart';

import 'accumulation_page.dart';

/// The second attempt of the search recipe.
final class RestartingSearch extends Solo<SearchState> {
  final SearchApi api;

  RestartingSearch(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        (ctx) async {
          final results = await ctx.abandonable(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
}

/// Not on the page: the second attempt with `ctx.join` in place of
/// `ctx.abandonable`, which the page speaks of and does not show.
final class JoiningSearch extends Solo<SearchState> {
  final SearchApi api;

  JoiningSearch(this.api) : super(const SearchState.idle());

  SoloJob<void> query(String text) => run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        (ctx) async {
          final results = await ctx.join(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
}

/// The second attempt of the settings recipe.
final class RestartingSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  RestartingSettingsController(this._api, Settings initial) : super(initial);

  SoloJob<void> update(SettingsPatch patch) => run<Settings, void>(
        key: 'settings',
        policy: Policy.restart,
        (ctx) async {
          final next = patch.apply(ctx.state);
          await ctx.join(() => _api.save(next));
          ctx.emit(next);
        },
      );
}
