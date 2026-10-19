#!/usr/bin/env python3
"""Reports sections of public documentation that open with prose alone.

The rule is "a section starts with code": a reader of a package learns
faster from a fragment than from a paragraph about it. A section that
cannot show code is not a section -- it belongs inside a neighbour, or its
rules belong in a reference table.

So a heading must be followed, within LEAD lines of prose, by a fenced
code block, a table, or a deeper heading. A page title (`#`) is exempt
outright: an intro paragraph before the first section is the page saying
what it is. A section is not exempt for being short: one that reaches the
next heading of its level with prose alone fails however few its lines,
since a pointer of three lines belongs inside a neighbour as well. The
last section of a page is the exception: no heading follows it, so it is
held to the LEAD budget alone.

A container -- a section whose next heading is a deeper one -- is cleared
by that heading, because the code lives in its subsections. It is not
exempt from the count: the lines introducing the subsections get the same
LEAD budget. That budget is generous rather than tight, which is why the
distinction is worth stating. Of the fifteen containers in the checked
documents on 2026-09-14, thirteen introduced their subsections in seven
lines or fewer; the one that went over had grown a paragraph about
`Bloc.add` into an intro that was supposed to state a requirement, and the
paragraph belonged in the attempt below it.

`docs/records/` is not checked: a record is history, not documentation.
Translations mirror their originals, and `check_translations.py` already
holds them to the same shape, so only the English side is checked here.

An attempt is code that is wrong on purpose, and its first line says so:
the first `dart` block under `The first attempt` opens with
`// The first attempt: ` and what goes wrong, and under `Первая попытка`
with `// Первая попытка: `. A reader who lands on the block from a search
or a link meets the mark before the code. `check_translations.py` compares
code without its comments, so this rule is checked on both sides.
"""

import pathlib
import re
import sys

LEAD = 10
ROOTS = ('packages',)
HEADING = re.compile(r'^(#{2,6})\s+(.*)$')
ATTEMPT = re.compile(r'^#{2,6}\s+(The \w+ attempt|\w+ попытка)$')


def offenders(path):
    lines = path.read_text().split('\n')
    fenced = False
    heading = None
    level = 0
    prose = 0
    for number, line in enumerate(lines, start=1):
        if line.startswith('```'):
            fenced = not fenced
            heading = None
            continue
        if fenced:
            continue
        match = HEADING.match(line)
        if match:
            if heading is not None and len(match.group(1)) <= level:
                yield heading
            heading = (number, match.group(2))
            level = len(match.group(1))
            prose = 0
            continue
        if heading is None:
            continue
        if line.startswith('|'):
            heading = None
            continue
        if line.strip():
            prose += 1
            if prose > LEAD:
                yield heading
                heading = None


def unmarked(path):
    """Attempts whose first `dart` block does not open with their mark."""
    lines = path.read_text().split('\n')
    fenced = False
    attempt = None
    for number, line in enumerate(lines, start=1):
        if line.startswith('```'):
            if not fenced and attempt and line.strip() == '```dart':
                mark = f'// {attempt[1]}: '
                if not lines[number].strip().startswith(mark):
                    yield attempt
                attempt = None
            fenced = not fenced
            continue
        if fenced:
            continue
        match = ATTEMPT.match(line)
        if match:
            attempt = (number, match.group(1))
        elif attempt and HEADING.match(line):
            yield attempt
            attempt = None
    if attempt:
        yield attempt


def documents():
    """Public documents in English and their translations."""
    for root in ('packages', 'docs/ru'):
        for path in sorted(pathlib.Path(root).rglob('*.md')):
            parts = path.parts
            if 'doc' in parts and 'api' in parts or '.dart_tool' in parts:
                continue
            yield path


def main():
    found = 0
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob('*.md')):
            parts = path.parts
            if 'doc' in parts and 'api' in parts:
                continue
            if '.dart_tool' in parts or path.name.endswith('.ru.md'):
                continue
            if path.name == 'CHANGELOG.md':
                continue
            for number, title in offenders(path):
                found += 1
                print(f'{path}:{number}: "{title}" opens with prose only')

    if found:
        print(f'\n{found} sections without code or a table in the first '
              f'{LEAD} lines.')

    bare = 0
    for path in documents():
        for number, title in unmarked(path):
            bare += 1
            print(f'{path}:{number}: "{title}" does not open its code with '
                  f'"// {title}: "')
    if bare:
        print(f'\n{bare} attempts without their mark.')

    if found or bare:
        return 1

    print('every section opens with code or a table')
    print('every attempt opens its code with its mark')
    return 0


if __name__ == '__main__':
    sys.exit(main())
