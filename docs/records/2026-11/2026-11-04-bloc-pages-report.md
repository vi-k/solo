# Страницы о bloc: отчёт

> **Состояние на 2026-11-04:** задачи 1–4 плана сделаны — зонды
> по критерию отбора, состав разделов обеих страниц, стенд, страница ядра
> на двух языках и её входы; задачи 5–8 впереди.
> **Что это:** отчёт об исполнении `2026-11-04-bloc-pages-plan.md`: зонды
> сценариев `vs-bloc.md` под bloc, вердикт по каждому, состав страниц
> и находки для стенда.
> **Связанные записи:** `2026-11-03-bloc-pages-design.md`,
> `2026-11-04-bloc-pages-plan.md`.

## Зонды

Пакет зондов — вне репозитория, на bloc 9.2.1 и `bloc_concurrency` 0.3.0,
`solo` и `async_job` путём из дерева (`async_job` ещё
и в `dependency_overrides`). Каждый зонд — один файл в `bin/`, гоняется
`dart run --enable-asserts`. Код ответов bloc и контроллеров `solo` —
из `vs-bloc.md`, местами укороченный до того, что решает сценарий: стенд берёт
блоки страниц байт в байт, зонд — нет. Время в зондах реальное, поэтому
длительности ниже — порядок величины, а не числа для страницы; стенд считает их
на виртуальном времени.

Под bloc контроллер `solo` живёт в одной форме во всех зондах:

```dart
final class StreamedChat = ChatController with SoloStream<ChatState>;

final class _Started extends ChatEvent {
  const _Started();
}

class ControlledChatBloc extends Bloc<ChatEvent, ChatState> {
  ControlledChatBloc(this._chat) : super(_chat.currentState) {
    on<_Started>(
      (e, emit) => emit.forEach(_chat.stream, onData: (state) => state),
    );
    on<SendMessage>((e, emit) => _chat.send(e.text).done);
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

### Шаг 1. Перепроверка сценариев 3, 10 и 11

**3. Закрытие.** API — 50 мс на сообщение, «hi» в полёте, «bye» в очереди,
`close()` через 10 мс. `job` — текущая задача в поле
(`ctx.abandonable(() => _api.send(e.text))`), `close()` делает
`await _current?.cancel()` до `super.close()`, обработчик ждёт `job.done`;
`job+g` — то же с `if (isClosed) return;` после `done`; `solo` — форма выше.

```text
bloc  close 96ms, sent [hi, bye], reads 0, states [], zone []
job   close 56ms, sent [hi, bye], reads 0, states [reply to bye], zone [Bad state: Cannot add new events after calling close]
job+g close 53ms, sent [hi, bye], reads 0, states [], zone []
solo  close 3ms, sent [hi], reads 0, states [], zone []
```

Сходится с дизайном и с ревью плана (I2): задача не ждёт вызов «hi»,
но `sequential()` запускает «bye», и `close()` ждёт его вызов целиком. Без
`isClosed` ответ «bye» уходит в закрывающийся bloc, `add` в нём падает в зону.
Контроллер, закрытый первым, снимает и вызов, и очередь.

**10. Запись перед перезапуском.** Запись куска — 20 мс, четыре куска
на загрузку, загрузки куски `0…3`, `100…103`, `200…203`. `design` — обработчик
первым делом ждёт `await _flashing?.cancel()`; `locked` — `LockedFirmwareBloc`;
`chain` — цепочка из плана:

```dart
final previous = _flashing;
final job = _flashing = Job<void>((ctx) async {
  if (previous != null) await ctx.join(() => previous.done);
  var written = 0;
  for (final chunk in e.chunks) {
    await ctx.join(() => _ble.write(chunk));
    emit(Flashing(++written, e.chunks.length));
  }
});
await emit.forEach(watch(job), onData: (_) => state,
    onError: (_, _) => state);
```

`solo` — `FirmwareController` с `Policy.restart` под bloc. Вывод без меток
времени; `middle` — есть ли на проводе кусок средней загрузки:

```text
design  [0, 30] maxInFlight=1 middle=true [flash0, 0+, 0-, 1+, flash1, 1-, 100+, 100-, 101+, 101-, 102+, 102-, 103+, 103-]
design  [0, 30, 5] maxInFlight=2 middle=true [flash0, 0+, 0-, 1+, flash1, flash2, 1-, 100+, 200+, 100-, 200-, 201+, 201-, …]
locked  [0, 30, 5] maxInFlight=1 middle=false [flash0, 0+, 0-, 1+, flash1, flash2, 1-, 200+, 200-, 201+, 201-, …]
chain   [0, 30, 5] maxInFlight=1 middle=false [flash0, 0+, 0-, 1+, flash1, flash2, 1-, 200+, 200-, 201+, 201-, …]
solo    [0, 30, 5] maxInFlight=1 middle=false [flash0, 0+, 0-, 1+, flash1, flash2, 1-, 200+, 200-, 201+, 201-, …]
```

На `[0, 30, 0]` — те же четыре строки, на `[0, 30]` все четыре версии дают
`maxInFlight=1`: на двух загрузках гонка дизайна не видна. Провод цепочки
и контроллера совпадает с `LockedFirmwareBloc` кусок в кусок, поэтому довод
обоих разделов — «меньше правил»: ни `Lock`, ни `emit.isDone` внутри и после
записи. Зона пуста везде, и под `--enable-asserts` тоже.

**11. Ресурс после отмены.** Клип 1 декодируется 50 мс, клип 2 — 20 мс, второй
открывается через 5 мс; `guarded` — `GuardedPreviewBloc`, `job` —
`ctx.abandonable(() => _decoder.open(e.clip),
dispose: (buffer) => buffer.release())` под `watch`. Со вторым открытием
и с `close()` во время декодирования:

```text
guarded close=false [open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1] releases={2: 1, 1: 1}
job     close=false [open 1, open 2, ready 2, sample 2, release 2, ready 1, release 1] releases={2: 1, 1: 1}
guarded close=true [open 1, open 2, closed, ready 2, release 2, ready 1, release 1] releases={2: 1, 1: 1}
job     close=true [open 1, open 2, closed, ready 2, release 2, ready 1, release 1] releases={2: 1, 1: 1}
```

Трасса та же, каждый буфер освобождён ровно раз — довод дизайна «меньше правил»
держится.

### Шаг 2. Страница `solo`: сценарии 1, 4, 5, 7, 9

**1. Порядок обновлений общего состояния.** Загрузка заметки — 30 мс, список
с сервера читается в начале вызова и возвращается через 40 мс. Контроллер
раздела Solo под bloc с двумя регистрациями по умолчанию — форма первой попытки
`vs-bloc.md`, — каждая отдаёт команду контроллеру:

```text
1 bloc NotesState([n0, n1], uploading: false) zone=[]
1 solo NotesState([n0, n1], uploading: false) zone=[]
```

Трасса та же, что у одной регистрации с `sequential()`. Вердикт: раздел, довод
«меньше правил» — снято правило «все обновления общего состояния через одну
регистрацию с `sequential()`»: код, к которому bloc ведёт сам, становится
верным, потому что порядок держит очередь контроллера.

**4. Выход из загрузки при отмене.** Обновление — 50 мс; старт, отмена через 10
мс, затем два старта подряд через 10 мс:

```text
4 bloc at cancel Initial, states [Loading, Initial, Loading, Initial], api done 3 zone=[]
4 solo at cancel Initial, states [Loading, Initial, Loading, Initial, Loading, Initial], api done 3 zone=[]
```

Контроллер с `Policy.restart` и `ifCancelled` публикует `Initial` между
перезапусками: на экране мигает состояние, которого у bloc нет. Трасса хуже,
правил не меньше. Вердикт: таблица.

**5. Перезапуск внутри общей очереди.** Перемотка — 30 мс, play и pause — по 10
мс; ответ Bloc с `_newestSeek` и токеном против `PlayerController`
с `Policy.restart` по ключу под bloc:

```text
bloc [1, 2, 3] gap=0 [play, seek 3 start, seek 3 end, pause]
solo [1, 2, 3] gap=0 [play, seek 3 start, seek 3 end, pause]
bloc [1, 2, 1] gap=0 [play, seek 1 start, seek 1 end, seek 1 start, seek 1 end, pause]
solo [1, 2, 1] gap=0 [play, seek 1 start, seek 1 end, pause]
bloc [1, 3] gap=15 [play, seek 1 start, seek 1 stopped, seek 3 start, seek 3 end, pause]
solo [1, 3] gap=15 [play, seek 1 start, seek 1 stopped, seek 3 start, seek 3 end, pause]
```

На серии `[1, 2, 1]` проверка `position != _newestSeek` пропускает первое
`Seek(1)`: последнее равно ему по значению, и устройство перематывает
на секунду 1 дважды. Вердикт: раздел, оба довода — трасса лучше на более
жёсткой серии, и меньше правил: ни `_newestSeek`, ни поля с токеном,
ни проверки после `await`; токен остаётся, но отменяет его `ctx.onCancel`.

**7. Снятие выбранной работы из очереди.** `Ble` — фейк стенда `vs-bloc`:
connect 30 мс, остальное по 10, устройство отказывает тому, к кому
не подключено. Три версии: `DeviceBloc` с поколениями через `Expando`;
`DeviceController` под bloc с регистрацией на каждую команду по умолчанию;
тот же контроллер под одной регистрацией с `sequential()`:

```text
=== leaving
bloc                                    device [connect, rename kitchen, disconnect]
controller, a registration per command  device [connect, rename kitchen, disconnect]
                                        outcomes [battery Cancelled(manual), …]
controller, one sequential registration device [connect, battery, rename kitchen, disconnect]
=== shared const read
bloc                                    device [connect, battery, rename kitchen, disconnect, connect, battery]
controller, a registration per command  device [connect, rename kitchen, disconnect, connect, battery]
controller, one sequential registration device [connect, battery, rename kitchen, disconnect, connect, battery]
=== read after disconnect
bloc                                    device [connect, disconnect]
                                        zone [Bad state: battery: not connected]
controller, a registration per command  device [connect, disconnect]
                                        outcomes [connect Done(null), disconnect Done(null), battery Cancelled(rules: is not Connected)]
controller, one sequential registration device [connect, disconnect]
                                        outcomes […, ReadBattery Cancelled(rules: is not Connected)]
```

На сценарии «экран вернулся быстро» (`… Disconnect(), Connect()`) bloc
и контроллер с регистрацией на команду дают одно и то же:
`[connect, rename kitchen, disconnect, connect]`.

Вердикт: раздел, оба довода. Трасса лучше в двух более жёстких сценариях: общий
`const ReadBattery()` у bloc перезаписывает поколение, и устаревшее чтение
уходит в устройство, а чтение за отключением роняет зону; контроллер снимает
первое и отказывает второму по правилу состояния. Правил меньше: ни `Expando`,
ни поколения, ни проверки в обработчике.

Условие раздела — регистрация на каждую команду. Под одной регистрацией
с `sequential()` события ждут в очереди bloc, в очереди контроллера никогда нет
больше одной задачи, и `removeWhere` снимать нечего: устаревшее чтение уходит
в устройство. Эта версия — к ней ведёт словарь bloc, где порядок команд держит
`sequential()`, — первая попытка раздела. Отказ чтению за отключением держит
и она: правило состояния проверяется при старте задачи.

**9. Независимая смена внешнего состояния.** Отчёт строится 50 мс, два запроса,
отзыв сессии через 20 мс. `ReportController` раздела Solo с `externalSetState`
из колбэка `Auth.onRevoked`, под bloc с одной регистрацией `BuildReport`:

```text
bloc states=[SignedOut(signed out elsewhere)] built=1 outcomes=[] zone=[]
solo states=[SignedOut(signed out elsewhere)] built=1 outcomes=[Cancelled(rules: is not SignedIn), Cancelled(rules: is not SignedIn)] zone=[]
```

Трасса та же. Вердикт: раздел, довод «меньше правил»: ни события
`SessionRevoked` с его регистрацией, ни проверки `state is! SignedIn`
до и после `await` — правило `enqueue<SignedIn, void>` объявлено у команды,
и обе задачи кончаются `Cancelled(rules: is not SignedIn)`, которое видит
вызывающий.

### Шаг 3. Страница ядра: сценарий 9

Задача из поля: `SessionRevoked` отменяет её и публикует `SignedOut`,
обработчик `BuildReport` проверяет состояние до старта и публикует только
`Done`:

```text
bloc states=[SignedOut(signed out elsewhere)] built=1 outcomes=[] zone=[]
job  states=[SignedOut(signed out elsewhere)] built=1 outcomes=[] zone=[]
```

Трасса та же, а правил не меньше: проверка после `await` заменена полем
с задачей, вызовом `cancel()` в обработчике отзыва и разбором исхода. Вердикт:
таблица.

### Шаг 4. Мост состояний

Контроллер публикует `1, 2, 2, 3`, затем `4`, и `close()` bloc приходит
во время второй команды, после первого её состояния:

```text
controller [1, 2, 2, 3, 4]
bloc       [1, 2, 3, 4]
bloc.state 4 counter.closed true bloc.isClosed true close 15ms
zone []
```

Мост держит: bloc повторяет каждое состояние контроллера, не равное
предыдущему, — равное он отбрасывает сам, `SoloStream` равенство не проверяет;
`close()` bloc закрывает контроллер; зона пуста. Другой кандидат,
`_counter.stream.listen(emit)` в конструкторе, анализатор отвергает:

```text
warning - bin/bridge_emit.dart:13:35 - The member 'emit' can only be used within 'package:bloc/src/bloc.dart' or a test. - invalid_use_of_visible_for_testing_member
```

## Состав страниц

У страницы ядра три раздела после моста — порог дизайна пройден.

**`packages/async_job/doc/bloc.md`:**

1. The bridge.
2. Closing and cancelling in-flight work (3) — трасса лучше: `close()` не ждёт
   вызов в полёте; `isClosed` и очередь остаются на bloc.
3. Finishing an in-flight write before restarting (10) — меньше правил.
4. Releasing a resource returned after cancellation (11) — меньше правил.
5. Таблица: сценарии 1, 2, 4, 5, 6, 7, 8, 9.

**`packages/solo/doc/bloc.md`:**

1. The bridges.
2. Ordering updates to shared state (1) — меньше правил.
3. Closing and cancelling in-flight work (3) — трасса лучше.
4. Restarting one operation within a shared queue (5) — трасса лучше и меньше
   правил.
5. Removing selected pending work (7) — трасса лучше и меньше правил; первая
   попытка — контроллер под одной регистрацией с `sequential()`.
6. Reacting to an independent external state change (9) — меньше правил.
7. Finishing an in-flight write before restarting (10) — меньше правил.
8. Таблица: сценарии 2, 4, 6, 8, 11 (у 11 — ссылка на страницу ядра).

Сценарий 8 на странице `solo` не зондировался, план его не называет: вызывающий
ждёт свой запрос, а `add` bloc возвращает `void` и съедает `Job` контроллера —
та же причина, что у сценария 6. Таблица.

Порядок разделов — порядок `vs-bloc.md`. Задачи 5 и 6 плана делят разделы
`solo` так: задача 5 — мосты и закрытие, задача 6 — 1, 5, 7, 9, 10 и таблица.

## Находки для стенда

- **`SoloStream` нужен мосту, а у контроллеров `vs-bloc.md` его нет.** Блок
  контроллера берётся байт в байт, поэтому страница добавляет поток применением
  миксина:
  `final class StreamedChat = ChatController with SoloStream<ChatState>;` —
  и мост держит `StreamedChat`.
- **Служебное событие моста ломает исчерпывающий `switch`.** Если `_Started`
  входит в запечатанное семейство событий, обработчик bloc со `switch`
  по событию (`DeviceBloc`, `PlayerBloc`, `NotesBloc`) требует пустую ветку
  `case _Started():`. На странице `solo` ответ bloc и контроллер под bloc —
  разные классы; если они делят семейство событий, у ответа bloc появляется
  ветка, которой нет в `vs-bloc.md`. Стенду — либо своё семейство событий
  у каждой версии, либо мост вне семейства.
- **Реальное время в стенде врёт.** Первый прогон зонда записи на реальном
  времени показал кусок средней загрузки у контроллера: зазор в 5 мс плыл
  от дрожания таймеров. Стенд считает на виртуальном времени, `nowMs()`
  из `RUNNER` `tool/doc_snippets.py` (находка M2 ревью плана).
- **Порядок закрытия и трансформер моста** — находка I3 ревью плана; зонд
  закрытия выше закрывает контроллер первым, мост — под трансформером
  по умолчанию.
- **Задержки фейков.** Где фейк уже есть у стенда `vs-bloc`, стенд страниц
  берёт его задержки. Зонды чата и устройства шли на тех же: сообщение 50 мс,
  отметка о прочтении 10, кусок записи 20, connect 30, прочие команды
  устройства 10. У плеера и заметок зонды взяли свои: play и pause по 10 мс
  против 30, перемотка одним ожиданием 30 мс против шагов по 10, загрузка
  заметки 30 мс и список 40 против 40 и 60. Вердикты сценариев 1 и 5 поэтому
  держат драйверы задачи 6 на фейках стенда, а не этот отчёт. Зазоры загрузок —
  `[0, 30, 5]` и `[0, 30, 0]`.

## Задача 2. Стенд, мост и закрытие на странице ядра

Стенд `tool/bloc_snippets.py` пишет пакет `bloc_pages_check`: `async_job`
и `solo` путём из дерева, `async_job` ещё и в `dependency_overrides`, bloc
^9.0.0, `bloc_concurrency` ^0.3.0, правила анализа `async_job`. Семь драйверов
ядра, все под `dart run --enable-asserts`:

- `core_bridge_cancelled` — под `concurrent()`, `droppable()` и `restartable()`
  `close()` возвращается за 0 мс, задача `Cancelled`; у `restartable()` вторая
  загрузка отменяет первую;
- `core_bridge_sequential` — под `sequential()` `close()` идёт 190 мс, обе
  задачи `Done`;
- `core_bridge_value` — обработчик ждёт `job.value` задачи в поле, зона
  получает ровно один `Cancelled`;
- `core_closing_bloc` и `core_closing_job` — чат: «hi» в полёте, «bye»
  в очереди, `close()` через 10 мс; сторожа — зона пуста, `sent == [hi, bye]`,
  ни одного состояния после `close()`, ни одной отметки о прочтении,
  и длительность `close()`: у bloc `90 = 50 - 10 + 50`, у задачи `50` — остаток
  «hi» уходит, вызов «bye» остаётся;
- `core_closing_bloc_failed` и `core_closing_job_failed` — вызов падает, зона
  получает `Bad state: send: offline` в обоих.

Проверки страницы: `check_traces.py` — семь процитированных трасс, ни одной
мимо вывода; `check_doc_shape.py` и `check_links.py` зелёные.

Каждый сторож проверен мутацией страницы — генерация, прогон драйвера, возврат
страницы копией со сверкой `cmp`:

| Мутация ответа | Драйвер краснеет |
|---|---|
| без `await _sending?.cancel();` | `close took 90`: сторож «close must wait only for the queued call» |
| `break` вместо `Error.throwWithStackTrace` | зона пуста: «the failure must reach the zone» |
| без `if (isClosed) return;` | зона: `Bad state: Cannot add new events after calling close` |
| `restartable()` вместо `sequential()` | `close took 0`: тот же сторож длительности |

Решения по ходу:

- **Ключ блока `watch`.** Регулярное выражение `doc_blocks.py` не видит
  объявления `watch<T>(`, и блок адресуется слагом первой строки:
  `the-bridge/the-value-of-job-as-a-stream-c`. Ключ соседа в плане (находка M3)
  неверен: `watch` на странице `riverpod-and-bloc.md` — часть блока
  `a-handler-that-restarts/a-stream-that-cancels-the-job/SearchBloc`, и стенд
  требует, чтобы блок страницы входил в него подстрокой. Цена ошибки — ложная
  тревога стенда при правке соседа, не тихое расхождение.
- **`RUNNER`** — исполнитель стенда `adapter_snippets.py` с `nowMs()` поверх
  виртуальных часов, а не копия из `doc_snippets.py`, как в плане: тот несёт
  проверку `quoted`, которая принадлежит стенду `vs-bloc`. Цена ошибки — ноль,
  проверки трасс держит `check_traces.py`.
- **`Failed` ответа бросается заново** `Error.throwWithStackTrace`: так ошибка
  вызова доходит до `onError` bloc и зоны, как у `ChatBloc` без задачи,
  и сторож «ошибка дошла туда же» сравнивает одно с одним.
- **Две строки о падении — два блока `text`.** Драйверы `*_bloc_failed`
  и `*_job_failed` не соседи по алфавиту, и общий блок `check_traces.py`
  не нашёл бы подряд.
- **Тест зеркала локалей сайта красный до задачи 4.** Запись `async_job/bloc`
  и сама страница попадают на сайт в задаче 2, а перевод — в задаче 4;
  `build_site_test.py` требует, чтобы русская локаль повторяла английскую,
  и между этими коммитами краснеет на одной странице. Гейт в `main` видит
  только вершину ветки после слияния, где перевод уже есть; цена ошибки —
  красный тест у того, кто встанет на промежуточный коммит.

## Задача 3. Остальные разделы страницы ядра и итоговая таблица

`tool/check_links.py` пропускает страницу, названную в `LEADS_UP`, и её
перевод: `async_job/doc/bloc.md` ведёт на `vs-bloc.md` `solo` из итоговой
таблицы, по решению 144. Тест `test_a_page_that_answers_with_the_queue` держит
обе стороны: названная страница и её перевод проходят, другая страница ядра
с той же ссылкой — нет; второй тест держит сам перечень.

На странице два раздела сценариев 10 и 11 и таблица сценариев 1, 2, 4–9,
во вступлении — список разделов со ссылками. Четыре новых драйвера:

- `core_write_bloc` и `core_write_job` — `LockedFirmwareBloc` и цепочка, четыре
  куска по 20 мс на загрузку, загрузки через 0, 30 и 5 мс и через 0, 30 и 0;
  оба печатают одну и ту же строку на серию и требуют: провод
  `[0, 1, 200, 201, 202, 203]`, одна запись за раз, состояния
  `[1/4, 1/4, 2/4, 3/4, 4/4]`, к печати ни одной записи в полёте; у цепочки ещё
  исход каждой задачи `Done` или `Cancelled`;
- `core_resource_bloc` и `core_resource_job` — `GuardedPreviewBloc` и задача
  с `dispose`, клип 1 за 50 мс, клип 2 за 20 через 5 мс, и то же с `close()`
  через 10 мс; оба печатают одну строку на случай и требуют трассу,
  `Preview(2)` и одно освобождение на буфер.

Мутации страницы, каждая краснеет на своём стороже:

| Мутация | Драйвер краснеет |
|---|---|
| цепочка без `ctx.join` прежней задачи | `two writes overlapped`, на проводе кусок `100` |
| `await _ble.write(chunk)` без `ctx.join` | провод `[0, 1, 2, 3, 200, …]` |
| обработчик ждёт `await _flashing?.done` до того, как поставить свою задачу | `two writes overlapped`, на проводе кусок `100` |
| `LockedFirmwareBloc` без проверки `emit.isDone` внутри замка | на проводе кусок `100` |
| задача без `dispose` | трасса без `release 2` и `release 1` |
| `discard` вместо `dispose` | трасса без `release 2`: буфер задачи, кончившейся `Done`, остался |
| `GuardedPreviewBloc` с `release` вне `finally` | трасса без `release 1` |

Решения по ходу:

- **Проверка `emit.isDone` после записи у `LockedFirmwareBloc` трассы
  не меняет.** Мутация без неё зелёная: `emit` отменённого эмиттера bloc 9
  молча пропускает, а следующий виток цикла останавливает проверка внутри
  замка. Страница называет довод только проверки внутри замка; итог раздела
  с задачей — «замок и проверки `emit.isDone`», без счёта.
- **`await` нулевого таймера перед чтением поля порядок не ломает.** Обработчик
  bloc запускается прямо в `add`, а `switchMap` под `restartable()` ставит
  следующие события на паузу, пока отменяет прежнюю подписку. Правило «поле
  до первого `await`» держит мутация с естественной ошибкой — обработчик ждёт
  прежнюю задачу сам, — и проза говорит правило свойством кода, без чужой
  версии.
- **Драйверы задач считают задачи, прежде чем их ждать.** Обёртка над `watch`
  страницы записывает каждую задачу; обработчик, которого `restartable()`
  пускает после отмены другого, стартует, когда отмена кончилась, а отмена
  `watch` ждёт конец задачи. Поэтому `requireEnded(count)` ждёт, пока задач
  станет столько, сколько событий.
- **Задача ресурса возвращает форму волны, а не буфер.** `dispose` освобождает
  буфер, когда задача кончается, раньше, чем `onData` получил бы его значение;
  форма волны снимается в теле.
- **Типы прошивки и превью — в стенде, не на странице**, как у `vs-bloc.md`: их
  хватает прочесть из кода разделов.

## Задача 4. Перевод и входы страницы ядра

Перевод — `docs/ru/async_job/bloc.md`, пара в `PAIRS`
`tool/check_translations.py`: 12 заголовков, 18 блоков кода, 32 абзаца, списка
и таблицы на своих местах. Блоки кода взяты из оригинала байт в байт, `watch` —
с русским dartdoc соседки `docs/ru/async_job/riverpod-and-bloc.md`. Ссылки
таблицы ведут на якоря русского `vs-bloc.md`, ссылка моста — на «Стрим, который
отменяет задачу».

Входы: строка «In a bloc app» / «В приложении на bloc» в «Guides» README ядра
после «With riverpod and bloc», запись в «Unreleased» обоих CHANGELOG, абзац
в конце раздела «A handler that restarts» `riverpod-and-bloc.md` и его
перевода, запись `optionalLinks` сайта первой, раньше записей `solo`. Страница
стоит в теме `async_job` на обоих языках, `build_site_test.py` снова зелёный.

Числа прозы против фейков стенда — все сходятся: сообщение 50 мс (`sendMs`),
`close()` через 10 мс (`closeAtMs`), запись части 20 мс, четыре части
на загрузку, загрузки через 30 и 5 мс или через 30 и 0, клип 1 за 50 мс, клип 2
за 20 через 5 мс.

Линтер `humanizer--ru`: в изменённых абзацах README, CHANGELOG
и `riverpod-and-bloc.md` ноль `ERROR`. На самой странице девять `ERROR` правила
«мат-знаки», все на имени файла `vs-bloc.md` в адресе ссылки: регулярное
выражение ловит `vs` как слово. В прозе их нет, адрес не меняется.
