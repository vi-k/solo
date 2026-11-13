import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo_camera_example/camera_state.dart';

/// What a probe saw on the phone, one line per call, event or error, with
/// the milliseconds since the probe started.
///
/// Every line is printed at once with the prefix `PROBE`, so a run that
/// hangs or crashes still leaves what it saw in the log of the device, and
/// is kept in [lines]. With [file] set, every line is also appended there:
/// the manual probe app keeps its journal on the phone that way.
class ProbeJournal {
  ProbeJournal({this.file});

  /// Where the lines go besides the console, when set.
  final File? file;

  /// The lines so far.
  final List<String> lines = [];

  final Stopwatch _clock = Stopwatch()..start();

  /// How many lines there are, for a screen that shows the journal.
  final ValueNotifier<int> count = ValueNotifier(0);

  /// Writes [text] down.
  void note(String text) {
    final line = '+${_clock.elapsedMilliseconds} ms $text';
    lines.add(line);
    // The device log is where a probe's lines are read from.
    // ignore: avoid_print
    print('PROBE $line');
    file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    count.value = lines.length;
  }

  /// Notes the file the screen handed up, with its size on disk.
  void captured(XFile file) {
    final File disk = File(file.path);
    final size = disk.existsSync() ? '${disk.lengthSync()} bytes' : 'missing';
    note('captured ${file.path} $size');
  }
}

/// The real [CameraPlatform] of the phone, with every call written down.
///
/// Each call that takes time gets a `start` line and an `end` line, or a
/// `threw` line; the closing and error events of every camera are written
/// down as they come, whether the controller listens to them or not.
class RecordingCameraPlatform extends CameraPlatform {
  RecordingCameraPlatform(this.inner, this.journal);

  /// The platform of the phone.
  final CameraPlatform inner;

  /// Where the calls go.
  final ProbeJournal journal;

  final List<StreamSubscription<Object>> _watches = [];

  Future<T> _timed<T>(String what, Future<T> Function() call) async {
    journal.note('$what start');
    try {
      final result = await call();
      journal.note('$what end');
      return result;
    } on Object catch (e) {
      journal.note('$what threw ${_short(e)}');
      rethrow;
    }
  }

  void _watch(int id) {
    _watches
      ..add(
        inner.onCameraClosing(id).listen((_) {
          journal.note('event closing #$id');
        }),
      )
      ..add(
        inner.onCameraError(id).listen((e) {
          journal.note('event error #$id ${e.description}');
        }),
      );
  }

  /// Stops writing down the events of the cameras created so far.
  Future<void> stopWatching() async {
    for (final watch in _watches) {
      await watch.cancel();
    }
    _watches.clear();
  }

  @override
  Future<List<CameraDescription>> availableCameras() =>
      inner.availableCameras();

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) => _timed('create ${cameraDescription.lensDirection.name}', () async {
    final id = await inner.createCamera(
      cameraDescription,
      resolutionPreset,
      enableAudio: enableAudio,
    );
    journal.note('created #$id');
    _watch(id);
    return id;
  });

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) => _timed('create ${cameraDescription.lensDirection.name}', () async {
    final id = await inner.createCameraWithSettings(
      cameraDescription,
      mediaSettings,
    );
    journal.note('created #$id');
    _watch(id);
    return id;
  });

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) => _timed(
    'initialize #$cameraId',
    () => inner.initializeCamera(cameraId, imageFormatGroup: imageFormatGroup),
  );

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      inner.onCameraInitialized(cameraId);

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
    int cameraId,
  ) => inner.onCameraResolutionChanged(cameraId);

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      inner.onCameraClosing(cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      inner.onCameraError(cameraId);

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      inner.onVideoRecordedEvent(cameraId);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      inner.onDeviceOrientationChanged();

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) => inner.lockCaptureOrientation(cameraId, orientation);

  @override
  Future<void> unlockCaptureOrientation(int cameraId) =>
      inner.unlockCaptureOrientation(cameraId);

  @override
  Future<XFile> takePicture(int cameraId) =>
      _timed('capture #$cameraId', () => inner.takePicture(cameraId));

  @override
  Future<void> prepareForVideoRecording() => inner.prepareForVideoRecording();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) => _timed(
    'record #${options.cameraId}',
    () => inner.startVideoCapturing(options),
  );

  @override
  Future<XFile> stopVideoRecording(int cameraId) =>
      _timed('stop #$cameraId', () => inner.stopVideoRecording(cameraId));

  @override
  Future<void> pauseVideoRecording(int cameraId) =>
      inner.pauseVideoRecording(cameraId);

  @override
  Future<void> resumeVideoRecording(int cameraId) =>
      inner.resumeVideoRecording(cameraId);

  @override
  bool supportsImageStreaming() => inner.supportsImageStreaming();

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) => _timed(
    'flash #$cameraId ${mode.name}',
    () => inner.setFlashMode(cameraId, mode),
  );

  @override
  Future<void> pausePreview(int cameraId) => inner.pausePreview(cameraId);

  @override
  Future<void> resumePreview(int cameraId) => inner.resumePreview(cameraId);

  @override
  Future<void> setDescriptionWhileRecording(CameraDescription description) =>
      _timed(
        'switch ${description.lensDirection.name}',
        () => inner.setDescriptionWhileRecording(description),
      );

  @override
  Widget buildPreview(int cameraId) => inner.buildPreview(cameraId);

  @override
  Future<void> dispose(int cameraId) =>
      _timed('dispose #$cameraId', () => inner.dispose(cameraId));
}

/// The first line of [e], without the stack.
String _short(Object e) => '$e'.split('\n').first;

/// Writes down every change of the state of a session and every error of
/// its jobs.
final class SessionNotes extends SoloObserver {
  SessionNotes(this.journal);

  final ProbeJournal journal;

  @override
  void onChange(
    SoloController<Object> solo,
    SoloTransition<Object> transition,
  ) => journal.note(_stateLine(transition.current));

  @override
  void onError(
    SoloController<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => journal.note(_errorLine(error));
}

/// Writes down every change of the state of a bloc and every error of its
/// handlers, in the lines of [SessionNotes]: the cases expect the same
/// lines of either controller.
final class BlocNotes extends BlocObserver {
  BlocNotes(this.journal);

  final ProbeJournal journal;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    journal.note(_stateLine(change.nextState as Object));
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    journal.note(_errorLine(error));
  }
}

/// The line of a change to [state].
String _stateLine(Object state) => switch (state) {
  Ready(:final recording) => 'state Ready recording $recording',
  _ => 'state ${state.runtimeType}',
};

/// The line of an [error], without the stack.
String _errorLine(Object error) => 'error ${_short(error)}';
