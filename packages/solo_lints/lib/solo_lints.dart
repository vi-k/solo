/// The rules of solo_lints, registered by [SoloLintsPlugin].
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/await_own_queue.dart';
import 'src/rules/catch_without_check.dart';
import 'src/rules/ctx_in_cleanup.dart';
import 'src/rules/release_on_the_call.dart';
import 'src/rules/sync_fake_async.dart';

/// Registers the rules of solo_lints.
///
/// Warnings are on as soon as the plugin is enabled; the lint
/// `catch_without_check` is turned on under `diagnostics:`.
class SoloLintsPlugin extends Plugin {
  @override
  String get name => 'solo_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(CtxInCleanup())
      ..registerWarningRule(ReleaseOnTheCall())
      ..registerWarningRule(SyncFakeAsync())
      ..registerWarningRule(AwaitOwnQueue())
      ..registerLintRule(CatchWithoutCheck());
  }
}
