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
package where it stands, dev dependencies included.

`run` goes through the layout with the SDK on `PATH`: `pub get`, the
direct hosted dependencies taken down to the lowest version their
constraints allow, `analyze lib`, the suite, and then the same for the
example and whatever program it has. It refuses an SDK that is not the
floor the pubspec declares, so raising the floor in a pubspec and
forgetting the job that checks it turns red rather than vacuous;
`--any-sdk` lifts that for a run by hand.

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

import os
import pathlib
import re
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
# Bottom up: a failure of the package below is the one to read first.
PACKAGES = ('async_job', 'solo', 'flutter_solo')

ENTRY = re.compile(r'^((?:│   |    )*)(?:├── |└── )(.+)$')
SIZE = re.compile(r' \((?:<1|[\d.]+) (?:B|KB|MB|GB)\)$')
LINTS = re.compile(r'^  (?:flutter_)?lints:.*\n', re.M)
DEPENDENCIES = re.compile(r'^dependencies:\n((?:(?:  .*)?\n)*)', re.M)
HOSTED = re.compile(r'^  (\w+): *\S', re.M)
OVERRIDDEN = re.compile(r'^  (\w+):', re.M)
SDK_FLOOR = re.compile(r'^  sdk: *[\'"]?(?:\^|>=)(\d+\.\d+\.\d+)', re.M)
FLUTTER_FLOOR = re.compile(
    r'^  flutter: *[\'"]?(?:\^|>=)(\d+\.\d+\.\d+)', re.M
)
DART_VERSION = re.compile(r'Dart SDK version: (\d+\.\d+\.\d+)')
FLUTTER_VERSION = re.compile(r'^Flutter (\d+\.\d+\.\d+)', re.M)
ANSI = re.compile(r'\x1b\[[0-9;]*m')


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


def hosted_dependencies(pubspec, overrides=''):
    """The direct dependencies a version constraint resolves from pub.dev.

    A dependency written as a map -- `sdk: flutter`, `path: ../` -- has
    nothing to take down, and neither has one the overrides replace.
    """
    block = DEPENDENCIES.search(pubspec)
    if block is None:
        return []
    replaced = set(OVERRIDDEN.findall(overrides))
    return [
        name
        for name in HOSTED.findall(block.group(1))
        if name not in replaced
    ]


def floor_mismatch(pubspec, dart_version, flutter_version):
    """What the SDK on `PATH` is, where it is not the declared floor."""
    problems = []
    for tool, floor, version, running in (
        ('Dart', SDK_FLOOR, DART_VERSION, dart_version),
        ('Flutter', FLUTTER_FLOOR, FLUTTER_VERSION, flutter_version),
    ):
        declared = floor.search(pubspec)
        running = version.search(running)
        if declared is None:
            continue
        found = running.group(1) if running else 'missing'
        if found != declared.group(1):
            problems.append(
                f'{tool} is {found}, the pubspec declares {declared.group(1)}'
            )
    return problems


def output_of(command, cwd=None):
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def stage(out):
    if out == REPO or REPO in out.parents:
        # A layout inside the checkout would be listed by the next dry run.
        print(f'{out} is inside the repository')
        return 2
    for package in PACKAGES:
        source = REPO / 'packages' / package
        # Nothing is uploaded: `--dry-run` validates and prints the tree.
        # What it says about the package is printed and not judged: between
        # releases the overrides alone are a hint in every run.
        _, text = output_of(['dart', 'pub', 'publish', '--dry-run'], source)
        files = listed_files(text)
        if not files:
            print(text)
            print(f'{package}: the dry run printed no archive')
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
        print(f'{package}: {len(files)} files{note}')
    return 0


def step(command, cwd):
    code, text = output_of(command, cwd)
    lines = text.strip().splitlines()
    verdict = 'ok' if code == 0 else f'FAILED, exit {code}'
    if code == 0 and command[1] == 'test' and lines:
        # The count, for whoever compares it with the gate of the tree.
        verdict = ANSI.sub('', lines[-1]).strip()
    print(f'    {" ".join(command)}: {verdict}')
    if code != 0:
        print('\n'.join('      ' + line for line in lines[-30:]))
    return code == 0


def run(out, any_sdk):
    dart_version = output_of(['dart', '--version'])[1]
    failed = []
    for package in PACKAGES:
        target = out / package
        pubspec = (target / 'pubspec.yaml').read_text()
        flutter = 'sdk: flutter' in pubspec
        tool = 'flutter' if flutter else 'dart'
        flutter_version = (
            output_of(['flutter', '--version'])[1] if flutter else ''
        )
        print(f'{package}:')
        mismatch = floor_mismatch(pubspec, dart_version, flutter_version)
        if mismatch and not any_sdk:
            print(''.join(f'    {problem}\n' for problem in mismatch), end='')
            failed.append(package)
            continue
        roots = [target]
        if (target / 'example' / 'pubspec.yaml').exists():
            roots.append(target / 'example')
        for root in roots:
            print(f'  {root.relative_to(out)}')
            overrides = root / 'pubspec_overrides.yaml'
            hosted = hosted_dependencies(
                (root / 'pubspec.yaml').read_text(),
                overrides.read_text() if overrides.exists() else '',
            )
            steps = [[tool, 'pub', 'get']]
            if hosted:
                steps.append([tool, 'pub', 'downgrade', *hosted])
            steps.append([tool, 'analyze', 'lib'])
            if (root / 'test').exists():
                steps.append([tool, 'test'])
            programs = [*root.glob('bin/*.dart'), *root.glob('example/*.dart')]
            for program in sorted(programs):
                steps.append(['dart', 'run', str(program.relative_to(root))])
            for command in steps:
                if not step(command, root):
                    failed.append(str(root.relative_to(out)))
                    break
    if failed:
        print(f'red: {", ".join(failed)}')
        return 1
    print('every archive passes its gate on the floor')
    return 0


def main(arguments):
    any_sdk = '--any-sdk' in arguments
    arguments = [word for word in arguments if word != '--any-sdk']
    if len(arguments) != 2 or arguments[0] not in ('stage', 'run'):
        print(__doc__)
        return 2
    out = pathlib.Path(os.path.abspath(arguments[1]))
    if arguments[0] == 'stage':
        return stage(out)
    return run(out, any_sdk)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
