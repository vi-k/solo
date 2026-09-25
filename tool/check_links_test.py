"""Guards for tool/check_links.py: what a broken link looks like.

Run from the repository root:

    python3 -m unittest tool/check_links_test.py
"""

import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import check_links  # noqa: E402


class LinkCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def write(self, name, text):
        path = self.root / name
        path.write_text(text)
        return path

    def problems(self, path):
        return [problem for _, problem in check_links.offenders(path)]


class AFileThatIsNotThere(LinkCase):
    def test_a_page_that_was_renamed(self):
        page = self.write('a.md', 'See [the page](gone.md).\n')
        self.assertEqual(self.problems(page), ['no such file: gone.md'])

    def test_a_page_that_is_there(self):
        self.write('b.md', '# B\n')
        page = self.write('a.md', 'See [the page](b.md).\n')
        self.assertEqual(self.problems(page), [])


class AnAnchorThatIsNotThere(LinkCase):
    def test_a_heading_that_was_reworded(self):
        self.write('b.md', '# B\n\n## What a group hands back\n')
        page = self.write('a.md', 'See [it](b.md#what-a-group-returns).\n')
        self.assertEqual(
            self.problems(page), ['no such section: b.md#what-a-group-returns']
        )

    def test_a_heading_that_is_there(self):
        self.write('b.md', '# B\n\n## What a group hands back\n')
        page = self.write('a.md', 'See [it](b.md#what-a-group-hands-back).\n')
        self.assertEqual(self.problems(page), [])

    def test_a_russian_heading(self):
        # The translations link this way: `state.md#внешнее-состояние`.
        self.write('b.md', '# Б\n\n## Что группа отдаёт обратно\n')
        page = self.write(
            'a.md', 'См. [это](b.md#что-группа-отдаёт-обратно).\n'
        )
        self.assertEqual(self.problems(page), [])

    def test_a_heading_with_code_in_it(self):
        # GitHub drops the backticks and the dot: `ctx.join` -> ctxjoin.
        self.write('b.md', '# B\n\n## The `ctx.join` rule\n')
        page = self.write('a.md', 'See [it](b.md#the-ctxjoin-rule).\n')
        self.assertEqual(self.problems(page), [])

    def test_a_repeated_heading(self):
        # `### The first attempt` opens four sections of one page, and a
        # link to the second of them is ordinary.
        self.write(
            'b.md',
            '# B\n\n### The first attempt\n\n### The first attempt\n',
        )
        page = self.write('a.md', 'See [it](b.md#the-first-attempt-1).\n')
        self.assertEqual(self.problems(page), [])

    def test_a_repetition_that_does_not_exist(self):
        self.write('b.md', '# B\n\n### The first attempt\n')
        page = self.write('a.md', 'See [it](b.md#the-first-attempt-1).\n')
        self.assertEqual(
            self.problems(page), ['no such section: b.md#the-first-attempt-1']
        )

    def test_a_section_of_the_page_itself(self):
        page = self.write('a.md', '# A\n\n## Chains\n\n[up](#chains)\n')
        self.assertEqual(self.problems(page), [])

    def test_a_section_of_the_page_itself_that_is_gone(self):
        page = self.write('a.md', '# A\n\n## Chains\n\n[up](#links)\n')
        self.assertEqual(self.problems(page), ['no such section: #links'])


class WhatIsLeftAlone(LinkCase):
    def test_an_external_link(self):
        page = self.write(
            'a.md', 'See [pub](https://pub.dev/packages/solo).\n'
        )
        self.assertEqual(self.problems(page), [])

    def test_a_link_inside_a_fenced_block(self):
        # A fragment showing Markdown is code, not a link.
        page = self.write(
            'a.md',
            'Example:\n\n```markdown\n[a page](gone.md)\n```\n',
        )
        self.assertEqual(self.problems(page), [])

    def test_a_link_inside_a_code_span(self):
        # `docs/conventions.md` shows the syntax this way.
        page = self.write('a.md', 'Ссылка `[текст](адрес)` — одно слово.\n')
        self.assertEqual(self.problems(page), [])

    def test_a_heading_inside_a_fenced_block(self):
        # It is a comment of a shell fragment, not a section of the page.
        self.write('b.md', '# B\n\n```sh\n# Chains\n```\n')
        page = self.write('a.md', 'See [it](b.md#chains).\n')
        self.assertEqual(self.problems(page), ['no such section: b.md#chains'])


class WhereTheLinkPoints(LinkCase):
    def test_a_link_to_a_directory(self):
        # `camera.md` links to the example folder, and a folder has no
        # headings to look an anchor up in.
        (self.root / 'example').mkdir()
        page = self.write('a.md', 'See [the example](example).\n')
        self.assertEqual(self.problems(page), [])

    def test_a_link_into_another_directory(self):
        (self.root / 'doc').mkdir()
        self.write('doc/b.md', '# B\n')
        page = self.write('a.md', 'See [it](doc/b.md).\n')
        self.assertEqual(self.problems(page), [])

    def test_a_link_up_and_across(self):
        (self.root / 'one').mkdir()
        (self.root / 'two').mkdir()
        self.write('two/b.md', '# B\n')
        page = self.write('one/a.md', 'See [it](../two/b.md).\n')
        self.assertEqual(self.problems(page), [])


class ThisRepositoryOnGitHub(LinkCase):
    # `solo` links `async_job` by its GitHub address, because pub.dev shows
    # a package without its neighbours. The file is still in this tree.
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(check_links, 'REPO', self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        (self.root / 'doc').mkdir()
        self.write('doc/b.md', '# B\n\n## Cleanup order\n')

    def link(self, tail):
        return self.write('a.md', f'See [it]({check_links.BLOB}{tail}).\n')

    def test_a_section_that_is_there(self):
        page = self.link('doc/b.md#cleanup-order')
        self.assertEqual(self.problems(page), [])

    def test_a_section_that_was_reworded(self):
        page = self.link('doc/b.md#ordering')
        self.assertEqual(
            self.problems(page),
            [f'no such section: {check_links.BLOB}doc/b.md#ordering'],
        )

    def test_a_file_that_is_not_there(self):
        page = self.link('doc/gone.md')
        self.assertEqual(
            self.problems(page),
            [f'no such file: {check_links.BLOB}doc/gone.md'],
        )

    def test_another_repository_on_github(self):
        page = self.write(
            'a.md', 'See [it](https://github.com/felangel/bloc/issues/1).\n'
        )
        self.assertEqual(self.problems(page), [])


if __name__ == '__main__':
    unittest.main()
