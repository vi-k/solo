# Lanes

`SoloLanes<S>` is a controller with several queues of root jobs over one state.
Each queue is a lane: its jobs run one at a time, in the order a `Solo` keeps,
and the jobs of different lanes run side by side. To a job of one lane, a write
of another lane is what `externalSetState` is to a job of a `Solo`: its rules
are asked again, and a `W` or a `keepWhile` that no longer holds cancels it. A
pool is a queue whose jobs run up to a set number at once and one at a time for
each key, as [A pool of places](#a-pool-of-places) shows.

Two consequences of that are easy to miss coming from a `Solo`. A reload lane
that writes `Loading` cancels every like with `W = Loaded`: the like that runs
is cancelled at the write, and a like that comes to its start while the state
is `Loading` never runs its body. And the rules go past `cancellable: false`,
so a write of one lane cancels a command to a device that runs in another.
[The table of cases](#the-table-of-cases) holds both.

Most sections open with a first attempt: the version the vocabulary of `Solo`
leads to, and what that code does. The answer follows under a heading of its
own. A section with nothing to get wrong opens with the answer. The states and
traces under the code are what this code prints when it runs.

## Two queues over one state

A gate learns from a server whether work may go on. Its state is a `Permit`, a
record `({bool start, bool keep})`. The work runs steps that take a while: a
step starts only while `start` holds and is cancelled once `keep` does not. A
reading of the server must not wait for a step to end.

### The first attempt

```dart
// The first attempt: two controllers, and the worker copies the gate.
final class Gate extends Solo<Permit> {
  Gate() : super((start: true, keep: true));

  Job<void> refresh(Future<Permit> Function() read) =>
      enqueue<Permit, void>((ctx) async => ctx.emit(await ctx.join(read)));
}

final class Worker extends Solo<Permit> {
  final Gate gate;

  Worker(this.gate) : super(gate.currentState) {
    gate.addListener(_sync);
  }

  void _sync() => externalSetState(gate.currentState);

  Job<void> run(Future<void> Function() step) => enqueue<Permit, void>(
    canStart: (s) => s.start,
    keepWhile: (s) => s.keep,
    (ctx) => ctx.join(step),
  );

  // Called once, when closing the worker finishes.
  @override
  void onClose() => gate.removeListener(_sync);
}
```

A `Solo` runs one root job at a time, so the reading and the steps get a
controller each. The worker copies the state of the gate into its own with
`externalSetState`, from a listener that runs inside every write of the gate,
and the rules of its steps judge the copy. A step of 100 ms starts at 0 ms, the
server withdraws the permit at 30 ms, a second step is asked for at 40 ms, and
the permit comes back at 150 ms with a third:

```text
0 ms: step 1 started
30 ms: refresh (keep: false, start: false)
100 ms: step 1 ended
100 ms: run 1: Cancelled(rules: keepWhile)
100 ms: run 2: Cancelled(rules: canStart)
150 ms: refresh (keep: true, start: true)
150 ms: step 3 started
250 ms: step 3 ended
250 ms: run 3: Done(null)
```

The first step runs to its end at 100 ms, though `keep` went at 30 ms:
`ctx.join` lets its action finish and checks the cancellation after it. It
works, and this is what it takes:

- a subscription of the worker to the gate, and its removal in `onClose`;
- a second copy of the state, in the worker;
- two controllers for the screen to listen to, with `Listenable.merge` in
  Flutter;
- two calls of `close` for whoever made them.

### Two lanes

```dart
final class Station extends SoloLanes<Permit> {
  late final SoloLane<Permit> _gate;
  late final SoloLane<Permit> _work;

  Station() : super((start: true, keep: true)) {
    _gate = lane('gate');
    _work = lane('work');
  }

  Job<void> refresh(Future<Permit> Function() read) => _gate
      .enqueue<Permit, void>((ctx) async => ctx.emit(await ctx.join(read)));

  Job<void> run(Future<void> Function() step) => _work.enqueue<Permit, void>(
    canStart: (s) => s.start,
    keepWhile: (s) => s.keep,
    (ctx) => ctx.join(step),
  );
}
```

The lanes are declared in the constructor with `lane`, as
[Declaring lanes](#declaring-lanes) explains. A lane is a `SoloLane`, with the
members of the queue of a `Solo`: `enqueue`, `job`, `enqueueJob`, `collect`,
`accumulate`, `queue`, `current`, `lastJobWhere` and `pending`. They are
public: whoever holds a lane queues jobs in it, so the controller keeps its
lanes in private fields. A `Solo` makes the children of `ctx.child` through its
own `job` and queues the groups of an accumulator through its own `enqueueJob`,
so a subclass that overrides the two sees those jobs too. A lane is no subclass
and takes no override: every job of a `SoloLanes` reaches `onStart` and
`onFinish` of the controller and a `SoloObserver`, as
[Watching every controller](diagnostics.md#watching-every-controller) shows.

The refresh writes the state in the gate lane, and the rules of the step in the
work lane are asked about it at once. The same steps and refreshes print the
same trace. The subscription, the listener, `onClose`, the copy and the second
`close` are gone: there is one state and one `close`. A refresh writes the
whole state, and here it may: the `Permit` is all of it.

Within a lane the jobs keep the order of a `Solo` queue, with its policies and
`first:`. A `Policy` looks for its key in its own lane only, so `restart`
cancels the running job of its own lane and leaves the other lanes alone. A
lane queues only the jobs it made: a job of another lane or of another
controller is refused with an `ArgumentError`. Between lanes there is no order,
and the engine keeps nothing apart: jobs that must not overlap, such as two
commands to one device, go into one lane.

## A write that keeps the other lane's work

The feed of
[A tap that does not wait for a reload](jobs.md#a-tap-that-does-not-wait-for-a-reload),
in one controller. `Feed` holds the posts as the server sent them, and a `Mark`
for each post the user has tapped; the screen shows the mark over the post. A
reload lane asks the server for the posts, which answers two seconds later, and
publishes them, as [A snapshot from the server](#a-snapshot-from-the-server)
shows. A likes lane marks the post and sends the like, which the server
confirms a twentieth of a second later. Each lane writes its own part of the
state, and neither may lose what the other wrote.

### The first attempt

```dart
// The first attempt: the like writes over a copy read before the wait.
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      final feed = ctx.state;
      ctx.emit(feed.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(feed.mark(postId, Mark(liked, ++_confirmations)));
    });
```

A listener prints the state as the posts and the marks over them, and `#1` is
the number of a confirmation. The reload is sent at 0 ms, and a like is tapped
at 1980 ms:

```text
0 ms: reload sent
1980 ms: posts none; marks p1 liked
1980 ms: like p1 sent
2000 ms: reload answered
2000 ms: posts p1, p2; marks p1 liked
2030 ms: like p1 confirmed
2030 ms: posts none; marks p1 liked #1
```

The reload publishes the posts at 2000 ms, while the like waits for the server.
At 2030 ms the like writes its copy of 1980 ms with one mark changed, and the
posts are gone: the copy was read before the reload published them. In a
`Solo`, only a child of the job or `externalSetState` writes while the job
waits; here every other lane does.

### A read at the write

```dart
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      ctx.emit(ctx.state.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
    });
```

Each `emit` takes the state as it stands, with whatever the other lane has
written meanwhile. `ctx.state` and the `emit` after it run in one synchronous
stretch, and no other lane writes between the two:

```text
0 ms: reload sent
1980 ms: posts none; marks p1 liked
1980 ms: like p1 sent
2000 ms: reload answered
2000 ms: posts p1, p2; marks p1 liked
2030 ms: like p1 confirmed
2030 ms: posts p1, p2; marks p1 liked #1
```

`ctx.state` is a checkpoint, as in a `Solo`: it checks cancellation and the
rules before it returns. The engine does not refuse a plain `emit`: a whole new
state written on purpose and a lost update look the same to it, and only the
domain tells them apart. It does see when the state was read, and with
[`Solo.debug`](diagnostics.md#logs) set, the second `emit` of the first attempt
comes with a line:

```text
Job() emit over a write of lane reload made after Job() last read the state: read ctx.state after the wait, or this write undoes the work of reload
```

A job that read the state before the wait and writes a snapshot on purpose
after it gets the line too, so it is a line in the log and not an error. A job
that has not read the state gets none, and neither does the read at the write.

The `stale_emit` lint of [solo_lints](https://pub.dev/packages/solo_lints)
reports the first attempt: its second `emit` writes a value built on `feed`,
which the job read before the `await`. The lint is a heuristic, and it does not
see the reload of [A snapshot from the server](#a-snapshot-from-the-server),
whose answer, written whole, loses the mark of the like all the same. Lints of
`solo_lints` are turned on by name, as its
[Install](https://github.com/vi-k/solo/blob/main/packages/solo_lints/README.md#install)
section shows.

## A snapshot from the server

A reload brings the server's word on the likes. A like the server confirmed
before the reload was sent comes back in the posts, and its mark is no longer
needed. A like still on its way keeps its mark: the server answered the reload
without it.

### The first attempt

```dart
// The first attempt: the answer of the server becomes the whole state.
Job<void> reload() => _reload.enqueue<Feed, void>(
  key: 'reload',
  policy: Policy.droppable,
  (ctx) async {
    final posts = await ctx.abandonable(api.fetchPosts);
    ctx.emit(Feed(posts: posts));
  },
);
```

The like is the one that reads at the write. The reload is sent at 0 ms, and a
like is tapped at 100 ms:

```text
0 ms: reload sent
100 ms: posts none; marks p1 liked
100 ms: like p1 sent
150 ms: like p1 confirmed
150 ms: posts none; marks p1 liked #1
2000 ms: reload answered
2000 ms: posts p1, p2; marks none
```

The server confirmed the like at 150 ms, but it answered the reload as it stood
at 0 ms, before the like. At 2000 ms the answer replaces the whole state, the
mark included, and the heart goes out while the server holds the like. A read
at the write does not help here: the reload does not change a part of what it
reads, it writes all of it.

### A merge

```dart
/// A like the screen shows over the feed.
final class Mark {
  final bool liked;

  /// The number of the confirmation, or `null` while the like is on its way.
  final int? confirmation;

  const Mark(this.liked, [this.confirmation]);
}

final class Feed {
  final List<Post> posts;
  final Map<String, Mark> marks;

  /// The confirmations the posts cover: the reload that brought them was
  /// sent after that many.
  final int seen;

  const Feed({this.posts = const [], this.marks = const {}, this.seen = 0});

  Feed withPosts(List<Post> posts) =>
      Feed(posts: posts, marks: marks, seen: seen);

  Feed mark(String postId, Mark? mark) => Feed(
    posts: posts,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (key != postId) key: value,
      postId: ?mark,
    },
    seen: seen,
  );

  /// Drops the marks of the likes the server had confirmed when a reload
  /// was sent after [seen] confirmations; a like on its way keeps its mark.
  Feed settled(int seen) => Feed(
    posts: posts,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (value.confirmation == null || value.confirmation! > seen)
          key: value,
    },
    seen: seen,
  );

  /// Puts back the mark [before] after a like that failed or was cancelled,
  /// unless the posts cover it: then they say what the server holds.
  Feed restored(String postId, Mark? before) => mark(postId, switch (before) {
    Mark(confirmation: final number?) when number <= seen => null,
    _ => before,
  });
}

final class FeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloLane<Feed> _reload;
  late final SoloLane<Feed> _likes;

  FeedController(this.api) : super(const Feed()) {
    _reload = lane('reload');
    _likes = lane('likes');
  }

  Job<void> reload() => _reload.enqueue<Feed, void>(
    key: 'reload',
    policy: Policy.droppable,
    (ctx) async {
      final seen = _confirmations;
      final posts = await ctx.abandonable(api.fetchPosts);
      ctx.emit(ctx.state.withPosts(posts).settled(seen));
    },
  );

  Job<void> setLiked(String postId, {required bool liked}) {
    Mark? before;
    return _likes.enqueue<Feed, void>(
      ifFailed: (feed, error, stackTrace) => feed.restored(postId, before),
      ifCancelled: (feed, cancelled) => feed.restored(postId, before),
      isExpectedError: (error) => error is ApiException,
      (ctx) async {
        before = ctx.state.marks[postId];
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      },
    );
  }
}
```

The reload merges the posts into the state it reads at the write, and
`settled(seen)` drops the marks the server's answer covers. `seen` is the count
of confirmations when the reload was sent. A like confirmed by then has a
number up to `seen`, and the posts bring it; a like still on its way gets a
greater number, or has none yet, and keeps its mark. The same taps, and a
second reload sent at 2100 ms:

```text
0 ms: reload sent
100 ms: posts none; marks p1 liked
100 ms: like p1 sent
150 ms: like p1 confirmed
150 ms: posts none; marks p1 liked #1
2000 ms: reload answered
2000 ms: posts p1, p2; marks p1 liked #1
2100 ms: reload sent
4100 ms: reload answered
4100 ms: posts p1 liked, p2; marks none
```

`setLiked` is the like of the last section with a correction. `before` is the
mark the post had when the like started, and when the like fails or is
cancelled, `ifFailed` or `ifCancelled` puts it back: the post shows what it
showed before the tap. A confirmed mark the posts cover does not come back. The
feed keeps the `seen` of the reload its posts came from, and those posts say
what the server holds, an unlike from another device included: `restored`
leaves the post to them. Each handler changes the `feed` it is given and
returns that: the reload may have written since the like started, and a state
kept from then, returned whole, would take its posts away. Nobody reads the
outcome of a tap, so `isExpectedError` names the `ApiException` of a failed
request, and it does not go on to the zone.

A like does not wait for a reload. A like of a second post still waits for the
first: there is one likes lane. In [A pool of places](#a-pool-of-places) it
goes past. The settling is part of the reload's write rather than a job of the
likes, so it waits for no like, and the screen listens to one controller.

## Work that a new epoch makes stale

Some writes make the work of the other lanes stale: a sign-out, a switch of
profile or of the source of the data. The domain says so, not a count of
writes: a field of the state that such a write changes, and a `keepWhile` in
the jobs it matters to. Here the feed carries an `epoch`, and an account lane
signs out:

```dart
Job<void> signOut() => _account.enqueue<Feed, void>(
  // A new epoch: the work of the lanes for the last user is stale.
  (ctx) async => ctx.emit(Feed(epoch: ctx.state.epoch + 1)),
);

Job<void> like(String postId) {
  final epoch = currentState.epoch;
  return _likes.enqueue<Feed, void>(
    keepWhile: (feed) => feed.epoch == epoch,
    (ctx) async {
      ctx.emit(ctx.state.mark(postId, const Mark(true)));
      await ctx.join(() => api.setLiked(postId, liked: true));
      // Not reached once the epoch has changed.
      ctx.emit(ctx.state.mark(postId, Mark(true, ++_confirmations)));
    },
  );
}
```

The epoch the like was queued in is kept in the closure of `keepWhile`, not in
the state: `like` reads `currentState.epoch` when it is called, and `keepWhile`
compares the epoch of every new state with it. So the epoch is read in the
method, before `enqueue`, and not in the body, which starts later, when the
epoch may have changed. A like of `p1` is sent at 0 ms, a like of `p2` waits
behind it, and the user signs out at 10 ms:

```text
0 ms: like p1 sent
10 ms: sign out
50 ms: like p1 confirmed
50 ms: like p1: Cancelled(rules: keepWhile)
50 ms: like p2: Cancelled(rules: keepWhile)
```

- The new epoch cancels the like of `p1` at 10 ms, at the write that changes
  it, and not at the next write of the like: the engine asks `keepWhile` after
  every write. From then on the like writes nothing, and a job its rules
  cancelled gets no `ifCancelled`: an old correction does not land on the new
  data.
- Nothing of the like takes down the mark it put up at 0 ms. The sign-out does:
  it writes the new epoch as a new `Feed`, whose marks are empty. A sign-out
  that carried the marks over to the new epoch would leave the mark of `p1` on
  its way for good.
- The like of `p2` was queued in the old epoch and comes to start in the new
  one. `keepWhile` is asked at the start too, and its body never runs.
- A write that keeps the epoch cancels nobody.

Cancellation and freeing the lane are two guarantees. The cancellation takes
the write and the correction from the job at once. The lane the job holds until
its wait ends: `ctx.join` waits for its action and checks the cancellation
after it. The like of `p1` holds the likes lane until the server answers at 50
ms, and a `close()` called at 10 ms completes then. Freeing the lane sooner is
a choice of its own: with `ctx.abandonable` instead of `ctx.join` the job lets
go at once, while the request runs on at the server.

## Rules by type on a record state

The camera and its notice from
[A notice the screen accepts](state.md#a-notice-the-screen-accepts), in one
controller. A camera lane takes shots, and a notices lane closes the notice of
a stored photo, so the acceptance does not wait for a shot. A shot needs the
camera `Ready` and is cancelled when it no longer is. What the device reports
reaches the state through `reflect`, with `externalSetState`.

### The first attempt

```dart
// The first attempt: a class state, and Ready asked for by hand.
final class Studio {
  final Camera camera;
  final Notice? notice;

  const Studio(this.camera, [this.notice]);
}

Job<void> shoot() => _camera.enqueue<Studio, void>(
  canStart: (studio) => studio.camera is Ready,
  (ctx) async {
    await ctx.join(device.focus);
    final zoom = (ctx.state.camera as Ready).zoom;
    final photo = await ctx.join(() => device.shoot(zoom));
    ctx.emit(Studio(ctx.state.camera, Notice(photo)));
  },
);
```

Two parts of one state make a product, and a class with fields holds one. But
no subtype of `Studio` says that the camera is `Ready`, so `W` is the whole
`Studio`, `canStart` asks for `Ready` by hand, and the body casts. The device
reports `Off` at 30 ms, during the focus:

```text
0 ms: focus started
30 ms: camera off
50 ms: focus done
50 ms: shoot: Failed(type 'Off' is not a subtype of type 'Ready' in type cast)
```

`canStart` is asked once, at the start, so nothing cancels the shot, and the
cast after the focus throws. The shot ends `Failed` with a `TypeError` that
nobody answers for. A `keepWhile` with the same test cancels the shot, and the
cast stays.

### W on a record

```dart
typedef Studio = ({Camera camera, Notice? notice});

final class StudioController extends SoloLanes<Studio> {
  final Device device;

  late final SoloLane<Studio> _camera;
  late final SoloLane<Studio> _notices;

  StudioController(this.device) : super((camera: const Ready(), notice: null)) {
    _camera = lane('camera');
    _notices = lane('notices');
  }

  Job<void> shoot() =>
      _camera.enqueue<({Ready camera, Notice? notice}), void>((ctx) async {
        await ctx.join(device.focus);
        // W says the camera is Ready, and so does ctx.state.
        final zoom = ctx.state.camera.zoom;
        final photo = await ctx.join(() => device.shoot(zoom));
        ctx.emit((camera: ctx.state.camera, notice: Notice(photo)));
      });

  // The device reports its camera: Off, or Ready again.
  void reflect(Camera camera) =>
      externalSetState((camera: camera, notice: currentState.notice));

  Job<void> accept(Notice notice) =>
      _notices.enqueue<Studio, void>((ctx) async {
        if (identical(ctx.state.notice, notice)) {
          ctx.emit((camera: ctx.state.camera, notice: null));
        }
      });
}
```

On a record `W` works. `Ready` is a subtype of `Camera`, so the record
`({Ready camera, Notice? notice})` is a subtype of `Studio`, and the check
`state is W` looks at the type of the value in each field. The body reads
`ctx.state.camera` as a `Ready` with no cast, and `Off` cancels the shot:

```text
0 ms: focus started
30 ms: camera off
50 ms: focus done
50 ms: shoot: Cancelled(rules: is not ({Ready camera, Notice? notice}))
```

On either form both writes keep the camera by hand, `ctx.state.camera` in the
shot and in the acceptance: each changes only the notice. Lanes fit where the
parts speak of one thing: the `Permit` that one lane writes and another reads,
the posts and the marks over them. Parts that live for different times, such as
notices that outlive the camera, still need two controllers, as in
[A board of its own](state.md#a-board-of-its-own): the lanes of one controller
close together.

## A pool of places

The feed takes photos besides likes. A user picks several at once, the server
takes two uploads at a time, and an upload the user cancels before it starts
must not go. A lane runs one job at a time, so its uploads would go one by one,
and in one likes lane a like of one post waits behind a like of another, though
the server takes them side by side.

### The first attempt

```dart
// The first attempt: a job of the lane that runs each upload as its child.
final _inbox = <SoloJob<Photo>>[];
Completer<void>? _wake;

// Queued by the constructor, after `_uploads = lane('uploads');`.
void _work() => _uploads.enqueue<Feed, void>((ctx) async {
  while (true) {
    if (_inbox.isEmpty) {
      final wake = _wake = Completer<void>();
      await ctx.abandonable(() => wake.future);
    }
    ctx.run(_inbox.removeAt(0)).ignore();
  }
});

SoloJob<Photo> upload(String file) {
  final job = _uploads.job<Feed, Photo>(
    (ctx) => ctx.join(() => api.upload(file)),
  );
  _inbox.add(job);
  _wake?.complete();
  _wake = null;
  return job;
}
```

The worker is a root job of the lane that never ends, and the uploads are its
children, so they run side by side. Four photos are picked at 0 ms, the user
cancels the third at once, and a drain is asked for at 20 ms:

```text
0 ms: c.jpg: Cancelled(manual)
0 ms: upload a.jpg sent
0 ms: upload b.jpg sent
20 ms: close(mode: drain)
100 ms: a.jpg: Done(Photo(a.jpg))
100 ms: b.jpg: Done(Photo(b.jpg))
100 ms: worker: Failed(Bad state: Job() has already finished; a job runs once, and a child needs a new Job.deferred)
100 ms: closed
60000 ms: d.jpg: no outcome
```

The cancel ends `c.jpg` at once, but it stays in the inbox, and `ctx.run` of a
job that has finished throws. The body of the worker fails, and the error goes
to the zone. The worker ends at 100 ms, once its children `a.jpg` and `b.jpg`
have, and the drain closes the controller. `d.jpg` never runs and never ends:
whoever awaits it waits for good.

Without the cancellation, the same four photos:

```text
0 ms: upload a.jpg sent
0 ms: upload b.jpg sent
0 ms: upload c.jpg sent
0 ms: upload d.jpg sent
20 ms: close(mode: drain)
100 ms: a.jpg: Done(Photo(a.jpg))
100 ms: b.jpg: Done(Photo(b.jpg))
100 ms: c.jpg: Done(Photo(c.jpg))
100 ms: d.jpg: Done(Photo(d.jpg))
60000 ms: closing is held by SoloPending(uploads: SoloPending([no key] in its body, draining))
```

All four go to the server at once: nothing holds the uploads to two. And the
drain never ends, since the worker waits for the next photo, and a drain waits
for the job of the lane. A limit of two, the cancels and the end of the inbox
would make the worker a second queue beside the lane's, one that its `queue`,
`pending` and `close` do not see.

### A pool

```dart
final class FeedController extends SoloLanes<Feed> {
  final FeedApi api;
  int _confirmations = 0;

  late final SoloPool<Feed> _likes;
  late final SoloPool<Feed> _uploads;

  FeedController(this.api) : super(const Feed()) {
    _likes = pool('likes', concurrency: 4);
    _uploads = pool('uploads', concurrency: 2);
  }

  // No key: any two uploads may run together, two at a time.
  Job<Photo> upload(String file) =>
      _uploads.enqueue<Feed, Photo>((ctx) => ctx.join(() => api.upload(file)));

  int get uploading => _uploads.running.length;
  int get waiting => _uploads.queue.length;

  // Likes of different posts run side by side, up to four at once; a like
  // and an unlike of one post run in the order of the taps.
  Job<void> setLiked(String postId, {required bool liked}) =>
      _likes.enqueue<Feed, void>(key: postId, (ctx) async {
        ctx.emit(ctx.state.mark(postId, Mark(liked)));
        await ctx.join(() => api.setLiked(postId, liked: liked));
        ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
      });
}
```

A pool is a queue whose root jobs run up to `concurrency` at once, each in a
place of its own. The same four photos, the third cancelled at once:

```text
0 ms: c.jpg: Cancelled(manual)
0 ms: upload a.jpg sent
0 ms: upload b.jpg sent
0 ms: uploading 2, waiting 1
20 ms: close(mode: drain)
100 ms: a.jpg: Done(Photo(a.jpg))
100 ms: upload d.jpg sent
100 ms: b.jpg: Done(Photo(b.jpg))
200 ms: d.jpg: Done(Photo(d.jpg))
200 ms: closed
```

The cancel takes `c.jpg` out of the queue, as in a lane, and `d.jpg` takes the
place that `a.jpg` leaves at 100 ms. The drain runs the queue out and completes
once no job of the pool runs. A child of a job of the pool takes no place:
`concurrency` counts the root jobs.

A pool has no `current`, since several jobs run at once. It has `running`, the
jobs that run now in the order they started, so `uploading` reads
`running.length`. Code written for a lane that reads `current` does not compile
with a pool, so it cannot read one job of several. Code that reads neither
member takes a `SoloQueueOwner`, which a lane and a pool both are.

A key keeps the order in a pool. While a job runs under a key, the jobs of that
key wait in the queue, and the jobs behind them with other keys go past them.
The like of `p1` is tapped at 10 ms and takes the server two seconds, the
unlike of `p1` is tapped at 20 ms, and the like of `p2` at 150 ms:

```text
10 ms: marks p1 liked
10 ms: like p1 sent
150 ms: marks p1 liked, p2 liked
150 ms: like p2 sent
200 ms: like p2 confirmed
200 ms: marks p1 liked, p2 liked #1
2010 ms: like p1 confirmed
2010 ms: marks p2 liked #1, p1 liked #2
2010 ms: marks p2 liked #1, p1 unliked
2010 ms: unlike p1 sent
2060 ms: unlike p1 confirmed
2060 ms: marks p2 liked #1, p1 unliked #3
```

The unlike goes to the server after the like of its post, in the order of the
taps. The like of `p2` takes a free place at 150 ms and goes past the unlike of
`p1`: in one likes lane it would be sent at 2060 ms, after both. The heart of
the unlike goes out late, though: the body writes the mark, and the body starts
at 2010 ms, so the heart stays lit for two seconds after the tap.

The key keeps the order under `Policy.sequential` too, the policy a call takes
by default, though in a `Solo` and in a lane that policy ignores keys. So one
key given to every job of a pool runs them one at a time, in the order of the
queue. The other policies look into the pool as into a lane: `droppable` hands
out the job of the key that waits or runs, and `restart` cancels the running
job of the key, and the new job starts once that one ends. To a job of a pool,
a write of another job of the same pool is what a write of another lane is: the
recipes of this page hold in a pool as they are.

A wait inside a pool hangs in a way of its own. A job that awaits a job it
queued under its own key in its own pool waits for good at once: it holds the
key itself. Under another key, or with none, it gets the job while a place is
free, and once every place is taken by jobs that wait so, none of them moves. A
test with an empty pool passes, and the screen hangs under load. So the
`await_own_queue` lint of [solo_lints](https://pub.dev/packages/solo_lints)
reports a wait for a job of the own pool whatever the key, as it reports a wait
for a job of the own lane.

## Declaring lanes

A lane is declared once, and the set of lanes stays as it is while the
controller works.

### The first attempt

```dart
// The first attempt: the lanes in late final fields.
late final _reload = lane('reload');
late final _likes = lane('likes');

FeedController(this.api) : super(const Feed());
```

A `late final` field reads well, and it is how a controller keeps an
accumulator. But it declares its lane on its first read, in the first call of a
method, and that call comes after the constructor:

```text
Bad state: Cannot declare lane reload of FeedController after its constructor: lanes are declared in the constructor body, and a late final field declares its lane on its first read; see https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes
```

`SoloLanes` seals its set of lanes a microtask after its constructor, so the
first `reload()` throws whenever it comes. A read in the same synchronous run
as the constructor gets through, but only until the first job: a screen that
writes `FeedController(api)..reload()` declares the reload lane and queues its
job, and the first `setLiked` throws all the same:

```text
Bad state: Cannot declare lane likes of FeedController after enqueueJob of one of its lanes was called: from the first call on, the lanes are what the pump walks; see https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes
```

Without the seal that comes a microtask after the constructor, whether a call
works would depend on the order of the taps, and the order the pump walks the
lanes in would follow the order of the first reads rather than the lines of the
class.

### In the constructor body

```dart
late final SoloLane<Feed> _reload;
late final SoloLane<Feed> _likes;

FeedController(this.api) : super(const Feed()) {
  _reload = lane('reload');
  _likes = lane('likes');
}
```

The fields are assigned in the body of the constructor, so the lanes are
declared before any job, and their order is the order of these lines: the order
`lanes` gives them in. `lane` and `lanes` are protected. `lane` throws a
`StateError` for a name the controller has a lane of already: every call
declares a new lane, and two of one name would read as one. It throws as well
once the set is sealed: a microtask after the constructor, at the first
`enqueueJob` of any lane whatever came of it, and after `close`.

Two lanes differ by identity, not by name: the name is for logs and `toString`.
A job tells the lane it runs in with `job.lane`, a `SoloLaneId` with that name,
and a job of a `Solo` has none.

A pool is declared the same way, by `pool` in the constructor body, and `pools`
gives the pools in the order of their lines. The pump walks the lanes and the
pools together, in the order they were declared. `pool` throws as `lane` does,
for a name of a lane or a pool the controller has already and once the set is
sealed, and it throws an `ArgumentError` for a `concurrency` below one. A job
of a pool tells the pool with `job.lane`: the places have no id of their own.

A set declared once fits a lane for each kind of work over one state: the
reload, the likes, the commands to a device. It does not fit a lane for each
item of a list that grows and shrinks, and the seal is not the only reason. The
pump walks every lane for the next job, and every write asks the rules of every
running job of every lane: a thousand jobs that run side by side and then write
once each ask a `keepWhile` about half a million times. Items that come and go
take a controller each, or a layer above the controllers that caches by id, as
in
[Where another package fits better](https://github.com/vi-k/solo/blob/main/packages/solo/README.md#where-another-package-fits-better).

## The table of cases

| What happens | What comes of it |
| --- | --- |
| The synchronous part of a job of one lane queues a job in another | If the other lane is free, it starts the job before control goes back to the event loop; how that start falls among the microtasks of the same turn is not promised. |
| A job of one lane writes a state outside the `W` of a job of another, as a reload writes `Loading` under a like with `W = Loaded` | The like that runs is cancelled at the write, and a like that comes to its start while the state is `Loading` is cancelled before its body runs. |
| A write of one lane, and a `cancellable: false` job of another whose `keepWhile` refuses the new state | The job is cancelled all the same: the rules go past `cancellable: false`, as `externalSetState` does in a `Solo`. |
| A job awaits a job it queued in another lane | It waits while the other lane runs that job. |
| A job awaits a job it queued in its own lane | It waits for good: a lane runs one job at a time. |
| A job of lane A awaits a job it queued in lane B, which awaits a job it queued in lane A | Both wait for good: the job in B waits for one queued in A behind the job that waits for it. |
| A job awaits `close()` or `cancelAll()` of its controller | It waits for itself: both wait for the jobs of every lane. |
| `close()` | The queues of every lane are cleared, and the running job of every lane is asked to cancel; a `cancellable: false` job turns that down and runs on. `close` completes when the last of them ends, as [Three ways to stop](cancellation.md#three-ways-to-stop) tells. |
| `close(mode: SoloCloseMode.drain)` | Every lane runs its queue out, and `close` completes when all of them are empty. |
| During a drain, a job of one lane queues a continuation in another | The continuation ends `Cancelled(closed)`: a closed controller takes no new root job, whichever lane asks. A `droppable` continuation whose key the other lane has accepted gets that job, as it would before the close. |
| A job of a pool is queued under a key that a running job of the pool holds | It waits until that job ends, and the jobs behind it with other keys go past it while a place is free. |
| A job of a pool awaits a job it queued in its own pool under its own key | It waits for good: it holds the key itself. |
| A job of a pool awaits a job it queued in its own pool under another key or with none | It gets the job while a place is free; once every place is taken by jobs that wait so, they wait for good. |
| `close()` or a drain over a pool | `close` clears the queue of a pool and asks every running job of it to cancel, and a drain of a pool ends once its queue is empty and none of its jobs runs. |
| An unlike fails after a reload has brought the server's word on the like | The correction puts back no mark: the posts say what the server held when the reload was sent, an unlike from another device included. |

Two controllers could take the continuation of a drain: the one drained first
and the other closed later. One controller closes its lanes together, so a
continuation that another lane has to take becomes part of a write instead, as
the settling of the feed is part of the reload's write.
