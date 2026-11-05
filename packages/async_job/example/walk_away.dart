import 'package:async_job/async_job.dart';

// README: begin
Future<void> main() async {
  final job = Job<String>((ctx) => ctx.abandonable(fetchQuote));
  final outcome = job.done;

  // Somebody left the screen while the quote was on its way.
  await Future<void>.delayed(const Duration(milliseconds: 50));

  // Returns before fetchQuote answers.
  await job.cancel();
  print(await outcome);
}
// README: end

/// The request of "Walking away from a call" in README.md: it prints when
/// it is sent and when its answer comes, a tenth of a second later.
Future<String> fetchQuote() async {
  print('request sent');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('quote answered');
  return 'Simple is better than complex.';
}
