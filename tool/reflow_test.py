"""Guards for tool/reflow.py: what a fill must never reshape.

Run from the repository root:

    python3 -m unittest tool/reflow_test.py
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import reflow  # noqa: E402


def fill(text):
    return reflow.reflow(text)[0]


class ListsKeepTheirShape(unittest.TestCase):
    def assertKept(self, text):
        self.assertEqual(fill(text), text)

    def test_a_loose_list_nested_under_a_numbered_item(self):
        # It sat after a blank line, with the next numbered item right
        # under it, and was filled into `* ошибки; * скрытые edge cases;`.
        self.assertKept(
            '3. Оцени:\n'
            '\n'
            '   * архитектуру и разделение ответственности;\n'
            '   * связанность и зацепление модулей;\n'
            '4. Найди:\n'
            '\n'
            '   * ошибки;\n'
            '   * скрытые edge cases;\n'
            '5. Проверь.\n'
        )

    def test_a_tight_list_nested_under_a_numbered_item(self):
        self.assertKept(
            '1. Заголовок плана\n'
            '   - первый пункт;\n'
            '   - второй пункт.\n'
            '2. Дальше.\n'
        )

    def test_a_paragraph_inside_an_item_keeps_its_indent(self):
        # Moved to column 0, it ends the list, and the `9.` under it,
        # which cannot interrupt a paragraph, becomes its last sentence.
        text = (
            '8. Короткий пункт.\n'
            '\n'
            '   Отдельный абзац восьмого пункта, написанный одной длинной '
            'строкой, поэтому он переносится, но с отступом в три пробела, '
            'а не в нулевой колонке.\n'
            '9. Следующий пункт.\n'
        )
        lines = fill(text).split('\n')
        paragraph = lines[2:-2]
        self.assertGreater(len(paragraph), 1)
        for line in paragraph:
            self.assertTrue(line.startswith('   ') and line[3] != ' ', line)
            self.assertLessEqual(len(line), 79, line)
        self.assertEqual(lines[-2], '9. Следующий пункт.')

    def test_a_long_nested_item_hangs_under_its_own_text(self):
        text = (
            '- Верх:\n'
            '  - вложенный пункт, достаточно длинный, чтобы не поместиться '
            'в одну строку шириной семьдесят девять колонок;\n'
        )
        lines = fill(text).rstrip('\n').split('\n')
        self.assertEqual(lines[0], '- Верх:')
        self.assertTrue(lines[1].startswith('  - вложенный'), lines[1])
        self.assertGreater(len(lines), 2)
        for line in lines[2:]:
            self.assertTrue(line.startswith('    ') and line[4] != ' ', line)
        for line in lines:
            self.assertLessEqual(len(line), 79, line)

    def test_a_block_indented_four_spaces_is_left_alone(self):
        # Four spaces after a blank line may be an indented code block.
        text = (
            'Абзац.\n'
            '\n'
            '    строка с отступом, которую нельзя переливать, даже если она '
            'уходит далеко за семьдесят девять колонок\n'
        )
        self.assertKept(text)
        self.assertEqual(reflow.reflow(text)[1], 1)


class FillStaysAFill(unittest.TestCase):
    def test_a_plain_paragraph_is_still_filled(self):
        self.assertEqual(fill('Первая строка\nвторая строка.\n'),
                         'Первая строка вторая строка.\n')

    def test_a_second_fill_changes_nothing(self):
        for text in (
            '1. Пункт\n   - вложенный пункт, достаточно длинный, чтобы '
            'не поместиться в одну строку шириной семьдесят девять колонок\n',
            '8. Пункт.\n\n   Абзац пункта, достаточно длинный, чтобы '
            'не поместиться в одну строку шириной семьдесят девять колонок\n',
        ):
            once = fill(text)
            self.assertEqual(fill(once), once)


if __name__ == '__main__':
    unittest.main()
