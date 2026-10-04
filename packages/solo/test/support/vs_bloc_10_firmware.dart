// Section 10 of `doc/vs-bloc.md`, "Finishing an in-flight write before restarting": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:async';

import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Chunk {
  const Chunk(this.index);

  final int index;
}

class Ble {
  final trace = <String>[];
  final written = <int>[];

  // A BLE write cannot be told to stop: the chunk handed to the stack
  // lands, and the only way to keep the wire clear is to wait for it.
  Future<void> write(Chunk chunk) async {
    trace.add('write ${chunk.index} start');
    await tick(20);
    written.add(chunk.index);
    trace.add('write ${chunk.index} end');
  }
}

sealed class FirmwareState {
  const FirmwareState();
}

sealed class NotBroken extends FirmwareState {
  const NotBroken();
}

final class Idle extends NotBroken {
  const Idle();

  @override
  String toString() => 'Idle';
}

final class Flashing extends NotBroken {
  Flashing(this.written, this.total);

  final int written;
  final int total;

  @override
  String toString() => 'Flashing($written/$total)';
}

final class Broken extends FirmwareState {
  Broken(this.error);

  final Object error;

  @override
  String toString() => 'Broken($error)';
}

// The code of the page.

final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
        (ctx) async {
          var written = 0;
          for (final chunk in chunks) {
            await ctx.join(() => _ble.write(chunk));
            ctx.emit(Flashing(++written, chunks.length));
          }
        },
      );
}

// What the test adds.

extension HardwareFailure on FirmwareController {
  // ignore: invalid_use_of_protected_member
  void hardwareFailed(Object error) => externalSetState(Broken(error));
}

/// A parent with a child that cleans up, and one with unattended work.
final class ParentController extends Solo<FirmwareState> {
  ParentController() : super(const Idle());

  final seen = <String>[];

  Job<void> withChild() => run<FirmwareState, void>(
        key: 'parent',
        (ctx) async {
          final child = job<FirmwareState, void>((childCtx) async {
            childCtx.onDispose(() async {
              await tick(20);
              seen.add('the cleanup of the child ended');
            });
            await childCtx.wait(() => tick(30));
            seen.add('the body of the child ended');
          });
          unawaited(ctx.run(child));
          seen.add('the body of the parent ended');
        },
      );

  Job<void> withUnattended() => run<FirmwareState, void>(
        key: 'upload',
        (ctx) async {
          ctx.unattended(() async {
            await tick(50);
            throw StateError('the unattended work failed');
          });
          seen.add('the body ended');
        },
      );

  Job<void> mark() => run<FirmwareState, void>(
        key: 'mark',
        (ctx) async => seen.add('the next job started'),
      );

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      seen.add('onError of ${job.key}: $error');
}
