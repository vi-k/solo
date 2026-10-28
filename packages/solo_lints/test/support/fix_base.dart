import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:test/test.dart';

import 'rule_base.dart';

/// A test of one quick fix: the rule reports a diagnostic, and the fix for it
/// turns the code into the expected text.
///
/// The fix context is built from the public API only, as the analysis server
/// builds it: the resolved library of the test file, the diagnostic and its
/// range as the selection.
abstract class FixTest extends RuleTest {
  /// The generator of the fix under test.
  ResolvedCorrectionProducer Function({
    required CorrectionProducerContext context,
  })
  get producer;

  /// Asserts that the rule reports [code] exactly at [span], in the form of
  /// [assertAt], that the fix for that diagnostic turns [code] into
  /// [expected], and that [expected] has no diagnostics at all: the fix
  /// silences the rule and leaves code that compiles.
  ///
  /// With [arguments], the fix is also expected to offer itself with them.
  Future<void> assertFix(
    String code,
    String span,
    String expected, {
    List<String>? arguments,
  }) async {
    final (:change, :fix) = await _fix(code, span);
    expect(change.edits, hasLength(1), reason: 'one file is edited');
    final edit = change.edits.single;
    expect(edit.file, result.path);
    expect(SourceEdit.applySequence(code, edit.edits), expected);
    if (arguments != null) expect(fix.fixArguments, arguments);
    // The analysis context caches the file, and assertDiagnostics only
    // writes it: without the change the old code is analyzed again.
    final analysis = result.session.analysisContext;
    result.session.resourceProvider
        .getFile(result.path)
        .writeAsStringSync(expected);
    analysis.changeFile(result.path);
    await analysis.applyPendingFileChanges();
    await assertDiagnostics(expected, const []);
  }

  /// Asserts that the rule reports [code] exactly at [span], in the form of
  /// [assertAt], and that the fix for that diagnostic builds no edits.
  Future<void> assertNoFix(String code, String span) async {
    final (:change, fix: _) = await _fix(code, span);
    expect(change.edits, isEmpty);
  }

  Future<({SourceChange change, ResolvedCorrectionProducer fix})> _fix(
    String code,
    String span,
  ) async {
    await assertAt(code, [span]);
    final diagnostic = result.diagnostics.singleWhere(
      (d) => rule.diagnosticCodes.contains(d.diagnosticCode),
    );
    final library = await result.session.getResolvedLibrary(result.path);
    if (library is! ResolvedLibraryResult) {
      throw StateError('${result.path} is not resolved: $library');
    }
    final context = CorrectionProducerContext.createResolved(
      libraryResult: library,
      unitResult: library.unitWithPath(result.path)!,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    );
    final builder = ChangeBuilder(session: result.session);
    final fix = producer(context: context);
    await fix.compute(builder);
    return (change: builder.sourceChange, fix: fix);
  }
}
