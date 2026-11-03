// The code tool/plugin_probe.py analyzes with the plugins of the tree.
//
// Every line a rule reports ends with a comment naming the rule. A line
// marked `rule unless plugin` is reported unless that plugin owns the rule,
// because the `ignore` above it names the rule under that plugin. The wait
// for the own queue is marked `await_own_queue`; what reports it depends on
// the plugins named, and the probe knows it per set.
import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';

abstract interface class Device {
  static late Future<Device> Function() open;

  Future<void> flush();

  Future<void> reset();

  Future<void> close();
}

Future<int> commit() async => 1;

// The rules of async_job on a job of the core.

final recording = Job<void>((ctx) async {
  final device = await ctx.join(Device.open);
  ctx.onDispose(device.close); // release_on_the_call
  ctx.onDispose(() async {
    await ctx.join(device.flush); // ctx_in_cleanup
  });
  try {
    await ctx.join(device.flush);
  } on Object { // catch_without_check
    await device.reset();
    rethrow;
  }
  try {
    await ctx.join(device.flush);
    // ignore: solo_lints/catch_without_check
  } on Object { // catch_without_check unless solo_lints
    await device.reset();
    rethrow;
  }
  try {
    await ctx.join(device.flush);
    // ignore: async_job_lints/catch_without_check
  } on Object { // catch_without_check unless async_job_lints
    await device.reset();
    rethrow;
  }
  await commit(); // bare_await
});

void elapse() {
  fakeAsync((async) async { // sync_fake_async
    await Future<void>.value();
  });
}

// The rules of async_job and of solo on the jobs of a controller.

sealed class State {}

final class Ready extends State {}

final class Broken extends State {
  Broken(this.error);

  final Object error;
}

class Profile {}

class ApiException implements Exception {}

abstract interface class Api {
  Future<Profile> load(String id);
}

late final Api api;

enum _Op { find }

late final Profiles profiles;

final class Profiles extends Solo<State> {
  Profiles() : super(Ready());

  Job<void> reset() => enqueue<State, void>((ctx) async {
    ctx.onDispose(() {
      ctx.emit(Ready()); // ctx_in_cleanup
    });
  });

  Job<void> retry() => enqueue<State, void>((ctx) async {
    try {
      await ctx.join(() => api.load('a'));
    } on Object catch (error) {
      ctx.emit(Broken(error));
      rethrow;
    }
  });

  Job<void> logout() => enqueue<State, void>((ctx) async {
    await close(); // await_own_queue
  });

  Job<Profile> find(String id) => enqueue<Ready, Profile>(
    key: _Op.find, // key_per_request
    policy: Policy.droppable,
    (ctx) => ctx.abandonable(() => api.load(id)),
  );

  SoloJob<Profile> load() => enqueue<Ready, Profile>(
    (ctx) => api.load('a'),
    isExpectedError: (e) => e is ApiException,
  );
}

void reload() {
  profiles.load().ignoreFailure(); // ignore_failure_hides_bugs
}
