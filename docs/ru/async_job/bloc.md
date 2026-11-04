# async_job в приложении на bloc

Обработчик bloc может выполнять свою работу задачей и оставить всё остальное
от bloc: события, трансформеры, состояния. Каждый раздел ниже берёт одно
требование приложения на bloc 9 с `bloc_concurrency`, показывает ответ одного
bloc, затем тот же обработчик с задачей внутри и говорит, что задача снимает
с кода и что остаётся на bloc. Код идёт на чистом Dart, а состояния и трассы
под ним — то, что этот код печатает.

Разделы — требования, в которых задача в обработчике оставляет коду меньше
работы:

- `close()` при `sequential()` ждёт идущий вызов —
  [«Закрытие и отмена начатой работы»](#закрытие-и-отмена-начатой-работы);
- замена загрузки не должна писать, пока идёт запись заменённой —
  [«Завершение начатой записи перед перезапуском»](#завершение-начатой-записи-перед-перезапуском);
- буфер, пришедший после того, как его обработчик заменили, всё равно надо
  освободить —
  [«Освобождение ресурса, полученного после отмены»](#освобождение-ресурса-полученного-после-отмены).

Сценарии, где менять приходится саму очередь bloc, собраны в разделе
[«Где дело в очереди»](#где-дело-в-очереди).

## Мост

Задача входит в обработчик стримом: его слушает `emit.forEach`, и отмена
подписки отменяет задачу. `watch` и есть такой стрим, разобранный в разделе
[«Стрим, который отменяет задачу»](riverpod-and-bloc.md#стрим-который-отменяет-задачу):

```dart
/// Значение [job] как стрим. Отмена подписки отменяет задачу.
///
/// Слушать его нужно сразу: значение читается в `onListen`, а стрим, который
/// никто не слушает, оставляет задачу без присмотра и её провал без
/// наблюдения.
Stream<T> watch<T>(Job<T> job) {
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      job.value
          .then(controller.add, onError: controller.addError)
          .whenComplete(controller.close);
    },
    onCancel: job.cancel,
  );
  return controller.stream;
}
```

Где этого хватает, решают две вещи в bloc. `restartable()` отменяет подписку
обработчика, который заменяет, а `close()` отменяет подписки всех идущих
обработчиков при `concurrent()`, который стоит по умолчанию, при `droppable()`
и при `restartable()`: там задача отменяется без единой вашей строки,
и `close()` возвращается сразу.

```text
concurrent: close took 0ms, the job Cancelled(manual)
droppable: close took 0ms, the job Cancelled(manual)
restartable: close took 0ms, the job Cancelled(manual)
```

При `sequential()` `close()` не отменяет ничего. Он ждёт идущий обработчик,
после него выполняет каждое событие из очереди, и каждая задача идёт до конца:

```text
sequential: close took 190ms, the jobs [Done(1), Done(2)]
```

Обработчик, который должен остановиться при `sequential()`, держит свою задачу
в поле, и `close()` отменяет её до `super.close()`. Такой обработчик ждёт
`job.done`, а не `job.value`: значение отменённой задачи бросает `Cancelled`,
и, раз поймать его некому, ошибка уходит в `onError` блока и дальше в зону.

```text
job.value under close: the zone [Cancelled(manual)]
```

`done` не бросает никогда. Он возвращает исход, и провал работы лежит в нём как
`Failed` — обработчик разбирает его сам.

## Закрытие и отмена начатой работы

Пользователь отправляет сообщение в чат и уходит с экрана до ответа. Старая
операция не должна обновлять закрытый экран или отмечать ответ прочитанным:
пользователь его не видел. API отвечает на сообщение за 50 мс; события
и состояние:

```dart
sealed class ChatEvent {
  const ChatEvent();
}

class SendMessage extends ChatEvent {
  const SendMessage(this.text);
  final String text;
}

class MarkReplyRead extends ChatEvent {
  const MarkReplyRead();
}

class ChatState {
  const ChatState([this.reply]);
  final String? reply;
  ChatState withReply(String reply) => ChatState(reply);
}
```

В трассах ниже пользователь отправляет «hi» и «bye», и экран закрывает bloc
через 10 мс: «hi» в полёте, «bye» ждёт в очереди.

### Только bloc

Последовательный обработчик проверяет закрытие после своего `await`:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;

  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      if (isClosed) return;
      emit(state.withReply(reply));
      add(const MarkReplyRead());
    }, transformer: sequential());
    on<MarkReplyRead>((e, emit) => _api.markRead(), transformer: sequential());
  }
}
```

```text
with bloc alone: close took 90ms, sent [hi, bye], reply null, reads 0
```

Проверка не пускает ответ в состояние, а отметку о прочтении — на сервер.
Закрытие всё равно ждёт вызов в полёте и затем выполняет очередь: «bye»
отправляется, пока идёт `close()`, и `close()` возвращается после его ответа,
который проверка тоже отбрасывает.

### Задача в обработчике

Вызов уходит в задачу, которая лежит в поле, и `close()` отменяет её
до `super.close()`:

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;
  Job<String>? _sending;

  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final job = _sending = Job(
        (ctx) => ctx.abandonable(() => _api.send(e.text)),
      );
      final outcome = await job.done;
      if (isClosed) return;
      switch (outcome) {
        case Done(:final value):
          emit(state.withReply(value));
          add(const MarkReplyRead());
        case Failed(:final error, :final stackTrace):
          Error.throwWithStackTrace(error, stackTrace);
        case Cancelled():
      }
    }, transformer: sequential());
    on<MarkReplyRead>((e, emit) => _api.markRead(), transformer: sequential());
  }

  @override
  Future<void> close() async {
    await _sending?.cancel();
    return super.close();
  }
}
```

```text
with a job: close took 50ms, sent [hi, bye], reply null, reads 0
```

`ctx.abandonable` заканчивает задачу сразу, как её отменили, и `close()` больше
не ждёт остаток вызова для «hi». Вызов каждого сообщения из очереди он
по-прежнему ждёт: `sequential()` запускает обработчик для «bye», пока идёт
`close()`, и его задача — не та, что лежала в поле, когда `close()` её отменял.
Провал вызова выходит из `done` как `Failed`, и обработчик бросает его снова,
поэтому он доходит до `onError` блока и до зоны так же, как провал `_api.send`
у одного bloc:

```text
with a job, the call fails: the zone [Bad state: send: offline], reply null
```

```text
with bloc alone, the call fails: the zone [Bad state: send: offline], reply null
```

Что остаётся на bloc: проверка `isClosed` после `await`, потому что сообщение
из очереди всё равно получает ответ, пока идёт `close()`, и сама очередь:
`sequential()` отправляет каждое сообщение, которое в ней ждёт.

## Завершение начатой записи перед перезапуском

Обновление прошивки записывает части через BLE одну за другой, по 20 мс каждая.
Новая загрузка должна остановить старый цикл и дождаться его текущей записи,
прежде чем отправлять свою часть: API BLE не может прервать принятую запись.
В трассах ниже у каждой загрузки четыре части, вторая начинается через 30 мс
после первой, пока пишется часть 1, а третья — через 5 мс после второй или
в тот же момент.

### Только bloc

Общая для обработчиков блокировка упорядочивает записи, а `emit.isDone`
останавливает заменённый цикл и внутри блокировки, и после записи:

```dart
class Lock {
  Future<void> _tail = Future.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final turn = Completer<void>();
    final before = _tail;
    _tail = turn.future;
    return before.then((_) => action()).whenComplete(turn.complete);
  }
}

class LockedFirmwareBloc extends Bloc<Flash, FirmwareState> {
  final Ble _ble;
  final _wire = Lock();

  LockedFirmwareBloc(this._ble) : super(const Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _wire.protect(() async {
          if (emit.isDone) return;
          await _ble.write(chunk);
        });
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

```text
uploads at 0, 30 and 35 ms: written [0, 1, 200, 201, 202, 203], 1 write at a time at most, states [1/4, 1/4, 2/4, 3/4, 4/4]
uploads at 0, 30 and 30 ms: written [0, 1, 200, 201, 202, 203], 1 write at a time at most, states [1/4, 1/4, 2/4, 3/4, 4/4]
```

Провод чистым держит проверка внутри блокировки: вторую загрузку заменяют, пока
она ждёт блокировку, и без проверки её запись началась бы, как только кончится
первая. Каждый обработчик, который пишет в устройство, обязан брать ту же
блокировку.

### Задача в обработчике

Каждая загрузка — задача, которая ждёт предыдущую, а `watch` отменяет её, когда
`restartable()` заменяет её обработчик:

```dart
class FirmwareBloc extends Bloc<Flash, FirmwareState> {
  final Ble _ble;
  Job<void>? _flashing;

  FirmwareBloc(this._ble) : super(const Idle()) {
    on<Flash>((e, emit) async {
      final previous = _flashing;
      final job = _flashing = Job<void>((ctx) async {
        if (previous != null) await ctx.join(() => previous.done);
        var written = 0;
        for (final chunk in e.chunks) {
          await ctx.join(() => _ble.write(chunk));
          emit(Flashing(++written, e.chunks.length));
        }
      });
      await emit.forEach(watch(job), onData: (_) => state);
    }, transformer: restartable());
  }
}
```

Провод и состояния — те же, что у bloc с блокировкой, строка в строку, в обеих
сериях. `ctx.join` ждёт то, что ему дали, и затем бросает `Cancelled`, если
задачу тем временем отменили: заменённая задача кончается после своей текущей
записи, до следующего `emit`, а следующая за ней до тех пор ничего не пишет,
потому что сначала ждёт `done` предыдущей.

Обработчик берёт предыдущую задачу и кладёт свою в поле сразу, до первого
`await`, поэтому следующая загрузка находит в поле эту и ждёт её. Ожидание
стоит в теле задачи, под `ctx.join`, а не в обработчике.

Прогресс задача публикует через `emit` обработчика, и так можно: обработчик
стоит в `emit.forEach`, пока его задача не кончится, а когда обработчик
заменён, задача бросает на следующем `join` и больше ничего не публикует.

Что остаётся на bloc: одно правило вместо блокировки и проверок `emit.isDone` —
поле читается и пишется до первого `await` обработчика.

## Освобождение ресурса, полученного после отмены

Аудиоредактор открывает нативный PCM-буфер для отрисовки волны, а пользователь
выбирает другой клип, пока первый ещё декодируется. Старую волну показывать
нельзя, но её буфер всё равно надо освободить. В трассах ниже клип 1
декодируется 50 мс, клип 2 — 20, и клип 2 открывается через 5 мс после клипа 1,
так что декодер отвечает сначала на второй запрос.

### Только bloc

Проверка эмиттера уходит внутрь `try`/`finally`, который владеет буфером:

```dart
class GuardedPreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  GuardedPreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final buffer = await _decoder.open(e.clip);
      try {
        if (emit.isDone) return;
        emit(Preview(buffer.waveform()));
      } finally {
        await buffer.release();
      }
    }, transformer: restartable());
  }
}
```

```text
a second clip while the first decodes: [open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1], state Preview(2)
```

```text
close while both decode: [open 1, open 2, closed, ready 2, release 2, ready 1, release 1]
```

`finally` выполняется и на пути заменённого обработчика, и только поэтому
устаревший буфер вообще освобождается. Каждый выход после получения буфера
обязан оставаться внутри `try`.

### Задача в обработчике

Освобождение объявлено на вызове, который возвращает буфер:

```dart
class PreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  PreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final job = Job<int>((ctx) async {
        final buffer = await ctx.abandonable(
          () => _decoder.open(e.clip),
          dispose: (buffer) => buffer.release(),
        );
        return buffer.waveform();
      });
      await emit.forEach(watch(job), onData: Preview.new);
    }, transformer: restartable());
  }
}
```

Трасса в обоих случаях та же, и каждый буфер освобождается один раз.
`ctx.abandonable` заканчивает отменённую задачу, не дожидаясь декодера,
и буфер, пришедший после этого, уходит в `dispose`; буфер, пришедший, пока
задача активна, освобождается, когда задача кончается. Задача возвращает волну,
а не буфер, потому что буфер к тому времени уже освобождён. Здесь `dispose`,
а не `discard`: `discard` — для ресурса, который отдают вызывающему как
результат, и буфер задачи, кончившейся `Done`, он не трогает.

Что остаётся на bloc: никакого `try`/`finally` вокруг буфера. Освобождение
объявлено там, где буфер получен, и выход, добавленный в обработчик потом, его
не потеряет.

## Где дело в очереди

Остальным сценариям из [«solo и bloc рядом»](../solo/vs-bloc.md) раздела здесь
нет: в каждом то, что приходится держать коду приложения на bloc, касается
очереди bloc, а задача внутри обработчика этого не меняет.

| Сценарий | Что остаётся на bloc |
| --- | --- |
| [Порядок обновлений общего состояния](../solo/vs-bloc.md#порядок-обновлений-общего-состояния) | одна регистрация с `sequential()` для событий, которые обновляют одно состояние: порядок — это порядок очереди |
| [Ошибка наблюдателя при обновлении состояния](../solo/vs-bloc.md#ошибка-наблюдателя-при-обновлении-состояния) | охрана внутри наблюдателя: провал — наблюдателя, а не работы |
| [Выход из состояния загрузки при отмене работы](../solo/vs-bloc.md#выход-из-состояния-загрузки-при-отмене-работы) | сброс из обработчика `CancelRefresh`: эмиттер заменённого обработчика уже закончен, что бы ни делала его задача |
| [Перезапуск одной операции в общей очереди](../solo/vs-bloc.md#перезапуск-одной-операции-в-общей-очереди) | `_newestSeek`, токен идущего `seek` и проверка после `await`: какой `seek` ещё нужен — вопрос о событиях, которые ждут в очереди |
| [Типизированные методы с выполнением через очередь](../solo/vs-bloc.md#типизированные-методы-с-выполнением-через-очередь) | функции-события и методы, которые возвращают `void`: задача создаётся в обработчике, после того как `add` вернулся |
| [Удаление выбранной ожидающей работы](../solo/vs-bloc.md#удаление-выбранной-ожидающей-работы) | поколения через `Expando`: удалять приходится события из очереди, у которых задачи ещё нет |
| [Ожидание конкретного запроса](../solo/vs-bloc.md#ожидание-конкретного-запроса) | completer на событии: `add` ничего не возвращает, а задача создаётся после него |
| [Реакция на независимое внешнее изменение состояния](../solo/vs-bloc.md#реакция-на-независимое-внешнее-изменение-состояния) | вторая регистрация и проверка после `await`; задача в поле может встать на место проверки — вместе с отменой из обработчика внешнего изменения и исходом, который надо разобрать, — и трасса остаётся той же |
