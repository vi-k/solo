#!/usr/bin/env python3
"""Reports public dartdoc that has outgrown the shape of a hint.

The dartdoc of a member is the hint an editor shows and the entry pub.dev
lists; the cases behind it live on the pages, and the last paragraph links
there (decision 103 of `docs/settled.md`). Three rules hold that shape:

- the first paragraph is one sentence, since dartdoc lifts it into the
  member lists of the API pages;
- no paragraph of prose runs past PARAGRAPH lines;
- no block runs past BLOCK lines, a code block included.

The sixth full review found public dartdoc a second reference the length
of a page, and the wave after it cut nineteen members to the shape. The
seventh found paragraphs of 25 to 30 lines in four members the wave had
not listed, and the eighth found more. Each wave cut what its reviewer
named; nothing held the length.

Only what pub.dev shows is checked: a `///` block at column 0, or at
column 2 inside a top-level declaration, for a name that does not start
with `_` inside a declaration whose name does not either. `example/` and
`test/` are not checked.
"""

import pathlib
import re
import sys

PACKAGES = ('async_job', 'solo', 'flutter_solo')
PARAGRAPH = 10
BLOCK = 30

DECLARATION = re.compile(
    r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
    r'(?:class|mixin|enum|extension(?:\s+type)?|typedef)\s+([A-Za-z_]\w*)'
)
# A sentence ends where a stop is followed by more text. A code span, a
# link and an abbreviation hold stops that end nothing.
STOP = re.compile(r'[.!?]\s+\S')
NOT_A_STOP = re.compile(r'`[^`]*`|\[[^\]]*\](\([^)]*\))?|\b(?:e\.g|i\.e)\.')


def strip_generics(text):
    while True:
        stripped = re.sub(r'<[^<>]*>', '', text)
        if stripped == text:
            return text
        text = stripped


def name_of(declaration):
    """The name a declaration line gives, or '' for one with none."""
    if declaration.startswith('library'):
        return 'library'
    named = DECLARATION.match(declaration)
    if named:
        return named.group(1)
    plain = strip_generics(declaration)
    # A function type is a type, not a name: `void Function() onCancel(...)`,
    # `static void Function(String message)? debug;`.
    while True:
        bare = re.sub(r'\bFunction\s*\([^()]*\)\??', 'F', plain)
        if bare == plain:
            break
        plain = bare
    head = re.split(r'\(|=>| = |;|\{', plain)[0]
    words = re.findall(r'[A-Za-z_][\w.]*', head)
    return words[-1] if words else ''


def paragraphs(lines):
    """The paragraphs of prose in a block, each a list of lines."""
    found, current, fenced = [], [], False
    for line in lines:
        if line.startswith('```'):
            fenced = not fenced
            if current:
                found.append(current)
                current = []
            continue
        if fenced:
            continue
        if line:
            current.append(line)
        elif current:
            found.append(current)
            current = []
    if current:
        found.append(current)
    return found


def sentences(paragraph):
    text = NOT_A_STOP.sub('X', ' '.join(paragraph))
    return len(STOP.findall(text)) + 1


def problems(block):
    """What is wrong with one block of dartdoc, its `///` stripped."""
    found = []
    prose = paragraphs(block)
    if prose and not block[0].startswith('```'):
        count = sentences(prose[0])
        if count > 1:
            found.append(f'the first paragraph is {count} sentences')
    for paragraph in prose:
        if len(paragraph) > PARAGRAPH:
            found.append(
                f'a paragraph of {len(paragraph)} lines, '
                f'over {PARAGRAPH}: "{paragraph[0][:40]}"'
            )
    if len(block) > BLOCK:
        found.append(f'{len(block)} lines, over {BLOCK}')
    return found


def blocks(source):
    """Yields (line number, public name, block) for each public block."""
    lines = source.split('\n')
    owner = ''
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip().startswith('///'):
            if line and not line[0].isspace():
                named = DECLARATION.match(line)
                if named:
                    owner = named.group(1)
                elif not line.startswith(('}', '//', '@')):
                    owner = ''
            i += 1
            continue
        start = i
        indent = len(line) - len(line.lstrip())
        while i < len(lines) and lines[i].strip().startswith('///'):
            i += 1
        block = [
            re.sub(r'^///\s?', '', text.strip()) for text in lines[start:i]
        ]
        after = i
        while after < len(lines) and (
            not lines[after].strip() or lines[after].strip().startswith('@')
        ):
            after += 1
        declaration = lines[after].strip() if after < len(lines) else ''
        name = name_of(declaration)
        if indent == 0:
            public = not name.startswith('_')
            shown = name
        elif indent == 2:
            public = (
                bool(owner)
                and not owner.startswith('_')
                and not name.startswith('_')
            )
            shown = f'{owner}.{name}'
        else:
            public = False
            shown = name
        if public:
            yield start + 1, shown, block


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    count = 0
    for package in PACKAGES:
        lib = root / 'packages' / package / 'lib'
        for path in sorted(lib.rglob('*.dart')):
            source = path.read_text(encoding='utf-8')
            for number, name, block in blocks(source):
                for problem in problems(block):
                    count += 1
                    where = path.relative_to(root)
                    print(f'{where}:{number}: {name}: {problem}')
    if count:
        print(f'{count} problems of dartdoc shape')
        return 1
    print('every public dartdoc is a hint')
    return 0


if __name__ == '__main__':
    sys.exit(main())
