import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports a catch in a job body that takes the job's `Cancelled` and acts
/// before asking the job.
class CatchWithoutCheck extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'catch_without_check',
    'This catch takes the cancellation of the job along with the errors it '
        'was written for.',
    correctionMessage: "Make '{0}.check();' the first line of the catch.",
  );

  /// Creates the rule.
  CatchWithoutCheck()
    : super(
        name: 'catch_without_check',
        description:
            'A broad catch in a job body takes Cancelled too; ask the job '
            'before handling the error.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCatchClause(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitCatchClause(CatchClause node) {
    if (!_takesCancelled(node.exceptionType?.type)) return;
    final ctx = _contextAround(node);
    if (ctx == null) return;
    final statement = node.parent;
    if (statement is! TryStatement) return;
    if (!_mayCancel(statement.body, ctx)) return;
    if (_asksFirst(node.body, ctx)) return;
    final at = node.exceptionType;
    if (at != null) {
      rule.reportAtNode(at, arguments: [ctx.displayName]);
    } else {
      rule.reportAtToken(node.catchKeyword!, arguments: [ctx.displayName]);
    }
  }

  /// Whether a clause on [type] takes `Cancelled`, which is an
  /// `Outcome<Never>` and an `Exception`.
  static bool _takesCancelled(DartType? type) {
    if (type == null || type is DynamicType) return true;
    final element = type.element;
    return isDartCoreClass(element, 'Object') ||
        isDartCoreClass(element, 'Exception') ||
        isCoreClass(element, 'Outcome');
  }

  /// The context of the job body around [node], unless [node] is in a
  /// cleanup, where a checkpoint throws `StateError`.
  static Element? _contextAround(AstNode node) {
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is! FunctionExpression) continue;
      if (cleanupContext(at) != null) return null;
      final ctx = jobContextOf(at);
      if (ctx != null) return ctx;
    }
    return null;
  }

  static bool _mayCancel(Block body, Element ctx) {
    final finder = _Cancellation(ctx);
    body.accept(finder);
    return finder.found;
  }

  static bool _asksFirst(Block body, Element ctx) {
    final statements = body.statements;
    if (statements.isEmpty) return false;
    final first = statements.first;
    if (statements.length == 1 && _isRethrow(first)) return true;
    if (first is ExpressionStatement) {
      return isCheckpoint(first.expression, ctx);
    }
    if (first is VariableDeclarationStatement) {
      final initializer = first.variables.variables.first.initializer;
      return initializer != null && isCheckpoint(initializer, ctx);
    }
    if (first is IfStatement) {
      return first.elseStatement == null &&
          _isCancelledOf(first.expression, ctx) &&
          _isRethrow(first.thenStatement);
    }
    return false;
  }

  /// Whether [statement] is `rethrow;` or a block of nothing else.
  static bool _isRethrow(Statement statement) {
    if (statement is Block) {
      return statement.statements.length == 1 &&
          _isRethrow(statement.statements.single);
    }
    return statement is ExpressionStatement &&
        statement.expression is RethrowExpression;
  }

  /// Whether [condition] is `ctx.job.isCancelled`.
  static bool _isCancelledOf(Expression condition, Element ctx) {
    final node = condition.unParenthesized;
    if (node is! PropertyAccess || node.propertyName.name != 'isCancelled') {
      return false;
    }
    final job = node.realTarget;
    return job is PrefixedIdentifier &&
        job.identifier.name == 'job' &&
        contextNamed(job.prefix) == ctx;
  }
}

/// Finds an `await` or a checkpoint on the context in a try block, outside
/// the functions declared in it.
class _Cancellation extends RecursiveAstVisitor<void> {
  final Element ctx;

  bool found = false;

  _Cancellation(this.ctx);

  @override
  void visitAwaitExpression(AwaitExpression node) => found = true;

  @override
  void visitForElement(ForElement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForElement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForStatement(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (isCheckpoint(node, ctx)) found = true;
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (readsState(node, ctx)) found = true;
    super.visitPrefixedIdentifier(node);
  }
}
