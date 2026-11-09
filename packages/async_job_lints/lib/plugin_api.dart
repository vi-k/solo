/// The API for an analyzer plugin built on top of async_job_lints.
///
/// A plugin that wants the rules of async_job_lints under its own name calls
/// [registerAsyncJobLints] from its `register`, and may reuse the recognizers
/// exported here for rules of its own. This library is not meant for the code
/// a plugin checks. It follows semver with the package.
library;

import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/add_check.dart';
import 'src/fixes/release_on_the_call.dart';
import 'src/rules/bare_await.dart';
import 'src/rules/catch_without_check.dart';
import 'src/rules/ctx_in_cleanup.dart';
import 'src/rules/discarded_outcome.dart';
import 'src/rules/outcome_after_await.dart';
import 'src/rules/release_on_the_call.dart';
import 'src/rules/sync_fake_async.dart';

export 'src/context.dart'
    show
        cleanupContext,
        firstPositional,
        functionOf,
        isDartCoreClass,
        isFromJobPackages,
        isJobContext,
        isSolo,
        isSoloContext,
        isSoloMember,
        jobContextOf,
        namedValue,
        ownQueueCall,
        returnedValues,
        waitingContext;

/// Registers the rules of async_job_lints and their quick fixes in
/// [registry].
///
/// With [ownQueueReportedElsewhere], `bare_await` stays quiet on a wait for a
/// job of the controller's own queue, because a rule of the calling plugin
/// reports that wait. Without it `bare_await` reports the wait as any other.
void registerAsyncJobLints(
  PluginRegistry registry, {
  bool ownQueueReportedElsewhere = false,
}) {
  registry
    ..registerWarningRule(CtxInCleanup())
    ..registerWarningRule(DiscardedOutcome())
    ..registerWarningRule(OutcomeAfterAwait())
    ..registerWarningRule(ReleaseOnTheCall())
    ..registerFixForRule(ReleaseOnTheCall.code, PassReleaseToCall.new)
    ..registerWarningRule(SyncFakeAsync())
    ..registerLintRule(CatchWithoutCheck())
    ..registerFixForRule(CatchWithoutCheck.code, AddCheck.new)
    ..registerLintRule(
      BareAwait(ownQueueReportedElsewhere: ownQueueReportedElsewhere),
    );
}
