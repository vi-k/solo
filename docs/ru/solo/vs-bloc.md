# solo и bloc рядом

Этот документ сравнивает [solo](https://pub.dev/packages/solo) с `Bloc`
и `Cubit` на десяти сценариях контроллеров. В каждом разделе описано
нужное поведение, показаны реализации и объяснено, что делает библиотека,
а что остаётся кодом приложения.

`Bloc` обрабатывает события, зарегистрированные через `on<E>`.
Трансформер определяет порядок выполнения событий этой регистрации.
`Cubit` предоставляет методы, напрямую меняющие состояние; очереди
событий у него нет.

В `solo` метод контроллера обычно создаёт `Job<T>` и ставит его в очередь
контроллера. Корневые Job выполняются по одной. Вызывающий код может
дождаться `job.value`, чтобы получить значение или исключение,
либо `job.done`, чтобы получить исход `Done`, `Failed` или `Cancelled`.
Политика очереди применяется при добавлении отдельного Job.

Остальные API solo вводятся по мере использования. В
[README](https://github.com/vi-k/solo/blob/main/packages/solo/README.ru.md)
есть полное введение и подробные контракты.

Примеры используют отдельные модели приложений: `Ready` у плеера
не является `Ready` датчика. Вспомогательные классы состояний, событий
и фейковые API определены в запускаемом стенде документации. Примеры
проверены с bloc 9.2.1, bloc_concurrency 0.3.0 и локальным кодом solo 0.2.0.
Трассы описывают эти запуски, а не гарантируют время работы произвольного
устройства. Стенд извлекает код из этого документа;
он находится в репозитории в `tool/doc_snippets.py`.

## Соответствия

Основные соответствия API для того, кто знает bloc:

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| Класс события, `on<E>`, `add(E())` | Метод, возвращающий `Job<T>` |
| `EventTransformer` | `Policy` при добавлении Job |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | Контрольные точки отмены, например `ctx.wait` и `ctx.check` |
| `emit.onEach`, `emit.forEach` | `ctx.each(stream, onData)` |
| `state`, `stream` | `currentState`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder`; выбор части состояния делает приложение |
| `BlocListener` для результата операции | Ожидание `job.done` этой операции |
| `BlocProvider` | Выбранный способ владения или передачи зависимостей |
| `close()` | `close()` |
| `blocTest` | `test` и ожидание исхода Job |

`sequential`, `droppable` и `restartable` соответствуют
`Policy.sequential`, `Policy.droppable` и `Policy.restart`.
`Policy.replace` удаляет ожидающую работу, сохраняя работающую Job.
Политики одновременного выполнения корневых Job нет; для независимой
параллельной работы используйте детей или отдельные контроллеры.

## 1. Порядок обновлений общего состояния

Контроллер заметок отправляет заметку и обновляет список с сервера.
Если обновление началось до конца отправки, ответ может содержать старый
список. Публикация такого ответа после отправки удалит новую заметку
из локального состояния, даже если оба обработчика читают актуальный
локальный `state`. Нужно упорядочить целые операции, включая ввод-вывод.

### Bloc

По умолчанию события обрабатываются конкурентно. Для последовательной
обработки обоих типов зарегистрируйте один обработчик общего типа
с `sequential()`:

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  NotesBloc(this._api) : super(const NotesState()) {
    on<NotesEvent>((e, emit) async {
      switch (e) {
        case UploadNote(:final note):
          emit(state.copyWith(uploading: true));
          await _api.upload(note);
          emit(
            state.copyWith(notes: [...state.notes, note], uploading: false),
          );
        case RefreshList():
          final serverNotes = await _api.list();
          emit(state.copyWith(notes: serverNotes));
      }
    }, transformer: sequential());
  }
}
```

Измеренное итоговое состояние: `NotesState([n0, n1], uploading: false)`.
Отправка завершается до чтения сервера. Одна регистрация также означает
один трансформер для всех команд, обрабатываемых этой регистрацией.

`sequential()` на двух отдельных регистрациях `on<E>` не упорядочивает
их между собой. В том же сценарии такая схема заканчивается
с `NotesState([n0], uploading: false)`. Поэтому все операции, которым нужен
общий порядок, должны использовать одну регистрацию. Это различие
разобрано в [обсуждении порядка обработчиков](https://github.com/felangel/bloc/issues/2790).

Отдельная проблема устаревшего снимка есть в выражении
`emit(state.copyWith(notes: await _api.list()))`: Dart вычисляет получатель
`state` до ожидания аргумента. Конкурентный тест этого варианта завершается
с `NotesState([n0], uploading: true)`, затирая и заметки, и флаг отправки.
Чтение состояния после await устраняет проблему снимка, но не делает
серверные операции последовательными.

### Solo

Методы одного контроллера используют общую очередь корневых Job:

```dart
final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.join(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          final serverNotes = await ctx.wait(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}
```

`ctx.join(action)` вызывает операцию и ждёт её завершения. После успешного
ответа он проверяет отмену перед возвратом результата. Отправка использует
`join`, чтобы следующая корневая Job не читала сервер, пока отправка
продолжается. Обновление использует `ctx.wait`, который может прекратить
ожидание при отмене: в этом примере результат чтения разрешено отбросить.

Итоговое состояние тоже `NotesState([n0, n1], uploading: false)`.
Добавление ещё одного метода через очередь сохраняет общий порядок.
Гарантия относится к корневым Job; дочерние Job могут работать внутри
родителя, а независимые изменения устройства имеют отдельный путь,
описанный в разделе 8.

В телах Job используйте методы ожидания контекста для проверки отмены
и правил состояния. Обычный `await` продолжает удерживать тело и очередь,
но не реагирует на отмену. Работа, запущенная без ожидания, может пережить
Job; нельзя считать, что она закончится до `close()`.

## 2. Ошибка наблюдателя при обновлении состояния

Диктофон запускает нативную запись, публикует `Recording` и включает
индикатор уровня. Наблюдатель телеметрии бросает ошибку при обработке
обновления. Операция диктофона должна завершиться независимо от отправки
телеметрии.

### Bloc и Cubit

Оба используют `BlocBase.emit`. Он вызывает `onChange` до изменения
состояния, а исключение этого вызова передаёт в `onError` и бросает дальше:

```dart
class RecorderBloc extends Bloc<StartRecording, RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderBloc(this._recorder, this._journal) : super(const Idle()) {
    on<StartRecording>((e, emit) async {
      await _recorder.start();
      emit(const Recording());
      _recorder.armMeter();
    });
  }

  @override
  void onChange(Change<RecorderState> change) {
    super.onChange(change);
    _journal.note('${change.nextState}');
  }
}

class TelemetryObserver extends BlocObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    _telemetry.send(change.nextState);
  }
}
```

В этом запуске устройство начинает запись, но состояние остаётся `Idle`.
Индикатор уровня не включается. Локальный журнал пуст, потому что запись
в него стоит после провалившегося `super.onChange`. Обработчик сообщает
`telemetry unavailable`. Та же ошибка наблюдателя в методе Cubit
передаётся вызывающему этот метод коду.

Перехватите ошибки телеметрии внутри наблюдателя, чтобы они не прерывали
обновление:

```dart
class GuardedTelemetryObserver extends BlocObserver {
  final Telemetry _telemetry;
  final Log _fallback;

  GuardedTelemetryObserver(this._telemetry, this._fallback);

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    try {
      _telemetry.send(change.nextState);
    } on Object catch (error, stackTrace) {
      _fallback.write(error, stackTrace);
    }
  }
}
```

Защищённый вариант достигает `Recording`, записывает
`[native start, arm meter]` и добавляет `[Recording]` в журнал.
Резервный логгер получает ошибку телеметрии. Подход работает, если все
соответствующие колбэки наблюдения обрабатывают свои ошибки, а резервный
логгер не бросает исключение. Одно переопределение `onError`
не предотвращает повторный бросок ошибки из `emit`.

### Solo

Наблюдатель и хуки контроллера вызываются независимо. Исключение каждого
хука передаётся в текущую зону Dart:

```dart
final class RecorderController extends Solo<RecorderState> {
  final Recorder _recorder;
  final Journal _journal;

  RecorderController(this._recorder, this._journal) : super(const Idle());

  Job<void> start() => run<RecorderState, void>(
        key: 'start',
        (ctx) async {
          await ctx.join(_recorder.start);
          ctx.emit(const Recording());
          _recorder.armMeter();
        },
      );

  @override
  void onChange(RecorderState previous, RecorderState current) =>
      _journal.note('$current');
}

final class TelemetryObserver extends SoloObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      _telemetry.send(current);
}
```

`SoloObserver` получает `SoloBase<Object>`, поскольку наблюдает
контроллеры с разными типами состояний. Собственный хук контроллера
использует его конкретный тип состояния.

С бросающим наблюдателем выполнение всё равно достигает `Recording`,
включает индикатор, записывает `[Recording]` локально и заканчивается
с `Done(null)`. Ошибка телеметрии передаётся в зону. Стенд обрабатывает
её через `runZonedGuarded`; необработанная ошибка зоны всё ещё может
завершить приложение. Изоляция хуков сохраняет ход выполнения операции,
а приложение по-прежнему отвечает за сообщения об ошибках.

## 3. Закрытие и отмена начатой работы

Пользователь отправляет сообщение в чат и уходит с экрана до ответа.
Контроллер должен запретить старой операции обновлять закрытый экран
и добавлять последующую работу после закрытия.

### Bloc

В этих версиях поведение закрытия зависит от трансформера.
С `sequential()` вызов `close()` ждёт работающий обработчик, который
ещё может публиковать состояние, пока закрытие не завершено.
С трансформером по умолчанию, `concurrent`, `droppable` или `restartable`
измеренный close возвращается до конца тела, а отменённый emitter
игнорирует последующие записи. Ни один вариант не прерывает вызов API
или оставшийся код тела обработчика.

Этот последовательный обработчик проверяет закрытие после await:

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
    on<MarkReplyRead>(
      (e, emit) => _api.markRead(),
      transformer: sequential(),
    );
  }
}
```

Проверка предотвращает и обновление ответа, и событие `MarkReplyRead`.
Закрытие всё ещё ждёт возврата вызова API и обработчика. Отдельная
регистрация `MarkReplyRead` безопасна в этом примере, поскольку не меняет
общее состояние; иначе возникло бы ограничение порядка из раздела 1.

`add` после закрытия бросает `StateError`, поэтому вызывающий код,
способный поздно отправить событие, должен сам обработать этот случай.
Метод Cubit тоже продолжает выполнение после закрытия, но его прямой
`emit` бросает исключение, а не использует отменённый emitter обработчика.

Другой случай: неожидаемая future вызывает emit после обычного
завершения обработчика, пока Bloc ещё открыт. Это вызывает assert
в debug; с отключёнными assert поздняя запись в измеренном запуске
меняет состояние. Это ограничение времени жизни разобрано в
[issue о завершённом обработчике](https://github.com/felangel/bloc/issues/2961).
Поддержка отмены также обсуждается в
[предложении отменяемых операций](https://github.com/felangel/bloc/issues/3069).

### Solo

`close()` прекращает приём Job, отменяет очередь, запрашивает отмену
работающей Job и ждёт её завершения, включая освобождение ресурсов:

```dart
final class ChatController extends Solo<ChatState> {
  final Api _api;

  ChatController(this._api) : super(const ChatState());

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await ctx.wait(() => _api.send(text));
          ctx.emit(ctx.state.withReply(reply));
          markReplyRead();
        },
      );

  Job<void> markReplyRead() =>
      run<ChatState, void>((ctx) => ctx.wait(_api.markRead));
}

Future<void> onScreenClosed(ChatController chat) async {
  await chat.close();
  chat.send('bye'); // задача, уже завершённая с Cancelled(closed)
}
```

В этом теле `ctx.wait` бросает `Cancelled`, когда закрытие отменяет Job.
Обновление ответа и вызов `markReplyRead()` не выполняются. Этот метод
поставил бы отдельную корневую Job через `run` контроллера;
она не является ребёнком `send`.

С обычным await закрытие ждало бы ответа API. Последующий `ctx.emit`
всё равно отклонил бы отменённую Job. Захваченный контекст, использованный
после завершения Job, бросает `StateError` и в debug, и в release.
Вызовы после закрытия возвращают Job, уже завершённые
с `Cancelled(closed)`, поэтому проверка `isClosed` в месте вызова не нужна.

### Выход из Loading после отмены

Отмена может происходить и при открытом контроллере. Рассмотрим индикатор
обновления с двумя состояниями, `Initial` и `Loading`. `StartRefresh`
начинает работу; `CancelRefresh` отменяет обработчик через ту же
регистрацию с `restartable()`. Пример отслеживает только активность
обновления; API не возвращает данных для отображения.

В Bloc недостаточно поместить сброс в `finally` старого обработчика:

```dart
class RefreshBloc extends Bloc<RefreshEvent, RefreshState> {
  final RefreshApi _api;

  RefreshBloc(this._api) : super(const Initial()) {
    on<RefreshEvent>((event, emit) async {
      if (event is CancelRefresh) return;
      emit(const Loading());
      try {
        await _api.refresh();
      } finally {
        emit(const Initial());
      }
    }, transformer: restartable());
  }
}
```

После `StartRefresh` состояние становится `Loading`. `CancelRefresh`
заменяет обработчик, но не публикует новое состояние. Future API
продолжает работать. Когда она завершается, `finally` вызывает старый,
отменённый emitter, который игнорирует `Initial`. Поэтому состояние
остаётся `Loading` даже после завершения вызова API. Сама отмена
не бросала исключение в старое тело.

Решение для Bloc: опубликовать сброс из активного обработчика отмены.
Замените ветку `CancelRefresh` на:

```dart
if (event is CancelRefresh) {
  emit(const Initial());
  return;
}
```

Теперь состояние становится `Initial` при обработке события отмены.
Поздний emit старого обработчика по-прежнему игнорируется и не может
перезаписать более новое обновление. С `restartable` любой тип события
этой регистрации может заменить текущий обработчик; отдельная
регистрация `on<CancelRefresh>` сама по себе не отменит `StartRefresh`.

В solo сброс привязывается к итоговому исходу операции:

```dart
final class RefreshController extends Solo<RefreshState> {
  final RefreshApi _api;

  RefreshController(this._api) : super(const Initial());

  Job<void> refresh() => run<RefreshState, void>(
        key: 'refresh',
        policy: Policy.restart,
        onError: (state, error, stackTrace) => const Initial(),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          await ctx.wait(_api.refresh);
          ctx.emit(const Initial());
        },
      );
}
```

Вызовите `controller.refresh()` и сохраните его Job; `await job.cancel()`
дождётся отмены и освобождения ресурсов. `ctx.wait` прекращает ожидание
API, а `onCancel` возвращает `Initial` до продвижения очереди.
Успешное обновление публикует `Initial` из тела; `onError` сбрасывает
индикатор при ошибке, при этом Job по-прежнему сообщает `Failed`.

Момент обновления различается: обработчик события отмены Bloc меняет
состояние при своём выполнении, а обработчик состояния solo вызывается
после уборки отменённой Job. Ни один пример не останавливает саму
операцию API. Если независимое внешнее состояние делает Job solo
недопустимой, её итоговые обработчики состояния пропускаются;
раздел 8 объясняет внешнее состояние, а README описывает правила допуска.

## 4. Перезапуск одной операции в общей очереди

Плеер должен выполнять `play`, `pause` и `seek` по одной операции.
При перетаскивании ползунка ожидающие позиции устаревают, а работающая
перемотка должна остановиться до начала замены. Play и pause сохраняют
свой порядок. API плеера в примере принимает токен и возвращает
управление при отмене.

### Bloc

Отдельный `on<Seek>` с `restartable()` может выполняться одновременно
с обработчиками play и pause. Для последовательности всех команд эта
реализация использует одну регистрацию с `sequential()` и отслеживает
последнюю позицию и активный токен:

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
    if (event is Seek) {
      _newestSeek = event.position;
      _seeking?.cancel();
    }
    super.onEvent(event);
  }
}
```

Для позиций `1, 2, 3`, добавленных вместе, устройство получает
`[play, seek 3, pause]`. Если seek 1 уже выполняется при появлении seek 3,
трасса выглядит так: `[seek 1 start, seek 1 stopped, seek 3 start,
seek 3 end]`. `onEvent` синхронно получает новый запрос и отменяет токен;
последовательный обработчик ждёт возврата плеера перед продолжением.

Сравнения значений позиции недостаточно, когда перетаскивание повторяет
значение. Ввод `1, 2, 1` даёт `[play, seek 1, seek 1, pause]`.
Этот случай исправляется определением последнего события по счётчику
поколений вместо его позиции.

Приложение поддерживает идентичность последнего запроса, активный токен
и проверку после await. Каждой команде с другим поведением замены
нужна соответствующая логика внутри общего обработчика. `add`
не возвращает исход пропущенной или прерванной перемотки.

### Solo

Политика очереди задаётся при добавлении каждой Job. Фрагмент показывает
pause и seek; play следует той же последовательной схеме, что pause.
`Ready` является рабочим типом состояния этих Job плеера:

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await ctx.join(_player.pause);
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
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

`Policy.restart` удаляет отменяемые ожидающие перемотки с тем же ключом
и запрашивает отмену активной. `ctx.onCancel` сразу передаёт запрос
плееру. `ctx.join` ждёт возврата операции, прежде чем текущая Job сможет
закончиться, а замена начаться. Если операция после отмены завершается
ошибкой, тело получает эту ошибку; исход Job остаётся отменённым.

Наблюдаемые трассы совпадают с успешными случаями Bloc выше. Pause и play
остаются в той же очереди с последовательной политикой по умолчанию.
Токен является локальной переменной тела seek, а вызывающий код может
проверить исход каждой перемотки, включая `Cancelled(manual)`
для заменённого запроса.

## 5. Типизированные методы с выполнением через очередь

Карта предоставляет `moveTo` и `setZoom`. Вызывающему коду нужны
типизированные аргументы, а частые обновления перетаскивания не должны
оставлять карту на устаревшей позиции.

### Cubit

Cubit напрямую поддерживает методы, возвращающие future:

```dart
class MapCubit extends Cubit<MapState> {
  final MapApi _map;

  MapCubit(this._map) : super(const MapState());

  Future<void> moveTo(Point<double> point) async {
    await _map.moveTo(point);
    emit(state.copyWith(center: point));
  }

  Future<void> setZoom(double value) async {
    await _map.setZoom(value);
    emit(state.copyWith(zoom: value));
  }
}
```

Эти методы не упорядочивают вызовы. При разной длительности нативных
вызовов трасса выглядит так: `[moveTo 1 start, moveTo 2 start,
moveTo 3 start, moveTo 3 end, moveTo 2 end, moveTo 1 end]`.
Состояние заканчивается на `MapState(1, z1)`, отражая самый старый запрос,
поскольку он завершился последним.

Цепочка future может упорядочить вызовы; для отбрасывания устаревших
запросов нужен дополнительный учёт. Приложение также должно решить,
как закрытие дожидается этой цепочки или делает её недействительной;
Cubit не управляет этим автоматически.

### Bloc с функциями в качестве событий

Событие само может быть функцией. Одна последовательная регистрация
выполняет эти функции, а публичные методы дают типизированный интерфейс:

```dart
typedef MapCommand = Future<void> Function(Emitter<MapState>);

class CommandMapBloc extends Bloc<MapCommand, MapState> {
  final MapApi _map;

  CommandMapBloc(this._map) : super(const MapState()) {
    on<MapCommand>(
      (command, emit) => command(emit),
      transformer: sequential(),
    );
  }

  void moveTo(Point<double> point) => add((emit) async {
        await _map.moveTo(point);
        emit(state.copyWith(center: point));
      });

  void setZoom(double value) => add((emit) async {
        await _map.setZoom(value);
        emit(state.copyWith(zoom: value));
      });
}
```

Теперь вызовы идут по порядку и заканчиваются с `MapState(3, z4)`.
Это даёт типизированные методы и общий порядок без отдельного класса
события на метод. Все команды по-прежнему используют один трансформер,
а показанные методы возвращают `void`. Для возврата результата нужен
дополнительный механизм, как в разделе 7.

### Solo

Каждый метод возвращает Job и задаёт политику замены:

```dart
enum MapKey { moveTo, setZoom }

final class MapController extends Solo<MapState> {
  final MapApi _map;

  MapController(this._map) : super(const MapState());

  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.moveTo(point, cancelToken: token));
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.setZoom(value, cancelToken: token));
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

Трасса перезапуска: `[moveTo 1 start, moveTo 1 stopped, moveTo 3 start,
moveTo 3 end]`. Средний запрос не начинается; первый останавливается
до начала последнего. И карта, и `MapState(3, z4)` отражают последний
запрос. Вызывающий код может дождаться операции через `job.value`
или `job.done` либо обойтись без ожидания. Сам возвращённый Job
не является Future; правила обработки ошибок описаны в README.

## 6. Удаление выбранной ожидающей работы

BLE-экран ставит в очередь подключение, чтение батареи и сигнала,
переименование и отключение. При закрытии экрана ожидающие чтения
нужно отбросить, а заказанное переименование должно завершиться
до отключения.

### Bloc

Одна регистрация с `sequential()` упорядочивает все команды устройства.
Через API Bloc нельзя перечислить или удалить её ожидающие события,
поэтому обработчик проверяет, актуально ли ещё чтение.

Одного флага ухода недостаточно, если экран откроется до обработки
старых событий: сброс флага для нового экрана снова разрешит старое
чтение. Эта версия записывает поколение экрана на каждом событии:

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
        case ReadSignal():
          if (_stampOf[e] != _screen) return;
          emit(state.copyWith(signal: await _ble.signal()));
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
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
    super.onEvent(event);
  }
}
```

Устройство получает `[connect, rename kitchen, disconnect]`. Если экран
открывается до конца ожидающей работы, старое чтение пропускается,
а новое выполняется: `[connect, disconnect, connect, battery]`.

Записи поколений являются состоянием приложения, связанным с очередью.
События всё равно доходят до обработчика, который должен проверять
каждую отбрасываемую команду. Схема с `Expando` также требует разных
объектов событий. Повторное использование канонического const-события
перезаписывает прежнюю метку; измеренная последовательность тогда
включает устаревшее чтение: `[connect, battery, disconnect, connect,
battery]`. `add` не возвращает результат, указывающий на пропуск чтения.

### Solo

Контроллер может удалять подходящие Job прямо из своей очереди:

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

  Job<void> disconnect() {
    queue.removeWhere(
      (job) =>
          job.key == DeviceKey.readBattery || job.key == DeviceKey.readSignal,
    );
    return run<Connected, void>(
      key: DeviceKey.disconnect,
      (ctx) async {
        await ctx.join(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

Трасса устройства та же, но удаление происходит при вызове `disconnect`.
Удалённые Job чтения завершаются с `Cancelled(manual)`; вызывающий код
может наблюдать этот результат. Переименование остаётся в очереди,
а отключение выполняется после него. `removeWhere` не затрагивает
уже работающее подключение. Для удаления Job с `cancellable: false`
из очереди нужен `force: true`.

## 7. Ожидание конкретного запроса

Оплату могут вызвать и кнопка Pay, и запрос платформы. Обработчик
платформы должен вернуть результат своего заказа. Одновременные запросы
одного заказа должны использовать одну оплату; разные заказы должны
выполняться последовательно.

Наблюдение `Paid` через `BlocListener` может обслужить навигацию экрана,
но функции, отвечающей на запрос платформы, нужен результат именно
этого запроса. `Bloc.add` возвращает `void`; этот случай затронут
в [обсуждении ожидания событий](https://github.com/felangel/bloc/issues/1556).

### Bloc

Передайте completer в событии и предоставьте метод, возвращающий его
future. Карта выполняющихся оплат даёт повторным вызовам общий результат:

```dart
class Pay extends CheckoutEvent {
  final Order order;
  final Completer<Receipt> result;

  Pay(this.order) : result = Completer<Receipt>();
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;
  final _inFlight = <String, Completer<Receipt>>{};

  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      try {
        emit(Paying());
        final receipt = await _api.pay(e.order);
        e.result.complete(receipt);
        emit(Paid(receipt));
      } on Object catch (error, stackTrace) {
        if (!e.result.isCompleted) {
          e.result.completeError(error, stackTrace);
        }
        emit(PaymentFailed(error));
      } finally {
        _inFlight.remove(e.order.id);
      }
    }, transformer: sequential());
  }

  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) return running.future;
    final event = Pay(order);
    _inFlight[order.id] = event.result;
    try {
      add(event);
    } on Object {
      _inFlight.remove(order.id);
      rethrow;
    }
    return event.result.future;
  }
}
```

`await bloc.pay(order)` теперь возвращает квитанцию. Три вызова по двум
заказам дают два обращения к API, а оба вызывающих один заказ получают
его квитанцию.

Completer должен завершаться на каждом пути. Catch вокруг `add` удаляет
запись из карты, когда закрытый Bloc отклоняет событие. `isCompleted`
предотвращает повторное завершение, если emit бросает ошибку после
передачи квитанции. Завершение результата до публикации `Paid` не даёт
ошибке наблюдателя заменить уже полученную квитанцию. Одного `droppable()`
для такого объединения недостаточно: отброшенное событие оставило бы
свой completer незавершённым.

### Cubit

Метод Cubit может вернуть квитанцию напрямую, но одновременные вызовы
автоматически не объединяются и не упорядочиваются. Эта версия добавляет
карту выполняющихся оплат и цепочку future:

```dart
class CheckoutCubit extends Cubit<CheckoutState> {
  final Api _api;
  final _inFlight = <String, Future<Receipt>>{};
  Future<void> _tail = Future.value();

  CheckoutCubit(this._api) : super(Cart());

  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) {
      return running;
    }
    final turn = Completer<void>();
    final before = _tail;
    _tail = turn.future;
    final result = before.then((_) => _pay(order)).whenComplete(turn.complete);
    _inFlight[order.id] = result;
    return result;
  }

  Future<Receipt> _pay(Order order) async {
    try {
      emit(Paying());
      final receipt = await _api.pay(order);
      emit(Paid(receipt));
      return receipt;
    } finally {
      _inFlight.remove(order.id);
    }
  }
}
```

Она тоже даёт два обращения к API для трёх запросов по двум заказам.
Обработка закрытия остаётся неполной: Cubit не ждёт эту собственную
цепочку. При измеренном закрытии во время оплаты списание проходит,
но последующий `emit(Paid(...))` бросает
`Bad state: Cannot emit new states after calling close`, и вызывающий
код получает эту ошибку вместо квитанции. Рабочая реализация должна
согласовать закрытие с цепочкой оплат и доставкой результата.

### Solo

Используйте идентификатор заказа в ключе и верните Job напрямую:

```dart
final class CheckoutController extends Solo<CheckoutState> {
  final Api _api;

  CheckoutController(this._api) : super(const Cart());

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        key: ('pay', order.id),
        policy: Policy.droppable,
        cancellable: false,
        (ctx) async {
          ctx.emit(const Paying());
          final receipt = await ctx.join(() => _api.pay(order));
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}
```

Обработчик платформы может разобрать исход этого Job:

```dart
Future<Map<String, Object?>> handlePayRequest(
  CheckoutController checkout,
  Order order,
) async {
  switch (await checkout.pay(order).done) {
    case Done(:final value):
      return {'paid': true, 'receipt': value.id};
    case Cancelled(:final reason):
      return {'paid': false, 'cancelled': reason.name};
    case Failed(:final error):
      return {'paid': false, 'error': '$error'};
  }
}
```

`Policy.droppable` возвращает существующий ожидающий или работающий Job
для того же ключа заказа. Оба вызова получают общую квитанцию,
а другой заказ создаёт другой Job. Измеренные три запроса снова дают
два обращения к API.

`cancellable: false` защищает всю операцию оплаты от обычной отмены,
включая закрытие контроллера после её старта. `join` ждёт результат API,
а тело публикует `Paid` до завершения с квитанцией. `close()` ждёт этого
завершения. Ошибки API по-прежнему дают `Failed`; состояние ошибки можно
задать через `run(onError: ...)`.

Этот Job принимает базовый `CheckoutState` без ограничения `keepWhile`.
Правила состояния могут отменить даже неотменяемый Job, поэтому более
узкий тип допустил бы отмену между отправкой списания и записью его
результата. Ни один метод ожидания не может отозвать списание у API,
которое не предоставляет механизм отмены.

`ctx.uncancellable` решает другую задачу: удерживает обычную отмену
на один шаг, затем применяет запрос. Он не гарантирует успешный исход Job
для оплаты, завершившейся во время этого шага. Для показанного
неотменяемого Job он не нужен.

Флаг также отклоняет ручную отмену, пока оплата стоит в очереди.
Если пользователь должен иметь возможность отменить оплату до начала
списания, моделируйте этот допуск отдельно. `close()`
и `queue.clear(force: true)` по-прежнему могут отбросить ожидающую оплату
без списания, а вызов после закрытия тоже не запускается. Эти случаи
объясняют ветку `Cancelled` обработчика платформы.

Общий Job в памяти объединяет только одновременные вызовы этого
контроллера. Повтор оплаты после перезапуска процесса или сетевого сбоя
также требует идемпотентного API оплаты; ни один пример этого
не предоставляет.

## 8. Реакция на независимое внешнее изменение состояния

Датчик сообщает об аппаратном сбое, пока калибровка ждёт измерение.
Контроллер должен сразу отразить `Broken` и не дать калибровке позднее
опубликовать поверх него `Calibrated`.

### Bloc

Прямой `emit` у Bloc помечен `@visibleForTesting` и документирован
для внутреннего использования. Вместо него слушатель может добавить
событие `HardwareFailed`. Выделите ему отдельную регистрацию,
чтобы оно не ждало за калибровкой:

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  final Sensor _hw;

  SensorBloc(this._hw) : super(Ready()) {
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      if (state is! Ready) return;
      await _hw.sample();
      if (state is! Ready) return;
      emit(Calibrated());
    }, transformer: sequential());
  }
}
```

Выполнение заканчивается на `Broken(cable unplugged)` без публикации
`Calibrated`. Калибровка проверяет состояние после каждого await,
поскольку событие сбоя не отменяет её обработчик или emitter.

Если оба события используют одну последовательную регистрацию,
уведомление сбоя ждёт за калибровкой. Измеренные состояния становятся
`[Calibrated, Broken(cable unplugged)]`, ненадолго сообщая об успехе
после сбоя устройства. Поэтому этот подход использует отдельный
обработчик сбоя и явные проверки в операциях, зависящих от устройства.

Cubit может отразить уведомление напрямую из метода наследника,
но его асинхронным операциям всё ещё нужны такие же проверки допустимости.

### Solo

`externalSetState` является защищённым методом для отражения изменения,
уже произошедшего в независимом источнике. Слушатель находится внутри
наследника контроллера:

```dart
final class SensorController extends Solo<SensorState> {
  final Sensor _hw;

  SensorController(this._hw) : super(const Ready()) {
    _hw.onError = (error) => externalSetState(Broken(error));
  }

  Job<void> calibrate() => run<Ready, void>(
        key: 'calibrate',
        (ctx) async {
          await ctx.join(_hw.zero);
          await ctx.join(_hw.sample);
          ctx.emit(const Calibrated());
        },
      );
}
```

Обычный Job для публикации `Broken` задержал бы этот факт в очереди
за калибровкой, которую он делает недопустимой. `externalSetState`
сразу обновляет состояние и проверяет работающие тела по их правилам.
Здесь `run<Ready, void>` разрешает калибровку только при `Ready`,
поэтому внешний сбой отменяет её с `Cancelled(rules: is not Ready)`.

Исключение относится к фактам вроде уже отключённого кабеля.
Уведомление с просьбой выполнить будущую работу должно поставить
обычный Job в очередь. Само получение данных из стрима не является
основанием обходить очередь. Остановите слушатель устройства перед
закрытием любого из контроллеров; фрагменты показывают регистрацию,
а не зависящее от приложения снятие слушателя.

При успехе Job может закончиться публикацией `Calibrated`, хотя это
состояние за пределами `Ready`. Собственный emit исключён из проверки
правил; последующая контрольная точка состояния отменила бы Job.
Это позволяет итоговый переход, но требует, чтобы рабочий тип охватывал
всё продолжение работы.

Уже начатый вызов датчика завершается в обоих примерах. `join` ждёт
его, прежде чем разрешить старт другой корневой Job. Устройство
с токеном отмены можно дополнительно остановить через `ctx.onCancel`,
как в разделе 4. Итоговые обработчики состояния `onError` и `onCancel`,
если они заданы, запрещаются несовместимым внешним обновлением,
поэтому не перезаписывают `Broken` при уборке.

## 9. Завершение начатой записи перед перезапуском

Обновление прошивки последовательно записывает части через BLE.
Замена должна остановить старый цикл и дождаться его текущей записи
до отправки любой новой части. API BLE в этом примере не может прервать
уже принятую запись.

### Bloc

`restartable()` отменяет старый emitter, но тело Dart продолжает
выполнение. Проверяйте `emit.isDone` после каждой записи, чтобы
остановить старый цикл:

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

  FirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        if (emit.isDone) return;
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

С проверкой перезапуск посреди загрузки записывает `[0, 1, 100, 101, …]`.
Без неё оба цикла продолжаются, и части чередуются.
[Обсуждение restartable](https://github.com/felangel/bloc/issues/3349)
поясняет, почему отмена не прерывает ожидаемые future.

Одной проверки недостаточно для предотвращения одновременных нативных
записей. Новый обработчик начинается, пока старая запись ещё ожидается.
В тесте получается `[write 0 start, write 0 end, write 1 start,
write 100 start, write 1 end, write 100 end, …]`.
Общая блокировка может упорядочить вызовы устройства:

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

Теперь трасса ставит конец каждой записи до начала следующей:
`[write 0 start, write 0 end, write 1 start, write 1 end, write 100 start,
write 100 end, …]`.

Проверяйте `emit.isDone` и внутри блокировки, и после записи. Событие
может быть заменено во время ожидания блокировки; проверка только
перед входом позволила бы его устаревшей записи начаться позднее.
Блокировка упорядочивает доступ к устройству, а проверка emitter
останавливает устаревшие обработчики. Все операции с этим устройством
должны соблюдать то же правило блокировки.

Отдельное событие `HardwareFailed`, публикующее `Broken`, не меняет
`isDone` этого emitter. В таком сценарии всё ещё нужны дополнительные
проверки состояния, чтобы остановить прошивку и сохранить `Broken`,
как в разделе 8.

### Solo

Job занимает очередь контроллера до завершения тела и уборки:

```dart
final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
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

`Policy.restart` запрашивает отмену и ставит замену в очередь.
`join` ждёт текущую запись; после успешной записи он обнаруживает
отмену и бросает исключение до следующей итерации. Замена начинается
после завершения старого Job. Наблюдаемая последовательность частей
и отсутствие одновременных записей совпадают с Bloc с блокировкой.

Внешнее состояние `Broken` также отменяет этот Job, поскольку больше
не соответствует `NotBroken`. Измеренный сценарий сбоя останавливается
после `[0, 1, 2]` с `Cancelled(rules: is not NotBroken)`. Проверка
охватывает и замену, и потерю допустимости состояния.

Если загрузка запускает детей через `ctx.run`, родитель ждёт и этих
детей, и освобождение их ресурсов. Работа, которой намеренно разрешено
пережить Job, может использовать `ctx.unattended`: её ошибки передаются
хукам Job, но она не удерживает очередь.

## 10. Освобождение ресурса, полученного после отмены

Аудиоредактор открывает нативный PCM-буфер для отрисовки волны.
Пользователь выбирает другой клип, пока декодирование ещё ожидается.
Старую волну нужно отбросить, но её буфер всё равно необходимо освободить.
Эти вызовы декодера могут безопасно выполняться одновременно, поскольку
буферы независимы. Декодеру с последовательным доступом нужно ожидание
из раздела 9.

### Bloc

Проверка `emit.isDone` перед использованием результата предотвращает
устаревшее обновление волны, но эта версия возвращается без освобождения
устаревшего буфера:

```dart
class PreviewBloc extends Bloc<OpenPreview, PreviewState> {
  final Decoder _decoder;

  PreviewBloc(this._decoder) : super(const NoPreview()) {
    on<OpenPreview>((e, emit) async {
      final buffer = await _decoder.open(e.clip);
      if (emit.isDone) return;
      emit(Preview(buffer.waveform()));
      await buffer.release();
    }, transformer: restartable());
  }
}
```

Перенесите проверку внутрь `try`/`finally`, который владеет полученным
буфером:

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

Оба варианта заканчиваются на `Preview(2)`. Первый освобождает текущий
буфер один раз, а устаревший ни разу; защищённый вариант освобождает
каждый один раз. Проверка только состояния пропустила бы утечку.

Обработчик продолжает ожидание после отмены emitter и освобождает буфер
при его получении. Это рабочий способ управления ресурсом; каждый выход
после получения должен оставаться внутри блока `try`. Дополнительные
ресурсы или передача владения требуют соответствующих решений об уборке.
Cubit может использовать тот же подход с собственной проверкой
устаревшего запроса, поскольку у него нет emitter обработчика
и `emit.isDone`.

### Solo

Зарегистрируйте освобождение на вызове, который получает буфер:

```dart
final class PreviewController extends Solo<PreviewState> {
  final Decoder _decoder;

  PreviewController(this._decoder) : super(const NoPreview());

  Job<void> open(Clip clip) => run<PreviewState, void>(
        key: 'preview',
        policy: Policy.restart,
        (ctx) async {
          final buffer = await ctx.wait(
            () => _decoder.open(clip),
            dispose: (buffer) => buffer.release(),
          );
          ctx.emit(Preview(buffer.waveform()));
        },
      );
}
```

`ctx.wait` может закончить отменённый Job до конца декодирования.
Поздний буфер всё равно передаётся в `dispose`; буфер, полученный
при активном Job, освобождается во время его уборки. Поэтому новая Job
может начаться, не ожидая устаревшее декодирование, а каждый буфер
будет освобождён.

Здесь нужен `dispose`, поскольку буфер временный, в том числе при успехе.
`discard` предназначен для ресурса, передаваемого вызывающему коду
как успешный результат; он не освободил бы этот временный буфер после
успешного обновления волны.

Защищённый Bloc и solo оба записывают
`[open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1]`
и заканчиваются на `Preview(2)`.

Позднее освобождение может произойти после закрытия контроллера.
В измеренном запуске solo `close()` заканчивается до появления устаревшего
буфера; он освобождается, когда декодирование наконец его возвращает.
Используйте `join`, когда и операция, и освобождение её ресурса должны
закончиться до продвижения очереди или закрытия контроллера.
