/// The rules of async_job_lints, registered by [AsyncJobLintsPlugin].
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'plugin_api.dart';

/// Registers the rules of async_job_lints.
///
/// Warnings are on as soon as the plugin is enabled; the lints
/// `catch_without_check` and `bare_await` are turned on under `diagnostics:`.
class AsyncJobLintsPlugin extends Plugin {
  @override
  String get name => 'async_job_lints';

  @override
  void register(PluginRegistry registry) => registerAsyncJobLints(registry);
}
