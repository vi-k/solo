import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports an `async` callback of `fakeAsync` or `FakeAsync.run`.
class SyncFakeAsync extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'sync_fake_async',
    "An 'await' in this callback leaves nobody to move the fake clock.",
    correctionMessage:
        "Make the callback synchronous: move the clock with 'elapse' and read "
        "'job.outcome'.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  SyncFakeAsync()
    : super(
        name: 'sync_fake_async',
        description:
            'The callback of fakeAsync has to stay synchronous: the test '
            'hangs or ends green with nothing run.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_isFakeAsync(node.methodName.element)) return;
    final callback = firstPositional(node.argumentList)?.unParenthesized;
    if (callback is! FunctionExpression) return;
    final keyword = callback.body.keyword;
    if (callback.body.isAsynchronous && keyword != null) {
      rule.reportAtToken(keyword);
    }
  }

  /// Whether [element] is `fakeAsync` or `FakeAsync.run` of fake_async.
  static bool _isFakeAsync(Element? element) {
    if (element == null) return false;
    final uri = element.library?.uri.toString() ?? '';
    if (!uri.startsWith('package:fake_async/')) return false;
    if (element is TopLevelFunctionElement) return element.name == 'fakeAsync';
    final owner = element.enclosingElement;
    return element is MethodElement &&
        element.name == 'run' &&
        owner is InterfaceElement &&
        owner.name == 'FakeAsync';
  }
}
