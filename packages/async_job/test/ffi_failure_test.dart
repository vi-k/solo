// A failure no weak reference can hold, past the four kinds `_isPlain` names.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';

import 'package:async_job/async_job.dart';
import 'package:test/test.dart';

Pointer<Void> _pointer() => Pointer<Void>.fromAddress(16);

/// Runs [body] as a job in a zone of its own and gives back its outcome and
/// what reached the zone.
Future<(Outcome<Object?>?, List<Object>)> _run(
  Future<Object?> Function(JobContext ctx) body, {
  bool cancel = false,
}) async {
  final zone = <Object>[];
  final done = Completer<Outcome<Object?>?>();
  runZonedGuarded(() {
    final job = Job<Object?>(body)..ignoreFailure();
    if (cancel) {
      Future<void>.delayed(Duration.zero, () => job.cancel().ignore());
    }
    job.done.then((_) => done.complete(job.outcome));
  }, (error, _) => zone.add(error));
  return (await done.future, zone);
}

void main() {
  test('a body that throws a Pointer ends Failed with it', () async {
    final (outcome, zone) = await _run((ctx) async {
      await Future<void>.delayed(Duration.zero);
      // ignore: only_throw_errors
      throw _pointer();
    });
    expect(outcome, isA<Failed>().having((f) => f.error, 'error', _pointer()));
    expect(zone, isEmpty);
  });

  test('a cancelled body that throws a Pointer still ends', () async {
    final gate = Completer<void>();
    final (outcome, _) = await _run((ctx) async {
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      // ignore: only_throw_errors
      throw _pointer();
    }, cancel: true);
    expect(gate.isCompleted, isTrue);
    expect(outcome, isA<Cancelled>());
  });

  test('ctx.join hands a Pointer on to the body as it is', () async {
    final (outcome, zone) = await _run(
      (ctx) => ctx.join(() => Future<Object?>.error(_pointer())),
    );
    expect(outcome, isA<Failed>().having((f) => f.error, 'error', _pointer()));
    expect(zone, isEmpty);
  });

  test('ctx.abandonable hands a Pointer thrown at once on as it is', () async {
    final (outcome, zone) = await _run(
      // ignore: only_throw_errors
      (ctx) => ctx.abandonable<Object?>(() => throw _pointer()),
    );
    expect(outcome, isA<Failed>().having((f) => f.error, 'error', _pointer()));
    expect(zone, isEmpty);
  });
}
