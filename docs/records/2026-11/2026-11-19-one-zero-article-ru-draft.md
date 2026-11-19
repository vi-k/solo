# Что нужно, чтобы отменить Future в Dart

> **Состояние на 2026-11-19:** русский текст статьи анонса 1.0 вынесен сюда
> по слову владельца «статью надо поправить. дай мне отдельным файлом русский
> вариант. после моей правки переведёшь на английский». Владелец правит этот
> текст; с него будет заново переведён английский текст статьи
> в `2026-11-05-one-zero-announcement-draft.md`. Ничего не опубликовано.
> **Что это:** русская статья «What cancelling a Future takes in Dart» —
> перевод из раздела «Переводы» черновиков, без правок, заголовки подняты
> на два уровня.
> **Связанные записи:** `2026-11-05-one-zero-announcement-draft.md`.

Пользователь открывает экран, экран начинает загрузку, и пользователь уходит
раньше, чем загрузка кончится. В Dart загрузка идёт дальше. `Future` — это
результат вычисления, а не само вычисление, и `cancel()` у неё нет:
[dart-lang/sdk#42855](https://github.com/dart-lang/sdk/issues/42855) просит его
с 2020 года. В bloc то же желание —
[felangel/bloc#3069](https://github.com/felangel/bloc/issues/3069), открытая
с 2021 года: кубит, закрытый во время загрузки, бросает
`Bad state: Cannot emit new states after calling close`, когда загрузка
возвращается.

Статья берёт одну небольшую загрузку, пробует отменить её средствами, которые
в Dart уже есть, и перечисляет, что для этой отмены нужно. Потом она показывает
[async_job](https://pub.dev/packages/async_job), пакет на чистом Dart, который
это делает, и то, чего он не делает.

## Загрузка

Загрузка открывает базу данных, читает три страницы и закрывает базу:

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

`Database` — заглушка: открывается за 20 мс, читает страницу за 30 мс
и печатает, что делает. Во всех примерах пользователь уходит на 35-й
миллисекунде, пока читается первая страница; `leave()` обозначает этот момент.
Трассы — то, что код печатает.

## Флаг

Первое, что под рукой, — флаг, который загрузка проверяет:

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

Это работает: загрузка дочитывает страницу, которая уже идёт, пропускает
остальные и закрывает базу. Цена — в форме кода. Каждому `await` нужна своя
проверка, и пропущенная проверка пускает загрузку дальше, а на это место ничто
не укажет. Каждому ресурсу нужен `finally`. А остановку от результата
вызывающий отличает по особому значению, здесь `null`, под которое тип
результата должен освободить место. Это соглашение, и держат его вручную
в каждой асинхронной функции.

## Future.timeout

`timeout` звучит как остановка:

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

Он останавливает ожидание, а не загрузку: вызывающий идёт дальше, а загрузка
читает все страницы впустую.

## CancelableOperation

В `package:async` есть `CancelableOperation`:

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

`cancel()` перестаёт отдавать значение, а загрузка — та же `Future`, что
и прежде: она идёт дальше. `value` отменённой операции не завершается никогда,
так что тот, кто его ещё ждёт, ждёт вечно, если только не попросит вместо него
`valueOrCancellation()`. `fromFuture` принимает колбэк `onCancel`, но то, что
он должен остановить, ему приходится доставать самому: снова флагом или
сигналом остановки самого вызова.

## Что нужно для отмены

Вместе отмена одной этой загрузки требует:

- Контрольной точки на каждом `await` и способа найти ту, которой не хватает.
- Решения о вызове, который уже идёт: дождаться его конца или уйти и дать ему
  кончиться впустую.
- Уборки, зарегистрированной там, где ресурс открывается: она выполняется,
  чем бы загрузка ни кончилась, в том числе для базы, которая откроется уже
  после отмены.
- `cancel()`, которого можно дождаться и который возвращается, когда уборка
  сделана.
- Исхода, который отличает отмену от успеха и от сбоя, чтобы типу результата
  не приходилось освобождать место под особое значение.
- Способа передать остановку вызову, который умеет останавливаться, например
  HTTP-запросу с собственным токеном отмены.

А когда работа запускает свою работу, нужны дочерние задачи: родитель, который
кончается после них, и отмена, которая до них доходит.

## Задача

`async_job` собирает всё это в `Job`. Тело задачи получает контекст, `ctx`.
Каждый вызов, которого тело ждёт через `ctx.join`, — контрольная точка,
а `dispose` регистрирует уборку рядом с открытием:

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

Отмена приходит, пока читается первая страница. `ctx.join` дожидается этого
чтения, а затем бросает `Cancelled` вместо того, чтобы отдать страницу телу,
так что вторая и третья страницы не начинаются. `dispose` закрывает базу,
и `cancel()` возвращается после этого. `job.done` даёт `Cancelled(manual)`,
и вызывающий отличает его от `Done` и `Failed`. Приди отмена во время
`Database.open`, `join` дождался бы открытия, а `dispose` закрыл бы базу,
которая открылась уже впустую.

`done` читается сразу после конструктора, до `leave()`: задача, которая падает,
пока её исход никто не держит, отдаёт ошибку в зону в тот самый момент, когда
кончается, и `await job.done`, который придёт позже, забрать её назад уже
не успеет.

### Уйти от вызова

Вызов, после которого задаче нечего убирать, ждать незачем. `ctx.abandonable`
перестаёт ждать при отмене, а вызов идёт дальше, и его результат никто
не берёт. Здесь `fetchQuote` печатает, когда запрос уходит и когда через 100 мс
приходит ответ:

```dart
final job = Job<String>((ctx) => ctx.abandonable(fetchQuote));
final outcome = job.done;

// Кто-то ушёл с экрана, пока цитата была в пути.
await Future<void>.delayed(const Duration(milliseconds: 50));

// Возвращается раньше, чем ответит fetchQuote.
await job.cancel();
print(await outcome);
```

```text
request sent
Cancelled(manual)
quote answered
```

### Передать остановку вызову

Вызов, который можно остановить, принимает собственный сигнал остановки,
а `ctx.onCancel` подаёт этот сигнал вместе с отменой. С dio:

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

Соединение закрывается, и сервер перестаёт готовить ответ, который никто
не прочтёт. Прерванный запрос всё равно бросает, при каждой отмене,
и по умолчанию ошибка уходит в зону неперехваченной. Одна строка в `main`
говорит async_job, что эта ошибка — то, как клиент останавливается, и с этого
момента она уходит наблюдателю задачи, а не в зону:

```dart
Job.isCancellationError = (error) =>
    error is DioException && error.type == DioExceptionType.cancel;
```

http 1.5 и новее делает то же через `AbortableRequest` и его `abortTrigger`;
тогда фильтр называет ещё и `RequestAbortedException` из http.

### Дочерние задачи

Тело запускает дочернюю задачу через `ctx.run`. Родитель кончается после
дочерних задач и их уборки, а отмена, которую он принял, переходит к ним.
Подробно — на странице
[«Children»](https://docs.yet-another.dev/async_job/children/).

## Чего он не делает

- **Он кооперативный.** Тело останавливается на контрольной точке. `await`
  в обход `ctx` или цикл, который ничего не ждёт, продолжают работу после
  отмены. Плагин анализатора
  [async_job_lints](https://pub.dev/packages/async_job_lints) сообщает
  об `await` в теле, который идёт не через контекст; это линт `bare_await`,
  включаемый по имени.
- **`ctx.join` дожидается вызова, который уже идёт.** Долгому вызову нужен свой
  сигнал остановки, как выше, или `ctx.abandonable`.
- **Это не управление состоянием.** Задача встаёт под провайдер riverpod или
  обработчик bloc, не меняя слоя состояния, а страница
  [«With riverpod and bloc»](https://docs.yet-another.dev/async_job/riverpod-and-bloc/)
  показывает, где каждый из них её отменяет.

`async_job` 1.0.4 лежит на [pub.dev](https://pub.dev/packages/async_job). Он
зависит только от `meta` и с 1.0 следует семантическому версионированию.
[Документация](https://docs.yet-another.dev/async_job/) рассказывает
об исходах, отмене, уборке, дочерних задачах, стримах и тестах под
`fake_async`. Для состояния с очередью поверх задач есть
[solo](https://pub.dev/packages/solo) из того же репозитория.
