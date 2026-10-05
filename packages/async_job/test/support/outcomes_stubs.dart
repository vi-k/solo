// What the code of `doc/outcomes.md` takes for granted: the data a job
// brings, the report made of it, and the operations it waits for. Each
// operation takes its time on the clock of the test, so a cancellation
// lands while it runs.
import 'package:async_job/async_job.dart';

import 'delay.dart';

/// The data `fetch` brings.
final class Data {
  const Data();
}

/// The report made of [data].
final class Report {
  final Data data;

  const Report(this.data);

  @override
  String toString() => 'Report($data)';
}

/// Downloads the data in 50 ms.
Future<Data> download(JobContext ctx) async {
  await ctx.abandonable(() => delay(50));
  return const Data();
}

/// Uploads for 10 ms and fails: the disk is full.
Future<void> upload(JobContext ctx) async {
  await ctx.abandonable(() => delay(10));
  throw StateError('disk full');
}

/// The request elsewhere that refreshes the token; it fails.
Future<void> refreshToken() async => throw StateError('token expired');

/// The report of the first section: it takes 50 ms, and the user may
/// cancel it on the way.
Job<Report> userReport() => Job<Report>((ctx) async {
      await ctx.abandonable(() => delay(50));
      return const Report(Data());
    });
