import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/plugin_api.dart';

/// Reports `lane(...)` or `pool(...)` of `SoloLanes` called anywhere but
/// right in a constructor body: a `late final` initializer, a method or a
/// function.
class LaneOutsideConstructor extends MultiAnalysisRule {
  /// The diagnostic for `lane(...)`.
  static const LintCode code = LintCode(
    'lane_outside_constructor',
    "'lane' outside the constructor body throws once SoloLanes has sealed "
        'its set of lanes, a microtask after the constructor.',
    correctionMessage:
        "Call 'lane' in the constructor body and keep the lane in a "
        "'late final' field.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// The diagnostic for `pool(...)`.
  static const LintCode poolCode = LintCode(
    'lane_outside_constructor',
    "'pool' outside the constructor body throws once SoloLanes has sealed "
        'its set of lanes and pools, a microtask after the constructor.',
    correctionMessage:
        "Call 'pool' in the constructor body and keep the pool in a "
        "'late final' field.",
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.lane_outside_constructor_pool',
  );

  /// Creates the rule.
  LaneOutsideConstructor()
    : super(
        name: 'lane_outside_constructor',
        description:
            'SoloLanes seals its set of lanes and pools a microtask after the '
            'constructor: lane(...) or pool(...) anywhere but the constructor '
            'body throws.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [code, poolCode];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final MultiAnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    final LintCode code;
    if (isSoloMember(element, 'SoloLanes', 'lane')) {
      code = LaneOutsideConstructor.code;
    } else if (isSoloMember(element, 'SoloLanes', 'pool')) {
      code = LaneOutsideConstructor.poolCode;
    } else {
      return;
    }
    if (declaresQueueOwner(node)) return;
    rule.reportAtNode(node, diagnosticCode: code);
  }
}
