import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../context.dart';

/// Reports a `Policy.droppable` job whose key is the same for every call
/// while its body reads the arguments of the call.
class KeyPerRequest extends AnalysisRule {
  /// The diagnostic this rule reports.
  static const LintCode code = LintCode(
    'key_per_request',
    "'{0}' is one key for every call: Policy.droppable hands a later caller "
        'the result of the first.',
    correctionMessage: 'Put the arguments the body reads into the key.',
  );

  /// Creates the rule.
  KeyPerRequest()
    : super(
        name: 'key_per_request',
        description:
            'Policy.droppable compares keys, not arguments: a key that '
            'ignores them gives a later caller the result of the first.',
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
    final shared = sharedKey(node);
    if (shared == null) return;
    rule.reportAtNode(shared.key, arguments: [shared.key.toSource()]);
  }
}

/// The key of [call], an `enqueue` or `enqueueJob` of `Solo`, and the
/// parameters of the enclosing function that its body reads, in declaration
/// order; `null` unless the call is a `Policy.droppable` job whose key names
/// none of the parameters while its body reads at least one.
///
/// For `enqueueJob(job(key: K, body), policy: ...)` the key and the body are
/// those of the inner `job` call.
({Expression key, List<FormalParameterElement> read})? sharedKey(
  MethodInvocation call,
) {
  final name = call.methodName.name;
  if (name != 'enqueue' && name != 'enqueueJob') return null;
  if (!isSoloMember(call.methodName.element, 'Solo', name)) return null;
  final arguments = call.argumentList;
  final policy = namedValue(arguments, 'policy');
  if (policy == null || !_isDroppable(policy)) return null;

  var made = call;
  if (name == 'enqueueJob') {
    final job = firstPositional(arguments)?.unParenthesized;
    if (job is! MethodInvocation ||
        !isSoloMember(job.methodName.element, 'Solo', 'job')) {
      return null;
    }
    made = job;
  }
  final key = namedValue(made.argumentList, 'key');
  final bodyArgument = firstPositional(made.argumentList);
  if (key == null || bodyArgument == null) return null;
  final body = functionOf(bodyArgument);
  if (body == null) return null;

  // The rule does not follow a variable to its value: a key built in a local
  // may well hold the parameters, so it stays silent. A parameter of a
  // closure around the call is new on every call of the closure, so it
  // counts as a local.
  final parameters = _parametersAround(call);
  if (_readsLocal(key, parameters)) return null;
  if (_referenced(key, parameters).isNotEmpty) return null;
  final read = _referenced(body, parameters);
  if (read.isEmpty) return null;
  return (
    key: key,
    read: [
      for (final p in parameters)
        if (read.contains(p)) p,
    ],
  );
}

bool _isDroppable(Expression policy) {
  final node = policy.unParenthesized;
  final element = switch (node) {
    PrefixedIdentifier() => node.identifier.element,
    PropertyAccess() => node.propertyName.element,
    DotShorthandPropertyAccess() => node.propertyName.element,
    _ => null,
  };
  return isSoloMember(element, 'Policy', 'droppable');
}

/// The parameters of the nearest method or function declaration around
/// [node], in declaration order.
List<FormalParameterElement> _parametersAround(AstNode node) {
  for (var at = node.parent; at != null; at = at.parent) {
    // A getter has no parameter list, hence no parameters.
    final FormalParameterList? list;
    switch (at) {
      case MethodDeclaration():
        list = at.parameters;
      case FunctionDeclaration():
        list = at.functionExpression.parameters;
      default:
        continue;
    }
    return [
      for (final p in list?.parameters ?? const <FormalParameter>[])
        ?p.declaredFragment?.element,
    ];
  }
  return const [];
}

bool _readsLocal(AstNode node, List<FormalParameterElement> parameters) {
  final finder = _LocalFinder(parameters.toSet());
  node.accept(finder);
  return finder.found;
}

class _LocalFinder extends RecursiveAstVisitor<void> {
  final Set<Element> parameters;

  bool found = false;

  _LocalFinder(this.parameters);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is LocalVariableElement ||
        element is FormalParameterElement && !parameters.contains(element)) {
      found = true;
    }
  }
}

/// The elements of [parameters] that a simple identifier in [node] names.
Set<Element> _referenced(
  AstNode node,
  List<FormalParameterElement> parameters,
) {
  final finder = _ReferenceFinder(parameters.toSet());
  node.accept(finder);
  return finder.found;
}

class _ReferenceFinder extends RecursiveAstVisitor<void> {
  final Set<Element> wanted;
  final Set<Element> found = {};

  _ReferenceFinder(this.wanted);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null && wanted.contains(element)) found.add(element);
  }
}
