import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../context.dart';

/// Makes `ctx.check();` the first line of a catch reported by
/// `catch_without_check`, with `ctx` the context of the job body.
class AddCheck extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'solo_lints.fix.addCheck',
    50,
    "Add '{0}.check();' as the first line of the catch",
  );

  /// Creates the fix in [context].
  AddCheck({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  List<String>? get fixArguments {
    final ctx = _context;
    return ctx == null ? null : [ctx.displayName];
  }

  @override
  FixKind get fixKind => _kind;

  CatchClause? get _clause => node.thisOrAncestorOfType<CatchClause>();

  Element? get _context {
    final clause = _clause;
    return clause == null ? null : bodyContextAround(clause);
  }

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final clause = _clause;
    final ctx = _context;
    if (clause == null || ctx == null) return;
    // At the top of the block the name may stand for something else.
    if (_namesIn(clause).contains(ctx.displayName)) return;
    final block = clause.body;
    final open = block.leftBracket;
    final statements = block.statements;
    final eol = utils.endOfLine;
    // The indent of the first statement when it has a line of its own, and
    // one level deeper than the line of the brace otherwise.
    final indent =
        statements.isNotEmpty && !_onLineOf(open, statements.first.offset)
        ? utils.getLinePrefix(statements.first.offset)
        : utils.getLinePrefix(open.offset) + utils.oneIndent;
    // `{}` opens up, so the brace that closes it gets a line of its own.
    final close =
        statements.isEmpty && _onLineOf(open, block.rightBracket.offset)
        ? '$eol${utils.getLinePrefix(open.offset)}'
        : '';
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(
        open.end,
        '$eol$indent${ctx.displayName}.check();$close',
      );
    });
  }

  /// The names [clause] declares where the check goes: its parameters and
  /// the declarations directly in its block.
  static Set<String> _namesIn(CatchClause clause) {
    final names = {
      ?clause.exceptionParameter?.name.lexeme,
      ?clause.stackTraceParameter?.name.lexeme,
    };
    for (final statement in clause.body.statements) {
      switch (statement) {
        case VariableDeclarationStatement(:final variables):
          names.addAll(variables.variables.map((v) => v.name.lexeme));
        case FunctionDeclarationStatement(:final functionDeclaration):
          names.add(functionDeclaration.name.lexeme);
        case PatternVariableDeclarationStatement(:final declaration):
          final finder = _PatternNames();
          declaration.pattern.accept(finder);
          names.addAll(finder.names);
        default:
      }
    }
    return names;
  }

  /// Whether [offset] is on the line of [open].
  bool _onLineOf(Token open, int offset) {
    final lines = unitResult.lineInfo;
    return lines.getLocation(open.offset).lineNumber ==
        lines.getLocation(offset).lineNumber;
  }
}

/// Collects the names of the variables a pattern declares.
class _PatternNames extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    names.add(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }
}
