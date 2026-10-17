#!/usr/bin/env python3
"""Reports a copy of `page_code.dart` that has drifted from the original.

`page_code.dart` is the helper the rakes tests hold a page's code to: it
says which pieces of a page the test does not run. The packages share no
test code, so the helper lives in four copies, and the first one is the
original:

    packages/async_job/test/support/page_code.dart
    packages/solo/test/support/page_code.dart
    packages/solo/example/test/support/page_code.dart
    packages/flutter_solo/test/support/page_code.dart

Until 2026-10-17 only a comment at the head of each said so. A fix that
reached three of them would have left a fourth package checking its pages
by the old rule, and every test of it green.

Each copy opens with a comment of its own naming the others. That header
is left out, and the rest has to be the original's, byte for byte. The
header is the plain `// ` comments the file opens with and nothing more:
a `///` doc comment, or a comment the analyzer reads, such as
`// ignore_for_file:`, ends it and is compared with the rest. Counted as
header, a line like that written right under it would turn off a copy's
lints unseen.
"""

import difflib
import pathlib
import re
import sys

COPIES = (
    'packages/async_job/test/support/page_code.dart',
    'packages/solo/test/support/page_code.dart',
    'packages/solo/example/test/support/page_code.dart',
    'packages/flutter_solo/test/support/page_code.dart',
)


ANALYZER_COMMENT = re.compile(rb'//\s*(ignore|@dart)')


def is_header(line):
    return line.startswith(b'// ') and not ANALYZER_COMMENT.match(line)


def body(path):
    lines = path.read_bytes().splitlines(keepends=True)
    start = 0
    while start < len(lines) and is_header(lines[start]):
        start += 1
    return lines[start:]


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    original, *copies = COPIES
    expected = body(root / original)
    drifted = 0
    for copy in copies:
        actual = body(root / copy)
        if actual == expected:
            continue
        drifted += 1
        sys.stdout.writelines(
            difflib.unified_diff(
                [line.decode(errors='replace') for line in expected],
                [line.decode(errors='replace') for line in actual],
                original,
                copy,
            ),
        )
    if drifted:
        print(f'{drifted} of {len(copies)} copies differ from {original}')
        return 1
    print(f'{len(copies)} copies of {original} agree with it')
    return 0


if __name__ == '__main__':
    sys.exit(main())
