import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scopo/scopo.dart';

import '../test/support/device_app_attempts.dart';
import 'support/probe.dart';

/// The first attempts that need a person at the phone: the permission
/// dialog, another app taking the camera, leaving the app during a
/// recording; and the app's answer to leaving the app, its own camera
/// screen, with the states and errors of its session in the journal.
///
/// Each attempt opens from the menu; the journal of every call, event and
/// state of the lifecycle shows under it and is kept in
/// `probe-journal.txt` in the temporary folder of the app, where the host
/// reads it after the run. Built and installed with
/// `flutter run -t integration_test/probe_app.dart`; on iOS in profile
/// mode, so that it starts from the home screen without a debugger.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final file = File('${Directory.systemTemp.path}/probe-journal.txt');
  final journal = ProbeJournal(file: file);
  journal.note('app start');
  CameraPlatform.instance = RecordingCameraPlatform(
    CameraPlatform.instance,
    journal,
  );
  AppLifecycleListener(
    onStateChange: (state) => journal.note('lifecycle ${state.name}'),
  );
  Solo.observer = SessionNotes(journal);
  // The camera screen waits on its `scopeKey`, which the coordinator keeps.
  runApp(AsyncScopeCoordinator(child: MaterialApp(home: _Menu(journal))));
}

typedef _Attempt =
    Widget Function(List<CameraDescription>, void Function(XFile));

final Map<String, _Attempt> _attempts = {
  'Leaving the app': (c, f) => ReadmeLifecycle(cameras: c, onCaptured: f),
  'Leaving the app (answer)': (_, f) => CameraScreen(onCaptured: f),
  'Losing the camera': (c, f) => ErrorListener(cameras: c, onCaptured: f),
  'Permissions': (c, f) => PermissionMessages(cameras: c, onCaptured: f),
};

class _Menu extends StatelessWidget {
  const _Menu(this.journal);

  final ProbeJournal journal;

  Future<void> _open(BuildContext context, String name) async {
    journal.note('screen open $name');
    final cameras = await availableCameras();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(name)),
          body: Column(
            children: [
              Expanded(child: _attempts[name]!(cameras, journal.captured)),
              SizedBox(height: 220, child: _JournalView(journal)),
            ],
          ),
        ),
      ),
    );
    journal.note('screen closed $name');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Probes')),
    body: Column(
      children: [
        for (final name in _attempts.keys)
          ListTile(title: Text(name), onTap: () => _open(context, name)),
        Expanded(child: _JournalView(journal)),
      ],
    ),
  );
}

class _JournalView extends StatelessWidget {
  const _JournalView(this.journal);

  final ProbeJournal journal;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: journal.count,
    builder: (_, _, _) {
      final lines = journal.lines.reversed.toList();
      return ListView.builder(
        itemCount: lines.length,
        itemBuilder: (_, i) =>
            Text(lines[i], style: const TextStyle(fontSize: 11)),
      );
    },
  );
}
