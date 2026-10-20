#!/usr/bin/env python3
"""Reports Markdown lines wider than the project's 79 columns.

A line is left alone when nothing can be done about its width. That is a
line whose overflow is one token the filler cannot split -- a long URL, a
`[label](url)` that must not break between `]` and `(`, a code span quoted
to be copied -- and a table row, a heading, or anything inside a fenced
code block: code has a width of its own, 80, and `dart format` keeps it.

The token rule is `reflow.py`'s rule, and it has to be, or the two
disagree: the filler keeps a link whole at any width, so on 2026-09-19 it
wrote an 81-column line that this check called an offence. Until then only
`http` was forgiven, and the link in that line had none -- it pointed at a
section of a neighbouring page.

`docs/records/` is not checked: a record is history, written on its day and
kept as it was.

Two blank lines in a row outside a code block are reported here too. They
render as one, so nothing on the site shows them, and the filler keeps
blank lines as they are. Before 2026-10-20 three stood in a row in
`errors.md` of `solo`, and two in five more places of the pages of both
packages.
"""

import pathlib
import re
import sys

WIDTH = 79
ROOTS = ('packages', 'docs')
SKIP = re.compile(r'^\s*(\||#)')
# One word to the filler, and so one word here: see `reflow.py`, which
# hides both behind a stand-in of the same width before it wraps.
ATOM = re.compile(r'!?\[[^\[\]]*\]\([^()\s]*\)|`[^`]+`')


def unbreakable(line):
    """The width of a line holding nothing but its widest whole token.

    The indent counts: a token of 78 columns three spaces in does not fit
    either, and no fill can take those three columns away.
    """
    indent = len(line) - len(line.lstrip(' '))
    masked = ATOM.sub(lambda match: '\x00' * len(match.group(0)), line.strip())
    return indent + max(len(word) for word in masked.split(' '))


def offenders(path):
    fenced = False
    for number, line in enumerate(path.read_text().split('\n'), start=1):
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced or len(line) <= WIDTH:
            continue
        if SKIP.match(line) or unbreakable(line) > WIDTH:
            continue
        yield number, len(line), line


def doubled_blanks(path):
    """The numbers of blank lines that follow a blank line, outside code."""
    fenced = False
    blank = False
    for number, line in enumerate(path.read_text().split('\n'), start=1):
        if line.startswith('```'):
            fenced = not fenced
        if fenced or line.strip():
            blank = False
            continue
        if blank:
            yield number
        blank = True


def main():
    found = 0
    doubled = 0
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
            for number in doubled_blanks(path):
                doubled += 1
                print(f'{path}:{number}: a second blank line in a row')
    if found or doubled:
        if found:
            print(f'\n{found} lines over {WIDTH} columns.')
        if doubled:
            print(f'\n{doubled} blank lines after a blank line.')
        return 1
    print(f'no Markdown line over {WIDTH} columns, no blank line doubled')
    return 0


if __name__ == '__main__':
    sys.exit(main())
