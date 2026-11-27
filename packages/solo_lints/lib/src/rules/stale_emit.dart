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
class StaleEmit extends MultiAnalysisRule {
  /// The diagnostic for a copy of the state read before a wait and written
  /// after it.
  static const LintCode code = LintCode(
    'stale_emit',
    "'{0}' was read from the state before an 'await', and this 'emit' writes "
        'it over what another lane wrote meanwhile.',
    correctionMessage:
        "Read 'ctx.state' where the job writes, after the last 'await'.",
    uniqueName: 'LintCode.stale_emit',
  );

  /// The diagnostic for a read of the state in the `emit` itself, before a
  /// wait in its argument.
  static const LintCode insideCode = LintCode(
    'stale_emit',
    "'{0}' is read before the 'await' inside this 'emit', and the write goes "
        'over what another lane wrote meanwhile.',
    correctionMessage:
        "Await into a local variable before the 'emit', and read 'ctx.state' "
        'in the emit after it.',
    uniqueName: 'LintCode.stale_emit_inside',
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
  List<DiagnosticCode> get diagnosticCodes => const [code, insideCode];

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
    final waits = _suspensionsOf(body);
    for (final root in reads.rootsOf(written)) {
      for (final read in reads.behind(root, {})) {
        if (!_waitsBetween(waits, read.at.offset, node)) continue;
        rule.reportAtNode(
          node,
          diagnosticCode: read.name == null
              ? StaleEmit.insideCode
              : StaleEmit.code,
          arguments: [read.name ?? read.at.toSource()],
        );
        return;
      }
    }
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
/// A body given to a member of a lane or a pool runs in a `SoloLanes`,
/// whichever it is; any other body runs there when it is queued on the
/// controller around, a child's or a handler's included, and that is a
/// `SoloLanes`.
bool _runsInLanes(MethodInvocation emit, FunctionExpression body, Element ctx) {
  // A body is a positional argument or, by its name, a named one.
  final parent = body.parent;
  final list = parent is ArgumentList ? parent : parent?.parent;
  final call = list?.parent;
  if (list is ArgumentList &&
      call is MethodInvocation &&
      isSoloQueueOwner(call.realTarget?.staticType)) {
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

/// A read of the state a written value is built on: the read itself, and
/// the local variable it was written to, or `null` when the value reads the
/// state right in the `emit`.
typedef _Read = ({Expression at, String? name});

/// Where a value of the job [body] read the state, followed within [body].
class _Reads {
  final FunctionExpression body;

  _Reads(this.body);

  /// The expressions [value] is built on: the target of its member calls,
  /// property reads, index reads, cascades, casts and `!`, taken off down to
  /// a read of the state, in each branch of `?:`, `??` and a switch
  /// expression, and in each field of a record literal.
  ///
  /// `feed.confirm(post)` is built on `feed`, `ctx.state.confirm(post)` on
  /// `ctx.state`, `a ? feed : ctx.state` on both, `(a: 1, b: saved.b)` on
  /// `1` and `saved`, and `Feed(posts: posts)` and `saved.a + 1` on
  /// themselves.
  List<Expression> rootsOf(Expression value) {
    final node = value.unParenthesized;
    if (_readsState(node)) return [node];
    final branches = switch (node) {
      ConditionalExpression(:final thenExpression, :final elseExpression) => [
        thenExpression,
        elseExpression,
      ],
      BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
          when operator.type == TokenType.QUESTION_QUESTION =>
        [leftOperand, rightOperand],
      SwitchExpression(:final cases) => [
        for (final arm in cases) arm.expression,
      ],
      RecordLiteral(:final fields) => [
        for (final field in fields) _valueOf(field),
      ],
      _ => null,
    };
    if (branches != null) return [for (final b in branches) ...rootsOf(b)];
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
    return next == null ? [node] : rootsOf(next);
  }

  /// The reads of the state [root] stands for: [root] itself when it reads
  /// the state, or the reads the last value written to a local variable
  /// before [root] is built on; none for anything else.
  ///
  /// [seen] holds the values already followed.
  List<_Read> behind(Expression root, Set<Expression> seen) {
    if (_readsState(root)) return [(at: root, name: null)];
    if (root is! SimpleIdentifier) return const [];
    final variable = root.element;
    if (variable is! LocalVariableElement) return const [];
    final writes = _Writes(variable);
    body.body.accept(writes);
    Expression? last;
    for (final value in writes.values) {
      // The right-hand side that holds [root] is the write being resolved,
      // not an earlier one: `feed = flag ? feed.confirm(post) : feed`
      // reads the copy it replaces.
      final holdsRoot = value.offset <= root.offset && root.end <= value.end;
      if (!holdsRoot &&
          value.offset < root.offset &&
          (last == null || value.offset > last.offset)) {
        last = value;
      }
    }
    if (last == null || !seen.add(last)) return const [];
    return [
      for (final from in rootsOf(last))
        if (_readsState(from))
          (at: from, name: variable.name)
        else
          ...behind(from, seen),
    ];
  }
}

/// The value of [field] of a record literal.
///
/// A positional field is the expression itself. A named field is a node of
/// its own, whose type the versions of the analyzer this package takes name
/// differently: a `NamedExpression` that opens with a [Label], or a node of
/// a name and a colon. Its value is its last child expression either way.
Expression _valueOf(AstNode field) {
  final children = field.childEntities;
  final named = children.isNotEmpty && children.first is Label;
  if (field is Expression && !named) return field;
  return children.whereType<Expression>().last;
}

/// The values written to [variable]: its initializer and the right-hand
/// sides of `variable = ...`, in the body itself.
///
/// A function declared in the body, a function expression or a local
/// function, is not entered: it may never run, and when it runs the order of
/// its writes is not that of the text.
class _Writes extends RecursiveAstVisitor<void> {
  final LocalVariableElement variable;

  final values = <Expression>[];

  _Writes(this.variable);

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

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

/// Whether one of [waits] suspends after the read at [read] and before
/// [emit] writes, in a function that runs [emit] rather than one that runs
/// on its own.
///
/// The order is that of the text of the job: a wait in a branch counts for
/// a write in another, unless the branch ends the job: a block that ends
/// with `return` or `throw` and does not hold the write is left before it.
bool _waitsBetween(List<_Suspension> waits, int read, AstNode emit) =>
    waits.any(
      (wait) =>
          wait.point > read &&
          wait.point < emit.end &&
          wait.function.offset <= emit.offset &&
          emit.end <= wait.function.end &&
          wait.leaving.every(
            (block) => block.offset <= emit.offset && emit.end <= block.end,
          ),
    );

/// Where a body suspends, the function body it suspends, and the blocks
/// around the wait, within that function, whose last statement is `return`
/// or `throw`.
typedef _Suspension = ({int point, FunctionBody function, List<Block> leaving});

/// The suspensions of [body]: the end of each `await`, where the body
/// resumes after the awaited value has run, and the start of the body of
/// each `await for`, which every turn waits to reach.
///
/// The action of `await ctx.join(...)` runs before the body suspends, so a
/// write in it comes before the wait.
List<_Suspension> _suspensionsOf(FunctionExpression body) {
  final waits = _Waits();
  body.body.accept(waits);
  return waits.found;
}

/// Whether the last statement of [block] is a `return` or a `throw`.
bool _endsTheJob(Block block) {
  if (block.statements.isEmpty) return false;
  final last = block.statements.last;
  return last is ReturnStatement ||
      (last is ExpressionStatement && last.expression is ThrowExpression);
}

class _Waits extends RecursiveAstVisitor<void> {
  final found = <_Suspension>[];

  void _add(AstNode node, int point) {
    final function = node.thisOrAncestorOfType<FunctionBody>();
    if (function == null) return;
    final leaving = <Block>[];
    for (var at = node.parent; at != null && at != function; at = at.parent) {
      if (at is Block && _endsTheJob(at)) leaving.add(at);
    }
    found.add((point: point, function: function, leaving: leaving));
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    _add(node, node.end);
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    if (node.awaitKeyword != null) _add(node, node.body.offset);
  }
}
