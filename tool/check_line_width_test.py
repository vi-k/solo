"""Guards for tool/check_line_width.py: which wide line is an offence.

Run from the repository root:

    python3 -m unittest tool/check_line_width_test.py
"""

import contextlib
import io
import os
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import check_line_width  # noqa: E402

LINK = '[ветвь, отказавшаяся от остановки группы]'
ANCHOR = '(children.md#что-группа-отдаёт-обратно)'


class WidthCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def offences(self, text):
        path = self.root / 'a.md'
        path.write_text(text)
        return [number for number, _, _ in check_line_width.offenders(path)]


class AWideLineThatCanBeFilled(WidthCase):
    def test_prose_that_was_not_wrapped(self):
        self.assertEqual(self.offences('слово ' * 20 + '\n'), [1])

    def test_prose_with_a_short_link_in_it(self):
        # The link fits; the line is long because nobody filled it.
        self.assertEqual(self.offences('слово ' * 15 + '[тут](b.md)\n'), [1])


class AWideLineThatCannotBeFilled(WidthCase):
    def test_a_link_wider_than_the_line(self):
        # 2026-09-19: the filler wrote this line at 81 columns, and the
        # check called it an offence. The link has no `http` in it.
        line = LINK + ANCHOR + ',\n'
        self.assertGreater(len(line.rstrip('\n')), check_line_width.WIDTH)
        self.assertEqual(self.offences(line), [])

    def test_a_long_url(self):
        self.assertEqual(
            self.offences('[pub](https://pub.dev/' + 'x' * 70 + ')\n'), []
        )

    def test_a_code_span_wider_than_the_line(self):
        self.assertEqual(self.offences('`' + 'x' * 90 + '`\n'), [])

    def test_an_indent_counts(self):
        # A token of 78 columns three spaces in does not fit either.
        self.assertEqual(self.offences('   `' + 'x' * 76 + '`\n'), [])

    def test_a_word_that_is_simply_long(self):
        self.assertEqual(self.offences('x' * 90 + '\n'), [])


class WhatIsNotProseAtAll(WidthCase):
    def test_a_table_row(self):
        self.assertEqual(self.offences('| ' + 'слово ' * 20 + '|\n'), [])

    def test_a_heading(self):
        self.assertEqual(self.offences('## ' + 'слово ' * 20 + '\n'), [])

    def test_a_fenced_block(self):
        self.assertEqual(
            self.offences('```dart\n' + 'x ' * 50 + '\n```\n'), []
        )


class TwoBlankLinesInARow(WidthCase):
    def doubled(self, text):
        path = self.root / 'a.md'
        path.write_text(text)
        return list(check_line_width.doubled_blanks(path))

    def test_one_blank_line_between_paragraphs(self):
        self.assertEqual(self.doubled('a\n\nb\n'), [])

    def test_two_blank_lines_between_paragraphs(self):
        self.assertEqual(self.doubled('a\n\n\nb\n'), [3])

    def test_three_name_both_extra_lines(self):
        # `errors.md` of `solo` had three, and both extra ones are offences.
        self.assertEqual(self.doubled('a\n\n\n\nb\n'), [3, 4])

    def test_a_line_of_spaces_is_blank(self):
        self.assertEqual(self.doubled('a\n\n  \nb\n'), [3])

    def test_blank_lines_inside_code_are_code(self):
        self.assertEqual(self.doubled('```dart\na();\n\n\nb();\n```\n'), [])

    def test_a_fence_ends_a_run(self):
        self.assertEqual(self.doubled('a\n\n```dart\n\nb();\n```\n'), [])



class TheExitCode(WidthCase):
    def run_main(self, text):
        (self.root / 'packages').mkdir()
        (self.root / 'packages' / 'a.md').write_text(text)
        here = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, here)
        with contextlib.redirect_stdout(io.StringIO()):
            return check_line_width.main()

    def test_a_clean_tree_passes(self):
        self.assertEqual(self.run_main('a\n\nb\n'), 0)

    def test_a_doubled_blank_line_alone_fails(self):
        self.assertEqual(self.run_main('a\n\n\nb\n'), 1)

    def test_a_wide_line_alone_fails(self):
        self.assertEqual(self.run_main('word ' * 20 + '\n'), 1)

    def test_agents_md_is_checked_too(self):
        (self.root / 'AGENTS.md').write_text('a\n\n\nc\n')
        self.assertEqual(self.run_main('a\n\nb\n'), 1)

if __name__ == '__main__':
    unittest.main()
