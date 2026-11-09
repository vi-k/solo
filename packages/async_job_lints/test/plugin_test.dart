import 'package:async_job_lints/async_job_lints.dart';
import 'package:async_job_lints/plugin_api.dart';
import 'package:async_job_lints/src/fixes/add_check.dart';
import 'package:async_job_lints/src/fixes/release_on_the_call.dart';
import 'package:async_job_lints/src/rules/bare_await.dart';
import 'package:test/test.dart';

import 'support/recording_registry.dart';

void main() {
  RecordingRegistry registered({bool ownQueueReportedElsewhere = false}) {
    final registry = RecordingRegistry();
    registerAsyncJobLints(
      registry,
      ownQueueReportedElsewhere: ownQueueReportedElsewhere,
    );
    return registry;
  }

  void expectTheCore(RecordingRegistry registry) {
    expect(
      registry.warnings.map((rule) => rule.name),
      unorderedEquals([
        'ctx_in_cleanup',
        'discarded_outcome',
        'outcome_after_await',
        'release_on_the_call',
        'sync_fake_async',
      ]),
    );
    expect(
      registry.lints.map((rule) => rule.name),
      unorderedEquals(['catch_without_check', 'bare_await']),
    );
    expect(registry.fixedRules, {'release_on_the_call', 'catch_without_check'});
    // The tests of the fixes make the producers directly, so a fix registered
    // for the wrong rule shows only here.
    expect(
      identical(registry.fixes['release_on_the_call'], PassReleaseToCall.new),
      isTrue,
      reason: 'release_on_the_call',
    );
    expect(
      identical(registry.fixes['catch_without_check'], AddCheck.new),
      isTrue,
      reason: 'catch_without_check',
    );
  }

  test('the seven rules of the core are registered, each with its kind', () {
    expectTheCore(registered());
  });

  test('the plugin registers through registerAsyncJobLints', () {
    final plugin = AsyncJobLintsPlugin();
    final registry = RecordingRegistry();
    plugin.register(registry);
    expect(plugin.name, 'async_job_lints');
    expectTheCore(registry);
  });

  // Two plugins that both register the rules of the core give one diagnostic
  // for each only while the codes are the same objects.
  test('two registrations share each diagnostic code', () {
    final first = registered();
    final second = registered();
    expect([...first.warnings, ...first.lints], hasLength(7));
    for (final rule in [...first.warnings, ...first.lints]) {
      final codes = second.rule(rule.name).diagnosticCodes;
      expect(codes, hasLength(rule.diagnosticCodes.length));
      for (final (index, code) in rule.diagnosticCodes.indexed) {
        expect(identical(code, codes[index]), isTrue, reason: rule.name);
      }
    }
  });

  test('the parameter reaches bare_await', () {
    BareAwait bareAwait(RecordingRegistry registry) =>
        registry.rule('bare_await') as BareAwait;
    expect(bareAwait(registered()).ownQueueReportedElsewhere, isFalse);
    expect(
      bareAwait(
        registered(ownQueueReportedElsewhere: true),
      ).ownQueueReportedElsewhere,
      isTrue,
    );
  });
}
