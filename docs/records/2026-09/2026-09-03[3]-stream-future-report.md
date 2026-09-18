> **Состояние на 2026-09-03:** разведка сделана, решение за владельцем:
> выносить ли исполнительное ядро `Job` в отдельный пакет до релиза
> `solo` 1.0.0. Кода не написано, `stream_future` не тронут.
> **Что это:** разбор пакета `stream_future` и оценка, может ли `Job` из
> `solo` заменить его, вместе с ценой выноса.
> **Связанные записи:** `2026-09-02[1]-solo-design.md` (раздел 5.4a про
> `onCancel`), `2026-09-03[2]-readme-review.md`.

# Разбор `stream_future` и вынос `Job` в отдельный пакет

Владелец спросил, стоит ли вынести `Job` в самостоятельный пакет, и назвал
две причины. Первая: соседний пакет `/Users/user/development/my/stream_future`
не доделан, живёт на `async*`, и `Job` мог бы его заменить. Вторая: если
`Job` станет самостоятельной сущностью, его можно будет запускать из
контекста solo через `ctx.run` и отменять по-настоящему, а не так, как
«отменяет» `guard`, который лишь перестаёт ждать.

## Что решено на 2026-09-03

Ничего. Разведка проведена, оценка ниже, решение отложено до ответа
владельца.

## Оценка и предлагаемый порядок работ

Ответ на первый вопрос: `Job` закрывает задачи `stream_future` практически
целиком после двух добавлений — канала прогресса и таймаута. Всё остальное
у `Job` либо уже есть и сделано лучше (исходы с причинами, `onCancel`,
потомки, отправка необслуженного отказа в зону), либо воспроизводить не
стоит (ручное вождение состояний, комбинаторные цепочки, реализация
`Future` самим хендлом — ровно те части, что в `stream_future` и не
доделаны).

Ответ на второй: solo сможет пользоваться вынесенным ядром, второй
реализации не потребуется. Но вынос — это не перенос файлов, а разрез
движка на две части: исполнительное ядро (запуск, отмена, потомки, исходы,
зона, наблюдатель) и слой состояния поверх него (`state`, `emit`,
`canStart`, `keepWhile`, очередь, политики). Тип состояния в ядро не идёт.

Параметр прогресса не заденет solo, если в ядре будет два типа: `Job<T>`
без прогресса, которым пользуется solo, и `ProgressJob<T, P>` с каналом
шагов, которым заменяется `stream_future`.

Что мешает прямо сейчас: `Job`, `JobContext` и `Outcome` объявлены через
`part of 'solo_base.dart'`; задача ходит в восемь приватных членов
контроллера, движок — в двенадцать приватных членов задачи. Через границу
пакета так нельзя, понадобится драйверный интерфейс: у задачи станет два
лица, одно для вызывающего и одно для планировщика. Плюс причины отмены
разъедутся (`manual`, `handler`, `closed` общие, `rules` и `parent` — про
solo), и `level`, `isChild`, `isQueued` останутся у подтипа solo.

Предлагаемый порядок, если владелец согласится:

1. Провести шов внутри solo, не создавая пакета: убрать из задачи знание о
   состоянии, вынести `_rejectStart`/`_rejectKeep` в движок, свести доступ
   движка к задаче к явному драйверному интерфейсу. Все тесты остаются
   зелёными, публичное API не меняется.
2. Вынести ядро в пакет и посадить `solo` на него.
3. Добавить в ядро канал прогресса и таймаут с причиной `timeout`.
4. `stream_future` архивировать, а не чинить.

Делать это дешевле до публикации `solo` 1.0.0: после публикации перенос
типов между пакетами станет ломающим изменением.

---

> **Состояние на 2026-09-03:** разведка по чтению кода и запуску тестов.
> В самом пакете `/Users/user/development/my/stream_future` ничего не менялось
> и не коммитилось. Для запуска тестов делалась копия в скретчпаде
> (`scratchpad/sf`) с заглушкой сломанной зависимости `team_logger`.
> **Что это:** разбор публичного API, семантики отмены, состояния тестов и
> сравнение с `Job` из `solo`.
> **Связанные записи:** нет.

## 0. Общие цифры

- `lib/` — 3370 строк в 23 файлах, весь код в одной библиотеке через `part`.
- `test/` — 12 532 строки, 6 файлов тестов + 12 файлов утилит.
- `example/` — 5 примеров в корне + подпроект `example/readme_examples/`.
- `pubspec.yaml`: `publish_to: none`, версия `0.1.0`, sdk `^3.9.2`,
  рантайм-зависимость одна — `meta`. Dev: `test`, `fake_async`, `lints`,
  `team_logger` (path `../team_logger`).
- `dart analyze` по `lib/` — чисто (4 `info`, ни одной ошибки).
  По всему репозиторию — 29 ошибок и 3 предупреждения, все вне `lib/`:
  9+9+2 в `example/readme_examples/bin/` (нет зависимостей `bloc`,
  `future_ext` — подпроект вообще не собирается), 9 в
  `test/utils/log_utils.dart` (разъехался API соседнего `team_logger`),
  3 в `analysis_options.yaml` (невалидная секция `exclude`).
- `example/next_example.dart` физически побит: с 190-й строки идёт мусор из
  несбалансированных скобок.
- Последние коммиты: `add ParentStep for next`, `rename Result -> Return`,
  `tests refactoring`. Работа брошена в середине рефакторинга переименований.

---

## 1. Публичное API

Экспортируется три библиотеки.

### `package:stream_future/stream_future.dart`

#### `StreamFuture<T> implements Future<T>`

```dart
factory StreamFuture(
  Stream<Progress<T>> Function() computation, {
  String? name,
  bool broadcast,          // по умолчанию true
  bool late,               // по умолчанию false: не стартовать до подписки
  void Function()? cancelComputation,
});
```

Тело — асинхронный генератор `async*`, который отдаёт `Step(...)` для
промежуточных шагов и ровно один `Return(value)` для результата. После
`Return` генератор дожимается до конца (`yield` работает как `return`),
`finally` выполняется.

Состояние и чтение:

| член | смысл |
|---|---|
| `String get name` | имя; прокси дописывают к нему свой суффикс (`fetch.timeout.or`) |
| `T get value` | значение при `Return`, бросает ошибку при `Fail`, `StateError` в остальных случаях |
| `StreamFutureState<T> get state` | текущее состояние |
| `Success<T> get lastStep` | последний успешный шаг (`Idle`/`Start`/`Step`/`Return`) |
| `bool get isBroadcast / isCompleted / isFailed / isCanceled / isClosed` | `isCompleted` — только `Return` или `Fail`; отменённая future НЕ считается completed, но считается closed |
| `Stream<StreamFutureState<T>> get progress` | поток всех состояний; подписка на него запускает работу |
| `Stream<StreamFutureState<T>> get debugProgress` | то же, но не влияет на работу и не считается подписчиком |

Режим «как Future»:

```dart
Future<R> then<R>(FutureOr<R> Function(T) onValue, {
  Function? onError,                                        // legacy-форма
  FutureOr<R> Function(Object, StackTrace)? onError2,
  FutureOr<R> Function(Canceled reason)? onCancel,
});
Future<void> get done;              // никогда не бросает
```

`await future` идёт через `then` и, если результат — отмена, бросает
`Canceled`. `done` ждёт завершения любым способом и молчит.

Режим «как Stream»:

```dart
Stream<T> asStream();               // только значение Return
Stream<NestedStep> asNested();      // все состояния, обёрнутые в NestedStep
Stream<StreamFutureState<T>> get progress;
Stream<StreamFutureState<T>> get debugProgress;
```

Это один и тот же объект в двух ролях, а не два типа. Практическое различие:
`broadcast: true` (по умолчанию) — можно слушать многократно, отписка ничего
не отменяет; `broadcast: false` — подписаться можно один раз (`await`
считается подпиской, поэтому `then` может быть только последним в цепочке),
зато работает backpressure (пауза подписки ставит генератор на паузу) и
отписка последнего слушателя отменяет работу.

Комбинаторы — все возвращают новую `StreamFuture` (прокси), исходная остаётся:

```dart
StreamFuture<R> map<R>(FutureOr<R> Function(T) convert);
StreamFuture<T> or(T fallback);                 // Cancel -> Return(fallback)
StreamFuture<T?> get orNull;                    // Cancel -> Return(null)
StreamFuture<T> onCancel(FutureOr<T> Function(Canceled) h);
StreamFuture<T> onError<E extends Object>(FutureOr<T> Function(E, StackTrace) h, {bool Function(E)? test});
StreamFuture<T> catchError(Function onError, {bool Function(Object)? test});  // @Deprecated
StreamFuture<T> whenComplete(FutureOr<void> Function() action);   // только Return/Fail
StreamFuture<T> whenCancel(FutureOr<void> Function(Canceled) action);
StreamFuture<T> log({onState, onValue, onError, onCancel});       // прозрачный проброс
StreamFuture<T> timeout(Duration timeLimit, {onTimeout, statesOnTimeout});
StreamFuture<T> unlink();                       // отмена потомка не отменяет источник
StreamFuture<T> as(String name);                // переименовать итоговую future
StreamFuture<T> asBroadcast();
StreamFuture<R> next<R>(Stream<Progress<R>> Function(T) computation, {cancelComputation, name});
Future<void> cancel({Canceled? reason});
```

#### `Step` / `Return` и вся иерархия состояний

```
StreamFutureState<T>            sealed, есть owner (имя создавшей future) и toString({mode})
├─ Idle          Success                     начальное состояние, наружу не отдаётся
├─ ParentStep    Success, _NestedStep        состояние источника в цепочке next()
├─ Start         Success                     старт; Start._withValue(v) в next()
├─ Step          Success, Progress           промежуточный шаг, Step(Object value)
│  └─ NestedStep Success, Progress, _Nested  состояние вложенной future
├─ Return<T>     Success, Progress, Done     единственный результат
├─ Fail          Done                        error + stackTrace, throwIt()
└─ Cancel        Done                        reason: Canceled, throwIt()
```

Маркерные интерфейсы: `Success<T>` (всё, что не отказ), `Progress<T>`
(`Step` и `Return` — то, что разрешено `yield`-ить из генератора),
`Done<T>` (`Return`, `Fail`, `Cancel` — терминальные).

Тип генератора — `Stream<Progress<T>>`, поэтому система типов сама
запрещает `yield Fail(...)` и `yield Cancel(...)` из тела: ошибка = `throw`,
отмена = просто `return` из генератора.

#### `StreamFutureController<T>` — «режим контроллера»

```dart
final class StreamFutureController<T> extends _StreamFutureController<T> {
  StreamFutureController({String? name, void Function()? cancelComputation, bool broadcast = true});
  void add(StreamFutureState<T> state);
}
```

Полноценная `StreamFuture` без генератора: состояния подаются руками. На нём
построена бо́льшая часть тестов (`controller_as_future_test.dart`,
`controller_as_stream_test.dart`). Переходы проверяются машиной состояний
`_checkState`: нельзя `Start` дважды, нельзя ничего после `Done`, нельзя
задать `Idle`, нельзя `Step` до `Start`, — иначе `StateError`.

#### `proxy` (внутренний механизм)

Наружу не экспортируется, но через него сделаны все комбинаторы. Всё, кроме
конструктора `StreamFuture` и `StreamFutureController`, — это
`_StreamFutureInternalProxy<S, T>`: подписывается на `source.progress`,
прогоняет каждое состояние через `_convertState`, публикует результат у себя.
Отсюда:

- `name` прокси = `'${source.name}.$_name'`;
- `broadcast` по умолчанию наследуется от источника;
- `propagateCancel` (по умолчанию `true`) — отмена прокси отменяет источник;
  `unlink()` = прокси с `propagateCancel: false`;
- флаг `_proxyEnabled`: когда прокси сам решает завершиться (отмена,
  `timeout` с обработчиком, `next` после `Return`), проброс из источника
  выключается.

#### `next` — цепочка

`a.next((value) => computation2(value))` возвращает новую future. Пока жив
источник, его состояния идут вниз обёрнутыми в `ParentStep`. Как только у
источника `Return(value)`, прокси отключает проброс, отменяет подписку на
источник и запускает второе вычисление со `Start._withValue(value)`. `Fail` и
`Cancel` источника пробрасываются как `ParentStep(state)` + сам `state`, то
есть цепочка обрывается тем же исходом.

#### `timeout`

```dart
StreamFuture<T> timeout(Duration timeLimit, {
  FutureOr<T> Function()? onTimeout,                                  // либо это,
  FutureOr<void> Function(EventSink<StreamFutureState<T>> sink)? statesOnTimeout, // либо это
});
```

Таймер заводится в `_onStart` — на первом состоянии, пришедшем от источника, —
и снимается при `_onSourceDone` и при `_cancel`. При срабатывании:

- без обработчиков — `_cancel(CanceledByTimeout(timeLimit))`, отмена уходит и
  в источник;
- с `onTimeout` — проброс выключается, источник и подписка отменяются
  параллельно, наружу отдаётся `Return(onTimeout())` (или `Fail`, если
  обработчик бросил);
- с `statesOnTimeout` — обработчику даётся `EventSink`, куда он может насыпать
  произвольные состояния (например ещё пару `Step`, а потом `Return`); если
  закрыть sink, не отдав `Done`, наружу уйдёт `Cancel(CanceledByTimeout)`.

#### Вспомогательное

- `StreamFutureConfig.toStringMode` + enum `StreamFutureToStringMode`
  (`short` / `showNestedOwner` / `showOwner` / `full`) — глобальная настройка
  того, как состояния печатаются.
- `package:stream_future/stream_future_testing.dart`: `StreamFutureDebug` —
  `logEnabled`, подменяемый `log`, счётчики `methodStart`/`methodDone`/
  `checkMethods`. Вся библиотека нашпигована вызовами внутри `assert(() {...})`,
  так что в релизе они выпадают.
- `package:stream_future/utils.dart`: `FutureOrExtension.map`,
  `handleMicrotasks()`, `handleEventLoop()`, `handleEventLoops(n)`.

---

## 2. Семантика отмены

**Чем отменяется.** `cancel({Canceled? reason})`. Внутри:
если состояние `Start` или `Step`, сначала дёргается хук
`cancelComputation` (он для внешнего процесса — оборвать http-запрос и
подобное), потом в поток кладётся `Cancel(reason)`, контроллер закрывается,
и только потом отменяется подписка на генератор. `await cancel()`
возвращается после того, как генератор действительно закончился.

**Гранулярность.** Отмена подписки на `async*`-генератор превращает
ближайший `yield` в `return`. То есть код между двумя `yield` всегда
доработает до конца — прервать `await` нельзя, и README это честно
признаёт. Проверено на живом примере: отмена в момент, когда генератор был
внутри второго `await`, не помешала ему допечатать всё до следующего `yield`.

**`finally`.** Отрабатывает всегда: и при `Return` (генератор дожимается
после отдачи результата), и при отмене. `cancel()` ждёт `finally`, потому
что `StreamSubscription.cancel()` на генераторе завершается только после
выхода из тела. Это заметно сильнее, чем `Future.any`/`CancelableOperation`,
и в этом весь смысл пакета.

**Отмена как третий исход.** `Cancel` — терминальное состояние, но
`isCompleted == false`, `value` бросает `StateError`, а `await future`
бросает `Canceled`. Пути не бросить: `orNull`, `or(fallback)`,
`onCancel(handler)`, `then(onCancel: ...)`, `done`.

**Способы попасть в `Cancel`:**

1. `cancel()` снаружи;
2. генератор просто `return`-нул, не отдав `Return` — `onDone` подписки
   кладёт `Cancel()`. То есть «передумал» — это отмена, а не ошибка;
3. тело бросило `Canceled` — в `_add` есть правило
   `Fail(Canceled) -> Cancel(reason)`, то есть `throw Canceled(...)` = самоотмена;
4. non-broadcast: отписался последний слушатель →
   `Cancel(CanceledBySubscription)`;
5. `timeout` → `Cancel(CanceledByTimeout(duration))`.

**Виды `Canceled`:**

```dart
base class Canceled implements Exception { Object? reason; StackTrace stackTrace; }
final class CanceledBySubscription extends Canceled;   // приватный конструктор
final class CanceledByTimeout extends Canceled;        // reason == Duration
```

`Canceled` объявлен `base`, поэтому пользователь может завести свой подвид и
передать его в `cancel(reason: ...)`. В TODO это записано как непроверенное
(«test for custom StreamFutureCanceled»).

**Родитель и дети.** Всё держится на подписках:

- отмена прокси (`.map`, `.or`, `.timeout`, …) по умолчанию отменяет
  источник (`propagateCancel: true`); `unlink()` это отключает;
- отмена источника едет вниз по цепочке как обычное состояние `Cancel` и по
  дороге конвертируется (`or` превратит его в `Return(fallback)`);
- вложенность делается через `yield* inner.asNested()` внутри внешнего
  генератора: состояния внутренней future заворачиваются в `NestedStep` и
  подмешиваются в прогресс внешней, а значение потом читается как
  `inner.value`. Отмена внешней обрывает `yield*`, что отменяет подписку на
  `inner.progress`; для non-broadcast внутренней это отменяет и её саму
  (`CanceledBySubscription`), для broadcast — только подписку.

**Найденная дыра.** Отмена самого внешнего прокси не проходит через его же
конвертацию: `_cancel` сначала ставит `_proxyEnabled = false`, а потом
публикует `Cancel` напрямую. Проверено репродьюсом:

```dart
final outer = f.orNull;
Future.delayed(d, outer.cancel);
await outer;   // бросает Canceled вместо того, чтобы вернуть null
f.cancel();    // а вот так — корректно возвращает null
```

То есть `orNull` защищает от отмены источника, но не от отмены самого себя.
Тот же дефект ловит красный тест `controller_as_future_test.dart / Call chain`
(`Expected: <null>, Actual: Canceled`).

---

## 3. Состояние тестов

`dart test` в исходном дереве **не запускается вообще**: все 6 файлов падают
на загрузке, потому что `test/utils/log_utils.dart` использует API соседнего
пакета `team_logger`, которого там больше нет (`Logger.init`,
`DefaultLogFormatter`, `LogNoFormatter`, `Logger.error`).

Чтобы получить настоящую картину, пакет скопирован в скретчпад, зависимость
`team_logger` выброшена, а тело `debugLoggerInit` заменено заглушкой, которая
по-прежнему ставит `StreamFutureDebug.log` (значит, внутренняя
проверка `methodStart`/`methodDone` продолжает работать). Исходное дерево не
тронуто.

**Результат: 109 тестов, 87 зелёных, 22 красных.**

Замечание про счёт: тесты параметризованы через `forEach*`, внутри одного
`test()` прогоняется десяток комбинаций (broadcast/non-broadcast, delay,
исход). Красный тест обрывается на первой упавшей комбинации, так что за
22 красными может стоять больше поломанных сценариев.

### Группировка падений по причинам

**A. Backpressure / ленивое вычисление в non-broadcast — не доделано (4).**
`future_test`: «Non-broadcast, lazy computation. Wait and subscribe»,
«…Wait, subscribe and unsubscribe»; те же два в `realtime_future_test`.
Ожидается, что при чтении через `StreamIterator` генератор продвигается ровно
на один шаг за `moveNext()` и стоит, пока не тянут. Фактически он убегает
вперёд: `Expected: [], Actual: ['start', 'step 1']`. Пауза/резюм подписки
доезжает до генератора не вовремя.

**B. Зависание — future никогда не завершается (7).**
`Bad state: No more timers` в `fakeAsync`, то есть событий больше нет, а
future всё ещё не готова. `future_test`: «Two futures. await second + await
first», «await first + await second», «await first + create second + await
second». `controller_as_future_test`: «next. transfer», «next. cancel»,
«next. cancel (middle unlinked)», «next. cancel (final unlinked)».
Вся ветка `next()` не работает — а это самый свежий, последний коммит.

**C. Сломан инвариант внутренней инструментации (2 уникальных теста).**
`Exception: method (controller.map, controller, _onSubscribe) cannot be done,
i.e. it did not start` — `methodDone` без парного `methodStart`.
`controller_as_future_test`: «await. No completion», «map. Handler return
result». Это не проблема логирования: библиотека сама поймала несимметричный
путь подписки/отписки в прокси (перевход или двойной вызов `_onSubscribe`).

**D. `timeout` не срабатывает через цепочку прокси (2).**
`controller_as_stream_test`: «Timeout. Without handler. Double timeout
(unlinked)» — ожидали `Cancel(CanceledBySubscription)`, получили
`Return(ok)`; «Timeout. State's handler add steps and close stream» —
ожидали `Cancel(CanceledByTimeout(100ms))`, получили `Return(ok)`. Таймер
заводится в `_onStart`, который вызывается только из `_addToProxy`, — и в
некоторых конфигурациях не заводится совсем.

**E. `cancelComputation` не останавливает генератор (1).**
`future_test / Cancel by timeout`: ожидали `['start', '* cancelComputation']`,
получили `['start', '* cancelComputation', 'step 1', 'done']`. После отмены
по таймауту генератор доработал ещё шаг и дошёл до конца.

**F. Дублируется `Start` в `progress` (1).**
`future_test / Normal flow`: `['Start', 'Start', 'Step(1)', ...]`. Буферный
повтор (`buffered()` отдаёт накопленные состояния новому подписчику) гонится
с живым событием.

**G. Realtime-контроллер как Stream не отдаёт вообще ничего (3).**
`realtime_controller_as_stream_test`: «Normal flow», «Error without handling»,
«Addition after completion» — ожидался полный лог состояний, фактически `[]`
(в третьем — только `'* onFinish'`). В настоящем, не поддельном асинхроне
слушатель, подписавшийся сразу после создания, всё пропускает.

**H. `orNull` обходится отменой внешней future (1).**
`controller_as_future_test / Call chain`: `Expected: <null>, Actual: Canceled`.
Разобрано в разделе 2.

**I. Тест не поспел за переименованием (1).**
`realtime_controller_as_future_test / 'then'. Handler worked successfully`:
ждёт строку `'StreamFutureCanceled'`, класс давно называется `Canceled`.
Единственное чисто косметическое падение из 22.

### Что это значит

Ядро (создание, шаги, `Return`/`Fail`/`Cancel`, простая отмена, `map`,
`onError`, `orNull`, `whenComplete`, `whenCancel` на прямом контроллере)
работает — это те 87 зелёных. Всё, что сверху — прокси-цепочки, `next`,
`timeout` в цепочке, backpressure, вложенность, — не доделано. TODO это
подтверждает: «tests: NestedStep», «test: timeout есть в 'as Stream', но нет
в 'as Future'», «нужно вернуть ParentStep».

---

## 4. Что есть в `stream_future`, чего нет в `Job`

### 4.1. Промежуточные шаги (прогресс) — главное расхождение

`yield Step(x)` + `progress` + `lastStep` + типизированная история состояний
с `owner`. У `Job` есть только `ctx.log(Object?)`, который уходит строкой в
`SoloObserver.onLog` и в хук контроллера. Ни потока прогресса на задании, ни
типизированного шага, ни «последнего успешного шага».

**Выражается ли через нынешний `Job`?** Нет. Не хватает канала прогресса:
что-то вроде `ctx.step(P value)` + `Stream<P> get steps` на `Job` (или
второй параметр типа `Job<T, P>`). Механически это `StreamController` на
задание плюс проброс в наблюдателя — порядка 50–100 строк, но это изменение
публичного API `Job`.

Заметим, что остальные состояния `stream_future` уже покрыты: `Start` ≈
`SoloObserver.onStart`, `Return`/`Fail`/`Cancel` ≈ `Outcome`,
`Idle`/`ParentStep`/`NestedStep` — внутренняя механика прокси, аналога не
требуют.

### 4.2. Таймауты

`timeout(d)`, `timeout(d, onTimeout: ...)`, `timeout(d, statesOnTimeout: ...)`.
У `Job` нет ничего.

**Выражается?** Частично и вручную:
`Timer(d, job.cancel)` плюс отмена таймера по завершении — три строки в
хелпере. Не хватает двух вещей: (1) готового `Job.timeout(...)` или
`ctx.withTimeout(...)`, (2) причины: в `CancelReason` нет `timeout`, и
отличить таймаут от ручной отмены можно будет только по соглашению
(`Cancelled.description == 'timeout'`). Вариант со `statesOnTimeout`
(подсунуть свои шаги вместо отменённых) без канала прогресса из 4.1
бессмыслен.

### 4.3. Вложенность и проксирование

`asNested()` (прогресс вложенной future подмешивается в прогресс внешней),
`next()` (цепочка), `unlink()` (не каскадировать отмену), `as()`
(переименование), плюс вся линейка комбинаторов `map`/`or`/`onError`/
`whenComplete`/`log` на самом хендле.

**Выражается?** По большей части — да, и лучше:

- вложенность: `ctx.run(child)` запускает потомка немедленно, родитель
  дожидается всех потомков, отмена родителя каскадирует в потомков
  (`CancelReason.parent`), а `Cancelled` потомка, прочитанный через
  `child.value`, отменяет родителя (`CancelReason.handler`). Это честная
  иерархия, а не обвязка над подписками, — и, в отличие от `stream_future`,
  она работает (в `stream_future` вся ветка `next` красная);
- цепочки: в `Job` их просто пишут телом задания —
  `final a = await ctx.run(jobA).value; final b = await ctx.run(jobB(a)).value;`.
  Никакой `next()` не нужен;
- `map`/`or`/`onError`/`whenComplete`: обычные `try`/`catch`/`switch` в теле
  или над `await job.done`. Сахар, а не возможность;
- `unlink()`: аналога нет, но «не каскадировать отмену» в `Job` — это просто
  корневое задание через `solo.add(...)` вместо `ctx.run(...)`;
- `as()`/`name`: покрывается `key` и `describe()`.

**Не выражается:** проброс прогресса потомка в прогресс родителя
(`NestedStep`). Это следствие 4.1 и имеет смысл только вместе с ним.

### 4.4. Режим контроллера

`StreamFutureController<T>.add(state)` — гонять машину состояний руками,
без генератора вообще. У `Job` задание всегда является функцией-телом.

**Выражается?** Прямо — нет. Эмулируется телом, которое ждёт `Completer`,
пополняемый снаружи. На практике это в первую очередь тестовая
приспособа: на ней держится половина тестов `stream_future` и почти нет
пользовательского кода.

### 4.5. `orNull` / `or(fallback)` / `onCancel`

**Выражается?** Да, без потерь:

```dart
final v = switch (await job.done) { Done(:final value) => value, _ => fallback };
```

`Job.done` возвращает `Outcome<T>` и никогда не бросает, `switch` по
`sealed`-иерархии исчерпывающий — это даже строже, чем `orNull`, потому что
заставляет обработать и `Failed`. Сахар `job.valueOrNull` /
`job.valueOr(fallback)` — расширение на пять строк.

### 4.6. Прочее по мелочи

- **`cancelComputation`** — хук на конструкторе. В `Job` есть
  `ctx.onCancel(callback)`, который строго мощнее: регистрируется и
  снимается в любой момент, возвращает функцию отписки, ошибки колбэка
  уходят в `onError`. Покрыто и лучше.
- **`late` (ленивый старт)** — покрыто: `SoloBase.job(...)` создаёт задание,
  не ставя его в очередь, и оно не выполняется, пока его не `add`/`run`.
- **Своя причина отмены.** `Canceled` — `base class`, пользователь заводит
  свой подвид и передаёт в `cancel(reason: ...)`. В `Job` `CancelReason` —
  закрытый enum, а произвольная информация помещается только в строку
  `description`. Небольшой, но реальный разрыв: нет типизированной полезной
  нагрузки в `Cancelled`.
- **`debugProgress`** — наблюдать за работой, не влияя на неё. В `Job`
  наблюдение и так не влияет (задание не привязано к подписчикам), так что
  сама проблема отсутствует.
- **`StreamFutureConfig.toStringMode`** — форматирование состояний для
  логов. Локальная мелочь.

---

## 5. Что есть в `Job`, чего нет здесь

- **`Outcome<T>` = `Done` / `Failed` / `Cancelled`, sealed.** Один тип,
  исчерпывающий `switch`, `done` никогда не бросает. В `stream_future`
  аналог рассыпан: `state` + `isCompleted`/`isFailed`/`isCanceled` +
  `value`, который бросает `StateError` на `Cancel`. Отмена в `Job` — первый
  класс, здесь — «состояние, которое надо не забыть проверить».
- **`CancelReason`** (`manual` / `rules` / `closed` / `parent` / `handler`)
  плюс `started` (успело ли задание стартовать) и `description`. В
  `stream_future` различаются только `Canceled`, `CanceledBySubscription`,
  `CanceledByTimeout`, и нет понятий «отменено правилами состояния»,
  «отменено закрытием контроллера», «отменено родителем».
- **`ignore()` и отправка необслуженного `Failed` в зону.** `Job`
  повторяет семантику необработанной ошибки `Future`: если исход `Failed`
  никто не наблюдал (`done`, `value`, `ignore`), через микротаску ошибка
  уходит в `Zone.handleUncaughtError` зоны создания. В `stream_future` этого
  нет вовсе — в TODO стоит пункт «Zones». Провалившаяся future, которую никто
  не ждёт, просто молча держит `Fail` в `state`.
- **`ctx.onCancel(callback)`** — регистрируется/снимается динамически,
  вызывается в момент пометки отмены (до того, как о ней узнает тело),
  ошибки колбэка идут в `onError` и не рушат отмену. Именно так отмена
  доводится до того, что действительно умеет останавливаться, — до
  cancel-токена драйвера, до `abort` http-клиента.
- **`canStart` / `keepWhile` / типизация `W extends S`.** Задание привязано
  к машине состояний контроллера: не стартует, если состояние не подходит, и
  автоматически отменяется (`CancelReason.rules`), если состояние перестало
  подходить по ходу работы. В `stream_future` понятия внешнего состояния нет
  вообще.
- **Очередь и политики** (`sequential`/`droppable`/`replace`/`restart`),
  `cancellable: false`, `close()` с отменой всей очереди, `key`, `level`,
  `isChild`, `SoloQueue`.
- **`SoloObserver`** — сквозные хуки `onCreate`/`onStart`/`onFinish`/
  `onError`/`onChange`/`onLog`/`onClose` на все контроллеры сразу.
- **`ctx.guard(action)`** — перестать *ждать* при отмене, при том что сама
  работа продолжается, а её поздняя ошибка уходит в `onError`, а не
  становится необработанной. В `stream_future` этого разделения нет.
- **`Job` намеренно НЕ является `Future`.** Вызвать метод без `await`
  законно. `StreamFuture implements Future<T>` — и отсюда растёт бо́льшая
  часть его сложности: `await` считается подпиской, non-broadcast нельзя
  слушать дважды, `then` обязан быть последним в цепочке, `Stream has already
  been listened to` вылетает на вполне естественном коде (проверено:
  `f.progress.listen(...)` вместе с `await f.orNull` на non-broadcast
  роняет программу).

---

## 6. Оценка

### Модели разной формы

`stream_future` — это **украшенная future**: одна операция, цепочка
комбинаторов, поток прогресса, отмена, доставляемая через механику подписок
на `Stream`. `Job` — это **единица работы внутри машины состояний**:
очередь, правила по состоянию, родитель/потомок, исходы. Пересечение ровно
одно, зато главное: «асинхронная операция, которую можно кооперативно
отменить, и у которой три исхода — значение, ошибка, отмена».

### На этом пересечении `Job` уже сильнее

1. **Гранулярность отмены у обоих одинаковая.** Ни тот, ни другой не умеет
   прервать `await`; тело в обоих случаях доезжает до ближайшей контрольной
   точки, и в обоих `finally` отрабатывает, а `cancel()` его дожидается.
   `async*` даёт контрольную точку бесплатно на каждом `yield`, `Job`
   требует `ctx.check()` / `ctx.state` / `ctx.guard(...)`. Но и `yield Step`
   автор обязывает писать руками после каждого `await` — README сам это
   признаёт («developers will forget»). То есть генератор покупает
   удобство, а не возможность, и платит за него всей машинерией подписок.
2. **Вся сложность `stream_future` — в этой машинерии, и именно она не
   работает.** 22 красных теста из 22 (кроме одного косметического) — это
   прокси, `_proxyEnabled`, порядок `_cancelSource` против
   `_cancelSourceSubscription`, буферный повтор, пауза/резюм, учёт
   подписок. У `Job` этого слоя нет вообще: отмена — это флаг
   `_pendingCancel`, набор колбэков и `Completer`.
3. **По всему, что вокруг результата, `Job` впереди:** исходы, причины,
   отправка в зону, `ignore`, `onCancel`, потомки, правила, очередь,
   наблюдатель.

### Чего `Job` не хватает, чтобы закрыть задачи `stream_future`

Это недостающий код, не расхождение моделей:

1. **Канал прогресса** — единственная по-настоящему отсутствующая
   возможность. `ctx.step(...)` + `Stream<...> get steps` на `Job`. ~50–100
   строк плюс изменение публичного API.
2. **Таймаут** — `Job.timeout(d)` / `ctx.withTimeout(d, ...)` и
   `CancelReason.timeout`. Десятки строк.
3. **Сахар на отменённый исход** — `valueOrNull`, `valueOr(fallback)`.
   Пять строк расширением.
4. **Типизированная нагрузка в `Cancelled`** — если владельцу нужны свои
   причины отмены. Мелочь.
5. **Проброс прогресса потомка в прогресс родителя** — только если сделан
   пункт 1 и это действительно нужно.

### Чего `Job` воспроизводить не стоит

`StreamFutureController` (ручное вождение состояний — это тестовая
приспособа), комбинаторные цепочки на хендле (`map`/`or`/`next` — в `Job`
это обычный код в теле, короче и понятнее), реализация `Future` самим
хендлом (источник ловушек), pull-based backpressure. Показательно, что это
ровно те части, которые в `stream_future` и не доделаны, и ни один внешний
код от них не зависит: пакет не опубликован (`publish_to: none`), примеры не
компилируются, тесты не запускаются.

### Про вынос `Job` в отдельный пакет

Тут есть подвох. `Job`, `JobContext`, `Outcome` объявлены как
`part of 'solo_base.dart'`, а `_Job` держит `SoloBase<S> _solo` и ходит в
него за `_cancel`, `_notifyStart`, `_notifyError`, `_notifyLog`,
`_setState`, `_running`, `_own`, `_onJobFinished`. Параметр состояния `S`/`W`
вшит в `JobContext` (`state`, `emit`, `stateAs`) и в правила
(`canStart`, `keepWhile`). Отдельный пакет «просто про задания» потребует
разрезать движок на две части: **исполнительное ядро** (запуск, отмена,
потомки, исходы, отправка в зону, наблюдатель) и **слой состояния**
(`emit`, `state`, `canStart`, `keepWhile`, очередь, политики) поверх него.
Это настоящий рефакторинг, а не перенос трёх файлов. Но: этот же разрез
нужен и сам по себе, независимо от судьбы `stream_future`.

### Вывод

- **Может ли `Job` закрыть задачи `stream_future`?** Практически целиком —
  после добавления канала прогресса и таймаута. Отмена, `finally`, три
  исхода, вложенность, fallback у `Job` уже есть, и сделаны лучше.
- **Принципиальное расхождение моделей** ровно одно: `stream_future`
  доставляет отмену и прогресс через `Stream`-подписки и потому обязан быть
  `Future`; `Job` не является ни тем, ни другим и держит отмену явным
  состоянием. Расхождение в пользу `Job`.
- **Всё остальное — недостающий код**, и его немного.
- `stream_future` в нынешнем виде — не работающая альтернатива, а
  незавершённый эксперимент: тесты не собираются, 20% написанных тестов
  красные, вся ветка `next` не работает, примеры не компилируются, README
  наполовину состоит из шаблонных «TODO».

---

## 7. Намерения автора: `TODO.md`, `README.md`, `article_ru.md`

### Чего автор хотел добиться

Все три документа об одном. Тезис: **отменяемость асинхронного кода в Дарте
— иллюзия**. `Future.any` с `canceler`, `CancelableOperation`,
`emit.isDone` в bloc — всё это отменяет только *получение результата*, а
сам код продолжает работать: доделывает запросы, пишет в БД, шлёт метрики,
кидает исключения — уже в отрыве от реального потока программы. Отсюда
неотслеживаемые Uncaught exceptions.

Единственный штатный способ прервать асинхронный код в Дарте — генератор
`async*`: отмена подписки превращает `yield` в `return`, и код честно
прерывается с отработкой `finally`. Но у `Stream` нет `cancel()`, а у
`Future` — только один результат, поэтому пользы от единственного `yield`
мало.

Идея пакета: **разбить атомарную асинхронную операцию на шаги**
(`yield Step(...)` после каждого `await`) и оставить один результат
(`yield Return(value)`). Снаружи это выглядит как обычная `Future`, внутри —
как отменяемый генератор, а побочным призом идёт бесплатный прогресс:
пошаговый лог и отладка, из которых видно, на каком шаге всё сломалось.
Автор сознательно принимает цену: разработчик обязан не забывать писать
`yield Step(...)` — ровно та же претензия, которую он предъявляет к
`isCanceled`-флагам, но здесь забывчивость стоит только гранулярности, а не
корректности.

Отдельно и категорически: настоящий `Future.cancel` (через зоны или
изолятов, как в `cancelable_future`) автор считает архитектурно
неприемлемым — со ссылкой на dart-lang/sdk#1806 и на потерю контроля над
ресурсами, созданными внутри асинхронного кода.

### Что осталось недоделанным

По `TODO.md`:

- `StreamFuture.delayed` (отменяемая), `StreamFuture.value`,
  `StreamFuture.fromFuture`, `StreamFuture.fromStream` — конструкторов нет;
  `StreamFuture.sync` признан невозможным, потому что внутри всегда `async*`;
- **Zones** — работа с зонами не начата (а это то самое, что в `Job` уже
  есть в виде отправки необслуженного `Failed` в зону создания);
- тест на пользовательский подвид `Canceled` — не написан;
- `timeout` есть в режиме «as Stream», но не в «as Future» — то есть автор
  сам знал, что таймаут покрыт не везде (группа D красных тестов);
- тесты на `NestedStep` — не написаны;
- «нужно вернуть `ParentStep`» — сделано последним коммитом
  `add ParentStep for next`, и именно на этой ветке `next` теперь висят
  7 красных тестов;
- README: не написаны сравнение с `cancellable` и раздел про `try`/`finally`.

По `README.md`: секции «Features», «Getting started», «Usage», «Additional
information» — нетронутые шаблоны `dart create` со словом TODO. В разделе про
`CancelableFuture` оставлен пустой блок кода там, где должен был быть пример
потери контроля над ресурсами. Один абзац продублирован по-русски и
по-английски. В примерах используется старое имя `Result` вместо `Return`.

По `article_ru.md`: статья оборвана на середине второго примера — написано
вступление, разобран `Future.any`, и следующая фраза («Преобразование Future
в asStream с последующей отменой») висит без продолжения. Полный план статьи
лежит в `TODO.md`.

Общее впечатление: работа брошена посреди волны переименований
(`Result` → `Return`) и добавления `ParentStep`, до того как автор довёл до
зелёного ветку `next` и вложенность.
