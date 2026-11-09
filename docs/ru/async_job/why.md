# Зачем задача

Что задача добавляет к обычной `Future`, флагу и `CancelableOperation`,
и развёрнутый пример, где она делает всё это сразу.

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
добавляет
[solo](https://github.com/vi-k/solo/blob/main/packages/async_job/README.ru.md#solo).
Повторы и пул задач не входят ни в один из пакетов. Срок встроен:
`Job(body, timeout: limit)` отменяет задачу, когда предел вышел, и она
кончается `Cancelled(timeout)`; см. раздел [«Срок»](time.md#срок) на странице
о времени.

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
final outcome = job.done;

// Кто-то передумал, пока база открывалась.
await Future<void>.delayed(const Duration(milliseconds: 10));
await job.cancel();

print(await outcome); // Cancelled(manual)
```

- **`ctx.join(Database.open)`** дожидается открытия и после отмены, а затем
  бросает `Cancelled` или собственную ошибку открытия, если оно упало. Ошибку,
  которая пришла после отмены, не несёт ни один исход; см.
  [«Куда уходят ошибки»](errors.md#куда-уходят-ошибки).
- **`discard: (database) => database.close()`** закрывает базу, когда задача
  кончается `Failed` или `Cancelled`; при `Done(database)` база остаётся
  открытой для вызывающего. См.
  [«`dispose` для того, что задача оставляет себе»](cleanup.md#dispose-для-того-что-задача-оставляет-себе).
- **`ctx.onCancel(stop.cancel)`** передаёт отмену собственному токену клиента
  в тот момент, когда задача её принимает. `CancelToken` принадлежит клиенту
  базы, а не этому пакету.
- **`ctx.join(() => database.migrate(stop))`** ждёт миграцию, а при отмене — её
  остановки. Клиент, который останавливается броском, при каждой отмене
  отправляет эту ошибку наблюдателю задачи, а затем к ответу, по умолчанию
  в зону, если только приложение не назвало её один раз
  в `Job.isCancellationError`; см. [«Ошибки отмены»](errors.md#ошибки-отмены).
- **`ctx.uncancellable(() async { ... })`** держит версию и её флаг готовности
  вместе: ребёнок запускается, а отмена ждёт конца шага, но задача всё равно
  кончается `Cancelled`, а `discard` закрывает базу. См.
  [«Придержать отмену»](cancellation.md#придержать-отмену).
- **`ctx.run(database.readyFlag())`** запускает ребёнком задачу, которая пишет
  флаг готовности; `readyFlag()` создаёт её через `Job.deferred`, и запуск
  остаётся за `ctx.run`. См. [«Дети»](children.md).
- **`final outcome = job.done;`** стоит сразу после того, как задача создана,
  раньше любого ожидания. Чтение `done` говорит ядру, что ошибка обработана,
  поэтому задача, упавшая во время ожидания ниже, вернёт ошибку только
  в `outcome`; прочитанный после ожидания, `done` принёс бы ошибку, которая уже
  ушла в зону. См.
  [«Сказать ядру, что она обработана»](outcomes.md#сказать-ядру-что-она-обработана).

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

Дальше — страницы: [«Исходы»](outcomes.md) о том, что отдаёт `done`,
и [«Отмена»](cancellation.md) о контрольных точках, которые этот пример
использует.
