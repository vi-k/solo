"""Guards for tool/archive_floor.py: what it reads out of pub and pubspecs.

Run from the repository root:

    python3 -m unittest tool/archive_floor_test.py

The run itself needs two SDKs and is the `floor` job of the gate. These
hold the parts that decide what that job looks at: which files make the
archive, which dependencies are taken down, and which SDK is the floor.
"""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import archive_floor  # noqa: E402

# What `flutter pub publish --dry-run` prints, cut down: the resolution
# comes first, the validation last, and the tree is between them.
DRY_RUN = """\
Resolving dependencies...
Downloading packages...
! solo 0.2.0 from path ../solo (overridden in ./pubspec_overrides.yaml)
Got dependencies!
Publishing flutter_solo 0.2.0 to https://pub.dev:
├── CHANGELOG.md (18 KB)
├── LICENSE (1 KB)
├── doc
│   └── mixins.md (9 KB)
├── example
│   ├── lib
│   │   └── main.dart (4 KB)
│   ├── pubspec.yaml (<1 KB)
│   └── test
│       └── profile_screen_test.dart (2 KB)
├── lib
│   ├── flutter_solo.dart (<1 KB)
│   └── src
│       └── solo_builder.dart (2 KB)
├── pubspec.yaml (<1 KB)
└── test
    ├── solo_builder_test.dart (9 KB)
    └── support
        └── plain_base.dart (<1 KB)

Total compressed archive size: 39 KB.
Validating package...
├── not a file of the archive (1 KB)
Package has 0 warnings and 2 hints.
"""

PUBSPEC = """\
name: flutter_solo
version: 0.2.0

environment:
  sdk: ^3.6.0
  flutter: '>=3.27.0'

dependencies:
  flutter:
    sdk: flutter
  meta: ^1.15.0
  solo: ^0.2.0

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
  lints: ^6.1.0
  test: ^1.26.3
"""

OVERRIDES = """\
# Use local solo until it is published.
dependency_overrides:
  solo:
    path: ../solo
"""


class TheArchiveIsTheTreePubPrints(unittest.TestCase):
    def test_every_file_with_its_directories(self):
        self.assertEqual(
            archive_floor.listed_files(DRY_RUN),
            [
                'CHANGELOG.md',
                'LICENSE',
                'doc/mixins.md',
                'example/lib/main.dart',
                'example/pubspec.yaml',
                'example/test/profile_screen_test.dart',
                'lib/flutter_solo.dart',
                'lib/src/solo_builder.dart',
                'pubspec.yaml',
                'test/solo_builder_test.dart',
                'test/support/plain_base.dart',
            ],
        )

    def test_a_directory_is_not_a_file(self):
        files = archive_floor.listed_files(DRY_RUN)
        self.assertNotIn('doc', files)
        self.assertNotIn('test/support', files)

    def test_the_tree_ends_where_it_ends(self):
        # A line shaped like an entry after the tree is not part of it.
        files = archive_floor.listed_files(DRY_RUN)
        self.assertNotIn('not a file of the archive', files)
        self.assertEqual(len(files), 11)

    def test_a_name_with_spaces_and_brackets(self):
        tree = '├── a file (draft).md (3 KB)\n└── b.md (1.5 MB)\n'
        self.assertEqual(
            archive_floor.listed_files(tree),
            ['a file (draft).md', 'b.md'],
        )

    def test_no_tree_is_no_files(self):
        self.assertEqual(
            archive_floor.listed_files('Because solo depends on...\n'), []
        )


class OnlyTheLintsAreDropped(unittest.TestCase):
    def test_both_lint_packages_go_and_nothing_else(self):
        stripped = archive_floor.without_lints(PUBSPEC)
        self.assertNotIn('lints', stripped)
        self.assertEqual(
            stripped,
            PUBSPEC.replace('  flutter_lints: ^6.0.0\n', '').replace(
                '  lints: ^6.1.0\n', ''
            ),
        )


class WhatIsTakenDown(unittest.TestCase):
    def test_a_constraint_is_and_a_map_is_not(self):
        # `flutter` is an SDK dependency, written as a map.
        self.assertEqual(
            archive_floor.hosted_dependencies(PUBSPEC), ['meta', 'solo']
        )

    def test_an_overridden_dependency_is_not(self):
        self.assertEqual(
            archive_floor.hosted_dependencies(PUBSPEC, OVERRIDES), ['meta']
        )

    def test_dev_dependencies_are_not(self):
        self.assertNotIn('test', archive_floor.hosted_dependencies(PUBSPEC))

    def test_a_pubspec_without_dependencies(self):
        self.assertEqual(
            archive_floor.hosted_dependencies('name: a\nversion: 1.0.0\n'),
            [],
        )


class TheFloorIsWhatThePubspecDeclares(unittest.TestCase):
    DART = 'Dart SDK version: 3.6.0 (stable) (Thu Dec 5 2024) on "linux"'
    FLUTTER = 'Flutter 3.27.0 • channel stable • https://github.com/x\n'

    def test_the_floor_itself(self):
        self.assertEqual(
            archive_floor.floor_mismatch(PUBSPEC, self.DART, self.FLUTTER), []
        )

    def test_a_newer_dart(self):
        newer = self.DART.replace('3.6.0', '3.13.0')
        self.assertEqual(
            archive_floor.floor_mismatch(PUBSPEC, newer, self.FLUTTER),
            ['Dart is 3.13.0, the pubspec declares 3.6.0'],
        )

    def test_a_newer_flutter(self):
        newer = self.FLUTTER.replace('3.27.0', '3.47.0')
        self.assertEqual(
            archive_floor.floor_mismatch(PUBSPEC, self.DART, newer),
            ['Flutter is 3.47.0, the pubspec declares 3.27.0'],
        )

    def test_a_raised_floor_the_job_did_not_follow(self):
        raised = PUBSPEC.replace('sdk: ^3.6.0', 'sdk: ^3.8.0')
        self.assertEqual(
            archive_floor.floor_mismatch(raised, self.DART, self.FLUTTER),
            ['Dart is 3.6.0, the pubspec declares 3.8.0'],
        )

    def test_a_pure_dart_package_asks_nothing_of_flutter(self):
        pure = PUBSPEC.replace("  flutter: '>=3.27.0'\n", '')
        self.assertEqual(archive_floor.floor_mismatch(pure, self.DART, ''), [])

    def test_no_flutter_on_the_path(self):
        self.assertEqual(
            archive_floor.floor_mismatch(PUBSPEC, self.DART, 'not found'),
            ['Flutter is missing, the pubspec declares 3.27.0'],
        )


if __name__ == '__main__':
    unittest.main()
