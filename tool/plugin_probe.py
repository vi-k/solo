#!/usr/bin/env python3
"""The plugins of the tree, run by the analysis server on a user's code.

The tests of the packages call the rules directly. What a user gets is
something else: the analysis server builds the plugins named in
`analysis_options.yaml`, runs them on the user's code and applies the
`ignore` comments to their diagnostics. This probe goes that way:

    python3 tool/plugin_probe.py [--fixes] [--keep]

It makes a directory of its own and removes only that directory. There it
copies `lib/` and `pubspec.yaml` of `packages/solo_lints` with the
dependency on async_job_lints turned into a path to the tree: the server
builds a plugin from its pubspec alone and applies no
`pubspec_overrides.yaml`. Next to it, a user package depends on the
published async_job, solo and fake_async and holds
`tool/plugin_probe/fixture.dart`, every line of which a rule reports ends
with a comment naming the rule.

For each set of plugins, named alone or both in either order, the probe
writes `analysis_options.yaml` with the plugins by path and their lints on,
runs `dart analyze --format=machine` and compares the diagnostics of the
ten rules with the marks. The output names no plugin: the owner of a
rule of the core shows only through the `ignore` lines. A rule of the core
belongs to the plugin named alone, and of two to the one named first.

The wait for the own queue is not a mark: what reports it depends on the
set. Named alone, async_job_lints reports it as `bare_await`, and
solo_lints as `await_own_queue` only. With both, the instances of both
plugins run on Dart 3.13 and one on Dart 3.10, so `bare_await` there
depends on the SDK and the order and is not compared.

When the diagnostics differ from the marks, the probe prints the other
lines `dart analyze` gave: a plugin that did not load says why there.

A set of one plugin that goes red points at the code of the plugins. A
set of two that goes red alone, after a new SDK, points at how the server
runs two plugins: that is not a promise to the user, who names one, as
decision 145 of `docs/settled.md` says. The gate runs the probe on the
latest stable SDK only; after a change to how the plugins register their
rules, run it on the floor SDK by hand as well.

`--fixes` asks the server for quick fixes, through the language server
protocol, at each diagnostic of a rule that has one, and counts the
actions titled with the message of the fix. Named alone, a plugin is
expected to give exactly one; with both, the count is printed as it comes.
`--keep` leaves the directory and prints its path.
"""

import argparse
import json
import pathlib
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter

REPO = pathlib.Path(__file__).resolve().parent.parent
PACKAGES = REPO / 'packages'
FIXTURE = REPO / 'tool' / 'plugin_probe' / 'fixture.dart'

CORE = (
    'ctx_in_cleanup',
    'release_on_the_call',
    'sync_fake_async',
    'catch_without_check',
    'bare_await',
    'discarded_outcome',
    'outcome_after_await',
)
RULES = CORE + ('await_own_queue', 'key_per_request',
                'ignore_failure_hides_bugs')

# The lints each plugin turns on; the warnings are on once it is named.
LINTS = {
    'async_job_lints': ('catch_without_check', 'bare_await'),
    'solo_lints': ('catch_without_check', 'bare_await', 'key_per_request',
                   'ignore_failure_hides_bugs'),
}

SETS = (
    ('async_job_lints',),
    ('solo_lints',),
    ('async_job_lints', 'solo_lints'),
    ('solo_lints', 'async_job_lints'),
)

# The rules with a quick fix, and the class that declares its kind.
FIXES = {
    'release_on_the_call':
        PACKAGES / 'async_job_lints/lib/src/fixes/release_on_the_call.dart',
    'catch_without_check':
        PACKAGES / 'async_job_lints/lib/src/fixes/add_check.dart',
    'key_per_request':
        PACKAGES / 'solo_lints/lib/src/fixes/key_per_request.dart',
}

MARK = re.compile(r'\S.*\s// (\w+)(?: unless (\w+))?$')

WAIT_FOR_DIAGNOSTICS = 120
# How many other lines of `dart analyze` a mismatch prints.
REST = 40


def marks():
    """The marked lines of the fixture: (line, rule, unless) by number."""
    found = []
    for number, line in enumerate(FIXTURE.read_text().splitlines(), 1):
        match = MARK.search(line)
        if match and match.group(1) in RULES:
            found.append((number, match.group(1), match.group(2)))
    return found


def expected(plugins, marked):
    """The (rule, line) pairs [plugins] report, and the own-queue line."""
    owner = plugins[0]
    rules = CORE if plugins == ('async_job_lints',) else RULES
    pairs = []
    own_queue = None
    for line, rule, unless in marked:
        if rule == 'await_own_queue':
            own_queue = line
            pairs.append(
                ('bare_await' if rules is CORE else 'await_own_queue', line))
        elif rule in rules and unless != owner:
            pairs.append((rule, line))
    return sorted(pairs), own_queue


def options(plugins, solo_lints):
    """`analysis_options.yaml` naming [plugins] by path."""
    paths = {
        'async_job_lints': PACKAGES / 'async_job_lints',
        'solo_lints': solo_lints,
    }
    lines = ['plugins:']
    for plugin in plugins:
        lines += [f'  {plugin}:', f'    path: {paths[plugin]}',
                  '    diagnostics:']
        lines += [f'      {lint}: true' for lint in LINTS[plugin]]
    return '\n'.join(lines) + '\n'


def lay_out(root):
    """The copy of solo_lints and the user package under [root]."""
    solo_lints = root / 'solo_lints'
    shutil.copytree(PACKAGES / 'solo_lints' / 'lib', solo_lints / 'lib')
    pubspec = (PACKAGES / 'solo_lints' / 'pubspec.yaml').read_text()
    path = PACKAGES / 'async_job_lints'
    pubspec, count = re.subn(r'^  async_job_lints: .*$',
                             f'  async_job_lints:\n    path: {path}',
                             pubspec, flags=re.M)
    if count != 1:
        sys.exit('pubspec.yaml of solo_lints has no async_job_lints line')
    (solo_lints / 'pubspec.yaml').write_text(pubspec)

    user = root / 'user'
    (user / 'lib').mkdir(parents=True)
    shutil.copy(FIXTURE, user / 'lib' / 'fixture.dart')
    (user / 'pubspec.yaml').write_text(
        'name: probe_user\n'
        'publish_to: none\n'
        'environment:\n'
        '  sdk: ^3.10.0\n'
        'dependencies:\n'
        '  async_job: ^1.0.0\n'
        '  fake_async: ^1.3.3\n'
        '  solo: ^1.0.0\n')
    run(['dart', 'pub', 'get'], user)
    return solo_lints, user


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True,
                            text=True)
    if result.returncode != 0:
        sys.exit(f'{" ".join(command)} failed:\n{result.stdout}'
                 f'{result.stderr}')


def analyze(user):
    """The (rule, line) pairs of the ten rules `dart analyze` reports.

    Also the other lines of its output: a plugin that does not load says why
    there, and a mismatch prints them.
    """
    # Diagnostics make the exit code non-zero; that is not a failure here.
    result = subprocess.run(['dart', 'analyze', '--format=machine'],
                            cwd=user, capture_output=True, text=True)
    pairs = []
    rest = []
    for line in (result.stdout + result.stderr).splitlines():
        fields = line.split('|')
        if (len(fields) >= 8 and fields[3].endswith('fixture.dart')
                and fields[2].lower() in RULES):
            pairs.append((fields[2].lower(), int(fields[4])))
        elif line.strip():
            rest.append(line)
    return sorted(pairs), rest


def compare(plugins, got, marked):
    """Whether [got] is what [plugins] should report; prints a mismatch."""
    want, own_queue = expected(plugins, marked)
    if len(plugins) == 2:
        got = [pair for pair in got if pair != ('bare_await', own_queue)]
        want = [pair for pair in want if pair != ('bare_await', own_queue)]
    if got == want:
        return True
    print(f'  expected: {want}')
    print(f'  got:      {got}')
    # Counted, so that a pair reported twice shows as extra.
    print(f'  missing:  {sorted((Counter(want) - Counter(got)).elements())}')
    print(f'  extra:    {sorted((Counter(got) - Counter(want)).elements())}')
    return False


class Server:
    """`dart language-server` over its standard streams."""

    def __init__(self, cwd):
        self.process = subprocess.Popen(
            ['dart', 'language-server', '--protocol=lsp'], cwd=cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL)
        self.messages = queue.Queue()
        self.next_id = 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        stream = self.process.stdout
        while True:
            length = None
            while True:
                header = stream.readline()
                if not header:
                    return
                header = header.decode().strip()
                if not header:
                    break
                name, _, value = header.partition(':')
                if name.lower() == 'content-length':
                    length = int(value)
            self.messages.put(json.loads(stream.read(length)))

    def send(self, message):
        body = json.dumps({'jsonrpc': '2.0', **message}).encode()
        self.process.stdin.write(
            f'Content-Length: {len(body)}\r\n\r\n'.encode() + body)
        self.process.stdin.flush()

    def notify(self, method, params):
        self.send({'method': method, 'params': params})

    def request(self, method, params, deadline):
        self.next_id += 1
        self.send({'id': self.next_id, 'method': method, 'params': params})
        return self.receive(lambda m: m.get('id') == self.next_id
                            and 'method' not in m, deadline)['result']

    def receive(self, wanted, deadline):
        """The first message [wanted] accepts; answers the server's requests
        on the way."""
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError
            try:
                message = self.messages.get(timeout=left)
            except queue.Empty:
                raise TimeoutError from None
            if 'method' in message and 'id' in message:
                self._answer(message)
            elif wanted(message):
                return message

    def _answer(self, message):
        result = None
        if message['method'] == 'workspace/configuration':
            result = [{} for _ in message['params']['items']]
        self.send({'id': message['id'], 'result': result})

    def close(self):
        try:
            self.request('shutdown', None, time.monotonic() + 10)
            self.notify('exit', None)
            self.process.wait(timeout=10)
        except (TimeoutError, subprocess.TimeoutExpired, OSError):
            self.process.kill()
            self.process.wait()


def fix_titles():
    """A pattern of the title of each fix, from the message of its kind."""
    titles = {}
    for rule, path in FIXES.items():
        match = re.search(r"FixKind\(\s*'[^']+',\s*\d+,\s*(['\"])(.*?)\1",
                          path.read_text(), re.S)
        parts = re.split(r'\{\d+\}', match.group(2))
        titles[rule] = re.compile(
            '.+?'.join(re.escape(part) for part in parts) + '$')
    return titles


def fixes(plugins, user, titles):
    """The count of fixes at each diagnostic with one; False on a failure."""
    fixable = [rule for rule in FIXES
               if rule in CORE or 'solo_lints' in plugins]
    uri = (user / 'lib' / 'fixture.dart').resolve().as_uri()
    server = Server(user)
    deadline = time.monotonic() + WAIT_FOR_DIAGNOSTICS
    try:
        server.request('initialize', {
            'processId': None,
            'rootUri': user.resolve().as_uri(),
            'capabilities': {'textDocument': {'codeAction': {
                'codeActionLiteralSupport': {'codeActionKind': {
                    'valueSet': ['', 'quickfix', 'refactor', 'source']}}}}},
        }, deadline)
        server.notify('initialized', {})
        server.notify('textDocument/didOpen', {'textDocument': {
            'uri': uri, 'languageId': 'dart', 'version': 1,
            'text': FIXTURE.read_text()}})
        seen = set()

        def complete(message):
            if message.get('method') != 'textDocument/publishDiagnostics':
                return False
            if message['params']['uri'] != uri:
                return False
            seen.clear()
            seen.update(str(d.get('code')).lower()
                        for d in message['params']['diagnostics'])
            return all(rule in seen for rule in fixable)

        try:
            diagnostics = server.receive(complete, deadline)['params'][
                'diagnostics']
        except TimeoutError:
            print(f'  no diagnostics of {sorted(set(fixable) - seen)} '
                  f'in {WAIT_FOR_DIAGNOSTICS} s')
            return False

        ok = True
        for diagnostic in diagnostics:
            rule = str(diagnostic.get('code')).lower()
            if rule not in fixable:
                continue
            actions = server.request('textDocument/codeAction', {
                'textDocument': {'uri': uri},
                'range': diagnostic['range'],
                'context': {'diagnostics': [diagnostic]},
            }, time.monotonic() + WAIT_FOR_DIAGNOSTICS) or []
            count = sum(1 for action in actions
                        if titles[rule].match(action.get('title', '')))
            line = diagnostic['range']['start']['line'] + 1
            print(f'  {", ".join(plugins)}, {rule} at {line}: {count}')
            if len(plugins) == 1 and count != 1:
                ok = False
        return ok
    except TimeoutError:
        print('  the server did not answer in time')
        return False
    finally:
        server.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--fixes', action='store_true',
                        help='also count the quick fixes per diagnostic')
    parser.add_argument('--keep', action='store_true',
                        help='leave the directory and print its path')
    args = parser.parse_args()

    version = subprocess.run(['dart', '--version'], capture_output=True,
                             text=True)
    print((version.stdout + version.stderr).strip())

    marked = marks()
    titles = fix_titles() if args.fixes else None
    root = pathlib.Path(tempfile.mkdtemp(prefix='plugin_probe_'))
    failed = False
    try:
        solo_lints, user = lay_out(root)
        for plugins in SETS:
            (user / 'analysis_options.yaml').write_text(
                options(plugins, solo_lints))
            name = ', '.join(plugins)
            pairs, rest = analyze(user)
            if not compare(plugins, pairs, marked):
                print('  the rest of the output of dart analyze:')
                for line in rest[:REST]:
                    print(f'    {line}')
                if len(rest) > REST:
                    print(f'    ... and {len(rest) - REST} lines more')
                print(f'FAILED {name}')
                failed = True
                break
            print(f'ok {name}')
            if args.fixes and not fixes(plugins, user, titles):
                print(f'FAILED fixes of {name}')
                failed = True
                break
    finally:
        if args.keep:
            print(f'kept {root}')
        else:
            shutil.rmtree(root)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
