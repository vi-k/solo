"""Guards for tool/build_site.py: where a link of a page lands on the site.

Run from the repository root:

    python3 -m unittest tool/build_site_test.py
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import build_site  # noqa: E402

REPO = 'https://github.com/vi-k/solo'


def rewrite(target, source, locale='en'):
    return build_site.rewrite(target, locale, '', REPO, source)


class ASectionOfAnotherPackage(unittest.TestCase):
    # pub.dev shows a package without its neighbours, so a page links the
    # next package by its GitHub address. On the site that address is a
    # page of the site, and the section it names is a section of that page.
    def test_a_section_of_a_readme(self):
        self.assertEqual(
            rewrite(
                f'{REPO}/blob/main/packages/flutter_solo/README.md'
                '#selecting-one-value',
                'packages/solo/README.md',
            ),
            '/flutter_solo/#selecting-one-value',
        )

    def test_a_section_of_a_guide(self):
        self.assertEqual(
            rewrite(
                f'{REPO}/blob/main/packages/async_job/doc/cleanup.md'
                '#cleanup-order-and-late-results',
                'packages/solo/doc/resources.md',
            ),
            '/async_job/cleanup/#cleanup-order-and-late-results',
        )

    def test_a_russian_readme_keeps_its_language(self):
        self.assertEqual(
            rewrite(
                f'{REPO}/blob/main/packages/solo/README.ru.md#быстрый-старт',
                'docs/ru/solo/testing.md',
                locale='ru',
            ),
            '/ru/solo/#быстрый-старт',
        )

    def test_a_file_that_is_no_page(self):
        target = f'{REPO}/blob/main/packages/solo/lib/solo.dart'
        self.assertEqual(
            rewrite(target, 'packages/solo/doc/jobs.md'), target
        )


class ARelativeLink(unittest.TestCase):
    # A relative link is read from the file it stands in, as GitHub reads
    # it, and that file decides which package the target belongs to.
    def test_a_page_next_to_it(self):
        self.assertEqual(
            rewrite('state.md#external-state', 'packages/solo/doc/jobs.md'),
            '/solo/state/#external-state',
        )

    def test_a_guide_from_a_readme(self):
        self.assertEqual(
            rewrite('doc/state.md', 'packages/solo/README.md'),
            '/solo/state/',
        )

    def test_a_russian_page_of_another_package(self):
        # Read as a page of `solo`, it was `/ru/solo/cleanup/`, which
        # does not exist.
        self.assertEqual(
            rewrite(
                '../async_job/cleanup.md#порядок-уборки-и-поздние-результаты',
                'docs/ru/solo/resources.md',
                locale='ru',
            ),
            '/ru/async_job/cleanup/#порядок-уборки-и-поздние-результаты',
        )

    def test_a_russian_page_from_a_russian_readme(self):
        self.assertEqual(
            rewrite(
                '../../docs/ru/solo/vs-bloc.md',
                'packages/flutter_solo/README.ru.md',
                locale='ru',
            ),
            '/ru/solo/vs-bloc/',
        )

    def test_a_folder_goes_to_github(self):
        self.assertEqual(
            rewrite('../example', 'packages/solo/doc/camera.md'),
            f'{REPO}/tree/main/packages/solo/example',
        )
        self.assertEqual(
            rewrite(
                '../../../packages/solo/example', 'docs/ru/solo/camera.md',
                locale='ru',
            ),
            f'{REPO}/tree/main/packages/solo/example',
        )


class WhatIsLeftAlone(unittest.TestCase):
    def test_a_section_of_the_page_itself(self):
        self.assertEqual(
            rewrite('#chains', 'packages/async_job/doc/children.md'),
            '#chains',
        )

    def test_an_external_link(self):
        target = 'https://pub.dev/packages/solo'
        self.assertEqual(rewrite(target, 'packages/solo/README.md'), target)


SITE = 'https://docs.yet-another.dev'


def page(text, source, locale='en'):
    """The body of the page [text] becomes, without its front matter."""
    built = build_site.convert(text, locale, '', REPO, source, SITE)
    return built.split('---\n', 2)[2].lstrip('\n')


class ALinkToThePageItself(unittest.TestCase):
    # "Also on the documentation site" is a link to the page it stands in,
    # once the README is that page. The sentence goes, and nothing else.
    def test_the_readme_drops_it(self):
        text = (
            '# async_job\n\n## Guides\n\n'
            'Also on the [documentation site](https://docs.yet-another.dev/'
            'async_job/), with\nsearch.\n\n| Page | What |\n| --- | --- |\n'
        )
        self.assertEqual(
            page(text, 'packages/async_job/README.md'),
            '## Guides\n\n| Page | What |\n| --- | --- |\n',
        )

    def test_the_russian_readme_drops_its_own(self):
        text = (
            '# async_job\n\nОни же на [сайте документации]'
            '(https://docs.yet-another.dev/ru/async_job/),\nс поиском.\n\n'
            'Текст.\n'
        )
        self.assertEqual(
            page(text, 'packages/async_job/README.ru.md', 'ru'),
            'Текст.\n',
        )

    def test_a_link_to_another_page_of_the_site_stays(self):
        text = (
            '# solo\n\nSee [the core](https://docs.yet-another.dev/'
            'async_job/).\n'
        )
        self.assertIn(
            'docs.yet-another.dev/async_job/',
            page(text, 'packages/solo/README.md'),
        )

    def test_a_list_a_quote_and_other_links_stay(self):
        link = '[site](https://docs.yet-another.dev/solo/)'
        other = '[pub](https://pub.dev/packages/solo)'
        text = (
            f'# solo\n\n- one\n- {link}\n\n> {link}\n\n'
            f'On the {link} and on {other}.\n'
        )
        built = page(text, 'packages/solo/README.md')
        self.assertEqual(built.count(link), 3)

    def test_a_fence_inside_a_list_item_stays_closed(self):
        link = '[site](https://docs.yet-another.dev/solo/)'
        text = f'# solo\n\n- item\n\n  ```\n  {link}\n  ```\n\nAfter.\n'
        built = page(text, 'packages/solo/README.md')
        self.assertEqual(built.count('```'), 2)
        self.assertIn('After.', built)

    def test_no_real_readme_links_to_itself_on_the_site(self):
        # The guards above run on text written here. This one runs on the
        # READMEs themselves, so a change of wording that slips past the
        # filter -- a link without its slash, with an anchor -- shows up.
        settings = build_site.config()
        for source, _, segment, locale in build_site.sources():
            if not source.name.startswith('README'):
                continue
            relative = source.relative_to(build_site.REPO).as_posix()
            built = build_site.convert(
                source.read_text(encoding='utf-8'),
                locale,
                settings['base'].strip('/'),
                settings['repo'].rstrip('/'),
                relative,
                settings['site'],
            )
            itself = settings['site'].rstrip('/') + build_site.page_url(
                settings['base'].strip('/'), locale, segment
            )
            with self.subTest(relative):
                self.assertNotIn(itself.rstrip('/'), built)

    def test_code_and_tables_stay(self):
        link = '[site](https://docs.yet-another.dev/solo/)'
        text = f'# solo\n\n```\n{link}\n```\n\n| {link} |\n'
        built = page(text, 'packages/solo/README.md')
        self.assertEqual(built.count(link), 2)


if __name__ == '__main__':
    unittest.main()
