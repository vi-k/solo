"""Guards for tool/archive_floor.py: what it reads out of pub and pubspecs.

Run from the repository root:

    python3 -m unittest tool/archive_floor_test.py

The run itself needs two SDKs and is the `floor` job of the gate. These
hold the parts that decide what that job looks at -- which files make the
archive, which dependencies are taken down and how far, which SDK is the
floor -- and the order of the run, with the SDK replaced by a recorder:
what is run in which root, and that nothing red or empty passes for green.
"""

import contextlib
import io
import pathlib
import shutil
import sys
import tempfile
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
            archive_floor.hosted_dependencies(PUBSPEC),
            [('meta', '1.15.0'), ('solo', '0.2.0')],
        )

    def test_an_overridden_dependency_is_not(self):
        self.assertEqual(
            archive_floor.hosted_dependencies(PUBSPEC, OVERRIDES),
            [('meta', '1.15.0')],
        )

    def test_dev_dependencies_are_not(self):
        hosted = archive_floor.hosted_dependencies(PUBSPEC)
        self.assertNotIn('test', [name for name, _ in hosted])

    def test_a_pubspec_without_dependencies(self):
        self.assertEqual(
            archive_floor.hosted_dependencies('name: a\nversion: 1.0.0\n'),
            [],
        )

    def test_the_shapes_a_pubspec_comes_in(self):
        # A comment in column 0 inside the block, one after the key, CRLF,
        # and a last line without a newline: each used to cost the list a
        # package or the whole of itself.
        for pubspec in (
            'dependencies:\n# why\n  meta: ^1.15.0\n  solo: ^0.2.0\n',
            'dependencies: # ours\n  meta: ^1.15.0\n  solo: ^0.2.0\n',
            'dependencies:\r\n  meta: ^1.15.0\r\n  solo: ^0.2.0\r\n',
            'dependencies:\n  meta: ^1.15.0\n  solo: ^0.2.0',
        ):
            with self.subTest(pubspec=pubspec):
                self.assertEqual(
                    archive_floor.hosted_dependencies(pubspec),
                    [('meta', '1.15.0'), ('solo', '0.2.0')],
                )

    def test_the_lower_bound_of_each_form(self):
        pubspec = (
            'dependencies:\n'
            '  a: ^1.2.3\n'
            "  b: '>=2.0.0 <3.0.0'\n"
            '  c: 4.5.6\n'
            '  d: any\n'
            '  e: ">= 0.1.0-dev.1"\n'
        )
        self.assertEqual(
            archive_floor.hosted_dependencies(pubspec),
            [
                ('a', '1.2.3'),
                ('b', '2.0.0'),
                ('c', '4.5.6'),
                ('d', None),
                ('e', '0.1.0-dev.1'),
            ],
        )


LOCK = """\
packages:
  async:
    dependency: "direct dev"
    description:
      name: async
      url: "https://pub.dev"
    source: hosted
    version: "2.13.1"
  meta:
    dependency: "direct main"
    description:
      name: meta
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "{meta}"
  metadata:
    dependency: transitive
    source: hosted
    version: "9.9.9"
"""


class TheTakingDownIsRead(unittest.TestCase):
    def test_at_the_bound(self):
        self.assertEqual(
            archive_floor.above_the_bound(
                LOCK.format(meta='1.15.0'), [('meta', '1.15.0')]
            ),
            [],
        )

    def test_above_the_bound(self):
        # What a dev dependency that wants a newer `meta` would leave.
        self.assertEqual(
            archive_floor.above_the_bound(
                LOCK.format(meta='1.18.3'), [('meta', '1.15.0')]
            ),
            ['meta is 1.18.3, the lower bound is 1.15.0'],
        )

    def test_not_resolved_at_all(self):
        self.assertEqual(
            archive_floor.above_the_bound(
                LOCK.format(meta='1.15.0'), [('solo', '0.3.0')]
            ),
            ['solo is missing, the lower bound is 0.3.0'],
        )

    def test_no_bound_is_nothing_to_hold(self):
        self.assertEqual(
            archive_floor.above_the_bound(
                LOCK.format(meta='1.19.0'), [('meta', None)]
            ),
            [],
        )


class OnlyTheDevDependenciesGo(unittest.TestCase):
    def test_the_block_and_nothing_after_it(self):
        pubspec = PUBSPEC + '\ntopics:\n  - async\n'
        stripped = archive_floor.without_dev_dependencies(pubspec)
        self.assertNotIn('dev_dependencies', stripped)
        self.assertNotIn('flutter_test', stripped)
        self.assertIn('  meta: ^1.15.0\n', stripped)
        self.assertIn('topics:\n  - async\n', stripped)

    def test_a_pubspec_without_them(self):
        pubspec = 'name: a\ndependencies:\n  meta: ^1.15.0\n'
        self.assertEqual(
            archive_floor.without_dev_dependencies(pubspec), pubspec
        )


class TheFloorIsWhatThePubspecDeclares(unittest.TestCase):
    DART = 'Dart SDK version: 3.6.0 (stable) (Thu Dec 5 2024) on "linux"'
    FLUTTER = 'Flutter 3.27.0 • channel stable • https://github.com/x\n'

    def mismatch(self, pubspec, dart=None, flutter=None):
        return archive_floor.floor_mismatch(
            pubspec,
            self.DART if dart is None else dart,
            self.FLUTTER if flutter is None else flutter,
        )

    def test_the_floor_itself(self):
        self.assertEqual(self.mismatch(PUBSPEC), [])

    def test_a_newer_dart(self):
        self.assertEqual(
            self.mismatch(PUBSPEC, dart=self.DART.replace('3.6.0', '3.13.0')),
            ['Dart is 3.13.0, the pubspec declares 3.6.0'],
        )

    def test_a_patch_above_the_floor(self):
        # Compared whole, not by its first characters.
        self.assertEqual(
            self.mismatch(PUBSPEC, dart=self.DART.replace('3.6.0', '3.6.1')),
            ['Dart is 3.6.1, the pubspec declares 3.6.0'],
        )

    def test_a_newer_flutter(self):
        newer = self.FLUTTER.replace('3.27.0', '3.47.0')
        self.assertEqual(
            self.mismatch(PUBSPEC, flutter=newer),
            ['Flutter is 3.47.0, the pubspec declares 3.27.0'],
        )

    def test_a_prerelease_of_the_floor_is_not_the_floor(self):
        beta = self.FLUTTER.replace('3.27.0', '3.27.0-0.1.pre')
        self.assertEqual(
            self.mismatch(PUBSPEC, flutter=beta),
            ['Flutter is 3.27.0-0.1.pre, the pubspec declares 3.27.0'],
        )

    def test_the_version_after_a_banner(self):
        # Flutter prints a notice above its version on a first run.
        banner = 'Welcome to Flutter!\n\n' + self.FLUTTER
        self.assertEqual(self.mismatch(PUBSPEC, flutter=banner), [])

    def test_a_raised_floor_the_job_did_not_follow(self):
        raised = PUBSPEC.replace('sdk: ^3.6.0', 'sdk: ^3.8.0')
        self.assertEqual(
            self.mismatch(raised),
            ['Dart is 3.6.0, the pubspec declares 3.8.0'],
        )

    def test_the_forms_a_floor_is_written_in(self):
        for form in ("'>=3.6.0 <4.0.0'", '">=3.6.0 <4.0.0"', "'>= 3.6.0'"):
            with self.subTest(form=form):
                pubspec = PUBSPEC.replace('sdk: ^3.6.0', f'sdk: {form}')
                self.assertEqual(self.mismatch(pubspec), [])
        caret = PUBSPEC.replace("flutter: '>=3.27.0'", 'flutter: ^3.27.0')
        self.assertEqual(self.mismatch(caret), [])

    def test_a_floor_that_cannot_be_read_is_not_a_pass(self):
        for pubspec in (
            PUBSPEC.replace('sdk: ^3.6.0', "sdk: '>3.5.0 <4.0.0'"),
            PUBSPEC.replace('  sdk: ^3.6.0\n', ''),
            PUBSPEC.replace('  sdk: ^3.6.0', '    sdk: ^3.6.0'),
        ):
            with self.subTest(pubspec=pubspec):
                self.assertIn(
                    'no floor of Dart is declared in the pubspec',
                    self.mismatch(pubspec),
                )
        unbounded = PUBSPEC.replace("  flutter: '>=3.27.0'\n", '')
        self.assertEqual(
            self.mismatch(unbounded),
            ['no floor of Flutter is declared in the pubspec'],
        )

    def test_a_pure_dart_package_asks_nothing_of_flutter(self):
        pure = PUBSPEC.replace("  flutter: '>=3.27.0'\n", '').replace(
            '  flutter:\n    sdk: flutter\n', ''
        ).replace('  flutter_test:\n    sdk: flutter\n', '')
        self.assertEqual(self.mismatch(pure, flutter=''), [])

    def test_no_flutter_on_the_path(self):
        self.assertEqual(
            self.mismatch(PUBSPEC, flutter='not found'),
            ['Flutter is missing, the pubspec declares 3.27.0'],
        )


TREE = """\
Publishing {name} 0.2.0 to https://pub.dev:
├── example
│   ├── bin
│   │   └── main.dart (1 KB)
│   ├── pubspec.yaml (<1 KB)
│   └── test
│       └── main_test.dart (1 KB)
├── lib
│   └── {name}.dart (1 KB)
├── pubspec.yaml (<1 KB)
└── test
    └── {name}_test.dart (1 KB)

Validating package...
Package has 0 warnings.
"""

PURE = """\
name: {name}
environment:
  sdk: ^3.6.0
dependencies:
  meta: ^1.15.0
dev_dependencies:
  lints: ^6.1.0
  test: ^1.26.3
"""


class Sandbox(unittest.TestCase):
    """A checkout of two packages and an SDK that records what it is asked."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.top = pathlib.Path(directory.name).resolve()
        self.repo = self.top / 'checkout' / 'low'
        for name in ('low', 'high'):
            package = self.repo / 'packages' / name
            for file in (
                f'lib/{name}.dart',
                f'test/{name}_test.dart',
                'example/bin/main.dart',
                'example/test/main_test.dart',
                'README.ru.md',
            ):
                (package / file).parent.mkdir(parents=True, exist_ok=True)
                (package / file).write_text('')
            (package / 'pubspec.yaml').write_text(PURE.format(name=name))
            (package / 'example' / 'pubspec.yaml').write_text(
                PURE.format(name=f'{name}_example')
            )
        overrides = self.repo / 'packages' / 'high' / 'pubspec_overrides.yaml'
        overrides.write_text(
            'dependency_overrides:\n  low:\n    path: ../low\n'
        )
        self.calls = []
        self.failing = None
        self.dry_run_exit = 0
        self.meta = '1.15.0'
        self.dart = 'Dart SDK version: 3.6.0 (stable)'
        for name, value in (
            ('REPO', self.repo),
            ('PACKAGES', ('low', 'high')),
            ('output_of', self.sdk),
        ):
            original = getattr(archive_floor, name)
            self.addCleanup(setattr, archive_floor, name, original)
            setattr(archive_floor, name, value)

    def sdk(self, command, cwd=None):
        if command[1:] == ['--version']:
            return 0, self.dart
        root = pathlib.Path(cwd)
        self.calls.append((root, ' '.join(command), self.devs(root)))
        if command[1:3] == ['pub', 'publish']:
            return self.dry_run_exit, TREE.format(name=root.name)
        if command[1:3] in (['pub', 'get'], ['pub', 'downgrade']):
            (root / 'pubspec.lock').write_text(LOCK.format(meta=self.meta))
        if self.failing is not None and self.failing in ' '.join(command):
            return 1, 'the name of what failed\nSome tests failed.'
        return 0, '+1: All tests passed!'

    @staticmethod
    def devs(root):
        pubspec = root / 'pubspec.yaml'
        return pubspec.exists() and 'dev_dependencies' in pubspec.read_text()

    def do(self, *arguments):
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            code = archive_floor.main(list(arguments))
        return code, printed.getvalue()

    def staged(self):
        out = self.top / 'layout'
        code, printed = self.do('stage', str(out))
        self.assertEqual(code, 0, printed)
        self.calls.clear()
        return out

    def ran(self, out, root):
        return [
            (command, devs)
            for where, command, devs in self.calls
            if where == out / root
        ]


class StageLaysOutTheArchive(Sandbox):
    def test_the_files_pub_lists_and_no_others(self):
        out = self.staged()
        self.assertTrue((out / 'low' / 'lib' / 'low.dart').exists())
        program = out / 'low' / 'example' / 'bin' / 'main.dart'
        self.assertTrue(program.exists())
        self.assertFalse((out / 'low' / 'README.ru.md').exists())

    def test_the_lints_go_from_the_package_and_from_its_example(self):
        out = self.staged()
        for pubspec in ('low/pubspec.yaml', 'low/example/pubspec.yaml'):
            text = (out / pubspec).read_text()
            self.assertNotIn('lints', text)
            self.assertIn('test: ^1.26.3', text)

    def test_the_overrides_of_the_tree_come_along(self):
        out = self.staged()
        self.assertTrue((out / 'high' / 'pubspec_overrides.yaml').exists())
        self.assertFalse((out / 'low' / 'pubspec_overrides.yaml').exists())

    def test_what_pub_said_is_printed(self):
        code, printed = self.do('stage', str(self.top / 'layout'))
        self.assertEqual(code, 0)
        self.assertIn('Package has 0 warnings.', printed)

    def test_a_dry_run_that_fails_fails_the_step(self):
        self.dry_run_exit = 65
        code, printed = self.do('stage', str(self.top / 'layout'))
        self.assertEqual(code, 1)
        self.assertIn('the dry run failed, exit 65', printed)

    def test_a_second_stage_replaces_the_first(self):
        out = self.staged()
        (out / 'low' / 'stale.dart').write_text('')
        self.assertEqual(self.do('stage', str(out))[0], 0)
        self.assertFalse((out / 'low' / 'stale.dart').exists())


class StageDeletesNothingItDidNotMake(Sandbox):
    def refused(self, out):
        code, printed = self.do('stage', str(out))
        self.assertEqual(code, 2, printed)
        self.assertEqual(self.calls, [])
        return printed

    def test_the_parent_of_a_checkout_named_like_a_package(self):
        # 2026-10-01: the checkout is called `solo`, and so is a package.
        # `stage ..` reached `rmtree(out / 'solo')`, which was the checkout.
        self.assertIn('holds the repository', self.refused(self.repo.parent))
        self.assertTrue((self.repo / 'packages' / 'low' / 'lib').exists())

    def test_the_parent_written_with_dots(self):
        self.refused(self.repo / 'packages' / '..' / '..')
        self.assertTrue((self.repo / 'packages').exists())

    def test_the_repository_and_a_directory_inside_it(self):
        self.assertIn('inside the repository', self.refused(self.repo))
        self.assertIn(
            'inside the repository', self.refused(self.repo / 'build' / 'out')
        )

    def test_a_link_into_the_repository(self):
        inside = self.repo / 'build'
        inside.mkdir()
        link = self.top / 'link'
        link.symlink_to(inside, target_is_directory=True)
        self.assertIn('inside the repository', self.refused(link))
        self.assertEqual(list(inside.iterdir()), [])

    def test_a_directory_of_somebody_elses(self):
        other = self.top / 'projects'
        (other / 'low' / 'src').mkdir(parents=True)
        (other / 'low' / 'src' / 'kept.txt').write_text('mine')
        self.assertIn('not a layout of this script', self.refused(other))
        kept = other / 'low' / 'src' / 'kept.txt'
        self.assertEqual(kept.read_text(), 'mine')

    def test_an_empty_directory_is_fine(self):
        out = self.top / 'empty'
        out.mkdir()
        self.assertEqual(self.do('stage', str(out))[0], 0)


class RunReplaysTheGate(Sandbox):
    def test_a_package_as_a_dependency_and_then_with_its_tests(self):
        out = self.staged()
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 0, printed)
        self.assertEqual(
            self.ran(out, 'low'),
            [
                ('dart pub get', False),
                ('dart pub downgrade meta', False),
                ('dart analyze --no-fatal-warnings lib', False),
                ('dart pub get', True),
                ('dart pub downgrade meta', True),
                ('dart test', True),
            ],
        )
        self.assertIn(': 4 roots', printed)

    def test_the_example_and_its_program(self):
        out = self.staged()
        self.do('run', str(out))
        self.assertEqual(
            [command for command, _ in self.ran(out, 'high/example')],
            [
                'dart pub get',
                'dart pub downgrade meta',
                'dart analyze --no-fatal-warnings lib',
                'dart run bin/main.dart',
                'dart pub get',
                'dart pub downgrade meta',
                'dart test',
            ],
        )

    def test_the_dev_dependencies_are_back_after_a_failure(self):
        out = self.staged()
        self.failing = 'analyze'
        self.assertEqual(self.do('run', str(out))[0], 1)
        pubspec = (out / 'low' / 'pubspec.yaml').read_text()
        self.assertIn('test: ^1.26.3', pubspec)

    def test_a_failing_step_is_red_and_printed_whole(self):
        out = self.staged()
        self.failing = 'dart test'
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 1)
        self.assertIn('dart test: FAILED, exit 1', printed)
        self.assertIn('the name of what failed', printed)
        self.assertIn('red: low, low/example, high, high/example', printed)

    def test_a_failing_step_stops_its_root_and_not_the_others(self):
        out = self.staged()
        self.failing = 'pub downgrade'
        self.assertEqual(self.do('run', str(out))[0], 1)
        self.assertEqual(
            [command for command, _ in self.ran(out, 'low')],
            ['dart pub get', 'dart pub downgrade meta'],
        )
        self.assertTrue(self.ran(out, 'high'))

    def test_a_dependency_that_stayed_above_its_bound_is_red(self):
        out = self.staged()
        self.meta = '1.18.3'
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 1)
        self.assertIn('meta is 1.18.3, the lower bound is 1.15.0', printed)
        self.assertNotIn('dart analyze', ' '.join(c for _, c, _ in self.calls))

    def test_an_archive_without_tests_is_red(self):
        out = self.staged()
        shutil.rmtree(out / 'low' / 'test')
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 1)
        self.assertIn('no tests in the archive', printed)
        self.assertIn('red: low', printed)

    def test_an_sdk_that_is_not_the_floor_runs_nothing(self):
        out = self.staged()
        self.dart = 'Dart SDK version: 3.13.0 (stable)'
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 1)
        self.assertEqual(self.calls, [])
        self.assertIn('Dart is 3.13.0, the pubspec declares 3.6.0', printed)

    def test_any_sdk_is_asked_for_and_not_assumed(self):
        out = self.staged()
        self.dart = 'Dart SDK version: 3.13.0 (stable)'
        code, _ = self.do('run', str(out), '--any-sdk')
        self.assertEqual(code, 0)
        self.assertTrue(self.calls)

    def test_a_missing_package_is_red(self):
        out = self.staged()
        shutil.rmtree(out / 'high')
        code, printed = self.do('run', str(out))
        self.assertEqual(code, 1)
        self.assertIn('no layout of this package', printed)

    def test_a_directory_that_is_not_a_layout(self):
        code, printed = self.do('run', str(self.repo / 'packages'))
        self.assertEqual(code, 2)
        self.assertEqual(self.calls, [])
        self.assertIn('not a layout made by `stage`', printed)


class NothingIsPublished(Sandbox):
    def test_the_only_call_to_publish_is_a_dry_run(self):
        self.do('stage', str(self.top / 'layout'))
        self.do('run', str(self.top / 'layout'))
        publishing = [c for _, c, _ in self.calls if 'publish' in c]
        self.assertEqual(publishing, ['dart pub publish --dry-run'] * 2)

    def test_anything_but_the_two_steps_is_the_usage(self):
        for arguments in (['publish', 'x'], ['stage'], ['run', 'a', 'b'], []):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.do(*arguments)[0], 2)
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
