import 'dart:mirrors';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/compile_errors.dart';
import 'support/test_solo.dart';
import 'support/test_state.dart';

/// `SoloController` is the base `Solo` stands on: the observer gets a
/// controller as the base, `Solo` declares its queue members and the two
/// that close and cancel itself, and nothing outside the package extends
/// the base.

/// An observer that keeps the controllers it is told were created.
final class _Created extends SoloObserver {
  final created = <SoloController<Object>>[];

  @override
  void onCreate(SoloController<Object> controller) => created.add(controller);
}

void main() {
  tearDown(() => Solo.observer = null);

  test('an observer gets the controller as SoloController', () {
    final observer = _Created();
    Solo.observer = observer;
    final solo = TestSolo(const Working());
    expect(observer.created, [same(solo)]);
  });

  test('close and cancelAll are declared by Solo', () {
    // The published lints know a member by the class that declares it, and
    // `close` and `cancelAll` by the owner of the method: a member that
    // moved to the base would be lost to them without a word.
    final declared = reflectClass(
      Solo,
    ).declarations.keys.map(MirrorSystem.getName);
    expect(
      declared,
      containsAll([
        'close',
        'cancelAll',
        'enqueue',
        'enqueueJob',
        'job',
        'collect',
        'accumulate',
        'queue',
        'current',
        'lastJobWhere',
      ]),
    );
  });

  test('the base cannot be extended outside the library', () async {
    final errors = await compileErrors('''
import 'package:solo/solo.dart';

class X extends SoloController<int> {}
''');
    expect(errors, isNotEmpty);
    expect(errors, everyElement(contains('constructor')));
  });
}
