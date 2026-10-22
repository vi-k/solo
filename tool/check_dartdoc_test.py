"""What the dartdoc check must call a problem, and what it must not."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check_dartdoc  # noqa: E402


def found(source):
    """(name, problems) for each public block of [source]."""
    return [
        (name, check_dartdoc.problems(block))
        for _, name, block in check_dartdoc.blocks(source)
    ]


class FirstParagraph(unittest.TestCase):
    def test_one_sentence_passes(self):
        self.assertEqual(check_dartdoc.problems(['Runs the body.']), [])

    def test_two_sentences_fail(self):
        self.assertEqual(
            check_dartdoc.problems(['Runs the body. Throws if it ran.']),
            ['the first paragraph is 2 sentences'],
        )

    def test_a_sentence_over_lines_is_one(self):
        block = ['Runs the body in the zone this is', 'called from.']
        self.assertEqual(check_dartdoc.problems(block), [])

    def test_stops_in_code_links_and_abbreviations_end_nothing(self):
        block = [
            'Takes `a. b`, as [Job.cancel] does, e.g. a',
            '[timeout](https://e.com/a. b) of it.',
        ]
        self.assertEqual(check_dartdoc.problems(block), [])

    def test_the_second_paragraph_may_hold_many(self):
        block = ['Runs the body.', '', 'It throws. It waits.']
        self.assertEqual(check_dartdoc.problems(block), [])


class Length(unittest.TestCase):
    def test_a_paragraph_over_the_limit(self):
        block = ['Runs.', ''] + ['word'] * (check_dartdoc.PARAGRAPH + 1)
        self.assertEqual(
            check_dartdoc.problems(block),
            [
                f'a paragraph of {check_dartdoc.PARAGRAPH + 1} lines, '
                f'over {check_dartdoc.PARAGRAPH}: "word"'
            ],
        )

    def test_code_is_not_a_paragraph(self):
        block = ['Runs.', '', '```dart'] + ['x;'] * 12 + ['```']
        self.assertEqual(check_dartdoc.problems(block), [])

    def test_a_block_over_the_limit_counts_its_code(self):
        block = ['Runs.', '', '```dart'] + ['x;'] * check_dartdoc.BLOCK
        block += ['```']
        self.assertEqual(
            check_dartdoc.problems(block)[-1],
            f'{check_dartdoc.BLOCK + 4} lines, over {check_dartdoc.BLOCK}',
        )


class Public(unittest.TestCase):
    def test_a_member_of_a_public_class_is_named_after_it(self):
        source = '\n'.join([
            'final class Job {',
            '  /// Runs. Twice.',
            '  void Function() onCancel(void Function() callback);',
            '',
            '  /// Prints. Twice.',
            '  static void Function(String message)? debug;',
            '}',
        ])
        self.assertEqual(
            found(source),
            [
                ('Job.onCancel', ['the first paragraph is 2 sentences']),
                ('Job.debug', ['the first paragraph is 2 sentences']),
            ],
        )

    def test_private_names_and_their_members_are_skipped(self):
        source = '\n'.join([
            '/// Holds. Twice.',
            'final _key = Object();',
            '',
            '/// Holds. Twice.',
            'final class _Shared {',
            '  /// Ends. Twice.',
            '  void finished() {}',
            '}',
            '',
            'final class Job {',
            '  /// Ends. Twice.',
            '  void _end() {}',
            '}',
        ])
        self.assertEqual(found(source), [])

    def test_a_local_block_is_skipped(self):
        source = '\n'.join([
            'void main() {',
            '    /// Local. Twice.',
            '    void inner() {}',
            '}',
        ])
        self.assertEqual(found(source), [])


if __name__ == '__main__':
    unittest.main()
