# solo под bloc

Bloc может отдать свою работу контроллеру `solo` и оставить себе всё остальное
от bloc: события, трансформеры, состояние, которое читает экран. Каждый раздел
ниже берёт одно требование приложения на bloc 9.2.1 с `bloc_concurrency`,
показывает ответ одного bloc, затем тот же bloc с контроллером под ним
и говорит, что контроллер снимает с кода и что остаётся на bloc. Контроллеры —
из разделов Solo страницы [«solo и bloc рядом»](vs-bloc.md), где каждый из них
стоит без bloc. Код идёт на чистом Dart, а состояния и трассы под ним — то, что
этот код печатает.

Разделы берут шесть требований, в которых контроллер под bloc оставляет коду
меньше работы. У одного bloc событиям, которые обновляют одно состояние, нужна
одна регистрация с `sequential()`, `close()` при `sequential()` ждёт идущий
вызов и отправляет каждое сообщение из очереди, а перетаскивание, которое
вернулось к позиции, перематывает на неё дважды. Чтение батареи ушедшего экрана
доходит до устройства, а чтение за отключением падает; отзыв сессии требует
своего события и проверки состояния по обе стороны от `await`; а загрузки
прошивки берут общую для обработчиков блокировку, чтобы замена не писала, пока
идёт запись, которую она заменяет. Сценарии, где ответ остаётся за bloc,
собраны в разделе [«Где ответ остаётся за bloc»](#где-ответ-остаётся-за-bloc).

## Мосты

Контроллеру под bloc нужны два моста: его задачи — в обработчики bloc, его
состояния — в состояние bloc. Состояния приходят через `stream`
от `SoloStream`. Здесь счётчик делает шаг каждые 10 мс:

```dart
final class Counter extends Solo<int> with SoloStream<int> {
  Counter() : super(0);

  Job<void> countTo(int target) => enqueue<int, void>((ctx) async {
    while (ctx.state < target) {
      await ctx.pause(const Duration(milliseconds: 10));
      ctx.emit(ctx.state + 1);
    }
  });

  Job<void> reset() => enqueue<int, void>((ctx) async => ctx.emit(0));
}
```

Мосты держат две функции приложения, и ими пользуется каждый bloc этой
страницы, под которым стоит контроллер. `follow` публикует состояния
контроллера в bloc, начиная с того, которое у контроллера сейчас, а `settle`
ждёт задачу и бросает её провал заново:

```dart
/// Публикует состояния [controller] через [emit], начиная с того, которое
/// у контроллера сейчас; [state] — состояние bloc.
Future<void> follow<S extends Object>(
  Emitter<S> emit,
  S state,
  SoloStream<S> controller,
) {
  final following = emit.forEach(controller.stream, onData: (next) => next);
  if (controller.currentState != state) emit(controller.currentState);
  return following;
}

/// Ждёт [job] и бросает её провал заново.
Future<void> settle(Job<Object?> job) async {
  if (await job.done case Failed(:final error, :final stackTrace)) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}
```

Bloc публикует состояния из обработчика собственного события, которое добавляет
конструктор и которое работает, пока bloc жив:

```dart
sealed class CounterEvent {
  const CounterEvent();
}

final class CountTo extends CounterEvent {
  const CountTo(this.target);
  final int target;
}

final class Reset extends CounterEvent {
  const Reset();
}

final class _Started extends CounterEvent {
  const _Started();
}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc(this._counter) : super(_counter.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _counter));
    on<CountTo>((e, emit) => settle(_counter.countTo(e.target)));
    on<Reset>((e, emit) => settle(_counter.reset()));
    add(const _Started());
  }

  final Counter _counter;

  @override
  Future<void> close() async {
    await _counter.close();
    return super.close();
  }
}
```

`Counter` подмешивает `SoloStream` там, где объявлен. Разделы ниже берут
контроллеры страницы «рядом», объявленные без примеси, и добавляют её в своём
классе, например
`final class StreamedNotes = NotesController with SoloStream<NotesState>;`. Эти
контроллеры — финальные классы, поэтому такой класс собирается только
в библиотеке контроллера. `_Started` расширяет запечатанное семейство событий,
как `CounterEvent`, и объявляется в библиотеке семейства.

Обработчики `CountTo` и `Reset` ждут задачи контроллера через `settle`.
`job.done` никогда не бросает: он возвращает исход и помечает задачу
наблюдённой, поэтому обработчик, который только ждёт его, теряет провал задачи,
и о нём не узнают ни `onError` bloc, ни зона. `settle` бросает исход `Failed`
заново, и ошибка идёт путём любой ошибки обработчика — в `onError` bloc
и дальше в зону. Задача, которую отменил закрывающийся контроллер, кончается
`Cancelled`, и `settle` даёт обработчику закончиться тихо, тогда как
`job.value` бросил бы `Cancelled`.

Bloc считает до 2, дважды сбрасывается и считает до 3, а экран закрывает его
через 35 мс, после первого шага последнего счёта:

```text
controller [1, 2, 0, 0, 1]
bloc       [1, 2, 0, 1]
close took 0ms, bloc.state 1, counter.isClosed true, bloc.isClosed true
```

Bloc публикует каждое состояние контроллера, кроме второго `0`: bloc, который
уже сделал `emit`, отбрасывает состояние, равное своему, а `SoloStream` его
публикует. `follow` сначала подписывается, а затем сравнивает состояния,
поэтому bloc начинает с состояния, которое у контроллера на момент подписки,
даже если контроллер сменил его после того, как конструктор bloc прочёл
`currentState`. `close()` bloc закрывает контроллер, и контроллер отменяет счёт
на `ctx.pause`. Закрытый контроллер закрывает свой стрим, и вместе с ним
заканчивается `emit.forEach`. Bloc этой страницы закрывают контроллер первым;
где порядок важен, разобрано в разделе
[«Закрытие и отмена начатой работы»](#закрытие-и-отмена-начатой-работы).

`_counter.stream.listen(emit)` в конструкторе было бы короче, но `emit`
у bloc — для самого bloc и тестов, и анализатор сообщает о таком вызове как
о `invalid_use_of_visible_for_testing_member`.

## Порядок обновлений общего состояния

Пользователь отправляет заметку и обновляет список. Обновление, которое
началось до конца отправки, читает старый список, и его публикация после
отправки удаляет новую заметку. Отправка идёт 40 мс, список читается в начале
вызова и возвращается через 60 мс, а экран добавляет отправку и обновление одно
за другим. События и состояние — из раздела
[«Порядок обновлений общего состояния»](vs-bloc.md#порядок-обновлений-общего-состояния).

### Только bloc

Оба события идут через одну регистрацию с `sequential()`:

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  NotesBloc(this._api) : super(const NotesState()) {
    on<NotesEvent>((e, emit) async {
      switch (e) {
        case UploadNote(:final note):
          emit(state.copyWith(uploading: true));
          await _api.upload(note);
          emit(state.copyWith(notes: [...state.notes, note], uploading: false));
        case RefreshList():
          final serverNotes = await _api.list();
          emit(state.copyWith(notes: serverNotes));
      }
    }, transformer: sequential());
  }
}
```

```text
with bloc alone: the list read [n0, n1], NotesState([n0, n1], uploading: false)
```

Очередь bloc запускает обновление, когда отправка закончилась, и список
читается после того, как сервер принял заметку. Порядок держит регистрация:
события, которые обновляют одно состояние, делят её под `sequential()`.
Со своей регистрацией у каждого события обновление идёт параллельно
с отправкой, как показывает первая попытка того же раздела
[«solo и bloc рядом»](vs-bloc.md#порядок-обновлений-общего-состояния).

### Контроллер под bloc

Вызовы уходят контроллеру того раздела:

```dart
final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

  Job<void> upload(Note note) => enqueue<NotesState, void>(key: 'upload', (
    ctx,
  ) async {
    ctx.emit(ctx.state.copyWith(uploading: true));
    await ctx.join(() => _api.upload(note));
    ctx.emit(
      ctx.state.copyWith(notes: [...ctx.state.notes, note], uploading: false),
    );
  });

  Job<void> refresh() => enqueue<NotesState, void>(key: 'refresh', (ctx) async {
    final serverNotes = await ctx.abandonable(_api.list);
    ctx.emit(ctx.state.copyWith(notes: serverNotes));
  });
}
```

Bloc берёт мосты из раздела [«Мосты»](#мосты), и каждое событие сохраняет
регистрацию, которую bloc даёт по умолчанию:

```dart
final class StreamedNotes = NotesController with SoloStream<NotesState>;

final class _Started extends NotesEvent {}

class NotesBloc extends Bloc<NotesEvent, NotesState> {
  NotesBloc(this._notes) : super(_notes.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _notes));
    on<UploadNote>((e, emit) => settle(_notes.upload(e.note)));
    on<RefreshList>((e, emit) => settle(_notes.refresh()));
    add(_Started());
  }

  final StreamedNotes _notes;

  @override
  Future<void> close() async {
    await _notes.close();
    return super.close();
  }
}
```

```text
with a controller: the list read [n0, n1], NotesState([n0, n1], uploading: false)
```

Два обработчика идут одновременно, а порядок держится: каждый отдаёт команду
контроллеру, когда приходит его событие, и очередь контроллера запускает
обновление, когда отправка закончилась.

Что остаётся на bloc: никакого правила о регистрациях. Регистрация на каждое
событие, код, к которому ведёт bloc, верна как есть: порядок — это порядок
очереди контроллера.

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

Проверка не пускает ответ в состояние, а прочтение — на сервер. Закрытие всё
равно ждёт идущий вызов и затем прогоняет очередь: «bye» отправляется, пока
идёт `close()`, и `close()` возвращается после его ответа, который проверка
тоже отбрасывает.

### Контроллер под bloc

Вызовы уходят контроллеру раздела
[«Закрытие и отмена начатой работы»](vs-bloc.md#закрытие-и-отмена-начатой-работы),
и ответ и прочтение — его задачи:

```dart
final class ChatController extends Solo<ChatState> {
  final Api _api;

  ChatController(this._api) : super(const ChatState());

  Job<void> send(String text) =>
      enqueue<ChatState, void>(key: 'send', (ctx) async {
        final reply = await ctx.abandonable(() => _api.send(text));
        ctx.emit(ctx.state.withReply(reply));
        markReplyRead();
      });

  Job<void> markReplyRead() =>
      enqueue<ChatState, void>((ctx) => ctx.abandonable(_api.markRead));
}
```

Bloc сохраняет свои события и свой `sequential()`, берёт стрим у контроллера
с `SoloStream` и закрывает контроллер раньше себя:

```dart
final class StreamedChat = ChatController with SoloStream<ChatState>;

final class _Started extends ChatEvent {
  const _Started();
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._chat) : super(_chat.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _chat));
    on<SendMessage>(
      (e, emit) => settle(_chat.send(e.text)),
      transformer: sequential(),
    );
    add(const _Started());
  }

  final StreamedChat _chat;

  @override
  Future<void> close() async {
    await _chat.close();
    return super.close();
  }
}
```

```text
with a controller: close took 0ms, sent [hi], reply null, reads 0
```

Закрытие контроллера отменяет «hi» на `ctx.abandonable`, до ответа и прочтения.
`sequential()` всё равно запускает обработчик для «bye», и закрытый контроллер
заканчивает его задачу `Cancelled(closed)` без вызова. Затем `super.close()`
не находит, чего ждать.

Держит это порядок. Если `super.close()` идёт первым, `sequential()` прогоняет
свою очередь через контроллер, который ещё открыт, и требование теряется
дважды: оба сообщения уходят в API, а оба ответа доходят до состояния
закрывающегося bloc и отмечаются прочитанными.

```text
with super.close() first: close took 100ms, sent [hi, bye], reply reply to bye, reads 2
```

Что остаётся на bloc: порядок в `close()` — сначала контроллер, затем
`super.close()`, — пока у регистрации остаётся `sequential()`. С регистрацией,
которую bloc даёт по умолчанию, как в других разделах, порядок сообщений держит
очередь контроллера, и при обоих порядках `close()` уходит одно «hi».
Обработчик не проверяет `isClosed`: ответ и прочтение — задачи контроллера,
а закрытый контроллер не выполняет ни то, ни другое.

## Перезапуск одной операции в общей очереди

Плеер выполняет `play`, `pause` и `seek` по одной операции. Пока ползунок
перетаскивают, ожидающие перемотки устаревают, а идущая перемотка должна
остановиться до начала следующей; `play` и `pause` сохраняют свой порядок.
`play` и `pause` идут по 30 мс, перемотка — три шага по 10 мс, и между шагами
она смотрит на свой токен. События и состояния — из раздела
[«Перезапуск одной операции в общей очереди»](vs-bloc.md#перезапуск-одной-операции-в-общей-очереди).

### Только bloc

Одна регистрация с `sequential()` держит порядок, а `onEvent` записывает самую
новую перемотку и останавливает идущую:

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;
  Duration? _newestSeek;
  CancelToken? _seeking;

  PlayerBloc(this._player) : super(const PlayerState()) {
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          if (position != _newestSeek) return;
          final token = CancelToken();
          _seeking = token;
          await _player.seek(position, cancelToken: token);
          _seeking = null;
          if (token.cancelled) return;
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(PlayerCommand event) {
    super.onEvent(event);
    if (event is Seek) {
      _newestSeek = event.position;
      _seeking?.cancel();
    }
  }
}
```

В трассах перетаскивание проходит 1, 2 и 3 между play и pause, другое
возвращается к 1, а перемотка на 3 приходит через 15 мс после перемотки на 1:

```text
with bloc alone, seeks 1, 2, 3: [play, seek 3, pause]
with bloc alone, seeks 1, 2, 1: [play, seek 1, seek 1, pause]
with bloc alone, seek 3 15 ms after seek 1: [seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]
```

Перемотка, которая не самая новая, возвращается, а самая новая — это позиция,
которую сравнивают по значению. Перетаскивание, вернувшееся к 1, не отбрасывает
свою первую перемотку на 1, и плеер перематывает на 1 дважды.

### Контроллер под bloc

Вызовы уходят контроллеру того раздела, у которого `stream` уже есть:

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> with SoloStream {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  Job<void> play() => enqueue<Ready, void>(key: PlayerKey.play, (ctx) async {
    await ctx.join(_player.play);
    ctx.emit(ctx.state.copyWith(playing: true));
  });

  Job<void> pause() => enqueue<Ready, void>(key: PlayerKey.pause, (ctx) async {
    await ctx.join(_player.pause);
    ctx.emit(ctx.state.copyWith(playing: false));
  });

  Job<void> seek(Duration position) => enqueue<Ready, void>(
    key: PlayerKey.seek,
    policy: Policy.restart,
    (ctx) async {
      final token = CancelToken();
      ctx.onCancel(token.cancel);
      await ctx.join(() => _player.seek(position, cancelToken: token));
      ctx.emit(ctx.state.copyWith(position: position));
    },
  );
}
```

Каждая команда получает регистрацию, которую bloc даёт по умолчанию:

```dart
final class _Started extends PlayerCommand {}

class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  PlayerBloc(this._player) : super(_player.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _player));
    on<Play>((e, emit) => settle(_player.play()));
    on<Pause>((e, emit) => settle(_player.pause()));
    on<Seek>((e, emit) => settle(_player.seek(e.position)));
    add(_Started());
  }

  final PlayerController _player;

  @override
  Future<void> close() async {
    await _player.close();
    return super.close();
  }
}
```

```text
with a controller, seeks 1, 2, 3: [play, seek 3, pause]
with a controller, seeks 1, 2, 1: [play, seek 1, pause]
with a controller, seek 3 15 ms after seek 1: [seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]
```

`Policy.restart` заменяет ожидающую перемотку и отменяет идущую,
а `ctx.onCancel` передаёт отмену токену. Заменяется задача, а не позиция:
перетаскивание, вернувшееся к 1, перематывает на 1 один раз.

Что остаётся на bloc: регистрация на каждую команду, кроме мостов, и больше
ничего. Ни `_newestSeek`, ни поля для токена, ни проверки после `await`,
ни `onEvent`.

## Удаление выбранной ожидающей работы

Экран устройства ставит в очередь подключение, чтение батареи, переименование
и отключение. Когда экран закрывается, ожидающее чтение нужно отбросить,
а переименование должно завершиться до отключения. Подключение идёт 30 мс,
любой другой вызов — 10, и устройство отказывает в чтении батареи
и переименовании, пока не подключено. События и состояния — из раздела
[«Удаление выбранной ожидающей работы»](vs-bloc.md#удаление-выбранной-ожидающей-работы);
у `ReadBattery` константный конструктор, поэтому два экрана могут добавить один
и тот же экземпляр.

### Только bloc

`onEvent` помечает каждое событие экраном, для которого его добавили, и чтение
ушедшего экрана возвращается:

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  final _stampOf = Expando<int>();
  int _screen = 0;

  DeviceBloc(this._ble) : super(const DeviceState()) {
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          if (_stampOf[e] != _screen) return;
          emit(state.copyWith(battery: await _ble.battery()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(DeviceEvent event) {
    super.onEvent(event);
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
  }
}
```

В трассах экран сразу уходит (`Connect`, `ReadBattery`, `Rename`,
`Disconnect`); затем экран, открытый снова, добавляет после них `Connect`
и тот же константный `ReadBattery`; а таймер добавляет чтение за отключением
(`Connect`, `Disconnect`, `ReadBattery`):

```text
with bloc alone, leaving: [connect, rename kitchen, disconnect]
with bloc alone, a shared const read: [connect, battery, rename kitchen, disconnect, connect, battery]
with bloc alone, a read after disconnect: [connect, disconnect], the zone [Bad state: battery: not connected]
```

Ушедший экран теряет своё чтение. Два экрана, которые добавили один константный
экземпляр, делят его метку: второй экран перезаписывает метку первого, и чтение
ушедшего экрана доходит до устройства. Чтение, добавленное после отключения,
несёт новую метку, доходит до устройства, которого уже нет, и его ошибка уходит
в зону.

### Первая попытка

Вызовы уходят контроллеру того раздела, чей `disconnect` снимает чтения, ещё
стоящие в его очереди. Bloc сохраняет одну регистрацию с `sequential()`,
которая держала порядок команд:

```dart
// Первая попытка: каждая команда ждёт в очереди bloc, и отключение
// не находит в очереди контроллера чтения, которое можно снять.
class SequentialDeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  SequentialDeviceBloc(this._device) : super(_device.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _device));
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await settle(_device.connect());
        case ReadBattery():
          await settle(_device.readBattery());
        case Rename(:final name):
          await settle(_device.rename(name));
        case Disconnect():
          await settle(_device.disconnect());
        case _Started():
      }
    }, transformer: sequential());
    add(const _Started());
  }

  final StreamedDevice _device;

  @override
  Future<void> close() async {
    await _device.close();
    return super.close();
  }
}
```

`StreamedDevice` и `_Started` объявлены вместе с ответом ниже, как в разделе
[«Мосты»](#мосты). Регистрация для `DeviceEvent` получает и `_Started`, и её
`switch` принимает его пустой веткой.

```text
one sequential registration, leaving: [connect, battery, rename kitchen, disconnect]
one sequential registration, a shared const read: [connect, battery, rename kitchen, disconnect, connect, battery]
one sequential registration, a read after disconnect: [connect, disconnect], the zone []
```

`sequential()` держит каждую команду, пока не закончится предыдущая, поэтому
в очереди контроллера никогда не бывает больше одной задачи: когда приходит
отключение, чтение уже выполнено. Чтению за отключением отказано всё равно:
`readBattery` выполняется только в `Connected`, а правило проверяется при
старте задачи.

### Контроллер под bloc

Контроллер того раздела:

```dart
enum DeviceKey { connect, readBattery, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  Job<void> connect() => enqueue<Offline, void>(
    key: DeviceKey.connect,
    cancellable: false,
    (ctx) async {
      await ctx.join(_ble.connect);
      ctx.emit(const Connected());
    },
  );

  Job<void> readBattery() =>
      enqueue<Connected, void>(key: DeviceKey.readBattery, (ctx) async {
        final battery = await ctx.join(_ble.battery);
        ctx.emit(ctx.state.copyWith(battery: battery));
      });

  Job<void> rename(String name) => enqueue<Connected, void>(
    key: DeviceKey.rename,
    cancellable: false,
    (ctx) => ctx.join(() => _ble.rename(name)),
  );

  Job<void> disconnect() {
    queue.removeWhere((job) => job.key == DeviceKey.readBattery);
    return enqueue<Connected, void>(
      key: DeviceKey.disconnect,
      cancellable: false,
      (ctx) async {
        await ctx.join(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

Каждая команда получает свою регистрацию:

```dart
final class StreamedDevice = DeviceController with SoloStream<DeviceState>;

final class _Started extends DeviceEvent {
  const _Started();
}

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc(this._device) : super(_device.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _device));
    on<Connect>((e, emit) => settle(_device.connect()));
    on<ReadBattery>((e, emit) => settle(_device.readBattery()));
    on<Rename>((e, emit) => settle(_device.rename(e.name)));
    on<Disconnect>((e, emit) => settle(_device.disconnect()));
    add(const _Started());
  }

  final StreamedDevice _device;

  @override
  Future<void> close() async {
    await _device.close();
    return super.close();
  }
}
```

```text
a registration per command, leaving: [connect, rename kitchen, disconnect]
a registration per command, a shared const read: [connect, rename kitchen, disconnect, connect, battery]
a registration per command, a read after disconnect: [connect, disconnect], the zone []
```

Каждый обработчик отдаёт команду контроллеру, когда приходит его событие,
и команды ждут в очереди контроллера, где отключение снимает чтение. Чтение
экрана, открытого снова, идёт после отключения и остаётся.

Что остаётся на bloc: регистрация на каждую команду, потому что под одной
регистрацией с `sequential()` в очереди контроллера снимать нечего.
Ни `Expando`, ни меток, ни проверки в обработчике.

## Реакция на независимое внешнее изменение состояния

Пользователь просит отчёт, и сессию отзывают с другого устройства, пока отчёт
собирается. Состояние должно сразу стать `SignedOut`, и ни один отчёт не должен
публиковаться поверх него. Отчёт собирается 50 мс из данных, уже лежащих
на устройстве, экран просит два, а сессию отзывают через 20 мс. События
и состояния — из раздела
[«Реакция на независимое внешнее изменение состояния»](vs-bloc.md#реакция-на-независимое-внешнее-изменение-состояния).

### Только bloc

Отзыв — событие со своей регистрацией, а сборка проверяет состояние по обе
стороны от своего `await`:

```dart
class ReportBloc extends Bloc<ReportEvent, ReportState> {
  final Reports _reports;
  final Auth _auth;

  ReportBloc(this._reports, this._auth) : super(SignedIn()) {
    _auth.onRevoked = (reason) => add(SessionRevoked(reason));
    on<SessionRevoked>((e, emit) => emit(SignedOut(e.reason)));
    on<BuildReport>((e, emit) async {
      if (state is! SignedIn) return;
      final report = await _reports.build(e.range);
      if (state is! SignedIn) return;
      emit(Ready(report));
    }, transformer: sequential());
  }

  @override
  Future<void> close() {
    _auth.onRevoked = null;
    return super.close();
  }
}
```

```text
with bloc alone: states [SignedOut(signed out elsewhere)], built 1, the zone []
```

Первый отчёт собирается и отбрасывается проверкой после `await`, а второй
не начинается.

### Контроллер под bloc

Вызовы уходят контроллеру того раздела, у которого есть `stream` и который
берёт отзыв из колбэка через `externalSetState`:

```dart
final class ReportController extends Solo<ReportState> with SoloStream {
  final Reports _reports;
  final Auth _auth;

  ReportController(this._reports, this._auth) : super(const SignedIn()) {
    _auth.onRevoked = (reason) => externalSetState(SignedOut(reason));
  }

  Job<void> build(Range range) =>
      enqueue<SignedIn, void>(key: 'report', (ctx) async {
        final report = await ctx.join(() => _reports.build(range));
        ctx.emit(Ready(report));
      });

  @override
  void onClose() {
    _auth.onRevoked = null;
  }
}
```

Кроме мостов, у bloc одна регистрация — для сборки:

```dart
final class _Started extends ReportEvent {}

class ReportBloc extends Bloc<ReportEvent, ReportState> {
  ReportBloc(this._report) : super(_report.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _report));
    on<BuildReport>((e, emit) => settle(_report.build(e.range)));
    add(_Started());
  }

  final ReportController _report;

  @override
  Future<void> close() async {
    await _report.close();
    return super.close();
  }
}
```

```text
with a controller: states [SignedOut(signed out elsewhere)], built 1, the zone []
```

`SignedOut` доходит до bloc через мост. `build` выполняется только
в `SignedIn`: первая задача дожидается своего отчёта и заканчивается,
не опубликовав его, вторая не начинается, и обе кончаются
`Cancelled(rules: is not SignedIn)`, который обработчик получает из `done`.

Что остаётся на bloc: ничего для отзыва. Ни `SessionRevoked` с его
регистрацией, ни проверки состояния до или после `await`: правило объявлено
у `build`.

## Завершение начатой записи перед перезапуском

Обновление прошивки записывает части через BLE одну за другой, по 20 мс каждая.
Новая загрузка должна остановить старый цикл и дождаться его текущей записи,
прежде чем отправлять свою часть: API BLE не может прервать принятую запись.
В трассах ниже у каждой загрузки четыре части, вторая начинается через 30 мс
после первой, пока пишется часть 1, а третья — через 5 мс после второй или
в тот же момент. События и состояния — из раздела
[«Завершение начатой записи перед перезапуском»](vs-bloc.md#завершение-начатой-записи-перед-перезапуском).

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

class LockedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;
  final _wire = Lock();

  LockedFirmwareBloc(this._ble) : super(Idle()) {
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

Вторую загрузку заменяют, пока она ждёт блокировку, и проверка внутри
блокировки не пускает её запись на провод. Каждый обработчик, который пишет
в устройство, обязан брать ту же блокировку.

### Контроллер под bloc

Вызовы уходят контроллеру того раздела:

```dart
final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => enqueue<NotBroken, void>(
    key: 'flash',
    policy: Policy.restart,
    (ctx) async {
      var written = 0;
      for (final chunk in chunks) {
        await ctx.join(() => _ble.write(chunk));
        ctx.emit(Flashing(++written, chunks.length));
      }
    },
  );
}
```

Кроме мостов, у bloc одна регистрация, с трансформером, который bloc даёт
по умолчанию:

```dart
final class StreamedFirmware = FirmwareController
    with SoloStream<FirmwareState>;

final class _Started extends FirmwareEvent {}

class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  FirmwareBloc(this._firmware) : super(_firmware.currentState) {
    on<_Started>((e, emit) => follow(emit, state, _firmware));
    on<Flash>((e, emit) => settle(_firmware.flash(e.chunks)));
    add(_Started());
  }

  final StreamedFirmware _firmware;

  @override
  Future<void> close() async {
    await _firmware.close();
    return super.close();
  }
}
```

Провод и состояния — те же, что у bloc с блокировкой, строка в строку, в обеих
сериях. `Policy.restart` отменяет идущую загрузку и запускает замену, когда её
задача закончилась; `ctx.join` даёт текущей записи дойти и затем бросает
`Cancelled`, до следующего `emit`. Вторую загрузку заменяют до её старта, и она
ничего не пишет, а обе заменённые загрузки кончаются `Cancelled(replaced)`.

Что остаётся на bloc: ни блокировки, ни проверки `emit.isDone`,
ни `restartable()`: замена — политика `flash`.

## Где ответ остаётся за bloc

Остальным сценариям из [«solo и bloc рядом»](vs-bloc.md) раздела здесь нет:
в каждом контроллер под bloc оставляет коду bloc столько же работы.

| Сценарий | Что остаётся на bloc |
| --- | --- |
| [Ошибка наблюдателя при обновлении состояния](vs-bloc.md#ошибка-наблюдателя-при-обновлении-состояния) | защита внутри наблюдателя: наблюдатель принадлежит bloc, и состояния контроллера доходят до него через тот же `emit` |
| [Выход из состояния загрузки при отмене работы](vs-bloc.md#выход-из-состояния-загрузки-при-отмене-работы) | сброс из обработчика `CancelRefresh`: контроллер, который перезапускает обновление, сбрасывает состояние и между двумя стартами, и экран на миг показывает `Initial` |
| [Типизированные методы с выполнением через очередь](vs-bloc.md#типизированные-методы-с-выполнением-через-очередь) | функции-события и методы, которые возвращают `void`: `add` ничего не возвращает, и `Job` контроллера остаётся в обработчике |
| [Ожидание конкретного запроса](vs-bloc.md#ожидание-конкретного-запроса) | completer на событии: вызывающий не может ждать `Job`, которого `add` не возвращает |
| [Освобождение ресурса, полученного после отмены](vs-bloc.md#освобождение-ресурса-полученного-после-отмены) | `try`/`finally` вокруг буфера: контроллер объявляет освобождение как `dispose` там, где буфер получен, и трасса та же |
