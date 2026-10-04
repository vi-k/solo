// Section 11 of `doc/vs-bloc.md`, "Releasing a resource returned after cancellation": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:async';

import 'package:solo/solo.dart';

class Clip {
  const Clip(this.id);

  final int id;

  @override
  String toString() => 'clip $id';
}

/// A native PCM buffer. Releasing it is not optional.
class Buffer {
  Buffer(this.clip, this.trace);

  final Clip clip;
  final List<String> trace;
  int releases = 0;

  int waveform() {
    trace.add('sample ${clip.id}');
    return clip.id;
  }

  Future<void> release() async {
    releases++;
    trace.add('release ${clip.id}');
  }
}

/// A decoder whose answers the test hands out one at a time.
class Decoder {
  final trace = <String>[];
  final answers = <int, Completer<Buffer>>{};

  Future<Buffer> open(Clip clip) {
    trace.add('open ${clip.id}');
    return (answers[clip.id] ??= Completer<Buffer>()).future;
  }

  Buffer deliver(Clip clip) {
    final buffer = Buffer(clip, trace);
    trace.add('ready ${clip.id}');
    (answers[clip.id] ??= Completer<Buffer>()).complete(buffer);
    return buffer;
  }
}

sealed class PreviewState {
  const PreviewState();
}

final class NoPreview extends PreviewState {
  const NoPreview();

  @override
  String toString() => 'NoPreview';
}

final class Preview extends PreviewState {
  const Preview(this.waveform);

  final int waveform;

  @override
  String toString() => 'Preview($waveform)';
}

// The code of the page.

final class PreviewController extends Solo<PreviewState> {
  final Decoder _decoder;

  PreviewController(this._decoder) : super(const NoPreview());

  Job<void> open(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          final buffer = await ctx.wait(
            () => _decoder.open(clip),
            dispose: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );
}

// What the test adds.

/// The `open` of the page with `discard:` where the page has `dispose:`,
/// and with `ctx.join` where it has `ctx.wait`: the two alternatives the
/// section names.
final class OtherPreviewController extends Solo<PreviewState> {
  OtherPreviewController(this._decoder) : super(const NoPreview());

  final Decoder _decoder;

  Job<void> openDiscarding(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          final buffer = await ctx.wait(
            () => _decoder.open(clip),
            discard: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );

  Job<void> openJoining(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          final buffer = await ctx.join(
            () => _decoder.open(clip),
            dispose: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );
}
