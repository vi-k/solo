// test_reflective_loader runs the methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:solo_lints/src/rules/catch_without_check.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CatchWithoutCheckTest);
  });
}

const _hardware = '''
abstract interface class Hardware {
  Future<void> open();

  Future<void> setZoom(int zoom);

  Future<void> reset();
}

late final Hardware hw;

final class DeviceError implements Exception {}
''';

const _solo =
    '''
import 'package:solo/solo.dart';

$_hardware
final class Camera extends Solo<Object> {
  Camera() : super(0);
''';

@reflectiveTest
class CatchWithoutCheckTest extends RuleTest {
  @override
  AbstractAnalysisRule get underTest => CatchWithoutCheck();

  Future<void> test_mistakes_page_wrong() => assertAt(
    '''
$_solo
  Job<void> zoom(int zoom) => enqueue<Object, void>((ctx) async {
    try {
      await ctx.join(hw.open);
      await ctx.join(() => hw.setZoom(zoom));
    } on Object catch (error) {
      await hw.reset();
      ctx.emit(error);
      rethrow;
    }
  });
}
''',
    ['on [[Object]] catch'],
  );

  Future<void> test_mistakes_page_right() => assertAt('''
$_solo
  Job<void> zoom(int zoom) => enqueue<Object, void>((ctx) async {
    try {
      await ctx.join(hw.open);
      await ctx.join(() => hw.setZoom(zoom));
    } on Object catch (error) {
      ctx.check();
      await hw.reset();
      ctx.emit(error);
      rethrow;
    }
  });
}
''', []);

  Future<void> test_clauses_that_take_cancelled() => assertAt(
    '''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  try {
    await hw.open();
  } catch (_) {
    await hw.reset();
  }
  try {
    await hw.open();
  } on Exception {
    await hw.reset();
  }
  try {
    await hw.open();
  } on Outcome<Object?> {
    await hw.reset();
  }
  try {
    await hw.open();
  } catch (_) {}
});
''',
    [
      '} [[catch]] (_) {',
      'on [[Exception]] {',
      'on [[Outcome<Object?>]] {',
      '} [[catch]] (_) {}',
    ],
  );

  Future<void> test_clauses_that_miss_cancelled() => assertAt('''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  try {
    await hw.open();
  } on DeviceError {
    await hw.reset();
  } on Cancelled {
    await hw.reset();
    rethrow;
  }
});
''', []);

  Future<void> test_try_that_cannot_cancel() => assertAt('''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  try {
    ctx.log('opening');
  } on Object {
    await hw.reset();
  }
});
''', []);

  Future<void> test_checkpoint_in_try_without_await() => assertAt(
    '''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  try {
    ctx.check();
  } on Object {
    await hw.reset();
  }
});
''',
    ['on [[Object]] {'],
  );

  Future<void> test_first_statements_that_ask() => assertAt('''
$_solo
  Job<void> open() => enqueue<Object, void>((ctx) async {
    try {
      await ctx.join(hw.open);
    } on Object {
      if (ctx.job.isCancelled) rethrow;
      await hw.reset();
    }
    try {
      await ctx.join(hw.open);
    } on Object catch (error) {
      ctx.emit(error);
      await hw.reset();
    }
    try {
      await ctx.join(hw.open);
    } on Object {
      await ctx.join(hw.reset);
    }
    try {
      await ctx.join(hw.open);
    } on Object {
      final state = ctx.state;
      ctx.log(state);
    }
    try {
      await ctx.join(hw.open);
    } on Object {
      rethrow;
    }
  });
}
''', []);

  Future<void> test_clause_for_cancelled_first_is_not_enough() => assertAt(
    '''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  try {
    await ctx.join(hw.open);
  } on Cancelled {
    rethrow;
  } on Object {
    await hw.reset();
  }
});
''',
    ['on [[Object]] {'],
  );

  Future<void> test_catch_in_cleanup() => assertAt('''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  ctx.onDispose(() async {
    try {
      await hw.reset();
    } on Object catch (error) {
      ctx.log(error);
    }
  });
});
''', []);

  Future<void> test_catch_outside_a_job() => assertAt('''
$_hardware
Future<void> open() async {
  try {
    await hw.open();
  } on Object {
    await hw.reset();
  }
}
''', []);

  Future<void> test_catch_in_a_nested_function() => assertAt(
    '''
import 'package:async_job/async_job.dart';

$_hardware
final job = Job<void>((ctx) async {
  await ctx.join(() async {
    try {
      await hw.open();
    } on Object {
      await hw.reset();
    }
  });
});
''',
    ['on [[Object]] {'],
  );

  // errors.md of solo, "A pause between attempts".
  Future<void> test_rethrow_if_before_a_checkpoint() => assertAt('''
$_solo
  Job<void> open() => enqueue<Object, void>((ctx) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await ctx.abandonable(hw.open);
      } on Object {
        if (attempt == 3) rethrow;
        await ctx.pause(Duration(seconds: attempt));
        continue;
      }
      return;
    }
  });
}
''', []);

  // groups.md of async_job, "A list the body hands out": the release has to
  // run for a cancellation too.
  Future<void> test_release_on_the_way_out() => assertAt('''
import 'package:async_job/async_job.dart';

abstract interface class Source {
  void close();
}

late final List<ChildJob<Source>> branches;

Future<void> writeArchive(List<Source> sources) async {}

final exported = Job.deferred<List<Source>>((ctx) async {
  final sources = await ctx.runAll(branches);
  try {
    await ctx.join(() => writeArchive(sources));
  } on Object catch (error) {
    ctx.log(error);
    for (final source in sources) {
      source.close();
    }
    rethrow;
  }
  return sources;
});
''', []);

  Future<void> test_catch_that_keeps_the_cancellation() => assertAt(
    '''
$_solo
  Job<void> open(bool quiet) => enqueue<Object, void>((ctx) async {
    try {
      await ctx.join(hw.open);
    } on Object catch (error) {
      ctx.log(error);
    }
    try {
      await ctx.join(hw.open);
    } on Object {
      if (quiet) return;
      rethrow;
    }
    try {
      await ctx.join(hw.open);
    } on Object {
      await hw.reset();
      rethrow;
    }
  });
}
''',
    ['on [[Object]] catch', 'on [[Object]] {', 'on [[Object]] {'],
  );

  Future<void> test_work_the_body_does_not_wait_for() => assertAt('''
$_solo
  Job<void> open() => enqueue<Object, void>((ctx) async {
    ctx.unattended(() async {
      try {
        await hw.open();
      } on Object catch (error) {
        ctx.log(error);
      }
    });
    await ctx.run(
      ctx.child((_) async {
        try {
          await ctx.join(hw.open);
        } on Object {
          await hw.reset();
        }
      }),
    );
  });
}
''', []);
}
