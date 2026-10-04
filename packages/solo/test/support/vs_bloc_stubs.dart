// What the sections of `doc/vs-bloc.md` share in `vs_bloc_rakes_test.dart`,
// and none of it is on the page: the clock of the fake APIs and the cancel
// token two of them watch. The bench `tool/doc_snippets.py` has the same
// three under the same names.

/// Completes [ms] milliseconds later; under fake time, when they are elapsed.
Future<void> tick(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// A device SDK's own cancel token: the call watches it and returns.
class CancelToken {
  bool cancelled = false;

  void cancel() => cancelled = true;
}

/// The plain list of calls a device received, from a start/end trace.
List<String> callsOf(List<String> trace) => [
      for (final entry in trace)
        if (entry.endsWith(' start')) entry.substring(0, entry.length - 6),
    ];
