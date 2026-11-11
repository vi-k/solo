# Lanes

`SoloLanes<S>` is a controller with several queues of root jobs over one state.
Each queue is a lane: its jobs run one at a time, in the order a `Solo` keeps,
and the jobs of different lanes run side by side. To a job of one lane, a write
of another lane is what `externalSetState` is to a job of a `Solo`: its rules
are asked again, and a `W` or a `keepWhile` that no longer holds cancels it.

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
lanes in private fields.

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
rules before it returns. The engine compares a plain `emit` with nothing: a
whole new state written on purpose and a lost update look the same to it, and
only the domain tells them apart.

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

  const Feed({this.posts = const [], this.marks = const {}});

  Feed withPosts(List<Post> posts) => Feed(posts: posts, marks: marks);

  Feed mark(String postId, Mark? mark) => Feed(
    posts: posts,
    marks: {
      for (final MapEntry(:key, :value) in marks.entries)
        if (key != postId) key: value,
      postId: ?mark,
    },
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
  );
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
      ifFailed: (feed, error, stackTrace) => feed.mark(postId, before),
      ifCancelled: (feed, cancelled) => feed.mark(postId, before),
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
showed before the tap. Nobody reads the outcome of a tap, so `isExpectedError`
names the `ApiException` of a failed request, and it does not go on to the
zone.

A like does not wait for a reload. A like of a second post still waits for the
first: there is one likes lane. The settling is part of the reload's write
rather than a job of the likes, so it waits for no like, and the screen listens
to one controller.

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

On either form a write keeps the other part by hand: `ctx.state.notice` in the
shot, `ctx.state.camera` in the acceptance. Lanes fit where the parts speak of
one thing: the `Permit` that one lane writes and another reads, the posts and
the marks over them. Parts that live for different times, such as notices that
outlive the camera, still need two controllers, as in
[A board of its own](state.md#a-board-of-its-own): the lanes of one controller
close together.

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
`lanes` gives them in and a pass of the pump walks them in. `lane` and `lanes`
are protected. `lane` throws a `StateError` for a name the controller has a
lane of already: every call declares a new lane, and two of one name would read
as one. It throws as well once the set is sealed: a microtask after the
constructor, at the first `enqueueJob` of any lane whatever came of it, and
after `close`.

Two lanes differ by identity, not by name: the name is for logs and `toString`.
A job tells the lane it runs in with `job.lane`, a `SoloLaneId` with that name,
and a job of a `Solo` has none.

## The table of cases

| What happens | What comes of it |
| --- | --- |
| The synchronous part of a job of one lane queues a job in another | The other lane starts it in the same pass of the pump if it was declared later, and in the next pass if it was declared earlier. |
| A job of one lane writes a state outside the `W` of a job of another, as a reload writes `Loading` under a like with `W = Loaded` | The like that runs is cancelled at the write, and a like that comes to its start while the state is `Loading` is cancelled before its body runs. |
| A write of one lane, and a `cancellable: false` job of another whose `keepWhile` refuses the new state | The job is cancelled all the same: the rules go past `cancellable: false`, as `externalSetState` does in a `Solo`. |
| A job awaits a job it queued in another lane | It waits while the other lane runs that job. |
| A job awaits a job it queued in its own lane | It waits for good: a lane runs one job at a time. |
| A job of lane A awaits a job it queued in lane B, which awaits a job it queued in lane A | Both wait for good: the job in B waits for one queued in A behind the job that waits for it. |
| A job awaits `close()` or `cancelAll()` of its controller | It waits for itself: both wait for the jobs of every lane. |
| `close()` | The queues of every lane are cleared, the running job of every lane is cancelled, and `close` completes when the last of them ends. |
| `close(mode: SoloCloseMode.drain)` | Every lane runs its queue out, and `close` completes when all of them are empty. |
| During a drain, a job of one lane queues a continuation in another | The continuation ends `Cancelled(closed)`: a closed controller takes no new root job, whichever lane asks. |
| An unlike fails after a reload has brought the server's word on the like | The correction puts back the confirmed mark the unlike found. It says what the server says, and the next reload takes it away. |

Two controllers could take the continuation of a drain: the one drained first
and the other closed later. One controller closes its lanes together, so a
continuation that another lane has to take becomes part of a write instead, as
the settling of the feed is part of the reload's write.
