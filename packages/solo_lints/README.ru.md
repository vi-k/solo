# solo_lints

`solo_lints` — плагин анализатора для кода
на [async_job](https://pub.dev/packages/async_job)
и [solo](https://pub.dev/packages/solo). Он сообщает об ошибках, которые
компилируются, работают и часто проходят первый тест: ожидание в уборке,
которое так и не случается; ресурс, потерянный при отмене; `catch`, который
сбрасывает исправное устройство; задача, которая ждёт саму себя. За каждым
правилом стоит раздел
[«Частых ошибок»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md) —
страницы solo, где каждая ошибка показана рядом с правильным способом.

## Установка

Назовите плагин в `analysis_options.yaml` в корне пакета или рабочего
пространства:

```yaml
plugins:
  solo_lints: ^0.1.0
```

Плагин сервер анализа скачивает сам, поэтому в `pubspec.yaml` он
не зависимость. Плагинам нужен Dart 3.10 или новее. Его диагностики показывают
`dart analyze`, `flutter analyze` и редактор. Правку раздела `plugins` редактор
видит после перезапуска своего сервера анализа.

Предупреждения включаются, как только плагин назван. Линт `catch_without_check`
включается по имени:

```yaml
plugins:
  solo_lints:
    version: ^0.1.0
    diagnostics:
      catch_without_check: true
```

Диагностику глушат именем плагина перед именем правила:
`// ignore: solo_lints/ctx_in_cleanup` строкой выше или
`// ignore_for_file: solo_lints/ctx_in_cleanup` на весь файл.

## Правила

| Правило | Вид | Сообщает |
| --- | --- | --- |
| `ctx_in_cleanup` | предупреждение | член контекста, который ждёт, вызван в уборке |
| `release_on_the_call` | предупреждение | освобождение зарегистрировано строкой ниже вызова, который приносит ресурс |
| `catch_without_check` | линт | широкий `catch` в теле, которое действует, не спросив задачу |
| `sync_fake_async` | предупреждение | `async`-колбэк `fakeAsync` |
| `await_own_queue` | предупреждение | задача ждёт задачу из очереди своего же контроллера |

### ctx_in_cleanup

```dart
ctx.onDispose(() async {
  await ctx.join(() => device.flush()); // ctx_in_cleanup
});
```

Уборка идёт после тела, где `join` бросает `StateError`, поэтому буфер остаётся
несброшенным, чем бы задача ни кончилась. Ждите там простым `await`. Правило
смотрит в функции, переданные в `ctx.onDispose` и `ctx.onDiscard`
и в `dispose:` и `discard:` методов `join`, `abandonable`, `wait` и `run`, —
литералы, а также локальные функции и `final`-переменные с литералом,
переданные по имени, — и сообщает о членах, которые там бросают: о контрольных
точках, `onCancel`, `start` и `each`. `onDispose`, `onDiscard`, `disown`, `log`
и `unattended` оно не трогает. Подробнее в разделе
[«Каждое ожидание на своём месте»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#каждое-ожидание-на-своём-месте).

### release_on_the_call

```dart
final db = await ctx.join(Database.open);
ctx.onDispose(db.close); // release_on_the_call
```

Отмена во время открытия бросает раньше второй строки, и открытая база
теряется. Передайте освобождение вызову, который приносит ресурс:
`ctx.join(Database.open, dispose: (db) => db.close())`. Правило берёт `join`,
`abandonable`, `wait` и `run` без своего освобождения, за которыми сразу идёт
`onDispose` или `onDiscard`, упоминающий переменную. Подробнее в разделе
[«Освобождение на вызове»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#освобождение-на-вызове).

### catch_without_check

```dart
try {
  await ctx.join(hw.open);
  await ctx.join(() => hw.setZoom(zoom));
} on Object catch (error) { // catch_without_check
  await hw.reset();
  ctx.emit(Broken(error));
  rethrow;
}
```

`Cancelled` реализует `Exception`, поэтому `catch` без `on` или с `on`
на `Object`, `Exception` или `Outcome` ловит его вместе с ошибками, ради
которых его писали, и отменённая задача сбрасывает камеру, которую никто
не ломал. Сделайте `ctx.check()` первой строкой `catch`. Правило смотрит в тело
задачи, в объявленные в нём локальные функции и в действия, которых тело ждёт
через `join`, `abandonable`, `wait` и `uncancellable`; уборку и работу без
присмотра оно не трогает. Правило молчит, когда блок `try` ничего не ждёт
и не доходит до контрольной точки, а также когда `catch` начинается
с контрольной точки после любых строк `if (...) rethrow;`, начинается
с `if (ctx.job.isCancelled) rethrow;` или кончается `rethrow;`, ничего
не ожидая и не задевая контрольных точек по пути, — так поступают синхронное
освобождение и запись в лог. Это линт, а не предупреждение: о `catch`, которому
и при отмене нужно дождаться освобождения, правило тоже сообщает. Там
`ctx.check()` первой строкой оставил бы ресурс неосвобождённым, и такой `catch`
сохраняет свои строки под `// ignore:`. Подробнее в разделе
[«Пропустить отмену через catch»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#пропустить-отмену-через-catch).

### sync_fake_async

```dart
await fakeAsync((async) async { // sync_fake_async
  final outcome = await profile.load().done;
  expect(outcome, isA<Done<String>>());
});
```

`await` в колбэке приостанавливает его, и двигать поддельные часы больше
некому: тест висит или кончается зелёным, ничего не выполнив. Оставьте колбэк
синхронным, двигайте часы через `elapse` и читайте `job.outcome`. Правило
сообщает об `async` колбэка, переданного в `fakeAsync` или `FakeAsync.run`.
Подробнее в разделе
[«Двигать часы в fakeAsync»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#двигать-часы-в-fakeasync).

### await_own_queue

```dart
Job<void> syncAndRecord(int item) =>
    enqueue<Ready, void>(key: _Op.syncAndRecord, (ctx) async {
      final path = await sync(item).value; // await_own_queue
      await recordPath(path).value; // await_own_queue
    });
```

`sync(item)` ставит задачу в очередь за той, что её ждёт, и ничего не движется,
пока `close()` не отменит обе. Выполняйте задачу через `ctx.run(_sync(item))`.
Правило берёт метод того же контроллера, который приносит `SoloJob` —
по объявленному типу или, если метод объявлен в том же файле, по тому, что он
возвращает, — а также `close()` и `cancelAll()`. Оно смотрит в тело задачи
с `SoloContext`, поставленной в очередь этого контроллера, включая то, что тело
возвращает, в действия, которых это тело ждёт через `join`, `abandonable`,
`wait` и `uncancellable`, и в его уборку: её очередь тоже ждёт. Контроллер —
и `mixin` с `on Solo`. Подробнее в разделе
[«Шаги детьми»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#шаги-детьми).

## Версии

Плагин работает на Dart 3.10 и новее, с `analyzer` от 12.1 до 14. SDK Dart,
которому нужен `analyzer` 15, эту версию не загружает, и её правила молчат,
пока выпуск не поднимет границу.

Типы async_job и solo правила узнают по именам и библиотекам, откуда те пришли,
и ни от одного из пакетов не зависят. На версии этих пакетов, где имя
сменилось, правило молчит, а не сообщает о правильном коде.
