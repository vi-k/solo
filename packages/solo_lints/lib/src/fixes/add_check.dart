import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
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
    final block = _clause?.body;
    final ctx = _context;
    if (block == null || ctx == null) return;
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

  /// Whether [offset] is on the line of [open].
  bool _onLineOf(Token open, int offset) {
    final lines = unitResult.lineInfo;
    return lines.getLocation(open.offset).lineNumber ==
        lines.getLocation(offset).lineNumber;
  }
}
