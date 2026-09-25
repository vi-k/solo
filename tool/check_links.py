#!/usr/bin/env python3
"""Reports Markdown links that lead nowhere.

A link inside the documentation is a promise that a file and a section
exist. Nothing checked that promise: a page renamed or a heading reworded
stayed green until a reader clicked, and the pages rename headings often --
an anchor written today outlives the wording it points at.

What the address says and what the text around it says are two different
promises, and only the first one is checked here. The Russian `cleanup.md`
called its neighbour "Дети, потоки и цепочки" while that page was titled
"Дети, стримы и цепочки": the address was right, the name was not, and no
script can tell, because link text is a phrase of the sentence it stands
in, not a copy of the title. That one was found by reading.

Two things are checked for every inline link with a relative target: that
the target exists, and that the anchor, if there is one, matches a heading
in it. A target can be a directory -- `camera.md` links to the example
folder -- and then there is nothing to look a heading up in. An anchor is
slugged the way GitHub does it -- lowercased, punctuation dropped, spaces
turned into hyphens -- and repeated headings get the same `-1`, `-2` tail,
because `### The first attempt` opens four sections of one page and a link
to the second of them is ordinary.

A link to a section of the page it stands on is checked the same way, so
`[the chains](#chains)` fails when that heading is reworded. External links
are not checked: a network call is not a gate's business. Links inside
fenced code blocks and inside backticks are not checked either, because a
fragment showing Markdown is code, not a link.

A link to this repository on GitHub is not external, only absolute: pub.dev
shows a package without its neighbours, so `solo` links a section of
`async_job` by its GitHub address. The file and the section behind it are
in this tree, and they are checked like a relative link's -- the address
holds the same promise, and until 2026-09-25 nobody checked it.

A guide page does not lead up. The packages are layered -- `solo` is built
on `async_job`, `flutter_solo` on `solo` -- and a page of `doc/` explains
its own package to a reader who may not have the one above it at all. So a
guide page, or its translation, that links into a document of a package
built on its own is reported. `observing.md` of `async_job` sent its
reader to the errors page of `solo` for "such an observer in full", and
what stood there was a `SoloObserver`, with hooks the core does not have.
A README is left alone: it is the front of its package and introduces the
family, and sending a reader to the package that solves their problem is
its job. Which package is built on which is read from the `dependencies` of
every pubspec, so a new package needs no edit here.

`docs/records/` is not checked: a record is history, written on its day and
kept as it was, and a link that pointed somewhere then is not a defect now.
"""

import json
import pathlib
import re
import sys

ROOTS = ('packages', 'docs')
LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
# `[текст](адрес)` inside backticks is a fragment showing the syntax,
# the way a fenced block is. Markdown renders it as text, not a link.
SPAN = re.compile(r'`[^`]+`')
HEADING = re.compile(r'^#{1,6}\s+(.*)$')
EXTERNAL = re.compile(r'^(https?:|mailto:)')
REPO = pathlib.Path(__file__).resolve().parent.parent
# The repository's address is the site's setting, so one place names it.
BLOB = json.loads((REPO / 'site' / 'site.json').read_text())['repo']
BLOB = BLOB.rstrip('/') + '/blob/main/'


DEPENDENCIES = re.compile(r'^dependencies:\n((?:[ \t].*\n|\n)*)', re.M)
NAME = re.compile(r'^  (\w+):', re.M)


def built_on():
    """Package -> every package of this tree built on it, however deep."""
    needs = {}
    for pubspec in sorted((REPO / 'packages').glob('*/pubspec.yaml')):
        block = DEPENDENCIES.search(pubspec.read_text())
        needs[pubspec.parent.name] = set(
            NAME.findall(block.group(1)) if block else ()
        )
    above = {package: set() for package in needs}
    for package in needs:
        pending = [package]
        while pending:
            below = pending.pop()
            for dependency in needs.get(below, ()):
                if dependency in above and package not in above[dependency]:
                    above[dependency].add(package)
                    pending.append(dependency)
    return above


def place(path):
    """The package a document belongs to, and whether it is a guide page."""
    try:
        parts = path.resolve().relative_to(REPO.resolve()).parts
    except ValueError:
        return None, False
    if len(parts) >= 3 and parts[0] == 'packages':
        return parts[1], len(parts) == 4 and parts[2] == 'doc'
    if len(parts) == 4 and parts[:2] == ('docs', 'ru'):
        return parts[2], True
    return None, False


def slug(heading):
    text = re.sub(r'[^\w\s-]', '', heading.strip().lower())
    return re.sub(r'\s+', '-', text).strip('-')


def anchors(path):
    """Every anchor the file offers, GitHub's repetition tail included."""
    seen = {}
    found = set()
    fenced = False
    for line in path.read_text().split('\n'):
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(1))
        count = seen.get(base, 0)
        seen[base] = count + 1
        found.add(base if count == 0 else f'{base}-{count}')
    return found


def offenders(path):
    package, guide = place(path)
    above = built_on().get(package, set()) if guide else set()
    fenced = False
    for number, line in enumerate(path.read_text().split('\n'), start=1):
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced:
            continue
        for target in LINK.findall(SPAN.sub('', line)):
            if target.startswith(BLOB):
                file, _, anchor = target[len(BLOB):].partition('#')
                destination = REPO / file
            elif EXTERNAL.match(target):
                continue
            else:
                file, _, anchor = target.partition('#')
                destination = (path.parent / file).resolve() if file else path
            upper, _ = place(destination)
            if upper in above:
                yield number, f'a page of {package} leads up to {upper}: {target}'
            if not destination.exists():
                yield number, f'no such file: {target}'
                continue
            if not destination.is_file():
                continue
            if anchor and anchor not in anchors(destination):
                yield number, f'no such section: {target}'


def main():
    found = 0
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob('*.md')):
            parts = path.parts
            if 'doc' in parts and 'api' in parts:
                continue
            if '.dart_tool' in parts or 'records' in parts:
                continue
            for number, problem in offenders(path):
                found += 1
                print(f'{path}:{number}: {problem}')
    if found:
        print(f'\n{found} links lead nowhere.')
        return 1
    print('every document link resolves')
    return 0


if __name__ == '__main__':
    sys.exit(main())
