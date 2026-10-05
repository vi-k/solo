// The two blocks of `doc/errors.md` under "Answering for an error",
// verbatim: the controller with its answer, and the handler of the process.
// The page elides the jobs and the reporting hook of the controller as "the
// jobs and the reporting hook above"; here they stand under that line, as
// they stand in `errors_page.dart`. `errors_rakes_test.dart` runs both.
import 'package:solo/solo.dart';

import 'errors_stubs.dart';

final class ProfileController extends Solo<ProfileState> {
  // ...the jobs and the reporting hook above...
  final ProfileApi api;

  /// Not on the page: the field the override of the page writes to.
  final _apiFailures = <Object>[];

  ProfileController(this.api) : super(const Initial());

  /// Not on the page: what the override kept, for the tests to read.
  List<Object> get apiFailures => _apiFailures;

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      reportCrash(error, stackTrace);

  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) =>
      _apiFailures.add(error);
}

/// Not on the page: the function around the statement, called once at
/// startup.
void installErrorHandler() {
  Solo.errorHandler = (solo, job, error, stackTrace) => Job.visitErrors(
        error,
        stackTrace,
        onFailure: (failure, failureStackTrace) => Sentry.captureException(
          failure,
          stackTrace: failureStackTrace,
        ),
      );
}
