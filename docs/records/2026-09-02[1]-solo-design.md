> **Состояние на 2026-09-03:** реализована целиком и смержена в `main` по
> плану `2026-09-02[2]-solo-plan.md` (задачи 1–20, коммит на задачу, от
> `03c8255` до коммита задачи 20). Расхождения реализации со спецификацией
> перечислены в шапке плана. Ранее, 2026-09-02, спецификация была
> согласована владельцем целиком, и в тот же день по его решению стрим стал
> асинхронным (правки в 3.1, 4.8, 4.9, 6.2, 7.3).
> **Что это:** устройство и публичный API пакета `solo`, преемника
> `conveyor` 1.x.
> **Связанные записи:** `2026-09-02[2]-solo-plan.md` (план реализации).

# Solo: дизайн

## 1. Контекст

### 1.1. Откуда растёт

`conveyor` 1.x — движок последовательной обработки событий, написанный
владельцем для контроллера камеры. Он вырос из шести претензий к bloc:

1. нельзя управлять очередью событий;
2. если все события `sequential`, одно из них нельзя сделать `restartable`,
   не вынося в отдельную очередь;
3. при параллельной работе несколько событий меняют одно состояние;
4. после отмены код обработчика продолжает работать, пока сам не проверит
   `emit.isDone`;
5. нельзя дождаться завершения именно своего события: слушать `stream`
   можно, но нет гарантии, что изменение пришло от него, а не от
   параллельного;
6. снаружи хочется звать метод, а не создавать событие и делать `add`.

Ядро `conveyor` эти претензии закрывает: одна очередь, одно событие за раз,
привязка события к типу состояния, кооперативная отмена, `ConveyorResult` с
`done`. Что не удалось — порог входа: три generic-параметра у события,
обработчик-генератор с оговоркой «прервать можно только на `yield`», ленивые
цепочки провайдера состояния (`isA`, `test`, `map`, `use`, `it`, `check`),
три предиката правил, два флага неотменяемости, девять классов причин отмены,
собственный связный список.

### 1.2. Что показало боевое применение

Единственный потребитель 1.x — контроллер камеры на 2800 строк с 30
событиями (внешний проект, в нём владелец больше не участвует, у него своя
копия пакета). Разбор по фичам:

| Фича 1.x | Использований | Вывод |
|---|---|---|
| `state.it` | 59 | основной доступ к состоянию |
| `yield* state.run(child)` | 25 | дочерние события — основа, не экзотика |
| `state.log` | 23 | нужен |
| `checkStateBeforeProcessing` | 23 | реальные предусловия: `!isPreviewPaused`, `isStreamingImages` |
| `checkStateOnExternalChange` | 32 | всегда один и тот же `state is! Failed`, в 30 случаях избыточен: тип уже исключает `Failed` |
| `checkState` (везде) | 0 | ни разу |
| `isA<T>()` | 7 | сужение внутри задач с объединённым типом |
| `test`, `map` | 0 | ни разу |
| `unkilled` | 4 | init, close, pause, resume |
| `uncancellable` отдельно | 0 | только прокидывается |
| `queue.removeWhere` | 8 | «заменить ожидающие», всегда по группе ключей, текущее не отменяется |
| `lastEventWhere` | 5 | «не добавлять, если есть», тоже по группе |
| `queue.addFirst` | 2 | «выполнить сразу после текущей» |
| `queue.clear()` и `clear(force: true)` | 3 | иммунитет неубиваемых от обычной очистки нужен |
| `until(onCancelled)`, `..check()` | 2 | прообраз `guard` |

Отдельно: событие не умеет возвращать значение, поэтому путь к видеофайлу
вытаскивался через переменную замыкания.

### 1.3. Решения, принятые по ходу

- **Имя `solo`**: один исполнитель на сцене, остальные ждут. «Конвейер» в
  информатике — pipeline с параллельными стадиями, то есть обещание
  обратного. Кандидаты `turnstile` и `airlock` отклонены по звучанию и из-за
  слова `lock`. На pub.dev имя свободно (проверено 2026-09-02).
- **Тело задачи — `async`, не `async*`.** Возвращаемое значение, нет
  оговорки про `yield`, нет повисших детей без `yield*`.
- **Методы возвращают хэндл, не `Future`.** Вызов без `await` законен, как
  `bloc.add`, и не ловится `unawaited_futures` и `discarded_futures`.
  Ожидание — там, где нужно, через хэндл.
- **Параллельности в ядре нет.** Зафиксировано как принцип, см. 2.7.
- **Новое ядро в этом же репозитории**, без слоя совместимости: потребителей
  у 1.x нет. Семантика 1.x переносится, API — нет.

## 2. Принципы

1. **Одна задача за раз.** Корневые задачи контроллера выполняются строго
   последовательно из одной очереди.
2. **Гарантия владения.** Пока задача выполняется, никакая другая задача
   этого контроллера состояние не меняет. Между её `InProgress` и `Success`
   никто не влезет.
3. **Правила вместо условий в коде.** Задача объявляет рабочий тип и
   предикаты; движок сам не запускает её в неподходящем состоянии и сам
   отменяет, когда состояние перестало подходить.
4. **Отмена кооперативная, но неизбежная.** Прервать чужой `await` в Dart
   нельзя. Зато каждое обращение к контексту проверяет отмену, а `guard`
   не запускает действие зря и не ждёт зря.
5. **Хэндл, не `Future`.** У вызывающего всегда три ответа на вопрос «что
   стало с моим вызовом»: успех со значением, отмена с причиной, ошибка.
6. **Очередь — объект первого класса.** Наследник контроллера видит её и
   распоряжается ею. Политики — сахар для типового случая.
7. **Параллельность не в ядре.** Она живёт в трёх местах: дети внутри одной
   задачи (осознанно, внутри критической секции родителя), отдельные
   контроллеры на независимые состояния, внешние активности (стримы,
   листенеры), вносящие изменения через внешнюю установку состояния. Дорожки
   внутри одного контроллера — это два контроллера без гарантии и с общим
   объектом, который они портят друг другу, то есть третья претензия к bloc.
   Когда кажется, что нужна параллельность, обычно нужна отзывчивость:
   `first: true`, отмена текущей, частые точки отмены в длинной задаче.

## 3. Публичный API

Пакет `solo`, точка входа `package:solo/solo.dart`.

### 3.1. Контроллер

Иерархия линейная. База — движок и состояние, наследники добавляют способ
доставки изменений:

```
SoloBase<S>        движок, state, очередь, хуки, externalSetState, close
  └ Solo<S>        + stream                                   (пакет solo)
      └ SoloListenable<S> implements ValueListenable<S>
                   + value, addListener, removeListener      (пакет flutter_solo)
```

```dart
abstract class SoloBase<S extends Object> {
  SoloBase(S initialState);

  S get state;
  bool get isClosed;

  /// Точка доставки для наследников. В базе пуста.
  @protected @mustCallSuper
  void publish(S previous, S current) {}

  /// Создать задачу, не ставя в очередь. Для фабрик вроде _closeCameraJob().
  Job<T> job<W extends S, T>(
    Future<T> Function(JobContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,    // один раз, при взятии из очереди
    bool Function(W state)? keepWhile,   // непрерывно: изменения и чтения
    bool cancellable = true,
    String Function()? describe,
  });

  /// Поставить в очередь. Возвращает ту же задачу (или найденную при droppable).
  Job<T> add<T>(
    Job<T> job, {
    bool first = false,
    Policy policy = Policy.sequential,
  });

  /// Сокращение: add(job(...), policy: policy).
  Job<T> run<W extends S, T>(
    Future<T> Function(JobContext<S, W> ctx) body, {
    Object? key,
    bool Function(W state)? canStart,
    bool Function(W state)? keepWhile,
    bool cancellable = true,
    String Function()? describe,
    Policy policy = Policy.sequential,
  });

  @protected SoloQueue get queue;
  @protected Job<Object?>? get current;
  @protected Job<Object?>? lastJobWhere(bool Function(Job<Object?> job) test);
  @protected void externalSetState(S state);

  Future<void> cancelAll({bool force = false});
  @mustCallSuper
  Future<void> close();

  // Хуки экземпляра. Пустые по умолчанию, super звать не обязательно.
  void onStart(Job<Object?> job) {}
  void onFinish(Job<Object?> job) {}
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}
  void onLog(Job<Object?> job, String message) {}
  void onChange(S previous, S current) {}

  static SoloObserver? observer;
  static void Function(String message)? debug;   // отладка самого движка
}

/// Обычный контроллер для чистого Dart и StreamBuilder.
class Solo<S extends Object> extends SoloBase<S> {
  Solo(super.initialState);

  Stream<S> get stream;          // broadcast, async

  @override
  void publish(S previous, S current) {
    super.publish(previous, current);
    _controller.add(current);
  }

  @override
  Future<void> close();          // закрывает стрим после super.close()
}

enum Policy { sequential, droppable, replace, restart }
```

В пакете `flutter_solo`:

```dart
class SoloListenable<S extends Object> extends Solo<S>
    implements ValueListenable<S> {
  SoloListenable(super.initialState);

  @override S get value => state;
  @override void addListener(VoidCallback listener);
  @override void removeListener(VoidCallback listener);

  @override
  void publish(S previous, S current) {
    super.publish(previous, current);   // событие в стрим (микротаска)
    _notifyListeners();                  // слушатели сразу
  }

  @override
  Future<void> close();                 // отписывает всех после super.close()
}
```

`value` и `state` в одном классе — осознанный дубль: `value` есть потому,
что этого требует интерфейс, а не как второе имя. Наружу только чтение и
подписка, то есть `ValueListenable`, не `ValueNotifier`: сеттер `value` был
бы дырой в гарантии владения.

- `run<Ready, void>(...)` — каноническая запись. Два type-параметра — плата
  за возвращаемое значение: Dart не выводит часть параметров. Альтернатива:
  типизировать параметр замыкания, `run((JobContext<CameraState, Ready> ctx)
  async {...})`, тогда выводится всё. Проект может завести
  `typedef Ctx<W extends CameraState> = JobContext<CameraState, W>`.
- `lastJobWhere` ищет в очереди с конца, затем в текущей задаче.
- `cancelAll` = `queue.clear(force: force)` плюс `current?.cancel()`;
  `force` действует только на очередь.
- `key` — любой объект, сравнение через `==`. Метаданные задачи удобно
  вешать на enum ключа (в камере это `reopensCamera`).
- `state` живёт в базе: чтение состояния безопасно всегда, гарантию
  нарушает только запись. Методы наследника читают его напрямую
  (`if (state is! Ready) return`), хуки получают его в `onChange`, контекст и
  `emit` говорят на языке «state». Наследники различаются только доставкой.
- Цепочка линейная, а не вилка от базы: Flutter-контроллер сохраняет
  `stream` (`where`, `distinct`, подписка в `initState` ради навигации по
  `Failed`) и подходит везде, где ожидается `Solo`. Цена — один
  `StreamController` на экземпляр. Обратный случай, контроллер из чистого
  Dart-пакета внутри `ValueListenableBuilder`, требует адаптера при любой
  иерархии.
- `SoloBase` — точка расширения «принеси свою доставку»: signals,
  riverpod-нотификатор, что угодно поверх `publish`.
- Ядро не зависит от Flutter, поэтому `ValueListenable` реализует только
  `flutter_solo`: `implements` в Dart номинальный.

### 3.2. Задача

```dart
abstract interface class Job<T> {
  Object? get key;
  String describe();
  int get level;                     // 0 — корневая
  bool get isChild;                  // level > 0
  bool get isQueued;
  bool get isRunning;
  bool get isFinished;
  bool get isCancelled;

  Outcome<T>? get outcome;           // синхронно, null пока не завершена
  Future<Outcome<T>> get done;       // никогда не бросает; `await job.done;` законно
  Future<T> get value;               // бросает Cancelled или ошибку
  Future<void> get whenCancelled;    // в момент отмены, не дожидаясь тела
  Future<void> cancel();             // ждёт реального завершения
}

sealed class Outcome<T> {}

final class Done<T> extends Outcome<T> {
  final T value;
}

final class Failed extends Outcome<Never> {
  final Object error;
  final StackTrace stackTrace;
}

final class Cancelled extends Outcome<Never> implements Exception {
  final CancelReason reason;
  final bool started;            // false — удалена из очереди до старта
  final String? description;     // 'is not Ready', 'canStart', 'keepWhile', ...
  final StackTrace? stackTrace;  // откуда пришла отмена
  const Cancelled([String? description]);   // единственный публичный конструктор
}

enum CancelReason { manual, rules, closed, parent, handler }
```

`Failed` и `Cancelled` наследуют `Outcome<Never>`, поэтому `switch` по
`Outcome<T>` с тремя ветками исчерпывающий.

### 3.3. Контекст внутри задачи

```dart
abstract interface class JobContext<S extends Object, W extends S> {
  W get state;                                  // отмена + тип + keepWhile
  T stateAs<T extends S>();                     // сужение, Cancelled при несовпадении
  void emit(S next);                            // только проверка отмены
  void check();                                 // после голого await
  Future<T> guard<T>(FutureOr<T> Function() action);
  Job<T> run<T>(Job<T> child);                  // ребёнком, сразу, в обход очереди
  void log(Object? message);                    // toString сразу, в onLog
  Job<Object?> get job;
}
```

`guard` принимает функцию, а не футуру: готовая футура означала бы, что
действие уже запущено до проверки. `FutureOr` — чтобы синхронное действие
тоже проходило проверку перед запуском. Перегрузок с аргументами
(`guardUnary` и т. п.) нет: они не покрывают именованные параметры, ухудшают
читаемость и экономят одну аллокацию на фоне вызова железа.

### 3.4. Очередь

```dart
abstract interface class SoloQueue {
  Iterable<Job<Object?>> get jobs;   // неизменяемое представление
  int get length;
  bool get isEmpty;
  bool get isNotEmpty;
  bool remove(Job<Object?> job, {bool force = false});
  int removeWhere(bool Function(Job<Object?> job) test, {bool force = false});
  int clear({bool force = false});
  Job<Object?>? lastWhere(bool Function(Job<Object?> job) test);
}
```

Без `force` неотменяемые задачи пропускаются молча. `force` действует только
на очередь: у выполняющейся неотменяемой задачи тело уже работает.

### 3.5. Observer

```dart
abstract class SoloObserver {
  void onCreate(SoloBase<Object> solo) {}
  void onStart(SoloBase<Object> solo, Job<Object?> job) {}
  void onFinish(SoloBase<Object> solo, Job<Object?> job) {}
  void onError(SoloBase<Object> solo, Job<Object?> job, Object error, StackTrace st) {}
  void onChange(SoloBase<Object> solo, Object previous, Object current) {}
  void onLog(SoloBase<Object> solo, Job<Object?> job, String message) {}
  void onClose(SoloBase<Object> solo) {}
}
```

Движок зовёт observer и хук экземпляра независимо, observer первым. Хукам не
нужен `@mustCallSuper`, забытый `super` в наследнике не отключает аналитику.
Observer — для сквозных вещей: аналитика, отправка ошибок, единый лог.

### 3.6. Модификаторы классов

| Тип | Модификатор | Почему |
|---|---|---|
| `SoloBase`, `SoloObserver` | `abstract class` | пользователь наследует; без `base`, чтобы наследникам не навязывать `base`/`final` и не ломать `Mock implements CameraController` из привычки к `MockBloc` |
| `Solo`, `SoloListenable` | `class` | то же |
| `Job`, `JobContext`, `SoloQueue` | `abstract interface class` | наследовать незачем, реализации приватные; реализовать можно: моки, фейковый `JobContext` для теста тела задачи без движка |
| `Outcome` | `sealed class` | исчерпывающий `switch` |
| `Done`, `Failed`, `Cancelled` | `final class` | закрытая иерархия; публичный конструктор `Cancelled` с `final` совместим |
| `Policy`, `CancelReason` | `enum` | |

`base` на контроллерах отклонён осознанно: единственное, от чего он
защищает, ручная реализация движка через `implements`, в реальности не
происходит, а `Mock` живёт на `noSuchMethod` и добавления членов не боится.
Ослабить модификатор потом можно, ужесточить нельзя, но ужесточать не
понадобится.

### 3.7. Правила, не видные из сигнатур

- `cancellable: false` защищает от действующих лиц: ручной `cancel`, `clear`
  без `force`, отмена родителя, `close`. Но не от реальности: если состояние
  перестало подходить по типу или `keepWhile`, задача отменяется всё равно,
  читать ей уже нечего. Поэтому неотменяемой задаче, которая должна пережить
  любое состояние, нужен базовый тип `S` и никакого `keepWhile`.
- `emit` доверяем, чтение проверяем. Излучённое состояние не проверяется
  против правил излучившей задачи, иначе `close` с `run<NotClosed>` и
  `emit(Closed())` отменял бы сам себя.
- `ctx.run(child)` возвращает хэндл, не значение. `await
  ctx.run(child).value` бросает, `switch (await ctx.run(child).done)` нет.
  Забытый `await` ничего не роняет.
- `add` в закрытый контроллер не бросает, а возвращает задачу с исходом
  `Cancelled(closed)`.
- Политика кроме `sequential` при `key == null` — `ArgumentError`, не
  `assert`: в release `null == null` истинно и `replace` вычистил бы все
  задачи без ключа.
- Из тела задачи видна вся поверхность наследника `Solo`, поэтому
  `ctx.solo` не нужен.

### 3.8. Пример использования

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Initial());

  Job<void> _setFocusPointJob(Offset point) => job<Ready, void>(
    key: Keys.setFocusPoint,
    canStart: (s) => !s.isPreviewPaused,
    describe: () => 'point: $point',
    (ctx) async {
      if (ctx.state.focusPointSupported) {
        await ctx.guard(() => hw.setFocusPoint(point));
      }
      ctx.emit(ctx.state.copyWith(focusPoint: point));
    },
  );

  Job<void> setFocusPoint(Offset point) {
    queue.removeWhere(
      (j) => j.key == Keys.setFocusPoint || j.key == Keys.resetFocusPoint,
    );
    return add(_setFocusPointJob(point));
  }

  Job<Photo> takePhoto() => run<Ready, Photo>(
    key: Keys.takePhoto,
    policy: Policy.droppable,
    (ctx) async {
      ctx.emit(ctx.state.copyWith(busy: true));
      final photo = await ctx.guard(() => hw.capture());
      queue.clear();
      ctx.emit(ctx.state.copyWith(busy: false));
      return photo;
    },
  );

  Job<void> close() {
    queue.clear();
    current?.cancel();
    return run<NotClosed, void>(
      key: Keys.close,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        ctx.emit(const Closing());
        await hw.close();
        ctx.emit(const Closed());
      },
    );
  }
}

// снаружи
camera.setFocusPoint(p);                 // без ожидания, линта нет
final photo = await camera.takePhoto().value;
switch (await camera.close().done) {
  case Done(): ...
  case Cancelled(:final reason): ...
  case Failed(:final error): ...
}
```

## 4. Движок и очередь

### 4.1. Состав

`lib/src/`: `solo_base.dart` (движок), `solo.dart` (`Solo` со стримом),
`job.dart`, `job_context.dart`, `queue.dart`, `outcome.dart`, `policy.dart`,
`observer.dart`. Очередь — `List<Job>`, связного списка нет.

### 4.2. Жизненный цикл задачи

`created` после `job()`, `queued` после `add`, `running`, `finished`.
Ребёнок из `ctx.run` минует `queued`. Повторный `add` или `ctx.run` уже
использованной задачи бросает `StateError`.

### 4.3. Цикл

`add` кладёт задачу в конец или в начало и, если сейчас ничего не
выполняется, планирует прокачку через `scheduleMicrotask`: вызывающий код
успевает закончить синхронную часть, в том числе добавить несколько задач и
поправить очередь до старта первой. Прокачка берёт первую задачу, проверяет
`state is W` и `canStart`. Провал: `Cancelled(rules, started: false)`,
`onFinish`, следующая. Успех: `current = job`, `onStart`, запуск тела. По
завершении тела ждём детей, фиксируем исход, `current = null`, `onFinish`,
снова прокачка через микротаску.

### 4.4. Когда проверяются правила работающих задач

Одно правило вместо трёх точек 1.x: **любое изменение состояния переоценивает
правила всех работающих задач, кроме той, которая это изменение сделала.**
Источник не важен: `externalSetState` или `emit` любой задачи. Переоценка идёт
от самых глубоких детей к корню. У кого `state is! W` или `keepWhile` вернул
`false`, тот отменяется сразу с причиной `rules`. Это сохраняет поведение
1.x, когда `emit` ребёнка отменяет родителя с узким типом, и объясняет, зачем
у родителей объединённые типы вроде `Initialized`. Сама излучившая задача
проверяется лениво: на следующем `ctx.state`, `check` или `guard`.

### 4.5. Механика отмены

`_cancel(job, cancelled)`:

- уже завершена: ничего;
- в очереди: убрать, исход `cancelled` с `started: false`, `onFinish`;
- выполняется, `cancellable: false`, причина от действующего лица (`manual`,
  `parent`, `closed`): ничего, `cancel()` вернёт `job.done`;
- иначе: запомнить причину, завершить `whenCancelled`, каскадно отменить
  детей с причиной `parent`. Тело продолжает работать до первого обращения к
  `ctx`. Когда тело и дети закончились, исход всегда та запомненная отмена,
  что бы тело ни вернуло и ни бросило.

Тело бросило `Cancelled` само, без отметки об отмене: исход
`Cancelled(handler)`. Сюда же попадает `Cancelled` ребёнка, долетевший через
`await child.value`. Любая другая ошибка: `Failed`, `onError`, `onFinish`.

### 4.6. Закрытие

`close()`: пометить закрытым; всем ожидающим `Cancelled(closed, started:
false)`, включая неотменяемые, с `onFinish` каждой; текущей `_cancel` с
`closed`, неотменяемую дождаться; закрыть стрим; завершить. Повторный `close`
возвращает ту же футуру. В 1.x `close` не дожидался неотменяемого процесса и
закрывал стрим у него под ногами — это чинится.

### 4.7. Политики в `add`

- `droppable`: ищем по ключу в очереди с конца и в текущей; нашли —
  возвращаем найденную (приведение к `Job<T>`), а новая завершается
  `Cancelled(manual, started: false, 'duplicate')`, чтобы ничей `done` не
  завис.
- `replace`: `removeWhere` по ключу без `force`, затем в конец.
- `restart`: то же плюс `cancel()` текущей с тем же ключом, не дожидаясь.

Группы ключей и «заменить, но не отменять» — через `queue` явно.

### 4.8. Порядок уведомлений

При любом изменении состояния, из `emit` или `externalSetState`, база
делает: записать состояние, `observer.onChange`, хук `onChange`,
`publish(previous, current)`, переоценка правил работающих задач. Всё
синхронно, состояние записано первым: сразу после `ctx.emit(x)` и
`solo.state`, и `ctx.state` дают `x`. `Solo.publish` зовёт `super` и
кладёт событие в асинхронный стрим: подписчики получат его на следующей
микротаске, в порядке изменений. `SoloListenable.publish` зовёт `super`,
затем слушателей в порядке подписки, синхронно. Итог: слушатели сейчас,
стрим следующей микротаской. Событие в стриме может быть старше `state`
на момент доставки: источник правды — `state`, стрим — история. Слушатель,
отписавшийся во время обхода, больше не вызывается; подписавшийся во время
обхода получит только следующее изменение.

Реентерабельность: `externalSetState` из хука `onChange`, observer или
слушателя `SoloListenable` вкладывает установку состояния в установку
состояния. Это допустимо: переоценка правил читает текущее состояние, а
не переданное, отмена идемпотентна. Слушатель стрима во вложенность не
попадает: он работает в своей микротаске.

`close()` у каждого уровня закрывает своё после `super.close()`: `Solo` —
стрим, `SoloListenable` — список слушателей.

### 4.9. Мелочи

`stream` — `broadcast()` без `sync`: синхронный контроллер бросает
`Bad state` при `add` из слушателя (проверено на Dart 3.13.0), а обходить
это пришлось бы отложенной публикацией; решение владельца от 2026-09-02.
`level` — глубина. Тестового миксина
нет: тесты делают наследника и зовут защищённый `externalSetState`.
`Solo.debug` — статическая функция для отладки движка, по умолчанию `null`.

## 5. Отмена и результат

### 5.1. Причины и стек-трейсы

`stackTrace` у `Cancelled` показывает не место, где задача умерла, а место,
откуда пришла отмена.

| `reason` | Откуда | `stackTrace` указывает на |
|---|---|---|
| `manual` | `job.cancel()`, `queue.remove`, `clear`, дубликат при `droppable` | вызов `cancel` или операции над очередью |
| `rules` | `canStart`, `state is! W`, `keepWhile`, `stateAs<T>` | `emit` или `externalSetState`, изменивший состояние; для `stateAs` — место вызова |
| `closed` | `close()`, `add` после закрытия | вызов `close` |
| `parent` | каскад от родителя | стек отмены родителя, тот же объект |
| `handler` | тело бросило `Cancelled` | место `throw` |

`description` уточняет внутри причины. `toString()` даёт
`Cancelled(rules: is not Ready)`.

### 5.2. Что бросается внутри тела

`ctx.state`, `stateAs`, `emit`, `check`, `guard` после отметки об отмене
бросают один и тот же экземпляр `Cancelled`, который потом лежит в
`job.outcome`. Пользовательский `throw Cancelled('...')` — сигнал, не исход:
движок создаёт исход с `reason: handler`, `started: true`, описанием из
брошенного и стеком из места `throw`.

### 5.3. Ошибка после отмены

Тело, уже отмеченное отменённым, бросило не `Cancelled`: исход не меняется,
ошибка идёт в `onError` и observer. Тело бросило `Cancelled` после отметки:
штатный путь, `onError` не вызывается.

### 5.4. `guard`

1. `check()`: если задача отменена или состояние не подходит, бросает
   `Cancelled`, `action` не вызывается.
2. Вызывает `action()`.
3. Ждёт результат наперегонки с `whenCancelled`. Отмена раньше — бросает
   `Cancelled`, перестаёт ждать.
4. Если брошенная футура позже завершится ошибкой, ошибка уходит в
   `onError` как ошибка после отмены.

`guard` гарантирует «не начнём зря» и «не будем ждать зря», но не «остановим
на полпути».

### 5.5. Родитель и отменённый ребёнок

- `await ctx.run(child).done` — ребёнок необязателен: `canStart` не прошёл
  или отменили, родитель продолжает. Это поведение `yield*` в 1.x.
- `await ctx.run(child).value` — ребёнок обязателен: `Cancelled` ребёнка
  долетает до тела родителя; не пойманный, делает родителя
  `Cancelled(handler, 'child <key>: ...')`. Ошибка ребёнка долетает как
  ошибка.

В обоих случаях `Failed` ребёнка вызывает `onError` независимо от того, кто
и как его ждал.

### 5.6. Отмена родителя

Дети получают `Cancelled(parent)` каскадом, глубокие первыми. Если тело
родителя стоит на `await child.value`, оно получает `Cancelled(parent)`
ребёнка и бросает дальше; исход родителя уже зафиксирован, брошенное
игнорируется. Неотменяемый ребёнок дорабатывает, родитель его ждёт.

### 5.7. Отмена до постановки в очередь

`cancel()` у задачи в состоянии `created` даёт `Cancelled(manual, started:
false)`. Последующий `add` или `ctx.run` бросает `StateError`.

### 5.8. `whenCancelled`, `value`, `done`

`whenCancelled` завершается в момент отметки. У задачи, завершившейся без
отмены, не завершается никогда. `guard` подписывается на него и отписывается
по завершении действия. `value` бросает `Cancelled` со стеком отмены или
ошибку с исходным стеком. `done` возвращает `Outcome<T>` и не бросает
никогда: ошибка внутри `Failed`, не в футуре.

### 5.9. Чего нет намеренно

Таймаутов: `guard(() => f().timeout(...))`. Принудительного прерывания тела:
невозможно в Dart.

## 6. Дети и внешнее состояние

### 6.1. Дети

- `ctx.run(child)` запускает сразу, в обход очереди: тело ребёнка исполняется
  синхронно до первого `await`. `child.level = parent.level + 1`.
- `canStart` ребёнка проверяется в момент `ctx.run`. Провал — уже
  завершённый хэндл с `Cancelled(rules, started: false)`, тело не вызывалось.
- Родитель завершён, только когда завершены тело и все дети. Проверок
  «повисших» детей и `StateError` из 1.x больше нет: забытый `await`
  означает, что родитель проживёт дольше.
- Параллельные дети разрешены: `Future.wait([ctx.run(a).value,
  ctx.run(b).value])`. Каждый `emit` переоценивает правила остальных
  работающих задач, включая родителя и брата.
- `emit` ребёнка идёт прямо в состояние. Фильтрации по типу родителя, как в
  стриме 1.x, нет: её заменяет переоценка правил родителя.
- Изнутри задачи «сделать сейчас» — только `ctx.run`. `add` изнутри законен
  как «сделать после меня» (в камере — `queue.addFirst` внутри `openCamera`),
  но ждать такую задачу нельзя: очередь заблокирована вами же. Движок это не
  детектирует.

### 6.2. Внешнее состояние

- `externalSetState(S next)` — защищённый метод базового класса.
  Устанавливает состояние, зовёт `onChange` и observer, пушит в `stream`,
  затем переоценивает правила всех работающих задач.
- Назначение: листенеры железа и плагинов, принудительные переходы
  (`Disposed` при утилизации, `Failed` при ошибке). Из UI-кода почти всегда
  нужна задача, а не это.
- Равенство не проверяется: каждый вызов — событие в стриме.
- Реентерабельно: хук `onChange`, observer или слушатель `SoloListenable`
  может позвать `externalSetState` внутри чужого `emit`; отмена
  идемпотентна. Слушатель стрима получает событие на следующей микротаске
  и во вложенность не попадает.
- `close()` состояние не трогает. Кто хочет `Disposed`, ставит его до
  `close`.

## 7. Тесты и пример

### 7.1. Стиль

`FakeAsync` со сдвигами 50/150/250 мс и проверкой упорядоченного журнала
событий целиком. Тестовая иерархия `TestState` с объединёнными интерфейсами
переиспользуется из 1.x. Журнал собирает тестовый observer.

### 7.2. Перенос из 1.x (118 сценариев в 17 группах)

| Группа 1.x | Судьба |
|---|---|
| State, WorkingState | как есть |
| Closing, 9 сдвигов | как есть, плюс сдвиги для неотменяемой текущей |
| externalSetState, 12 сдвигов и «Extremal» | как есть |
| checkStateBeforeProcessing | становится `canStart` |
| checkState | становится `keepWhile` |
| Queue | как есть, плюс `first: true` |
| Sequential, Droppable, Restartable, по 6 вариантов | дважды: через `Policy` и через явные операции с очередью |
| Inner events, 17 сдвигов | как есть, `yield*` → `ctx.run(...).done` |
| Check state on yield | «`emit` ребёнка переоценивает правила родителя» |
| State providers, 26 тестов на цепочки | 4 теста на `stateAs` |
| Debounce, 2 группы | уходят с фичей; рецепт через `Timer` в README |
| `linked_list_test.dart` | уходит со списком |

### 7.3. Новое

- ошибка после отмены: исход `Cancelled`, `onError` вызван;
- `cancellable: false`: `cancel` ждёт и не отменяет, `clear` пропускает,
  `force` снимает, `close` дожидается, `keepWhile` и тип отменяют;
- родитель ждёт детей, в том числе не ожидаемого явно и неотменяемого;
- `guard`: не запускает при отмене, перестаёт ждать, ошибка брошенной футуры
  в `onError`;
- `done`, `value`, `outcome`, `whenCancelled`; исчерпывающий `switch` по
  `Outcome<T>` как тест на компиляцию;
- политики: дубликат завершён, `restart` отменяет текущую, `ArgumentError`
  без ключа;
- повторный `add`, `add` завершённой, `cancel` до `add`;
- observer раньше хука экземпляра, не зависит от `super`;
- `add` после `close`, повторный `close`;
- `publish`: вызывается после `onChange` и до переоценки правил; наследник
  `SoloBase` без стрима получает все изменения;
- в `flutter_solo`: слушатели синхронно, стрим следующей микротаской,
  отписка во время обхода, отписка всех при `close`, `value == state`;
- источник стека для `manual` и `rules`;
- реентерабельность `externalSetState` из хука `onChange`: состояние
  свежее сразу после `emit`, стрим получает оба события по порядку;
- `log` с уровнем; `describe` в журнале.

### 7.4. Пример: фейковая камера

Отдельный пакет `example/` со своим `pubspec.yaml` и зависимостью на `solo`
по пути. `FakeCameraHardware` с асинхронными операциями и листенером,
меняющим состояние извне. `CameraController extends Solo<CameraState>` с
состояниями Initial, Preparing, Ready, Disposed, Failed и объединениями.
Задачи: `init`, `openCamera` с ребёнком `closeCamera` и восстановлением,
неотменяемый `closeCamera`, `pause`/`resume`, `setFocusPoint` с заменой по
группе ключей, `takePhoto` с `droppable`, `guard` и очисткой очереди,
возвращающий `Photo`, `dispose` через принудительное закрытие, ошибка
железа через `externalSetState(Failed)`. Тесты в `example/test/` гоняют
сценарий «зум, фокус, затвор, и тут закрытие». `bin/main.dart` печатает
журнал. README показывает куски из этого же кода.

### 7.5. Пакет `flutter_solo`

Обязателен с первого дня: без него у Flutter-пользователя нет
`ValueListenable`. Содержимое: `SoloListenable<S>` и тесты на порядок
уведомлений, отписку во время обхода и `close`. Виджеты (`SoloBuilder` с
селектором, `SoloListener` для побочных эффектов) — позже, см. раздел 10.
Где живёт пакет, отдельный репозиторий или `packages/` в этом, — открытый
вопрос, на ядро не влияет.

### 7.6. Проверки

`dart analyze` без предупреждений, `dart test` в корне и в `example/`.
`flutter test` в `flutter_solo`.

## 8. Что убрано из 1.x и почему

| 1.x | Судьба | Почему |
|---|---|---|
| `async*` и `yield` | `async` и `ctx.emit` | значение из задачи; нет оговорки про `yield`; нет повисших детей |
| `use` | `f(ctx.state)` | сахар без содержания |
| `map` | `ctx.emit(f(ctx.state))` | то же |
| `isA` в цепочке | `ctx.stateAs<T>()` | цепочка без потребителя не работала — ловушка |
| `test` в цепочке | `if` + `throw Cancelled()` | не использовалась |
| `checkStateOnExternalChange` | удалён | во всех 32 случаях избыточен |
| `checkStateBeforeProcessing`, `checkState` | `canStart`, `keepWhile` | те же две семантики, ясные имена |
| проверка нового состояния на `yield` | удалена | задача отменяла сама себя своим же `emit` |
| стриминг детей через родителя с фильтром типа | `ctx.run` + переоценка правил | проще, без `yield*` |
| `uncancellable` + `unkilled` | `cancellable` | `uncancellable` отдельно не использовался |
| 9 классов `Cancelled`/`Removed` | `Cancelled` + `CancelReason` + `started` | один тип для `catch`, один enum для `switch` |
| второй generic `Event` у конвейера | нет | задачи создаются через `run`, не наследованием |
| связный список | `List` | размеры малы, O(1) удаление не нужно |
| `Future.until`, `Debouncer` | `ctx.guard`, ничего | `until` — прообраз `guard`; debounce вне ядра |
| `onRemove`, `onCancel`, `onDone` | `onFinish` + `job.outcome` | меньше хуков |
| ленивый `String Function()` в `log` | нет | не использовался |
| `TestSetState` | нет | тесты делают наследника |

## 9. Миграция имён

| 1.x | 2.0 |
|---|---|
| `Conveyor<S, E>` | `Solo<S>`; во Flutter `SoloListenable<S>` |
| `ConveyorEvent<S, E, W>` + `queue.add` | `job<W, T>` + `add`, или `run<W, T>` |
| `state.it` | `ctx.state` |
| `state.isA<T>().it` / `.use(f)` | `ctx.stateAs<T>()` / `f(ctx.stateAs<T>())` |
| `yield x` | `ctx.emit(x)` |
| `yield* state.run(child)` | `await ctx.run(child).done` или `.value` |
| `state.log`, `state.check` | `ctx.log`, `ctx.check` |
| `f().until(state.result.onCancelled)` | `ctx.guard(() => f())` |
| `checkStateBeforeProcessing` | `canStart` |
| `checkState` | `keepWhile` |
| `unkilled: true` | `cancellable: false` |
| `event.result.done` | `job.done` |
| `result.isCancelled`, `.cancellationReason` | `job.isCancelled`, `job.outcome as Cancelled` |
| `queue.addFirst(e)` | `add(job, first: true)` |
| `lastEventWhere` | `lastJobWhere` |
| `ExternalSetState` mixin | защищённый `externalSetState` |
| `onChanged(current, previous)` | `onChange(previous, current)` |

## 10. Отложено, вне рамок 2.0

- Генераторная обёртка `runStream` поверх `async`-ядра.
- Утилита композиции состояний нескольких контроллеров для UI.
- Пауза очереди (пункт TODO 1.x).
- `Policy.debounce(duration)`.
- Типизированный ключ `Solo<S, K>`.
- Виджеты в `flutter_solo` сверх `SoloListenable`: `SoloBuilder` с
  селектором по части состояния, `SoloListener` для побочных эффектов вроде
  навигации по `Failed`.

Пункты TODO 1.x, вошедшие в дизайн: запрет двойного запуска задачи
(`StateError`), неотменяемый ребёнок делает ожидание родителя неизбежным
(структурное завершение), тесты на ошибку после отмены, на `describe`, на
неотменяемые задачи, на незавершённых детей.

## 11. Решения по открытым вопросам

Приняты владельцем 2026-09-02:

- Первая версия `solo` — `1.0.0`. Имя новое, `2.0.0` намекало бы на
  несуществующую `solo` 1.x, `0.x` читается как «не готово».
- Папка репозитория переименовывается в `solo` владельцем между сессиями.
- `flutter_solo` живёт в этом же репозитории: монорепозиторий с
  `packages/solo` и `packages/flutter_solo`. Переезд ядра в `packages/solo`
  выполнен в тот же день.
- Публикация на pub.dev — по правилам `AGENTS.md`, отдельным решением.
