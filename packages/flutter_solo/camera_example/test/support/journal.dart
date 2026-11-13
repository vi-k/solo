import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_camera_platform.dart';

/// The journal of a run: the calls [platform] got, every change of the
/// state of a controller, and every error a job of one threw, in the order
/// they came.
///
/// The lines of the platform are those of [FakeCameraPlatform.log]; this
/// adds `state Ready` for a change of the state, by the type of the new
/// one, and `error CameraException(…)` for an error. The traces the page
/// quotes are runs of these lines. Set it as [Solo.observer] for the run,
/// and take it off when the test is over.
final class Journal extends SoloObserver {
  /// The platform whose calls the journal takes in.
  final FakeCameraPlatform platform;

  final List<String> _lines = [];

  /// How many lines of [platform] are already in [_lines].
  int _taken = 0;

  /// Creates a journal of [platform].
  Journal(this.platform);

  /// Every line so far.
  List<String> get lines {
    _catchUp();
    return List.unmodifiable(_lines);
  }

  @override
  void onChange(
    SoloController<Object> solo,
    SoloTransition<Object> transition,
  ) => _add('state ${transition.current.runtimeType}');

  @override
  void onError(
    SoloController<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => _add('error $error');

  /// Adds [line] after the lines the platform wrote before it.
  void _add(String line) {
    _catchUp();
    _lines.add(line);
  }

  /// Takes in the lines the platform wrote since the last look.
  void _catchUp() {
    final log = platform.log;
    while (_taken < log.length) {
      _lines.add(log[_taken++]);
    }
  }
}

/// Matches a list of lines that holds [run] as consecutive lines, each
/// compared without its indentation.
Matcher containsRun(List<String> run) => predicate<List<String>>((lines) {
  final wanted = [for (final line in run) line.trim()];
  final trimmed = [for (final line in lines) line.trim()];
  for (var start = 0; start + wanted.length <= trimmed.length; start++) {
    var matched = 0;
    while (matched < wanted.length &&
        trimmed[start + matched] == wanted[matched]) {
      matched++;
    }
    if (matched == wanted.length) return true;
  }
  return false;
}, 'contains the run of lines $run');
