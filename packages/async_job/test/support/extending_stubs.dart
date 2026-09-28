// What the code of `doc/extending.md` takes for granted: the account, the
// operations, the observer that prints, and the reason of the rule, which
// the page shows and every version of its engine shares.
import 'dart:async';

import 'package:async_job/async_job.dart';

final class SignedOutReason extends CancelReason {
  const SignedOutReason();

  @override
  String get name => 'signed out';
}

/// What the first attempt of the rule throws.
final class SignedOut implements Exception {
  const SignedOut();

  @override
  String toString() => 'SignedOut';
}

/// Whether the user is signed in; the rule of the engine reads it.
final class Account {
  bool signedIn = true;
}

final account = Account();

/// The job's observer, printing what reaches it.
final class Printer extends JobObserver {
  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      print('onError: $error');
}

final printer = Printer();

/// Takes 20 ms and brings 42 rows.
Future<int> download() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return 42;
}

Future<void> save(int rows) =>
    Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> upload() => Future<void>.delayed(const Duration(milliseconds: 10));

Future<void> work() => Future<void>.delayed(const Duration(milliseconds: 10));

/// The moment the user does [act] — `cancel` or `sign out` — to [job], 10
/// ms in, while the download runs; and the outcome, once there is one.
void userDoes(String act, Job<void> job) {
  Timer(const Duration(milliseconds: 10), () {
    print(act);
    if (act == 'cancel') {
      unawaited(job.cancel());
    } else {
      account.signedIn = false;
    }
  });
  job.done.then((outcome) => print('outcome: $outcome')).ignore();
}
