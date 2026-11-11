/// The rules of solo_lints for code on solo, registered by [SoloLintsPlugin]:
/// those of async_job_lints for the core and five of the controller.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:async_job_lints/plugin_api.dart';

import 'src/fixes/key_per_request.dart';
import 'src/rules/await_own_queue.dart';
import 'src/rules/ignore_failure_hides_bugs.dart';
import 'src/rules/key_per_request.dart';
import 'src/rules/lane_outside_constructor.dart';
import 'src/rules/stale_emit.dart';

/// Registers the rules of async_job_lints and the five of solo_lints.
///
/// Warnings are on as soon as the plugin is enabled; the lints
/// `catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs`,
/// `stale_emit` and `bare_await` are turned on under `diagnostics:`.
class SoloLintsPlugin extends Plugin {
  @override
  String get name => 'solo_lints';

  @override
  void register(PluginRegistry registry) {
    // The rules of the core come from async_job_lints; await_own_queue says
    // what bare_await would at a wait for the own queue or the own lane, and
    // what discarded_outcome would at the own lane.
    registerAsyncJobLints(
      registry,
      ownQueueReportedElsewhere: true,
      ownLaneReportedElsewhere: true,
    );
    registry
      ..registerWarningRule(AwaitOwnQueue())
      ..registerLintRule(KeyPerRequest())
      ..registerFixForRule(KeyPerRequest.code, PutArgumentsIntoKey.new)
      ..registerLintRule(IgnoreFailureHidesBugs())
      ..registerLintRule(StaleEmit())
      ..registerWarningRule(LaneOutsideConstructor());
  }
}
