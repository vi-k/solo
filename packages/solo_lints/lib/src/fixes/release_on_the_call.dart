import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../context.dart';
import '../rules/release_on_the_call.dart';

/// Moves a release reported by `release_on_the_call` into `dispose:` or
/// `discard:` of the call that brings the resource.
class PassReleaseToCall extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'solo_lints.fix.passReleaseToCall',
    50,
    "Pass the release as '{0}:' of the call",
  );

  /// Creates the fix in [context].
  PassReleaseToCall({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  List<String>? get fixArguments {
    final release = _release;
    return release == null ? null : [_label(release)];
  }

  @override
  FixKind get fixKind => _kind;

  ExpressionStatement? get _statement =>
      node.thisOrAncestorOfType<ExpressionStatement>();

  MethodInvocation? get _release {
    final release = _statement?.expression.unParenthesized;
    return release is MethodInvocation ? release : null;
  }

  static String _label(MethodInvocation release) =>
      release.methodName.name == 'onDispose' ? 'dispose' : 'discard';

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final statement = _statement;
    final release = _release;
    if (statement == null || release == null) return;
    final statements = statementsOf(statement.parent);
    final at = statements?.indexOf(statement) ?? -1;
    if (statements == null || at < 1) return;
    final brought = broughtBy(statements[at - 1]);
    if (brought == null) return;
    // The release reads the last value of a variable assigned again, while
    // `dispose:` would get the first.
    final variable = brought.variable;
    if (variable is! VariableElement ||
        !variable.isFinal && _assigned(statement.parent!, variable)) {
      return;
    }
    final name = brought.variable.displayName;
    final released = firstPositional(release.argumentList);
    if (released == null) return;
    final function = _closure(released, name);
    if (function == null) return;
    final arguments = brought.call.argumentList;
    if (arguments.arguments.isEmpty) return;
    final last = arguments.arguments.last;
    final comma = last.endToken.next;
    final trailing = comma != null && comma.type == TokenType.COMMA;
    final argument = '${_label(release)}: $function';
    await builder.addDartFileEdit(file, (builder) {
      if (trailing) {
        // After the comma, on a line of its own when the last argument has
        // one.
        final lines = unitResult.lineInfo;
        final own =
            lines.getLocation(last.offset).lineNumber !=
            lines.getLocation(arguments.leftParenthesis.offset).lineNumber;
        final separator = own
            ? '${utils.endOfLine}${utils.getLinePrefix(last.offset)}'
            : ' ';
        builder.addSimpleInsertion(comma.end, '$separator$argument,');
      } else {
        builder.addSimpleInsertion(last.end, ', $argument');
      }
      builder.addDeletion(utils.getLinesRange(range.node(statement)));
    });
  }

  /// Whether [node] assigns [variable] anywhere.
  static bool _assigned(AstNode node, Element variable) {
    final finder = _Assignment(variable);
    node.accept(finder);
    return finder.found;
  }

  /// The function to pass for [released], with the parameter [name], or
  /// `null` when [released] is in a form this fix does not handle: only a
  /// tear-off of a method of the variable and a literal without parameters
  /// are.
  String? _closure(Expression released, String name) {
    if (released is PrefixedIdentifier && released.prefix.name == name) {
      return '($name) => $name.${released.identifier.name}()';
    }
    final parameters = released is FunctionExpression
        ? released.parameters
        : null;
    if (released is FunctionExpression &&
        released.typeParameters == null &&
        parameters != null &&
        parameters.parameters.isEmpty) {
      final text = utils.getNodeText(released);
      final open = parameters.leftParenthesis.end - released.offset;
      return '${text.substring(0, open)}$name${text.substring(open)}';
    }
    return null;
  }
}

class _Assignment extends RecursiveAstVisitor<void> {
  final Element variable;

  bool found = false;

  _Assignment(this.variable);

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (node.element == variable) found = true;
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.writeElement == variable) found = true;
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.writeElement == variable) found = true;
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.writeElement == variable) found = true;
    super.visitPrefixExpression(node);
  }
}
