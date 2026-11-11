import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/plugin_api.dart';

/// Reports `ctx.emit` in a job of a `SoloLanes` that writes a value built on
/// the state as the job read it before an `await`.
///
/// A heuristic: a whole new state, such as the answer of a server, written
/// over what another lane wrote is not seen.
class StaleEmit extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'stale_emit',
    "'{0}' was read from the state before an 'await', and this 'emit' writes "
        'it over what another lane wrote meanwhile.',
    correctionMessage:
        "Read 'ctx.state' where the job writes, after the last 'await'.",
  );

  /// Creates the rule.
  StaleEmit()
    : super(
        name: 'stale_emit',
        description:
            'A job of SoloLanes that writes the state as it read it before '
            'an await loses what another lane wrote while it waited.',
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
    if (node.methodName.name != 'emit') return;
    final target = node.realTarget;
    final ctx = target is SimpleIdentifier ? target.element : null;
    if (ctx == null || !callsOn(node, ctx, const {'emit'})) return;
    final written = firstPositional(node.argumentList);
    final body = _bodyOf(node, ctx);
    if (written == null || body == null || !_runsInLanes(node, body, ctx)) {
      return;
    }
    final reads = _Reads(body);
    final root = reads.rootOf(written);
    final read = reads.readAt(root, {});
    if (read == null || !_waitsBetween(body, read, node)) return;
    rule.reportAtNode(node, arguments: [root.toSource()]);
  }
}

/// The job body around [node] whose context is [ctx].
FunctionExpression? _bodyOf(AstNode node, Element ctx) {
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is FunctionExpression && jobContextOf(at) == ctx) return at;
  }
  return null;
}

/// Whether the job [body] of [ctx], where [emit] writes, runs in a lane of
/// a `SoloLanes`, whose other lanes write while it waits; in a `Solo` only a
/// child of the job or `externalSetState` does.
///
/// A body given to a member of a lane runs in a `SoloLanes`, whichever lane
/// it is; any other body runs there when it is queued on the controller
/// around, a child's or a handler's included, and that is a `SoloLanes`.
bool _runsInLanes(MethodInvocation emit, FunctionExpression body, Element ctx) {
  // A body is a positional argument or, by its name, a named one.
  final parent = body.parent;
  final list = parent is ArgumentList ? parent : parent?.parent;
  final call = list?.parent;
  if (list is ArgumentList &&
      call is MethodInvocation &&
      isSoloLane(call.realTarget?.staticType)) {
    return true;
  }
  return queuedBodyOf(emit)?.ctx == ctx && isSoloLanes(controllerAround(emit));
}

/// Whether [node] reads the state: `ctx.state` or `ctx.stateAs<T>()` of a
/// `SoloContext`, the job's own or that of its parent.
bool _readsState(Expression node) {
  final on = switch (node) {
    PrefixedIdentifier(:final prefix) => prefix,
    PropertyAccess(:final realTarget) => realTarget,
    MethodInvocation(:final realTarget?) => realTarget,
    _ => null,
  };
  if (on is! SimpleIdentifier || !isSoloContext(on.staticType)) return false;
  final ctx = on.element;
  return ctx != null &&
      (readsState(node, ctx) ||
          (node is MethodInvocation && callsOn(node, ctx, const {'stateAs'})));
}

/// Where a value of the job [body] read the state, followed within [body].
class _Reads {
  final FunctionExpression body;

  _Reads(this.body);

  /// The expression [value] is built on: the target of its member calls,
  /// property reads, index reads, cascades, casts and `!`, taken off down to
  /// a read of the state.
  ///
  /// `feed.confirm(post)` is built on `feed`, `ctx.state.confirm(post)` on
  /// `ctx.state`, and `Feed(posts: posts)` on itself.
  Expression rootOf(Expression value) {
    var node = value.unParenthesized;
    while (!_readsState(node)) {
      final next = switch (node) {
        PrefixedIdentifier(:final prefix) => prefix,
        PropertyAccess(:final realTarget) => realTarget,
        MethodInvocation(:final realTarget?) => realTarget,
        IndexExpression(:final realTarget) => realTarget,
        CascadeExpression(:final target) => target,
        AsExpression(:final expression) => expression,
        PostfixExpression(:final operand, :final operator)
            when operator.type == TokenType.BANG =>
          operand,
        _ => null,
      };
      if (next == null) break;
      node = next.unParenthesized;
    }
    return node;
  }

  /// The offset of the read of the state [root] stands for: [root] itself
  /// when it reads the state, or the read the last value written to a local
  /// variable before [root] is built on; `null` for anything else.
  int? readAt(Expression root, Set<Element> seen) {
    if (_readsState(root)) return root.offset;
    if (root is! SimpleIdentifier) return null;
    final variable = root.element;
    if (variable is! LocalVariableElement || !seen.add(variable)) return null;
    final writes = _Writes(variable);
    body.body.accept(writes);
    Expression? last;
    for (final value in writes.values) {
      if (value.offset < root.offset &&
          (last == null || value.offset > last.offset)) {
        last = value;
      }
    }
    return last == null ? null : readAt(rootOf(last), seen);
  }
}

/// The values written to [variable]: its initializer and the right-hand
/// sides of `variable = ...`.
class _Writes extends RecursiveAstVisitor<void> {
  final LocalVariableElement variable;

  final values = <Expression>[];

  _Writes(this.variable);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    final value = node.initializer;
    if (value != null && node.declaredFragment?.element == variable) {
      values.add(value);
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    if (node.operator.type == TokenType.EQ && node.writeElement == variable) {
      values.add(node.rightHandSide);
    }
  }
}

/// Whether [body] waits after the read at [read] and before [emit] writes:
/// an `await` or an `await for` between the two, in a function that runs
/// [emit] rather than one that runs on its own.
bool _waitsBetween(FunctionExpression body, int read, AstNode emit) {
  final waits = _Waits();
  body.body.accept(waits);
  return waits.found.any((wait) {
    final (offset, function) = wait;
    return offset > read &&
        offset < emit.end &&
        function.offset <= emit.offset &&
        emit.end <= function.end;
  });
}

/// The offsets of the `await`s and `await for`s of a body, each with the
/// function body it suspends.
class _Waits extends RecursiveAstVisitor<void> {
  final found = <(int, FunctionBody)>[];

  void _add(AstNode node) {
    final function = node.thisOrAncestorOfType<FunctionBody>();
    if (function != null) found.add((node.offset, function));
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    _add(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    if (node.awaitKeyword != null) _add(node);
  }
}
