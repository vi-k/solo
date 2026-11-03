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
    final visitor = _Visitor(this);
    registry
      ..addBlock(this, visitor)
      ..addSwitchCase(this, visitor)
      ..addSwitchDefault(this, visitor)
      ..addSwitchPatternCase(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;

  _Visitor(this.rule);

  @override
  void visitBlock(Block node) => _scan(statementsOf(node));

  @override
  void visitSwitchCase(SwitchCase node) => _scan(statementsOf(node));

  @override
  void visitSwitchDefault(SwitchDefault node) => _scan(statementsOf(node));

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) =>
      _scan(statementsOf(node));

  void _scan(List<Statement>? statements) {
    if (statements == null) return;
    for (var i = 0; i + 1 < statements.length; i++) {
      final brought = broughtBy(statements[i]);
      if (brought == null) continue;
      final (:variable, :ctx, call: _) = brought;
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

  static bool _mentions(Expression expression, Element variable) {
    final finder = _Mention(variable);
    expression.accept(finder);
    return finder.found;
  }
}

/// The statements [node] holds when it is a block or a switch member,
/// otherwise `null`.
List<Statement>? statementsOf(AstNode? node) => switch (node) {
  Block() => node.statements,
  SwitchCase() => node.statements,
  SwitchDefault() => node.statements,
  SwitchPatternCase() => node.statements,
  _ => null,
};

/// The call [statement] awaits, the variable it declares and the context of
/// that call, when [statement] is `final x = await ctx.join(...)` with no
/// release of its own.
({MethodInvocation call, Element variable, Element ctx})? broughtBy(
  Statement statement,
) {
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
  return variable == null ? null : (call: call, variable: variable, ctx: ctx);
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
