import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:async_job_lints/plugin_api.dart';

/// Reports a job of a controller that waits for a job of the same
/// controller's queue or of the lane the job runs in, or for its `close` or
/// `cancelAll`.
class AwaitOwnQueue extends MultiAnalysisRule {
  /// The diagnostic for a wait for the queue of a `Solo`, and for `close`
  /// or `cancelAll` of any controller.
  static const LintCode code = LintCode(
    'await_own_queue',
    "'{0}' waits for the running job, and the running job waits for '{0}'.",
    correctionMessage:
        "Run the job with 'ctx.run' instead of the queue; don't wait for "
        "'close' or 'cancelAll' from a job.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// The diagnostic for a wait for the lane of a `SoloLanes` the job runs
  /// in.
  static const LintCode laneCode = LintCode(
    'await_own_queue',
    "'{0}' waits for the running job of the lane '{1}', and the running job "
        "waits for '{0}'.",
    correctionMessage:
        "Run the job with 'ctx.run' instead of the lane, or queue it in "
        'another lane.',
    severity: DiagnosticSeverity.WARNING,
    uniqueName: 'LintCode.await_own_queue_lane',
  );

  /// Creates the rule.
  AwaitOwnQueue()
    : super(
        name: 'await_own_queue',
        description:
            "A job that waits for its own controller's queue or lane waits "
            'for itself.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [code, laneCode];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addAwaitExpression(this, visitor)
      ..addFunctionExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AwaitOwnQueue rule;

  _Visitor(this.rule);

  @override
  void visitAwaitExpression(AwaitExpression node) => _check(node.expression);

  /// A job body and the action of a waiting call are waited for through what
  /// they return.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (waitingContext(node) == null &&
        !isSoloContext(jobContextOf(node)?.type)) {
      return;
    }
    returnedValues(node.body).forEach(_check);
  }

  void _check(Expression waited) {
    final node = waited.unParenthesized;
    if (queueLaneOf(node) != QueueLane.own) return;
    final call = _waitedCall(node);
    final body = _queuedBody(waited);
    if (call == null || body == null) return;
    final around = waited.thisOrAncestorMatching(
      (node) => node is ClassDeclaration || node is MixinDeclaration,
    );
    final owner = switch (around) {
      ClassDeclaration(:final declaredFragment) => declaredFragment?.element,
      MixinDeclaration(:final declaredFragment) => declaredFragment?.element,
      _ => null,
    };
    // Solo before 2.0 has no SoloController.
    final type = owner?.thisType;
    if (!isSolo(type) && !isSoloController(type)) return;
    final name = call.methodName.name;
    final lane = body.lane;
    // close and cancelAll wait for every lane, not only for this one.
    if (lane == null || node is! PropertyAccess) {
      rule.reportAtNode(
        call,
        diagnosticCode: AwaitOwnQueue.code,
        arguments: [name],
      );
    } else {
      rule.reportAtNode(
        call,
        diagnosticCode: AwaitOwnQueue.laneCode,
        arguments: [name, lane.displayName],
      );
    }
  }

  /// The call [waited] waits for: the target of `.value` or `.done`, or
  /// `close()` or `cancelAll()` itself.
  static MethodInvocation? _waitedCall(Expression waited) {
    if (waited is MethodInvocation) return waited;
    if (waited is! PropertyAccess) return null;
    final target = waited.realTarget.unParenthesized;
    return target is MethodInvocation ? target : null;
  }

  /// The context of the job body that waits for [node] when that is a body
  /// of a `SoloContext` queued on this controller, and the lane field it is
  /// queued in when it is given to one: [node] is in the body itself, in the
  /// actions of waiting calls on its context or in its cleanup, which the
  /// queue waits for as well.
  static ({Element ctx, Element? lane})? _queuedBody(AstNode node) {
    final crossed = <Element>[];
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is! FunctionExpression) continue;
      final ctx = jobContextOf(at);
      if (ctx != null) {
        if (!isSoloContext(ctx.type)) return null;
        if (!crossed.every((c) => c == ctx)) return null;
        final (:here, :lane) = _queuedHere(at);
        return here ? (ctx: ctx, lane: lane) : null;
      }
      final through = waitingContext(at) ?? cleanupContext(at);
      if (through == null) return null;
      crossed.add(through);
    }
    return null;
  }

  /// Whether [body] is given to a call on this controller, on one of its
  /// lanes or on a context, rather than to another controller's `enqueue`,
  /// and the lane field when it is given to a lane.
  static ({bool here, Element? lane}) _queuedHere(FunctionExpression body) {
    final parent = body.parent;
    final list = parent is ArgumentList ? parent : parent?.parent;
    final call = list?.parent;
    if (list is! ArgumentList || call is! MethodInvocation) {
      return (here: true, lane: null);
    }
    final target = call.realTarget;
    if (target == null ||
        target is ThisExpression ||
        isJobContext(target.staticType)) {
      return (here: true, lane: null);
    }
    final lane = _laneField(target);
    return (here: lane != null, lane: lane);
  }

  /// The lane field of this controller that [target] reads, `_likes` or
  /// `this._likes`: an instance field typed `SoloLane`.
  static Element? _laneField(Expression target) {
    final node = target.unParenthesized;
    final read = switch (node) {
      SimpleIdentifier() => node.element,
      PropertyAccess(target: ThisExpression()) => node.propertyName.element,
      _ => null,
    };
    final field = read is GetterElement ? read.variable : read;
    if (field is! FieldElement || field.isStatic) return null;
    return isSoloLane(field.type) ? field.baseElement : null;
  }
}
