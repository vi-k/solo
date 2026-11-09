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

/// Reports an outcome of a job that is waited for and dropped: reading
/// `done` takes the failure off its route, so nothing answers for it.
class DiscardedOutcome extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'discarded_outcome',
    "The outcome is dropped here, and reading 'done' took the failure off its "
        'route: nothing answers for a failure of this job.',
    correctionMessage:
        "Read the outcome, await 'value' to have the failure thrown, or call "
        "'ignoreFailure()' on the job if its failure is not wanted.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  DiscardedOutcome()
    : super(
        name: 'discarded_outcome',
        description:
            "An outcome of 'done' that nobody reads: the failure of the job "
            'reaches no answerer.',
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
      ..addExpressionStatement(this, visitor)
      ..addReturnStatement(this, visitor)
      ..addExpressionFunctionBody(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    var dropped = node.expression.unParenthesized;
    if (dropped is AwaitExpression) {
      dropped = dropped.expression.unParenthesized;
    }
    if (!_isOutcomeFuture(dropped.staticType)) return;
    // A body waiting for its own queue is named by bare_await and
    // await_own_queue: the job waits for itself.
    if (bodyContextAround(node) != null && ownQueueCall(dropped) != null) {
      return;
    }
    _check(dropped);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    final value = node.expression;
    final body = node.thisOrAncestorOfType<FunctionBody>();
    if (value == null || body == null) return;
    _checkReturned(value, body);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) =>
      _checkReturned(node.expression, node);

  /// Checks [value], returned from [body], when the function drops it: its
  /// return type is `void`, `Future<void>` or `FutureOr<void>`. An awaited
  /// value counts too: `() async => await job.done` drops the outcome all the
  /// same.
  void _checkReturned(Expression value, FunctionBody body) {
    var returned = value.unParenthesized;
    if (returned is AwaitExpression) {
      returned = returned.expression.unParenthesized;
    }
    if (!_isOutcomeFuture(returned.staticType)) return;
    if (!_returnTypesOf(body).any(_isVoid)) return;
    _check(returned);
  }

  /// Reports [dropped] unless its job is read later or told to drop its
  /// failure earlier.
  void _check(Expression dropped) {
    final job = _jobOf(dropped);
    if (job != null && _answeredNearby(job, dropped)) return;
    final member = _doneName(dropped);
    if (member != null) {
      rule.reportAtNode(member);
    } else {
      rule.reportAtNode(dropped);
    }
  }

  /// Whether the scope of [job] reads its outcome after [dropped] or calls
  /// `ignoreFailure()` on it before.
  static bool _answeredNearby(Element job, Expression dropped) {
    final scope = _scopeOf(job, dropped);
    if (scope == null) return false;
    final uses = _Uses(job, dropped);
    scope.accept(uses);
    return uses.answered;
  }

  /// The innermost function around [node] that declares [job].
  static AstNode? _scopeOf(Element job, AstNode node) {
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is! FunctionBody) continue;
      final function = at.parent;
      if (function == null) continue;
      final finder = _Declaration(job);
      function.accept(finder);
      if (finder.found) return function;
    }
    return null;
  }

  /// The local variable or parameter whose `done` [dropped] reads, directly
  /// or as the action of a waiting call.
  static Element? _jobOf(Expression dropped) {
    final direct = _receiverOfDone(dropped);
    if (direct != null) return direct;
    if (dropped is! MethodInvocation) return null;
    final ctx = contextNamed(dropped.realTarget);
    if (ctx == null || !callsOn(dropped, ctx, waitingCalls)) return null;
    final argument = firstPositional(dropped.argumentList);
    final action = argument == null ? null : functionOf(argument);
    if (action == null) return null;
    final values = returnedValues(action.body);
    return values.length == 1
        ? _receiverOfDone(values.single.unParenthesized)
        : null;
  }

  /// The local variable or parameter [node] reads `done` of.
  static Element? _receiverOfDone(Expression node) {
    final target = switch (node) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier.name == 'done' =>
        prefix,
      PropertyAccess(:final propertyName) when propertyName.name == 'done' =>
        node.realTarget.unParenthesized,
      _ => null,
    };
    if (target is! SimpleIdentifier) return null;
    final element = target.element;
    return element is LocalVariableElement || element is FormalParameterElement
        ? element
        : null;
  }

  /// The name `done` when [node] ends with it.
  static SimpleIdentifier? _doneName(Expression node) => switch (node) {
    PrefixedIdentifier(:final identifier) when identifier.name == 'done' =>
      identifier,
    PropertyAccess(:final propertyName) when propertyName.name == 'done' =>
      propertyName,
    _ => null,
  };

  /// The return types the function of [body] has: its own, and the one the
  /// parameter it is passed to, or the variable it initializes or is
  /// assigned to, expects.
  static Iterable<DartType> _returnTypesOf(FunctionBody body) sync* {
    final function = body.parent;
    if (function is FunctionExpression) {
      final type = function.staticType;
      if (type is FunctionType) yield type.returnType;
      final slot = _slotOf(function);
      for (final expected in [
        slot.correspondingParameter?.type,
        _namedParameterType(slot),
        _variableType(slot),
        _assignedType(slot),
      ]) {
        if (expected is FunctionType) yield expected.returnType;
      }
    } else if (function is MethodDeclaration) {
      final type = function.declaredFragment?.element.returnType;
      if (type != null) yield type;
    }
  }

  /// The expression whose place decides the type [function] is expected to
  /// have: [function] itself, or the parentheses, the branch of `?:` or the
  /// operand of `??` around it.
  static Expression _slotOf(FunctionExpression function) {
    Expression slot = function;
    while (true) {
      final parent = slot.parent;
      if (parent is! Expression) return slot;
      final passes = switch (parent) {
        ParenthesizedExpression() => true,
        ConditionalExpression(:final condition) => condition != slot,
        BinaryExpression(:final operator) =>
          operator.type == TokenType.QUESTION_QUESTION,
        _ => false,
      };
      if (!passes) return slot;
      slot = parent;
    }
  }

  /// The type of the named parameter [slot] is passed to.
  ///
  /// A named argument has no `correspondingParameter` on its value, and its
  /// own node is `NamedExpression` in analyzer 12 and `NamedArgument` later,
  /// so the parameter is found by name in the type of the invocation: of the
  /// constructor for `super(...)`, `this(...)` and `.new(...)`, whose
  /// invocation has no type of its own.
  static DartType? _namedParameterType(Expression slot) {
    final argument = slot.parent;
    if (argument == null) return null;
    final name = argumentName(argument);
    final list = argument.parent;
    if (name == null || list is! ArgumentList) return null;
    final invoked = switch (list.parent) {
      ConstructorReferenceNode(:final element) => element?.type,
      InvocationExpression(:final staticInvokeType) => staticInvokeType,
      InstanceCreationExpression(:final constructorName) =>
        constructorName.element?.type,
      _ => null,
    };
    if (invoked is! FunctionType) return null;
    for (final parameter in invoked.formalParameters) {
      if (parameter.isNamed && parameter.name == name) return parameter.type;
    }
    return null;
  }

  /// The declared type of the variable [slot] initializes.
  static DartType? _variableType(Expression slot) {
    final variable = slot.parent;
    return variable is VariableDeclaration
        ? variable.declaredFragment?.element.type
        : null;
  }

  /// The type of what [slot] is assigned to with `=` or `??=`.
  static DartType? _assignedType(Expression slot) {
    final assignment = slot.parent;
    if (assignment is! AssignmentExpression ||
        assignment.rightHandSide != slot) {
      return null;
    }
    return switch (assignment.operator.type) {
      TokenType.EQ || TokenType.QUESTION_QUESTION_EQ => assignment.writeType,
      _ => null,
    };
  }

  /// Whether [type] is `void`, `Future<void>` or `FutureOr<void>`.
  static bool _isVoid(DartType type) {
    if (type is VoidType) return true;
    return type is InterfaceType &&
        (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
        type.typeArguments.single is VoidType;
  }

  /// Whether [type] is a `Future` of `Outcome` of async_job.
  static bool _isOutcomeFuture(DartType? type) {
    if (type is! InterfaceType || !type.isDartAsyncFuture) return false;
    final value = type.typeArguments.single;
    return value is InterfaceType && isCoreClass(value.element, 'Outcome');
  }
}

/// Finds the declaration of a local variable or parameter.
class _Declaration extends RecursiveAstVisitor<void> {
  final Element element;

  bool found = false;

  _Declaration(this.element);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) found = true;
    super.visitVariableDeclaration(node);
  }

  // analyzer 12 and 14 name the node of a parameter differently, so the
  // list is visited instead.
  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      if (parameter.declaredFragment?.element == element) found = true;
    }
    super.visitFormalParameterList(node);
  }
}

/// Looks for an answer to the failure of a job around the dropped outcome:
/// a read of `outcome`, `value` or `done` after it, or `ignoreFailure()`
/// before it, as a call or in a cascade of the declaration.
class _Uses extends RecursiveAstVisitor<void> {
  final Element job;

  final Expression dropped;

  bool answered = false;

  _Uses(this.job, this.dropped);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final value = node.initializer;
    if (node.declaredFragment?.element == job &&
        value is CascadeExpression &&
        value.cascadeSections.any(_isIgnoreFailure)) {
      answered = true;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element != job) return;
    final member = _memberOn(node);
    if (member == null) return;
    if (member == 'ignoreFailure' && node.offset < dropped.offset) {
      answered = true;
    }
    if (const {'outcome', 'value', 'done'}.contains(member) &&
        node.offset >= dropped.end) {
      answered = true;
    }
  }

  static bool _isIgnoreFailure(Expression section) =>
      section is MethodInvocation &&
      section.methodName.name == 'ignoreFailure' &&
      isFromJobPackages(section.methodName.element);

  /// The member read or called on [node], if [node] is the target.
  static String? _memberOn(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final prefix, :final identifier) when prefix == node =>
      identifier.name,
    PropertyAccess(:final target, :final propertyName) when target == node =>
      propertyName.name,
    MethodInvocation(:final target, :final methodName) when target == node =>
      methodName.name,
    _ => null,
  };
}
