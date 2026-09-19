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
fenced code blocks are not checked either, because a fragment showing
Markdown is code, not a link.

`docs/records/` is not checked: a record is history, written on its day and
kept as it was, and a link that pointed somewhere then is not a defect now.
"""

import pathlib
import re
import sys

ROOTS = ('packages', 'docs')
LINK = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
HEADING = re.compile(r'^#{1,6}\s+(.*)$')
EXTERNAL = re.compile(r'^(https?:|mailto:)')


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
    fenced = False
    for number, line in enumerate(path.read_text().split('\n'), start=1):
        if line.startswith('```'):
            fenced = not fenced
            continue
        if fenced:
            continue
        for target in LINK.findall(line):
            if EXTERNAL.match(target):
                continue
            file, _, anchor = target.partition('#')
            destination = (path.parent / file).resolve() if file else path
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
