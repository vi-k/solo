# solo и bloc рядом

Этот документ сравнивает [solo](https://pub.dev/packages/solo) с `Bloc`
и `Cubit` на одиннадцати сценариях контроллеров. Каждый раздел описывает нужное
поведение, начинает с кода, который это поведение само подсказывает, говорит,
что этот код делает на самом деле, и только потом показывает реализации,
которые требование выполняют, — на bloc и на solo, — вместе с тем, что делает
библиотека, а что остаётся кодом приложения.

Первая попытка здесь не чучело: это та версия, к которой ведёт словарь самого
API, а состояния и трассы под ней — то, что этот код печатает при запуске.
Прочитать её до ответа и есть смысл раздела; тот, кто ловушку уже знает, может
сразу перейти к `### Bloc` и `### Solo`.

`Bloc` обрабатывает события, зарегистрированные через `on<E>`. Трансформер
определяет порядок выполнения событий этой регистрации. `Cubit` предоставляет
методы, напрямую меняющие состояние; очереди событий у него нет.

В `solo` метод контроллера обычно создаёт `Job<T>` и ставит его в очередь
контроллера. Корневые `Job` выполняются по одной. Вызывающий код может
дождаться `job.value`, чтобы получить значение или исключение, либо `job.done`,
чтобы получить исход `Done`, `Failed` или `Cancelled`. Политика очереди
применяется при добавлении отдельной `Job`.

Остальные API solo вводятся по мере использования.
В [README](https://github.com/vi-k/solo/blob/main/packages/solo/README.ru.md)
есть полное введение и подробные контракты.

Примеры используют отдельные модели приложений: `Ready` у плеера не является
`Ready` датчика. Вспомогательные классы состояний, событий и фейковые API здесь
не показаны: они лежат рядом с кодом, который извлекает эти примеры
из документа, — `tool/doc_snippets.py` в репозитории. Примеры проверены с bloc
9.2.1, bloc_concurrency 0.3.0 и локальным кодом solo 0.2.0. Трассы описывают
эти запуски, а не гарантируют время работы произвольного устройства.

## Соответствия

Основные соответствия API для того, кто знает bloc:

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| Класс события, `on<E>`, `add(E())` | Метод, возвращающий `Job<T>` |
| `EventTransformer` | `Policy` при добавлении `Job` |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | Контрольные точки отмены, например `ctx.wait` и `ctx.check` |
| `emit.onEach`, `emit.forEach` | `ctx.each(stream, onData)` |
| `state`, `stream` | `currentState`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder`; выбор части состояния делает приложение |
| `BlocListener` для результата операции | Ожидание `job.done` этой операции |
| `BlocProvider` | Выбранный способ владения или передачи зависимостей |
| `close()` | `close()` |
| `blocTest` | `test` и ожидание исхода `Job` |

`sequential`, `droppable` и `restartable` соответствуют `Policy.sequential`,
`Policy.droppable` и `Policy.restart`. `Policy.replace` удаляет ожидающую
работу, сохраняя работающую `Job`. Политики одновременного выполнения корневых
`Job` нет; для независимой параллельной работы используйте детей или отдельные
контроллеры.

## 1. Порядок обновлений общего состояния

Контроллер заметок отправляет заметку и обновляет список с сервера. Если
обновление началось до конца отправки, ответ может содержать старый список.
Публикация такого ответа после отправки удалит новую заметку из локального
состояния, даже если оба обработчика читают актуальное локальное состояние.
Нужно упорядочить целые операции, включая ввод-вывод.

### Первая попытка

Тип события на команду, обработчик на событие и на обоих — трансформер,
название которого и есть требование:

```dart
class SplitNotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  SplitNotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      emit(
        state.copyWith(notes: [...state.notes, e.note], uploading: false),
      );
    }, transformer: sequential());
    on<RefreshList>((e, emit) async {
      final serverNotes = await _api.list();
      emit(state.copyWith(notes: serverNotes));
    }, transformer: sequential());
  }
}
```

Итоговое состояние — `NotesState([n0], uploading: false)`: отправленной заметки
в нём нет. Почему — видно из порядка выполнения. Ниже записи самого сервера
и каждая публикация с событием, которое её сделало; локальный список поначалу
пуст, потому что его ещё не читали:

```text
UploadNote emits [], uploading: true
upload n1 starts
list reads [n0]
server receives n1 and holds [n0, n1]
UploadNote emits [n1], uploading: false
RefreshList emits [n0]
```

Обновление читает сервер в третьей строке — раньше, чем до сервера дошла
отправка в четвёртой, — и публикует этот ответ в шестой, уже после того, как
отправка опубликовала свою. Ответ старше того состояния, которое он затирает,
и никакое чтение локального `state` внутри обработчиков этого не покажет:
устаревший список лежит в ответе, а не в состоянии.

Трансформер упорядочивает события своей регистрации, а здесь их две, поэтому
оба обработчика по-прежнему работают одновременно. Это различие разобрано
в [обсуждении порядка обработчиков](https://github.com/felangel/bloc/issues/2790).

У тех же двух регистраций есть и другой способ потерять заметку, и в нём
трансформеры не участвуют вовсе. Запись в одну строку
`emit(state.copyWith(notes: await _api.list()))` вычисляет получатель `state`
до ожидания аргумента и публикует состояние, собранное до отправки. Этот
вариант заканчивается на `NotesState([n0], uploading: true)`, затирая заодно
и флаг отправки.

### Вторая попытка

Недостающая половина — одна регистрация на обе команды. Сама по себе она тоже
ничего не даёт. Умолчание — это одно поле, `Bloc.transformer`, и программа
вправе его присвоить; каждый `Bloc` читает его в момент создания, поэтому
присваивание распоряжается теми, кто создан после него, и не трогает уже живых.
Регистрация, не назвавшая трансформер, выполняет свои события конкурентно:

```dart
class ConcurrentNotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  ConcurrentNotesBloc(this._api) : super(const NotesState()) {
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
    });
  }
}
```

Состояние снова `NotesState([n0], uploading: false)`, и порядок совпадает
с приведённым выше строка в строку. Две попытки ошибаются по разным причинам —
там две очереди, здесь ни одной, — но по результату их не различить.

### Bloc

Обе половины вместе: одна регистрация общего типа и `sequential()` на ней:

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

Итоговое состояние — `NotesState([n0, n1], uploading: false)`, и в порядке
выполнения сдвинулась одна строка:

```text
UploadNote emits [], uploading: true
upload n1 starts
server receives n1 and holds [n0, n1]
UploadNote emits [n1], uploading: false
list reads [n0, n1]
RefreshList emits [n0, n1]
```

Теперь обновление читает сервер, который заметку уже держит, и публикует
не устаревший ответ. Ответ делает актуальным именно порядок; проверка
локального состояния по приходу ответа этого не дала бы.

Одна регистрация означает и один трансформер на все команды, которые в ней
обрабатываются: каждая операция, которой нужен этот порядок, должна
обрабатываться в ней же.

### Solo

Методы одного контроллера используют общую очередь корневых `Job`:

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
`join`, чтобы следующая корневая `Job` не читала сервер, пока отправка
продолжается. Обновление использует `ctx.wait`, который может прекратить
ожидание при отмене: в этом примере результат чтения разрешено отбросить.

Итоговое состояние тоже `NotesState([n0, n1], uploading: false)`, и порядок тот
же, что у воронки bloc выше — `list reads [n0, n1]` после `server receives n1`,
— только вместо типов событий в нём ключи `Job`.

Помнить здесь про трансформеры и порядок обработки событий не нужно:
трансформер некуда передать, планирование не выбирают. Корневые `Job`
контроллера выполняются по одной, в порядке добавления, и по-другому
не выполняются. Добавление ещё одного метода через очередь сохраняет этот
порядок: очередь одна на контроллер, а не на команду, и расположить методы так,
чтобы у двух из них оказалось по своей очереди, нельзя. Гарантия относится
к корневым `Job`; дочерние `Job` могут работать внутри родителя, а независимые
изменения устройства имеют отдельный путь, описанный в разделе 9.

В телах `Job` используйте методы ожидания контекста для проверки отмены
и правил состояния. Обычный `await` продолжает удерживать тело и очередь,
но не реагирует на отмену. Работа, запущенная без ожидания, может пережить
`Job`; нельзя считать, что она закончится до `close()`.

## 2. Ошибка наблюдателя при обновлении состояния

Диктофон запускает нативную запись, публикует `Recording` и включает индикатор
уровня. Наблюдатель телеметрии бросает ошибку при обработке обновления.
Операция диктофона должна завершиться независимо от отправки телеметрии.

### Первая попытка

Наблюдатель, который сообщает о каждом изменении, и контроллер, который ведёт
локальный журнал изменений. Оба написаны так, как сами хуки и предлагают, —
с вызовом `super` первой строкой:

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
Индикатор уровня не включается. Локальный журнал тоже пуст, и дело
не в неудачном порядке строк: документация самого `onChange` требует вызывать
`super.onChange` первым, а это ставит глобального наблюдателя впереди
собственной записи контроллера. Перенос записи до `super` спасает журнал —
в нём остаётся `[Recording]` — и больше ничего: состояние всё так же `Idle`,
индикатор всё так же не включён. Обработчик сообщает `telemetry unavailable`,
а та же ошибка наблюдателя в методе `Cubit` передаётся вызывающему этот метод
коду.

`Bloc` и `Cubit` публикуют состояние через `BlocBase.emit`. Он вызывает
`onChange` до изменения состояния, а исключение этого вызова передаёт
в `onError` и бросает дальше — в тот самый обработчик, который публиковал.
Отправка отчёта, ради которой наблюдатель и заведён, оказывается на одном пути
с операцией, о которой она отчитывается.

### Bloc и Cubit

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
`[native start, arm meter]` и добавляет `[Recording]` в журнал. Резервный
логгер получает ошибку телеметрии. Подход работает, если все соответствующие
колбэки наблюдения обрабатывают свои ошибки, а резервный логгер не бросает
исключение.

`onError` — не второе место для той же защиты. `emit` ловит исключение, отдаёт
его в `onError` и бросает дальше, поэтому переопределение там о сбое сообщает,
но не предотвращает его. С переопределённым `onError` и всё так же бросающим
наблюдателем выполнение заканчивается на `Idle` с невключённым индикатором —
ровно как незащищённый, — а о сбое сообщают дважды: из `emit` и из сломанного
им обработчика.

### Solo

Наблюдатель и хуки контроллера вызываются независимо. Исключение каждого хука
передаётся в текущую зону Dart:

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
  void onChange(SoloTransition<RecorderState> transition) =>
      _journal.note('${transition.current}');
}

final class TelemetryObserver extends SoloObserver {
  final Telemetry _telemetry;

  TelemetryObserver(this._telemetry);

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      _telemetry.send(transition.current);
}
```

`SoloObserver` получает `SoloBase<Object>`, поскольку наблюдает контроллеры
с разными типами состояний. Собственный хук контроллера использует его
конкретный тип состояния.

С бросающим наблюдателем выполнение всё равно достигает `Recording`, включает
индикатор, записывает `[Recording]` локально и заканчивается с `Done(null)`:
упавший хук не меняет ни исход `Job`, ни очередь. Ошибка телеметрии уходит
в `Zone.current.handleUncaughtError` — туда же, где приложение уже разбирается
с необработанными асинхронными ошибками, и больше никуда. Оставленная там без
обработки, она всё ещё может завершить приложение: изоляция хуков сохраняет ход
операции, но не берёт на себя отчётность.

## 3. Закрытие и отмена начатой работы

Пользователь отправляет сообщение в чат и уходит с экрана до ответа. Контроллер
должен запретить старой операции обновлять закрытый экран и добавлять
последующую работу после закрытия: ответа пользователь не видел, а отметка
о прочтении сказала бы серверу обратное.

### Первая попытка

Экрана нет, контроллер закрыт — и обработчик написан так, будто закрытие
на этом всё и заканчивает:

```dart
class UnguardedChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;

  UnguardedChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
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

С `sequential()` закрытие ждёт вызов API, который ещё выполняется, а состояние
после него — `ChatState(reply to hi)`: ответ опубликован в контроллер, который
уже закрывался. Последующий `add` затем бросает
`Bad state: Cannot add new events after calling close`, и эта ошибка приходит
в зону, пока `close()` ещё ожидают, а не вызывающему обработчик коду. Отметка
о прочтении к серверу не уходит — но лишь потому, что бросил тот самый `add`,
который её бы и отправил. Одна половина требования держится случайностью,
сломавшей другую.

В этих версиях поведение закрытия зависит от трансформера. С `sequential()`
вызов `close()` ждёт работающий обработчик, который ещё может публиковать
состояние, пока закрытие не завершено. С `concurrent` — тем самым, который
регистрация получает по умолчанию, — а также с `droppable` или `restartable`
вызов `close()` возвращается до конца тела, а отменённый emitter игнорирует
последующие записи. Ни один вариант не прерывает вызов API или оставшийся код
тела обработчика.

### Bloc

Этот последовательный обработчик проверяет закрытие после `await`:

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

Проверка предотвращает и обновление ответа, и событие `MarkReplyRead`. Закрытие
всё ещё ждёт возврата вызова API и обработчика. Отдельная регистрация
`MarkReplyRead` безопасна в этом примере, поскольку не меняет общее состояние;
иначе возникло бы ограничение порядка из раздела 1.

`add` после закрытия бросает `StateError`, поэтому вызывающий код, способный
поздно отправить событие, должен сам обработать этот случай. Метод `Cubit` тоже
продолжает выполнение после закрытия, но его прямой `emit` бросает исключение,
а не использует отменённый emitter обработчика.

Другой случай: неожидаемая future вызывает `emit` после обычного завершения
обработчика, пока `Bloc` ещё открыт. Это вызывает `assert` в отладочной сборке;
с отключёнными `assert` поздняя запись меняет состояние. Это ограничение
времени жизни разобрано
в [issue о завершённом обработчике](https://github.com/felangel/bloc/issues/2961).
Поддержка отмены также обсуждается
в [предложении отменяемых операций](https://github.com/felangel/bloc/issues/3069).

### Solo

`close()` прекращает приём `Job`, отменяет очередь, запрашивает отмену
работающей `Job` и ждёт её завершения, включая освобождение ресурсов:

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
  chat.send('bye'); // не выполнится: Job сразу вернётся с Cancelled(closed)
}
```

В этом теле `ctx.wait` бросает `Cancelled`, когда закрытие отменяет `Job`.
Обновление ответа и вызов `markReplyRead()` не выполняются. Этот метод поставил
бы отдельную корневую `Job` через `run` контроллера; она не является ребёнком
`send`.

С обычным `await` закрытие ждало бы ответа API. Последующий `ctx.emit` всё
равно отклонил бы отменённую `Job`. Вызовы после закрытия возвращают `Job`, уже
завершённые с `Cancelled(closed)`, поэтому проверка `isClosed` в месте вызова
не нужна.

`ctx` действителен, пока выполняется его `Job`, и у случая с bloc выше есть
здесь пара: тело, которое начало future и не стало её ждать, возвращается,
а future потом зовёт `ctx.emit` у законченной `Job`. Этот вызов бросает
`Bad state: Job(send) has already finished, cannot emit` — и в отладочной
сборке, и в релизной, — а состояние остаётся прежним. Там, где у bloc `assert`,
исчезающий в релизе, здесь обычная ошибка, которая не исчезает.

## 4. Выход из состояния загрузки при отмене работы

Отмена может происходить и при открытом контроллере. У индикатора обновления
два состояния, `Initial` и `Loading`. `StartRefresh` начинает работу;
`CancelRefresh` отменяет обработчик через ту же регистрацию с `restartable()`.
При отмене обновления индикатор должен вернуться в `Initial`. Пример
отслеживает только активность обновления; API не возвращает данных для
отображения.

### Первая попытка

Сброс принадлежит тому месту, где работа кончается, чем бы она ни кончилась, —
а это `finally`:

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

После `StartRefresh` состояние становится `Loading`. `CancelRefresh` заменяет
обработчик, но не публикует новое состояние. Future, которую вернул вызов API,
продолжает выполняться. Когда она завершается, `finally` вызывает старый,
отменённый emitter, который игнорирует `Initial`. Поэтому состояние остаётся
`Loading` даже после завершения вызова API. Сама отмена не бросала исключение
в старое тело.

### Bloc

Публиковать сброс из того обработчика, который действительно выполняется, —
из обработчика события отмены. Замените ветку `CancelRefresh` на:

```dart
if (event is CancelRefresh) {
  emit(const Initial());
  return;
}
```

Теперь состояние становится `Initial` при обработке события отмены. Поздний
`emit` старого обработчика по-прежнему игнорируется и не может перезаписать
более новое обновление. С `restartable` любой тип события этой регистрации
может заменить текущий обработчик; отдельная регистрация `on<CancelRefresh>`
сама по себе не отменит `StartRefresh`.

### Solo

Сброс привязывается к итоговому исходу операции:

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

  Job<void>? cancelRefresh() {
    final refresh = lastJobWhere((job) => job.key == 'refresh');
    unawaited(refresh?.cancel());
    return refresh;
  }
}
```

`cancelRefresh()` находит работающее обновление по его ключу и отменяет, так
что для отмены экрану нужен только контроллер — как на стороне bloc для
отправки `CancelRefresh` нужен только сам `Bloc`. Отдаёт он ту самую `Job`,
которую отменяет, а не future, — по той же причине, по которой её отдаёт
`refresh()`: `controller.cancelRefresh();` — законченное предложение, и проекту
с включённым `discarded_futures` придраться не к чему. Кому нужен исход, тот
дожидается `controller.cancelRefresh()?.done`, а `null` там означает, что
отменять было нечего.

`lastJobWhere` просматривает очередь с конца и только потом берёт работающую
`Job`, то есть отвечает ожидающим обновлением, если оно есть. Этому методу
нужен именно такой порядок: обновление оказывается в очереди только потому, что
`refresh()` вызвали второй раз, а `Policy.restart` в тот же момент отменила
работающее. `ctx.wait` прекращает ожидание API, а `onCancel` возвращает
`Initial` до продвижения очереди. Успешное обновление публикует `Initial`
из тела; `onError` сбрасывает индикатор при ошибке, при этом `Job` по-прежнему
сообщает `Failed`.

Момент обновления различается: обработчик события отмены в bloc меняет
состояние при своём выполнении, а обработчик состояния solo вызывается после
уборки отменённой `Job`. Ни один пример не останавливает саму операцию API.
Если независимое внешнее состояние делает `Job` solo недопустимой, её итоговые
обработчики состояния пропускаются; раздел 9 объясняет внешнее состояние,
а README описывает правила допуска.

## 5. Перезапуск одной операции в общей очереди

Плеер должен выполнять `play`, `pause` и `seek` по одной операции. При
перетаскивании ползунка ожидающие позиции устаревают, а работающая перемотка
должна остановиться до начала замены. `play` и `pause` сохраняют свой порядок.
API плеера в примере принимает токен и возвращает управление при отмене.

### Первая попытка

По регистрации на команду, а на ту, которую нужно уметь заменять, —
трансформер, названный по требованию:

```dart
class SplitPlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;

  SplitPlayerBloc(this._player) : super(const PlayerState()) {
    on<Play>((e, emit) => _player.play(), transformer: sequential());
    on<Pause>((e, emit) => _player.pause(), transformer: sequential());
    on<Seek>((e, emit) async {
      await _player.seek(e.position);
      emit(PlayerState(position: e.position));
    }, transformer: restartable());
  }
}
```

Пользователь запускает воспроизведение, протаскивает ползунок через три позиции
и жмёт паузу: `Play`, `Seek(1ms)`, `Seek(2ms)`, `Seek(3ms)`, `Pause` — подряд,
ничего между ними не дожидаясь.

Трасса устройства — `[play start, seek 1 start, seek 2 start, pause start,
seek 3 start, play end, pause end, seek 1 end, seek 2 end, seek 3 end]`,
а итоговое состояние `PlayerState(3ms)`, то есть ровно та позиция, которую
просил пользователь. Состояние верное, устройство — нет.

Не сработало сразу двое. Трансформер упорядочивает события одной регистрации
и ничего сверх того, а регистраций здесь три: `pause` ждёт другую `pause`,
но никогда — `play`. А `restartable()` отменяет emitter заменённого
обработчика, но не останавливает нативный вызов, который тот ждёт:
на устройство ушли все три перемотки, причём третья — уже после паузы.
До состояния дошёл только последний `emit`, поэтому по состоянию ничего этого
не видно.

### Вторая попытка

Одна регистрация на все три команды, чтобы очередь была одна:

```dart
class SerialPlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;

  SerialPlayerBloc(this._player) : super(const PlayerState()) {
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          await _player.seek(position);
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }
}
```

Теперь команды доходят до устройства в том порядке, в каком их нажимали,
а состояние снова заканчивается на `PlayerState(3ms)` — и в этот раз с ним
согласно устройство: оно действительно стоит на паузе на третьей позиции.
Трасса — `[play start, play end, seek 1 start, seek 1 end, seek 2 start,
seek 2 end, seek 3 start, seek 3 end, pause start, pause end]`.

Чего очередь не умеет — так это выбрасывать то, что перетаскивание уже
обессмыслило. Позиции 1 и 2 устарели, не успев начаться, и устройство
перематывает на каждую по очереди; `pause` ждёт за всеми тремя. Порядок
и замена — разные требования, и `sequential()` отвечает только на первое.

### Bloc

Одна очередь остаётся. Реализация добавляет к ней способ понять, какая
перемотка ещё нужна, и остановить ту, что уже выполняется:

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

`onEvent` выполняется внутри `add`, до того как событие попадёт в очередь: он
запоминает последнюю позицию и отменяет токен уже выполняющейся перемотки.
Остальное делает обработчик — отбрасывает позицию, которая больше не последняя,
и, будучи последовательным, ждёт возврата плеера перед продолжением.

Для позиций `1, 2, 3`, добавленных вместе, устройство получает
`[play, seek 3, pause]`. Если `seek 1` уже выполняется при появлении `seek 3`,
трасса выглядит так:
`[seek 1 start, seek 1 stopped, seek 3 start, seek 3 end]`.

Сравнения значений позиции недостаточно, когда перетаскивание повторяет
значение. Ввод `1, 2, 1` даёт `[play, seek 1, seek 1, pause]`. Чтобы такие
события различались, каждое нужно помечать при поступлении, а не сравнивать
по тому, что оно несёт, — эту схему целиком показывает раздел 7, вместе
с условием, которое к ней прилагается: события должны быть разными объектами.

Три вещи держит на себе приложение: какая позиция последняя (`_newestSeek`),
какой токен принадлежит выполняющейся перемотке (`_seeking`) и проверка после
`await`, которая не даёт отменённой перемотке опубликовать состояние. Команда
с другим правилом замены приносит в тот же обработчик свою ветку и свою
бухгалтерию. А `add` ничего не возвращает, поэтому у пропущенной или прерванной
перемотки нет исхода, который мог бы прочитать вызывающий код.

### Solo

Политика очереди задаётся при добавлении каждой `Job`, а `Ready` — рабочий тип
состояния, который принимают эти `Job` плеера:

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  Job<void> play() => run<Ready, void>(
        key: PlayerKey.play,
        (ctx) async {
          await ctx.join(_player.play);
          ctx.emit(ctx.state.copyWith(playing: true));
        },
      );

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
и запрашивает отмену активной. `ctx.onCancel` сразу передаёт запрос плееру.
`ctx.join` ждёт возврата операции, прежде чем текущая `Job` сможет закончиться,
а замена начаться. Если операция после отмены завершается ошибкой, тело
получает эту ошибку; исход `Job` остаётся отменённым.

Наблюдаемые трассы совпадают с успешными случаями bloc выше. `pause` и `play`
остаются в той же очереди с последовательной политикой по умолчанию. Токен
является локальной переменной тела `seek`, а вызывающий код может проверить
исход каждой перемотки, включая `Cancelled(manual)` для заменённого запроса.

## 6. Типизированные методы с выполнением через очередь

Карта предоставляет `moveTo` и `setZoom`. Вызывающий код должен дотягиваться
до них методами самого контроллера — со своими аргументами и без отдельного
класса на каждую команду, — а частые обновления при перетаскивании не должны
оставлять карту на устаревшей позиции.

### Первая попытка

`Cubit` напрямую поддерживает методы, возвращающие future, поэтому
типизированный интерфейс вызова достаётся даром:

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

Эти методы не упорядочивают вызовы. При разной длительности нативных вызовов
трасса может выглядеть так: `[moveTo 1 start, moveTo 2 start, moveTo 3 start,
moveTo 3 end, moveTo 2 end, moveTo 1 end]`. Состояние может закончиться
на любом из трёх запросов: здесь — на `MapState(1, z1)`, самом старом, потому
что именно он вернулся последним. В коде нет ничего, что решало бы, какой
победит.

Цепочка future может упорядочить вызовы; для отбрасывания устаревших запросов
нужен дополнительный учёт. Приложение также должно решить, как закрытие
дожидается этой цепочки или делает её недействительной; `Cubit` не управляет
этим автоматически.

### Bloc с функциями в качестве событий

Событие само может быть функцией. Одна последовательная регистрация выполняет
эти функции, а публичные методы дают типизированный интерфейс:

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

Теперь вызовы идут по порядку и заканчиваются с `MapState(3, z4)`. Обычный
класс события типизирован ничуть не хуже — `add(MoveTo(point))` проверяет
аргумент, как любой другой конструктор, — но тогда словарь команд живёт рядом
с контроллером, а не на нём, и каждой команде нужен свой класс. Замыкание
убирает и то и другое, а платой становится опознаваемость события: наблюдатель
этого `Bloc` получает на каждую из четырёх команд
`(Emitter<MapState>) => Future<void>` — без имени и без аргументов, которые
можно было бы записать. Все команды по-прежнему используют один трансформер,
а показанные методы возвращают `void`. Для возврата результата нужен
дополнительный механизм, как в разделе 8.

### Solo

Каждый метод возвращает `Job` и задаёт политику замены:

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

Трасса перезапуска:
`[moveTo 1 start, moveTo 1 stopped, moveTo 3 start, moveTo 3 end]`. Средний
запрос не начинается; первый останавливается до начала последнего. И карта,
и `MapState(3, z4)` отражают последний запрос. Вызывающий код может дождаться
операции через `job.value` или `job.done` либо обойтись без ожидания. Сама
возвращённая `Job` не является `Future`; правила обработки ошибок описаны
в README.

## 7. Удаление выбранной ожидающей работы

BLE-экран ставит в очередь подключение, чтение батареи и сигнала,
переименование и отключение. При закрытии экрана ожидающие чтения нужно
отбросить, а заказанное переименование должно завершиться до отключения.

### Первая попытка

Одна регистрация с `sequential()` упорядочивает все команды устройства. Через
API `Bloc` нельзя перечислить или удалить её ожидающие события, поэтому
обработчику приходится проверять, актуально ли ещё чтение, а самое очевидное
для проверки — флаг ухода: экран ставит его, когда уходит, и снимает, когда
возвращается.

```dart
class FlagDeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  var _leaving = false;

  FlagDeviceBloc(this._ble) : super(const DeviceState()) {
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          if (_leaving) return;
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          if (_leaving) return;
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
    super.onEvent(event);
    if (event is Disconnect) _leaving = true;
    if (event is Connect) _leaving = false;
  }
}
```

На уходе флаг работает:
`[_leaving = true, connect, rename kitchen, disconnect]`. Трасса несёт записи
в `_leaving` вместе с вызовами устройства, и запись стоит раньше их всех:
`onEvent` выполняется внутри `add`, а очередь разбирается, когда все пять
команд уже в ней. К тому времени, как обработчик доходит до первой, флаг
выставлен, и оба чтения пропускаются.

Чего этим не выразить — так это экрана, который вернулся раньше, чем разошлись
старые события. Те же пять команд, а за ними `Connect` открывшегося экрана:
`[_leaving = true, _leaving = false, connect, battery, signal, rename kitchen,
disconnect, connect]`. Обе записи ложатся раньше первого вызова устройства,
вторая снимает флаг, и чтения, поставленные ушедшим экраном, снова разрешены.
Оба чтения сделаны для экрана, которого уже нет.

### Bloc

Флаг говорит, где экран сейчас; очереди же нужно знать, какому экрану
принадлежит каждое событие. Эта версия записывает поколение экрана на каждом
событии:

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
    super.onEvent(event);
    if (event is Disconnect) _screen++;
    _stampOf[event] = _screen;
  }
}
```

Поколение увеличивается там же, где выставлялся флаг, и так же рано:
`[_screen = 1, connect, rename kitchen, disconnect]`. Разница в том, что
стоящие в очереди события сохраняют доставшуюся им метку, поэтому `Connect`
после них ничего не меняет для чтений:
`[_screen = 1, connect, rename kitchen, disconnect, connect]`.

Записи поколений являются состоянием приложения, связанным с очередью. События
всё равно доходят до обработчика, который должен проверять каждую отбрасываемую
команду. Схема с `Expando` также требует разных объектов событий. Если
открывшийся экран просит батарею тем же каноническим `const ReadBattery()`,
этот `add` перезаписывает метку стоящего в очереди чтения, и устаревшее чтение
всё-таки выполняется: `[_screen = 1, connect, battery, rename kitchen,
disconnect, connect, battery]`. Сигнал, отдельный объект, в трассу не попадает.
`add` не возвращает результат, указывающий на пропуск чтения.

### Solo

Контроллер может удалять подходящие `Job` прямо из своей очереди:

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

Вызовы устройства те же, но удаление происходит при вызове `disconnect`.
Удалённые `Job` чтения завершаются с `Cancelled(manual)`; вызывающий код может
наблюдать этот результат. Переименование остаётся в очереди, а отключение
выполняется после него. `removeWhere` не затрагивает уже работающее
подключение. Для удаления `Job` с `cancellable: false` из очереди нужен
`force: true`.

## 8. Ожидание конкретного запроса

Оплату могут вызвать и кнопка Pay, и запрос платформы. Обработчик платформы
должен вернуть результат своего заказа. Одновременные запросы одного заказа
должны использовать одну оплату; разные заказы должны выполняться
последовательно.

Наблюдение `Paid` через `BlocListener` может обслужить навигацию экрана,
но функции, отвечающей на запрос платформы, нужен результат именно этого
запроса. `Bloc.add` возвращает `void`; этот случай затронут
в [обсуждении ожидания событий](https://github.com/felangel/bloc/issues/1556).

### Первая попытка

Результату придётся ехать на самом событии — completer'ом, которого ждёт
вызывающий код. `droppable()` читается как политика объединения: пока списание
выполняется, второй запрос на него не должен начинать ещё одно.

```dart
class Pay extends CheckoutEvent {
  final Order order;
  final Completer<Receipt> result;

  Pay(this.order) : result = Completer<Receipt>();
}

class DroppableCheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;

  DroppableCheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      final receipt = await _api.pay(e.order);
      e.result.complete(receipt);
      emit(Paid(receipt));
    }, transformer: droppable());
  }

  Future<Receipt> pay(Order order) {
    final event = Pay(order);
    add(event);
    return event.result.future;
  }
}
```

Три запроса дают одно обращение к API, и ответ получает один вызывающий
из трёх: `[Receipt(for A), never answered, never answered]`. Двое других
продолжают ждать, когда всё остальное уже закончилось, и ждали бы столько,
сколько живёт процесс: `droppable()` отбросил их события, а completer
отброшенного события не завершает никто.

Второй из этих двоих показывает, что политика делает на самом деле: заказ B —
другая оплата, и его тоже отбросили. `droppable()` отбрасывает то, что пришло,
пока работает обработчик, а не то, что дублирует его.

### Bloc

`Completer` едет на событии, как и выше. Объединению не хватает карты
выполняющихся оплат: вызывающему код заказа, который уже выполняется, нужно
отдать completer той самой оплаты, а не отброшенное событие со своим:

```dart
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

`await bloc.pay(order)` теперь возвращает квитанцию. Три вызова по двум заказам
дают два обращения к API, а оба вызывающих один заказ получают его квитанцию.

`Completer` должен завершаться на каждом пути. `catch` вокруг `add` удаляет
запись из карты, когда закрытый `Bloc` отклоняет событие. `isCompleted`
предотвращает повторное завершение, если `emit` бросает ошибку после передачи
квитанции. Завершение результата до публикации `Paid` не даёт ошибке
наблюдателя заменить уже полученную квитанцию. Трансформер остаётся
`sequential()`: объединяет оплаты карта, а до очереди после неё доходят разные
заказы, которым нужен порядок, а не взаимное отбрасывание.

### Cubit

Метод `Cubit` может вернуть квитанцию напрямую, но одновременные вызовы
автоматически не объединяются и не упорядочиваются. Эта версия добавляет карту
выполняющихся оплат и цепочку future:

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

Она тоже даёт два обращения к API для трёх запросов по двум заказам. Обработка
закрытия остаётся неполной: `Cubit` не ждёт эту собственную цепочку. При
закрытии во время оплаты списание проходит, но последующий `emit(Paid(...))`
бросает `Bad state: Cannot emit new states after calling close`, и вызывающий
код получает эту ошибку вместо квитанции. Рабочая реализация должна согласовать
закрытие с цепочкой оплат и доставкой результата.

### Solo

Используйте идентификатор заказа в ключе и верните `Job` напрямую:

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

Обработчик платформы может разобрать исход этой `Job`:

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

`Policy.droppable` возвращает существующую ожидающую или работающую `Job` для
того же ключа заказа. Оба вызова получают общую квитанцию, а другой заказ
создаёт другой `Job`. Три запроса снова дают два обращения к API.

`cancellable: false` защищает всю операцию оплаты от обычной отмены, включая
закрытие контроллера после её старта. `join` ждёт результат API, а тело
публикует `Paid` до завершения с квитанцией. `close()` ждёт этого завершения.
Ошибки API по-прежнему дают `Failed`; состояние ошибки можно задать через
`run(onError: ...)`.

Эта `Job` принимает базовый `CheckoutState` без ограничения `keepWhile`.
Правила состояния могут отменить даже неотменяемую `Job`, поэтому более узкий
тип допустил бы отмену между отправкой списания и записью его результата.
Ни один метод ожидания не может отозвать списание у API, которое
не предоставляет механизм отмены.

`ctx.uncancellable` решает другую задачу: удерживает обычную отмену на один
шаг, затем применяет запрос. Он не гарантирует успешный исход `Job` для оплаты,
завершившейся во время этого шага. Для показанной неотменяемой `Job` он
не нужен.

Флаг также отклоняет ручную отмену, пока оплата стоит в очереди. Если
пользователь должен иметь возможность отменить оплату до начала списания,
моделируйте этот допуск отдельно. `close()` и `queue.clear(force: true)`
по-прежнему могут отбросить ожидающую оплату без списания, а вызов после
закрытия тоже не запускается. Эти случаи объясняют ветку `Cancelled`
обработчика платформы.

Общая `Job` в памяти объединяет только одновременные вызовы этого контроллера.
Повтор оплаты после перезапуска процесса или сетевого сбоя также требует
идемпотентного API оплаты; ни один пример этого не предоставляет.

## 9. Реакция на независимое внешнее изменение состояния

Датчик сообщает об аппаратном сбое, пока калибровка ждёт измерение. Контроллер
должен сразу отразить `Broken` и не дать калибровке позднее опубликовать поверх
него `Calibrated`.

### Первая попытка

Прямой `emit` у `Bloc` помечен `@visibleForTesting` и документирован для
внутреннего использования, поэтому слушатель вместо него добавляет событие
`HardwareFailed`. Одна регистрация на оба события — это то, чего требует раздел
1, и это то, что напишет читатель, только что усвоивший тот урок:

```dart
class FunnelSensorBloc extends Bloc<SensorEvent, SensorState> {
  final Sensor _hw;

  FunnelSensorBloc(this._hw) : super(Ready()) {
    _hw.onError = (error) => add(HardwareFailed(error));
    on<SensorEvent>((e, emit) async {
      switch (e) {
        case HardwareFailed(:final error):
          emit(Broken(error));
        case Calibrate():
          if (state is! Ready) return;
          await _hw.zero();
          if (state is! Ready) return;
          await _hw.sample();
          if (state is! Ready) return;
          emit(Calibrated());
      }
    }, transformer: sequential());
  }
}
```

Опубликованные состояния — `[Calibrated, Broken(cable unplugged)]`. Кабель был
уже выдернут, когда публиковался `Calibrated`: событие сбоя ждало своей очереди
за калибровкой, которую оно делает недопустимой, а каждая проверка в этом
обработчике читала состояние, которое никому не дали изменить. Экран, следящий
за контроллером, сообщает об успехе после сбоя устройства.

Порядок из раздела 1 и нужная здесь быстрота тянут в разные стороны, и одной
регистрацией не сделать и то и другое.

### Bloc

Выделите сбою отдельную регистрацию, чтобы он не ждал за калибровкой:

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
`Calibrated`. Калибровка проверяет состояние после каждого `await`, поскольку
событие сбоя не отменяет её обработчик или emitter: проверки — это то, что
вторая регистрация делает нужным, а не то, что она заменяет.

`Cubit` может отразить уведомление напрямую из метода наследника, но его
асинхронным операциям всё ещё нужны такие же проверки допустимости.

### Solo

`externalSetState` является защищённым методом для отражения изменения, уже
произошедшего в независимом источнике. Слушатель находится внутри наследника
контроллера:

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

Обычная `Job` для публикации `Broken` задержала бы этот факт в очереди
за калибровкой, которую он делает недопустимой. `externalSetState` сразу
обновляет состояние и проверяет работающие тела по их правилам. Здесь
`run<Ready, void>` разрешает калибровку только при `Ready`, поэтому внешний
сбой отменяет её с `Cancelled(rules: is not Ready)`.

Исключение относится к фактам вроде уже отключённого кабеля. Уведомление
с просьбой выполнить будущую работу должно поставить обычную `Job` в очередь.
Само получение данных из стрима не является основанием обходить очередь.
Остановите слушатель устройства перед закрытием любого из контроллеров;
фрагменты показывают регистрацию, а не зависящее от приложения снятие
слушателя.

При успехе `Job` может закончиться публикацией `Calibrated`, хотя это состояние
за пределами `Ready`. Собственный `emit` исключён из проверки правил;
последующая контрольная точка состояния отменила бы `Job`. Это позволяет
итоговый переход, но требует, чтобы рабочий тип охватывал всё продолжение
работы.

Уже начатый вызов датчика завершается в обоих примерах. `join` ждёт его, прежде
чем разрешить старт другой корневой `Job`. Устройство с токеном отмены можно
дополнительно остановить через `ctx.onCancel`, как в разделе 5. Итоговые
обработчики состояния `onError` и `onCancel`, если они заданы, запрещаются
несовместимым внешним обновлением, поэтому не перезаписывают `Broken` при
уборке.

## 10. Завершение начатой записи перед перезапуском

Обновление прошивки последовательно записывает части через BLE. Замена должна
остановить старый цикл и дождаться его текущей записи до отправки любой новой
части. API BLE в этом примере не может прервать уже принятую запись.

### Первая попытка

`restartable()` — та самая политика, которую требование и называет: новая
загрузка заменяет работающую. Цикл написан так, будто замена его останавливает:

```dart
class UnguardedFirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

  UnguardedFirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      var written = 0;
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        emit(Flashing(++written, e.chunks.length));
      }
    }, transformer: restartable());
  }
}
```

Устройство получает `[0, 1, 100, 2, 101, 3, 102, 4, 103, 5, 104, 105]`: оба
цикла продолжили писать, и две загрузки чередуются в эфире. `restartable()`
отменяет emitter заменённого обработчика, и отменённый emitter игнорирует
записи, но тело Dart, ожидающее `_ble.write`, этим не прерывается.
[Обсуждение restartable](https://github.com/felangel/bloc/issues/3349)
поясняет, почему отмена не прерывает ожидаемые future.

### Вторая попытка

Раз тело не прерывается, оно должно заметить само: `emit.isDone` истинно после
того, как emitter отменили.

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

Теперь части принадлежат одной загрузке: перезапуск посреди неё записывает
`[0, 1, 100, 101, …]`. Но устройство по-прежнему видит двух пишущих. Новый
обработчик начинается, пока старая запись ещё ожидается, и трасса —
`[write 0 start, write 0 end, write 1 start, write 100 start, write 1 end,
write 100 end, …]`: проверка распоряжается тем, что публикуется, а не тем, что
происходит в эфире.

### Bloc

Общая блокировка упорядочивает вызовы устройства:

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

Теперь трасса ставит конец каждой записи до начала следующей: `[write 0 start,
write 0 end, write 1 start, write 1 end, write 100 start, write 100 end, …]`.

Проверяйте `emit.isDone` и внутри блокировки, и после записи. Событие может
быть заменено во время ожидания блокировки; проверка только перед входом
позволила бы его устаревшей записи начаться позднее. Блокировка упорядочивает
доступ к устройству, а проверка emitter останавливает устаревшие обработчики.
Все операции с этим устройством должны соблюдать то же правило блокировки.

Отдельное событие `HardwareFailed`, публикующее `Broken`, не меняет `isDone`
этого emitter. В таком сценарии всё ещё нужны дополнительные проверки
состояния, чтобы остановить прошивку и сохранить `Broken`, как в разделе 9.

### Solo

`Job` занимает очередь контроллера до завершения тела и уборки:

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

`Policy.restart` запрашивает отмену и ставит замену в очередь. `join` ждёт
текущую запись; после успешной записи он обнаруживает отмену и бросает
исключение до следующей итерации. Замена начинается после завершения старой
`Job`. Наблюдаемая последовательность частей и отсутствие одновременных записей
совпадают со случаем bloc с блокировкой.

Внешнее состояние `Broken` также отменяет эту `Job`, поскольку больше
не соответствует `NotBroken`. Сценарий сбоя останавливается после `[0, 1, 2]`
с `Cancelled(rules: is not NotBroken)`. Проверка охватывает и замену, и потерю
допустимости состояния.

Если загрузка запускает детей через `ctx.run`, родитель ждёт и этих детей,
и освобождение их ресурсов. Работа, которой намеренно разрешено пережить `Job`,
может использовать `ctx.unattended`: её ошибки передаются хукам `Job`, но она
не удерживает очередь.

## 11. Освобождение ресурса, полученного после отмены

Аудиоредактор открывает нативный PCM-буфер для отрисовки волны. Пользователь
выбирает другой клип, пока декодирование ещё ожидается. Старую волну нужно
отбросить, но её буфер всё равно необходимо освободить. Эти вызовы декодера
могут безопасно выполняться одновременно, поскольку буферы независимы. Декодеру
с последовательным доступом нужно ожидание из раздела 10.

### Первая попытка

Проверка `emit.isDone` перед использованием результата предотвращает устаревшее
обновление волны, и после раздела 10 эта проверка ставится рефлекторно:

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

Состояние заканчивается на `Preview(2)` — верно, — а устаревший буфер
освобождается ноль раз: ранний возврат оставляет его сборщику мусора, который
не умеет освобождать нативный буфер. По состоянию об этом не сказано ничего.

### Bloc

Перенесите проверку внутрь `try`/`finally`, который владеет полученным буфером:

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

Оба варианта заканчиваются на `Preview(2)`. Первый освобождает текущий буфер
один раз, а устаревший ни разу; защищённый вариант освобождает каждый один раз.
`finally` выполняется и на отменённом пути — только поэтому устаревший буфер
вообще освобождается.

Обработчик продолжает ожидание после отмены emitter и освобождает буфер при его
получении. Это рабочий способ управления ресурсом; каждый выход после получения
должен оставаться внутри блока `try`. Дополнительные ресурсы или передача
владения требуют соответствующих решений об уборке. `Cubit` может использовать
тот же подход с собственной проверкой устаревшего запроса, поскольку у него нет
emitter обработчика и `emit.isDone`.

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

`ctx.wait` может закончить отменённую `Job` до конца декодирования. Поздний
буфер всё равно передаётся в `dispose`; буфер, полученный при активной `Job`,
освобождается во время её уборки. Поэтому новая `Job` может начаться, не ожидая
устаревшее декодирование, а каждый буфер будет освобождён.

Здесь нужен `dispose`, поскольку буфер временный, в том числе при успехе.
`discard` предназначен для ресурса, передаваемого вызывающему коду как успешный
результат; он не освободил бы этот временный буфер после успешного обновления
волны.

Защищённый bloc и solo оба записывают
`[open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1]`
и заканчиваются на `Preview(2)`.

Позднее освобождение может произойти после закрытия контроллера. В solo
`close()` заканчивается до появления устаревшего буфера; он освобождается,
когда декодирование наконец его возвращает. Используйте `join`, когда
и операция, и освобождение её ресурса должны закончиться до продвижения очереди
или закрытия контроллера.
