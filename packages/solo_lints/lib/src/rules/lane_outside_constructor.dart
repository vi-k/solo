import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/plugin_api.dart';

/// Reports `lane(...)` of `SoloLanes` called anywhere but right in a
/// constructor body: a `late final` initializer, a method or a function.
class LaneOutsideConstructor extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'lane_outside_constructor',
    "'lane' outside the constructor body throws once SoloLanes has sealed "
        'its set of lanes, a microtask after the constructor.',
    correctionMessage:
        "Call 'lane' in the constructor body and keep the lane in a "
        "'late final' field.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  LaneOutsideConstructor()
    : super(
        name: 'lane_outside_constructor',
        description:
            'SoloLanes seals its set of lanes a microtask after the '
            'constructor: lane(...) anywhere but the constructor body throws.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!isSoloMember(node.methodName.element, 'SoloLanes', 'lane')) return;
    if (declaresLane(node)) return;
    rule.reportAtNode(node);
  }
}
