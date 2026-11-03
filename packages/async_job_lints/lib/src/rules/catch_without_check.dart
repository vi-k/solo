import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
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
    correctionMessage:
        "Make '{0}.check();' the first line of the catch, unless the catch "
        'has to run for a cancellation as well.',
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
    if (!takesCancelled(node.exceptionType?.type)) return;
    final ctx = bodyContextAround(node);
    if (ctx == null) return;
    final statement = node.parent;
    if (statement is! TryStatement) return;
    if (!_waits(statement.body, ctx)) return;
    if (_letsItThrough(node.body, ctx)) return;
    final at = node.exceptionType;
    if (at != null) {
      rule.reportAtNode(at, arguments: [ctx.displayName]);
    } else {
      rule.reportAtToken(node.catchKeyword!, arguments: [ctx.displayName]);
    }
  }

  /// Whether [block] waits or reaches a checkpoint of [ctx].
  static bool _waits(Block block, Element ctx) {
    final finder = _Cancellation(ctx);
    block.accept(finder);
    return finder.found;
  }

  /// Whether the catch [body] lets a cancellation out before it acts on it.
  static bool _letsItThrough(Block body, Element ctx) {
    if (body.statements.isEmpty) return false;
    return askingStatement(body, ctx) != null || _leavesAtOnce(body, ctx);
  }

  /// Whether the catch [body] ends in `rethrow;` with nothing on the way that
  /// waits, reaches a checkpoint of [ctx] or leaves the catch otherwise: a
  /// release or a log on the way out holds up nobody and must run for a
  /// cancellation too.
  static bool _leavesAtOnce(Block body, Element ctx) {
    if (!isRethrow(body.statements.last)) return false;
    final finder = _Cancellation(ctx, exits: true);
    body.accept(finder);
    return !finder.found;
  }
}

/// Finds an `await` or a checkpoint on the context in a block, outside the
/// functions declared in it, and with [exits] a `return`, `break` or
/// `continue` as well.
class _Cancellation extends RecursiveAstVisitor<void> {
  final Element ctx;
  final bool exits;

  bool found = false;

  _Cancellation(this.ctx, {this.exits = false});

  @override
  void visitBreakStatement(BreakStatement node) {
    if (exits) found = true;
  }

  @override
  void visitContinueStatement(ContinueStatement node) {
    if (exits) found = true;
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (exits) found = true;
    super.visitReturnStatement(node);
  }

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
