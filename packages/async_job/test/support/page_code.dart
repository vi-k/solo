import 'dart:io';

/// The pieces of the `dart` code on [page] that [test] does not run.
///
/// A block of the page is cut into pieces at its blank lines, and each
/// piece has to stand in [test] as a run of whole lines, in the same order
/// and with nothing between them. Indentation does not count, nor do blank
/// lines and `// ignore:` comments of the test, which the page has no use
/// for. The first line of a piece may end a longer line of the test, where
/// the test hands the page's expression to a helper of its own. A line
/// checked alone would let a piece drop a line or swap two and still be
/// found.
List<String> codeMissingFrom(String page, String test) {
  List<String> lines(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty && !line.trim().startsWith('// ignore:'))
            line.trim(),
      ];

  final source = lines(File(test).readAsStringSync());
  bool runs(List<String> piece) {
    for (var start = 0; start + piece.length <= source.length; start++) {
      if (!source[start].endsWith(piece.first)) {
        continue;
      }
      var matched = 1;
      while (
          matched < piece.length && source[start + matched] == piece[matched]) {
        matched++;
      }
      if (matched == piece.length) {
        return true;
      }
    }
    return false;
  }

  return [
    for (final block in RegExp(r'```dart\n(.*?)\n```', dotAll: true)
        .allMatches(File(page).readAsStringSync()))
      for (final piece in block.group(1)!.split(RegExp(r'\n\s*\n')))
        if (!runs(lines(piece))) piece,
  ];
}
