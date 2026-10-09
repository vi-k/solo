@Timeout(Duration(seconds: 5))
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/accumulation_first_attempts.dart';
import 'support/accumulation_page.dart';
import 'support/accumulation_second_attempts.dart';
import 'support/accumulation_stubs.dart';
import 'support/page_code.dart';

/// The sentinel of `doc/accumulation.md`.
///
/// The code of the page stands verbatim in the files
/// `test/support/accumulation_*.dart`: the first attempts in one, the second
/// attempts in another, the accumulators, the types and the two blocks of
/// the reference in a third. The tests below run that
/// code through the scenario the page gives each recipe, build the lines the
/// page quotes under it and compare them with the quote. What the page says
/// of the engine without showing code is pinned on `Bench`, a controller
/// whose handlers write down when they started and with what.
///
/// The bench `tool/accumulation_snippets.py` builds the same blocks out of
/// the page itself and stays the guard of its code; this file is what
/// `dart test` knows of the page between two runs of the bench.
///
/// Every scenario runs under fake time. A test collects what it saw and
/// asserts once the zone it ran in has returned: an `expect` that failed
/// inside would be one more error of that zone.

const _doc = 'doc/accumulation.md';
const _pageFile = 'test/support/accumulation_page.dart';
const _attemptsFile = 'test/support/accumulation_first_attempts.dart';
const _secondAttemptsFile = 'test/support/accumulation_second_attempts.dart';

String _page() => File(_doc).readAsStringSync();

/// The page with every run of whitespace turned into one space, so that a
/// phrase is found wherever its lines were broken.
String _prose() => _page().replaceAll(RegExp(r'\s+'), ' ');

/// Holds the page to [phrase]: the test that calls this runs what the phrase
/// says, so a page that stops saying it leaves the test with nothing to
/// stand for.
///
/// The page is not handed to `expect`: a failure would print all of it.
void _says(String phrase) => expect(
      _prose().contains(phrase),
      isTrue,
      reason: '$_doc no longer says: $phrase',
    );

/// What the page quotes under its `text` fences, in order.
List<String> _quotes() => [
      for (final block
          in RegExp(r'```text\n(.*?)\n```', dotAll: true).allMatches(_page()))
        block.group(1)!,
    ];

/// What the code under test printed.
final _printed = <String>[];

/// Runs [body] under fake time, in a zone of its own, and returns the errors
/// that reached that zone uncaught. Nothing is asserted inside.
List<String> _zone(void Function(FakeAsync async) body) {
  final errors = <String>[];
  _printed.clear();
  fakeAsync((async) {
    now = () => async.elapsed.inMilliseconds;
    runZonedGuarded(
      () => body(async),
      (error, stackTrace) => errors.add('$error'),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => _printed.add(line),
      ),
    );
    async.flushMicrotasks();
  });

  return errors;
}

const _off = Settings(notifications: false, theme: 'light', language: 'en');

AccumulationTiming _debounce(int milliseconds) =>
    AccumulationTiming.debounce(ms(milliseconds));

AccumulationTiming _throttle(int milliseconds, {bool startAtOnce = true}) =>
    AccumulationTiming.throttle(ms(milliseconds), startAtOnce: startAtOnce);

/// The scenario of the search recipe: `solo`, one character every 50 ms.
/// Returns the lines the page quotes under a version, and the server.
({String trace, FakeSearchApi api, List<int> shownAt})
    _type<C extends Solo<SearchState>>(
  C Function(SearchApi api) make,
  Job<void> Function(C controller, String text) query, {
  int latency = 100,
}) {
  final api = FakeSearchApi(latency);
  final shown = <String>[];
  final shownAt = <int>[];
  _zone((async) {
    final controller = make(api);
    controller.addListener(() {
      shown.add(
        'at ${now()} ms the screen shows ${controller.currentState.results}',
      );
      shownAt.add(now());
    });
    for (final text in ['s', 'so', 'sol', 'solo']) {
      query(controller, text);
      async.elapse(ms(50));
    }
    async.elapse(ms(1300));
  });
  final times = api.asked.length == 1 ? 'time' : 'times';

  return (
    trace: [
      'the server was asked ${api.asked.length} $times: ${api.asked}',
      ...shown,
    ].join('\n'),
    api: api,
    shownAt: shownAt,
  );
}

/// The scenario of the settings recipe: the switch, the theme, the language,
/// 20 ms apart.
({
  String trace,
  FakeSettingsApi api,
  List<String> outcomes,
  List<int> shownAt,
  List<String> errors,
}) _flip<C extends Solo<Settings>>(
  C Function(SettingsApi api) make,
  Job<void> Function(C controller, SettingsPatch patch) update,
) {
  final api = FakeSettingsApi();
  final outcomes = <String>[];
  final shownAt = <int>[];
  var end = '';
  final errors = _zone((async) {
    final controller = make(api)..addListener(() => shownAt.add(now()));
    final jobs = <Job<void>>[];
    for (final patch in const [
      SettingsPatch(notifications: true),
      SettingsPatch(theme: 'dark'),
      SettingsPatch(language: 'ru'),
    ]) {
      jobs.add(update(controller, patch));
      async.elapse(ms(20));
    }
    async.elapse(ms(1000));
    outcomes.addAll([for (final job in jobs) '${job.outcome}']);
    end = describe(controller.currentState);
  });
  final times = api.sent.length == 1 ? 'time' : 'times';

  return (
    trace: [
      'the server was written to ${api.sent.length} $times:',
      for (final write in api.sent) '  $write',
      'the screen ends up with $end',
    ].join('\n'),
    api: api,
    outcomes: outcomes,
    shownAt: shownAt,
    errors: errors,
  );
}

/// The scenario of the log recipe: three lines written one after another,
/// then one more [later] ms after them.
({String trace, FakeLogApi api, int counter}) _write<C extends Solo<int>>(
  C Function(LogApi api) make,
  Job<void> Function(C controller, LogEntry entry) log, {
  int later = 2000,
}) {
  final api = FakeLogApi();
  var burst = 0;
  var counter = 0;
  _zone((async) {
    final controller = make(api);
    for (final message in ['opened', 'loaded', 'shown']) {
      log(controller, LogEntry(message));
    }
    async.elapse(ms(500));
    burst = api.sent.length;
    async.elapse(ms(later - 500));
    log(controller, const LogEntry('tapped'));
    async.elapse(ms(3000));
    counter = controller.currentState;
  });
  final requests = api.sent.length == 1 ? 'request' : 'requests';

  return (
    trace: [
      'the server got ${api.sent.length} $requests:',
      for (var i = 0; i < api.sent.length; i++)
        '  ${api.sent[i]} at ${api.sentAt[i]} ms',
      'the three lines of the transition cost $burst of them',
      'the counter says $counter',
    ].join('\n'),
    api: api,
    counter: counter,
  );
}

/// The scenario of the command recipe: three taps in a row, resume, pause,
/// resume.
({String trace, FakeDevice device, List<String> heard})
    _tap<C extends Solo<Playback>>(
  C Function(PlayerDevice device) make,
  Job<void> Function(C controller) resume,
  Job<void> Function(C controller) pause,
) {
  final device = FakeDevice();
  final hears = Hears();
  Solo.observer = hears;
  var one = false;
  var settled = -1;
  var end = '';
  _zone((async) {
    final controller = make(device);
    final first = resume(controller);
    pause(controller);
    final third = resume(controller);
    one = identical(first, third);
    third.done.then((_) => settled = now()).ignore();
    async.elapse(ms(800));
    end = '${controller.currentState.runtimeType}';
  });
  Solo.observer = null;
  final commands = device.heard.length == 1 ? 'command' : 'commands';

  return (
    trace: [
      'the device heard ${device.heard.length} $commands:',
      for (final command in device.heard) '  $command',
      'the button gave back ${one ? 'one job' : 'a job for every tap'}',
      'the player settles $end at $settled ms',
    ].join('\n'),
    device: device,
    heard: hears.lines,
  );
}

/// The controller of the settings with a deadline on its accumulator: what
/// the page says of `timeout` next to the client timeout.
final class _TimedSettings extends Solo<Settings> {
  final SettingsApi _api;
  late final _updates = accumulate<Settings, SettingsPatch, void>(
    (ctx, patch) async {
      final next = patch.apply(ctx.state);
      await ctx.join(() => _api.save(next));
      ctx.emit(next);
    },
    merge: (accumulated, incoming) => accumulated.merge(incoming),
    key: 'settings',
    timeout: const Duration(milliseconds: 100),
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
  );

  _TimedSettings(this._api, super.initial);

  SoloJob<void> update(SettingsPatch patch) => _updates.add(patch);
}

void main() {
  tearDown(() {
    Solo.observer = null;
    Solo.debug = null;
  });

  group('The page', () {
    test('every first attempt stands in the file of the first attempts', () {
      expect(
        codeMissingFrom(_doc, _attemptsFile, under: '#### The first attempt'),
        isEmpty,
      );
    });

    test('every second attempt stands in the file of the second attempts', () {
      expect(
        codeMissingFrom(
          _doc,
          _secondAttemptsFile,
          under: '#### The second attempt',
        ),
        isEmpty,
      );
    });

    test('every other block stands in the file of the page', () {
      for (final heading in [
        '### A search that fires on every keystroke',
        '### Settings saved on every flip of a switch',
        '### One request per log line',
        '### Commands where only the last one counts',
        '#### The accumulator',
        '#### When they are separate jobs after all',
        '### Choosing where events join',
        '### Start, cancellation and errors',
      ]) {
        expect(
          codeMissingFrom(_doc, _pageFile, under: heading),
          isEmpty,
          reason: heading,
        );
      }
    });

    test('no block of the page is left out of both files', () {
      expect(
        codeMissingFrom(
          _doc,
          _pageFile,
          alsoIn: [_attemptsFile, _secondAttemptsFile],
        ),
        isEmpty,
      );
      expect(
        RegExp(r'^```dart$', multiLine: true).allMatches(_page()),
        hasLength(18),
      );
    });

    test('every fence is dart or text, and twelve of them are quotes', () {
      expect(strayFences(_doc), isEmpty);
      expect(_quotes(), hasLength(12));
      _says('Under each version is what the scenario above it leads to');
    });

    test('a first attempt opens every recipe, the accumulator closes it', () {
      final headings = [
        for (final line in _page().split('\n'))
          if (line.startsWith('####')) line.substring(5),
      ];
      expect(headings, [
        'The first attempt',
        'The second attempt',
        'The accumulator',
        'The first attempt',
        'The second attempt',
        'The accumulator',
        'The first attempt',
        'The accumulator',
        'The first attempt',
        'The accumulator',
        'When they are separate jobs after all',
      ]);
    });

    test('the sections it points at are named by their headings', () {
      _says('[Choosing where events join](#choosing-where-events-join) says '
          'when to take `adjacent` instead');
      _says('[Choosing when a group is '
          'ready](#choosing-when-a-group-is-ready) explains what a throttle '
          'interval is measured from');
      expect(_prose().contains('The policy section'), isFalse);
      expect(_prose().contains('the timing section'), isFalse);
    });

    test('ctx.join and the policy join are told apart where both stand', () {
      _says('`ctx.join` keeps the execution slot until that future completes');
      _says('the place `AccumulationPolicy.join` keeps is not reachable');
    });
  });

  group('The opening', () {
    test('adding an event runs no handler and changes no state', () {
      _says('Adding an event does not run the handler or change controller '
          'state');
      final api = FakeLogApi();
      var counter = -1;
      var queued = false;
      _zone((async) {
        final logs = LogController(api);
        final job = logs.logEvent(const LogEntry('one'));
        queued = job.isQueued;
        counter = logs.currentState;
      });
      expect(queued, isTrue);
      expect(counter, 0);
      expect(api.sent, [
        ['one'],
      ]);
    });

    test('a group is sealed when its debounce window expires', () {
      _says('a group accepts events until it is sealed: when its debounce '
          'window expires');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _debounce(200));
        bench.busy('busy', 500);
        final first = a.add('1');
        async.elapse(ms(199));
        seen.add('before: ${identical(first, a.add('2'))}');
        async.elapse(ms(200));
        seen.add('after: ${identical(first, a.add('3'))}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, [
        'before: true',
        'after: false',
        'busy at 0 ms',
        'a[1, 2] at 500 ms',
        'a[3] at 599 ms',
      ]);
    });

    test('under a throttle or no timing, when the queue takes the job', () {
      _says('under a throttle or with no timing at all, when the queue takes '
          'the job to run it');
      for (final timing in [null, _throttle(200)]) {
        final seen = <String>[];
        _zone((async) {
          final bench = Bench();
          final a = bench.collector('a', timing: timing, work: 100);
          final first = a.add('1');
          seen.add('queued: ${identical(first, a.add('2'))}');
          async.elapse(ms(10));
          seen.add('taken: ${identical(first, a.add('3'))}');
          async.elapse(ms(1000));
          seen.add(bench.ran.first);
        });
        expect(
          seen,
          ['queued: true', 'taken: false', 'a[1, 2] at 0 ms'],
          reason: '$timing',
        );
      }
    });
  });

  group('A search that fires on every keystroke', () {
    test('the first attempt asks four times and shows four screens', () {
      final run = _type(QueuedSearch.new, (c, text) => c.query(text));
      expect(run.trace, _quotes()[0]);
      expect(run.api.askedAt, [0, 100, 200, 300]);
      _says('Each request waits for the one before it, so the answer to '
          '`solo` arrives 400 ms after the first keystroke');
      _says('the screen answers three words the user had already typed past');
    });

    test('the second attempt shows one screen and still asks four times', () {
      final run = _type(RestartingSearch.new, (c, text) => c.query(text));
      expect(run.trace, _quotes()[1]);
      expect(run.api.askedAt, [0, 50, 100, 150]);
      expect(run.shownAt, [250]);
      _says('Nothing stale reaches the screen now, and the answer comes '
          'sooner');
      _says('The server was still asked four times');
    });

    test('ctx.join in its place sends fewer against this server, and later',
        () {
      _says('how many requests go out depends on how much faster the server '
          'is than the typing');
      final waited = _type(RestartingSearch.new, (c, text) => c.query(text));
      final joined = _type(JoiningSearch.new, (c, text) => c.query(text));
      expect(joined.api.asked, ['s', 'so', 'solo']);
      expect(joined.shownAt.single, greaterThan(waited.shownAt.single));
    });

    test('against a server faster than the typing ctx.join saves nothing', () {
      final waited = _type(
        RestartingSearch.new,
        (c, text) => c.query(text),
        latency: 40,
      );
      final joined = _type(
        JoiningSearch.new,
        (c, text) => c.query(text),
        latency: 40,
      );
      expect(joined.api.asked, waited.api.asked);
      expect(joined.api.asked, hasLength(4));
    });

    test('the accumulator asks once, 300 ms after the typing stops', () {
      final run = _type(Search.new, (c, text) => c.query(text));
      expect(run.trace, _quotes()[2]);
      expect(run.api.askedAt, [450]);
      _says('the debounce holds the group until the typing stops for 300 ms');
      _says('`policy` spells out the default, `join`; [Choosing where events '
          'join](#choosing-where-events-join) says what a policy decides');
    });

    test('its answer is later than either attempt above', () {
      _says('the answer arrives later than either attempt above');
      final first = _type(QueuedSearch.new, (c, text) => c.query(text));
      final second = _type(RestartingSearch.new, (c, text) => c.query(text));
      final third = _type(Search.new, (c, text) => c.query(text));
      expect(third.shownAt.last, greaterThan(first.shownAt.last));
      expect(third.shownAt.last, greaterThan(second.shownAt.last));
    });

    test('typing that never pauses for 300 ms asks nothing', () {
      final api = FakeSearchApi();
      final seen = <String>[];
      _zone((async) {
        final search = Search(api);
        for (var tap = 0; tap < 20; tap++) {
          search.query('q$tap');
          async.elapse(ms(299));
        }
        seen.add('typing: ${api.asked}');
        async.elapse(ms(1));
        seen.add('paused: ${api.asked}');
      });
      expect(seen, ['typing: []', 'paused: [q19]']);
    });

    test('a cancelled job leaves its request in flight for the next group', () {
      _says('cancelling one ends its waiting, not the request it has already '
          'sent');
      final api = FakeSearchApi(1000);
      final seen = <String>[];
      _zone((async) {
        final search = Search(api);
        final first = search.query('solo');
        async.elapse(ms(400));
        seen.add('started: ${api.open} open');
        first.cancel().ignore();
        async.elapse(ms(10));
        seen.add('cancelled: ${first.outcome}, ${api.open} open');
        search.query('dart');
        async.elapse(ms(400));
        seen.add('next group: ${api.open} open');
        async.elapse(ms(3000));
        seen.add('end: ${search.currentState.results}');
      });
      expect(seen, [
        'started: 1 open',
        'cancelled: Cancelled(manual), 1 open',
        'next group: 2 open',
        'end: [hits for dart]',
      ]);
    });

    test("every keystroke of a group gets the group's one job", () {
      _says('the returned job exposes the outcome and cancellation, like '
          'other jobs');
      final api = FakeSearchApi();
      final jobs = <Job<void>>{};
      var outcome = '';
      _zone((async) {
        final search = Search(api);
        for (final text in ['s', 'so', 'sol']) {
          jobs.add(search.query(text));
        }
        async.elapse(ms(1000));
        outcome = '${jobs.single.outcome}';
      });
      expect(jobs, hasLength(1));
      expect(outcome, 'Done(null)');
    });
  });

  group('Settings saved on every flip of a switch', () {
    test('a patch replaces the fields it carries and keeps the rest', () {
      _says('A new value for a field replaces the previous one; fields '
          'absent from the new patch are kept');
      final merged = const SettingsPatch(theme: 'dark', language: 'ru')
          .merge(const SettingsPatch(theme: 'light'));
      expect(
        describe(merged.apply(_off)),
        'notifications: false, theme: light, language: ru',
      );
    });

    test('the first attempt writes three times', () {
      final run = _flip(
        (api) => EagerSettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      expect(run.trace, _quotes()[3]);
      expect(run.api.sentAt, [0, 100, 200]);
      expect(run.outcomes, ['Done(null)', 'Done(null)', 'Done(null)']);
    });

    test('its first two writes land after the user has moved on from them', () {
      _says('the first two publish settings the user has already moved on '
          'from');
      _says('Another device reading between them finds the light theme '
          'after its owner has already picked the dark one');
      final run = _flip(
        (api) => EagerSettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      // The three changes are made at 0, 20 and 40 ms; the dark theme is
      // picked at 20 ms.
      expect(run.api.landedAt, [100, 200, 300]);
      expect(run.api.sent[0], contains('theme: light'));
      expect(run.api.sent[1], contains('language: en'));
    });

    test('the second attempt loses two of the three changes', () {
      final run = _flip(
        (api) => RestartingSettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      expect(run.trace, _quotes()[4]);
      _says('The switch went back off and the theme went back to light');
      _says("Two of the user's three changes are gone, from the server and "
          'from the screen both, and nothing failed');
      expect(run.errors, isEmpty);
      expect(
        run.outcomes,
        ['Cancelled(replaced)', 'Cancelled(replaced)', 'Done(null)'],
      );
    });

    test('the write restart asked to stop went out all the same', () {
      _says('The first of the two writes is the one restart asked to stop, '
          'and it went out all the same');
      final run = _flip(
        (api) => RestartingSettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      expect(run.api.sentAt, [0, 100]);
      expect(run.api.landedAt, [100, 200]);
      // The cancelled job never reached its `emit`: one screen, the last.
      expect(run.shownAt, [200]);
    });

    test('the accumulator writes once, with all three changes', () {
      final run = _flip(
        (api) => SettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      expect(run.trace, _quotes()[5]);
      _says('the group carries all three changes into one write');
      expect(run.outcomes, ['Done(null)', 'Done(null)', 'Done(null)']);
    });

    test('200 ms after the last change it saves, then emits what it saved', () {
      _says('After 200 ms without another change the handler saves one '
          'snapshot with all three changes, and emits it once the write has '
          'ended');
      final run = _flip(
        (api) => SettingsController(api, _off),
        (c, patch) => c.update(patch),
      );
      expect(run.api.sentAt, [240]);
      expect(run.api.landedAt, [340]);
      expect(run.shownAt, [340]);
    });

    test('a reload queued between two flips is not a boundary', () {
      _says('so a `reload` queued between two flips is not a boundary');
      final api = FakeSettingsApi();
      var one = false;
      _zone((async) {
        final settings = SettingsController(api, _off);
        final first = settings.update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(10));
        settings.reload();
        async.elapse(ms(10));
        one = identical(
          first,
          settings.update(const SettingsPatch(language: 'ru')),
        );
        async.elapse(ms(1000));
      });
      expect(one, isTrue);
      expect(api.loads, 1);
      expect(api.sent, ['notifications: false, theme: dark, language: ru']);
    });

    test('merge is not called for the first event, and is for each next one',
        () {
      _says('The first event becomes the accumulated value without calling '
          '`merge`');
      _says('synchronously from `add`, before the handler starts');
      final api = FakeSettingsApi();
      final merged = <String>[];
      final seen = <String>[];
      _zone((async) {
        final settings = SettingsController(api, _off)
          ..update(CountingPatch(merged, notifications: true));
        seen.add('after the first: ${merged.length}');
        async.elapse(ms(50));
        settings.update(const SettingsPatch(theme: 'dark'));
        seen.add('after the second: $merged, writes ${api.sent.length}');
        async.elapse(ms(1000));
      });
      expect(seen, [
        'after the first: 0',
        'after the second: [merge at 50 ms], writes 0',
      ]);
      expect(api.sent, ['notifications: true, theme: dark, language: en']);
    });

    test('changeSettings prints what the page quotes', () {
      final api = FakeSettingsApi();
      _zone((async) {
        changeSettings(api, _off).ignore();
        async.elapse(ms(1000));
      });
      expect(_printed.join('\n'), _quotes()[6]);
      expect(api.sent, ['notifications: true, theme: dark, language: ru']);
    });

    test(
        'until the handler runs the state is the initial one, and a ready '
        'job runs in the pause', () {
      _says('Until the handler runs, the state keeps its initial value, and '
          'other ready jobs can run during the pause');
      final api = FakeSettingsApi();
      final seen = <String>[];
      _zone((async) {
        final settings = SettingsController(api, _off)
          ..update(const SettingsPatch(theme: 'dark'));
        final reload = settings.reload();
        async.elapse(ms(150));
        seen
          ..add('in the pause: ${describe(settings.currentState)}')
          ..add('reload: ${reload.outcome}, writes ${api.sent.length}');
        async.elapse(ms(1000));
        seen.add('after: ${describe(settings.currentState)}');
      });
      expect(seen, [
        'in the pause: notifications: false, theme: light, language: en',
        'reload: Done(null), writes 0',
        'after: notifications: false, theme: dark, language: en',
      ]);
    });

    test('a failed save fails the group and leaves the state as it was', () {
      _says('If saving fails, the state is unchanged and the group fails');
      final api = FakeSettingsApi()..failure = StateError('disk full');
      final seen = <String>[];
      final errors = _zone((async) {
        final settings = SettingsController(api, _off);
        final group = settings.update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(400));
        seen
          ..add('${group.outcome}')
          ..add(describe(settings.currentState));
      });
      expect(seen, [
        'Failed(Bad state: disk full)',
        'notifications: false, theme: light, language: en',
      ]);
      // Nobody observed the outcome, so the failure reaches the zone too.
      expect(errors, ['Bad state: disk full']);
    });

    test('a later patch does not carry the changes that failed', () {
      _says('a later independent patch does not automatically include them');
      final api = FakeSettingsApi()..failure = StateError('disk full');
      _zone((async) {
        final settings = SettingsController(api, _off)
          ..update(const SettingsPatch(theme: 'dark')).ignoreFailure();
        async.elapse(ms(400));
        api.failure = null;
        settings.update(const SettingsPatch(language: 'ru'));
        async.elapse(ms(400));
      });
      expect(api.sent.last, 'notifications: false, theme: light, language: ru');
    });

    test('ctx.join keeps the slot of a cancelled write until it has ended', () {
      _says('even after cancellation, and that is what stops the next write '
          'from starting on top of this one');
      final api = FakeSettingsApi(latency: 500);
      final seen = <String>[];
      _zone((async) {
        final settings = SettingsController(api, _off);
        final first = settings.update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(250));
        first.cancel().ignore();
        settings.update(const SettingsPatch(language: 'ru'));
        async.elapse(ms(300));
        seen.add('at 550: finished ${first.isFinished}, '
            '${api.writing} writing, ${api.sent.length} sent');
        async.elapse(ms(1500));
        seen.add('${first.outcome}, the next write at ${api.sentAt.last} ms');
      });
      expect(seen, [
        'at 550: finished false, 1 writing, 1 sent',
        'Cancelled(manual), the next write at 700 ms',
      ]);
    });

    test(
        'a save that gives up on a timeout lets the next write go out over '
        'it', () {
      _says('a `save` that completes its future on a timeout hands the slot '
          'back while the server is still writing');
      final api = FakeSettingsApi(latency: 500, timeout: 100);
      var writing = 0;
      _zone((async) {
        final settings = SettingsController(api, _off)
          ..update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(350));
        settings.update(const SettingsPatch(language: 'ru'));
        async.elapse(ms(250));
        writing = api.writing;
        async.elapse(ms(2000));
      });
      expect(writing, 2);
      expect(api.sentAt, [200, 550]);
      expect(api.landedAt, [700, 1050]);
    });

    test(
        'a deadline keeps the slot, and costs the emit that the next group '
        'writes back over', () {
      _says('A deadline given to the accumulator with `timeout` is a '
          'cancellation, not a client timeout: `ctx.join` keeps the slot until '
          '`save` completes, so the next write still waits for this one to '
          'end');
      _says('the next group applies its patch to them and writes the old '
          'values back over the change');
      _says('A group past its deadline is cancelled while the server is still '
          'writing, ends `Cancelled(timeout)` once the write is stored, and '
          'never reaches its `emit`');
      final api = FakeSettingsApi(latency: 500);
      final seen = <String>[];
      _zone((async) {
        final settings = _TimedSettings(api, _off);
        final first = settings.update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(350));
        final second = settings.update(const SettingsPatch(language: 'ru'));
        async.elapse(ms(250));
        seen.add('at 600: ${first.outcome}, cancelled ${first.isCancelled}, '
            '${api.writing} writing');
        async.elapse(ms(2000));
        seen
          ..add('${first.outcome}, ${second.outcome}')
          ..add('server ${describe(api.stored)}')
          ..add('screen ${describe(settings.currentState)}');
      });
      expect(api.sentAt, [200, 700]);
      expect(api.landedAt, [700, 1200]);
      expect(seen, [
        'at 600: null, cancelled true, 1 writing',
        'Cancelled(timeout), Cancelled(timeout)',
        'server notifications: false, theme: light, language: ru',
        'screen notifications: false, theme: light, language: en',
      ]);
    });

    test('a cancellation can keep the emit from a write the server accepted',
        () {
      _says('Cancellation can also prevent the final `emit` after the server '
          'has accepted the write');
      final api = FakeSettingsApi();
      final seen = <String>[];
      _zone((async) {
        final settings = SettingsController(api, _off);
        final group = settings.update(const SettingsPatch(theme: 'dark'));
        async.elapse(ms(250));
        group.cancel().ignore();
        async.elapse(ms(500));
        seen
          ..add('${group.outcome}')
          ..add('server ${api.stored.theme}, screen '
              '${settings.currentState.theme}');
      });
      expect(seen, ['Cancelled(manual)', 'server dark, screen light']);
    });
  });

  group('One request per log line', () {
    test('the first attempt sends four requests, each after the one before',
        () {
      final run =
          _write(EagerLogController.new, (c, entry) => c.logEvent(entry));
      expect(run.trace, _quotes()[7]);
      _says('Three lines written one after another by the code that handles '
          'a screen transition, then one more two seconds later');
      expect(run.api.sentAt, [0, 100, 200, 2000]);
      _says('each send starts only when the one before it has finished');
    });

    test('the collector sends the transition together and the fourth at once',
        () {
      final run = _write(LogController.new, (c, entry) => c.logEvent(entry));
      expect(run.trace, _quotes()[8]);
      _says('The fourth is written after the throttle interval has passed, '
          'so it goes at once and on its own');
      expect(run.api.sentAt, [0, 2000]);
    });

    test('a fourth line written inside the interval waits for its end', () {
      _says('the interval is a floor under the rate, not a delay added to '
          'every entry');
      final run = _write(
        LogController.new,
        (c, entry) => c.logEvent(entry),
        later: 500,
      );
      expect(run.api.sent, [
        ['opened', 'loaded', 'shown'],
        ['tapped'],
      ]);
      expect(run.api.sentAt, [0, 1000]);
    });

    test('the handler gets an unmodifiable list', () {
      _says('gives the handler an unmodifiable snapshot');
      final api = FakeLogApi();
      Object? refusal;
      _zone((async) {
        LogController(api).logEvent(const LogEntry('one'));
        async.elapse(ms(10));
        try {
          api.lists.single.add(const LogEntry('two'));
        } on Object catch (error) {
          refusal = error;
        }
      });
      expect(refusal, isUnsupportedError);
    });

    test('an entry changed after add is sent changed', () {
      _says('an entry changed after `add` is sent changed');
      final api = FakeLogApi();
      _zone((async) {
        final logs = LogController(api)..logEvent(const LogEntry('first'));
        async.elapse(ms(10));
        final entry = MutableEntry('as added');
        logs.logEvent(entry);
        async.elapse(ms(10));
        entry.text = 'changed after add';
        async.elapse(ms(2000));
      });
      expect(api.sent.last, ['changed after add']);
    });

    test('every addition to a group gets the same job', () {
      _says('the caller gets the same `Job` every other addition to that '
          'group got');
      final jobs = <Job<void>>{};
      _zone((async) {
        final logs = LogController(FakeLogApi());
        for (final message in ['one', 'two', 'three']) {
          jobs.add(logs.logEvent(LogEntry(message)));
        }
        async.elapse(ms(200));
      });
      expect(jobs, hasLength(1));
    });

    test('close() drops the waiting group and leaves no timer of its own', () {
      _says('`close()` drops the group instead of leaving a list and a timer '
          'behind');
      final api = FakeLogApi();
      final seen = <String>[];
      _zone((async) {
        final logs = LogController(api)..logEvent(const LogEntry('one'));
        async.elapse(ms(150));
        final waiting = logs.logEvent(const LogEntry('two'));
        seen.add('before: ${async.pendingTimers.length} timer');
        logs.close().ignore();
        seen.add('after: ${async.pendingTimers.length} timers, '
            '${waiting.outcome}');
        async.elapse(ms(3000));
      });
      expect(seen, [
        'before: 1 timer',
        'after: 0 timers, Cancelled(closed)',
      ]);
      expect(api.sent, [
        ['one'],
      ]);
    });

    test('the counter counts what was sent and reached emit', () {
      _says('counts entries whose send operation completed and whose handler '
          'reached `emit`');
      final api = FakeLogApi()..failure = StateError('offline');
      final seen = <String>[];
      final errors = _zone((async) {
        final logs = LogController(api);
        final failed = logs.logEvent(const LogEntry('one'));
        async.elapse(ms(200));
        seen.add('${failed.outcome}, counter ${logs.currentState}');
        api.failure = null;
        async.elapse(ms(1000));
        final cancelled = logs.logEvent(const LogEntry('two'));
        async.elapse(ms(50));
        cancelled.cancel().ignore();
        async.elapse(ms(200));
        seen.add('${cancelled.outcome}, counter ${logs.currentState}');
        async.elapse(ms(1000));
        logs.logEvent(const LogEntry('three'));
        async.elapse(ms(200));
        seen.add('counter ${logs.currentState}');
      });
      expect(seen, [
        'Failed(Bad state: offline), counter 0',
        'Cancelled(manual), counter 0',
        'counter 1',
      ]);
      expect(api.sent, [
        ['one'],
        ['two'],
        ['three'],
      ]);
      expect(errors, ['Bad state: offline']);
    });

    test('the working type int is the whole state, so any count starts', () {
      _says('Both take three type arguments, `<W, E, T>`: the working type '
          '`W`, as in `run`, the event type `E` and the result type `T`');
      _says('The working type `int` is that whole state, so the handler '
          'starts whatever the count is and reads it as `ctx.state`.');
      final api = FakeLogApi();
      final counts = <int>[];
      _zone((async) {
        final logs = LogController(api);
        for (final message in ['one', 'two', 'three']) {
          logs.logEvent(LogEntry(message));
          async.elapse(ms(1200));
          counts.add(logs.currentState);
        }
      });
      // Each group started at the count the one before it left.
      expect(counts, [1, 2, 3]);
      expect(api.sent, [
        ['one'],
        ['two'],
        ['three'],
      ]);
    });

    test('a cancelled group and a plain close() leave entries unsent', () {
      _says('A failed send, a cancelled group or a plain `close()` can leave '
          'them unsent');
      final api = FakeLogApi();
      _zone((async) {
        final logs = LogController(api)..logEvent(const LogEntry('one'));
        async.elapse(ms(150));
        logs.logEvent(const LogEntry('cancelled')).cancel().ignore();
        logs.logEvent(const LogEntry('closed'));
        logs.close().ignore();
        async.elapse(ms(3000));
      });
      expect(api.sent, [
        ['one'],
      ]);
    });

    test('a draining close sends what is already queued', () {
      _says('`close()` with `SoloCloseMode.drain` sends what is already '
          'queued');
      final api = FakeLogApi();
      var closedAt = -1;
      var counter = 0;
      _zone((async) {
        final logs = LogController(api)..logEvent(const LogEntry('one'));
        async.elapse(ms(10));
        logs
          ..logEvent(const LogEntry('two'))
          ..logEvent(const LogEntry('three'));
        logs
            .close(mode: SoloCloseMode.drain)
            .then((_) => closedAt = now())
            .ignore();
        async.elapse(ms(3000));
        counter = logs.currentState;
      });
      expect(api.sent, [
        ['one'],
        ['two', 'three'],
      ]);
      expect(api.sentAt, [0, 1000]);
      expect(closedAt, 1100);
      expect(counter, 3);
    });
  });

  group('Commands where only the last one counts', () {
    test('the first attempt tells the device everything that was tapped', () {
      final run = _tap(QueuedPlayer.new, (c) => c.resume(), (c) => c.pause());
      expect(run.trace, _quotes()[9]);
      _says('gets there the long way');
      _says('it plays, stops, and plays again, and the stop in the middle is '
          'something the user hears');
    });

    test('the accumulator tells it once, on one job', () {
      final run = _tap(Player.new, (c) => c.resume(), (c) => c.pause());
      expect(run.trace, _quotes()[10]);
      _says('all three return the same handle');
    });

    test('nothing was queued and cancelled on the way', () {
      _says('Nothing was queued and cancelled on the way');
      final run = _tap(Player.new, (c) => c.resume(), (c) => c.pause());
      expect(run.heard, [
        'transport started at 0 ms',
        'transport finished Done(null) at 100 ms',
      ]);
    });

    test('merge keeps the incoming command and drops the one it had', () {
      _says('`merge` keeps the incoming command and drops the one it had');
      final device = FakeDevice();
      var end = '';
      _zone((async) {
        final player = Player(device)
          ..resume()
          ..pause();
        async.elapse(ms(300));
        end = '${player.currentState.runtimeType}';
      });
      expect(device.heard, ['pause at 0 ms']);
      expect(end, 'Paused');
    });

    test('commands that build on each other are merged by adding them up', () {
      _says('are merged by adding them up, not by replacing');
      final sought = <String>[];
      _zone((async) {
        final bench = Bench();
        final seek = bench.accumulate<int, int, void>(
          (ctx, seconds) async => sought.add('$seconds s further on'),
          merge: (accumulated, incoming) => accumulated + incoming,
          policy: AccumulationPolicy.adjacent,
        );
        bench.busy('busy', 50);
        async.flushMicrotasks();
        seek
          ..add(10)
          ..add(10)
          ..add(10);
        async.elapse(ms(100));
      });
      expect(sought, ['30 s further on']);
    });

    test(
        'under adjacent a job of another kind between two commands is a '
        'boundary', () {
      _says('a job of another kind added between two commands is a boundary '
          'and the merging stops there');
      final device = FakeDevice();
      _zone((async) {
        BusyPlayer(device, device.note)
          ..busy()
          ..resume()
          ..chime()
          ..pause();
        async.elapse(ms(1000));
      });
      expect(
        device.heard,
        ['resume at 50 ms', 'chime at 150 ms', 'pause at 150 ms'],
      );
    });

    test('under join the resume would be dropped and the pause left alone', () {
      _says('`join` joins the group where it stands, and here that would '
          'drop the `resume` the user tapped and leave the device with the '
          '`pause` alone');
      final device = FakeDevice();
      _zone((async) {
        JoiningPlayer(device)
          ..busy()
          ..resume()
          ..chime()
          ..pause();
        async.elapse(ms(1000));
      });
      expect(device.heard, ['pause at 50 ms', 'chime at 150 ms']);
    });

    test('Policy.replace does not help two jobs that share no key', () {
      _says('`Policy.replace` does not help: it removes jobs with the same '
          'key, and these two do not share one');
      final run = _tap(
        (device) => KeyedPlayer(device, Policy.replace, oneKey: false),
        (c) => c.resume(),
        (c) => c.pause(),
      );
      expect(run.device.heard, ['pause at 0 ms', 'resume at 100 ms']);
    });

    test('removing and adding puts the command at the tail, on a new job', () {
      _says('the command ends up at the tail, behind whatever was queued '
          'between');
      _says('this way a new job has to be built');
      _says('keeping it means holding the command outside the job, where '
          'the job reads it when it starts, and that is what an accumulator '
          'does for its job');
      final device = FakeDevice();
      final seen = <String>[];
      _zone((async) {
        final transport = Transport(device)..pause();
        async.flushMicrotasks();
        final first = transport.resume();
        transport.chime();
        seen.add('${transport.queued}');
        final second = transport.resume();
        seen
          ..add('${transport.queued}')
          ..add('same job: ${identical(first, second)}, the first '
              '${first.outcome}');
        async.elapse(ms(1000));
      });
      expect(seen, [
        '[Command.resume, chime]',
        '[chime, Command.resume]',
        'same job: false, the first Cancelled(manual)',
      ]);
      expect(device.heard, ['pause at 0 ms', 'resume at 150 ms']);
    });

    test('the queue never touches the running job', () {
      _says('a `pause` that has already started runs to its end whatever is '
          'removed behind it');
      final device = FakeDevice();
      final seen = <String>[];
      _zone((async) {
        final transport = Transport(device);
        final pausing = transport.pause();
        async.elapse(ms(10));
        transport.resume();
        async.elapse(ms(1000));
        seen
          ..add('${pausing.outcome}')
          ..add('${transport.currentState.runtimeType}');
      });
      expect(seen, ['Done(null)', 'Playing']);
      expect(device.heard, ['pause at 0 ms', 'resume at 100 ms']);
    });

    test('cancelAll() clears the whole queue and cancels the current job', () {
      _says('reach for `cancelAll()` — it clears the whole queue and cancels '
          'the current job');
      final device = FakeDevice();
      final seen = <String>[];
      _zone((async) {
        final transport = Transport(device);
        final pausing = transport.pause();
        async.elapse(ms(10));
        final chime = transport.chime();
        final resuming = transport.resume();
        transport.cancelAll().ignore();
        async.elapse(ms(1000));
        seen.addAll([
          '${pausing.outcome}',
          '${chime.outcome}',
          '${resuming.outcome}',
          '${transport.currentState.runtimeType}',
        ]);
      });
      expect(seen, [
        'Cancelled(manual)',
        'Cancelled(manual)',
        'Cancelled(manual)',
        'Paused',
      ]);
      expect(device.heard, ['pause at 0 ms']);
    });

    test('one key and Policy.restart cancel the running command as well', () {
      _says('or give both commands one key and `Policy.restart`');
      final device = FakeDevice();
      final seen = <String>[];
      _zone((async) {
        final player = KeyedPlayer(device, Policy.restart, oneKey: true);
        final pausing = player.pause();
        async.elapse(ms(10));
        final resuming = player.resume();
        async.elapse(ms(1000));
        seen.addAll([
          '${pausing.outcome}',
          '${resuming.outcome}',
          '${player.currentState.runtimeType}',
        ]);
      });
      expect(seen, ['Cancelled(replaced)', 'Done(null)', 'Playing']);
    });

    test('removeWhere skips a protected job unless force is given', () {
      _says('`removeWhere` skips jobs created with `cancellable: false` '
          'unless `force: true` is given');
      final device = FakeDevice();
      final seen = <String>[];
      _zone((async) {
        final transport = Transport(device)..pause();
        async.elapse(ms(10));
        final guarded = transport.pause(cancellable: false);
        transport.resume();
        seen
          ..add('${transport.queued}, ${guarded.outcome}')
          ..add('removed ${transport.removePauses(force: true)}, '
              '${guarded.outcome}');
      });
      expect(seen, [
        '[Command.pause, Command.resume], null',
        'removed 1, Cancelled(manual)',
      ]);
    });
  });

  group('Choosing when a group is ready', () {
    /// One event, a second 100 ms later, and a third on its own at 1150 ms.
    List<String> twoAndOne(AccumulationTiming timing) {
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: timing)..add('1');
        async.elapse(ms(100));
        a.add('2');
        async.elapse(ms(1050));
        a.add('3');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });

      return seen;
    }

    test('the table: debounce', () {
      _says('| The first group is ready | after `duration` with no new event '
          '| at once | after `duration` |');
      _says('| An addition | restarts the timer | does not extend the timer '
          '| does not extend the timer |');
      expect(twoAndOne(_debounce(200)), [
        'a[1, 2] at 300 ms',
        'a[3] at 1350 ms',
      ]);
    });

    test('the table: throttle', () {
      _says('| The wait is measured from | the last accepted event | the '
          'previous actual start | the previous start, or the moment the '
          'group appeared |');
      expect(twoAndOne(_throttle(200)), [
        'a[1] at 0 ms',
        'a[2] at 200 ms',
        'a[3] at 1150 ms',
      ]);
    });

    test('the table: throttle with startAtOnce false', () {
      expect(twoAndOne(_throttle(200, startAtOnce: false)), [
        'a[1, 2] at 200 ms',
        'a[3] at 1350 ms',
      ]);
    });

    test('a 200 ms window with events at 0, 60 and 120 is ready at 320', () {
      _says('With a 200 ms window, events at 0, 60 and 120 ms make the group '
          'ready at 320 ms');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _debounce(200))..add('1');
        async.elapse(ms(60));
        a.add('2');
        async.elapse(ms(60));
        a.add('3');
        async.elapse(ms(199));
        seen.add('at 319: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 320: ${bench.ran}');
      });
      expect(seen, ['at 319: []', 'at 320: [a[1, 2, 3] at 320 ms]']);
    });

    test('an addition restarts the timer even when merge changes nothing', () {
      _says('Every addition restarts the timer, even when `merge` returns an '
          'unchanged value');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.accumulate<int, String, void>(
          (ctx, value) async => bench.ran.add('kept $value at ${now()} ms'),
          merge: (accumulated, incoming) => accumulated,
          timing: _debounce(200),
        )..add('x');
        async.elapse(ms(150));
        a.add('y');
        async.elapse(ms(199));
        seen.add('at 349: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 350: ${bench.ran}');
      });
      expect(seen, ['at 349: []', 'at 350: [kept x at 350 ms]']);
    });

    test('the timer seals the group while another job is running', () {
      _says('When the timer fires, the group is sealed even if another job '
          'is running');
      _says('`collect` takes its snapshot then, and not again');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _debounce(200));
        bench.busy('busy', 500);
        final first = a.add('1');
        async.elapse(ms(250));
        seen.add('a later event joins: ${identical(first, a.add('2'))}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, [
        'a later event joins: false',
        'busy at 0 ms',
        'a[1] at 500 ms',
        'a[2] at 500 ms',
      ]);
    });

    test('throttle: additions gather and do not extend the interval', () {
      _says('Additions during the interval gather in an open group without '
          'extending the timer');
      _says('queued input is ready without needing another event');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _throttle(200))..add('1');
        async.elapse(ms(50));
        a.add('2');
        async.elapse(ms(100));
        a.add('3');
        async.elapse(ms(49));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran}');
      });
      expect(seen, [
        'at 199: [a[1] at 0 ms]',
        'at 200: [a[1] at 0 ms, a[2, 3] at 200 ms]',
      ]);
    });

    test(
        'throttle: an empty interval creates no job, and the next group '
        'is ready at once', () {
      _says('An interval that passes with no event creates no job, and the '
          'group of the next event is ready at once: the interval is counted '
          'from the previous start, and it has run out.');
      final hears = Hears();
      Solo.observer = hears;
      var timers = -1;
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _throttle(200))..add('1');
        async.elapse(ms(2200));
        timers = async.pendingTimers.length;
        a.add('2');
        async.elapse(ms(1));
        seen.addAll(bench.ran);
      });
      expect(hears.lines.where((line) => line.contains('started')), [
        'a started at 0 ms',
        'a started at 2200 ms',
      ]);
      expect(timers, 0);
      expect(seen, ['a[1] at 0 ms', 'a[2] at 2200 ms']);
    });

    for (final policy in AccumulationPolicy.values) {
      test(
          'startAtOnce false, ${policy.name}: a later event does not push '
          'back a group that waits only for the slot', () {
        _says('is not pushed back by a later event, whatever the policy does '
            'with that event');
        final seen = <String>[];
        _zone((async) {
          final bench = Bench();
          final a = bench.collector(
            'a',
            policy: policy,
            timing: _throttle(200, startAtOnce: false),
          );
          bench.busy('busy', 400);
          a.add('1');
          // The interval is over at 200 ms; the slot is busy until 400 ms.
          async.elapse(ms(300));
          a.add('2');
          async.elapse(ms(1000));
          seen.addAll(bench.ran);
        });
        // An interval started over by the event at 300 ms would end at 500
        // ms.
        expect(seen, ['busy at 0 ms', 'a[1, 2] at 400 ms']);
      });
    }

    test(
        'startAtOnce false: after an empty interval the next group counts a '
        'whole one', () {
      _says('An interval that passes with no event leaves nothing running, '
          'and the next group counts a whole interval from its own '
          'appearance.');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'a',
          timing: _throttle(200, startAtOnce: false),
        )..add('1');
        // The first group starts at 200 ms, and the interval its start
        // renewed is over at 400 ms with nothing written in it.
        async.elapse(ms(1000));
        a.add('2');
        async.elapse(ms(199));
        seen.add('at 1199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 1200: ${bench.ran}');
        async.elapse(ms(100));
        // Written while the interval of the start at 1200 ms still runs:
        // ready when that one ends, not a whole interval later.
        a.add('3');
        async.elapse(ms(1000));
        seen.add('then: ${bench.ran}');
      });
      expect(seen, [
        'at 1199: [a[1] at 200 ms]',
        'at 1200: [a[1] at 200 ms, a[2] at 1200 ms]',
        'then: [a[1] at 200 ms, a[2] at 1200 ms, a[3] at 1400 ms]',
      ]);
    });

    test('startAtOnce false: a group beside a running one starts no interval',
        () {
      _says('a group that appears beside another of the same accumulator, '
          'queued or running, starts none');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'a',
          work: 300,
          timing: _throttle(200, startAtOnce: false),
        )..add('1');
        // The first group starts at 200 ms and runs until 500 ms; the
        // interval its start renewed is over at 400 ms.
        async.elapse(ms(450));
        a.add('2');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      // An interval counted from the appearance at 450 ms would hold the
      // second group until 650 ms.
      expect(seen, ['a[1] at 200 ms', 'a[2] at 500 ms']);
    });

    test('startAtOnce false: a group beside a queued one starts no interval',
        () {
      final seen = <String>[];
      _zone((async) {
        final bench = Bench()..busy('slot', 350);
        final a = bench.collector(
          'a',
          policy: AccumulationPolicy.adjacent,
          timing: _throttle(200, startAtOnce: false),
        )..add('1');
        // The first group has waited its interval out by 200 ms and waits
        // for the slot alone.
        async.elapse(ms(300));
        bench.busy('between', 10);
        a.add('2');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      // An interval started by the second group at 300 ms would hold the
      // first one until 500 ms.
      expect(seen, [
        'slot at 0 ms',
        'a[1] at 350 ms',
        'between at 350 ms',
        'a[2] at 550 ms',
      ]);
    });

    test('starting at once: a burst in one turn is one group', () {
      _says("The log recipe's three lines stay together because they are "
          'written in one turn');
      final api = FakeLogApi();
      _zone((async) {
        LogController(api)
          ..logEvent(const LogEntry('opened'))
          ..logEvent(const LogEntry('loaded'))
          ..logEvent(const LogEntry('shown'));
        async.elapse(ms(3000));
      });
      expect(api.sent, [
        ['opened', 'loaded', 'shown'],
      ]);
    });

    test('starting at once: a burst over two turns is split', () {
      _says('Starting at once has a price when nothing is running');
      _says('what starting at once costs a burst that takes more than one '
          'turn');
      _says('the first event goes on its own and the rest wait out the whole '
          'interval');
      final api = FakeLogApi();
      _zone((async) {
        final logs = LogController(api)..logEvent(const LogEntry('opened'));
        async.flushMicrotasks();
        logs
          ..logEvent(const LogEntry('loaded'))
          ..logEvent(const LogEntry('shown'));
        async.elapse(ms(3000));
      });
      expect(api.sent, [
        ['opened'],
        ['loaded', 'shown'],
      ]);
      expect(api.sentAt, [0, 1000]);
    });

    test('a burst over several turns while a job is running stays together',
        () {
      _says('A burst written while a job of the controller is running stays '
          'together too, however many turns it takes');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _throttle(1000));
        bench.busy('busy', 50);
        for (final event in ['1', '2', '3']) {
          a.add(event);
          async.elapse(ms(10));
        }
        async.elapse(ms(3000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['busy at 0 ms', 'a[1, 2, 3] at 50 ms']);
    });

    test(
        'startAtOnce false: one event waits the whole interval, and a drain '
        'waits with it', () {
      _says('A single event on an idle accumulator is held for the whole '
          'interval, and `close(mode: SoloCloseMode.drain)` waits with it');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final job = bench
            .collector('a', timing: _throttle(1000, startAtOnce: false))
            .add('1');
        async.elapse(ms(100));
        var closedAt = -1;
        bench
            .close(mode: SoloCloseMode.drain)
            .then((_) => closedAt = now())
            .ignore();
        async.elapse(ms(3000));
        seen.add('${job.outcome}, ${bench.ran}, closed at $closedAt ms');
      });
      expect(seen, ['Done(null), [a[1] at 1000 ms], closed at 1000 ms']);
    });

    test('startAtOnce false: a plain close() drops the waiting event', () {
      _says('a plain `close()` drops it');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final job = bench
            .collector('a', timing: _throttle(1000, startAtOnce: false))
            .add('1');
        async.elapse(ms(100));
        bench.close().ignore();
        async.elapse(ms(3000));
        seen.add('${job.outcome}, ${bench.ran}');
      });
      expect(seen, ['Cancelled(closed), []']);
    });

    test('a group refused by its start rule spends no interval', () {
      _says('A group rejected by start rules consumes no throttle interval');
      final seen = <String>[];
      _zone((async) {
        var allowed = false;
        final bench = Bench();
        final a = bench.collector(
          'a',
          timing: _throttle(200),
          canStart: (state) => allowed,
        );
        final refused = a.add('1');
        async.elapse(ms(10));
        seen.add('${refused.outcome}');
        allowed = true;
        a.add('2');
        async.elapse(ms(1));
        seen.addAll(bench.ran);
      });
      expect(seen, ['Cancelled(rules: canStart)', 'a[2] at 10 ms']);
    });

    test('a group cancelled from onStart does spend it', () {
      _says('cancellation from `onStart` does');
      final seen = <String>[];
      _zone((async) {
        final bench = CancelsOnStart();
        final a = bench.collector('a', timing: _throttle(200));
        bench.cancelNext = true;
        final cancelled = a.add('1');
        async.elapse(ms(10));
        seen.add('${cancelled.outcome}');
        a.add('2');
        async.elapse(ms(189));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran}');
      });
      expect(seen, [
        'Cancelled(manual)',
        'at 199: []',
        'at 200: [a[2] at 200 ms]',
      ]);
    });

    test(
        'startAtOnce false: after a refusal the next group counts a full '
        'interval', () {
      _says('so the next group to appear counts a full interval of its own '
          'from the moment it appears');
      final seen = <String>[];
      _zone((async) {
        var allowed = false;
        final bench = Bench();
        final a = bench.collector(
          'a',
          timing: _throttle(200, startAtOnce: false),
          canStart: (state) => allowed,
        );
        final refused = a.add('1');
        async.elapse(ms(199));
        seen.add('at 199: ${refused.outcome}');
        async.elapse(ms(51));
        seen.add('at 250: ${refused.outcome}');
        allowed = true;
        a.add('2');
        async.elapse(ms(199));
        seen.add('at 449: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 450: ${bench.ran}');
      });
      expect(seen, [
        'at 199: null',
        'at 250: Cancelled(rules: canStart)',
        'at 449: []',
        'at 450: [a[2] at 450 ms]',
      ]);
    });

    test(
        'another job holds the slot until 500: the next group starts then, '
        'and the one after at 700', () {
      _says('the next group starts at 500 ms and the one after that cannot '
          'start before 700 ms');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _throttle(200))..add('1');
        async.elapse(ms(10));
        bench.busy('busy', 490);
        async.elapse(ms(10));
        a.add('2');
        async.elapse(ms(490));
        a.add('3');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, [
        'a[1] at 0 ms',
        'busy at 10 ms',
        'a[2] at 500 ms',
        'a[3] at 700 ms',
      ]);
    });

    test(
        'a handler that outlasts the interval lets the next group start as '
        'it ends', () {
      _says('the next group can start as soon as they finish');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', work: 500, timing: _throttle(200))
          ..add('1');
        async.elapse(ms(10));
        a.add('2');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['a[1] at 0 ms', 'a[2] at 500 ms']);
    });

    test('a waiting group stays in queue.jobs, and a ready job passes it', () {
      _says('Waiting groups stay visible in `queue.jobs`');
      _says('The list can therefore be nonempty while no job is running');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        bench.collector('a', timing: _debounce(200)).add('1');
        async.elapse(ms(10));
        seen.add('${bench.queued}, current ${bench.current}');
        bench.busy('ready', 20);
        async.elapse(ms(50));
        seen.add('${bench.ran}, ${bench.queued}, current ${bench.current}');
        async.elapse(ms(500));
        seen.add('${bench.ran}');
      });
      expect(seen, [
        '[a], current null',
        '[ready at 10 ms], [a], current null',
        '[ready at 10 ms, a[1] at 200 ms]',
      ]);
    });

    test('no timing and a zero duration make no timers', () {
      _says('makes groups ready immediately and creates no timers, whatever '
          '`startAtOnce` says');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        bench.collector('plain').add('1');
        bench
            .collector(
              'zero',
              timing: AccumulationTiming.throttle(
                Duration.zero,
                startAtOnce: false,
              ),
            )
            .add('1');
        bench
            .collector(
              'none',
              timing: AccumulationTiming.debounce(Duration.zero),
            )
            .add('1');
        seen.add('${async.pendingTimers.length} timers');
        async.flushMicrotasks();
        seen.addAll(bench.ran);
      });
      expect(seen, [
        '0 timers',
        'plain[1] at 0 ms',
        'zero[1] at 0 ms',
        'none[1] at 0 ms',
      ]);
    });

    test('a negative duration throws ArgumentError', () {
      _says('Negative durations throw `ArgumentError`');
      expect(() => AccumulationTiming.debounce(ms(-1)), throwsArgumentError);
      expect(() => AccumulationTiming.throttle(ms(-1)), throwsArgumentError);
      expect(
        () => AccumulationTiming.throttle(ms(-1), startAtOnce: false),
        throwsArgumentError,
      );
    });

    test('one timing for two accumulators, an interval for each', () {
      _says('each accumulator has its own groups and throttle interval');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final shared = _throttle(200);
        bench.collector('one', timing: shared).add('1');
        async.elapse(ms(10));
        bench.collector('two', timing: shared).add('1');
        async.elapse(ms(10));
        seen.addAll(bench.ran);
      });
      expect(seen, ['one[1] at 0 ms', 'two[1] at 10 ms']);
    });

    test('an event processed before the debounce callback restarts the timer',
        () {
      _says('an event processed before a debounce callback can restart the '
          'timer');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _debounce(200));
        // Set before the group's own timer, so it fires first at 200 ms.
        Timer(ms(200), () => a.add('before'));
        a.add('1');
        async.elapse(ms(200));
        seen.add('at 200: ${bench.ran}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['at 200: []', 'a[1, before] at 400 ms']);
    });

    test('an event processed after it belongs to a new group', () {
      _says('an event processed after it belongs to a new group');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('a', timing: _debounce(200))..add('1');
        // Set after the group's own timer, so it fires second at 200 ms.
        Timer(ms(200), () => a.add('after'));
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['a[1] at 200 ms', 'a[after] at 400 ms']);
    });
  });

  group('Choosing where events join', () {
    test('the three lines of the page give one handle on its controller', () {
      final api = FakeSettingsApi();
      var one = false;
      _zone((async) {
        final jobs = threeCalls(SettingsController(api, _off));
        one = identical(jobs[0], jobs[1]);
        async.elapse(ms(1000));
      });
      expect(one, isTrue);
      expect(api.loads, 1);
      expect(api.sent, ['notifications: false, theme: dark, language: ru']);
    });

    /// A1, then B, then A2, while a job holds the slot: the queue after
    /// the additions, the handle for A2 and what ran.
    List<String> threeAdditions(AccumulationPolicy policy) {
      final seen = <String>[];
      final hears = Hears();
      Solo.observer = hears;
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', policy: policy);
        bench.busy('current', 100);
        async.flushMicrotasks();
        final a1 = a.add('1');
        bench.busy('B', 10);
        final a2 = a.add('2');
        seen
          ..add('${bench.queued}')
          ..add(identical(a1, a2) ? "A1's job" : 'a new job');
        async.elapse(ms(1000));
        seen.add('${bench.ran.skip(1).toList()}');
      });
      Solo.observer = null;
      seen.add('${hears.lines.where((line) => line.contains('Cancelled'))}');

      return seen;
    }

    test('the table: adjacent', () {
      _says('| `adjacent` | `[A1, B, A2]` | A new job |');
      expect(threeAdditions(AccumulationPolicy.adjacent), [
        '[A, B, A]',
        'a new job',
        '[A[1] at 100 ms, B at 100 ms, A[2] at 110 ms]',
        '()',
      ]);
    });

    test('the table: replace', () {
      _says("| `replace` | `[B, A(A1 + A2)]` | A1's existing job, moved "
          'behind B |');
      expect(threeAdditions(AccumulationPolicy.replace), [
        '[B, A]',
        "A1's job",
        '[B at 100 ms, A[1, 2] at 110 ms]',
        '()',
      ]);
    });

    test('the table: join, the default', () {
      _says("| `join` (default) | `[A(A1 + A2), B]` | A1's existing job |");
      expect(threeAdditions(AccumulationPolicy.join), [
        '[A, B]',
        "A1's job",
        '[A[1, 2] at 100 ms, B at 100 ms]',
        '()',
      ]);
      // And with no policy named, where the engine's own default decides.
      for (final merging in [false, true]) {
        final seen = <String>[];
        _zone((async) {
          final defaults = Defaults()..busy('current', 100);
          async.flushMicrotasks();
          final a = merging ? defaults.last : defaults.items;
          final a1 = a.add('1');
          defaults.busy('B', 10);
          seen.add('${identical(a1, a.add('2'))}, ${defaults.queued}');
        });
        expect(
          seen,
          ['true, [A, B]'],
          reason: merging ? 'accumulate' : 'collect',
        );
      }
    });

    test('a ready B passes A while A waits for timing', () {
      _says('a ready B can pass A while A waits for timing');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', timing: _debounce(200))..add('1');
        bench.busy('B', 10);
        a.add('2');
        seen.add('${bench.queued}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['[A, B]', 'B at 0 ms', 'A[1, 2] at 200 ms']);
    });

    test(
        'under adjacent and a throttle an entry behind another job costs a '
        'second request an interval later', () {
      _says('`join` is the default so that a group does not depend on what '
          'else is queued');
      _says('under `adjacent` it would start a second group behind that job, '
          'and a throttle would hold that group for another interval');
      List<String> run(AccumulationPolicy policy) {
        final seen = <String>[];
        _zone((async) {
          final bench = Bench();
          final a = bench.collector(
            'A',
            policy: policy,
            timing: _throttle(1000),
          );
          bench.busy('current', 100);
          async.flushMicrotasks();
          a.add('1');
          bench.busy('B', 10);
          a.add('2');
          async.elapse(ms(5000));
          seen.addAll(bench.ran.skip(1));
        });

        return seen;
      }

      expect(run(AccumulationPolicy.adjacent), [
        'A[1] at 100 ms',
        'B at 100 ms',
        'A[2] at 1100 ms',
      ]);
      expect(run(AccumulationPolicy.join), [
        'A[1, 2] at 100 ms',
        'B at 100 ms',
      ]);
    });

    test('once B has run, a waiting A is the tail again for adjacent', () {
      _says('If B has already run, a waiting A may again be at the tail, so '
          'a later event can join it with `adjacent`');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          policy: AccumulationPolicy.adjacent,
          timing: _debounce(200),
        );
        final a1 = a.add('1');
        bench.busy('B', 10);
        async.elapse(ms(50));
        seen.add('joined: ${identical(a1, a.add('2'))}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['joined: true', 'B at 0 ms', 'A[1, 2] at 250 ms']);
    });

    test(
        'groups already separate are not combined when the job between '
        'them goes', () {
      _says('Already separate groups are never combined retroactively');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', policy: AccumulationPolicy.adjacent);
        bench.busy('current', 100);
        async.flushMicrotasks();
        a.add('1');
        final between = bench.busy('B', 10);
        final a2 = a.add('2');
        between.cancel().ignore();
        seen
          ..add('${bench.queued}')
          ..add('a third joins the tail: ${identical(a2, a.add('3'))}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran.skip(1));
      });
      expect(seen, [
        '[A, A]',
        'a third joins the tail: true',
        'A[1] at 100 ms',
        'A[2, 3] at 100 ms',
      ]);
    });

    for (final policy in AccumulationPolicy.values) {
      test('a sealed debounce group takes no event under ${policy.name}', () {
        _says('A sealed debounce group is ineligible for all three policies');
        final seen = <String>[];
        _zone((async) {
          final bench = Bench();
          final a = bench.collector(
            'A',
            policy: policy,
            timing: _debounce(200),
          );
          bench.busy('current', 500);
          async.flushMicrotasks();
          final a1 = a.add('1');
          async.elapse(ms(250));
          seen.add('joined: ${identical(a1, a.add('2'))}, ${bench.queued}');
        });
        expect(seen, ['joined: false, [A, A]']);
      });
    }

    test(
        'replace moves the job, keeps the handle and the events, and says '
        'so in Solo.debug', () {
      _says("`Solo.debug`, the engine's own trace from "
          '[Logs](errors.md#logs) on the errors page, says '
          '`move <job> to the tail`');
      _says('a group that is already at the tail keeps the place it has');
      final seen = <String>[];
      final debug = <String>[];
      final hears = Hears();
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', policy: AccumulationPolicy.replace);
        bench.busy('current', 100);
        async.flushMicrotasks();
        final a1 = a.add('1');
        bench.busy('B', 10);
        Solo.observer = hears;
        Solo.debug = debug.add;
        final a2 = a.add('2');
        seen.add('${bench.queued}');
        final a3 = a.add('3');
        Solo.debug = null;
        Solo.observer = null;
        seen
          ..add('${bench.queued}')
          ..add('one handle: ${identical(a1, a2) && identical(a2, a3)}');
        async.elapse(ms(1000));
        seen.add(bench.ran.last);
      });
      expect(seen, [
        '[B, A]',
        '[B, A]',
        'one handle: true',
        'A[1, 2, 3] at 110 ms',
      ]);
      expect(debug, ['move Job(A) to the tail', 'move Job(A) to the tail']);
      _says('there is no observer event, because no job started or finished');
      expect(hears.lines, isEmpty);
    });

    test('the move starts a fresh debounce window', () {
      _says('The move starts a fresh debounce window and preserves the '
          "accumulator's throttle interval");
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          policy: AccumulationPolicy.replace,
          timing: _debounce(200),
        )..add('1');
        async.elapse(ms(150));
        bench.busy('B', 10);
        a.add('2');
        async.elapse(ms(199));
        seen.add('at 349: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 350: ${bench.ran}');
      });
      expect(seen, [
        'at 349: [B at 150 ms]',
        'at 350: [B at 150 ms, A[1, 2] at 350 ms]',
      ]);
    });

    test('the move leaves the throttle interval where it was', () {
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          policy: AccumulationPolicy.replace,
          timing: _throttle(200),
        )..add('1');
        async.elapse(ms(50));
        a.add('2');
        bench.busy('B', 10);
        async.elapse(ms(100));
        a.add('3');
        async.elapse(ms(49));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran.last}');
      });
      expect(seen, [
        'at 199: [A[1] at 0 ms, B at 50 ms]',
        'at 200: A[2, 3] at 200 ms',
      ]);
    });

    test('a group with cancellable false is moved like any other', () {
      _says('a move is not a removal, and the flag has nothing to refuse');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          policy: AccumulationPolicy.replace,
          cancellable: false,
        );
        bench.busy('current', 100);
        async.flushMicrotasks();
        final a1 = a.add('1');
        bench.busy('B', 10);
        seen.add('moved: ${identical(a1, a.add('2'))}, ${bench.queued}');
      });
      expect(seen, ['moved: true, [B, A]']);
    });

    test('a running group is never moved', () {
      _says('A running group is never moved: it stops accepting events when '
          'the queue takes it');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          policy: AccumulationPolicy.replace,
          work: 100,
        );
        final a1 = a.add('1');
        async.elapse(ms(10));
        seen.add('joined: ${identical(a1, a.add('2'))}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran);
      });
      expect(seen, ['joined: false', 'A[1] at 0 ms', 'A[2] at 100 ms']);
    });

    test('two accumulators with one key stay separate', () {
      _says('Two accumulators with the same `key` remain separate');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench()..busy('current', 100);
        async.flushMicrotasks();
        final one = bench.collector('one', key: 'k').add('1');
        final two = bench.collector('two', key: 'k').add('1');
        seen.add('one job: ${identical(one, two)}, ${bench.queued}');
      });
      expect(seen, ['one job: false, [k, k]']);
    });

    test('the key still labels their jobs for the ordinary policies', () {
      _says("The key still labels their jobs for the ordinary queue's "
          'search and policies');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench()..busy('current', 100);
        async.flushMicrotasks();
        final one = bench.collector('one', key: 'k').add('1');
        final two = bench.collector('two', key: 'k').add('1');
        bench.run<int, void>(
          key: 'k',
          policy: Policy.restart,
          (ctx) async {},
        );
        seen.add('${one.outcome}, ${two.outcome}, ${bench.queued}');
      });
      expect(seen, ['Cancelled(replaced), Cancelled(replaced), [k]']);
    });

    test('a new accumulator on every call joins nothing', () {
      _says('Creating a new accumulator on every call prevents events from '
          'joining an existing one');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench()..busy('current', 100);
        async.flushMicrotasks();
        final first = bench.collector('fresh').add('1');
        final second = bench.collector('fresh').add('2');
        seen.add('joined: ${identical(first, second)}');
        async.elapse(ms(1000));
        seen.addAll(bench.ran.skip(1));
      });
      expect(seen, [
        'joined: false',
        'fresh[1] at 100 ms',
        'fresh[2] at 100 ms',
      ]);
    });
  });

  group('Start, cancellation and errors', () {
    test('the block of the page prints what the page quotes', () {
      final api = FakeLogApi();
      _zone((async) {
        oneHandle(LogController(api)).ignore();
        async.elapse(ms(3000));
      });
      expect(_printed.join('\n'), _quotes()[11]);
      expect(api.sent, isEmpty);
    });

    test('events added from canStart and onStart go to a later group', () {
      _says('before `canStart` and `onStart`. Events added from either '
          'callback go to a later group');
      final seen = <String>[];
      _zone((async) {
        final hooks = AddsFromHooks();
        hooks.items.add('1');
        async.elapse(ms(100));
        seen.addAll(hooks.ran);
      });
      expect(seen, ['[1]', '[from canStart, from onStart]']);
    });

    test('the handler runs with the working type it was given', () {
      _says('The handler runs with the configured working type and rules, '
          "and the group's job is an ordinary job to the queue");
      final seen = <String>[];
      _zone((async) {
        final typed = Typed();
        final early = typed.items.add('early');
        async.elapse(ms(10));
        seen.add('${early.outcome}, ${typed.ran}');
        typed.turnOn();
        final group = typed.items.add('a');
        typed.items.add('b');
        async.elapse(ms(10));
        seen
          ..add('${group.outcome}, ${typed.ran}')
          ..add('${(typed.currentState as On).count}');
      });
      expect(seen, [
        'Cancelled(rules: is not On), []',
        'Done(null), [[a, b] on 0]',
        '2',
      ]);
    });

    test('an accumulator creates no job until the first event', () {
      _says('An accumulator creates no job until the first event');
      final hears = Hears();
      Solo.observer = hears;
      final seen = <String>[];
      _zone((async) {
        final bench = Bench()..collector('A', timing: _throttle(100));
        async.elapse(ms(1000));
        seen.add('${bench.queued}, ${async.pendingTimers.length} timers');
      });
      expect(seen, ['[], 0 timers']);
      expect(hears.lines, isEmpty);
    });

    test('without timing each event that finds no group starts a job', () {
      _says('each event starts a separate job');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A');
        for (final event in ['1', '2', '3']) {
          a.add(event);
          async.elapse(ms(10));
        }
        seen.addAll(bench.ran);
      });
      expect(seen, ['A[1] at 0 ms', 'A[2] at 10 ms', 'A[3] at 20 ms']);
    });

    for (final policy in AccumulationPolicy.values) {
      test(
          'cancelling the handle cancels the whole group under '
          '${policy.name}', () {
        _says('Additions to one group share one handle, result and '
            'cancellation under every policy');
        final seen = <String>[];
        _zone((async) {
          final bench = Bench();
          final a = bench.collector('A', policy: policy);
          bench.busy('current', 100);
          async.flushMicrotasks();
          final first = a.add('1');
          final second = a.add('2');
          second.cancel().ignore();
          async.elapse(ms(1000));
          seen.add('${first.outcome}, ${bench.ran.skip(1).toList()}');
        });
        expect(seen, ['Cancelled(manual), []']);
      });
    }

    test('the handle outlives the move of replace', () {
      _says('cancelling it cancels the group wherever the job now stands');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', policy: AccumulationPolicy.replace);
        bench.busy('current', 100);
        async.flushMicrotasks();
        final first = a.add('1');
        bench.busy('B', 10);
        a.add('2');
        first.cancel().ignore();
        seen.add('${first.outcome}, ${bench.queued}');
        async.elapse(ms(1000));
        seen.add('${bench.ran.skip(1).toList()}');
      });
      expect(seen, ['Cancelled(manual), [B]', '[B at 100 ms]']);
    });

    /// An accumulator whose `merge` does what [mode] says on its way.
    ({List<String> seen, List<String> errors}) merging(String mode) {
      final seen = <String>[];
      final errors = _zone((async) {
        final bench = Bench();
        late final SoloAccumulator<String, void> a;
        var armed = false;
        a = bench.accumulate<int, String, void>(
          (ctx, value) async => bench.ran.add('a[$value] at ${now()} ms'),
          merge: (accumulated, incoming) {
            if (armed) {
              switch (mode) {
                case 'throws':
                  throw StateError('merge failed');
                case 'adds':
                  a.add('again');
                case 'cancels':
                  bench.cancelAll().ignore();
              }
            }

            return '$accumulated+$incoming';
          },
          timing: _debounce(200),
        );
        final group = a.add('1');
        async.elapse(ms(150));
        armed = true;
        try {
          a.add('2');
          seen.add('add returned');
        } on Object catch (error) {
          seen
            ..add('${error.runtimeType}')
            ..add('$error');
        }
        armed = false;
        seen.add('${group.outcome}, ${bench.queued.length} queued');
        async.elapse(ms(49));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran}');
      });

      return (seen: seen, errors: errors);
    }

    test('a merge that throws leaves the group, its job and its timer', () {
      _says('If it throws, `add` throws the same error and the existing '
          'group, its job and its timer remain unchanged');
      final run = merging('throws');
      expect(run.seen, [
        'StateError',
        'Bad state: merge failed',
        'null, 1 queued',
        'at 199: []',
        'at 200: [a[1] at 200 ms]',
      ]);
      expect(run.errors, isEmpty);
    });

    test('an add from within merge throws StateError', () {
      _says("Calling the same accumulator's `add` from within its `merge` "
          'throws `StateError`');
      expect(merging('adds').seen, [
        'StateError',
        'Bad state: Cannot add while this accumulator is merging',
        'null, 1 queued',
        'at 199: []',
        'at 200: [a[1] at 200 ms]',
      ]);
    });

    test('a merge that removes its own group is not committed', () {
      _says('The engine also checks that the target group is still eligible '
          'after the callback, before committing the result');
      expect(merging('cancels').seen, [
        'StateError',
        'Bad state: The accumulation group changed during merge',
        'Cancelled(manual), 0 queued',
        'at 199: []',
        'at 200: []',
      ]);
    });

    test('a start rule that turns the job down cancels the whole group', () {
      _says('A start rule that turns the job down cancels everything the '
          'group has accumulated');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', canStart: (state) => false);
        final group = a.add('1');
        a
          ..add('2')
          ..add('3');
        async.elapse(ms(10));
        seen.add('${group.outcome}, ${bench.ran}');
      });
      expect(seen, ['Cancelled(rules: canStart), []']);
    });

    test('an accepted cancellation wins over the value that comes later', () {
      _says('accepted cancellation still takes precedence over a later value '
          'or error');
      final api = FakeLogApi();
      final seen = <String>[];
      _zone((async) {
        final logs = LogController(api);
        final group = logs.logEvent(const LogEntry('one'));
        async.elapse(ms(50));
        group.cancel().ignore();
        async.elapse(ms(100));
        seen.add('${group.outcome}, counter ${logs.currentState}');
      });
      expect(seen, ['Cancelled(manual), counter 0']);
      expect(api.sent, [
        ['one'],
      ]);
    });

    test('cancelling a queued debounce group removes its timer', () {
      _says('Cancelling a queued debounce group removes its timer');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final group = bench.collector('A', timing: _debounce(200)).add('1');
        seen.add('${async.pendingTimers.length}');
        group.cancel().ignore();
        seen.add('${async.pendingTimers.length}');
      });
      expect(seen, ['1', '0']);
    });

    test('clearing throttle groups keeps the interval already started', () {
      _says('Removing or clearing throttle groups preserves an already '
          'started interval, so adding another event cannot bypass the limit');
      _says('That timer expires once');
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector('A', timing: _throttle(200))..add('1');
        async.elapse(ms(50));
        final waiting = a.add('2');
        bench.queue.clear();
        seen.add('${waiting.outcome}, ${async.pendingTimers.length} timer');
        a.add('3');
        async.elapse(ms(149));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran.last}');
        async.elapse(ms(1000));
        seen.add('${async.pendingTimers.length} timers');
      });
      expect(seen, [
        'Cancelled(manual), 1 timer',
        'at 199: [A[1] at 0 ms]',
        'at 200: A[3] at 200 ms',
        '0 timers',
      ]);
    });

    test(
        'startAtOnce false: a group removed in its interval leaves what is '
        'left of it', () {
      final seen = <String>[];
      _zone((async) {
        final bench = Bench();
        final a = bench.collector(
          'A',
          timing: _throttle(200, startAtOnce: false),
        );
        final removed = a.add('1');
        async.elapse(ms(150));
        removed.cancel().ignore();
        a.add('2');
        async.elapse(ms(49));
        seen.add('at 199: ${bench.ran}');
        async.elapse(ms(1));
        seen.add('at 200: ${bench.ran}');
      });
      expect(seen, ['at 199: []', 'at 200: [A[2] at 200 ms]']);
    });

    /// A debounce group, a throttle group and an accumulated value waiting
    /// behind a running batch when the controller is closed in [mode].
    List<String> closing(SoloCloseMode mode) {
      final seen = <String>[];
      var merges = 0;
      _zone((async) {
        final bench = Bench();
        final debounced = bench.collector('deb', timing: _debounce(200));
        final throttled =
            bench.collector('thr', timing: _throttle(300), work: 50);
        final merged = bench.accumulate<int, String, void>(
          (ctx, value) async => bench.ran.add('acc[$value] at ${now()} ms'),
          merge: (accumulated, incoming) {
            merges += 1;
            return incoming;
          },
          timing: _debounce(200),
        );
        throttled.add('1');
        async.elapse(ms(10));
        final d = debounced.add('1');
        final t = throttled.add('2');
        final m = merged.add('1');
        var closedAt = -1;
        bench.close(mode: mode).then((_) => closedAt = now()).ignore();
        // One timer is the running handler's own, not the engine's.
        seen.add('${async.pendingTimers.length - 1} engine timers, '
            '${bench.queued.length} queued');
        final late = merged.add('2');
        seen.add('an add after: ${late.outcome}, the same job '
            '${identical(late, m)}, $merges merges');
        async.elapse(ms(1000));
        seen
          ..add('${d.outcome}, ${t.outcome}, ${m.outcome}')
          ..add('${bench.ran.skip(1).toList()}')
          ..add('closed at $closedAt ms');
      });

      return seen;
    }

    test('close() cancels the timers and drops the queued groups', () {
      _says('`close()` cancels every timing timer, drops queued groups and '
          'cancels or waits for the running job under the usual rules');
      _says('its job, the one handle every addition to it got, completes '
          'with `Cancelled(closed)`');
      expect(closing(SoloCloseMode.cancel), [
        '0 engine timers, 0 queued',
        'an add after: Cancelled(closed), the same job false, 0 merges',
        'Cancelled(closed), Cancelled(closed), Cancelled(closed)',
        '[]',
        'closed at 50 ms',
      ]);
    });

    test('a draining close waits the windows out and runs what is queued', () {
      _says('it waits the accumulation window out and runs the groups '
          'already queued');
      _says('Neither mode takes anything new');
      expect(closing(SoloCloseMode.drain), [
        '3 engine timers, 3 queued',
        'an add after: Cancelled(closed), the same job false, 0 merges',
        'Done(null), Done(null), Done(null)',
        '[deb[1] at 210 ms, acc[1] at 210 ms, thr[2] at 300 ms]',
        'closed at 350 ms',
      ]);
    });
  });
}

extension on Job<Object?> {
  /// The methods of the page declare `Job<T>`; whether the job still waits
  /// in the queue is on the `SoloJob<T>` the controller made.
  bool get isQueued => (this as SoloJob<Object?>).isQueued;
}
