# async_job

`async_job` добавляет к асинхронному коду на Dart отмену, дочерние задачи
и освобождение ресурсов. Пакет работает на чистом Dart, из зависимостей только
`meta`.

`Job<T>` выполняет функцию, которая называется телом задачи, и запоминает, чем
она завершилась. Через `await job.done` можно получить исход задачи, а через
`await job.value` значение, возвращённое телом. Сама `Job` не реализует
`Future`: задачу можно запустить без `await`, это обычное дело, а не забытое
ожидание, и линты о неожидаемых future её не трогают.

## Установка

```sh
dart pub add async_job
```

## Быстрый старт

Задача открывает базу и читает из неё, а кто-то отменяет её, пока идёт чтение.
Тело получает контекст `ctx`, и каждый вызов, которого оно ждёт через
`ctx.join`, служит контрольной точкой: когда задача отменена, следующая точка
бросает `Cancelled`. `dispose` закрывает базу, чем бы задача ни кончилась:

```dart
import 'package:async_job/async_job.dart';

final job = Job<void>((ctx) async {
  // Проверка перед вызовом и ещё раз перед возвратом значения,
  // а база закрывается, чем бы Job ни кончилась.
  final db = await ctx.join(Database.open, dispose: (db) => db.close());
  use(await ctx.join(db.readAll));
});

// Кто-то ушёл с экрана, пока шло чтение.
await Future<void>.delayed(const Duration(milliseconds: 50));

// Ждёт тело, его детей и его уборку.
await job.cancel();
print(job.outcome); // Cancelled(manual)
```

С `Database`, которая печатает, когда открывается и когда закрывается, это
печатает:

```text
database opened
database closed
Cancelled(manual)
```

`ctx.join` дождался чтения, которое уже началось, и прочитанные данные до тела
не дошли. `await job.cancel()` возвращается, когда задача кончилась вместе
с уборкой, поэтому `outcome` на следующей строке уже готов; ни то ни другое
провал не наблюдает, как объясняет страница
[«Исходы»](../../docs/ru/async_job/outcomes.md). Тело запускается на следующей
микротаске: задача, отменённая сразу после создания, его не выполняет
и кончается `Cancelled(manual)` с `started: false`, поэтому блок сначала ждёт.

## Зачем

У обычной `Future` нет отмены. Флаг может попросить работу остановиться,
но спрашивать флаг работе приходится после каждого `await`, а закрывает
открытое `finally`:

```dart
var cancelled = false;

Future<void> load() async {
  final db = await Database.open();
  try {
    if (cancelled) return;
    final rows = await db.readAll();
    if (cancelled) return;
    use(rows);
  } finally {
    await db.close();
  }
}
```

Каждому новому `await` нужна своя проверка, а пропущенная проверка пускает
работу дальше после отмены, и ничто не укажет на это место. А `load`
возвращается одинаково, отменили работу или она дошла до конца, так что
вызывающий не отличит одно от другого.

Остановить ожидание Dart умеет и сам. `Future.timeout` останавливает его, когда
выходит время, а `CancelableOperation` из `package:async` перестаёт отдавать
значение по вызову `cancel()`. Ни то ни другое не держит того, что работа
открывает: база, которая открылась после конца ожидания, остаётся открытой.
`CancelableOperation` ловит её только в `onCancel`, написанном ради этого
одного ожидания:

```dart
final open = Database.open();
final operation = CancelableOperation.fromFuture(
  open,
  // cancel() прекращает ожидание, а здесь база закроется, когда откроется.
  onCancel: () async => (await open).close(),
);
```

Когда база уже отдана, `cancel()` ничего не делает: следующее чтение идёт
дальше, и работе снова нужны флаг и `finally`. А `value` отменённой операции
не завершается вовсе, и тот, кто его ждёт, ждёт вечно.

Задача добавляет три вещи:

- **Контрольную точку на каждом вызове, которого она ждёт через контекст.**
  `ctx.join` проверяет отмену перед вызовом и перед возвратом значения,
  а задача кончается `Cancelled`, и вызывающий отличит это от `Done`.
- **Уборку, зарегистрированную там, где ресурс открывается.** `dispose`
  закрывает базу, чем бы задача ни кончилась, и база, открытая уже после
  отмены, тоже закрывается, без кода, написанного ради отмены.
- **Детей, которых она ждёт.** Задача кончается после своих детей и своей
  уборки, а принятая ею отмена передаётся детям.

В `async_job` нет управления состоянием, очереди и правил планирования: их
добавляет [solo](#solo). Повторы и пул задач не входят ни в один из пакетов.
Срок встроен: `Job(body, timeout: limit)` отменяет задачу, когда предел вышел,
и она кончается `Cancelled(timeout)`; см. раздел
[«Срок»](../../docs/ru/async_job/cancellation.md#срок) на странице об отмене.

## Развёрнутый пример

Задача открывает базу, выполняет миграцию, помечает базу готовой и возвращает
открытую базу вызывающему коду. Если задача упала или отменена, она вместо
этого закрывает базу:

```dart
final job = Job<Database>((ctx) async {
  final database = await ctx.join(
    Database.open,
    discard: (database) => database.close(),
  );

  final stop = CancelToken();
  ctx.onCancel(stop.cancel);

  await ctx.join(() => database.migrate(stop));
  await ctx.uncancellable(() async {
    await database.writeVersion();
    await ctx.run(database.readyFlag());
  });

  return database;
});

// Кто-то передумал, пока база открывалась.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

final outcome = await job.done; // Cancelled(manual)
```

- **`ctx.join(Database.open)`** дожидается открытия и после отмены, а затем
  бросает `Cancelled` или собственную ошибку открытия, если оно упало. Эту
  ошибку не несёт ни один исход; см.
  [«Куда уходят ошибки»](../../docs/ru/async_job/observing.md#куда-уходят-ошибки).
- **`discard: (database) => database.close()`** закрывает базу, когда задача
  кончается `Failed` или `Cancelled`; при `Done(database)` база остаётся
  открытой для вызывающего. См.
  [«Порядок уборки и поздние результаты»](../../docs/ru/async_job/cleanup.md#порядок-уборки-и-поздние-результаты).
- **`ctx.onCancel(stop.cancel)`** передаёт отмену собственному токену клиента
  в тот момент, когда задача её принимает. `CancelToken` принадлежит клиенту
  базы, а не этому пакету.
- **`ctx.join(() => database.migrate(stop))`** ждёт миграцию, а при отмене — её
  остановки. Клиент, который останавливается броском, при каждой отмене
  отправляет эту ошибку наблюдателю задачи, а затем в зону, если только
  приложение не назвало её один раз в `Job.isCancellationError`; см.
  [«Ошибки отмены»](../../docs/ru/async_job/observing.md#ошибки-отмены).
- **`ctx.uncancellable(() async { ... })`** держит версию и её флаг готовности
  вместе: ребёнок запускается, а отмена ждёт конца шага, но задача всё равно
  кончается `Cancelled`, а `discard` закрывает базу. См.
  [«Придержать отмену»](../../docs/ru/async_job/cancellation.md#придержать-отмену).
- **`ctx.run(database.readyFlag())`** запускает ребёнком задачу, которая пишет
  флаг готовности; `readyFlag()` создаёт её через `Job.deferred`, и запуск
  остаётся за `ctx.run`. См. [«Дети»](../../docs/ru/async_job/children.md).

Полный запускаемый пример с имитацией `Database` и `CancelToken` находится
в `example/example.dart`. Он запускает задачу четыре раза: один раз до конца
и трижды с отменой, пока база открывается, пока идёт миграция и пока пишется
версия. Он печатает:

```text
Nobody changes their mind:
database opened
migrated
version written
ready flag written
Done(database)
database closed

Somebody changes their mind while the database opens:
database opened
database closed
Cancelled(manual)

While it migrates, the token stops the migration:
database opened
migration stopped
database closed
Cancelled(manual)

While the version is written, the step ends whole:
database opened
migrated
version written
ready flag written
database closed
Cancelled(manual)
```

## Контекст коротко

Что делает каждый член `ctx`, как он ведёт себя в уже отменённой задаче и что
с ним делает отмена, пришедшая, пока он работает:

| Член | Что делает | Задача уже отменена | Отмена пришла, пока он работает |
| --- | --- | --- | --- |
| `ctx.check()` | Контрольная точка там, где нет вызова, который можно обернуть | Бросает `Cancelled` |  |
| `ctx.join(action)` | Выполняет действие и ждёт его целиком | Бросает `Cancelled` | Ждёт конца действия, потом бросает |
| `ctx.abandonable(action)` | Выполняет действие и ждёт его, но не дольше, чем живёт задача | Бросает `Cancelled` | Бросает сразу, а действие идёт дальше |
| `ctx.uncancellable(action)` | Выполняет шаг, придержав отмену | Бросает `Cancelled` | Держит отмену до конца шага, а бросает следующая контрольная точка |
| `ctx.pause(duration)` | Даёт пройти времени | Бросает `Cancelled` | Прерывает паузу и бросает |
| `ctx.run(child)` | Запускает ребёнка, созданного через `Job.deferred`, и ждёт его значения | Бросает `Cancelled` | Передаёт отмену ребёнку, ждёт его и бросает |
| `ctx.runAll(children)` | Запускает детей бок о бок и останавливает остальных, как только один из них кончится не значением | Бросает `Cancelled` | Передаёт отмену детям, ждёт их и бросает |
| `ctx.each(stream, onData)` | Запускает ребёнка, который берёт события стрима по одному | Бросает `Cancelled` | Передаёт отмену ребёнку |
| `ctx.onCancel(callback)` | Вызывает колбэк, как только задача примет отмену | Бросает `Cancelled` |  |
| `ctx.onDispose(disposer)` | Убирает, когда задача кончается, при любом исходе | Работает как обычно |  |
| `ctx.onDiscard(disposer)` | Убирает, если значение никому не досталось | Работает как обычно |  |
| `ctx.disown(value)` | Снимает уборку, зарегистрированную для значения | Работает как обычно |  |
| `ctx.unattended(action)` | Запускает работу, которую задача не ждёт; её ошибки идут туда же, куда ошибки уборки | Работает как обычно | Работа не отменяется |
| `ctx.log(message)` | Передаёт сообщение наблюдателю | Работает как обычно |  |
| `ctx.job` | Задача этого контекста | Работает как обычно |  |

Последняя колонка верна там, где задача принимает отмену сразу, как та пришла.
Внутри `ctx.uncancellable` и в задаче, созданной с `cancellable: false`, задача
не принимает отмену, пока член работает, и он продолжает так, будто её не было.

## Страницы

Они же на [сайте документации](https://docs.yet-another.dev/ru/async_job/),
с поиском.

| Страница | О чём |
| --- | --- |
| [Исходы](../../docs/ru/async_job/outcomes.md) | `Done`, `Failed`, `Cancelled` и наблюдение за провалом |
| [Отмена](../../docs/ru/async_job/cancellation.md) | Контрольные точки, `onCancel`, `uncancellable`, `timeout` |
| [Дети](../../docs/ru/async_job/children.md) | `Job.deferred`, `ctx.run`, ребёнок без `await`, глубина дерева |
| [Группы](../../docs/ru/async_job/groups.md) | `.wait`, `ctx.runAll`, что группа отдаёт обратно |
| [Цепочки](../../docs/ru/async_job/chains.md) | `then`, продолжение ребёнка, шаги подряд |
| [Стримы](../../docs/ru/async_job/streams.md) | `ctx.each`, `Job.each` и что делают `await for` и `listen` в теле |
| [Уборка](../../docs/ru/async_job/cleanup.md) | `dispose`, `discard`, `onDispose`, порядок |
| [Наблюдение и тестирование](../../docs/ru/async_job/observing.md) | `JobObserver`, `JobAnswerer`, `Job.visitErrors`, логи, `unattended`, время под управлением теста |
| [Своё поверх ядра](../../docs/ru/async_job/extending.md) | `JobBase`, `JobContextBase`, свой движок |

## solo

[solo](https://pub.dev/packages/solo) добавляет состояние, очередь
и декларативные правила. Он выполняет одну корневую задачу за раз и даёт ей
исключительный доступ к состоянию. Используйте его, если нужен контроллер
с такими гарантиями. Он реэкспортирует `async_job`, поэтому достаточно
зависимости от `solo`.

Задачи работают везде, где работает Dart. Чтобы связать `solo` с виджетами,
используйте [flutter_solo](https://pub.dev/packages/flutter_solo).
