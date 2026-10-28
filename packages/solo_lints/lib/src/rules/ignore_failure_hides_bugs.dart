import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports `ignoreFailure()` on a job that names its expected errors with
/// `isExpectedError`, when nothing else takes the job.
class IgnoreFailureHidesBugs extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'ignore_failure_hides_bugs',
    "'ignoreFailure()' also hides the bugs that '{0}' lets through.",
    correctionMessage:
        "Drop 'ignoreFailure()': isExpectedError already keeps the expected "
        'errors quiet.',
  );

  /// Creates the rule.
  IgnoreFailureHidesBugs()
    : super(
        name: 'ignore_failure_hides_bugs',
        description:
            'isExpectedError already keeps the expected errors of a job '
            'quiet: ignoreFailure() on it silences the bugs as well.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'ignoreFailure' ||
        !isFromJobPackages(node.methodName.element)) {
      return;
    }
    final job = node.realTarget;
    if (job == null) return;
    // `ignoreFailure()` returns void, so after `E.ignoreFailure()` the caller
    // has no job left; a cascade hands the job on unless its value is thrown
    // away.
    if (node.isCascaded && !_dropped(node.parent! as CascadeExpression)) {
      return;
    }
    final owner = _Reduction(context).ownerOf(job);
    if (owner == null) return;
    rule.reportAtNode(node.methodName, arguments: ["$owner's isExpectedError"]);
  }
}

/// Whether the value of [cascade] is thrown away: it is a statement or the
/// `=>` body of a function returning `void`.
bool _dropped(CascadeExpression cascade) {
  final parent = cascade.parent;
  if (parent is ExpressionStatement) return true;
  if (parent is! ExpressionFunctionBody) return false;
  final function = parent.parent;
  final type = switch (function) {
    MethodDeclaration() => function.declaredFragment?.element.returnType,
    FunctionExpression(parent: final FunctionDeclaration declaration) =>
      declaration.declaredFragment?.element.returnType,
    // A literal's return type is inferred as void when the type it is passed
    // as or assigned to returns void, and from its body otherwise.
    FunctionExpression(:final staticType) =>
      staticType is FunctionType ? staticType.returnType : null,
    _ => null,
  };
  return type is VoidType;
}

/// Follows the expression of a job to the call that makes it, within the
/// library under analysis.
class _Reduction {
  final RuleContext context;

  /// The methods and functions this reduction has gone through, against
  /// recursion.
  final Set<Element> _seen = {};

  _Reduction(this.context);

  /// The name for the predicate of [job]: the method or function nearest to
  /// [job] the reduction goes through, otherwise the call that takes
  /// `isExpectedError` or the field of the accumulator; `null` when [job]
  /// does not reduce to a job with `isExpectedError`.
  String? ownerOf(Expression job) {
    final node = job.unParenthesized;
    if (node is! MethodInvocation) return null;
    final element = node.methodName.element;
    final name = node.methodName.name;
    if (isSoloMember(element, 'Solo', 'job') ||
        isSoloMember(element, 'Solo', 'enqueue')) {
      return _names(node) ? name : null;
    }
    if (isSoloMember(element, 'Solo', 'enqueueJob')) {
      // With Policy.droppable the call may hand back a job already running
      // under the key, but the same key almost always comes from the same
      // method, so the argument stands for it.
      final argument = firstPositional(node.argumentList);
      return argument == null ? null : ownerOf(argument);
    }
    if (isSoloMember(element, 'SoloAccumulator', 'add')) {
      return _accumulator(node.realTarget);
    }
    if (element is! MethodElement &&
        element is! TopLevelFunctionElement &&
        element is! LocalFunctionElement) {
      return null;
    }
    final base = element!.baseElement;
    if (!_seen.add(base)) return null;
    final returned = switch (_declarationOf(base)) {
      MethodDeclaration(:final body) => _returnedBy(body),
      FunctionDeclaration(:final functionExpression) => _returnedBy(
        functionExpression.body,
      ),
      _ => null,
    };
    if (returned == null || ownerOf(returned) == null) return null;
    return base.name;
  }

  /// The name of the field [target] reads, when it is a final field of this
  /// class holding a `collect` or `accumulate` with `isExpectedError`.
  String? _accumulator(Expression? target) {
    final node = target?.unParenthesized;
    final read = switch (node) {
      SimpleIdentifier() => node.element,
      PropertyAccess(target: ThisExpression()) => node.propertyName.element,
      _ => null,
    };
    final field = read is GetterElement ? read.variable : read;
    if (field is! FieldElement || !field.isFinal) return null;
    final declaration = _declarationOf(field.baseElement);
    if (declaration is! VariableDeclaration) return null;
    final value = declaration.initializer?.unParenthesized;
    if (value is! MethodInvocation) return null;
    final made = value.methodName.element;
    if (!isSoloMember(made, 'Solo', 'collect') &&
        !isSoloMember(made, 'Solo', 'accumulate')) {
      return null;
    }
    return _names(value) ? field.name : null;
  }

  /// The declaration of [element] in the library under analysis, if it is
  /// there: the analyzer gives a rule no bodies of other libraries.
  AstNode? _declarationOf(Element element) {
    final finder = _DeclarationFinder(element);
    for (final unit in context.allUnits) {
      unit.unit.accept(finder);
      if (finder.found != null) return finder.found;
    }
    return null;
  }
}

/// Whether [call] names the expected errors.
bool _names(MethodInvocation call) =>
    namedValue(call.argumentList, 'isExpectedError') != null;

/// The expression [body] returns when that is all it does: a `=>` body or a
/// block of one `return`.
Expression? _returnedBy(FunctionBody body) => switch (body) {
  ExpressionFunctionBody(:final expression) => expression,
  BlockFunctionBody(
    block: Block(statements: [ReturnStatement(:final expression)]),
  ) =>
    expression,
  _ => null,
};

class _DeclarationFinder extends RecursiveAstVisitor<void> {
  final Element element;

  AstNode? found;

  _DeclarationFinder(this.element);

  void _check(AstNode node, Fragment? fragment) {
    if (fragment?.element == element) found = node;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(node, node.declaredFragment);
    if (found == null) super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _check(node, node.declaredFragment);
    if (found == null) super.visitMethodDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _check(node, node.declaredFragment);
    if (found == null) super.visitVariableDeclaration(node);
  }
}
