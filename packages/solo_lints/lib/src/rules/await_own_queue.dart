import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports a job of a controller that waits for a job of the same
/// controller's queue, or for its `close` or `cancelAll`.
class AwaitOwnQueue extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'await_own_queue',
    "'{0}' waits for the running job, and the running job waits for '{0}'.",
    correctionMessage:
        "Run the job with 'ctx.run' instead of the queue; don't wait for "
        "'close' or 'cancelAll' from a job.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  AwaitOwnQueue()
    : super(
        name: 'await_own_queue',
        description:
            "A job that waits for its own controller's queue waits for "
            'itself.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addAwaitExpression(this, visitor)
      ..addFunctionExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitAwaitExpression(AwaitExpression node) => _check(node.expression);

  /// A job body and the action of a waiting call are waited for through what
  /// they return.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (waitingContext(node) == null &&
        !isSoloContext(jobContextOf(node)?.type)) {
      return;
    }
    returnedValues(node.body).forEach(_check);
  }

  void _check(Expression waited) {
    final call = ownQueueCall(waited.unParenthesized);
    if (call == null) return;
    final ctx = _queuedBody(waited);
    if (ctx == null) return;
    final around = waited.thisOrAncestorMatching(
      (node) => node is ClassDeclaration || node is MixinDeclaration,
    );
    final owner = switch (around) {
      ClassDeclaration(:final declaredFragment) => declaredFragment?.element,
      MixinDeclaration(:final declaredFragment) => declaredFragment?.element,
      _ => null,
    };
    if (owner == null || !isSolo(owner.thisType)) return;
    rule.reportAtNode(call, arguments: [call.methodName.name]);
  }

  /// The context of the job body that waits for [node] when that is a body
  /// of a `SoloContext` queued on this controller: [node] is in the body
  /// itself, in the actions of waiting calls on its context or in its
  /// cleanup, which the queue waits for as well.
  static Element? _queuedBody(AstNode node) {
    final crossed = <Element>[];
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is! FunctionExpression) continue;
      final ctx = jobContextOf(at);
      if (ctx != null) {
        if (!isSoloContext(ctx.type) || !_queuedHere(at)) return null;
        return crossed.every((c) => c == ctx) ? ctx : null;
      }
      final through = waitingContext(at) ?? cleanupContext(at);
      if (through == null) return null;
      crossed.add(through);
    }
    return null;
  }

  /// Whether [body] is given to a call on this controller or on a context,
  /// rather than to another controller's `enqueue`.
  static bool _queuedHere(FunctionExpression body) {
    final parent = body.parent;
    final list = parent is ArgumentList ? parent : parent?.parent;
    final call = list?.parent;
    if (list is! ArgumentList || call is! MethodInvocation) return true;
    final target = call.realTarget;
    return target == null ||
        target is ThisExpression ||
        isJobContext(target.staticType);
  }
}
