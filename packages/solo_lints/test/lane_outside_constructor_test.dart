// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/lane_outside_constructor.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(LaneOutsideConstructorTest);
  });
}

@reflectiveTest
class LaneOutsideConstructorTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => LaneOutsideConstructor();

  Future<void> test_constructor_body() => assertAt('''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _reload = lane('reload');
    this._likes = this.lane('likes');
  }

  late final SoloLane<int> _reload;
  late final SoloLane<int> _likes;
}

final class Station extends Feed {
  Station() {
    _gate = lane('gate');
    _exit = super.lane('exit');
  }

  late final SoloLane<int> _gate;
  late final SoloLane<int> _exit;
}
''', []);

  // A closure in the constructor body may run later, so the rule takes it
  // as outside, though map runs it at once; a collection for is the body
  // itself.
  Future<void> test_lanes_from_a_list_of_names() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed(List<String> names) : super(0) {
    _mapped = names.map((name) => lane(name)).toList();
    _listed = [for (final name in names) lane(name)];
  }

  late final List<SoloLane<int>> _mapped;
  late final List<SoloLane<int>> _listed;
}
''',
    ['lane(name)'],
  );

  // "Declaring lanes" on the lanes page of solo: the first read of the field
  // comes after the constructor.
  Future<void> test_late_final_initializer() {
    const code = '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0);

  late final _reload = lane('reload');
}
''';
    const span = "lane('reload')";
    return assertDiagnostics(code, [
      lint(
        code.indexOf(span),
        span.length,
        messageContainsAll: ["'lane' outside the constructor body throws"],
      ),
    ]);
  }

  Future<void> test_method_and_function_in_the_constructor() => assertAt(
    '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    scheduleMicrotask(() => _likes = lane('likes'));
  }

  late final SoloLane<int> _likes;
  late final SoloLane<int> _reload;

  void declare() {
    _reload = lane('reload');
  }
}

void scheduleMicrotask(void Function() callback) {}
''',
    ["lane('likes')", "lane('reload')"],
  );

  Future<void> test_mixin_on_lanes() => assertAt(
    '''
import 'package:solo/solo.dart';

mixin Audit on SoloLanes<int> {
  late final SoloLane<int> audit = lane('audit');
}
''',
    ["lane('audit')"],
  );

  Future<void> test_pool_in_constructor_body() => assertAt('''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0) {
    _likes = pool('likes', concurrency: 4);
    this._saves = super.pool('saves', concurrency: 2);
  }

  late final SoloPool<int> _likes;
  late final SoloPool<int> _saves;
}
''', []);

  // A pool is sealed with the lanes, and its message names the pool.
  Future<void> test_pool_in_late_final_initializer() {
    const code = '''
import 'package:solo/solo.dart';

final class Feed extends SoloLanes<int> {
  Feed() : super(0);

  late final _likes = pool('likes', concurrency: 4);
}
''';
    const span = "pool('likes', concurrency: 4)";
    return assertDiagnostics(code, [
      lint(
        code.indexOf(span),
        span.length,
        messageContainsAll: [
          "'pool' outside the constructor body throws",
          'its set of lanes and pools',
        ],
      ),
    ]);
  }

  // Only pool of SoloLanes declares a pool.
  Future<void> test_not_pools() => assertAt('''
final class Road {
  late final _left = pool('left', concurrency: 2);

  int pool(String name, {required int concurrency}) => concurrency;
}
''', []);

  // Only lane of SoloLanes declares a lane.
  Future<void> test_not_lanes() => assertAt('''
import 'package:solo/solo.dart';

final class Road {
  late final _left = lane('left');

  int lane(String name) => name.length;
}

final class Desk extends Solo<int> {
  Desk() : super(0);

  late final _left = lane('left');

  int lane(String name) => name.length;
}
''', []);
}
