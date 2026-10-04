// Section 1 of `doc/vs-bloc.md`, "Ordering updates to shared state": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:async';

import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Note {
  Note(this.id);

  final String id;

  @override
  String toString() => id;
}

/// Records the two moments the section turns on: when the server takes the
/// note, and what `list` saw when it read. The snapshot is taken before the
/// wait on purpose: that is a response in flight.
class Api {
  final trace = <String>[];
  final _server = <Note>[Note('n0')];

  Future<void> upload(Note note) async {
    trace.add('upload $note starts');
    await tick(40);
    _server.add(note);
    trace.add('server receives $note and holds $_server');
  }

  Future<List<Note>> list() async {
    final snapshot = List<Note>.from(_server);
    trace.add('list reads $snapshot');
    await tick(60);
    return snapshot;
  }
}

final class NotesState {
  const NotesState({this.notes = const [], this.uploading = false});

  final List<Note> notes;
  final bool uploading;

  NotesState copyWith({List<Note>? notes, bool? uploading}) => NotesState(
        notes: notes ?? this.notes,
        uploading: uploading ?? this.uploading,
      );

  @override
  String toString() => 'NotesState($notes, uploading: $uploading)';
}

// The code of the page.

final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.join(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          final serverNotes = await ctx.wait(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}

// What the test adds.

/// Every publication among the server's own entries, with the key of the
/// job that made it: `onChange` runs inside the change.
final class TracedNotesController extends NotesController {
  TracedNotesController(this.api) : super(api);

  final Api api;

  @override
  void onChange(SoloTransition<NotesState> transition) {
    final previous = transition.previous;
    final next = transition.current;
    api.trace.add(
      '${transition.job?.key} emits ${next.notes}'
      '${next.uploading == previous.uploading ? '' : ', '
          'uploading: ${next.uploading}'}',
    );
  }
}

/// The upload of the page with `ctx.wait` where the page has `ctx.join`:
/// what the paragraph under the code says `join` is there for.
final class WaitingNotesController extends Solo<NotesState> {
  WaitingNotesController(this._api) : super(const NotesState());

  final Api _api;

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.wait(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          final serverNotes = await ctx.wait(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}

/// Bodies the page describes without showing: a plain `await` where the
/// page has `ctx.join`, and work started and not awaited.
final class PlainNotesController extends Solo<NotesState> {
  PlainNotesController(this._api) : super(const NotesState());

  final Api _api;

  /// What each body went through, in order.
  final met = <String>[];

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          await _api.upload(note);
          met.add('the await returned');
          try {
            ctx.emit(ctx.state.copyWith(notes: [note]));
            met.add('emitted');
          } on Cancelled {
            met.add('emit threw Cancelled');
            rethrow;
          }
        },
      );

  Job<void> mark(String name) => run<NotesState, void>(
        key: name,
        (ctx) async => met.add('$name started'),
      );

  Job<void> detached() => run<NotesState, void>(
        key: 'detached',
        (ctx) async {
          unawaited(tick(100).then((_) => met.add('detached work ended')));
        },
      );
}
