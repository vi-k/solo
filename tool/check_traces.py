#!/usr/bin/env python3
"""Checks that the traces a document quotes are the traces its bench prints.

The benches prove that every fragment compiles and runs. They do not prove
that the output quoted next to a fragment is that fragment's output: the
drivers print, and a number in the prose that stopped being true stays
there. This closes that gap for the traces kept in fenced blocks.

A trace block is a fence opened with ``` alone or with ```text. Its lines
must appear, in order and next to each other, in the captured output of the
drivers. Leading and trailing whitespace is ignored on both sides: a driver
indents its lines under the name of the case, and the document quotes them
flush left.

What this does not check: numbers written into the prose itself. Those are
still the author's to keep true.

Usage, from the repository root:

    python3 tool/check_traces.py <document.md> <captured-output.txt>

Both arguments can be repeated in pairs. Exit code 1 if a quoted trace is
not in the output.
"""

import pathlib
import sys


def traces(text):
    """Every block fenced by ``` alone or ```text, in order."""
    found, buf, state = [], [], 'out'
    for line in text.split('\n'):
        if line.startswith('```'):
            if state == 'out':
                state = 'trace' if line[3:].strip() in ('', 'text') else 'code'
            else:
                if state == 'trace':
                    found.append('\n'.join(buf))
                buf, state = [], 'out'
            continue
        if state == 'trace':
            buf.append(line)
    return found


def printed(block, output):
    """Are the block's lines consecutive lines of the output?"""
    wanted = [line.strip() for line in block.split('\n') if line.strip()]
    lines = [line.strip() for line in output.split('\n')]
    for start in range(len(lines) - len(wanted) + 1):
        if lines[start:start + len(wanted)] == wanted:
            return True
    return False


def main():
    argv = sys.argv[1:]
    if not argv or len(argv) % 2:
        print(__doc__.strip().split('Usage,')[-1].strip())
        return 2

    bad = 0
    for i in range(0, len(argv), 2):
        doc = pathlib.Path(argv[i])
        output = pathlib.Path(argv[i + 1]).read_text()
        blocks = traces(doc.read_text())
        missing = [b for b in blocks if not printed(b, output)]
        bad += len(missing)
        print(f'{doc}: {len(blocks)} quoted traces, {len(missing)} not printed')
        for block in missing:
            print('  not in the output:')
            for line in block.split('\n'):
                print(f'    {line}')

    if bad:
        print(f'\n{bad} quoted traces are not what the bench prints.')
        return 1
    print('every quoted trace is what the bench prints')
    return 0


if __name__ == '__main__':
    sys.exit(main())
