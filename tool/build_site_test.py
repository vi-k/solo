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


if __name__ == '__main__':
    unittest.main()
