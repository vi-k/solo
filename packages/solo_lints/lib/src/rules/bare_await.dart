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
class BareAwait extends MultiAnalysisRule {
  /// The diagnostic for an `await`.
  static const LintCode code = LintCode(
    'bare_await',
    "This wait doesn't go through '{0}', so a cancellation of the job doesn't "
        'end it.',
    correctionMessage:
        "Wait through '{0}.join', '{0}.abandonable' or '{0}.pause', or put "
        "the steps that must all run in '{0}.uncancellable'.",
    uniqueName: 'LintCode.bare_await',
  );

  /// The diagnostic for an `await for`.
  static const LintCode loopCode = LintCode(
    'bare_await',
    "This loop reads the stream past '{0}', so a cancellation of the job "
        "doesn't end it.",
    correctionMessage: "Process the stream with '{0}.each'.",
    uniqueName: 'LintCode.bare_await_for',
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
  List<DiagnosticCode> get diagnosticCodes => const [code, loopCode];

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

class _Visitor extends SimpleAstVisitor<void> {
  final MultiAnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitAwaitExpression(AwaitExpression node) {
    final ctx = _bodyContextOf(node);
    if (ctx == null || _Waits(ctx, node).through(node.expression)) return;
    // A wait for the controller's own queue is a deadlock, and
    // await_own_queue says so at the same await.
    if (ownQueueCall(node.expression.unParenthesized) != null) return;
    _report(node.awaitKeyword, BareAwait.code, ctx);
  }

  @override
  void visitForElement(ForElement node) => _awaitFor(node.awaitKeyword, node);

  @override
  void visitForStatement(ForStatement node) =>
      _awaitFor(node.awaitKeyword, node);

  void _awaitFor(Token? keyword, AstNode node) {
    if (keyword == null) return;
    final ctx = _bodyContextOf(node);
    if (ctx != null) _report(keyword, BareAwait.loopCode, ctx);
  }

  void _report(Token at, LintCode code, Element ctx) {
    // A body that names its context `_` is told the usual name.
    final name = ctx.displayName == '_' ? 'ctx' : ctx.displayName;
    rule.reportAtToken(at, diagnosticCode: code, arguments: [name]);
  }

  /// The context of the job body that [node] waits in, outside any function
  /// declared in that body.
  ///
  /// `null` in a `finally`, which runs for a cancellation too, in a catch
  /// that handles one (see [_handles]), and in a body of a job made with
  /// `cancellable: false`.
  static Element? _bodyContextOf(AstNode node) {
    final catches = <CatchClause>[];
    var child = node;
    for (var at = node.parent; at != null; child = at, at = at.parent) {
      if (at is CatchClause) catches.add(at);
      if (at is TryStatement && identical(child, at.finallyBlock)) return null;
      if (at is FunctionExpression) {
        final ctx = _contextOf(at);
        if (ctx == null || _refusesCancellation(at)) return null;
        if (catches.any(_handles)) return null;
        return ctx;
      }
    }
    return null;
  }

  /// The first parameter of [body] when it is typed `JobContext` or a
  /// subtype, a wildcard included: a body that does not name its context
  /// cannot wait through it.
  static Element? _contextOf(FunctionExpression body) {
    final parameters = body.parameters?.parameters;
    if (parameters == null || parameters.isEmpty) return null;
    final element = parameters.first.declaredFragment?.element;
    return isJobContext(element?.type) ? element : null;
  }

  /// Whether [clause] handles a cancellation, so its waits are a release
  /// that has to run for it: the clause is `on Cancelled`, or it takes a
  /// cancellation, its body ends in `rethrow;` and nothing leaves it before
  /// that end. A wait on the way to a `return`, or to a `continue` of the
  /// loop around, is a pause before going on, not a release.
  ///
  /// A check in the clause does not make it one: it hears a cancellation
  /// that has come, not one that comes during the wait after it.
  static bool _handles(CatchClause clause) {
    final type = clause.exceptionType?.type;
    if (isCoreClass(type?.element, 'Cancelled')) return true;
    final statements = clause.body.statements;
    return takesCancelled(type) &&
        statements.isNotEmpty &&
        isRethrow(statements.last) &&
        !_Exits.leave(clause.body);
  }

  /// Whether [body] belongs to a job made with `cancellable: false`: the
  /// call it is passed to says so, or, for a function declared at the top
  /// level, every call it is passed to by name does.
  static bool _refusesCancellation(FunctionExpression body) {
    final parent = body.parent;
    if (parent is ArgumentList) return _refuses(parent);
    if (parent is! FunctionDeclaration) return false;
    final function = parent.declaredFragment?.element;
    if (function == null) return false;
    final uses = _ArgumentUses(function);
    body.root.accept(uses);
    return uses.lists.isNotEmpty && uses.lists.every(_refuses);
  }

  /// Whether [arguments] pass `cancellable: false`, as a literal or as a
  /// constant.
  static bool _refuses(ArgumentList arguments) {
    final value = namedValue(arguments, 'cancellable')?.unParenthesized;
    if (value is BooleanLiteral) return !value.value;
    if (value is! Identifier) return false;
    final element = value.element;
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (variable is! VariableElement || !variable.isConst) return false;
    return variable.computeConstantValue()?.toBoolValue() == false;
  }
}

/// What an awaited expression in the body of [ctx] waits through.
class _Waits {
  final Element ctx;

  /// The `await` being judged, where a lookup of earlier statements starts.
  final AwaitExpression at;

  _Waits(this.ctx, this.at);

  /// Whether [expression] waits through the context: a waiting member of
  /// it, a child it runs, a call it is handed to, or futures of these taken
  /// together; or waits for nothing a cancellation could cut short.
  bool through(Expression expression) {
    final node = expression.unParenthesized;
    if (!_isFuture(node.staticType)) return true;
    switch (node) {
      case MethodInvocation():
        final target = node.realTarget;
        if (contextNamed(target) != null) return callsOn(node, ctx, _waiting);
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
    if (name == 'value' || name == 'done') return _isChild(target);
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
    if (list is! ListLiteral) return false;
    return list.elements.every(_element);
  }

  /// Whether the futures [element] of a list literal brings all wait through
  /// the context, a `for` or an `if` element included.
  bool _element(CollectionElement? element) => switch (element) {
    null => true,
    Expression() => through(element),
    ForElement() => _element(element.body),
    IfElement() =>
      _element(element.thenElement) && _element(element.elseElement),
    _ => false,
  };

  /// Whether [target] is a child the job runs: `ctx.each(...)`, a final
  /// local variable that holds one, or a variable the body passed to
  /// `ctx.start` earlier and cannot have replaced since. A child of
  /// `ctx.child` that nobody started never ends.
  bool _isChild(Expression? target) {
    if (target == null) return false;
    final node = target.unParenthesized;
    if (node is MethodInvocation) return callsOn(node, ctx, const {'each'});
    if (node is! SimpleIdentifier) return false;
    final value = node.element;
    if (value == null) return false;
    if (_fixed(value) &&
        _earlier((statement) => _calls(statement, 'start', value))) {
      return true;
    }
    final initializer = _finalLocalValue(node);
    return initializer != null && _isChild(initializer);
  }

  /// Whether [value] names one object for as long as the body runs: a final
  /// variable or parameter, or the getter of a final field.
  static bool _fixed(Element value) => switch (value) {
    VariableElement() => value.isFinal,
    GetterElement() => value.isOriginVariable && value.variable.isFinal,
    _ => false,
  };

  /// Whether [arguments] pass the context itself to a parameter typed
  /// `JobContext`, so the call can wait through it.
  bool _handsOverContext(ArgumentList arguments) {
    for (final AstNode argument in arguments.arguments) {
      final value = argumentValue(argument).unParenthesized;
      if (value is! SimpleIdentifier || value.element != ctx) continue;
      if (isJobContext(_parameterType(arguments, argument, value))) {
        return true;
      }
    }
    return false;
  }

  /// The type of the parameter that [argument] of [arguments] goes to.
  ///
  /// A named argument is looked up by its name in the type of the call:
  /// the analyzer gives the value of one no parameter.
  static DartType? _parameterType(
    ArgumentList arguments,
    AstNode argument,
    Expression value,
  ) {
    final name = argumentName(argument);
    if (name == null) return value.correspondingParameter?.type;
    final call = arguments.parent;
    final type = call is InvocationExpression ? call.staticInvokeType : null;
    return type is FunctionType ? type.namedParameterTypes[name] : null;
  }

  /// Whether [target] is a variable the body has just taken back from the
  /// cleanup with `ctx.disown`: on the statement before the `await`, or in
  /// the condition of the `if` that the `await` opens. The release that
  /// follows has to run even for a cancellation.
  bool _releases(Expression? target) {
    if (target is! SimpleIdentifier) return false;
    final value = target.element;
    final statement = at.parent;
    if (value == null || statement is! ExpressionStatement) return false;
    AstNode opened = statement;
    final parent = statement.parent;
    if (parent is Block) {
      final statements = parent.statements;
      final index = statements.indexOf(statement);
      if (index > 0 && _calls(statements[index - 1], 'disown', value)) {
        return true;
      }
      if (index != 0) return false;
      opened = parent;
    }
    final around = opened.parent;
    return around is IfStatement &&
        identical(around.thenStatement, opened) &&
        _callsWith(around.expression, 'disown', value);
  }

  /// Whether an earlier statement of a block around [at], inside the body,
  /// matches [test].
  bool _earlier(bool Function(Statement) test) {
    AstNode child = at;
    for (var node = at.parent; node != null; child = node, node = node.parent) {
      if (node is FunctionBody) return false;
      if (node is! Block) continue;
      for (final statement in node.statements) {
        if (identical(statement, child)) break;
        if (test(statement)) return true;
      }
    }
    return false;
  }

  /// Whether [statement] calls the member [name] of the context with
  /// [value].
  bool _calls(Statement statement, String name, Element value) =>
      statement is ExpressionStatement &&
      _callsWith(statement.expression, name, value);

  /// Whether [expression] calls the member [name] of the context with
  /// [value] first, as a call or as a section of a cascade on it.
  bool _callsWith(Expression expression, String name, Element value) {
    final node = expression.unParenthesized;
    if (node is CascadeExpression) {
      return contextNamed(node.target) == ctx &&
          node.cascadeSections.any(
            (section) => _callsWith(section, name, value),
          );
    }
    if (node is! MethodInvocation || !callsOn(node, ctx, {name})) return false;
    final argument = firstPositional(node.argumentList)?.unParenthesized;
    return argument is SimpleIdentifier && argument.element == value;
  }

  /// The value a final local variable named by [node] is initialized with,
  /// when the declaration ends before [node].
  static Expression? _finalLocalValue(SimpleIdentifier node) {
    final element = node.element;
    if (element is! LocalVariableElement || !element.isFinal) return null;
    final finder = _DeclarationFinder(element);
    node.root.accept(finder);
    final declaration = finder.found;
    // A variable read in its own initializer, which only code with errors
    // does, would lead back here.
    if (declaration == null || declaration.end > node.offset) return null;
    return declaration.initializer;
  }

  /// Whether [type] is a future to wait for: `Future`, `FutureOr` or a
  /// subtype, or a type a future may hide behind: `dynamic`, `Object` and a
  /// type parameter bounded by one of these.
  static bool _isFuture(DartType? type) {
    if (type == null || type is DynamicType) return true;
    if (type is TypeParameterType) return _isFuture(type.bound);
    if (type.isDartAsyncFutureOr || type.isDartCoreObject) return true;
    if (type is! InterfaceType) return false;
    return type.isDartAsyncFuture ||
        type.allSupertypes.any((t) => t.isDartAsyncFuture);
  }

  static bool _isFutureClass(Expression? target) {
    if (target is! Identifier) return false;
    final element = target.element;
    return element is InterfaceElement &&
        element.name == 'Future' &&
        element.library.uri.toString() == 'dart:async';
  }
}

/// Collects the argument lists that pass [function] by name.
class _ArgumentUses extends RecursiveAstVisitor<void> {
  final Element function;

  final lists = <ArgumentList>[];

  _ArgumentUses(this.function);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element != function) return;
    final parent = node.parent;
    final list = parent is ArgumentList ? parent : parent?.parent;
    if (list is ArgumentList) lists.add(list);
  }
}

/// Finds a statement that leaves a block other than through its end: a
/// `return`, or a `break` or `continue` to a statement around the block.
/// Functions declared in the block are not part of it.
class _Exits extends RecursiveAstVisitor<void> {
  final Block block;

  bool found = false;

  _Exits(this.block);

  /// Whether a statement of [block] leaves it before its end.
  static bool leave(Block block) {
    final exits = _Exits(block);
    block.accept(exits);
    return exits.found;
  }

  @override
  void visitBreakStatement(BreakStatement node) => _goesTo(node.target);

  @override
  void visitContinueStatement(ContinueStatement node) => _goesTo(node.target);

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitReturnStatement(ReturnStatement node) => found = true;

  void _goesTo(AstNode? target) {
    if (target == null ||
        target.offset < block.offset ||
        target.end > block.end) {
      found = true;
    }
  }
}

class _DeclarationFinder extends RecursiveAstVisitor<void> {
  final Element element;

  VariableDeclaration? found;

  _DeclarationFinder(this.element);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) {
      found = node;
      return;
    }
    super.visitVariableDeclaration(node);
  }
}
