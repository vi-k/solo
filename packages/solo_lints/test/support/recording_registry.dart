import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';

/// A [PluginRegistry] that keeps what a plugin registers.
///
/// Only the calls a plugin of rules makes are recorded; any other member
/// throws. The fix generator is taken as [Function]: its type is not exported
/// by analysis_server_plugin, and a wider parameter still overrides.
final class RecordingRegistry implements PluginRegistry {
  /// The rules registered as warnings, in order.
  final warnings = <AbstractAnalysisRule>[];

  /// The rules registered as lints, in order.
  final lints = <AbstractAnalysisRule>[];

  final _fixed = <DiagnosticCode>[];

  /// The names of the rules a fix is registered for.
  Set<String> get fixedRules => {
    for (final code in _fixed)
      for (final rule in [...warnings, ...lints])
        if (rule.diagnosticCodes.contains(code)) rule.name,
  };

  /// The registered rule named [name].
  AbstractAnalysisRule rule(String name) =>
      [...warnings, ...lints].singleWhere((rule) => rule.name == name);

  @override
  void registerWarningRule(AbstractAnalysisRule rule) => warnings.add(rule);

  @override
  void registerLintRule(AbstractAnalysisRule rule) => lints.add(rule);

  @override
  void registerFixForRule(DiagnosticCode code, Function generator) =>
      _fixed.add(code);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not recorded');
}
