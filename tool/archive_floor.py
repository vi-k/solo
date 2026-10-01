#!/usr/bin/env python3
"""The gate, replayed from what would be published and on the SDK floor.

The gate of `AGENTS.md` proves the tree: every file in it, the dev
dependencies resolved along with the rest, the newest versions the
constraints allow, on the latest stable. A user gets something else -- the
archive, without the dev dependencies, and possibly on the lowest SDK and
the lowest `meta` the pubspec admits. This replays the gate there.

Two steps, because they want two SDKs:

    python3 tool/archive_floor.py stage <out>    # on stable
    python3 tool/archive_floor.py run <out>      # on the floor

`stage` lays out, package by package, the files `dart pub publish` would
upload. It asks pub itself, with `--dry-run`, which uploads nothing and
prints the archive as a tree; the files are copied from the checkout.
Stable is needed for that and nothing else: the dry run resolves the
package where it stands, dev dependencies included. What the dry run says
about the package is printed, and a dry run that fails fails the step.

`<out>` is a directory outside the repository that does not exist yet, is
empty, or holds an earlier layout: `stage` leaves a file of its own there
and replaces nothing in a directory that lacks it.

`run` goes through the layout with the SDK on `PATH`, twice for each
package and for its example. First as a dependency: the pubspec without
its `dev_dependencies`, the direct hosted dependencies taken down to the
lowest version their constraints allow, `analyze lib`, and whatever
program there is. Then with its tests: the dev dependencies back, the same
taking down, and the suite. After each taking down the lockfile is read,
and a dependency that did not reach its lower bound is a failure. So is a
package with no tests in its archive: there would be nothing to replay.

It refuses an SDK that is not the floor the pubspec declares, so raising
the floor in a pubspec and forgetting the job that checks it turns red
rather than vacuous; `--any-sdk` lifts that for a run by hand. On the
floor the analyzer is asked for errors alone: the lint packages are not
there, and the style is the business of the gate on stable.

Two things differ between the layout and the archive, both of them about
development only. `lints` and `flutter_lints` are dropped from
`dev_dependencies`: they want an SDK above the floor, and without them the
rest resolves. And a package that carries a `pubspec_overrides.yaml` in
the tree gets it in the layout too, where its paths lead to the layouts
next door instead of the tree: the package below is not published yet.
While those files live, the constraints between the packages are not
proved here. Once a release takes them out, the same run resolves the
package below from pub.dev by the constraint in the archive.
"""

import pathlib
import re
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
# Bottom up: a failure of the package below is the one to read first.
PACKAGES = ('async_job', 'solo', 'flutter_solo')
# What `stage` leaves at the top of a layout, and what tells one from a
# directory of somebody else's. Not a dot file: it travels with the layout
# as a CI artifact, and those leave hidden files behind.
MARK = 'archive_floor.txt'

ENTRY = re.compile(r'^((?:│   |    )*)(?:├── |└── )(.+)$')
SIZE = re.compile(r' \((?:<1|[\d.]+) (?:B|KB|MB|GB)\)$')
LINTS = re.compile(r'^  (?:flutter_)?lints:.*(?:\n|\Z)', re.M)
LOWER_BOUND = re.compile(r'^[\'"]?(?:\^|>= ?)?(\d+\.\d+\.\d+[^\s\'"]*)')
DART_VERSION = re.compile(r'Dart SDK version: (\d+\.\d+\.\d+\S*)')
FLUTTER_VERSION = re.compile(r'^Flutter (\d+\.\d+\.\d+\S*)', re.M)
ANSI = re.compile(r'\x1b\[[0-9;]*m')


def say(text=''):
    # Flushed line by line: in CI the output is a pipe, and a step killed
    # by the timeout would otherwise leave nothing behind.
    print(text, flush=True)


def listed_files(output):
    """The files in the tree `dart pub publish --dry-run` prints.

    A file is an entry with a size after its name; an entry without one is
    a directory, and what follows one level deeper is inside it.
    """
    files = []
    directories = []
    in_tree = False
    for line in output.splitlines():
        entry = ENTRY.match(line)
        if entry is None:
            if in_tree:
                break
            continue
        in_tree = True
        depth = len(entry.group(1)) // 4
        name = entry.group(2)
        del directories[depth:]
        if SIZE.search(name):
            files.append('/'.join([*directories, SIZE.sub('', name)]))
        else:
            directories.append(name)
    return files


def without_lints(pubspec):
    """The pubspec without the lint packages, which want a newer SDK."""
    return LINTS.sub('', pubspec)


def _entries(pubspec):
    """Every meaningful line of a pubspec with the top-level key above it."""
    key = None
    for line in pubspec.splitlines():
        text = line.split(' #')[0].rstrip()
        if not text.strip() or text.lstrip().startswith('#'):
            continue
        if not text.startswith(' '):
            key = text.split(':')[0]
            continue
        yield key, text


def without_dev_dependencies(pubspec):
    """The pubspec as a package depending on this one resolves it."""
    kept = []
    dropping = False
    for line in pubspec.splitlines(keepends=True):
        if line.strip() and not line.startswith((' ', '#')):
            dropping = line.split(':')[0] == 'dev_dependencies'
        if not dropping:
            kept.append(line)
    return ''.join(kept)


def hosted_dependencies(pubspec, overrides=''):
    """The direct dependencies pub.dev resolves, each with its lower bound.

    A dependency written as a map -- `sdk: flutter`, `path: ../` -- has
    nothing to take down, and neither has one the overrides replace. The
    bound is `None` for a constraint without one, such as `any`.
    """
    replaced = {
        text.strip().rstrip(':')
        for key, text in _entries(overrides)
        if key == 'dependency_overrides' and re.match(r'^  \S', text)
    }
    hosted = []
    for key, text in _entries(pubspec):
        entry = re.match(r'^  (\w+): *(\S.*)$', text)
        if key != 'dependencies' or entry is None:
            continue
        if entry.group(1) in replaced:
            continue
        bound = LOWER_BOUND.match(entry.group(2))
        hosted.append((entry.group(1), bound.group(1) if bound else None))
    return hosted


def above_the_bound(lockfile, hosted):
    """The dependencies the lockfile holds above their lower bound."""
    problems = []
    for name, bound in hosted:
        if bound is None:
            continue
        locked = re.search(
            rf'^  {re.escape(name)}:\n(?:    .*\n)*?    version: "([^"]+)"',
            lockfile,
            re.M,
        )
        found = locked.group(1) if locked else 'missing'
        if found != bound:
            problems.append(f'{name} is {found}, the lower bound is {bound}')
    return problems


def floor_mismatch(pubspec, dart_version, flutter_version):
    """What the SDK on `PATH` is, where it is not the declared floor.

    A floor that cannot be read is a mismatch too: a constraint this
    script does not understand must not pass for a check that was made.
    """
    floors = {}
    for key, text in _entries(pubspec):
        entry = re.match(r'^  (sdk|flutter): *(\S.*)$', text)
        if key == 'environment' and entry is not None:
            bound = LOWER_BOUND.match(entry.group(2))
            floors[entry.group(1)] = bound.group(1) if bound else None
    wanted = [('Dart', 'sdk', DART_VERSION, dart_version)]
    if 'sdk: flutter' in pubspec:
        wanted.append(('Flutter', 'flutter', FLUTTER_VERSION, flutter_version))
    problems = []
    for tool, key, version, running in wanted:
        declared = floors.get(key)
        if declared is None:
            problems.append(f'no floor of {tool} is declared in the pubspec')
            continue
        running = version.search(running)
        found = running.group(1) if running else 'missing'
        if found != declared:
            problems.append(
                f'{tool} is {found}, the pubspec declares {declared}'
            )
    return problems


def output_of(command, cwd=None):
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def refusal(out):
    """Why `stage` must not write into [out], or `None`."""
    if out == REPO or REPO in out.parents:
        # A layout inside the checkout would be listed by the next dry run.
        return 'is inside the repository'
    if out in REPO.parents:
        # A package directory under it could be the checkout itself.
        return 'holds the repository'
    if out.exists() and any(out.iterdir()) and not (out / MARK).exists():
        return f'is not empty and has no {MARK}: not a layout of this script'
    return None


def stage(out):
    out = out.resolve()
    reason = refusal(out)
    if reason is not None:
        say(f'{out} {reason}')
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / MARK).write_text('Laid out by tool/archive_floor.py stage.\n')
    for package in PACKAGES:
        source = REPO / 'packages' / package
        # Nothing is uploaded: `--dry-run` validates and prints the tree.
        code, text = output_of(['dart', 'pub', 'publish', '--dry-run'], source)
        files = listed_files(text)
        if code != 0 or not files:
            say(text)
            say(f'{package}: the dry run failed, exit {code}')
            return 1
        target = out / package
        if target.exists():
            shutil.rmtree(target)
        for file in files:
            (target / file).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / file, target / file)
        for pubspec in (
            target / 'pubspec.yaml',
            target / 'example' / 'pubspec.yaml',
        ):
            if pubspec.exists():
                pubspec.write_text(without_lints(pubspec.read_text()))
        overrides = source / 'pubspec_overrides.yaml'
        if overrides.exists():
            shutil.copyfile(overrides, target / 'pubspec_overrides.yaml')
        note = ', with the overrides of the tree' if overrides.exists() else ''
        say(f'{package}: {len(files)} files{note}')
        validation = text.find('Validating package')
        if validation >= 0:
            for line in text[validation:].strip().splitlines():
                say(f'    {line}')
    return 0


def step(command, cwd):
    code, text = output_of(command, cwd)
    lines = text.strip().splitlines()
    verdict = 'ok' if code == 0 else f'FAILED, exit {code}'
    if code == 0 and command[1] == 'test' and lines:
        # The count, for whoever compares it with the gate of the tree.
        verdict = ANSI.sub('', lines[-1]).strip()
    say(f'      {" ".join(command)}: {verdict}')
    if code != 0:
        # Whole: a red run here does not reproduce on stable, and the name
        # of the failing test is not in the last lines.
        say('\n'.join('        ' + ANSI.sub('', line) for line in lines))
    return code == 0


def resolved(root, tool, hosted):
    """Resolves [root] and takes its hosted dependencies to their bounds."""
    if not step([tool, 'pub', 'get'], root):
        return False
    names = [name for name, _ in hosted]
    if not names:
        return True
    if not step([tool, 'pub', 'downgrade', *names], root):
        return False
    problems = above_the_bound((root / 'pubspec.lock').read_text(), hosted)
    for problem in problems:
        say(f'      {problem}')
    return not problems


def analysis(tool):
    # Errors alone. Warnings and infos come from a linter older than the
    # one the gate uses, with the lint packages missing.
    quiet = ['--no-fatal-warnings']
    if tool == 'flutter':
        quiet.append('--no-fatal-infos')
    return [tool, 'analyze', *quiet, 'lib']


def passes(root, tool):
    """One package or example: as a dependency, then with its tests."""
    pubspec = root / 'pubspec.yaml'
    original = pubspec.read_text()
    overrides = root / 'pubspec_overrides.yaml'
    hosted = hosted_dependencies(
        original, overrides.read_text() if overrides.exists() else ''
    )
    say('    as a dependency')
    pubspec.write_text(without_dev_dependencies(original))
    try:
        if not resolved(root, tool, hosted):
            return False
        if not step(analysis(tool), root):
            return False
        programs = [*root.glob('bin/*.dart'), *root.glob('example/*.dart')]
        for program in sorted(programs):
            path = str(program.relative_to(root))
            if not step(['dart', 'run', path], root):
                return False
    finally:
        pubspec.write_text(original)
    say('    with its tests')
    if not (root / 'test').exists():
        say('      no tests in the archive: nothing to replay')
        return False
    return resolved(root, tool, hosted) and step([tool, 'test'], root)


def run(out, any_sdk):
    out = out.resolve()
    if not (out / MARK).exists():
        say(f'{out} has no {MARK}: not a layout made by `stage`')
        return 2
    dart_version = output_of(['dart', '--version'])[1]
    failed = []
    roots = 0
    for package in PACKAGES:
        target = out / package
        say(f'{package}:')
        if not (target / 'pubspec.yaml').exists():
            say('    no layout of this package')
            failed.append(package)
            continue
        pubspec = (target / 'pubspec.yaml').read_text()
        flutter = 'sdk: flutter' in pubspec
        tool = 'flutter' if flutter else 'dart'
        flutter_version = (
            output_of(['flutter', '--version'])[1] if flutter else ''
        )
        mismatch = floor_mismatch(pubspec, dart_version, flutter_version)
        if mismatch and not any_sdk:
            for problem in mismatch:
                say(f'    {problem}')
            failed.append(package)
            continue
        for root in (target, target / 'example'):
            if not (root / 'pubspec.yaml').exists():
                continue
            roots += 1
            say(f'  {root.relative_to(out)}')
            if not passes(root, tool):
                failed.append(str(root.relative_to(out)))
    if failed:
        say(f'red: {", ".join(failed)}')
        return 1
    say(f'every archive passes its gate on the floor: {roots} roots')
    return 0


def main(arguments):
    any_sdk = '--any-sdk' in arguments
    arguments = [word for word in arguments if word != '--any-sdk']
    if len(arguments) != 2 or arguments[0] not in ('stage', 'run'):
        say(__doc__)
        return 2
    out = pathlib.Path(arguments[1])
    if arguments[0] == 'stage':
        return stage(out)
    return run(out, any_sdk)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
