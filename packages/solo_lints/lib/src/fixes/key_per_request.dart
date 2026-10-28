import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../context.dart';
import '../rules/key_per_request.dart';

/// Puts the parameters that the body of a job reads into the key reported by
/// `key_per_request`: `key` becomes the record `(key, id, page)`.
class PutArgumentsIntoKey extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'solo_lints.fix.putArgumentsIntoKey',
    50,
    'Put the arguments the body reads into the key',
  );

  static const _comparable = ['String', 'int', 'double', 'num', 'bool'];

  /// Creates the fix in [context].
  PutArgumentsIntoKey({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // The diagnostic sits on the key; the call it belongs to is the first
    // ancestor for which `sharedKey` names this node as the key (for
    // `enqueueJob` the nearest invocation is the inner `job`, which it
    // does not answer for).
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is! MethodInvocation) continue;
      final shared = sharedKey(at);
      if (shared == null || !identical(shared.key, node)) continue;
      if (!shared.read.every(_isComparable)) return;
      final names = shared.read.map((p) => p.displayName).join(', ');
      final key = shared.key;
      await builder.addDartFileEdit(file, (builder) {
        builder.addSimpleReplacement(
          range.node(key),
          '(${utils.getNodeText(key)}, $names)',
        );
      });
      return;
    }
  }

  /// Whether a key may hold the argument for [parameter]: a number, a
  /// string, a bool or an enum, nullable or not, all compared by value.
  static bool _isComparable(FormalParameterElement parameter) {
    final type = parameter.type;
    if (type is! InterfaceType) return false;
    final element = type.element;
    return element is EnumElement ||
        _comparable.any((name) => isDartCoreClass(element, name));
  }
}
