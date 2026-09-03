#!/usr/bin/env python3
"""Check that the Russian translations mirror their English originals.

Pairs checked:
  * packages/solo/README.md          <-> packages/solo/README.ru.md
  * packages/flutter_solo/README.md  <-> packages/flutter_solo/README.ru.md
  * packages/solo/doc/vs-bloc.md     <-> docs/ru/solo/vs-bloc.md

Compares:
  * the sequence of heading levels (count and order),
  * the number of fenced code blocks,
  * for each pair of code blocks, the sequence of non-comment lines
    (lines whose trimmed form starts with // or /// are dropped).

Prose and comment text are expected to differ: they are the translation.
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
        REPO / "packages" / "flutter_solo" / "README.md",
        REPO / "packages" / "flutter_solo" / "README.ru.md",
    ),
    (
        REPO / "packages" / "solo" / "doc" / "vs-bloc.md",
        REPO / "docs" / "ru" / "solo" / "vs-bloc.md",
    ),
]

FENCE = re.compile(r"^\s*```")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")


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
