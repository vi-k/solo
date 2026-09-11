#!/usr/bin/env python3
"""Reports sections of public documentation that open with prose alone.

The rule is "a section starts with code": a reader of a package learns
faster from a fragment than from a paragraph about it. A section that
cannot show code is not a section -- it belongs inside a neighbour, or its
rules belong in a reference table.

So a heading must be followed, within LEAD lines of prose, by a fenced
code block or a table. Three kinds of heading are exempt. A page title
(`#`): an intro paragraph before the first section is the page saying
what it is. A container, whose next heading is a deeper one -- the code
lives in the subsections, and the lines under the container introduce
them. And a section shorter than LEAD lines altogether, which is a
pointer rather than an explanation.

`docs/records/` is not checked: a record is history, not documentation.
Translations mirror their originals, and `check_translations.py` already
holds them to the same shape, so only the English side is checked here.
"""

import pathlib
import re
import sys

LEAD = 10
ROOTS = ('packages',)
HEADING = re.compile(r'^(#{2,6})\s+(.*)$')


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
        return 1

    print('every section opens with code or a table')
    return 0


if __name__ == '__main__':
    sys.exit(main())
