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

Future<void> main() async {
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
}
```

`example/quick_start.dart` запускает этот блок с `Database`, которая печатает,
когда открывается и когда закрывается. Он печатает:

```text
database opened
database closed
Cancelled(manual)
```

`ctx.join` дождался чтения, которое уже началось, и прочитанные данные до тела
не дошли. `await job.cancel()` возвращается, когда задача кончилась вместе
с уборкой, поэтому `outcome` на следующей строке уже готов; ни то ни другое
провал не наблюдает в смысле раздела [«Четыре слова»](#четыре-слова). Тело
запускается на следующей микротаске: задача, отменённая сразу после создания,
его не выполняет и кончается `Cancelled(manual)` с `started: false`, поэтому
блок сначала ждёт.

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
[«Срок»](../../docs/ru/async_job/time.md#срок) на странице о времени.

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
  бросает `Cancelled` или собственную ошибку открытия, если оно упало. Ошибку,
  которая пришла после отмены, не несёт ни один исход; см.
  [«Куда уходят ошибки»](../../docs/ru/async_job/errors.md#куда-уходят-ошибки).
- **`discard: (database) => database.close()`** закрывает базу, когда задача
  кончается `Failed` или `Cancelled`; при `Done(database)` база остаётся
  открытой для вызывающего. См.
  [«`dispose` для того, что задача оставляет себе»](../../docs/ru/async_job/cleanup.md#dispose-для-того-что-задача-оставляет-себе).
- **`ctx.onCancel(stop.cancel)`** передаёт отмену собственному токену клиента
  в тот момент, когда задача её принимает. `CancelToken` принадлежит клиенту
  базы, а не этому пакету.
- **`ctx.join(() => database.migrate(stop))`** ждёт миграцию, а при отмене — её
  остановки. Клиент, который останавливается броском, при каждой отмене
  отправляет эту ошибку наблюдателю задачи, а затем к ответу, по умолчанию
  в зону, если только приложение не назвало её один раз
  в `Job.isCancellationError`; см.
  [«Ошибки отмены»](../../docs/ru/async_job/errors.md#ошибки-отмены).
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
| `ctx.check()` | Голая контрольная точка | Бросает `Cancelled` |  |
| `ctx.join(action)` | Ждёт действие целиком | Бросает `Cancelled` | Ждёт, потом бросает |
| `ctx.abandonable(action)` | Ждёт, пока жива задача | Бросает `Cancelled` | Бросает сразу |
| `ctx.uncancellable(action)` | Придерживает отмену | Бросает `Cancelled` | Держит её до конца шага |
| `ctx.pause(duration)` | Даёт пройти времени | Бросает `Cancelled` | Прерывается и бросает |
| `ctx.run(child)` | Запускает ребёнка и ждёт | Бросает `Cancelled` | Передаёт её, ждёт, бросает |
| `ctx.start(child)` | Запускает ребёнка, не ждёт | Бросает `Cancelled` | Передаёт её |
| `ctx.runAll(children)` | Запускает детей бок о бок | Бросает `Cancelled` | Передаёт её, ждёт, бросает |
| `ctx.each(stream, onData)` | Следует за стримом в ребёнке | Бросает `Cancelled` | Передаёт её |
| `ctx.onCancel(callback)` | Зовёт колбэк при отмене | Бросает `Cancelled` |  |
| `ctx.onDispose(disposer)` | Убирает в конце | Работает как обычно |  |
| `ctx.onDiscard(disposer)` | Убирает, если не `Done` | Работает как обычно |  |
| `ctx.disown(value)` | Снимает уборку значения | Работает как обычно |  |
| `ctx.unattended(action)` | Запускает работу, которую никто не ждёт | Работает как обычно | Не отменяется |
| `ctx.log(message)` | Передаёт сообщение наблюдателю | Работает как обычно |  |
| `ctx.job` | Задача этого контекста | Работает как обычно |  |
| `ctx.heldCancellation` | Придержанная отмена или `null` | Работает как обычно |  |

Чего в ячейках нет:

- `ctx.check()` — контрольная точка для места, где нечего обернуть.
- `ctx.abandonable` перестаёт ждать, когда задачу отменяют, а действие идёт
  дальше. `ctx.uncancellable` держит отмену до конца шага, а бросает её
  следующая контрольная точка.
- `ctx.run`, `ctx.start` и `ctx.runAll` принимают `ChildJob`, например
  созданную через `Job.deferred`, и передают отмену своим детям. `ctx.start`
  оставляет исход своего ребёнка тому, у кого ребёнок в руках. `ctx.runAll`
  останавливает остальных, как только один ребёнок кончится не значением.
- `ctx.each` отдаёт события стрима колбэку по одному.

- `ctx.onCancel` вызывает колбэк, как только задача примет отмену.
  `ctx.onDispose` убирает при любом исходе. `ctx.onDiscard` убирает, если
  задача кончилась не `Done`, а тело, которое кончилось `Done`, не вернув
  значение, убирает его само.
- Ошибки работы `ctx.unattended` идут в `onError`, затем к ответу.
- Замыкание, переданное в `ctx.log`, вызывает наблюдатель, который строит
  строку.
- `ctx.heldCancellation` — отмена, которую придерживает открытая секция
  `uncancellable`.

Последняя колонка верна там, где задача принимает отмену сразу, как та пришла.
Внутри `ctx.uncancellable` и в задаче, созданной с `cancellable: false`, задача
не принимает отмену, пока член работает, и он продолжает так, будто её не было.

## Четыре слова

Модель ошибок и отмены держат четыре слова, и смысл у каждого уже, чем
в обычной речи:

| Слово | Что значит | Страница |
| --- | --- | --- |
| Наблюдать провал | Читать `done` или `value`, передать провал дальше через `then` или вызвать `ignoreFailure()` не позже микрозадачи после конца задачи; чтение `outcome` и наблюдатель у задачи не в счёт. | [Исходы](../../docs/ru/async_job/outcomes.md#ошибка-которую-никто-не-ждёт) |
| Ответить за ошибку | Что происходит с провалом, который никто не наблюдает, и с ошибкой, которой не несёт ни один исход: её берёт `onUnanswered` наблюдателя, который подмешивает `JobAnswerer`, а без такого наблюдателя — зона. | [Ошибки](../../docs/ru/async_job/errors.md#ответ-за-ошибки) |
| Зона | Зона, где задача создана; ошибка, которая до неё дошла, там неперехваченная. | [Ошибки](../../docs/ru/async_job/errors.md) |
| Принять отмену | Задача становится отменённой: отмена передаётся её детям, вызываются её колбэки `onCancel`, и задача кончится `Cancelled`, что бы тело ни делало дальше. | [Отмена](../../docs/ru/async_job/cancellation.md) |

## Страницы

Они же на [сайте документации](https://docs.yet-another.dev/ru/async_job/),
с поиском.

| Страница | О чём |
| --- | --- |
| [Исходы](../../docs/ru/async_job/outcomes.md) | `Done`, `Failed`, `Cancelled` и наблюдение за провалом |
| [Отмена](../../docs/ru/async_job/cancellation.md) | Контрольные точки, `onCancel`, `uncancellable` |
| [Время](../../docs/ru/async_job/time.md) | `ctx.pause`, срок через `timeout` |
| [Дети](../../docs/ru/async_job/children.md) | `Job.deferred`, `ctx.run`, `ctx.start` для ребёнка без `await`, глубина дерева |
| [Группы](../../docs/ru/async_job/groups.md) | `.wait`, `ctx.runAll`, что группа отдаёт обратно |
| [Цепочки](../../docs/ru/async_job/chains.md) | `then`, продолжение ребёнка, шаги подряд |
| [Стримы](../../docs/ru/async_job/streams.md) | `ctx.each`, `Job.each` и что делают `await for` и `listen` в теле |
| [Уборка](../../docs/ru/async_job/cleanup.md) | `dispose`, `discard`, `ctx.disown` для значения, которое задача не отдаёт |
| [Правила уборки](../../docs/ru/async_job/cleanup-rules.md) | Ресурс, переданный другой задаче, `onDispose` и снятие, порядок и поздние результаты |
| [Наблюдение](../../docs/ru/async_job/observing.md) | `JobObserver`, имя задачи, логи |
| [Ошибки](../../docs/ru/async_job/errors.md) | Куда идёт ошибка, `JobAnswerer`, `Job.isCancellationError`, `unattended`, `JobObserver.all` |
| [Правила ошибок](../../docs/ru/async_job/error-rules.md) | Путь ошибки каждого вида, `Job.debug`, `Job.visitErrors`, редкие случаи |
| [Тестирование](../../docs/ru/async_job/testing.md) | Задача под `fakeAsync` и что двигает её время |
| [Своё поверх ядра](../../docs/ru/async_job/extending.md) | `JobBase`, `JobContextBase`, своя задача, `Job.deferred`, `finish` |
| [Свой движок](../../docs/ru/async_job/engine.md) | Очередь, которая отказывает в `cancelWith`, правило в `check()` |

## solo

[solo](https://pub.dev/packages/solo) добавляет состояние, очередь
и декларативные правила. Он выполняет одну корневую задачу за раз и даёт ей
исключительный доступ к состоянию. Используйте его, если нужен контроллер
с такими гарантиями. Он реэкспортирует `async_job`, поэтому достаточно
зависимости от `solo`.

Задачи работают везде, где работает Dart. Чтобы связать `solo` с виджетами,
используйте [flutter_solo](https://pub.dev/packages/flutter_solo).
