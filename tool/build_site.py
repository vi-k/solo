#!/usr/bin/env python3
"""Assembles the documentation site's content from the packages.

The packages stay the single source of truth: `site/src/content/docs/` is
generated here and kept out of git. Nothing is edited by hand there, and
nothing is duplicated -- a README or a page in `doc/` is read where it
lives, given the frontmatter Starlight wants, and written out with its
links pointing at site URLs instead of files in the repository.

Usage, from the repository root:

    python3 tool/build_site.py

Then, in `site/`: `npm ci && npm run build`.

Only the English originals go to the site. The Russian translations in
`docs/ru/` are for the owner and for agents; the site does not carry them.
"""

import json
import pathlib
import re
import shutil
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SITE = REPO / 'site'
OUT = SITE / 'src' / 'content' / 'docs'
HAND_WRITTEN = SITE / 'content'

# Package directory -> the segment it gets in the site's URLs.
PACKAGES = {
    'solo': 'solo',
    'async_job': 'async_job',
    'flutter_solo': 'flutter_solo',
}

HEADING = re.compile(r'^#\s+(.*)$')
LINK = re.compile(r'\]\(([^)]+)\)')


def config():
    with open(SITE / 'site.json', encoding='utf-8') as file:
        return json.load(file)


def sources():
    """Yields (source path, output path relative to OUT, url prefix)."""
    for package, segment in PACKAGES.items():
        readme = REPO / 'packages' / package / 'README.md'
        yield readme, pathlib.Path(segment) / 'index.md', segment
        doc = REPO / 'packages' / package / 'doc'
        if not doc.is_dir():
            continue
        for page in sorted(doc.glob('*.md')):
            yield page, pathlib.Path(segment) / page.name, segment


def rewrite(target, segment, base, repo):
    """Turns one markdown link target into a site URL."""
    if target.startswith(('#', 'mailto:')):
        return target

    # The one absolute link between packages: it is a page of this site.
    blob = f'{repo}/blob/main/packages/'
    if target.startswith(blob):
        rest = target[len(blob):]
        package, _, tail = rest.partition('/')
        if package in PACKAGES:
            if tail == 'README.md':
                return f'{base}/{PACKAGES[package]}/'
            if tail.startswith('doc/') and tail.endswith('.md'):
                name = tail[len('doc/'):-len('.md')]
                return f'{base}/{PACKAGES[package]}/{name}/'

    if target.startswith(('http://', 'https://')):
        return target

    path, _, anchor = target.partition('#')
    anchor = f'#{anchor}' if anchor else ''

    if path.endswith('.md'):
        name = pathlib.PurePosixPath(path).stem
        if name == 'README':
            return f'{base}/{segment}/{anchor}'
        return f'{base}/{segment}/{name}/{anchor}'

    # Anything else is a directory in the repository: the example package,
    # a source folder. Those have no page here, so they point at GitHub.
    cleaned = path.lstrip('./')
    for package in PACKAGES:
        if PACKAGES[package] == segment:
            source = f'packages/{package}'
            break
    if path.startswith('../'):
        return f'{repo}/tree/main/{source}/{cleaned}{anchor}'
    return f'{repo}/tree/main/{source}/{path}{anchor}'


def convert(text, segment, base, repo, source):
    lines = text.split('\n')
    title = None
    fenced = False
    body = []
    for line in lines:
        if line.startswith('```'):
            fenced = not fenced
        if title is None and not fenced:
            match = HEADING.match(line)
            if match:
                title = match.group(1)
                continue
        body.append(line)

    if title is None:
        raise SystemExit('a page without a title heading')

    while body and not body[0].strip():
        body.pop(0)

    out = []
    fenced = False
    for line in body:
        if line.startswith('```'):
            fenced = not fenced
            out.append(line)
            continue
        if fenced:
            out.append(line)
            continue
        out.append(
            LINK.sub(
                lambda m: f']({rewrite(m.group(1), segment, base, repo)})',
                line,
            )
        )

    escaped = title.replace('\\', '\\\\').replace('"', '\\"')
    # "Edit this page" must reach the file that is actually edited, which
    # is the one in the package, not the copy generated here.
    edit = f'{repo}/edit/main/{source}'
    front = f'---\ntitle: "{escaped}"\neditUrl: "{edit}"\n---\n\n'
    return front + '\n'.join(out).rstrip() + '\n'


def main():
    settings = config()
    base = settings['base'].rstrip('/')
    repo = settings['repo'].rstrip('/')

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    written = 0
    for source, relative, segment in sources():
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            convert(
                source.read_text(encoding='utf-8'),
                segment,
                base,
                repo,
                source.relative_to(REPO).as_posix(),
            ),
            encoding='utf-8',
        )
        written += 1

    for page in sorted(HAND_WRITTEN.glob('*.md')):
        shutil.copyfile(page, OUT / page.name)
        written += 1

    print(f'wrote {written} pages under {OUT.relative_to(REPO)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
