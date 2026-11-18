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

/// Whether [type] is `SoloController` of solo, the base of `Solo` and
/// `SoloLanes`, or one of its subtypes.
///
/// Solo before 2.0 has no `SoloController`, and its `Solo` is not one: a rule
/// about any controller asks [isSolo] too.
bool isSoloController(DartType? type) => _isA(type, 'SoloController', _solo);

/// Whether [type] is `SoloLane` of solo, a lane of `SoloLanes`, or one of its
/// subtypes.
bool isSoloLane(DartType? type) => _isA(type, 'SoloLane', _solo);

/// Whether [type] is `SoloLanes` of solo, the controller with lanes, or one
/// of its subtypes; a mixin on `SoloLanes` is one too.
bool isSoloLanes(DartType? type) => _isA(type, 'SoloLanes', _solo);

/// Whether [type] is `SoloJob` of solo or one of its subtypes.
bool isSoloJob(DartType? type) => _isA(type, 'SoloJob', _solo);

/// Whether [type] is `Job` of async_job or one of its subtypes.
bool isJob(DartType? type) => _isA(type, 'Job', _asyncJob);

/// Whether [type] is a job that does not run until it is started: `ChildJob`
/// of async_job or a subtype, other than a `SoloJob`, which the queue starts.
bool isDeferredJob(DartType? type) =>
    _isA(type, 'ChildJob', _asyncJob) && !isSoloJob(type);

/// Whether [element] is the member [name] of the class or enum [type]
/// declared in solo.
///
/// For [type] `Solo` the member of the same name of `SoloLane` counts too:
/// a lane queues its jobs by the members of the queue of a `Solo`.
bool isSoloMember(Element? element, String type, String name) {
  if (element == null || element.name != name) return false;
  final owner = element.enclosingElement;
  if (owner is! InterfaceElement) return false;
  return _named(owner, type, _solo) ||
      (type == 'Solo' && _named(owner, 'SoloLane', _solo));
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
/// for: `method(...).value` and `method(...).done` for a method of a `Solo`
/// that returns a `SoloJob`, and `close()` and `cancelAll()` of a `Solo`.
///
/// A wait in a `SoloLanes` is not among these: [queueLaneOf] tells whether
/// it is for the lane the job runs in.
MethodInvocation? ownQueueCall(Expression waited) {
  final call = queueCallOf(waited);
  if (call == null) return null;
  final jobOf = waited is PropertyAccess;
  final own = _ownMethodOf(call);
  if (own == null) return null;
  final (method, owner) = own;
  if (jobOf) {
    return isSolo(owner) && _returnsSoloJob(call, method) ? call : null;
  }
  // Both close and cancelAll are members of SoloController, so a method of
  // the controller by either name is its own or overrides it; the one of a
  // mixin on SoloController, such as SoloStream, counts in a Solo.
  final ofSolo =
      isSolo(owner) ||
      (isSoloController(owner) && isSolo(controllerAround(call)));
  return ofSolo ? call : null;
}

/// Whose queue a wait is for, as [queueLaneOf] tells it.
enum QueueLane {
  /// The queue or the lane the waiting job runs in: the wait never ends.
  own,

  /// Another lane of the same controller, which runs on its own.
  other,

  /// Not known: not a wait for a queue, or a lane that is not seen.
  unknown,
}

/// Whose queue [waited] waits for, when a job body of the enclosing
/// controller waits for it.
///
/// For a `Solo` the answer is [QueueLane.own] where [ownQueueCall] finds
/// the call. `close()` and `cancelAll()` of any controller are
/// [QueueLane.own]: they wait for every lane. In a `SoloLanes` the lane of
/// the waited job is the lane field the call queues it in,
/// `_likes.enqueue(...)`, or the one a method of the controller queues it
/// in, read from the method's body in the same file; the lane of the
/// waiting body is the lane field whose `enqueue` takes it. Both seen and
/// the same is [QueueLane.own], both seen and different is
/// [QueueLane.other]; anything else, a body of a child or of a handler of
/// an accumulator included, is [QueueLane.unknown].
QueueLane queueLaneOf(Expression waited) {
  final call = queueCallOf(waited);
  if (call == null) return QueueLane.unknown;
  final jobOf = waited is PropertyAccess;
  final target = call.realTarget;
  if (target != null &&
      target is! ThisExpression &&
      target is! SuperExpression) {
    // A job queued in a lane right here: `_likes.enqueue(...).done`.
    final lane = jobOf ? _laneQueuedBy(call) : null;
    return lane == null ? QueueLane.unknown : _laneAgainst(lane, waited);
  }
  final own = _ownMethodOf(call);
  if (own == null) return QueueLane.unknown;
  final (method, owner) = own;
  if (!jobOf) {
    return isSolo(owner) || isSoloController(owner)
        ? QueueLane.own
        : QueueLane.unknown;
  }
  if (isSolo(owner)) {
    return _returnsSoloJob(call, method) ? QueueLane.own : QueueLane.unknown;
  }
  if (!isSoloController(owner)) return QueueLane.unknown;
  // A declared SoloJob does not name the lane, so the body is read always.
  final lane = _laneOfMethod(call, method);
  return lane == null ? QueueLane.unknown : _laneAgainst(lane, waited);
}

/// [QueueLane.own] when the job body that waits for [waited] runs in
/// [lane], [QueueLane.other] when it runs in another lane.
QueueLane _laneAgainst(Element lane, AstNode waited) {
  final body = queuedBodyOf(waited)?.lane;
  if (body == null) return QueueLane.unknown;
  return body == lane ? QueueLane.own : QueueLane.other;
}

/// The call [waited] waits for: the target of `.value` or `.done` when it
/// is a call, or [waited] itself when it calls `close` or `cancelAll`.
MethodInvocation? queueCallOf(Expression waited) {
  if (waited is PropertyAccess &&
      const {'value', 'done'}.contains(waited.propertyName.name)) {
    final target = waited.realTarget.unParenthesized;
    return target is MethodInvocation ? target : null;
  }
  if (waited is MethodInvocation &&
      const {'close', 'cancelAll'}.contains(waited.methodName.name)) {
    return waited;
  }
  return null;
}

/// The method of a class or a mixin that [call] calls on `this` or
/// `super`, and the type that declares it.
(MethodElement, InterfaceType)? _ownMethodOf(MethodInvocation call) {
  final target = call.realTarget;
  if (target != null &&
      target is! ThisExpression &&
      target is! SuperExpression) {
    return null;
  }
  final method = call.methodName.element;
  if (method is! MethodElement) return null;
  final owner = method.enclosingElement;
  return owner is InterfaceElement ? (method, owner.thisType) : null;
}

/// The type of the class or the mixin around [node]: the controller, when
/// [node] is in one.
DartType? controllerAround(AstNode node) {
  final around = node.thisOrAncestorMatching(
    (node) => node is ClassDeclaration || node is MixinDeclaration,
  );
  final element = switch (around) {
    ClassDeclaration(:final declaredFragment) => declaredFragment?.element,
    MixinDeclaration(:final declaredFragment) => declaredFragment?.element,
    _ => null,
  };
  return element?.thisType;
}

/// The lane field of this controller that [expression] reads, `_likes` or
/// `this._likes`: an instance field typed `SoloLane` whose every write in its
/// class is a `lane(...)` declaration in a constructor body. A getter is not
/// one, nor is a lane the controller takes rather than declares, or may take
/// as well: which lane it gives is not seen, and a lane is public, so it may
/// be another controller's.
Element? _laneField(Expression? expression) {
  final node = expression?.unParenthesized;
  final read = switch (node) {
    SimpleIdentifier() => node.element,
    PropertyAccess(target: ThisExpression()) => node.propertyName.element,
    _ => null,
  };
  final field = read is GetterElement ? read.variable : read;
  if (field is! FieldElement || field.isStatic || !field.isOriginDeclaration) {
    return null;
  }
  if (!isSoloLane(field.type)) return null;

  return _ownLaneFields(node!.root).contains(field.baseElement)
      ? field.baseElement
      : null;
}

/// The own lane fields of each unit, found in one walk of it.
final _ownLaneFieldsOf = Expando<Set<Element>>('own lane fields');

/// The fields of the unit [root] is in that are their controller's own
/// lanes.
Set<Element> _ownLaneFields(AstNode root) =>
    _ownLaneFieldsOf[root] ??= (_LaneDeclarations()..walk(root)).own;

/// Finds the writes of the fields of a unit: `field = lane(...)` or
/// `this.field = lane(...)` right in a constructor body of the class that
/// declares it, where `SoloLanes` lets a controller declare its lanes, and
/// every other write, which makes the field one that may hold another
/// controller's lane.
class _LaneDeclarations extends RecursiveAstVisitor<void> {
  final _declared = <Element>{};
  final _written = <Element>{};

  /// The fields written only by a declaration.
  Set<Element> get own => _declared.difference(_written);

  void walk(AstNode root) => root.accept(this);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    final written = node.writeElement;
    final target = written is SetterElement ? written.variable : written;
    if (target is! FieldElement) return;
    final field = target.baseElement;
    final value = node.rightHandSide.unParenthesized;
    final inConstructor = node.thisOrAncestorOfType<ConstructorDeclaration>();
    final declares =
        node.operator.type == TokenType.EQ &&
        value is MethodInvocation &&
        declaresLane(value) &&
        inConstructor?.declaredFragment?.element.enclosingElement ==
            field.enclosingElement;
    (declares ? _declared : _written).add(field);
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    super.visitFieldFormalParameter(node);
    final element = node.declaredFragment?.element;
    final field = element is FieldFormalParameterElement ? element.field : null;
    if (field != null) _written.add(field.baseElement);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    super.visitConstructorFieldInitializer(node);
    final field = node.fieldName.element;
    if (field is FieldElement) _written.add(field.baseElement);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    final field = node.declaredFragment?.element;
    if (node.initializer != null && field is FieldElement) {
      _written.add(field.baseElement);
    }
  }
}

/// Whether [call] declares a lane where `SoloLanes` lets a controller
/// declare it: `lane(...)` of `SoloLanes` on `this` or `super`, right in a
/// constructor body rather than in a function declared there.
///
/// A `lane(...)` anywhere else, a `late final` initializer or a method,
/// throws once `SoloLanes` has sealed its lanes, a microtask after the
/// constructor.
bool declaresLane(MethodInvocation call) {
  final on = call.realTarget;
  if (on != null && on is! ThisExpression && on is! SuperExpression) {
    return false;
  }
  if (!isSoloMember(call.methodName.element, 'SoloLanes', 'lane')) {
    return false;
  }
  final constructor = call.thisOrAncestorOfType<ConstructorDeclaration>();
  return constructor != null &&
      call.thisOrAncestorOfType<FunctionBody>() == constructor.body;
}

/// The lane field [call] queues a job in: `enqueue` or `enqueueJob` of a
/// `SoloLane` read from a field of this controller.
Element? _laneQueuedBy(MethodInvocation call) {
  final name = call.methodName.name;
  if (name != 'enqueue' && name != 'enqueueJob') return null;
  final owner = call.methodName.element?.enclosingElement;
  if (owner is! InterfaceElement || !_named(owner, 'SoloLane', _solo)) {
    return null;
  }
  return _laneField(call.realTarget);
}

/// The lane field every value [method] returns is queued in, when the
/// method is declared in the file of [call].
Element? _laneOfMethod(MethodInvocation call, MethodElement method) {
  final finder = _MethodFinder(method.baseElement);
  call.root.accept(finder);
  final body = finder.found?.body;
  if (body == null) return null;
  final lanes = {
    for (final value in returnedValues(body))
      switch (value.unParenthesized) {
        final MethodInvocation queued => _laneQueuedBy(queued),
        _ => null,
      },
  };
  return lanes.length == 1 ? lanes.single : null;
}

/// The job body of this controller that waits for [node], when there is
/// one: its context, and the lane field whose `enqueue` takes the body.
///
/// [node] is in the body itself, in the actions of waiting calls on its
/// context or in its cleanup, which the queue waits for as well. The body
/// takes a `SoloContext` and is given to a call on this controller, on the
/// context of a body queued here or on a lane field, or to no call; the
/// class or the mixin around is a controller. A child runs where its parent
/// does: the child of a job of another controller runs there. The lane is
/// `null` for a body given to anything but `enqueue` of a lane: a body given
/// to `job` may run as a child in another lane, and a handler of `collect`
/// or `accumulate` runs where its group goes. A rule that reports a wait for
/// the own queue or the own lane looks at this body, and a rule that leaves
/// a wait for the own lane to it asks the same.
({Element ctx, Element? lane})? queuedBodyOf(AstNode node) {
  final around = controllerAround(node);
  if (!isSolo(around) && !isSoloController(around)) return null;
  final crossed = <Element>[];
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is! FunctionExpression) continue;
    final ctx = jobContextOf(at);
    if (ctx != null) {
      if (!isSoloContext(ctx.type)) return null;
      if (!crossed.every((c) => c == ctx)) return null;
      return _queuedHere(at, ctx);
    }
    final through = waitingContext(at) ?? cleanupContext(at);
    if (through == null) return null;
    crossed.add(through);
  }
  return null;
}

/// [body] with its context [ctx] when it is given to a call on this
/// controller, on the context of a body queued here or on a lane field, or
/// to no call, rather than to another controller's `enqueue`; with the lane
/// when it is given to `enqueue` of a lane field.
({Element ctx, Element? lane})? _queuedHere(
  FunctionExpression body,
  Element ctx,
) {
  // A body is a positional argument or, by its name, a named one.
  final parent = body.parent;
  final list = parent is ArgumentList ? parent : parent?.parent;
  final call = list?.parent;
  if (list is! ArgumentList || call is! MethodInvocation) {
    return (ctx: ctx, lane: null);
  }
  final target = call.realTarget;
  if (target == null || target is ThisExpression || target is SuperExpression) {
    return (ctx: ctx, lane: null);
  }
  if (isJobContext(target.staticType)) {
    // `outer.child(...)`: here when `outer` is the context of a body queued
    // here, not of a job of another controller.
    final parent = target.unParenthesized;
    final outer = queuedBodyOf(call);
    return parent is SimpleIdentifier &&
            outer != null &&
            parent.element == outer.ctx
        ? (ctx: ctx, lane: null)
        : null;
  }
  if (_laneField(target) == null) return null;
  return (ctx: ctx, lane: _laneQueuedBy(call));
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
