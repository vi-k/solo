# Линии

`SoloLanes<S>` — контроллер с несколькими очередями корневых задач над одним
состоянием. Каждая очередь — линия: её задачи идут по одной, в том порядке,
который держит `Solo`, а задачи разных линий идут бок о бок. Для задачи одной
линии запись другой линии — то же, что `externalSetState` для задачи `Solo`: её
правила спрашиваются снова, и `W` или `keepWhile`, которые больше
не выполняются, её отменяют.

У этого два следствия, которые легко пропустить, если прийти от `Solo`. Линия
перезагрузки, которая пишет `Loading`, отменяет все лайки с `W = Loaded`:
идущий лайк отменяется на этой записи, а лайк, который доходит до старта, пока
состояние — `Loading`, так и не выполняет своё тело. И правила проходят мимо
`cancellable: false`, поэтому запись одной линии отменяет команду устройству,
которая идёт в другой. Оба случая есть в разделе
[«Таблица случаев»](#таблица-случаев).

Большинство разделов открывается первой попыткой: версией, к которой ведёт
словарь `Solo`, и тем, что этот код делает. Ответ идёт следом, под своим
заголовком. Раздел, в котором ошибиться не в чем, открывается ответом.
Состояния и трассы под кодом — то, что этот код печатает при запуске.

## Две очереди над одним состоянием

Ворота узнают у сервера, можно ли продолжать работу. Их состояние — `Permit`,
запись `({bool start, bool keep})`. Работа выполняет шаги, которые идут
какое-то время: шаг начинается, только пока выполняется `start`, и отменяется,
как только перестаёт выполняться `keep`. Чтение сервера не должно ждать конца
шага.

### Первая попытка

```dart
// Первая попытка: два контроллера, и исполнитель копирует ворота.
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

  // Вызывается один раз, когда завершается закрытие исполнителя.
  @override
  void onClose() => gate.removeListener(_sync);
}
```

`Solo` выполняет одну корневую задачу за раз, поэтому чтение и шаги получают
по своему контроллеру. Исполнитель копирует состояние ворот в своё через
`externalSetState`, из слушателя, который выполняется внутри каждой записи
ворот, и правила его шагов судят по копии. Шаг длиной 100 мс начинается в 0 мс,
сервер отзывает разрешение в 30 мс, второй шаг запрошен в 40 мс, а разрешение
возвращается в 150 мс вместе с третьим:

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

Первый шаг доходит до конца в 100 мс, хотя `keep` пропал в 30 мс: `ctx.join`
даёт своему действию закончиться и проверяет отмену после него. Это работает,
и вот чего это стоит:

- подписки исполнителя на ворота и её снятия в `onClose`;
- второй копии состояния, в исполнителе;
- двух контроллеров, которые слушает экран, с `Listenable.merge` во Flutter;
- двух вызовов `close` у того, кто их создал.

### Две линии

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

Линии объявляются в конструкторе через `lane`, как объясняет раздел
[«Объявление линий»](#объявление-линий). Линия — это `SoloLane` с членами
очереди `Solo`: `enqueue`, `job`, `enqueueJob`, `collect`, `accumulate`,
`queue`, `current`, `lastJobWhere` и `pending`. Они публичные: кто держит
линию, тот ставит в неё задачи, поэтому контроллер хранит свои линии
в приватных полях. `Solo` делает детей `ctx.child` через собственный `job`
и ставит группы накопителя через собственный `enqueueJob`, так что подкласс,
который их переопределяет, видит и эти задачи. Линия не подкласс
и переопределения не принимает: каждая задача `SoloLanes` доходит до `onStart`
и `onFinish` контроллера и до `SoloObserver`, как показывает раздел
[«Наблюдение за всеми контроллерами»](diagnostics.md#наблюдение-за-всеми-контроллерами).

Обновление пишет состояние в линии ворот, и правила шага в линии работы
спрашиваются о нём сразу. Те же шаги и обновления печатают ту же трассу.
Подписки, слушателя, `onClose`, копии и второго `close` больше нет: состояние
одно и `close` один. Обновление пишет состояние целиком, и здесь ему можно:
`Permit` — это всё состояние.

Внутри линии задачи держат порядок очереди `Solo`, с её политиками и `first:`.
`Policy` ищет свой ключ только в своей линии, поэтому `restart` отменяет идущую
задачу своей линии и не трогает другие. Линия ставит в очередь только задачи,
которые создала она сама: задача другой линии или другого контроллера
отклоняется с `ArgumentError`. Между линиями порядка нет, и движок ничего
не разводит: задачи, которые не должны пересекаться, например две команды
одному устройству, идут в одну линию.

## Запись, которая бережёт работу другой линии

Лента из раздела
[«Нажатие, которое не ждёт перезагрузки»](jobs.md#нажатие-которое-не-ждёт-перезагрузки),
в одном контроллере. `Feed` хранит посты такими, какими их прислал сервер,
и `Mark` для каждого поста, который нажал пользователь; экран показывает
отметку поверх поста. Линия перезагрузки запрашивает посты у сервера, который
отвечает через две секунды, и публикует их, как показывает раздел
[«Снимок с сервера»](#снимок-с-сервера). Линия лайков ставит отметку на пост
и отправляет лайк, который сервер подтверждает через двадцатую долю секунды.
Каждая линия пишет свою часть состояния, и ни одна не должна терять то, что
написала другая.

### Первая попытка

```dart
// Первая попытка: лайк пишет поверх копии, прочитанной до ожидания.
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      final feed = ctx.state;
      ctx.emit(feed.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(feed.mark(postId, Mark(liked, ++_confirmations)));
    });
```

Слушатель печатает состояние как посты и отметки поверх них, а `#1` — номер
подтверждения. Перезагрузка отправлена в 0 мс, лайк нажат в 1980 мс:

```text
0 ms: reload sent
1980 ms: posts none; marks p1 liked
1980 ms: like p1 sent
2000 ms: reload answered
2000 ms: posts p1, p2; marks p1 liked
2030 ms: like p1 confirmed
2030 ms: posts none; marks p1 liked #1
```

Перезагрузка публикует посты в 2000 мс, пока лайк ждёт сервера. В 2030 мс лайк
пишет свою копию из 1980 мс с одной изменённой отметкой, и посты пропадают:
копия прочитана до того, как перезагрузка их опубликовала. В `Solo`, пока
задача ждёт, пишут только её дочерняя задача или `externalSetState`; здесь
пишет каждая другая линия.

### Чтение в момент записи

```dart
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      ctx.emit(ctx.state.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)));
    });
```

Каждый `emit` берёт состояние таким, какое оно сейчас, со всем, что тем
временем написала другая линия. `ctx.state` и `emit` после него выполняются
одним синхронным отрезком, и никакая другая линия между ними не пишет:

```text
0 ms: reload sent
1980 ms: posts none; marks p1 liked
1980 ms: like p1 sent
2000 ms: reload answered
2000 ms: posts p1, p2; marks p1 liked
2030 ms: like p1 confirmed
2030 ms: posts p1, p2; marks p1 liked #1
```

`ctx.state` — контрольная точка, как в `Solo`: перед тем как вернуть состояние,
он проверяет отмену и правила. Простой `emit` движок не отклоняет: целое новое
состояние, записанное намеренно, и потерянное обновление для него выглядят
одинаково, и различает их только предметная область. Но он видит, когда
состояние было прочитано, и с [`Solo.debug`](diagnostics.md#логи) второй `emit`
первой попытки приходит со строкой:

```text
Job() emit over a write of lane reload made after Job() last read the state: read ctx.state after the wait, or this write undoes the work of reload
```

Задача, которая прочитала состояние до ожидания и после него намеренно пишет
снимок, тоже получит эту строку, поэтому это строка в логе, а не ошибка.
Задача, которая состояние не читала, строки не получит, как и чтение в момент
записи.

## Снимок с сервера

Перезагрузка приносит слово сервера о лайках. Лайк, который сервер подтвердил
до отправки перезагрузки, возвращается в постах, и его отметка больше не нужна.
Лайк, который ещё в пути, сохраняет отметку: сервер ответил на перезагрузку без
него.

### Первая попытка

```dart
// Первая попытка: ответ сервера становится всем состоянием.
Job<void> reload() => _reload.enqueue<Feed, void>(
  key: 'reload',
  policy: Policy.droppable,
  (ctx) async {
    final posts = await ctx.abandonable(api.fetchPosts);
    ctx.emit(Feed(posts: posts));
  },
);
```

Лайк здесь тот, что читает в момент записи. Перезагрузка отправлена в 0 мс,
лайк нажат в 100 мс:

```text
0 ms: reload sent
100 ms: posts none; marks p1 liked
100 ms: like p1 sent
150 ms: like p1 confirmed
150 ms: posts none; marks p1 liked #1
2000 ms: reload answered
2000 ms: posts p1, p2; marks none
```

Сервер подтвердил лайк в 150 мс, но на перезагрузку ответил тем, что было в 0
мс, до лайка. В 2000 мс ответ заменяет всё состояние, отметку тоже, и сердечко
гаснет, хотя сервер держит лайк. Чтение в момент записи здесь не помогает:
перезагрузка не меняет часть того, что читает, она пишет всё целиком.

### Склейка

```dart
/// Лайк, который экран показывает поверх ленты.
final class Mark {
  final bool liked;

  /// Номер подтверждения или `null`, пока лайк в пути.
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

  /// Убирает отметки лайков, которые сервер уже подтвердил, когда после
  /// [seen] подтверждений отправлена перезагрузка; лайк в пути сохраняет
  /// отметку.
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

Перезагрузка вклеивает посты в состояние, которое читает в момент записи,
а `settled(seen)` убирает отметки, которые покрывает ответ сервера. `seen` —
число подтверждений на момент отправки перезагрузки. У лайка, подтверждённого
к этому времени, номер не больше `seen`, и его приносят посты; лайк, который
ещё в пути, получает номер больше или пока не имеет никакого и сохраняет
отметку. Те же нажатия и вторая перезагрузка, отправленная в 2100 мс:

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

`setLiked` — лайк из прошлого раздела с поправкой. `before` — отметка, которая
была у поста, когда лайк начался, и когда лайк падает или отменяется,
`ifFailed` или `ifCancelled` возвращают её на место: пост показывает то же, что
до нажатия. Каждый обработчик правит пришедший ему `feed` и возвращает его же:
с начала лайка перезагрузка могла записать своё, и состояние, сохранённое тогда
и возвращённое целиком, унесло бы её посты. Исход нажатия никто не читает,
поэтому `isExpectedError` называет `ApiException` неудавшегося запроса,
и до зоны оно не доходит.

Лайк не ждёт перезагрузки. Лайк второго поста по-прежнему ждёт первого: линия
лайков одна. Сверка — часть записи перезагрузки, а не задача лайков, поэтому
она не ждёт ни одного лайка, а экран слушает один контроллер.

## Работа, которую новая эпоха делает устаревшей

Некоторые записи делают работу других линий устаревшей: выход из аккаунта,
смена профиля или источника данных. Об этом говорит предметная область,
а не счёт записей: поле состояния, которое меняет такая запись, и `keepWhile`
в тех задачах, которым это важно. Здесь лента несёт `epoch`, а из аккаунта
выходит линия аккаунта:

```dart
Job<void> signOut() => _account.enqueue<Feed, void>(
  // Новая эпоха: работа линий для прошлого пользователя устарела.
  (ctx) async => ctx.emit(Feed(epoch: ctx.state.epoch + 1)),
);

Job<void> like(String postId) {
  final epoch = currentState.epoch;
  return _likes.enqueue<Feed, void>(
    keepWhile: (feed) => feed.epoch == epoch,
    (ctx) async {
      ctx.emit(ctx.state.mark(postId, const Mark(true)));
      await ctx.join(() => api.setLiked(postId, liked: true));
      // Сюда не доходит, если эпоха сменилась.
      ctx.emit(ctx.state.mark(postId, Mark(true, ++_confirmations)));
    },
  );
}
```

Эпоха, в которой лайк поставлен в очередь, хранится в замыкании `keepWhile`,
а не в состоянии: `like` читает `currentState.epoch` в момент вызова,
а `keepWhile` сравнивает с ней эпоху каждого нового состояния. Поэтому эпоха
читается в методе, до `enqueue`, а не в теле, которое начнётся позже, когда
эпоха может уже смениться. Лайк `p1` отправлен в 0 мс, лайк `p2` ждёт за ним,
а пользователь выходит из аккаунта в 10 мс:

```text
0 ms: like p1 sent
10 ms: sign out
50 ms: like p1 confirmed
50 ms: like p1: Cancelled(rules: keepWhile)
50 ms: like p2: Cancelled(rules: keepWhile)
```

- Новая эпоха отменяет лайк `p1` в 10 мс, на той записи, которая её меняет,
  а не на следующей записи лайка: движок спрашивает `keepWhile` после каждой
  записи. С этого момента лайк ничего не пишет, а задача, которую отменили её
  правила, не получает `ifCancelled`: старая поправка не ложится на новые
  данные.
- Лайк `p2` поставлен в очередь в старой эпохе, а до старта доходит в новой.
  `keepWhile` спрашивается и на старте, и его тело так и не выполняется.
- Запись, которая сохраняет эпоху, не отменяет никого.

Отмена и освобождение линии — две разные гарантии. Отмена сразу отнимает
у задачи запись и поправку. Линию задача держит, пока не кончится её ожидание:
`ctx.join` ждёт своего действия и проверяет отмену после него. Лайк `p1` держит
линию лайков, пока сервер не ответит в 50 мс, и `close()`, вызванный в 10 мс,
завершается тогда же. Освободить линию раньше — отдельный выбор:
с `ctx.abandonable` вместо `ctx.join` задача отпускает линию сразу, а запрос
идёт на сервере дальше.

## Правила по типу на состоянии-записи

Камера и её уведомление из раздела
[«Уведомление, которое принимает экран»](state.md#уведомление-которое-принимает-экран),
в одном контроллере. Линия камеры делает снимки, а линия уведомлений закрывает
уведомление о сохранённом фото, так что принятие не ждёт снимка. Снимку нужна
камера в состоянии `Ready`, и он отменяется, когда она перестаёт в нём быть.
То, что сообщает устройство, попадает в состояние через `reflect`, с помощью
`externalSetState`.

### Первая попытка

```dart
// Первая попытка: состояние-класс, и Ready проверяется вручную.
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

Две части одного состояния составляют произведение, и его держит класс
с полями. Но никакой подтип `Studio` не говорит, что камера в `Ready`, поэтому
`W` — весь `Studio`, `canStart` проверяет `Ready` вручную, а тело приводит тип.
Устройство сообщает `Off` в 30 мс, во время фокусировки:

```text
0 ms: focus started
30 ms: camera off
50 ms: focus done
50 ms: shoot: Failed(type 'Off' is not a subtype of type 'Ready' in type cast)
```

`canStart` спрашивается один раз, на старте, поэтому снимок ничто не отменяет,
и приведение после фокусировки бросает. Снимок кончается `Failed`
с `TypeError`, за который никто не отвечает. `keepWhile` с той же проверкой
отменяет снимок, а приведение остаётся.

### W на записи

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
        // W говорит, что камера в Ready, и ctx.state говорит то же.
        final zoom = ctx.state.camera.zoom;
        final photo = await ctx.join(() => device.shoot(zoom));
        ctx.emit((camera: ctx.state.camera, notice: Notice(photo)));
      });

  // Устройство сообщает о камере: Off или снова Ready.
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

На записи `W` работает. `Ready` — подтип `Camera`, поэтому запись
`({Ready camera, Notice? notice})` — подтип `Studio`, а проверка `state is W`
смотрит на тип значения в каждом поле. Тело читает `ctx.state.camera` как
`Ready` без приведения, а `Off` отменяет снимок:

```text
0 ms: focus started
30 ms: camera off
50 ms: focus done
50 ms: shoot: Cancelled(rules: is not ({Ready camera, Notice? notice}))
```

В обеих формах запись сохраняет другую часть вручную: `ctx.state.notice`
в снимке, `ctx.state.camera` в принятии. Линии подходят там, где части говорят
об одном: `Permit`, который одна линия пишет, а другая читает, посты и отметки
поверх них. Частям, которые живут разное время, например уведомлениям, которые
переживают камеру, по-прежнему нужны два контроллера, как в разделе
[«Своя доска»](state.md#своя-доска): линии одного контроллера закрываются
вместе.

## Объявление линий

Линия объявляется один раз, и набор линий не меняется, пока контроллер
работает.

### Первая попытка

```dart
// Первая попытка: линии в полях late final.
late final _reload = lane('reload');
late final _likes = lane('likes');

FeedController(this.api) : super(const Feed());
```

Поле `late final` читается хорошо, и так контроллер хранит накопитель. Но оно
объявляет свою линию при первом чтении, в первом вызове метода, а этот вызов
приходит после конструктора:

```text
Bad state: Cannot declare lane reload of FeedController after its constructor: lanes are declared in the constructor body, and a late final field declares its lane on its first read; see https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes
```

`SoloLanes` запечатывает набор линий через микрозадачу после своего
конструктора, поэтому первый `reload()` бросает, когда бы он ни пришёл. Чтение
в том же синхронном прогоне, что и конструктор, проходит, но только до первой
задачи: экран, который пишет `FeedController(api)..reload()`, объявляет линию
перезагрузки и ставит в неё задачу, и первый `setLiked` всё равно бросает:

```text
Bad state: Cannot declare lane likes of FeedController after enqueueJob of one of its lanes was called: from the first call on, the lanes are what the pump walks; see https://github.com/vi-k/solo/blob/main/packages/solo/doc/lanes.md#declaring-lanes
```

Без печати, которая наступает через микрозадачу после конструктора, то,
сработает ли вызов, зависело бы от порядка нажатий, а порядок, в котором насос
обходит линии, следовал бы порядку первых чтений, а не строкам класса.

### В теле конструктора

```dart
late final SoloLane<Feed> _reload;
late final SoloLane<Feed> _likes;

FeedController(this.api) : super(const Feed()) {
  _reload = lane('reload');
  _likes = lane('likes');
}
```

Поля присваиваются в теле конструктора, поэтому линии объявлены раньше любой
задачи, а их порядок — порядок этих строк: в нём их отдаёт `lanes`. `lane`
и `lanes` защищённые. `lane` бросает `StateError` на имя, линия с которым
у контроллера уже есть: каждый вызов объявляет новую линию, и две линии с одним
именем читались бы как одна. Бросает он и после того, как набор запечатан:
через микрозадачу после конструктора, на первом `enqueueJob` любой линии,
чем бы он ни кончился, и после `close`.

Две линии различаются тождеством, а не именем: имя — для логов и `toString`.
Задача узнаёт свою линию через `job.lane`, `SoloLaneId` с этим именем,
а у задачи `Solo` его нет.

## Таблица случаев

| Что происходит | Что из этого выходит |
| --- | --- |
| Синхронная часть задачи одной линии ставит задачу в другую | Если другая линия свободна, она начинает задачу прежде, чем управление вернётся в цикл событий; где этот старт встанет среди микрозадач того же хода, не обещано. |
| Задача одной линии пишет состояние вне `W` задачи другой, как перезагрузка пишет `Loading` под лайком с `W = Loaded` | Идущий лайк отменяется на этой записи, а лайк, который доходит до старта, пока состояние — `Loading`, отменяется до того, как выполнится его тело. |
| Запись одной линии и задача `cancellable: false` другой, чей `keepWhile` отвергает новое состояние | Задача всё равно отменяется: правила проходят мимо `cancellable: false`, как `externalSetState` в `Solo`. |
| Задача ждёт задачу, которую поставила в другую линию | Она ждёт, пока другая линия выполняет ту задачу. |
| Задача ждёт задачу, которую поставила в свою линию | Она ждёт вечно: линия выполняет одну задачу за раз. |
| Задача линии A ждёт задачу, которую поставила в линию B, а та ждёт задачу, которую поставила в линию A | Обе ждут вечно: задача в B ждёт задачу, поставленную в A за той, которая ждёт её саму. |
| Задача ждёт `close()` или `cancelAll()` своего контроллера | Она ждёт саму себя: оба ждут задач каждой линии. |
| `close()` | Очереди всех линий очищаются, а идущую задачу каждой линии просят отмениться; задача с `cancellable: false` отказывает и идёт дальше. `close` завершается, когда кончается последняя из них, как рассказывает [«Три способа остановиться»](cancellation.md#три-способа-остановиться). |
| `close(mode: SoloCloseMode.drain)` | Каждая линия доводит свою очередь до конца, и `close` завершается, когда все они пусты. |
| Во время дренажа задача одной линии ставит продолжение в другую | Продолжение кончается `Cancelled(closed)`: закрытый контроллер не берёт новой корневой задачи, какая бы линия ни просила. |
| Снятие лайка падает после того, как перезагрузка принесла слово сервера о лайке | Поправка возвращает подтверждённую отметку, которую застало снятие лайка. Она говорит то же, что сервер, и следующая перезагрузка её убирает. |

Продолжение дренажа могли бы принять два контроллера: тот, что закрывается
с дренажем первым, и другой, закрытый позже. Один контроллер закрывает свои
линии вместе, поэтому продолжение, которое должна принять другая линия,
становится частью записи, как сверка ленты — часть записи перезагрузки.
