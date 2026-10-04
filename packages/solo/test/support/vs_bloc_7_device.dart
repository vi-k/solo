// Section 7 of `doc/vs-bloc.md`, "Removing selected pending work": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Ble {
  final trace = <String>[];
  var _connected = false;

  // A device answers nobody it is not connected to. Without this the fake
  // is more permissive than any radio, and a claim checked against it says
  // something about the fake.
  void _requireConnected(String call) {
    if (!_connected) {
      throw StateError('$call: not connected');
    }
  }

  Future<void> connect() async {
    trace.add('connect');
    await tick(30);
    _connected = true;
  }

  Future<int> battery() async {
    _requireConnected('battery');
    trace.add('battery');
    await tick(10);
    return 100;
  }

  Future<void> rename(String name) async {
    _requireConnected('rename');
    trace.add('rename $name');
    await tick(10);
  }

  Future<void> disconnect() async {
    trace.add('disconnect');
    await tick(10);
    _connected = false;
  }
}

sealed class DeviceState {
  const DeviceState();
}

final class Offline extends DeviceState {
  const Offline();

  @override
  String toString() => 'Offline';
}

final class Connected extends DeviceState {
  const Connected({this.battery});

  final int? battery;

  Connected copyWith({int? battery}) =>
      Connected(battery: battery ?? this.battery);

  @override
  String toString() => 'Connected(b:$battery)';
}

// The code of the page.

enum DeviceKey { connect, readBattery, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  Job<void> connect() => run<Offline, void>(
        key: DeviceKey.connect,
        (ctx) async {
          await ctx.join(_ble.connect);
          ctx.emit(const Connected());
        },
      );

  Job<void> readBattery() => run<Connected, void>(
        key: DeviceKey.readBattery,
        (ctx) async {
          final battery = await ctx.join(_ble.battery);
          ctx.emit(ctx.state.copyWith(battery: battery));
        },
      );

  Job<void> rename(String name) => run<Connected, void>(
        key: DeviceKey.rename,
        cancellable: false,
        (ctx) => ctx.join(() => _ble.rename(name)),
      );

  Job<void> disconnect() {
    queue.removeWhere((job) => job.key == DeviceKey.readBattery);
    return run<Connected, void>(
      key: DeviceKey.disconnect,
      (ctx) async {
        await ctx.join(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}

// What the test adds.

/// The sweeps the page names, which a caller outside the class cannot make:
/// `queue` is protected.
extension Sweeps on DeviceController {
  // ignore: invalid_use_of_protected_member
  void clearQueue({bool force = false}) => queue.clear(force: force);
}
