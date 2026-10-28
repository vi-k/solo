import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports a release registered on the line under the call that brings the
/// resource.
class ReleaseOnTheCall extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'release_on_the_call',
    "'{0}' is lost if a cancellation comes before this line.",
    correctionMessage:
        "Pass the release as '{1}:' of the call that brings '{0}'.",
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  ReleaseOnTheCall()
    : super(
        name: 'release_on_the_call',
        description:
            'A resource registered for release after the call that brings it '
            'is lost to a cancellation in between.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addBlock(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitBlock(Block node) {
    final statements = node.statements;
    for (var i = 0; i + 1 < statements.length; i++) {
      final call = _broughtBy(statements[i]);
      if (call == null) continue;
      final (variable, ctx) = call;
      final next = statements[i + 1];
      if (next is! ExpressionStatement) continue;
      final release = next.expression.unParenthesized;
      if (release is! MethodInvocation) continue;
      if (!callsOn(release, ctx, const {'onDispose', 'onDiscard'})) continue;
      final released = firstPositional(release.argumentList);
      if (released == null || !_mentions(released, variable)) continue;
      final label = release.methodName.name == 'onDispose'
          ? 'dispose'
          : 'discard';
      rule.reportAtNode(release, arguments: [variable.displayName, label]);
    }
  }

  /// The variable [statement] declares and the context of the call it
  /// awaits, when [statement] is `final x = await ctx.join(...)` with no
  /// release of its own.
  (Element, Element)? _broughtBy(Statement statement) {
    if (statement is! VariableDeclarationStatement) return null;
    final variables = statement.variables.variables;
    if (variables.length != 1) return null;
    final declaration = variables.single;
    final initializer = declaration.initializer?.unParenthesized;
    if (initializer is! AwaitExpression) return null;
    final call = initializer.expression.unParenthesized;
    if (call is! MethodInvocation) return null;
    final ctx = contextNamed(call.realTarget);
    if (ctx == null || !callsOn(call, ctx, releasingCalls)) return null;
    final arguments = call.argumentList;
    if (namedValue(arguments, 'dispose') != null ||
        namedValue(arguments, 'discard') != null) {
      return null;
    }
    final variable = declaration.declaredFragment?.element;
    return variable == null ? null : (variable, ctx);
  }

  static bool _mentions(Expression expression, Element variable) {
    final finder = _Mention(variable);
    expression.accept(finder);
    return finder.found;
  }
}

class _Mention extends RecursiveAstVisitor<void> {
  final Element variable;

  bool found = false;

  _Mention(this.variable);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == variable) found = true;
  }
}
