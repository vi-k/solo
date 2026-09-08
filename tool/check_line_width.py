#!/usr/bin/env python3
"""Reports Markdown lines wider than the project's 79 columns.

Four kinds of line cannot be wrapped and are left alone: a line holding a
long URL, a table row, a heading, and anything inside a fenced code block —
code has a width of its own, 80, and `dart format` keeps it.

`docs/records/` is not checked: a record is history, written on its day and
kept as it was.
"""

import pathlib
import re
import sys

WIDTH = 79
ROOTS = ('packages', 'docs')
SKIP = re.compile(r'^\s*(\||#)')


def offenders(path):
    fenced = False
    for number, line in enumerate(path.read_text().split('\n'), start=1):
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced or len(line) <= WIDTH:
            continue
        if 'http' in line or SKIP.match(line):
            continue
        yield number, len(line), line


def main():
    found = 0
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob('*.md')):
            parts = path.parts
            if 'doc' in parts and 'api' in parts:
                continue
            if '.dart_tool' in parts or 'records' in parts:
                continue
            for number, width, line in offenders(path):
                found += 1
                print(f'{path}:{number}: {width} columns')
                print(f'  {line}')
    if found:
        print(f'\n{found} lines over {WIDTH} columns.')
        return 1
    print(f'no Markdown line over {WIDTH} columns')
    return 0


if __name__ == '__main__':
    sys.exit(main())
