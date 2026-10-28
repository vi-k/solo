import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports a member of the context that throws `StateError` when called in
/// the job's cleanup.
class CtxInCleanup extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'ctx_in_cleanup',
    "'{0}.{1}' throws in cleanup: the body is gone.",
    correctionMessage:
        "Use a plain 'await' here; in cleanup the context only takes "
        "'onDispose', 'onDiscard', 'disown', 'log' and 'unattended'.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// The members that throw while the engine runs the cleanup.
  static const _throwing = {
    ...coreCheckpoints,
    'onCancel',
    'start',
    'each',
    ...soloCheckpoints,
  };

  /// Creates the rule.
  CtxInCleanup()
    : super(
        name: 'ctx_in_cleanup',
        description:
            'Cleanup runs after the body, where the waiting members of the '
            'context throw.',
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
    for (final AstNode argument in node.argumentList.arguments) {
      final value = argumentValue(argument);
      final ctx = cleanupContext(value);
      if (ctx == null) continue;
      functionOf(value)?.body.accept(_Cleanup(rule, ctx));
    }
  }
}

class _Cleanup extends RecursiveAstVisitor<void> {
  final AnalysisRule rule;
  final Element ctx;

  _Cleanup(this.rule, this.ctx);

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A cleanup registered inside this one is scanned on its own.
    if (cleanupContext(node) == ctx) return;
    super.visitFunctionExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (callsOn(node, ctx, CtxInCleanup._throwing)) {
      _report(node, node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (readsState(node, ctx)) _report(node, 'state');
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (readsState(node, ctx)) _report(node, 'state');
    super.visitPropertyAccess(node);
  }

  void _report(AstNode node, String member) =>
      rule.reportAtNode(node, arguments: [ctx.displayName, member]);
}
