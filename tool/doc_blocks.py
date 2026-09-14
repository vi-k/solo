#!/usr/bin/env python3
"""Addresses the code blocks of a Markdown document by name, never position.

A bench that builds runnable files out of a document has to name the block
it wants. Numbering them is the obvious way and the wrong one: insert a
block into a section and every key after it points at somebody else's
code, silently. So a block is addressed by the section it is in and by a
name it declares -- `1/NotesBloc`.

A block declaring several names answers to each of them. A name declared
twice in one section answers to neither: the entry is poisoned, and a use
of it fails here instead of quietly building the wrong file. A block that
declares nothing is addressed by a slug of its first line.

Blocks come out byte-identical. That is the whole point: the code in the
document is the code that ran.

Usage:

    python3 doc_blocks.py --list doc.md            # every key
    python3 doc_blocks.py --emit 1/NotesBloc doc.md
    python3 doc_blocks.py --list --lang=python doc.md
    python3 doc_blocks.py --list --declares='^def (\\w+)' doc.md

Exit code of --list is 1 if any key is poisoned.
"""

import pathlib
import re
import sys

# What a block declares at column 0. Dart is the default; another language
# is either in this table or given as --declares=<regexp with one group>.
DECLARES = {
    'dart': r'^(?:(?:final|abstract|sealed|base|interface) )*'
            r'(?:class|enum|mixin|extension|typedef)\s+(\w+)'
            r'|^[A-Za-z_][\w<>,?\[\] ]*\s(\w+)\s*\(',
    'python': r'^(?:class|def|async def)\s+(\w+)',
    'go': r'^(?:func|type)\s+(\w+)',
    'rust': r'^(?:pub\s+)?(?:fn|struct|enum|trait|mod)\s+(\w+)',
    'js': r'^(?:export\s+)?(?:default\s+)?'
          r'(?:class|function|const|let)\s+(\w+)',
}
DECLARES['ts'] = DECLARES['js']
POISONED = object()


def slug(line):
    # \W keeps the letters of any alphabet: a Russian heading has to end up
    # with a key, not with an empty string.
    return re.sub(r'\W+', '-', line.lower(), flags=re.UNICODE).strip('-')[:30]


def sections(text):
    """(key, body) per `## ` heading. A numbered heading keeps its number."""
    for part in re.split(r'\n## ', text)[1:]:
        head = part.split('\n')[0].strip()
        number = re.match(r'(\d+)\.', head)
        yield (number.group(1) if number else slug(head)), part


def blocks(text, lang, declares):
    """{key: source}, with a repeated name poisoning its key."""
    found = {}
    fence = re.compile(f'```{lang}\\n(.*?)```', re.S)
    names = re.compile(declares, re.M)
    for section, body in sections(text):
        for block in fence.findall(body):
            declared = [a or b for a, b in _pairs(names.findall(block))]
            for name in declared or [slug(block.split('\n')[0])]:
                key = f'{section}/{name}'
                found[key] = POISONED if key in found else block
    return found


def _pairs(matches):
    """findall gives strings for one group, tuples for several."""
    for match in matches:
        yield match if isinstance(match, tuple) else (match, '')


def main():
    argv = sys.argv[1:]
    lang = 'dart'
    declares = None
    emit = None
    names = []
    for arg in argv:
        if arg.startswith('--lang='):
            lang = arg.split('=', 1)[1]
        elif arg.startswith('--declares='):
            declares = arg.split('=', 1)[1]
        elif arg == '--emit':
            emit = ''
        elif arg.startswith('--'):
            continue
        elif emit == '':
            emit = arg
        else:
            names.append(arg)
    if not names or ('--emit' in argv and not emit):
        print(__doc__.strip().split('Usage:')[-1].strip())
        return 2

    declares = declares or DECLARES.get(lang, DECLARES['dart'])
    found = blocks(pathlib.Path(names[0]).read_text(), lang, declares)

    if emit:
        block = found.get(emit)
        if block is None:
            print(f'no block answers to {emit}', file=sys.stderr)
            return 1
        if block is POISONED:
            print(f'{emit} is declared twice in its section', file=sys.stderr)
            return 1
        sys.stdout.write(block)
        return 0

    bad = 0
    for key, block in found.items():
        if block is POISONED:
            bad += 1
            print(f'!! {key}\tdeclared twice in its section')
            continue
        lines = block.rstrip('\n').split('\n')
        print(f'   {key}\t{len(lines)} lines\t{lines[0][:50]}')
    print(f'\n{len(found)} keys, {bad} poisoned')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
