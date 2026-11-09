import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports the first observation of a job made in a function when a wait
/// stands between the job and the observation: the job can end during the
/// wait, and its failure is answered for before the observation.
class OutcomeAfterAwait extends MultiAnalysisRule {
  /// The diagnostic for a late `done`.
  static const LintCode doneCode = LintCode(
    'outcome_after_await',
    _message,
    correctionMessage:
        "Read 'done' right after {1}, 'final outcome = {2}.done;', and await "
        'that outcome here.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.outcome_after_await_done',
  );

  /// The diagnostic for a late `value`.
  static const LintCode valueCode = LintCode(
    'outcome_after_await',
    _message,
    correctionMessage:
        "Take 'value' right after {1}, 'final value = {2}.value..ignore();', "
        'and await it here.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.outcome_after_await_value',
  );

  /// The diagnostic for a late `ignoreFailure()`.
  static const LintCode ignoreFailureCode = LintCode(
    'outcome_after_await',
    _message,
    correctionMessage:
        "Call 'ignoreFailure()' right after {1}, before any wait.",
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.outcome_after_await_ignore_failure',
  );

  /// The diagnostic for a late `then` or `shared()`.
  static const LintCode continuationCode = LintCode(
    'outcome_after_await',
    _message,
    correctionMessage:
        'Make the continuation right after {1}, before any wait.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.outcome_after_await_continuation',
  );

  static const _message =
      'The job can end during a wait above, and its failure is then answered '
      "for before this line reads '{0}'.";

  /// Creates the rule.
  OutcomeAfterAwait()
    : super(
        name: 'outcome_after_await',
        description:
            'A job is observed before the first wait after it is made: a '
            'failure during the wait is otherwise answered for twice.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    doneCode,
    valueCode,
    ignoreFailureCode,
    continuationCode,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addVariableDeclarationStatement(this, _Visitor(this));
  }
}

/// The members that observe a job (decision 146 of the project), with the
/// name the message gives each and the code it reports.
const _observers = {
  'done': ('done', OutcomeAfterAwait.doneCode),
  'value': ('value', OutcomeAfterAwait.valueCode),
  'ignoreFailure': ('ignoreFailure()', OutcomeAfterAwait.ignoreFailureCode),
  'then': ('then', OutcomeAfterAwait.continuationCode),
  'shared': ('shared()', OutcomeAfterAwait.continuationCode),
};

/// The members that neither observe a job nor hand it to anybody.
const _bystanders = {
  'cancel',
  'outcome',
  'isRunning',
  'isFinished',
  'isCancelled',
  'key',
  'describe',
  'level',
  'isChild',
  'whenCancelled',
  'whenFinished',
};

class _Visitor extends SimpleAstVisitor<void> {
  final MultiAnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    final scope = node.thisOrAncestorOfType<FunctionBody>();
    if (scope == null) return;
    final late = node.variables.isLate;
    for (final variable in node.variables.variables) {
      final value = variable.initializer?.unParenthesized;
      final job = variable.declaredFragment?.element;
      if (value == null || job == null || !_isMade(value)) continue;
      _check(job, variable.name.lexeme, node, scope, _isDeferred(value), late);
    }
  }

  void _check(
    Element job,
    String name,
    Statement declaration,
    FunctionBody scope,
    bool deferred,
    bool late,
  ) {
    final events = _Events(job, scope.isAsynchronous && scope.isGenerator);
    scope.accept(events);
    // The window opens where the job can start to fail: at its declaration,
    // at the first read of a late variable, which makes the job, or at
    // `start()` for a job that does not run until it is started. A first
    // read that might not run leaves the job's making unknown, and the rule
    // keeps quiet.
    var opened = deferred || late ? null : declaration.end;
    var made = !late;
    for (final use in events.uses) {
      if (use.offset < declaration.end) continue;
      if (use.escapes) return;
      if (!made) {
        made = true;
        if (!deferred) {
          if (!_runsSurely(use.reference, declaration)) return;
          opened = use.offset;
        }
      }
      final member = use.member;
      if (member == 'start') {
        opened = use.end;
        continue;
      }
      if (_bystanders.contains(member)) continue;
      final observer = _observers[member];
      final at = use.name;
      if (observer == null || opened == null || at == null) return;
      final from = opened;
      final waited = events.waits.any((end) => end > from && end <= use.offset);
      if (!waited) return;
      final (shown, code) = observer;
      final where = deferred ? "'start()'" : 'the job is made';
      final arguments = [
        shown,
        where,
        // Only the corrections for `done` and `value` quote the code.
        if (code == OutcomeAfterAwait.doneCode ||
            code == OutcomeAfterAwait.valueCode)
          name,
      ];
      rule.reportAtNode(at, diagnosticCode: code, arguments: arguments);
      return;
    }
  }

  /// Whether [read] runs whenever the statement holding it does, and that
  /// statement stands in the block that holds [declaration]: nothing between
  /// them is a branch, a short-circuit, a null-aware call or the initializer
  /// of a late variable. Only the nodes listed here pass; any other keeps the
  /// rule quiet.
  static bool _runsSurely(AstNode read, Statement declaration) {
    var node = read;
    while (true) {
      final parent = node.parent;
      if (parent == null) return false;
      if (parent is Block) return parent == declaration.parent;
      final passes = switch (parent) {
        PrefixedIdentifier() ||
        ArgumentList() ||
        ParenthesizedExpression() ||
        AwaitExpression() ||
        PrefixExpression() ||
        InterpolationExpression() ||
        StringInterpolation() ||
        InstanceCreationExpression() ||
        ExpressionStatement() ||
        ReturnStatement() ||
        VariableDeclarationList() ||
        VariableDeclarationStatement() => true,
        PropertyAccess(:final target) => target == node,
        MethodInvocation(:final target) =>
          target == node || !_shortCircuits(parent),
        VariableDeclaration(parent: VariableDeclarationList(:final isLate)) =>
          !isLate,
        AssignmentExpression(:final rightHandSide, :final operator) =>
          rightHandSide != node ||
              operator.type != TokenType.QUESTION_QUESTION_EQ,
        BinaryExpression(:final rightOperand, :final operator) =>
          rightOperand != node || !_shortCircuiting.contains(operator.type),
        ConditionalExpression(:final condition) => condition == node,
        IfStatement(:final expression) => expression == node,
        // A named argument, whose node analyzer 12 and 14 name differently.
        _ => parent.parent is ArgumentList && argumentName(parent) != null,
      };
      if (!passes) return false;
      node = parent;
    }
  }

  /// The operators whose right operand might not run.
  static const _shortCircuiting = {
    TokenType.AMPERSAND_AMPERSAND,
    TokenType.BAR_BAR,
    TokenType.QUESTION_QUESTION,
  };

  /// Whether the arguments of [call] might not run: the call or a target
  /// before it in the chain is null-aware, or the call is a cascade section.
  static bool _shortCircuits(MethodInvocation call) {
    if (call.isCascaded) return true;
    Expression? link = call;
    while (true) {
      switch (link) {
        case MethodInvocation(:final isNullAware, :final target):
          if (isNullAware) return true;
          link = target;
        case PropertyAccess(:final isNullAware, :final target):
          if (isNullAware) return true;
          link = target;
        case IndexExpression(:final isNullAware, :final target):
          if (isNullAware) return true;
          link = target;
        default:
          return false;
      }
    }
  }

  /// Whether [value] makes a job: a call, not a read, a cascade or an
  /// `await`.
  static bool _isMade(Expression value) =>
      (value is InstanceCreationExpression ||
          value is MethodInvocation ||
          value is FunctionExpressionInvocation) &&
      isJob(value.staticType);

  /// Whether the job [value] makes runs only once it is started: a
  /// `ChildJob` of async_job, or the job of `Solo.job`.
  static bool _isDeferred(Expression value) =>
      isDeferredJob(value.staticType) ||
      (value is MethodInvocation &&
          isSoloMember(value.methodName.element, 'Solo', 'job'));
}

/// One reference to the job.
final class _Use {
  /// Where the reference starts.
  final int offset;

  /// Where the reference ends.
  final int end;

  /// The member read or called on the job, if the reference is a target.
  final String? member;

  /// The name of [member] in the code.
  final SimpleIdentifier? name;

  /// Whether the reference hands the job to code the rule does not follow.
  final bool escapes;

  /// The node that refers to the job.
  final AstNode reference;

  _Use(
    this.reference,
    this.offset,
    this.end, {
    this.member,
    this.name,
    this.escapes = false,
  });
}

/// The references to a job and the waits in the function that made it, in
/// the order of the source.
///
/// The function includes the actions of the waiting calls in it, which run
/// when the call is made; any other function in it runs on its own, so its
/// waits do not count and a reference to the job in it hands the job away.
class _Events extends RecursiveAstVisitor<void> {
  final Element job;

  /// Whether a `yield` waits for the listener: in an `async*` function.
  final bool yieldWaits;

  /// The ends of the waits: a suspension comes after the operand.
  final waits = <int>[];

  final uses = <_Use>[];

  var _inside = 0;

  _Events(this.job, this.yieldWaits);

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (waitingContext(node) != null) {
      super.visitFunctionExpression(node);
      return;
    }
    _inside++;
    super.visitFunctionExpression(node);
    _inside--;
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    if (_inside > 0 || _cancelsTheJob(node.expression)) return;
    waits.add(node.end);
  }

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null && _inside == 0) {
      waits.add(node.forLoopParts.end);
    }
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    if (node.awaitKeyword != null && _inside == 0) {
      waits.add(node.forLoopParts.end);
    }
    super.visitForElement(node);
  }

  @override
  void visitYieldStatement(YieldStatement node) {
    super.visitYieldStatement(node);
    if (yieldWaits && _inside == 0) waits.add(node.end);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final target = node.leftHandSide;
    if (target is SimpleIdentifier && node.writeElement == job) {
      uses.add(_Use(target, target.offset, target.end, escapes: true));
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element != job) return;
    if (_inside > 0) {
      uses.add(_Use(node, node.offset, node.end, escapes: true));
      return;
    }
    final name = _memberOn(node);
    uses.add(
      name == null
          ? _Use(node, node.offset, node.end, escapes: true)
          : _Use(node, node.offset, name.end, member: name.name, name: name),
    );
  }

  /// Whether [operand] is `cancel()` of the job itself: its future ends
  /// before the failure is answered for, so it does not open the gap.
  bool _cancelsTheJob(Expression operand) {
    final call = operand.unParenthesized;
    if (call is! MethodInvocation || call.methodName.name != 'cancel') {
      return false;
    }
    final target = call.target;
    return target is SimpleIdentifier && target.element == job;
  }

  /// The name of the member read or called on [node], if [node] is the
  /// target.
  static SimpleIdentifier? _memberOn(SimpleIdentifier node) =>
      switch (node.parent) {
        PrefixedIdentifier(:final prefix, :final identifier)
            when prefix == node =>
          identifier,
        PropertyAccess(:final target, :final propertyName)
            when target == node =>
          propertyName,
        MethodInvocation(:final target, :final methodName)
            when target == node =>
          methodName,
        _ => null,
      };
}
