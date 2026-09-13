import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/src/listeners.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Listeners', () {
    test('calls listeners in subscription order', () {
      final log = <String>[];
      Listeners()
        ..add(() {
          log.add('first');
        })
        ..add(() {
          log.add('second');
        })
        ..add(() {
          log.add('third');
        })
        ..notify(Object());
      expect(log, ['first', 'second', 'third']);
    });

    test('two registrations of the same function produce two calls', () {
      var count = 0;
      void callback() => count++;

      Listeners()
        ..add(callback)
        ..add(callback)
        ..notify(Object());
      expect(count, 2);
    });

    test('remove deactivates the earliest active registration', () {
      final listeners = Listeners();
      final log = <String>[];
      var removedAndReadded = false;

      late final VoidCallback f;
      void a() {
        log.add('A');
        if (!removedAndReadded) {
          removedAndReadded = true;
          listeners
            ..remove(f)
            ..add(f);
        }
      }

      void g() => log.add('G');
      f = () => log.add('F');

      listeners
        ..add(a)
        ..add(f)
        ..add(g)
        ..add(f)
        ..notify(Object());
      expect(log, ['A', 'G', 'F']);

      log.clear();
      listeners.notify(Object());
      expect(log, ['A', 'G', 'F', 'F']);
    });

    test('listener removed during pass is not called', () {
      final listeners = Listeners();
      final log = <String>[];

      late final VoidCallback second;
      second = () => log.add('second');

      listeners
        ..add(() {
          log.add('first');
          expect(listeners.remove(second), isTrue);
        })
        ..add(second)
        ..add(() {
          log.add('third');
        })
        ..notify(Object());
      expect(log, ['first', 'third']);
    });

    test('listener added during pass waits for the next pass', () {
      final listeners = Listeners();
      final log = <String>[];
      var added = false;

      void second() => log.add('second');

      listeners
        ..add(() {
          log.add('first');
          if (!added) {
            added = true;
            listeners.add(second);
          }
        })
        ..notify(Object());
      expect(log, ['first']);

      log.clear();
      listeners.notify(Object());
      expect(log, ['first', 'second']);
    });

    test('re-adding a removed listener during pass waits for next pass', () {
      final listeners = Listeners();
      final log = <String>[];
      var readded = false;

      void b() => log.add('B');

      listeners
        ..add(() {
          log.add('A');
          if (!readded) {
            readded = true;
            listeners
              ..remove(b)
              ..add(b);
          }
        })
        ..add(b)
        ..notify(Object());
      expect(log, ['A']);

      log.clear();
      listeners.notify(Object());
      expect(log, ['A', 'B']);
    });

    test('nested notify preserves subscription order', () {
      final listeners = Listeners();
      final log = <String>[];
      var depth = 0;

      void a() {
        log.add('A:$depth');
        if (depth == 0) {
          depth++;
          listeners.notify(Object());
          depth--;
        }
      }

      void b() => log.add('B:$depth');
      void c() => log.add('C:$depth');

      listeners
        ..add(a)
        ..add(b)
        ..add(c)
        ..notify(Object());
      expect(log, ['A:0', 'A:1', 'B:1', 'C:1', 'B:0', 'C:0']);
    });

    test('nested notify respects removal during outer pass', () {
      final listeners = Listeners();
      final log = <String>[];
      var depth = 0;

      late final VoidCallback b;
      void a() {
        log.add('A:$depth');
        if (depth == 0) {
          listeners.remove(b);
          depth++;
          listeners.notify(Object());
          depth--;
        }
      }

      b = () => log.add('B:$depth');
      void c() => log.add('C:$depth');

      listeners
        ..add(a)
        ..add(b)
        ..add(c)
        ..notify(Object());
      expect(log, ['A:0', 'A:1', 'C:1', 'C:0']);
    });

    test('nested notify sees listeners added before it runs', () {
      final listeners = Listeners();
      final log = <String>[];
      var depth = 0;

      void c() => log.add('C:$depth');
      void a() {
        log.add('A:$depth');
        if (depth == 0) {
          listeners.add(c);
          depth++;
          listeners.notify(Object());
          depth--;
        }
      }

      void b() => log.add('B:$depth');

      listeners
        ..add(a)
        ..add(b)
        ..notify(Object());
      expect(log, ['A:0', 'A:1', 'B:1', 'C:1', 'B:0']);
    });

    test('nested notify with duplicate registrations and removal', () {
      final listeners = Listeners();
      final log = <String>[];
      var depth = 0;

      late final VoidCallback f;
      void a() {
        log.add('A:$depth');
        if (depth == 0) {
          listeners.remove(f);
          depth++;
          listeners.notify(Object());
          depth--;
        }
      }

      void g() => log.add('G:$depth');
      f = () => log.add('F:$depth');

      listeners
        ..add(a)
        ..add(g)
        ..add(f)
        ..add(f)
        ..notify(Object());
      expect(log, ['A:0', 'A:1', 'G:1', 'F:1', 'G:0', 'F:0']);
    });

    test('nested notify with removal and re-addition', () {
      final listeners = Listeners();
      final log = <String>[];
      var depth = 0;
      var manipulated = false;

      late final VoidCallback b;
      void a() {
        log.add('A:$depth');
        if (!manipulated) {
          manipulated = true;
          listeners.remove(b);
          depth++;
          listeners.notify(Object());
          depth--;
        } else if (depth == 1) {
          listeners.add(b);
        }
      }

      b = () => log.add('B:$depth');

      listeners
        ..add(a)
        ..add(b)
        ..notify(Object());
      expect(log, ['A:0', 'A:1']);

      log.clear();
      listeners.notify(Object());
      expect(log, ['A:0', 'B:0']);
    });

    test('throwing listener does not abort pass and error is reported', () {
      final log = <String>[];
      final errors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      Listeners()
        ..add(() {
          log.add('first');
        })
        ..add(() {
          throw StateError('boom');
        })
        ..add(() {
          log.add('third');
        })
        ..notify(Object());

      expect(log, ['first', 'third']);
      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
    });

    test('a throwing error reporter does not abort the selection pass', () {
      final source = ValueNotifier(0);
      addTearDown(source.dispose);
      final selection = SoloSelection<int, int>(source, (value) => value);
      final log = <String>[];
      final zoneErrors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (_) => throw StateError('reporter boom');
      addTearDown(() => FlutterError.onError = previous);

      selection
        ..addListener(() {
          throw StateError('listener boom');
        })
        ..addListener(() {
          log.add('after');
        });

      runZonedGuarded<void>(
        () {
          source.value = 1;
        },
        (error, _) => zoneErrors.add(error),
      );

      expect(log, ['after']);
      expect(zoneErrors, [isA<StateError>()]);
      expect(zoneErrors.single.toString(), contains('reporter boom'));
    });

    test('isEmpty and clear lifecycle', () {
      final listeners = Listeners();
      expect(listeners.isEmpty, isTrue);

      void a() {}
      listeners.add(a);
      expect(listeners.isEmpty, isFalse);

      listeners.clear();
      expect(listeners.isEmpty, isTrue);

      final log = <String>[];
      listeners
        ..add(() {
          log.add('first');
          listeners.clear();
        })
        ..add(() {
          log.add('second');
        })
        ..notify(Object());
      expect(log, ['first']);
      expect(listeners.isEmpty, isTrue);
    });

    test('removes a tear-off, which is equal but not identical', () {
      final counter = _Counter();
      expect(counter.tick == counter.tick, isTrue);
      expect(identical(counter.tick, counter.tick), isFalse);

      final listeners = Listeners()..add(counter.tick);
      expect(listeners.remove(counter.tick), isTrue);
      listeners.notify(Object());
      expect(counter.calls, 0);
      expect(listeners.isEmpty, isTrue);
    });

    test('remove returns false when listener is unknown', () {
      final listeners = Listeners();
      expect(listeners.remove(() {}), isFalse);

      void a() {}
      listeners.add(a);
      expect(listeners.remove(() {}), isFalse);
      expect(listeners.remove(a), isTrue);
      expect(listeners.remove(a), isFalse);
    });
  });
}

final class _Counter {
  int calls = 0;

  void tick() => calls++;
}
