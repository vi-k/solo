/// Recognizers for the shapes of async_job and solo in a syntax tree.
///
/// The plugin does not depend on either package: a type is recognized by its
/// name and the library it comes from, so a renamed class leaves a rule silent
/// rather than wrong.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

const _asyncJob = 'package:async_job/';
const _solo = 'package:solo/';

/// The members of `JobContext` that throw the job's `Cancelled` once the job
/// has accepted one.
const coreCheckpoints = {
  'check',
  'join',
  'abandonable',
  'wait',
  'uncancellable',
  'pause',
  'run',
  'runAll',
};

/// The members `SoloContext` adds to [coreCheckpoints]; `state` is a getter.
const soloCheckpoints = {'emit', 'state', 'stateAs'};

/// The waiting calls whose `dispose:` and `discard:` take a cleanup.
const releasingCalls = {'join', 'abandonable', 'wait', 'run'};

/// The calls on a context whose action the body waits for.
const waitingCalls = {'join', 'abandonable', 'wait', 'uncancellable'};

/// Whether [element] comes from a library of async_job or solo.
bool isFromJobPackages(Element? element) {
  final uri = element?.library?.uri.toString();
  if (uri == null) return false;
  return uri.startsWith(_asyncJob) || uri.startsWith(_solo);
}

bool _named(InterfaceElement element, String name, String package) =>
    element.name == name &&
    (element.library.uri.toString().startsWith(package));

/// Whether [type] is the class [name] of [package] or one of its subtypes.
bool _isA(DartType? type, String name, String package) {
  if (type is! InterfaceType) return false;
  return _named(type.element, name, package) ||
      type.allSupertypes.any((t) => _named(t.element, name, package));
}

/// Whether [type] is `JobContext` of async_job or one of its subtypes.
bool isJobContext(DartType? type) => _isA(type, 'JobContext', _asyncJob);

/// Whether [type] is `SoloContext` of solo or one of its subtypes.
bool isSoloContext(DartType? type) => _isA(type, 'SoloContext', _solo);

/// Whether [type] is `Solo` of solo or one of its subclasses.
bool isSolo(DartType? type) => _isA(type, 'Solo', _solo);

/// Whether [type] is `SoloJob` of solo or one of its subtypes.
bool isSoloJob(DartType? type) => _isA(type, 'SoloJob', _solo);

/// Whether [element] is the member [name] of the class or enum [type]
/// declared in solo.
bool isSoloMember(Element? element, String type, String name) {
  if (element == null || element.name != name) return false;
  final owner = element.enclosingElement;
  return owner is InterfaceElement && _named(owner, type, _solo);
}

/// Whether [element] is the class [name] declared in async_job.
bool isCoreClass(Element? element, String name) =>
    element is InterfaceElement && _named(element, name, _asyncJob);

/// Whether [element] is the class [name] declared in `dart:core`.
bool isDartCoreClass(Element? element, String name) =>
    element is InterfaceElement &&
    element.name == name &&
    element.library.uri.toString() == 'dart:core';

/// Whether a catch clause on [type] takes `Cancelled`, which is an
/// `Outcome<Never>` and an `Exception`.
bool takesCancelled(DartType? type) {
  if (type == null || type is DynamicType) return true;
  final element = type.element;
  return isDartCoreClass(element, 'Object') ||
      isDartCoreClass(element, 'Exception') ||
      isCoreClass(element, 'Outcome');
}

/// The context of [node] when it is a job body: its first parameter, if that
/// is typed `JobContext` or a subtype.
FormalParameterElement? jobContextOf(FunctionExpression node) {
  final parameters = node.parameters?.parameters;
  if (parameters == null || parameters.isEmpty) return null;
  // A wildcard names no context: nothing in the body can call on it.
  if (parameters.first.name?.lexeme == '_') return null;
  final element = parameters.first.declaredFragment?.element;
  return isJobContext(element?.type) ? element : null;
}

/// The context [target] names: the element of a simple identifier typed
/// `JobContext` or a subtype, otherwise `null`.
Element? contextNamed(Expression? target) {
  if (target is SimpleIdentifier && isJobContext(target.staticType)) {
    return target.element;
  }
  return null;
}

/// Whether [node] calls a member of async_job or solo named one of [names] on
/// the context [ctx].
bool callsOn(MethodInvocation node, Element ctx, Set<String> names) =>
    names.contains(node.methodName.name) &&
    contextNamed(node.realTarget) == ctx &&
    isFromJobPackages(node.methodName.element);

/// The context whose getter [node] reads, when [node] is `ctx.name`.
Element? _getterOf(AstNode node, String name) {
  if (node is PrefixedIdentifier && node.identifier.name == name) {
    return contextNamed(node.prefix);
  }
  if (node is PropertyAccess && node.propertyName.name == name) {
    return contextNamed(node.realTarget);
  }
  return null;
}

/// Whether [node] reads `ctx.state` of a `SoloContext`.
bool readsState(AstNode node, Element ctx) {
  if (_getterOf(node, 'state') != ctx) return false;
  final target = node is PrefixedIdentifier
      ? node.prefix
      : (node as PropertyAccess).realTarget;
  return isSoloContext(target.staticType);
}

/// The checkpoints of [ctx]: [coreCheckpoints], and [soloCheckpoints] for a
/// `SoloContext`.
Set<String> checkpointsOf(Element ctx) {
  final type = switch (ctx) {
    VariableElement(:final type) => type,
    _ => null,
  };
  return isSoloContext(type)
      ? {...coreCheckpoints, ...soloCheckpoints}
      : coreCheckpoints;
}

/// Whether [expression], with any `await` and parentheses taken off, is a
/// checkpoint on [ctx].
bool isCheckpoint(Expression expression, Element ctx) {
  var node = expression.unParenthesized;
  if (node is AwaitExpression) node = node.expression.unParenthesized;
  if (node is MethodInvocation) {
    return callsOn(node, ctx, checkpointsOf(ctx));
  }
  return readsState(node, ctx);
}

// analyzer 12 calls a named argument `NamedExpression`, analyzer 13 and
// later `NamedArgument`, and only the later ones type the list of arguments
// as `Argument`. The plugin supports both, so it names neither: a positional
// argument is an `Expression` in both, and a named one is told by its tokens.

/// The name of [argument] in an [ArgumentList] when it is named, otherwise
/// `null`.
String? argumentName(AstNode argument) {
  final name = argument.beginToken;
  final colon = name.next;
  return name.isIdentifier && colon != null && colon.type == TokenType.COLON
      ? name.lexeme
      : null;
}

/// The value of [argument] in an [ArgumentList], named or positional.
Expression argumentValue(AstNode argument) => argumentName(argument) == null
    ? argument as Expression
    : argument.childEntities.whereType<Expression>().last;

/// The value of the first positional argument of [list], if there is one.
Expression? firstPositional(ArgumentList list) {
  for (final AstNode argument in list.arguments) {
    if (argumentName(argument) == null) return argument as Expression;
  }
  return null;
}

/// The value of the argument [name] of [list], if it is given.
Expression? namedValue(ArgumentList list, String name) {
  for (final AstNode argument in list.arguments) {
    if (argumentName(argument) == name) return argumentValue(argument);
  }
  return null;
}

/// The context [node] is registered as cleanup on, if it is one.
///
/// A cleanup is the function passed to `ctx.onDispose` or `ctx.onDiscard`, or
/// the `dispose:` or `discard:` argument of `ctx.join`, `ctx.abandonable`,
/// `ctx.wait` and `ctx.run`.
Element? cleanupContext(Expression node) {
  final parent = node.parent;
  final argument = parent is ArgumentList ? node : parent;
  final list = argument?.parent;
  if (argument == null || list is! ArgumentList) return null;
  final call = list.parent;
  if (call is! MethodInvocation) return null;
  final ctx = contextNamed(call.realTarget);
  if (ctx == null || !isFromJobPackages(call.methodName.element)) return null;
  final name = call.methodName.name;
  final label = argumentName(argument);
  if (label == null) {
    return firstPositional(list) == node &&
            (name == 'onDispose' || name == 'onDiscard')
        ? ctx
        : null;
  }
  return (label == 'dispose' || label == 'discard') &&
          releasingCalls.contains(name)
      ? ctx
      : null;
}

/// The context of the waiting call whose action [node] is, otherwise `null`.
Element? waitingContext(FunctionExpression node) {
  final list = node.parent;
  if (list is! ArgumentList || firstPositional(list) != node) return null;
  final call = list.parent;
  if (call is! MethodInvocation) return null;
  final ctx = contextNamed(call.realTarget);
  if (ctx == null || !callsOn(call, ctx, waitingCalls)) return null;
  return ctx;
}

/// The context of the job body around [node], unless [node] is in a cleanup,
/// where a checkpoint throws `StateError`, or in a function that runs on its
/// own: unattended work, a listener, a timer.
Element? bodyContextAround(AstNode node) {
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is! FunctionExpression) continue;
    if (cleanupContext(at) != null) return null;
    final ctx = jobContextOf(at);
    if (ctx != null) return ctx;
    // A local function runs when the body calls it, and the action of a
    // waiting call while the body waits for it.
    if (at.parent is! FunctionDeclaration && waitingContext(at) == null) {
      return null;
    }
  }
  return null;
}

/// The function [argument] stands for: a literal, the declaration of the
/// local function it names or the literal a final local variable it names
/// holds; `null` for anything else.
FunctionExpression? functionOf(Expression argument) {
  final node = argument.unParenthesized;
  if (node is FunctionExpression) return node;
  if (node is! SimpleIdentifier) return null;
  final element = node.element;
  final named =
      element is LocalFunctionElement ||
      (element is LocalVariableElement && element.isFinal);
  if (!named) return null;
  final finder = _FunctionFinder(element!);
  node.root.accept(finder);
  return finder.found;
}

class _FunctionFinder extends RecursiveAstVisitor<void> {
  final Element element;

  FunctionExpression? found;

  _FunctionFinder(this.element);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.declaredFragment?.element == element) {
      found = node.functionExpression;
      return;
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) {
      final value = node.initializer?.unParenthesized;
      if (value is FunctionExpression) found = value;
      return;
    }
    super.visitVariableDeclaration(node);
  }
}

/// The call of the enclosing controller's own queue that [waited] waits
/// for: `method(...).value` and `method(...).done` for a method that returns
/// a `SoloJob`, and `close()` and `cancelAll()`.
MethodInvocation? ownQueueCall(Expression waited) {
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
bool _returnsSoloJob(MethodInvocation call, MethodElement method) {
  if (isSoloJob(call.staticType)) return true;
  final finder = _MethodFinder(method.baseElement);
  call.root.accept(finder);
  final body = finder.found?.body;
  return body != null &&
      returnedValues(body).any((value) => isSoloJob(value.staticType));
}

/// The values [body] returns: its expression, or the values of the return
/// statements of its block outside the functions declared in it.
List<Expression> returnedValues(FunctionBody body) {
  if (body is ExpressionFunctionBody) return [body.expression];
  if (body is! BlockFunctionBody) return const [];
  final returns = _Returns();
  body.block.accept(returns);
  return returns.values;
}

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

/// The statement by which the catch [body] asks the job of [ctx] whether it
/// was cancelled before it acts: `if (ctx.job.isCancelled) rethrow;` first,
/// or a checkpoint first after any `if (...) rethrow;` lines; `null` when the
/// catch acts first.
Statement? askingStatement(Block body, Element ctx) {
  final statements = body.statements;
  if (statements.isEmpty) return null;
  final first = statements.first;
  if (first is IfStatement &&
      _isCancelledOf(first.expression, ctx) &&
      isRethrowIf(first)) {
    return first;
  }
  // `if (attempt == 3) rethrow;` passes the cancellation on unchanged, so
  // the statement after it is the first that acts.
  for (final statement in statements) {
    if (isRethrowIf(statement)) continue;
    return _isCheckpointStatement(statement, ctx) ? statement : null;
  }
  return null;
}

/// Whether [statement] is a checkpoint of [ctx], as an expression or as the
/// value of a variable.
bool _isCheckpointStatement(Statement statement, Element ctx) {
  if (statement is ExpressionStatement) {
    return isCheckpoint(statement.expression, ctx);
  }
  if (statement is VariableDeclarationStatement) {
    final initializer = statement.variables.variables.first.initializer;
    return initializer != null && isCheckpoint(initializer, ctx);
  }
  return false;
}

/// Whether [statement] is `if (...) rethrow;` with no else.
bool isRethrowIf(Statement statement) =>
    statement is IfStatement &&
    statement.elseStatement == null &&
    isRethrow(statement.thenStatement);

/// Whether [statement] is `rethrow;` or a block of nothing else.
bool isRethrow(Statement statement) {
  if (statement is Block) {
    return statement.statements.length == 1 &&
        isRethrow(statement.statements.single);
  }
  return statement is ExpressionStatement &&
      statement.expression is RethrowExpression;
}

/// Whether [condition] is `ctx.job.isCancelled`.
bool _isCancelledOf(Expression condition, Element ctx) {
  final node = condition.unParenthesized;
  if (node is! PropertyAccess || node.propertyName.name != 'isCancelled') {
    return false;
  }
  final job = node.realTarget;
  return job is PrefixedIdentifier &&
      job.identifier.name == 'job' &&
      contextNamed(job.prefix) == ctx;
}
