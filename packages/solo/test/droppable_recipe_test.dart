@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// The recipe from `doc/jobs.md`, written as the page shows it: a method
/// that has to know whether its own job was taken assembles the job first
/// and compares it with what `add` gives back.
///
/// The page promises three things about it. They are pinned here so a
/// change to the policy cannot quietly turn the recipe into a lie.
int duplicates = 0;

final _mine = <SoloJob<String>>[];

SoloJob<String> load(TestSolo solo, String id) {
  final mine = solo.job<TestState, String>(
    key: ('load', id),
    (ctx) async {
      await ctx.wait(() => delay(100));
      return id;
    },
  );
  _mine.add(mine);
  final taken = solo.add(mine, policy: Policy.droppable);
  if (!identical(taken, mine)) {
    // `mine` was dropped and has already ended with `Cancelled(duplicate)`;
    // `taken` is the load that was there before this call.
    duplicates++;
  }
  return taken;
}

void main() {
  setUp(() {
    duplicates = 0;
    _mine.clear();
  });

  test('the first call is handed its own job', () {
    runSolo((solo, journal, async) {
      final taken = load(solo, 'ada');
      expect(identical(taken, _mine.single), isTrue);
      expect(duplicates, 0);
      async.flushTimers();
      expect(taken.outcome, isA<Done<String>>());
    });
  });

  test('the second call is handed the first job and told so', () {
    runSolo((solo, journal, async) {
      final first = load(solo, 'ada');
      final second = load(solo, 'ada');
      expect(identical(second, first), isTrue);
      expect(duplicates, 1);
      // Dropped inside the call itself: the outcome is there before
      // anything has run.
      expect(
        _mine.last.outcome,
        isA<Cancelled>()
            .having((c) => c.reason, 'reason', isA<DuplicateCancelReason>())
            .having((c) => '$c', 'text', 'Cancelled(duplicate)')
            .having((c) => c.started, 'started', isFalse),
      );
      async.flushTimers();
      expect(first.outcome, isA<Done<String>>());
    });
  });

  test("a load of another profile is nobody's duplicate", () {
    runSolo((solo, journal, async) {
      final ada = load(solo, 'ada');
      final grace = load(solo, 'grace');
      expect(identical(ada, grace), isFalse);
      expect(duplicates, 0);
      async.flushTimers();
      expect(ada.outcome, isA<Done<String>>());
      expect(grace.outcome, isA<Done<String>>());
    });
  });
}
