#!/usr/bin/env python3
"""Fills Markdown paragraphs to the project's 79 columns.

A line break inside a paragraph carries no meaning, so it should not be a
decision: the text is filled greedily, and a word that fits on the line
above goes there. Hand-wrapping drifts -- 75% of the prose sat below the
limit with room for the next word, and seventeen paragraphs carried a
short orphan line left over from an edit that rewrapped only what it
touched.

What is never touched: fenced code, tables, headings, blockquotes, blank
lines. A long word -- a URL, a code span -- is never broken, so a link too
wide for the limit keeps its own line, and the words before it stop early.

A list item keeps its marker and hangs its continuation under the text:
`- ` at two spaces, `1. ` at three. Nested lists are not handled; there
are none, and a file that grows one is reported rather than reshaped.

`docs/records/` is not filled. A record is written on its day and kept as
it was; a new one can still be filled by naming it as an argument.

Usage, from the repository root:

    python3 tool/reflow.py            # fill packages/, docs/, AGENTS.md
    python3 tool/reflow.py --check    # say what would change, touch nothing
    python3 tool/reflow.py path.md    # fill these files, records included
"""

import pathlib
import re
import sys
import textwrap

WIDTH = 79
ROOTS = ('packages', 'docs')
EXTRA = ('AGENTS.md',)

MARKER = re.compile(r'^([-*+] |\d+\. )')
UNTOUCHED = re.compile(r'^\s*(\||#{1,6} |>)')
# A wrapped line must not open a construct the original did not.
HAZARD = re.compile(r'^\s*([-*+] |\d+\. |#{1,6} |>|\||```)')
# Two things are one word here. `[label](url)`, because a break between
# `]` and `(` is not a link any more -- it is that text, in brackets, next
# to a URL in parentheses. And `a code span`, which survives a break but
# reads as two halves of nothing; a command is quoted to be copied.
LINK = r'!?\[[^\[\]]*\]\([^()\s]*\)'
SPAN = r'`[^`]+`'
ATOM = re.compile(f'{LINK}|{SPAN}')
LINK_ONLY = re.compile(LINK)
STAND_IN = re.compile('\x00(\\d+)~*\x00')
# A Russian preposition, conjunction or particle of one or two letters
# binds forward: left at the end of a line it hangs there, and the reader
# meets it without the word it governs. It is glued to the next word, and
# the pair breaks as one. Pronouns are not in the list on purpose -- `её`
# at the end of a line is nobody's mistake.
GLUED = {
    'в', 'во', 'к', 'ко', 'с', 'со', 'о', 'об', 'от', 'до', 'за', 'из',
    'на', 'по', 'у', 'и', 'а', 'но', 'да', 'то', 'ни', 'не', 'же', 'бы',
    'ли',
}
KEEP_TOGETHER = '\x01'


def files():
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob('*.md')):
            parts = path.parts
            if 'records' in parts or '.dart_tool' in parts:
                continue
            if 'doc' in parts and 'api' in parts:
                continue
            yield path
    for name in EXTRA:
        path = pathlib.Path(name)
        if path.exists():
            yield path



def glue(body, room):
    """Ties every hanging preposition to the word behind it."""
    words = body.split(' ')
    out = []
    for word in words:
        # The pair has to fit -- unless the next word does not fit on a
        # line by itself either. A link wider than the limit keeps its own
        # line anyway, and the preposition is better off there with it
        # than hanging at the end of the line above.
        if (out and out[-1].split(KEEP_TOGETHER)[-1].lower() in GLUED
                and (len(out[-1]) + 1 + len(word) <= room
                     or len(word) > room)):
            out[-1] += KEEP_TOGETHER + word
        else:
            out.append(word)
    return ' '.join(out)

def fill(body, first_indent, next_indent):
    # Each link becomes one space-free word of the same width, so the fill
    # measures it as it really is and cannot break it.
    links = []
    room = WIDTH - len(next_indent)

    def stand_in(text):
        links.append(text)
        tag = f'\x00{len(links) - 1}'
        return tag + '~' * (len(text) - len(tag) - 1) + '\x00'

    def hide(match):
        atom = match.group(0)
        # A span wider than the line has to break somewhere: a quoted trace
        # of a whole run is written to be read, not copied. A link is kept
        # whole at any width -- see `check_line_width.py` on long URLs.
        if len(atom) > room and not LINK_ONLY.fullmatch(atom):
            # It breaks after a comma, never inside an entry: `seek` at the
            # end of one line and `3 start` at the start of the next is two
            # things to the eye and one in the trace.
            pieces = re.split(r'(?<=,) ', atom)
            if len(pieces) > 1:
                return ' '.join(
                    stand_in(piece) if len(piece) <= room else piece
                    for piece in pieces
                )
            return atom
        return stand_in(atom)

    # An odd number of backticks is broken markup, not a span: leave the
    # spans alone there and keep the links safe.
    atom = ATOM if body.count('`') % 2 == 0 else LINK_ONLY

    lines = textwrap.wrap(
        glue(atom.sub(hide, body), room),
        WIDTH,
        initial_indent=first_indent,
        subsequent_indent=next_indent,
        break_long_words=False,
        break_on_hyphens=False,
    )
    return [
        STAND_IN.sub(lambda m: links[int(m.group(1))],
                     line.replace(KEEP_TOGETHER, ' ')) for line in lines
    ]


def wrap_block(block):
    """One run of paragraph lines, filled. Returns None if it is not ours."""
    items = []  # (marker, [lines])
    for line in block:
        match = MARKER.match(line)
        if match or not items:
            items.append((match.group(1) if match else '', [line[
                len(match.group(1)):] if match else line.strip()]))
        else:
            items[-1][1].append(line.strip())

    out = []
    for marker, parts in items:
        body = ' '.join(part.strip() for part in parts if part.strip())
        if not body:
            return None
        filled = fill(body, marker, ' ' * len(marker))
        if any(HAZARD.match(line) for line in filled[1:]):
            return None
        out.extend(filled)
    return out


def reflow(text):
    lines = text.split('\n')
    out = []
    kept = 0
    index = 0
    fenced = False
    # A YAML front matter is not prose: filled, it becomes one paragraph
    # and the file stops having a front matter at all.
    if lines and lines[0].strip() == '---':
        out.append(lines[0])
        index = 1
        while index < len(lines):
            out.append(lines[index])
            index += 1
            if out[-1].strip() == '---':
                break
    while index < len(lines):
        line = lines[index]
        if line.startswith('```'):
            fenced = not fenced
            out.append(line)
            index += 1
            continue
        if fenced or not line.strip() or UNTOUCHED.match(line):
            out.append(line)
            index += 1
            continue
        block = []
        while index < len(lines):
            line = lines[index]
            if (not line.strip() or line.startswith('```')
                    or UNTOUCHED.match(line)):
                break
            block.append(line)
            index += 1
        filled = wrap_block(block)
        if filled is None:
            kept += 1
            out.extend(block)
        else:
            out.extend(filled)
    return '\n'.join(out), kept


def main():
    argv = sys.argv[1:]
    check = '--check' in argv
    named = [pathlib.Path(a) for a in argv if not a.startswith('--')]
    targets = named or list(files())

    changed = []
    kept = 0
    for path in targets:
        before = path.read_text()
        after, left = reflow(before)
        kept += left
        if after != before:
            changed.append(path)
            if not check:
                path.write_text(after)

    if kept:
        print(f'{kept} blocks left as they were: not a paragraph this '
              f'script understands')
    if check:
        for path in changed:
            print(f'{path}: would be refilled')
        if changed:
            print(f'\n{len(changed)} files are not filled to {WIDTH} columns.')
            return 1
        print(f'every paragraph is filled to {WIDTH} columns')
        return 0

    for path in changed:
        print(f'{path}: refilled')
    print(f'{len(changed)} files refilled' if changed
          else 'nothing to refill')
    return 0


if __name__ == '__main__':
    sys.exit(main())
