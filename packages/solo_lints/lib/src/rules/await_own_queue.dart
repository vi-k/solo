import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
    // The same body that bare_await and discarded_outcome ask about before
    // they leave the wait to this rule.
    final call = queueCallOf(node);
    final body = queuedBodyOf(node);
    if (call == null || body == null) return;
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
}
