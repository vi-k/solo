import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports an `await` in a job body that waits past the context, where a
/// cancellation does not reach the wait.
class BareAwait extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'bare_await',
    "This wait doesn't go through '{0}', so a cancellation of the job doesn't "
        'end it.',
    correctionMessage:
        "Wait through '{0}.join', '{0}.abandonable' or '{0}.pause', or put "
        "the call in '{0}.uncancellable' when it must not be cut short.",
  );

  /// Creates the rule.
  BareAwait()
    : super(
        name: 'bare_await',
        description:
            'A job body waits through its context, where a cancellation '
            'reaches the wait.',
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
      ..addForStatement(this, visitor)
      ..addForElement(this, visitor);
  }
}

/// The members of the context whose future a body awaits.
const _waiting = {
  'join',
  'abandonable',
  'wait',
  'uncancellable',
  'pause',
  'run',
  'runAll',
};

/// The members of the context that make a child the body may await.
const _children = {'each', 'child'};

/// The members of a child job whose future ends with the child.
const _childFutures = {'value', 'done'};

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitAwaitExpression(AwaitExpression node) {
    final ctx = _bodyContextOf(node);
    if (ctx == null || _Waits(ctx, node).through(node.expression)) return;
    // A wait for the controller's own queue is a deadlock, and
    // await_own_queue says so at the same await.
    if (ownQueueCall(node.expression.unParenthesized) != null) return;
    rule.reportAtToken(node.awaitKeyword, arguments: [ctx.displayName]);
  }

  @override
  void visitForElement(ForElement node) => _awaitFor(node.awaitKeyword, node);

  @override
  void visitForStatement(ForStatement node) =>
      _awaitFor(node.awaitKeyword, node);

  void _awaitFor(Token? keyword, AstNode node) {
    if (keyword == null) return;
    final ctx = _bodyContextOf(node);
    if (ctx != null) rule.reportAtToken(keyword, arguments: [ctx.displayName]);
  }

  /// The context of the job body that [node] waits in, outside any function
  /// declared in that body.
  ///
  /// `null` in a catch and in a `finally`, which handle a failure or a
  /// cancellation already on its way, and in a body of a job made with
  /// `cancellable: false`, which no cancellation reaches.
  static Element? _bodyContextOf(AstNode node) {
    var child = node;
    for (var at = node.parent; at != null; child = at, at = at.parent) {
      if (at is CatchClause) return null;
      if (at is TryStatement && identical(child, at.finallyBlock)) return null;
      if (at is FunctionExpression) {
        final ctx = jobContextOf(at);
        return ctx == null || _refusesCancellation(at) ? null : ctx;
      }
    }
    return null;
  }

  /// Whether the call [body] is passed to says `cancellable: false`.
  static bool _refusesCancellation(FunctionExpression body) {
    final list = body.parent;
    if (list is! ArgumentList) return false;
    final value = namedValue(list, 'cancellable');
    return value is BooleanLiteral && !value.value;
  }
}

/// What an awaited expression in the body of [ctx] waits through.
class _Waits {
  final Element ctx;

  /// The `await` being judged, where a lookup of earlier statements starts.
  final AwaitExpression at;

  _Waits(this.ctx, this.at);

  /// Whether [expression] waits through the context: a waiting member of
  /// it, a child it made, a call it is handed to, or futures of these taken
  /// together; or waits for nothing a cancellation could cut short.
  bool through(Expression expression) {
    final node = expression.unParenthesized;
    if (!_isFuture(node.staticType)) return true;
    switch (node) {
      case MethodInvocation():
        final target = node.realTarget;
        final owner = contextNamed(target);
        if (owner != null) return callsOn(node, owner, _waiting);
        if (node.methodName.name == 'cancel' && _isChild(target)) return true;
        if (node.methodName.name == 'wait' && _isFutureClass(target)) {
          return _all(firstPositional(node.argumentList));
        }
        return _handsOverContext(node.argumentList) || _releases(target);
      case FunctionExpressionInvocation():
        return _handsOverContext(node.argumentList);
      case ConditionalExpression():
        return through(node.thenExpression) && through(node.elseExpression);
      case PropertyAccess():
        return _property(node.realTarget, node.propertyName.name);
      case PrefixedIdentifier():
        return _property(node.prefix, node.identifier.name);
      case SimpleIdentifier():
        final initializer = _finalLocalValue(node);
        return initializer != null && through(initializer);
      default:
        return false;
    }
  }

  /// `child.value`, `child.done`, and `[a, b].wait` or `(a, b).wait`.
  bool _property(Expression target, String name) {
    if (_childFutures.contains(name)) return _isChild(target);
    if (name != 'wait') return false;
    final node = target.unParenthesized;
    if (node is ListLiteral) return _all(node);
    if (node is RecordLiteral) {
      final List<AstNode> fields = node.fields;
      return fields.every((field) => through(argumentValue(field)));
    }
    return false;
  }

  /// Whether [list] is a literal list of futures that all wait through the
  /// context.
  bool _all(Expression? list) {
    if (list is! ListLiteral || list.elements.isEmpty) return false;
    return list.elements.every((e) => e is Expression && through(e));
  }

  /// Whether [target] is a child job the context made: `ctx.each(...)` or
  /// `ctx.child(...)`, or a final local variable that holds one.
  bool _isChild(Expression? target) {
    if (target == null) return false;
    final node = target.unParenthesized;
    if (node is MethodInvocation) {
      final owner = contextNamed(node.realTarget);
      return owner != null && callsOn(node, owner, _children);
    }
    if (node is SimpleIdentifier) {
      final initializer = _finalLocalValue(node);
      return initializer != null && _isChild(initializer);
    }
    return false;
  }

  /// Whether [arguments] pass the context itself, so the call can wait
  /// through it.
  bool _handsOverContext(ArgumentList arguments) {
    for (final AstNode argument in arguments.arguments) {
      final value = argumentValue(argument).unParenthesized;
      if (value is SimpleIdentifier && value.element == ctx) return true;
    }
    return false;
  }

  /// Whether [target] is a variable the body took back from the cleanup
  /// with `ctx.disown` earlier in the same block: the release that follows
  /// has to run even for a cancellation.
  bool _releases(Expression? target) {
    if (target is! SimpleIdentifier) return false;
    final value = target.element;
    if (value == null) return false;
    AstNode child = at;
    for (var node = at.parent; node != null; child = node, node = node.parent) {
      if (node is FunctionBody) return false;
      if (node is! Block) continue;
      for (final statement in node.statements) {
        if (identical(statement, child)) break;
        if (_disowns(statement, value)) return true;
      }
    }
    return false;
  }

  bool _disowns(Statement statement, Element value) {
    if (statement is! ExpressionStatement) return false;
    final call = statement.expression.unParenthesized;
    if (call is! MethodInvocation || !callsOn(call, ctx, const {'disown'})) {
      return false;
    }
    final argument = firstPositional(call.argumentList)?.unParenthesized;
    return argument is SimpleIdentifier && argument.element == value;
  }

  /// The value a final local variable named by [node] is initialized with.
  static Expression? _finalLocalValue(SimpleIdentifier node) {
    final element = node.element;
    if (element is! LocalVariableElement || !element.isFinal) return null;
    final finder = _InitializerFinder(element);
    node.root.accept(finder);
    return finder.found;
  }

  /// Whether [type] is a future to wait for: `Future`, `FutureOr` or a
  /// subtype; `dynamic` counts, as a future may hide behind it.
  static bool _isFuture(DartType? type) {
    if (type == null || type is DynamicType) return true;
    if (type.isDartAsyncFutureOr) return true;
    if (type is! InterfaceType) return false;
    return type.isDartAsyncFuture ||
        type.allSupertypes.any((t) => t.isDartAsyncFuture);
  }

  static bool _isFutureClass(Expression? target) {
    if (target is! SimpleIdentifier) return false;
    final element = target.element;
    return element is InterfaceElement &&
        element.name == 'Future' &&
        element.library.uri.toString() == 'dart:async';
  }
}

class _InitializerFinder extends RecursiveAstVisitor<void> {
  final Element element;

  Expression? found;

  _InitializerFinder(this.element);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) {
      found = node.initializer;
      return;
    }
    super.visitVariableDeclaration(node);
  }
}
