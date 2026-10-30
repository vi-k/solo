#!/usr/bin/env python3
"""Builds runnable scenarios from packages/async_job/doc/riverpod-and-bloc.md.

Every snippet is copied byte-identical out of the markdown and wrapped in a
runnable file: fakes above it, a driver below it. That is what keeps the
page honest -- the code in it is the code that ran, against the riverpod,
bloc, http and dio a reader resolves today.

Usage, from the repository root:

    python3 tool/adapter_snippets.py [workdir]

The default workdir is /tmp/adapters-check. It creates one package,
adapters_check, with a path dependency on packages/async_job. Then:

    dart pub get
    dart analyze --fatal-infos bin/v
    dart run bin/v/provider_answer.dart   # and so on

The riverpod and bloc drivers run on virtual time, under the runner of
tool/doc_snippets.py and for its reason: `bloc.close()` waits for futures of
the root zone, and a bare `fakeAsync` never lets them complete. The request
driver runs on real time against a raw socket on loopback, and its order is
held by awaits, not by margins of time.

Blocks are addressed as in tool/doc_blocks.py, by section and by the name a
block declares, with one step more: a `###` subsection is part of the key.
The page puts a first attempt and its answer in one section under one class
name, and the subsection is what tells them apart --
'a-handler-that-restarts/the-first-attempt/SearchBloc'.

Every `dart` block of the page is built: the script stops if one of them
went into no driver.
"""
import os
import re
import sys

import doc_blocks

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/adapters-check'
DOC = os.path.join(REPO, 'packages', 'async_job', 'doc', 'riverpod-and-bloc.md')

# The majors the page names. The bench resolves the newest of each, on the
# SDK of the job; the floor of async_job is not what it proves.
PUBSPEC = """name: adapters_check
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  async_job:
    path: {async_job}
  bloc: ^9.0.0
  bloc_concurrency: ^0.3.0
  dio: ^5.9.0
  fake_async: ^1.3.1
  http: ^1.5.0
  riverpod: ^3.0.0

dev_dependencies:
  lints: ^5.1.1
""".format(async_job=os.path.join(REPO, 'packages', 'async_job'))

# The rules of async_job itself: a fragment that passes here would pass
# inside the package.
OPTIONS = 'include: async_job_rules.yaml\n'


def page_blocks(text):
    """{section/[subsection/]name: source}, a repeated key poisoned."""
    found = {}
    for section, body in doc_blocks.sections(text):
        for index, part in enumerate(re.split(r'\n### ', body)):
            prefix = section
            if index:
                prefix += '/' + doc_blocks.slug(part.split('\n')[0])
            # One subsection as a page of one section named 'x'.
            inner = doc_blocks.blocks(
                '\n## x\n' + part, 'dart', doc_blocks.DECLARES['dart'])
            for key, block in inner.items():
                full = prefix + '/' + key.split('/', 1)[1]
                found[full] = doc_blocks.POISONED if full in found else block
    return found


class Blocks(dict):
    """The blocks of the page, and which of them a driver has taken."""

    def __init__(self, found):
        super().__init__(found)
        self.taken = set()

    def __getitem__(self, key):
        self.taken.add(key)
        block = super().__getitem__(key)
        assert block is not doc_blocks.POISONED, f'{key} is declared twice'
        return block

    def unbuilt(self):
        """The first line of every block no driver took by any of its keys."""
        built = {id(dict.__getitem__(self, key)) for key in self.taken}
        left = {}
        for key in self:
            source = dict.__getitem__(self, key)
            if id(source) not in built:
                left[id(source)] = source.split('\n')[0]
        return sorted(left.values())


snips = Blocks(page_blocks(open(DOC).read()))
if ROOT == '--list':
    for key in snips:
        poisoned = dict.__getitem__(snips, key) is doc_blocks.POISONED
        print(key, '(declared twice)' if poisoned else '')
    sys.exit(0)


def replaced(source, old, new, count=1):
    """source with old replaced, failing if old is not there count times."""
    assert source.count(old) == count, f'expected {count}x: {old!r}'
    return source.replace(old, new)


PROVIDER = 'a-provider-that-is-gone'
NOTIFIER = 'a-notifier-that-starts-again'
HANDLER = 'a-handler-that-restarts'
REQUEST = 'a-request-to-abort'

READ_ROWS = snips[f'{PROVIDER}/readRows']

# The same database on every page of the core: it prints when it opens,
# reads a page and closes. Opening takes 10 ms and a page 20 ms, and the
# drivers act between those marks, never on one: two events on the same
# millisecond of virtual time run in an order real time would not keep.
DATABASE = '''
int pagesRead = 0;

final class Database {
  Database._(this.query);

  final String query;

  static Future<Database> open(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('database opened for $query');
    return Database._(query);
  }

  Future<String> readPage(int page) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    print('$query: page $page read');
    pagesRead++;
    return '$query: page $page';
  }

  void close() => print('database for $query closed');
}

Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
'''

# The `main` of every virtual-time driver; the driver itself is `scenario`.
# The clock is elapsed from outside the fake zone, with a turn of the real
# event loop between two steps: a future of `dart:async` itself, the one a
# broadcast subscription returns from `cancel` for one, belongs to the root
# zone and completes its listeners there, and `bloc.close()` waits for it.
# The same runner as in tool/doc_snippets.py, which says more.
RUNNER = '''
Future<void> main() async {
  Object? failure;
  StackTrace? failureTrace;
  var ended = false;
  final clock = FakeAsync()
    ..run((clock) {
      Future<void>.sync(scenario).then<void>(
        (_) {
          ended = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          failure = error;
          failureTrace = stackTrace;
          ended = true;
        },
      );
    });
  while (!ended) {
    clock.flushMicrotasks();
    await Future<void>.delayed(Duration.zero);
    if (ended || clock.microtaskCount > 0) {
      continue;
    }
    if (clock.elapsed > const Duration(minutes: 10)) {
      throw StateError('the scenario did not end in ten of its minutes');
    }
    clock.elapse(const Duration(milliseconds: 1));
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureTrace!);
  }
}
'''

RIVERPOD_HEAD = """import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:fake_async/fake_async.dart';
import 'package:riverpod/riverpod.dart';
"""

BLOC_HEAD = """import 'dart:async';

import 'package:async_job/async_job.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:fake_async/fake_async.dart';
"""

FILES = {}

# ----------------------------------------------------------------- provider
# The screen listens to rows('dart') and leaves 20 ms in: the database is
# open by then, and the first page is 10 ms from being read.
SCREEN_LEAVES = '''
Future<void> scenario() async {
  final container = ProviderContainer();
  final screen = container.listen(rows('dart'), (_, _) {});
  await delay(20);
  print('screen left');
  screen.close();
  await delay(200);
  container.dispose();
  require(pagesRead == PAGES, 'pages read: $pagesRead, not PAGES');
}
'''

FILES['provider_first'] = (
    RIVERPOD_HEAD + DATABASE + READ_ROWS
    + snips[f'{PROVIDER}/the-first-attempt/'
            'the-first-attempt-the-job-read']
    + SCREEN_LEAVES.replace('PAGES', '3') + RUNNER)

# A screen another route covers: its listener is paused 20 ms in and
# resumed 40 ms later, after the cancelled job has closed its database.
FILES['provider_second'] = (
    RIVERPOD_HEAD + DATABASE + READ_ROWS
    + snips[f'{PROVIDER}/the-second-attempt/'
            'the-second-attempt-a-paused-sc']
    + '''
Future<void> scenario() async {
  final container = ProviderContainer();
  final screen = container.listen(rows('dart'), (_, _) {});
  await delay(20);
  print('screen covered');
  screen.pause();
  await delay(40);
  print('screen shown');
  screen.resume();
  await delay(400);
  require(pagesRead == 4, 'pages read: $pagesRead, not 1 and then 3');
  require(
    container.read(rows('dart')).value?.length == 3,
    'the second job delivers the rows',
  );
  screen.close();
  container.dispose();
}
''' + RUNNER)

# The answer, then the observer twice: as the page has it, and without its
# filter, which the prose says hears the Cancelled(manual) of the disposal.
OBSERVER = snips[f'{PROVIDER}/cancelling-on-disposal/CrashReports']
UNFILTERED = replaced(
    replaced(OBSERVER, '    if (error is Cancelled) return;\n', ''),
    'CrashReports', 'Unfiltered')

FILES['provider_answer'] = (
    RIVERPOD_HEAD + DATABASE + READ_ROWS
    + snips[f'{PROVIDER}/cancelling-on-disposal/'
            'final-rows-futureprovider-auto']
    + OBSERVER + UNFILTERED
    + '''
final reported = <Object>[];

void report(Object error, StackTrace stackTrace) => reported.add(error);

Future<void> leave(ProviderObserver observer) async {
  final container = ProviderContainer(observers: [observer]);
  final screen = container.listen(rows('dart'), (_, _) {});
  await delay(20);
  print('screen left');
  screen.close();
  await delay(200);
  container.dispose();
}

Future<void> scenario() async {
  await leave(CrashReports());
  require(pagesRead == 1, 'pages read: $pagesRead, not 1');
  require(reported.isEmpty, 'the filter passes the cancellation over');

  await leave(Unfiltered());
  require(
    reported.length == 1 && '${reported.single}' == 'Cancelled(manual)',
    'without the filter the observer hears Cancelled(manual): $reported',
  );

  // A screen that turns to another query leaves its provider to disposal.
  pagesRead = 0;
  final container = ProviderContainer();
  var screen = container.listen(rows('d'), (_, _) {});
  await delay(20);
  screen.close();
  screen = container.listen(rows('da'), (_, _) {});
  await delay(200);
  screen.close();
  container.dispose();
  require(pagesRead == 1 + 3, 'the query left reads one page: $pagesRead');
}
''' + RUNNER)

# ----------------------------------------------------------------- notifier
# A search for 'd', and one for 'da' 15 ms in, while 'd' has its database
# open and reads its first page. Then the same without the check before
# the state is written, which the prose says lets the Cancelled of 'd' in.
SEARCH = snips[f'{NOTIFIER}/Search']
CHECK = ('    // A newer search or the disposal owns the state now.\n'
         '    if (!ref.mounted || !identical(job, _current)) return;\n')
UNCHECKED = replaced(
    replaced(replaced(SEARCH, CHECK, ''), 'Search', 'Unchecked', 3),
    'final search =', 'final unchecked =')

FILES['notifier'] = (
    RIVERPOD_HEAD + DATABASE + READ_ROWS + SEARCH + UNCHECKED
    + '''
Future<List<String>> type<T extends AsyncNotifier<List<String>>>(
  AsyncNotifierProvider<T, List<String>> provider, {
  required void Function(T notifier, String query) search,
  bool quiet = false,
}) async {
  final states = <String>[];
  final container = ProviderContainer();
  final screen = container.listen(provider, (_, next) {
    final state = switch (next) {
      AsyncData(:final value) => 'state: $value',
      AsyncError(:final error) => 'error: $error',
      _ => 'loading',
    };
    states.add(state);
    if (!quiet && next is AsyncData<List<String>>) print(state);
  });
  search(container.read(provider.notifier), 'd');
  await delay(15);
  if (!quiet) print('search: da');
  search(container.read(provider.notifier), 'da');
  await delay(200);
  screen.close();
  container.dispose();
  return states;
}

Future<void> scenario() async {
  final states = await type(
    search,
    search: (notifier, query) => unawaited(notifier.search(query)),
  );
  require(
    !states.any((state) => state.startsWith('error')),
    'no error reaches the state: $states',
  );

  final bare = await type(
    unchecked,
    search: (notifier, query) => unawaited(notifier.search(query)),
    quiet: true,
  );
  require(
    bare.contains('error: Cancelled(manual)'),
    'without the check the Cancelled of d reaches the state: $bare',
  );
}
''' + RUNNER)

# ------------------------------------------------------------------ handler
# 'a', then 'ab' 35 ms in, while 'a' reads its second page; 'abc' at 185 ms
# and close() at 220, while 'abc' reads its second page.
TYPING = '''
Future<void> scenario() async {
  SearchState? last;
  final bloc = SearchBloc()..add(const Searched('a'));
  final states = bloc.stream.listen((state) => last = state);
  await delay(35);
  bloc.add(const Searched('ab'));
  await delay(150);
  bloc.add(const Searched('abc'));
  await delay(35);
  await bloc.close();
  print('bloc closed');
  await delay(200);
  await states.cancel();
  require(pagesRead == PAGES, 'pages read: $pagesRead, not PAGES');
  require(
    last?.rows.length == 3 && last?.error == null,
    'the search for ab delivers its rows',
  );
}
'''

EVENTS = snips[f'{HANDLER}/Searched']
assert EVENTS is snips[f'{HANDLER}/SearchState']

FILES['bloc_first'] = (
    BLOC_HEAD + DATABASE + READ_ROWS + EVENTS
    + snips[f'{HANDLER}/the-first-attempt/SearchBloc']
    # a: 3, ab: 3, abc: 3
    + TYPING.replace('PAGES', '9') + RUNNER)

ANSWER = snips[f'{HANDLER}/a-stream-that-cancels-the-job/SearchBloc']

# A job that ends Cancelled on its own, under the answer without its
# `onError:`, which the prose says hands the error to bloc and the zone.
SELF_CANCELLED = replaced(
    replaced(
        replaced(ANSWER[ANSWER.index('final class SearchBloc'):],
                 '        onError: (error, stackTrace) => '
                 'SearchState(const [], error),\n', ''),
        'watch(readRows(event.query))', 'watch(gaveUp())'),
    'SearchBloc', 'BareBloc', 2)

FILES['bloc_answer'] = (
    BLOC_HEAD + DATABASE + READ_ROWS + EVENTS + ANSWER + SELF_CANCELLED
    + '''
Job<List<String>> gaveUp() => Job((ctx) async {
  await ctx.pause(const Duration(milliseconds: 5));
  throw const Cancelled('gave up');
});
''' + TYPING.replace('PAGES', '7').replace(
        'Future<void> scenario() async {', 'Future<void> typing() async {')
    + '''
Future<void> scenario() async {
  // a: 2, ab: 3, abc: 2
  await typing();

  final zone = <Object>[];
  await runZonedGuarded(() async {
    final bloc = BareBloc()..add(const Searched('x'));
    await delay(50);
    await bloc.close();
  }, (error, _) => zone.add(error));
  require(
    zone.length == 1 && zone.single is Cancelled,
    "without onError: the job's own Cancelled reaches the zone: $zone",
  );

  final kept = <Object?>[];
  final bloc = SearchBloc()..add(const Searched('x'));
  final states = bloc.stream.listen((state) => kept.add(state.error));
  await delay(200);
  await states.cancel();
  await bloc.close();
  require(kept.isNotEmpty && kept.last == null, 'readRows ends Done');
}
''' + RUNNER)

# ------------------------------------------------------------------ request
# Real time against a raw socket: it says when the client hangs up, and
# sends the body 300 ms after the request unless the client is gone. An
# HttpServer would not do: it answers into a closed connection without a
# word.
SERVER = '''
final class Exchange {
  final arrived = Completer<void>();
  final hungUp = Completer<void>();
  bool sentBody = false;
}

final class SlowServer {
  SlowServer._(this._socket);

  final ServerSocket _socket;
  Exchange exchange = Exchange();

  static Future<SlowServer> start() async {
    final server = SlowServer._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._socket.listen(server._serve);
    return server;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${_socket.port}/report');

  /// A fresh record for the next request.
  Exchange expect() => exchange = Exchange();

  void _serve(Socket socket) {
    final exchange = this.exchange;
    var gone = false;
    socket.listen(
      (_) {
        if (!exchange.arrived.isCompleted) exchange.arrived.complete();
      },
      onDone: () {
        if (exchange.sentBody) return;
        gone = true;
        print('server: client hung up');
        exchange.hungUp.complete();
      },
      onError: (Object _) {
        gone = true;
      },
    );
    unawaited(
      exchange.arrived.future.then((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (gone) return;
        print('server: sending the body');
        exchange.sentBody = true;
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\\r\\nContent-Length: 6\\r\\n'
            'Connection: close\\r\\n\\r\\nreport',
          ),
        );
        await socket.flush();
        await socket.close();
      }),
    );
  }

  Future<void> close() => _socket.close();
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Cancels [job] once the server has the request, and prints the outcome
/// when the cancellation is over and, for a client that hung up, once the
/// server has seen it go.
Future<void> cancelInFlight(
  Job<String> job,
  Exchange exchange, {
  required bool hangsUp,
}) async {
  await exchange.arrived.future;
  print('cancel');
  await job.cancel();
  if (hangsUp) await exchange.hungUp.future;
  print('outcome: ${job.outcome}');
  // Past the moment the server would have answered.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  require(
    exchange.sentBody == !hangsUp,
    hangsUp ? 'the server never sends the body' : 'the server sends it',
  );
}
'''


def body_of(key):
    """A block that declares `job`, as the body of a function."""
    return snips[key]


FIRST = body_of(f'{REQUEST}/the-first-attempt/'
                'the-first-attempt-the-cancella')
HTTP = body_of(f'{REQUEST}/the-client-s-token/'
               'http-1-5-and-later-a-request-w')
DIO = body_of(f'{REQUEST}/the-client-s-token/dio-a-canceltoken')
FILTER = snips[f'{REQUEST}/the-client-s-token/'
               'job-iscancellationerror-error']

FILES['request'] = """import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async_job/async_job.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
""" + SERVER + f'''
Future<void> firstAttempt(SlowServer server, http.Client client) async {{
  final url = server.url;
  final exchange = server.expect();
{FIRST}
  await cancelInFlight(job, exchange, hangsUp: false);
}}

Future<void> withHttp(SlowServer server, http.Client client) async {{
  final url = server.url;
  final exchange = server.expect();
{HTTP}
  await cancelInFlight(job, exchange, hangsUp: true);
}}

Future<void> withDio(SlowServer server, Dio dio) async {{
  final url = server.url;
  final exchange = server.expect();
{DIO}
  await cancelInFlight(job, exchange, hangsUp: true);
}}

Future<List<Object>> uncaught(Future<void> Function() run) async {{
  final zone = <Object>[];
  await runZonedGuarded(run, (error, _) => zone.add(error));
  return zone;
}}

Future<void> main() async {{
  final server = await SlowServer.start();
  final client = http.Client();
  final dio = Dio();

  print('== join');
  require(
    (await uncaught(() => firstAttempt(server, client))).isEmpty,
    'the first attempt throws nothing',
  );

  // Without the filter the aborted requests reach the zone.
  print('== tokens, before the filter');
  final before = [
    ...await uncaught(() => withHttp(server, client)),
    ...await uncaught(() => withDio(server, dio)),
  ];
  require(
    before.length == 2 &&
        before.first is http.RequestAbortedException &&
        before.last is DioException,
    'the aborted requests reach the zone: $before',
  );

{FILTER}
  print('== tokens');
  final after = [
    ...await uncaught(() => withHttp(server, client)),
    ...await uncaught(() => withDio(server, dio)),
  ];
  require(after.isEmpty, 'the filter keeps them out of the zone: $after');

  client.close();
  dio.close();
  await server.close();
}}
'''

unbuilt = snips.unbuilt()
assert not unbuilt, f'blocks of the page no driver builds: {unbuilt}'

d = f'{ROOT}/adapters_check/bin/v'
os.makedirs(d, exist_ok=True)
for key, body in FILES.items():
    open(f'{d}/{key}.dart', 'w').write(body)

open(f'{ROOT}/adapters_check/pubspec.yaml', 'w').write(PUBSPEC)
with open(os.path.join(REPO, 'packages', 'async_job',
                       'analysis_options.yaml')) as rules:
    open(f'{ROOT}/adapters_check/async_job_rules.yaml', 'w').write(
        rules.read())
open(f'{ROOT}/adapters_check/analysis_options.yaml', 'w').write(OPTIONS)
print('wrote', len(FILES), 'files under', ROOT)
