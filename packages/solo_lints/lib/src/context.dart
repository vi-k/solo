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
