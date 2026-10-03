@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/jobs_page.dart';
import 'support/jobs_stubs.dart';

/// The recipe of `doc/jobs.md` for a method that has to know whether its
/// own job was taken: it assembles the job first and compares it with what
/// `add` gives back.
///
/// The code is the page's own, verbatim in `support/jobs_page.dart`. What
/// the page says about it is pinned here, so a change to the policy cannot
/// quietly turn the recipe into a lie.
void main() {
  setUp(() => stage = Stage());

  test('the first call is handed its own job', () {
    fakeAsync((async) {
      final camera = CountingController();
      final taken = camera.load('ada');

      expect(camera.duplicates, 0);
      expect(camera.finished, isEmpty, reason: 'nothing was dropped');
      async.flushTimers();
      expect('${taken.outcome}', 'Done(Profile(ada))');
      expect(camera.finished, [taken]);
      camera.close().ignore();
      async.flushTimers();
    });
  });

  test('the second call is handed the first job and told so', () {
    fakeAsync((async) {
      final camera = CountingController();
      final first = camera.load('ada');
      final second = camera.load('ada');

      expect(second, same(first));
      expect(camera.duplicates, 1);
      // Dropped inside the call itself: the job the second call brought has
      // its outcome before anything has run.
      final dropped = camera.finished.single;
      expect(dropped, isNot(same(first)));
      expect(
        dropped.outcome,
        isA<Cancelled>()
            .having((c) => c.reason, 'reason', isA<DuplicateCancelReason>())
            .having(
              (c) => c.reason,
              'reason',
              isNot(isA<ManualCancelReason>()),
            )
            .having((c) => '$c', 'text', 'Cancelled(duplicate)')
            .having((c) => c.started, 'started', isFalse),
      );

      async.flushTimers();
      expect('${first.outcome}', 'Done(Profile(ada))');
      expect(
        stage.trace,
        ['load ada begins', 'load ada ends'],
        reason: 'the dropped job never started',
      );
      camera.close().ignore();
      async.flushTimers();
    });
  });

  test("a load of another profile is nobody's duplicate", () {
    fakeAsync((async) {
      final camera = CountingController();
      final ada = camera.load('ada');
      final grace = camera.load('grace');

      expect(grace, isNot(same(ada)));
      expect(camera.duplicates, 0);
      async.flushTimers();
      expect('${ada.outcome}', 'Done(Profile(ada))');
      expect('${grace.outcome}', 'Done(Profile(grace))');
      camera.close().ignore();
      async.flushTimers();
    });
  });

  test('a call that finds the load over is handed a job of its own', () {
    fakeAsync((async) {
      final camera = CountingController();
      final first = camera.load('ada');
      async.flushTimers();
      final later = camera.load('ada');

      expect(later, isNot(same(first)));
      expect(camera.duplicates, 0);
      async.flushTimers();
      expect('${later.outcome}', 'Done(Profile(ada))');
      camera.close().ignore();
      async.flushTimers();
    });
  });
}
