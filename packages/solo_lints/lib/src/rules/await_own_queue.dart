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
    final body = node.body;
    if (body is ExpressionFunctionBody) {
      _check(body.expression);
    } else if (body is BlockFunctionBody) {
      final returns = _Returns();
      body.block.accept(returns);
      returns.values.forEach(_check);
    }
  }

  void _check(Expression waited) {
    final call = _ownCall(waited.unParenthesized);
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

  /// The call of this controller's method that [waited] waits for:
  /// `method(...).value`, `method(...).done` for a method that returns a
  /// `SoloJob`, and `close()` and `cancelAll()`.
  static MethodInvocation? _ownCall(Expression waited) {
    MethodInvocation? call;
    var jobOf = false;
    if (waited is PropertyAccess &&
        const {'value', 'done'}.contains(waited.propertyName.name)) {
      final target = waited.realTarget.unParenthesized;
      if (target is MethodInvocation) call = target;
      jobOf = true;
    } else if (waited is MethodInvocation &&
        const {'close', 'cancelAll'}.contains(waited.methodName.name)) {
      call = waited;
    }
    if (call == null) return null;
    final target = call.realTarget;
    if (target != null && target is! ThisExpression) return null;
    final method = call.methodName.element;
    if (method is! MethodElement) return null;
    final owner = method.enclosingElement;
    if (owner is! InterfaceElement || !isSolo(owner.thisType)) return null;
    // Both close and cancelAll are members of Solo, so a method of the
    // controller by either name is Solo's or overrides it.
    if (jobOf && !_returnsSoloJob(call, method)) return null;
    return call;
  }

  /// Whether [call] of [method] brings a `SoloJob`: by its declared type, or
  /// by what the method returns when it is declared in the same file.
  static bool _returnsSoloJob(MethodInvocation call, MethodElement method) {
    if (isSoloJob(call.staticType)) return true;
    final finder = _MethodFinder(method.baseElement);
    call.root.accept(finder);
    final body = finder.found?.body;
    if (body is ExpressionFunctionBody) {
      return isSoloJob(body.expression.staticType);
    }
    if (body is BlockFunctionBody) {
      final returns = _Returns();
      body.block.accept(returns);
      return returns.values.any((value) => isSoloJob(value.staticType));
    }
    return false;
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

/// Collects the values of the return statements of a block, outside the
/// functions declared in it.
class _Returns extends RecursiveAstVisitor<void> {
  final values = <Expression>[];

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitReturnStatement(ReturnStatement node) {
    final value = node.expression;
    if (value != null) values.add(value);
  }
}

class _MethodFinder extends RecursiveAstVisitor<void> {
  final Element method;

  MethodDeclaration? found;

  _MethodFinder(this.method);

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.declaredFragment?.element == method) found = node;
  }
}
