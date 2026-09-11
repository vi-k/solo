#!/usr/bin/env python3
"""Assembles the documentation site's content from the packages.

The packages stay the single source of truth: `site/src/content/docs/` is
generated here and kept out of git. Nothing is edited by hand there, and
nothing is duplicated -- a README or a page in `doc/` is read where it
lives, given the frontmatter Starlight wants, and written out with its
links pointing at site URLs instead of files in the repository.

Both languages go to the site. English is the root locale and comes from
the packages; Russian lives under `/ru/` and comes from the `README.ru.md`
of each package and from `docs/ru/<package>/`. The two sides mirror each
other because `tool/check_translations.py` holds them to it.

Usage, from the repository root:

    python3 tool/build_site.py

Then, in `site/`: `npm ci && npm run build`.
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

# Locale -> the path segment it is served under. English is the root.
LOCALES = {'en': '', 'ru': 'ru'}

HEADING = re.compile(r'^#\s+(.*)$')
LINK = re.compile(r'\]\(([^)]+)\)')
# A link may cross into another package's folder; the path says which.
IN_PACKAGE = re.compile(r'(?:^|/)(?:packages|ru)/([A-Za-z_]+)/')


def config():
    with open(SITE / 'site.json', encoding='utf-8') as file:
        return json.load(file)


def sources():
    """Yields (source path, path under OUT, package segment, locale)."""
    for package, segment in PACKAGES.items():
        english = REPO / 'packages' / package
        yield english / 'README.md', f'{segment}/index.md', segment, 'en'
        for page in sorted((english / 'doc').glob('*.md')):
            yield page, f'{segment}/{page.name}', segment, 'en'

        yield (english / 'README.ru.md', f'ru/{segment}/index.md',
               segment, 'ru')
        russian = REPO / 'docs' / 'ru' / package
        if russian.is_dir():
            for page in sorted(russian.glob('*.md')):
                yield page, f'ru/{segment}/{page.name}', segment, 'ru'


def page_url(base, locale, segment, name=None):
    parts = [base, LOCALES[locale], segment]
    if name is not None:
        parts.append(name)
    return '/' + '/'.join(part for part in parts if part) + '/'


def rewrite(target, segment, locale, base, repo):
    """Turns one markdown link target into a site URL."""
    if target.startswith(('#', 'mailto:')):
        return target

    # The absolute links between packages are pages of this site.
    blob = f'{repo}/blob/main/packages/'
    if target.startswith(blob):
        package, _, tail = target[len(blob):].partition('/')
        if package in PACKAGES:
            if tail.startswith('README'):
                return page_url(base, locale, PACKAGES[package])
            if tail.startswith('doc/') and tail.endswith('.md'):
                name = tail[len('doc/'):-len('.md')]
                return page_url(base, locale, PACKAGES[package], name)

    if target.startswith(('http://', 'https://')):
        return target

    path, _, anchor = target.partition('#')
    anchor = f'#{anchor}' if anchor else ''

    named = IN_PACKAGE.search(path)
    package = named.group(1) if named and named.group(1) in PACKAGES else None
    where = PACKAGES[package] if package else segment

    if path.endswith('.md'):
        name = pathlib.PurePosixPath(path).name
        if name.startswith('README'):
            return page_url(base, locale, where) + anchor
        return page_url(base, locale, where, name[:-len('.md')]) + anchor

    # Anything else is a folder in the repository -- the example package, a
    # source directory. Those have no page here, so they point at GitHub.
    if named:
        source = f'packages/{package or named.group(1)}'
        tail = path[named.end():]
    else:
        source = f'packages/{where}'
        tail = path.lstrip('./')
    return f'{repo}/tree/main/{source}/{tail}{anchor}'


def convert(text, segment, locale, base, repo, source):
    title = None
    fenced = False
    body = []
    for line in text.split('\n'):
        if line.startswith('```'):
            fenced = not fenced
        if title is None and not fenced:
            match = HEADING.match(line)
            if match:
                title = match.group(1)
                continue
        body.append(line)

    if title is None:
        raise SystemExit(f'{source}: no title heading')

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
                lambda m: ']({})'.format(
                    rewrite(m.group(1), segment, locale, base, repo)
                ),
                line,
            )
        )

    escaped = title.replace('\\', '\\\\').replace('"', '\\"')
    # "Edit this page" must reach the file that is actually edited, which
    # is the one in the repository, not the copy generated here.
    edit = f'{repo}/edit/main/{source}'
    front = f'---\ntitle: "{escaped}"\neditUrl: "{edit}"\n---\n\n'
    return front + '\n'.join(out).rstrip() + '\n'


def main():
    settings = config()
    base = settings['base'].strip('/')
    repo = settings['repo'].rstrip('/')

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    written = 0
    for source, relative, segment, locale in sources():
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            convert(
                source.read_text(encoding='utf-8'),
                segment,
                locale,
                base,
                repo,
                source.relative_to(REPO).as_posix(),
            ),
            encoding='utf-8',
        )
        written += 1

    for page in sorted(HAND_WRITTEN.rglob('*.md')):
        target = OUT / page.relative_to(HAND_WRITTEN)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(page, target)
        written += 1

    print(f'wrote {written} pages under {OUT.relative_to(REPO)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
