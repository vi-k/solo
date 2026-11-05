# Анонс 1.0: статья, два поста и ответ в bloc#3069, черновики

> **Состояние на 2026-11-05:** черновики написаны по слову владельца «давай
> анонс» и исправлены по независимому ревью Opus (раздел «Ревью»); публикует
> владелец сам. Ничего не опубликовано.
> **Что это:** четыре текста для каналов после 1.0 — статья «What cancelling
> a Future takes in Dart», посты в r/FlutterDev и r/dartlang, ответ
> в bloc#3069 — и зонды, которыми проверен их код.
> **Связанные записи:** `2026-10-30-prospects-review.md`,
> `2026-10-31-site-core-entry-report.md`,
> `2026-11-05-core-readme-entry-plan.md`.

Каналы выбраны в `2026-10-30-prospects-review.md`, «Что предлагаю владельцу»,
п. 5, и отложены владельцем 2026-10-31 до выпуска 1.0: статья по-английски
от боли, посты в r/FlutterDev и r/dartlang, ответ в bloc#3069 со ссылкой
на страницу ядра «With riverpod and bloc». Все четыре текста ведут к ядру,
решение 144 `docs/settled.md`; `solo` назван один раз, в конце статьи, и нигде
не подан заменой bloc или riverpod, решение 133.

Тексты лежат в огороженных блоках без переносов: GitHub в комментариях
превращает каждый перенос строки в разрыв, и абзац, залитый по 79 символов,
пришёл бы в bloc#3069 столбиком. Копировать блок целиком, без строк ограды.

## Что проверить перед публикацией

- **Где живёт статья.** Не решено: dev.to, Medium или страница на сайте
  документации. Посты ссылаются на неё словом `[ARTICLE LINK]` — заменить
  адресом, когда он будет.
- **Порядок.** Сначала статья, потом посты со ссылкой на неё, ответ
  в bloc#3069 — когда угодно: он от статьи не зависит.
- **Правила сабреддитов.** Достать их с reddit.com не вышло: сайт отдаёт
  заглушку вместо `about/rules.json`. Известно по зеркалам, что r/FlutterDev
  с 2023 года снимает рекламу закрытых приложений; пакеты с открытым кодом там
  публикуют. Флер и правило о самопродвижении посмотреть в боковой панели обоих
  сабреддитов.
- **Отправка `main`.** Ссылки на GitHub ведут на `blob/main`, а сайт
  документации собирается из `main` после отправки. Страница «Why a job»
  на сайте появится только с отправкой коммитов 2026-11-05, поэтому тексты
  на неё не ссылаются. Публиковать после того, как сайт пересоберётся:
  на 2026-11-05 живой сайт ещё отдаёт снятую 2026-11-04 страницу
  `/async_job/bloc/` и не знает `/async_job/why/`; проверить, что первая
  пропала.
- **Код на old.reddit.** Блоки кода в оградах из обратных кавычек старый
  интерфейс Reddit не рисует, там код — отступ в четыре пробела. Посмотреть
  предпросмотр поста и решить, какую форму оставить.

## Статья

Заголовок: **What cancelling a Future takes in Dart**

````markdown
A user opens a screen, the screen starts a load, and the user leaves before the load is done. In Dart the load runs on. A `Future` is the result of a computation, not the computation, and it has no `cancel()`: [dart-lang/sdk#42855](https://github.com/dart-lang/sdk/issues/42855) has asked for one since 2020. In bloc the same wish is [felangel/bloc#3069](https://github.com/felangel/bloc/issues/3069), open since 2021: a cubit closed during a load throws `Bad state: Cannot emit new states after calling close` when the load comes back.

This article takes one small load, tries to cancel it with the tools Dart already has, and lists what cancelling it takes. Then it shows [async_job](https://pub.dev/packages/async_job), a pure Dart package that does those things, and what it does not do.

## The load

The load opens a database, reads three pages and closes the database:

```dart
Future<List<String>> load() async {
  final db = await Database.open();
  try {
    return [for (var page = 1; page <= 3; page++) await db.readPage(page)];
  } finally {
    await db.close();
  }
}
```

`Database` is a fake that opens in 20 ms, reads a page in 30 ms and prints what it does. In every example the user leaves 35 ms in, while the first page is being read; `leave()` stands for that moment. The traces are what the code prints.

## A flag

The first tool at hand is a flag that the load checks:

```dart
var cancelled = false;

Future<List<String>?> loadOrStop() async {
  final db = await Database.open();
  try {
    final rows = <String>[];
    for (var page = 1; page <= 3; page++) {
      if (cancelled) return null;
      rows.add(await db.readPage(page));
    }
    return rows;
  } finally {
    await db.close();
  }
}

final rows = loadOrStop();
await leave();
cancelled = true;
print('result: ${await rows}');
```

```text
database opened
page 1 read
database closed
result: null
```

It works: the load finishes the page in flight, skips the rest and closes the database. The cost is in the shape of the code. Every `await` needs a check of its own, and a check left out lets the load run on, with nothing pointing at the place. Every resource needs a `finally`. And the caller tells a stop from a result by a sentinel, `null` here, that the result type has to make room for. It is a convention, kept by hand in every async function.

## Future.timeout

`timeout` sounds like a stop:

```dart
try {
  await load().timeout(const Duration(milliseconds: 35));
} on TimeoutException {
  print('gave up');
}
```

```text
database opened
gave up
page 1 read
page 2 read
page 3 read
database closed
```

It stops the waiting, not the load: the caller moves on, and the load reads every page for nobody.

## CancelableOperation

`package:async` has `CancelableOperation`:

```dart
final operation = CancelableOperation.fromFuture(load());
await leave();
await operation.cancel();
print('cancelled');
```

```text
database opened
cancelled
page 1 read
page 2 read
page 3 read
database closed
```

`cancel()` stops delivering the value, and the load is the same `Future` as before: it runs on. The `value` of a cancelled operation never completes, so whoever still awaits it waits for good, unless it asks for `valueOrCancellation()` instead. `fromFuture` takes an `onCancel` callback, but whatever it should stop, it has to reach by itself: a flag again, or a stop signal of the call.

## What cancelling takes

Put together, cancelling this one load takes:

- A checkpoint at every `await`, and a way to find the one that is missing.
- A decision about the call in flight: wait for it to finish, or walk away and let it finish for nobody.
- Cleanup registered where the resource opens, which runs however the load ends, including for a database that opens after the cancellation.
- A `cancel()` that can be awaited and returns once the cleanup is done.
- An outcome that tells cancelled from done and failed, so the result type does not make room for a sentinel.
- A way to hand the stop to a call that can stop, such as an HTTP request with a cancel token of its own.

And once the work starts work of its own, it takes children: a parent that ends after them, and a cancellation that reaches them.

## A job

`async_job` puts these into a `Job`. Its body gets a context, `ctx`. Every call the body awaits through `ctx.join` is a checkpoint, and `dispose` registers the cleanup next to the open:

```dart
final job = Job<List<String>>((ctx) async {
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  return [
    for (var page = 1; page <= 3; page++)
      await ctx.join(() => db.readPage(page)),
  ];
});
final outcome = job.done;

await leave();
await job.cancel();
print('cancel returned');
print(await outcome);
```

```text
database opened
page 1 read
database closed
cancel returned
Cancelled(manual)
```

The cancellation lands while the first page is being read. `ctx.join` waits for that read, then throws `Cancelled` instead of handing the page to the body, so the second and third pages never start. `dispose` closes the database, and `cancel()` returns after it has. `job.done` gives `Cancelled(manual)`, which the caller tells from `Done` and `Failed`. Had the cancellation come during `Database.open`, `join` would have waited for the open, and `dispose` would have closed the database that arrived for nobody.

`done` is read right after the constructor: a job that fails before anybody reads its outcome would otherwise reach the zone as an uncaught error.

### Walking away from a call

For a call that leaves nothing for the job to clean up, waiting is a waste. `ctx.abandonable` stops waiting at the cancellation, and the call runs on with nobody to take its result. Here `fetchQuote` prints when the request goes out and when the answer comes, 100 ms later:

```dart
final job = Job<String>((ctx) => ctx.abandonable(fetchQuote));
final outcome = job.done;

// Somebody left the screen while the quote was on its way.
await Future<void>.delayed(const Duration(milliseconds: 50));

// Returns before fetchQuote answers.
await job.cancel();
print(await outcome);
```

```text
request sent
Cancelled(manual)
quote answered
```

### Handing the stop to the call

A call that can be stopped takes a stop signal of its own, and `ctx.onCancel` fires it together with the cancellation. With dio:

```dart
final job = Job<String>((ctx) async {
  final token = CancelToken();
  ctx.onCancel(token.cancel);

  final response = await ctx.join(
    () => dio.getUri<String>(url, cancelToken: token),
  );
  return response.data!;
});
```

The connection closes, and the server stops working on an answer nobody will read. The aborted request still throws, on every cancellation, and by default the error goes to the zone as an uncaught one. One line in `main` tells async_job that this error is how the client stops, and from then on it goes to the job's observer instead of the zone:

```dart
Job.isCancellationError = (error) =>
    error is DioException && error.type == DioExceptionType.cancel;
```

http 1.5 and later does the same with `AbortableRequest` and its `abortTrigger`; the filter then names its `RequestAbortedException` too.

### Children

A body starts a child job with `ctx.run`. The parent ends after its children and their cleanup, and a cancellation it accepts passes down to them. The [Children](https://docs.yet-another.dev/async_job/children/) page goes through it.

## What it does not do

- **It is cooperative.** A body stops at a checkpoint. An `await` that goes around `ctx`, or a loop that never awaits, runs on after the cancellation. The analyzer plugin [async_job_lints](https://pub.dev/packages/async_job_lints) reports an `await` in a body that does not go through the context; it is the `bare_await` lint, turned on by name.
- **`ctx.join` waits for the call in flight.** A long call needs its own stop signal, as above, or `ctx.abandonable`.
- **It is not state management.** A job goes under a riverpod provider or a bloc handler without changing the state layer, and [With riverpod and bloc](https://docs.yet-another.dev/async_job/riverpod-and-bloc/) shows where each of them cancels it.

`async_job` 1.0.0 is on [pub.dev](https://pub.dev/packages/async_job). It depends only on `meta`, and from 1.0 it follows semantic versioning. The [documentation](https://docs.yet-another.dev/async_job/) covers outcomes, cancellation, cleanup, children, streams and testing under `fake_async`. For state with a queue on top of jobs there is [solo](https://pub.dev/packages/solo), from the same repository.
````

## r/FlutterDev

Заголовок: **async_job 1.0: cancel async work when the screen goes, under
riverpod or bloc**

````markdown
When a screen goes away, riverpod disposes its provider and bloc closes its handlers, but the load they started is a `Future`, and nothing stops it. It runs to the end for nobody, and a cubit throws `Bad state: Cannot emit new states after calling close`.

[async_job](https://pub.dev/packages/async_job) is a pure Dart package for cancelling that work. A job checks for the cancellation at every call it awaits through its context, closes what it opened however it ends, and ends `Done`, `Failed` or `Cancelled`. It goes under the state layer you already have. Under riverpod, the provider cancels the job when it is disposed:

```dart
Job<List<String>> readRows(String query) => Job((ctx) async {
  final db = await ctx.join(
    () => Database.open(query),
    dispose: (db) => db.close(),
  );
  return [
    for (var page = 1; page <= 3; page++)
      await ctx.join(() => db.readPage(page)),
  ];
});

final rows = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  query,
) {
  final job = readRows(query);
  ref.onDispose(job.cancel);
  return job.value;
});
```

When the user leaves the screen during the first page, the job stops after that page and the database closes; here with a fake `Database` that prints what it does:

```text
database opened for dart
screen left
dart: page 1 read
database for dart closed
```

A `ProviderObserver` that sends failures to crash reports hears that `Cancelled` too and should skip it.

`ref.onCancel` looks like the place for it but is not: riverpod 3 calls it when a covered screen pauses its listeners, and the reads start over when the screen comes back. The page [With riverpod and bloc](https://docs.yet-another.dev/async_job/riverpod-and-bloc/) shows that case, a notifier that starts again on every search, a bloc handler under `restartable()` and an HTTP request that aborts with the job.

Alongside it: [async_job_lints](https://pub.dev/packages/async_job_lints), an analyzer plugin that reports code that compiles and still loses a resource or ignores a cancellation; the two lints among its rules are turned on by name.

The longer story, with a flag, `Future.timeout` and `CancelableOperation` tried first: [ARTICLE LINK]

I'm the author. Feedback is welcome, especially from people who have fought this with `isClosed` checks or `CancelableOperation`.
````

## r/dartlang

Заголовок: **What cancelling a Future takes in Dart (async_job 1.0)**

````markdown
A `Future` in Dart has no `cancel()`. I wrote up what cancelling one small load takes, trying the tools Dart already has first: [ARTICLE LINK]

The load opens a database, reads three pages and closes it, and somebody cancels it during the first page:

- **A flag** works, but needs a check after every `await`, a `finally` for every resource and a sentinel the result type makes room for.
- **`Future.timeout`** stops the waiting; the load reads every page for nobody.
- **`CancelableOperation`** stops delivering the value; the load runs on, and the `value` of a cancelled operation never completes unless read through `valueOrCancellation()`.

[async_job](https://pub.dev/packages/async_job) 1.0 puts what is missing into a `Job`: a checkpoint at every call the body awaits through its context, cleanup registered where a resource opens, a `cancel()` that returns once the cleanup is done and an outcome that tells `Cancelled` from `Done` and `Failed`:

```dart
final job = Job<List<String>>((ctx) async {
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  return [
    for (var page = 1; page <= 3; page++)
      await ctx.join(() => db.readPage(page)),
  ];
});
```

Cancelled during the first page, it finishes that read, skips the rest, closes the database and ends `Cancelled(manual)`. Children, deadlines, streams and `fake_async` tests are covered in the [documentation](https://docs.yet-another.dev/async_job/).

It is pure Dart and depends only on `meta`, so it runs in CLI tools and servers as well as in Flutter. The cancellation is cooperative: an `await` that goes around the context does not hear it, and the analyzer plugin [async_job_lints](https://pub.dev/packages/async_job_lints) reports such an `await`.

I'm the author; questions and criticism welcome.
````

## Ответ в bloc#3069

Ответ отвечает на пример автора bloc от 2025-03-29 — две дорогие операции,
`isClosed` после каждой, — и на то, что в ветке дважды сказано
о `CancelableOperation`: работа под ним идёт дальше. Он не предлагает ничего
внести в bloc: заявка открыта с 2021 года, автор bloc объяснил, почему API
в ядро не добавляет, и ответ это уважает.

````markdown
A data point from outside bloc, on two points that come up here: `CancelableOperation` stops delivering the value but not the work, and `maybeEmit` still runs B, as [this comment](https://github.com/felangel/bloc/issues/3069#issuecomment-2764251377) shows.

I maintain [async_job](https://pub.dev/packages/async_job), a pure Dart package for cooperative cancellation. Here is the A/B example from above with a job per load, cancelled in `close()`:

```dart
class MyCubit extends Cubit<MyState> {
  MyCubit() : super(MyState.idle);

  Job<void>? _load;

  Future<void> load() async {
    final job = _load = Job((ctx) async {
      emit(MyState.loading);
      await ctx.join(_expensiveOperationA);
      emit(MyState.loadedA);
      await ctx.join(_expensiveOperationB);
      emit(MyState.loadedB);
    });
    if (await job.done case Failed(:final error, :final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    await _load?.cancel();
    return super.close();
  }
}
```

If the cubit is closed while A runs, `close()` cancels the job; `ctx.join` waits for A and then throws `Cancelled` instead of returning, so neither `emit(MyState.loadedA)` nor B runs, and `super.close()` comes after the job has ended: no `StateError` and no `isClosed` checks. Reading `done` never throws, so `load()` rethrows a failure of A or B itself. With A and B printing when they start and finish, a listener printing the states and `print('closed')` after `await cubit.close()`, on bloc 9.2.1 and async_job 1.0.0 (the stream delivers states asynchronously, so `loading` prints after `A started`):

```text
A started
MyState.loading
A finished
closed
```

Here `close()` waits for A. If A can be stopped, such as a dio request, it takes a token through `ctx.onCancel`; if it holds nothing, `ctx.abandonable` leaves it behind. For `Bloc` handlers under `restartable()`, a small bridge through `emit.forEach` cancels the job both on a restart and on `close()`: [A handler that restarts](https://docs.yet-another.dev/async_job/riverpod-and-bloc/#a-handler-that-restarts).

Not suggesting any of this belongs in bloc, only that the work after `close()` has an answer outside it.
````

## Ревью

Независимое ревью Opus черновиков, 2026-11-05, по копии дерева. Critical нет,
две Important и двенадцать Minor с правками английского; ниже — словами
ревьюера, сжато. Ревьюер прогнал оба зонда, стенд `tool/adapter_snippets.py`
для трассы поста в r/FlutterDev и сверил утверждения с исходником ядра, bloc
9.2.1, async 2.13.1, http 1.5 и riverpod 3.4.3. Все трассы совпали, факты
о bloc#3069, sdk#42855 и версиях на pub.dev верны, решения 133 и 144
не нарушены, все восемь адресов отвечают 200.

### Important

1. **Ответ в bloc#3069: `await job.done` молча теряет ошибку A и B.** `done`
   никогда не бросает и помечает задачу наблюдённой: `load()` кончается
   нормально, `Failed` не доходит ни до зоны, ни до наблюдателя. В примере
   автора bloc ошибка A выходит из `load()`. Проверено:
   `packages/async_job/lib/src/job.dart:268-273` и зонд под `runZonedGuarded`.

   Вердикт: принята, проверено по `job.dart` — «Completes with the outcome;
   never throws. Reading it marks the job observed». Итог: исправлено, как
   предложено: `load()` перебрасывает `Failed` через
   `Error.throwWithStackTrace`, ответ говорит об этом фразой; третий прогон
   зонда — «load threw: Bad state: A failed».

2. **Статья: первый пункт списка обещает больше, чем даёт пакет.** «A
   checkpoint at every `await`, that nobody has to remember to write» —
   а `ctx.join` пишут руками, и сама статья ниже говорит, что `await` в обход
   `ctx` идёт дальше; `bare_await` включается только по имени.

   Вердикт: принята. Итог: исправлено, как предложено: «A checkpoint at every
   `await`, and a way to find the one that is missing».

### Minor

1. **Ответ: `_load` помнит только последнюю задачу.** Второй `load()` без
   `close()` оставит первую задачу без отмены.

   Вердикт: правка не нужна — пример повторяет пример автора bloc с одной
   загрузкой, а отмена предыдущей — уже рецепт нотифаера со страницы,
   на которую ведёт ответ.

2. **Ответ: трасса и формулировки.** `A started` раньше `MyState.loading` без
   объяснения; `closed` печатает драйвер, которого нет в тексте; «as shown
   above» в ветке из 37 комментариев; «the thread keeps coming back to» —
   натяжка; в ветке никто не спрашивал, ждёт ли `close()`.

   Вердикт: принята. Итог: исправлено: порядок и `print('closed')` объяснены
   у трассы, ссылка на комментарий автора bloc вместо «above», «two points that
   come up here», концовка — «the work after `close()` has an answer outside
   it».

3. **r/FlutterDev: `providerDidFail` слышит `Cancelled` при каждом уходе
   с экрана.** Скопированный рецепт пошлёт его в отчёты о сбоях.

   Вердикт: принята. Итог: исправлено фразой: наблюдатель, который шлёт сбои
   в отчёты, слышит этот `Cancelled` и пропускает его.

4. **r/FlutterDev: обещание о линтах шире умолчания.** Правила о пропущенной
   отмене — линты, включаемые по имени.

   Вердикт: принята. Итог: исправлено: «the two lints among its rules are
   turned on by name».

5. **r/FlutterDev: слова без предмета.** «reads every page» до страниц, кубит
   «gets» ошибку, «the screen leaves», трасса печатает то, чего код
   не печатает.

   Вердикт: принята. Итог: исправлено все четыре, как предложено.

6. **Статья, «Walking away»: `fetchQuote` не описан.**

   Вердикт: принята частично. Итог: фраза о том, что печатает `fetchQuote`,
   добавлена; ожидание 50 мс оставлено — блок дословно из README ядра, где его
   держит сторож.

7. **Статья: `valueOrCancellation()`.** Первое возражение читателя; работу он
   не останавливает.

   Вердикт: принята, метод есть в async 2.13.1
   (`cancelable_operation.dart:150`). Итог: оговорка добавлена в статью
   и в пост r/dartlang.

8. **Статья: «as it is» неверно для bloc** — там нужен мост `watch`.

   Вердикт: принята. Итог: «without changing the state layer», как на самой
   странице.

9. **Статья: фраза о http неполна** — фильтр называет только `DioException`.

   Вердикт: принята. Итог: дописано, что фильтр называет
   и `RequestAbortedException`.

10. **Статья: ссылка на Children ведёт на GitHub, остальные — на сайт.**

    Вердикт: принята. Итог: ссылка на сайт.

11. **Живой сайт отстаёт от дерева:** `/async_job/bloc/` отвечает 200,
    `/async_job/why/` — 404.

    Вердикт: принята, `/async_job/bloc/` проверен — 200. Итог: пункт
    «Отправка `main`» велит публиковать после пересборки сайта.

12. **Reddit: огороженный код не рисуется на old.reddit.**

    Вердикт: принята. Итог: пункт в «Что проверить перед публикацией».

Правки английского — «tries to cancel it with the tools Dart already has»,
«which» вместо «, that», «`done` is read», «leaves nothing for the job to clean
up», «can be stopped takes a stop signal», фраза о фильтре ошибки, висячий
оборот и «An A that can stop» в ответе — приняты и внесены как предложены.

## Зонды

Код статьи и ответа собран и прогнан 2026-11-05; трассы в текстах — вывод этих
программ. Блоки «Walking away», dio-клиента и провайдера riverpod взяты
из README ядра и страницы «With riverpod and bloc», где их держат сторож README
и стенд `tool/adapter_snippets.py`; трасса поста в r/FlutterDev — трасса
раздела «Cancelling on disposal» той страницы.

Статья: файл в `packages/async_job/example/`, `dart run` из пакета, async_job
из дерева на `57fcae59`, `package:async` из dev-зависимостей. В статье
`leave()` стоит вместо ожидания 35 мс, а драйвер вокруг блоков — функции
`flag`, `timeout`, `operation` и `job`.

```dart
import 'dart:async';

import 'package:async/async.dart';
import 'package:async_job/async_job.dart';

/// A database that opens in 20 ms and reads a page in 30 ms.
class Database {
  static Future<Database> open() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    print('database opened');
    return Database();
  }

  Future<String> readPage(int page) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    print('page $page read');
    return 'page $page';
  }

  Future<void> close() async => print('database closed');
}

// The load.
Future<List<String>> load() async {
  final db = await Database.open();
  try {
    return [for (var page = 1; page <= 3; page++) await db.readPage(page)];
  } finally {
    await db.close();
  }
}

// A flag.
var cancelled = false;

Future<List<String>?> loadOrStop() async {
  final db = await Database.open();
  try {
    final rows = <String>[];
    for (var page = 1; page <= 3; page++) {
      if (cancelled) return null;
      rows.add(await db.readPage(page));
    }
    return rows;
  } finally {
    await db.close();
  }
}

/// Stands for "the user leaves 35 ms in".
Future<void> leave() => Future<void>.delayed(const Duration(milliseconds: 35));

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

Future<void> flag() async {
  final rows = loadOrStop();
  await leave();
  cancelled = true;
  print('result: ${await rows}');
}

Future<void> timeout() async {
  try {
    await load().timeout(const Duration(milliseconds: 35));
  } on TimeoutException {
    print('gave up');
  }
}

Future<void> operation() async {
  final operation = CancelableOperation.fromFuture(load());
  await leave();
  await operation.cancel();
  print('cancelled');
  var completed = false;
  unawaited(operation.value.then((_) => completed = true));
  await settle();
  print('value completed: $completed');
}

Future<void> job() async {
  final job = Job<List<String>>((ctx) async {
    final db = await ctx.join(Database.open, dispose: (db) => db.close());
    return [
      for (var page = 1; page <= 3; page++)
        await ctx.join(() => db.readPage(page)),
    ];
  });
  final outcome = job.done;

  await leave();
  await job.cancel();
  print('cancel returned');
  print(await outcome);
}

Future<void> main() async {
  for (final (name, run) in [
    ('flag', flag),
    ('timeout', timeout),
    ('CancelableOperation', operation),
    ('job', job),
  ]) {
    print('== $name');
    await run();
    await settle();
  }
}
```

```text
== flag
database opened
page 1 read
database closed
result: null
== timeout
database opened
gave up
page 1 read
page 2 read
page 3 read
database closed
== CancelableOperation
database opened
cancelled
page 1 read
page 2 read
page 3 read
database closed
value completed: false
== job
database opened
page 1 read
database closed
cancel returned
Cancelled(manual)
```

Ответ в bloc#3069: отдельный пакет с `async_job: ^1.0.0` и `bloc: ^9.0.0`
с pub.dev, разрешились 1.0.0 и 9.2.1; `dart analyze` без замечаний. Класс
`MyCubit` — дословно блок ответа. Второй прогон, без `close()` до конца
загрузки, показывает, что без отмены B идёт как обычно, третий — что ошибка A
выходит из `load()`, а не пропадает в `done`.

```dart
import 'package:async_job/async_job.dart';
import 'package:bloc/bloc.dart';

enum MyState { idle, loading, loadedA, loadedB }

var failA = false;

Future<String> _expensiveOperationA() async {
  print('A started');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  if (failA) throw StateError('A failed');
  print('A finished');
  return 'a';
}

Future<String> _expensiveOperationB() async {
  print('B started');
  await Future<void>.delayed(const Duration(milliseconds: 100));
  print('B finished');
  return 'b';
}

// MyCubit of the reply goes here.

Future<void> main() async {
  final cubit = MyCubit()..stream.listen(print);
  final loading = cubit.load();
  // The user goes back while A runs.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await cubit.close();
  print('closed');
  await loading;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  print('---- left open');
  final open = MyCubit()..stream.listen(print);
  await open.load();
  await open.close();
  print('---- A fails');
  failA = true;
  final failing = MyCubit()..stream.listen(print);
  try {
    await failing.load();
  } on StateError catch (error) {
    print('load threw: $error');
  }
  await failing.close();
}
```

```text
A started
MyState.loading
A finished
closed
---- left open
A started
MyState.loading
A finished
B started
MyState.loadedA
B finished
MyState.loadedB
---- A fails
A started
MyState.loading
load threw: Bad state: A failed
```
