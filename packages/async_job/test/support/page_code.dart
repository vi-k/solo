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
///
/// A page whose first attempts cannot share a library with its answer —
/// two classes of one name — names the libraries that hold them in
/// [alsoIn], and a piece may stand in any one of the files. [under] narrows
/// the page to the parts under the headings of that text, each up to the
/// next heading: that is how a page holds an answer to its own file, where
/// the line of a first attempt would be found as well.
List<String> codeMissingFrom(
  String page,
  String test, {
  List<String> alsoIn = const [],
  String? under,
}) {
  List<String> lines(String text) => [
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty && !line.trim().startsWith('// ignore:'))
            line.trim(),
      ];

  final sources = [
    for (final file in [test, ...alsoIn]) lines(File(file).readAsStringSync()),
  ];
  bool runsIn(List<String> source, List<String> piece) {
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

  bool runs(List<String> piece) =>
      sources.any((source) => runsIn(source, piece));

  var text = File(page).readAsStringSync();
  if (under != null) {
    text = [
      for (final part in text.split(RegExp('^(?=#)', multiLine: true)))
        if (part.split('\n').first == under) part,
    ].join();
  }
  return [
    for (final block
        in RegExp(r'```dart\n(.*?)\n```', dotAll: true).allMatches(text))
      for (final piece in block.group(1)!.split(RegExp(r'\n\s*\n')))
        if (!runs(lines(piece))) piece,
  ];
}
