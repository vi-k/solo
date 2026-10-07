#!/usr/bin/env python3
"""Check that the Russian translations mirror their English originals.

Pairs checked:
  * packages/solo/README.md          <-> packages/solo/README.ru.md
  * packages/async_job/README.md     <-> packages/async_job/README.ru.md
  * packages/flutter_solo/README.md  <-> packages/flutter_solo/README.ru.md
  * packages/solo/doc/vs-bloc.md     <-> docs/ru/solo/vs-bloc.md
  * packages/solo/doc/accumulation.md <-> docs/ru/solo/accumulation.md
  * packages/solo/doc/<page>.md    <-> docs/ru/solo/<page>.md
  * packages/async_job/doc/<page>.md <-> docs/ru/async_job/<page>.md
  * packages/flutter_solo/doc/<page>.md <-> docs/ru/flutter_solo/<page>.md

Compares:
  * the sequence of heading levels (count and order),
  * the number of fenced code blocks,
  * for each pair of code blocks, the sequence of non-comment lines
    (lines whose trimmed form starts with // or /// are dropped),
  * the shape of the prose around them: under each heading, as many
    paragraphs, list items and table rows as the original has, in the same
    places between the code blocks,
  * dashes in the translation: there are to be none, in the prose or in the
    comments of its code.

Prose and comment text are expected to differ: they are the translation.
The last check is there because the first three let a paragraph go: the
README of flutter_solo went without the last paragraph of its "Testing"
section in Russian, with every heading and every block of code in place.

The translations are written without dashes, and nothing but attention held
that: the Russian state page of solo kept twenty of them through two rounds
of reading.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PAIRS = [
    (
        REPO / "packages" / "solo" / "README.md",
        REPO / "packages" / "solo" / "README.ru.md",
    ),
    (
        REPO / "packages" / "async_job" / "README.md",
        REPO / "packages" / "async_job" / "README.ru.md",
    ),
    (
        REPO / "packages" / "flutter_solo" / "README.md",
        REPO / "packages" / "flutter_solo" / "README.ru.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "vs-bloc.md",
        REPO / "docs" / "ru" / "solo" / "vs-bloc.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "accumulation.md",
        REPO / "docs" / "ru" / "solo" / "accumulation.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "jobs.md",
        REPO / "docs" / "ru" / "solo" / "jobs.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "state.md",
        REPO / "docs" / "ru" / "solo" / "state.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "cancellation.md",
        REPO / "docs" / "ru" / "solo" / "cancellation.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "resources.md",
        REPO / "docs" / "ru" / "solo" / "resources.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "children.md",
        REPO / "docs" / "ru" / "solo" / "children.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "streams.md",
        REPO / "docs" / "ru" / "solo" / "streams.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "errors.md",
        REPO / "docs" / "ru" / "solo" / "errors.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "testing.md",
        REPO / "docs" / "ru" / "solo" / "testing.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "camera.md",
        REPO / "docs" / "ru" / "solo" / "camera.md",
    ),
    (
        REPO / "packages" / "flutter_solo" / "doc" / "mixins.md",
        REPO / "docs" / "ru" / "flutter_solo" / "mixins.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "outcomes.md",
        REPO / "docs" / "ru" / "async_job" / "outcomes.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "cancellation.md",
        REPO / "docs" / "ru" / "async_job" / "cancellation.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "children.md",
        REPO / "docs" / "ru" / "async_job" / "children.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "streams.md",
        REPO / "docs" / "ru" / "async_job" / "streams.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "cleanup.md",
        REPO / "docs" / "ru" / "async_job" / "cleanup.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "observing.md",
        REPO / "docs" / "ru" / "async_job" / "observing.md",
    ),
    (
        REPO / "packages" / "async_job" / "doc" / "extending.md",
        REPO / "docs" / "ru" / "async_job" / "extending.md",
    ),
]

FENCE = re.compile(r"^\s*```")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
# An em dash anywhere; an en dash unless it stands in a range of numbers.
DASH = re.compile(r"\u2014|(?<!\d)\u2013|\u2013(?!\d)")
# A hyphen between spaces, which is a dash typed on the keyboard.
HYPHEN_DASH = re.compile(r"(?<=\S) - (?=\S)")
CODE_SPAN = re.compile(r"`[^`]*`")


def parse(path: Path):
    headings = []  # (level, text)
    blocks = []  # list of (info_string, [lines])
    in_block = False
    info = ""
    cur: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            if in_block:
                blocks.append((info, cur))
                cur = []
                in_block = False
            else:
                in_block = True
                info = line.strip().lstrip("`").strip()
            continue
        if in_block:
            cur.append(line)
            continue
        m = HEADING.match(line)
        if m:
            headings.append((len(m.group(1)), m.group(2).strip()))
    if in_block:
        blocks.append((info, cur))
    return headings, blocks


def shape(path: Path) -> list[str]:
    """What the document is made of, block by block.

    A heading by its level, a fenced block by its fence, a list and a table
    by the number of their lines, and `paragraph` for the rest. Lines of one
    block stand together; a blank line, a fence or a heading ends it.
    """
    blocks: list[str] = []
    fenced = False
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if fenced:
            fenced = not line.startswith("```")
        elif line.startswith("```"):
            blocks.append(line.strip())
            fenced = True
            inside = False
        elif not line.strip():
            inside = False
        elif HEADING.match(line):
            blocks.append(line.split(" ")[0])
            inside = False
        elif line.startswith("|") or line.startswith("- "):
            kind = "table" if line.startswith("|") else "list"
            if inside and blocks[-1].startswith(kind):
                lines = int(blocks[-1].split(" ")[-1]) + 1
                blocks[-1] = f"{kind} of {lines}"
            else:
                blocks.append(f"{kind} of 1")
            inside = True
        elif not inside:
            blocks.append("paragraph")
            inside = True
    return blocks


def dashes(path: Path) -> list[str]:
    """The lines of a translation that carry a dash, as `path:line: text`.

    A dash counts wherever it stands, a comment in a code block included: the
    comments are translated too. A hyphen between spaces counts in the prose
    only, outside code spans, where it cannot be a minus.
    """
    found: list[str] = []
    fenced = False
    lines = path.read_text(encoding="utf-8").splitlines()
    for number, line in enumerate(lines, start=1):
        if FENCE.match(line):
            fenced = not fenced
            continue
        prose = "" if fenced else CODE_SPAN.sub("``", line)
        if DASH.search(line) or HYPHEN_DASH.search(prose):
            found.append(f"{path.relative_to(REPO)}:{number}: {line.strip()}")
    return found


def strip_trailing_comment(line: str) -> str:
    """Drop a trailing // comment that is not inside a string literal."""
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "/" and line.startswith("//", i):
            return line[:i].rstrip()
        i += 1
    return line


# Deviations allowed in a translation's code blocks. Each entry is announced
# in the output, so an intentional deviation can never hide a real one.
PATH_EXCEPTIONS: dict[str, str] = {}


def code_lines(lines: list[str], *, translation: bool = False) -> list[str]:
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        line = strip_trailing_comment(line)
        if translation and line in PATH_EXCEPTIONS:
            line = PATH_EXCEPTIONS[line]
        out.append(line)
    return out


def check(orig: Path, tran: Path) -> list[str]:
    problems: list[str] = []
    print(f"== {orig.relative_to(REPO)} <-> {tran.relative_to(REPO)}")

    ho, bo = parse(orig)
    ht, bt = parse(tran)

    lo = [lvl for lvl, _ in ho]
    lt = [lvl for lvl, _ in ht]
    if lo != lt:
        problems.append(
            f"heading levels differ:\n  original:    {lo}\n  translation: {lt}"
        )
    else:
        print(f"headings: {len(lo)} in the same order, levels {lo}")

    if len(bo) != len(bt):
        problems.append(
            f"code block count differs: original {len(bo)}, translation {len(bt)}"
        )
    else:
        print(f"code blocks: {len(bo)} in both files")
    for k, v in PATH_EXCEPTIONS.items():
        print(f"allowed path deviation: translation {k!r} == original {v!r}")

    so = shape(orig)
    st = shape(tran)
    if so != st:
        at = next(
            (i for i, (a, b) in enumerate(zip(so, st)) if a != b),
            min(len(so), len(st)),
        )
        problems.append(
            f"{tran.relative_to(REPO)}: the prose differs in shape at block "
            f"{at + 1} of {len(so)} (the translation has {len(st)}):\n"
            f"  original:    {so[max(at - 2, 0):at + 2]}\n"
            f"  translation: {st[max(at - 2, 0):at + 2]}"
        )
    else:
        prose = sum(not b.startswith(("#", "```")) for b in so)
        print(f"prose: {prose} paragraphs, lists and tables in the same places")

    dashed = dashes(tran)
    if dashed:
        problems.append(
            f"{len(dashed)} lines of the translation carry a dash:\n    "
            + "\n    ".join(dashed)
        )
    else:
        print("dashes: none in the translation")

    for i, (a, b) in enumerate(zip(bo, bt), start=1):
        info_a, lines_a = a
        info_b, lines_b = b
        if info_a != info_b:
            problems.append(
                f"block {i}: fence info differs: {info_a!r} vs {info_b!r}"
            )
        ca = code_lines(lines_a)
        cb = code_lines(lines_b, translation=True)
        if ca != cb:
            only_a = [x for x in ca if x not in cb]
            only_b = [x for x in cb if x not in ca]
            detail = []
            if only_a:
                detail.append("    only in original:    " + repr(only_a[:5]))
            if only_b:
                detail.append("    only in translation: " + repr(only_b[:5]))
            if not detail:
                detail.append("    same lines, different order")
            problems.append(
                f"block {i} ({info_a}): {len(ca)} vs {len(cb)} code lines\n"
                + "\n".join(detail)
            )

    return problems


def main() -> int:
    problems: list[str] = []
    for orig, tran in PAIRS:
        problems += check(orig, tran)

    if problems:
        print("\nDIFFERENCES FOUND:")
        for p in problems:
            print("  - " + p)
        return 1

    print("no differences")
    return 0


if __name__ == "__main__":
    sys.exit(main())
