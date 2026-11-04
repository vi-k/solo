# Страницы о bloc: отчёт

> **Состояние на 2026-11-04:** все задачи плана сделаны и влиты в `main` —
> зонды по критерию отбора, состав разделов обеих страниц, стенд, обе
> страницы на двух языках и их входы; ревью готовой работы — одна находка
> Critical, шесть Important и десять Minor, все приняты и закрыты (раздел
> «Ревью работы»). Ревью простоты тем же днём,
> `2026-11-04-bloc-pages-simplicity-report.md`, пересматривает состав: три
> раздела ядра и «Ordering» `solo` уходят в таблицы. После ревью дизайна
> переделки, `2026-11-04-core-bloc-page-rework-design.md`, страница ядра снята
> по слову владельца, а страница `solo` сужена.
> **Что это:** отчёт об исполнении `2026-11-04-bloc-pages-plan.md`: зонды
> сценариев `vs-bloc.md` под bloc, вердикт по каждому, состав страниц
> и находки для стенда.
> **Связанные записи:** `2026-11-03-bloc-pages-design.md`,
> `2026-11-04-bloc-pages-plan.md`,
> `2026-11-04-bloc-pages-simplicity-report.md`.

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
  bloc идёт микрозадачей после `add`: контроллер событий bloc широковещательный
  и не `sync`. Порядок не ломает и задержка в 1 мс: таймеры одной длины
  срабатывают по порядку, и поле ставится раньше, чем его читает следующий
  обработчик. (Исправлено по находке M7 ревью работы: прежде здесь стоял довод
  о запуске обработчика прямо в `add`.) Правило «поле до первого `await`»
  держит мутация с естественной ошибкой — обработчик ждёт прежнюю задачу сам, —
  и проза говорит правило свойством кода, без чужой версии.
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

## Задача 5. Мосты и закрытие на странице `solo`

Страница `packages/solo/doc/bloc.md`, «solo under bloc»: вступление, «The
bridges» и «Closing and cancelling in-flight work». Стенд читает её вторым
документом: `SOLO`, свои `Blocks` и `unbuilt()`, драйверы `solo_*`. Гейт пишет
их вывод в `bloc-pages-solo.out` и сверяет страницу `solo` с ним, страницу
ядра — с `bloc-pages-core.out`: обе цитируют строку
`with bloc alone: close took 90ms, …`, и каждая должна найти её в выводе своих
драйверов.

Мост состояний показан на счётчике — `Counter` с `SoloStream` под
`CounterBloc`: событие `_Started`, которое добавляет конструктор, слушает
`stream` через `emit.forEach`, методы контроллера ждутся через `job.done`,
`close()` закрывает контроллер первым. Драйверы:

- `solo_bridge_states` — счёт до 2, два сброса, счёт до 3, `close()` через 35
  мс: контроллер `[1, 2, 0, 0, 1]`, bloc `[1, 2, 0, 1]` — второй сброс
  публикует то же состояние, и bloc его отбрасывает; `close()` за 0 мс,
  контроллер и bloc закрыты, зона пуста;
- `solo_closing_bloc` — `ChatBloc` одного bloc, та же строка, что у ядра;
- `solo_closing_controller` — `ChatController` из `vs-bloc.md` (генератор
  требует, чтобы блок страницы был подстрокой блока раздела Solo `vs-bloc.md`)
  под `ChatBloc` с `sequential()`: `close()` за 0 мс, `sent [hi]`, ни одного
  состояния после `close()`, ноль прочтений, зона пуста;
- `solo_closing_bloc_first` — тот же блок, генератор меняет порядок
  в `close()`: `close()` за 100 мс, `sent [hi, bye]`, два состояния после
  `close()`, два прочтения.

Сценарий чата у драйверов общий с ядром, поэтому фабрика bloc и проверки ушли
в драйвер: `chatBloc(api)` и `check(api, afterClose)`, проверки ответа одного
bloc — `requireGuarded`.

Мутации страницы, каждая красная на своём стороже:

| Мутация | Где краснеет |
| --- | --- |
| `CounterBloc.close()` без `await _counter.close()` | `solo_bridge_states`: контроллер досчитал до 3, `counter.isClosed false` |
| `countTo(...).value` вместо `.done` | `solo_bridge_states`: зона `[Cancelled(closed)]` |
| `send(...).value` вместо `.done` | `solo_closing_controller`: зона `[Cancelled(closed), Cancelled(closed)]` |
| `super.close()` первым на странице | генератор: «the close of the page moved» |
| `ChatController` без `ctx.abandonable` | генератор: блок не совпадает с `vs-bloc.md` |

Решения по ходу:

- **`watch` на странице `solo` нет**, хотя план и дизайн его называют. Ни один
  раздел страницы его не берёт: обработчики под контроллером ждут `job.done`,
  отмену держит контроллер. Блок без употребления на странице — шум, поэтому
  мост задач — абзац о `job.done` со ссылкой на «The bridge» страницы ядра, где
  показано, куда уходит `Cancelled` из `job.value`. Проверки подстроки `watch`
  для страницы `solo` поэтому тоже нет. Цена ошибки — блок и проверка, если
  раздел задачи 6 его всё же возьмёт.
- **Мост состояний — на счётчике, а не на чате.** Мост чата — ответ раздела
  закрытия; показанный в мостах, он оставил бы разделу пустой ответ. Счётчик —
  первый пример документации bloc, и на нём видно равное состояние, которое
  bloc отбрасывает.
- **`SendMessage` под контроллером — под `sequential()`**, как у ответа одного
  bloc: читатель меняет тело обработчика и оставляет регистрацию. На нём
  и держится довод порядка `close()`: `super.close()` первым прогоняет очередь
  `sequential()` через открытый контроллер.
- **Ссылка на раздел `vs-bloc.md`** стоит там, где страница показывает
  контроллер, а не в последней строке раздела: читателю она нужна рядом
  с кодом.
- **`build_site_test.py` красный** на зеркале локалей — страницы `solo/bloc`
  нет в русской локали. Как и между задачами 2 и 4: перевод — задача 7.

## Задача 6. Остальные разделы страницы `solo` и итоговая таблица

Разделы в порядке `vs-bloc.md`: «Ordering updates to shared state» перед
закрытием, за ним «Restarting one operation within a shared queue», «Removing
selected pending work», «Reacting to an independent external state change»,
«Finishing an in-flight write before restarting» и таблица «Where bloc keeps
its answer» — сценарии 2, 4, 6, 8 и 11, у 11 ссылка на раздел страницы ядра
по адресу GitHub. Вступление перечисляет ловушки всех шести разделов.

Ответ одного bloc и контроллер каждого раздела взяты из `vs-bloc.md` как есть,
и генератор держит это: `from_vs_bloc` требует, чтобы блок страницы был
подстрокой блока того же имени в подразделе Bloc или Solo того же раздела
`vs-bloc.md`. Мост у контроллера без `SoloStream` (заметки, устройство,
прошивка) — применение миксина
`Streamed<X> = <X>Controller with SoloStream<…>`, у плеера и отчёта поток уже
есть. Фейки — фейки `tool/doc_snippets.py` с его задержками: загрузка заметки
40 мс и список 60, play и pause по 30, перемотка тремя шагами по 10, connect 30
и прочее 10, отчёт 50, кусок записи 20.

Драйверы, по два на раздел, у удаления три:

- `solo_ordering_bloc` и `solo_ordering_controller` — загрузка и обновление
  подряд: список прочитан `[n0, n1]`, состояние
  `NotesState([n0, n1], uploading: false)` у обоих. Под контроллером у каждого
  события своя регистрация по умолчанию;
- `solo_restarting_bloc` и `solo_restarting_controller` — серии `1, 2, 3`
  и `1, 2, 1` между play и pause и перемотка на 3 через 15 мс после перемотки
  на 1: у одного bloc `[play, seek 1, seek 1, pause]` на возвратной серии,
  у контроллера `[play, seek 1, pause]`; остальное совпадает;
- `solo_removing_bloc`, `solo_removing_sequential` (первая попытка — контроллер
  под одной регистрацией с `sequential()`) и `solo_removing_controller`
  (регистрация на команду) — уход с экрана, общее `const ReadBattery()`
  и чтение за отключением; исходы устройства — те же, что у зонда задачи 1,
  зона только у одного bloc;
- `solo_external_bloc` и `solo_external_controller` — два отчёта, отзыв через
  20 мс: `states [SignedOut(signed out elsewhere)], built 1`, зона пуста;
  у контроллера обе задачи кончаются `Cancelled(rules: is not SignedIn)` —
  драйвер ловит их подклассом `RecordedReport`;
- `solo_write_bloc` и `solo_write_controller` — сценарий записи ядра на фейке
  с событиями `vs-bloc.md`: та же строка, что у ядра, в обеих сериях;
  у контроллера подкласс `RecordedFirmware` ждёт `done` трёх задач — две
  `Cancelled(replaced)`, последняя `Done(null)`.

Мутации страницы, каждая красная на своём стороже:

| Мутация | Где краснеет |
| --- | --- |
| `seek(...).value` вместо `.done` в `PlayerBloc` под контроллером | `solo_restarting_controller`: зона из пяти `Cancelled(replaced)` |
| `SequentialDeviceBloc` без пустой ветки `case _Started():` | `solo_removing_sequential` не собирается: `switch` не исчерпывающий |
| `build(...).value` вместо `.done` в `ReportBloc` под контроллером | `solo_external_controller`: зона `[Cancelled(rules: is not SignedIn), …]` |
| `FirmwareBloc` без `add(_Started())` | `solo_write_controller`: `states []` |
| `NotesBloc` под контроллером без `add(_Started())` | `solo_ordering_controller`: состояние `NotesState([], …)` |
| `DeviceBloc` одного bloc без проверки поколения | генератор: блок не совпадает с `vs-bloc.md` |

Решения по ходу:

- **`BuildReport` под контроллером — без `sequential()`**, хотя у ответа одного
  bloc он есть. Порядок отчётов держит очередь контроллера, и довод раздела —
  что за bloc не остаётся ни события отзыва, ни проверок; лишний трансформер
  спорил бы с ним. В закрытии `sequential()` оставлен, потому что на нём
  держится довод порядка `close()`. Цена ошибки — строка в блоке.
- **Первая попытка удаления называется `SequentialDeviceBloc`**: имя
  `DeviceBloc` в одном разделе дважды отравило бы ключ. Мост `StreamedDevice`
  и `_Started` объявлены в блоке ответа, первая попытка ссылается на них:
  первый блок `dart` под «The first attempt» обязан открываться пометкой,
  и контроллер с мостом встать перед ней не могут.
- **Исходы задач проверяются там, где о них говорит проза** — у отчёта
  и у записи; у остальных разделов проза об исходах молчит, и драйвер их
  не ловит.
- **Строка о сценарии 4 в таблице** — по зонду задачи 1: контроллер
  с `Policy.restart` и `ifCancelled` публикует `Initial` между двумя стартами.
  Драйвера у таблицы нет, как и у таблицы ядра.
- **Драйверы записи — `solo_write_bloc` и `solo_write_controller`**,
  а не `solo_firmware_*` плана: имена драйверов идут по разделу, как у ядра
  (`core_write_*`) и у остальных разделов страницы.
- **`build_site_test.py` по-прежнему красный** на зеркале локалей до перевода
  в задаче 7.

## Задача 7. Перевод и входы страницы `solo`

Перевод — `docs/ru/solo/bloc.md`, пара в `PAIRS` `tool/check_translations.py`
сразу за парой `riverpod.md`: 22 заголовка, 36 блоков кода, 61 абзац, списки
и таблица на своих местах. Блоки кода взяты из оригинала байт в байт, кроме
пометки первой попытки удаления. Ссылки на разделы сценариев ведут на якоря
русского `vs-bloc.md`, ссылки на страницу ядра — на русскую
`../async_job/bloc.md`, хотя английская ведёт на GitHub: переводы лежат вне
пакетов, и ссылка между ними относительная, как у соседних переводов. «Guard»
строки наблюдателя в таблице — «защита», как в разделе наблюдателя русского
`vs-bloc.md`.

Входы: строка «solo under bloc» / «solo под bloc» в «Guides» README `solo`
после «solo under riverpod»; фраза в абзаце над таблицей названа так, чтобы
назвать обе страницы, и абзац остался в восьми строках, `check_doc_shape.py`
зелёный. Для этого «puts the pages together» стало «joins them», а «for one who
stays on it» — «for one who stays»; русский абзац уложился без сокращений.
Раздел «Coming from bloc» не тронут. Во вступлении `vs-bloc.md` и перевода —
фраза о странице в конце абзаца о README; стенд `vs-bloc` собирается
и проходит, `check_traces` по `vs-bloc.md` — 3 трассы из 3, `QUOTED` и `SAID`
не задеты. Запись в «Unreleased» / «Не выпущено» обоих CHANGELOG `solo` после
записи о странице riverpod. Сайт: `page('solo/bloc', …)` и запись
`optionalLinks` стоят с задачи 5, `build_site_test.py` зелёный — 27 тестов.

Числа прозы против фейков стенда — все сходятся: шаг счётчика 10 мс и `close()`
через 35 мс; отправка 40 мс, список 60 мс; сообщение 50 мс (`sendMs`),
`close()` через 10 мс; `play` и `pause` по 30 мс, перемотка — три шага по 10
мс, вторая перемотка через 15 мс; подключение 30 мс, остальные вызовы
устройства 10 мс; отчёт 50 мс, два отчёта, отзыв через 20 мс; запись части 20
мс, четыре части, загрузки через 30 и 5 мс или через 30 и 0.

Линтер `humanizer--ru`: в изменённых абзацах README, CHANGELOG и `vs-bloc.md`
ноль `ERROR`; на самой странице тринадцать `ERROR` правила «мат-знаки», все
на имени файла `vs-bloc.md` в адресе ссылки, как в задаче 4.

Решения по ходу:

- **Ссылка страницы ядра на страницу `solo` — отдельным коммитом после коммита
  задачи, а не раньше**, как велит план. Русская страница ядра ведёт
  на `../solo/bloc.md`, и `check_links.py` краснеет, пока перевода нет;
  а ни один коммит не трогает обе страницы. Цена ошибки — порядок двух
  коммитов.
- **Ссылка — относительная, `../../solo/doc/bloc.md`, а не по GitHub**, как
  у соседней ссылки на `vs-bloc.md` в том же абзаце; ставится в абзац над
  таблицей «Where the queue is the problem», а не в саму таблицу: строки
  таблицы — сценарии, а страница `solo` отвечает на несколько из них сразу.
  Цена ошибки — одна ссылка.

## Задача 8. Записи и полная проверка

Решение 133 `docs/settled.md` дополнено: к пользователям bloc идут оба пакета,
каждый своей страницей, и bloc на обеих остаётся. У дизайна — шапка и раздел
«Что вышло» с отступлениями от него. В handoff — вторая фаза страниц
на нотифаере riverpod как предложение, которое ждёт дизайна и слова владельца.

Полная проверка — задания `docs` и `snippets` гейта подряд, на коммите задачи 7
и ссылки ядра: четырнадцать шагов `docs` зелёные, пять генераторов стендов,
анализ шести пакетов без замечаний, все драйверы доходят до конца,
`check_traces.py` по семи документам — ни одной трассы, которой нет в выводе.

## Ревью работы

Независимое ревью Opus по копии дерева на f36e14ad. Ревьюер собрал и прогнал
стенд вне дерева на bloc 9.2.1 и `bloc_concurrency` 0.3.0 — анализ чистый, все
26 драйверов зелёные, трассы 10 из 10 у ядра и 14 из 14 у `solo`, — гонял
мутации страниц и свои зонды; репозиторий не тронут. Итог ревьюера: одна
находка Critical, шесть Important и десять Minor. Находки ниже — его текст,
вердикт — отдельным абзацем после каждой. Все приняты и закрыты двумя
коммитами: 945eed0f — страница `solo`, её перевод, README и стенд; c6baf571 —
страница ядра, её перевод и стенд. После них полная проверка — задания `docs`
и `snippets` гейта подряд, на c6baf571 — зелёная: четырнадцать шагов `docs`,
пять генераторов, анализ шести пакетов без замечаний, все драйверы доходят
до конца (у страниц о bloc их теперь 30), `check_traces.py` по семи
документам — ни одной трассы, которой нет в выводе.

### Critical

**C1. `packages/solo/doc/bloc.md`, строки 83–84, 211–212, 338, 484–486,
695–698, 809, 929, абзац 98–104. Мост задач через `.done` глотает провал задачи
контроллера.**

- **Утверждение.** «the handler awaits `job.done`, which never throws and
  returns the outcome». Все обработчики страницы —
  `(e, emit) => _x.method().done`.
- **Почему это плохо.** Чтение `done` помечает провал наблюдённым.
  `packages/async_job/lib/src/job.dart:268–273`: «Reading it marks the job
  observed, so nobody is asked to answer for a [Failed] outcome». Таблица
  в `packages/async_job/doc/outcomes.md:116–118`: «Reads `done` | yes».
  Обработчик исход выбрасывает. Значит, провал не доходит ни до `onError` bloc,
  ни до зоны, ни до `BlocObserver`. У одного bloc ошибка вызова в обработчике
  попадает в `onError` и в зону. Страница ядра это знает: её `ChatBloc`
  разбирает `Failed` и бросает его заново (строки 163–164, «a failure of the
  work is in it as `Failed`, for the handler to deal with»). Страница `solo`
  о `Failed` молчит, и каждый её раздел учит терять ошибки.
- **Зонд.** `Counter`, у которого `countTo` бросает
  `StateError('device gone')`, под `CounterBloc` страницы, плюс `BlocObserver`,
  записывающий `onError`:
  ```
  bloc.state 0
  the zone [], bloc onError []
  ```
- **Правка.** В «The bridges» показать обработчик, который отдаёт провал bloc,
  как на странице ядра. Например, общий хелпер страницы:
  ```dart
  Future<void> settle(Job<Object?> job) async {
    if (await job.done case Failed(:final error, :final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
  ```
  Регистрации тогда:
  `on<CountTo>((e, emit) => settle(_counter.countTo(e.target)))`. В стенд
  добавить драйвер с падающей задачей контроллера
  и `require('$zone' == '[Bad state: …]')`. Другой путь — сказать прямо, что
  провал разбирает наблюдатель контроллера, и показать его. Абзац 98–104
  в любом случае должен сказать, куда девается `Failed`.

Вердикт: принято. Итог: в «The bridges» страницы `solo` объявлены `settle`,
который ждёт задачу и бросает `Failed` заново, и `follow` (I3); все обработчики
страницы и перевода ждут задачи контроллера через `settle`, а абзац
о `job.done` говорит, куда девается провал и почему. Это путь, предложенный
ревьюером. Сторож стоит не на падающем счётчике, а на коде раздела закрытия:
драйвер `solo_closing_controller_failed` — чат под контроллером на API без
сети — требует ошибку в зоне, и мутация `settle` без
`Error.throwWithStackTrace` его краснит. Своя функция стенда `settle()`
переименована в `waitOut()`: имя теперь занято страницей. Коммит 945eed0f.

### Important

**I1. `packages/async_job/doc/bloc.md:5` и `packages/solo/doc/bloc.md:5` — «an
app on bloc 9». Охрана `isClosed` в разделах закрытия верна только с bloc
9.2.1.**

- **Причина.** В 9.2.1 `isClosed` стал учитывать контроллер событий:
  `bloc-9.2.1/CHANGELOG.md`, «fix: `isClosed` should incorporate event
  controller state (#4809)»; `bloc-9.2.1/lib/src/bloc.dart:303` —
  `bool get isClosed => _eventController.isClosed || super.isClosed;`.
  В 9.0–9.2.0 `isClosed` во время прогона очереди под `sequential()` — `false`.
  Тогда ответ на «bye» попадает в состояние, а `add(MarkReplyRead())` падает
  в зону.
- **Зонд.** Тот же стенд с `bloc: 9.2.0` (в `pubspec.lock` —
  `version: "9.2.0"`):
  ```
  with bloc alone: close took 90ms, sent [hi, bye], reply reply to bye, reads 0
  Bad state: with bloc alone: nothing may reach the zone: [Bad state: Cannot add new events after calling close, …×2]
  with a job: close took 50ms, sent [hi, bye], reply reply to bye, reads 0
  Bad state: with a job: nothing may reach the zone: [Bad state: Cannot add new events after calling close]
  ```
  Падают `core_closing_bloc`, `core_closing_job` и `solo_closing_bloc`.
  Остальные 23 драйвера на 9.2.0 печатают то же самое.
- **Что не так в стенде.** Стенд просит `bloc: ^9.0.0`
  (`tool/bloc_snippets.py:69`) и берёт свежую версию, поэтому пол
  не проверяется. `vs-bloc.md:58` честно пишет «bloc 9.2.1».
- **Правка.** На обеих страницах и в переводах: «bloc 9.2.1». В «What stays
  with bloc» раздела закрытия ядра одна фраза: с 9.2.1 `isClosed` верен уже
  во время прогона очереди, раньше — нет. В `PUBSPEC` стенда — `bloc: ^9.2.1`,
  чтобы пол стенда совпадал с обещанием страниц. Заметка: ответ контроллера
  `solo` на 9.2.0 работает (`sent [hi]`, зона пуста).

Вердикт: принято, проверено своим зондом: стенд с `bloc: 9.2.0` —
`core_closing_bloc`, `core_closing_job` и `solo_closing_bloc` красные, в зоне
«Cannot add new events after calling close», ответ на «bye» в состоянии;
`solo_closing_controller` зелёный. Итог: обе страницы и переводы называют bloc
9.2.1; в «What stays with bloc» закрытия ядра — фраза о том, что до 9.2.1
`isClosed` остаётся `false`, пока `close()` прогоняет очередь, и ответ на «bye»
попадает в состояние; `PUBSPEC` стенда — `bloc: ^9.2.1`, с комментарием почему.
Коммиты c6baf571 (ядро и стенд) и 945eed0f (страница `solo`).

**I2. `packages/solo/doc/bloc.md:202, 326, 684, 919–920`.
`final class StreamedX = XController with SoloStream<…>` не собирается, если
bloc лежит в другой библиотеке, чем контроллер.**

- **Причина.** Контроллеры `vs-bloc.md` объявлены `final class`, а такой класс
  нельзя расширить вне его библиотеки. Стенд кладёт всё в один файл и этого
  не видит. Читатель, у которого `notes_controller.dart` и `notes_bloc.dart` —
  разные файлы, получит ошибку.
- **Зонд** (два файла):
  ```
  error - two_libraries.dart:4:29 - The class 'NotesController' can't be extended outside of its library because it's a final class. - invalid_use_of_type_outside_library
  ```
  То же касается `_Started extends NotesEvent/ChatEvent/…` при запечатанном
  семействе событий не в `part`-файле.
- **Правка.** Одна фраза в «The bridges»: применение примеси объявляется рядом
  с контроллером, в его библиотеке. Ещё лучше — контроллер приложения
  подмешивает `SoloStream` там, где объявлен, как `PlayerController`
  и `ReportController`. И о `_Started`: событие моста живёт в библиотеке
  семейства событий.

Вердикт: принято. Итог: в «The bridges» после `CounterBloc` — абзац о том, что
`Counter` подмешивает `SoloStream` там, где объявлен, а разделы ниже добавляют
примесь к контроллерам страницы «рядом» своим классом, и он собирается только
в библиотеке финального контроллера; `_Started` объявляется в библиотеке
запечатанного семейства событий. Стенд этого не проверяет: каждый драйвер —
один файл; зонд ревьюера с двумя файлами процитирован в находке. Коммит
945eed0f.

**I3. `packages/solo/doc/bloc.md:79–86` и утверждение 115–116 («The bloc
publishes every state of the controller but one equal…»). Мост состояний теряет
состояние, которое контроллер публикует между конструктором bloc и подпиской.**

- **Причина.** `super(_counter.currentState)` снимает состояние сразу.
  `emit.forEach` подписывается на широковещательный `stream` только
  в обработчике `_Started`, а он идёт микрозадачей позже: `_eventController`
  в bloc — `StreamController.broadcast()`, не `sync`. Контроллер, который
  передали уже с работой (DI, общий для двух экранов), так рассинхронизирует
  bloc до следующего `emit`.
- **Зонд.** Задача `enqueue((ctx) async => ctx.emit(5))` поставлена перед
  `CounterBloc(counter)`:
  ```
  counter.currentState 5, bloc.state 0
  ```
  С правкой ниже — `counter.currentState 5, bloc.state 5`.
- **Правка.** Обработчик моста сначала подписывается, затем сверяет состояние:
  ```dart
  (e, emit) {
    final following = emit.forEach(_counter.stream, onData: (s) => s);
    if (_counter.currentState != state) emit(_counter.currentState);
    return following;
  }
  ```
  Либо оговорить в прозе, что мост верен только для контроллера, созданного
  вместе с bloc. Попутно: «drops as it drops any such `emit`» неточно. Bloc
  отбрасывает равное только после первого своего `emit` (`bloc.dart:200`:
  `if (this.state == state && _emitted) return;`).

Вердикт: принято. Итог: `follow` сначала подписывается на `stream`, затем
сравнивает `currentState` контроллера с состоянием bloc и публикует его, если
оно другое; фраза об отбрасывании исправлена: bloc отбрасывает равное состояние
только после первого своего `emit`. Драйвер `solo_bridge_late` ставит задачу
контроллера перед конструктором bloc и требует, чтобы bloc начал с 0 и дошёл
до 5; мутация `follow` без сравнения его краснит. Коммит 945eed0f.

**I4. `packages/solo/doc/bloc.md:337–340, 363–374`. Правило «порядок `close()`»
в разделе закрытия создано только оставленным `sequential()`. Сама страница
в других разделах учит обходиться без него.**

- **Мутация.** Убрать `transformer: sequential()` у `SendMessage` под
  контроллером:
  ```
  solo_closing_controller: with a controller: close took 0ms, sent [hi], reply null, reads 0
  solo_closing_bloc_first: with super.close() first: close took 0ms, sent [hi], reply null, reads 0   (RED только потому, что драйвер требует [hi, bye])
  ```
  С регистрацией по умолчанию требование выполняется и при обратном порядке
  закрытия.
- **Противоречие с другими разделами.** «Ordering» говорит «a registration for
  each event … is right as it is». «Removing» делает «контроллер под одной
  регистрацией с `sequential()`» первой попыткой. Отчёт честно пишет, что
  `sequential()` здесь оставлен, «потому что на нём держится довод порядка
  `close()`». Довод держится на коде, который страница в другом разделе
  называет лишним. «The bridges» (строки 119–120) отсылает сюда как к причине
  закрывать контроллер первым во всех bloc.
- **Правка.** Сказать прямо: порядок важен, пока у регистрации остаётся
  `sequential()`. С регистрацией по умолчанию, как в остальных разделах,
  очередь держит контроллер, и порядок `close()` в этом сценарии ничего
  не решает. Закрывать контроллер первым — привычка на случай `sequential()`.
  Либо убрать `sequential()` из ответа, перестроить довод и сторож
  `solo_closing_bloc_first`.

Вердикт: принято, первым из предложенных путей: `sequential()` в ответе раздела
закрытия остаётся, а проза говорит, где порядок `close()` важен. Итог: «What
stays with bloc» раздела закрытия — порядок важен, пока у регистрации остаётся
`sequential()`; с регистрацией по умолчанию оба порядка отправляют одно «hi».
Абзац мостов говорит, что bloc страницы закрывают контроллер первым, а где
порядок важен — в разделе закрытия. Два драйвера, `solo_closing_default`
и `solo_closing_default_bloc_first`, берут ответ раздела без `sequential()`
у `SendMessage`, в обоих порядках, и требуют `sent [hi]`, ни одного состояния
после `close()` и ни одного прочтения. Коммит 945eed0f.

**I5. `packages/async_job/doc/bloc.md:384, 387, 393–400` (10 ссылок). Страница
ядра ведёт в `solo` относительными путями `../../solo/doc/…`.**

- **Правило.** `docs/conventions.md:246–248`: «Английская страница ссылается
  на другой пакет адресом на GitHub, потому что pub.dev показывает пакет без
  соседей». `packages/async_job/.pubignore` исключает только `README.ru.md`,
  так что `doc/bloc.md` уходит в архив с мёртвыми ссылками. Решение по ходу
  в отчёте («относительная, как у соседней ссылки на `vs-bloc.md`») опирается
  на соседние ссылки, которые нарушают то же правило.
- **Правка.** Адреса
  `https://github.com/vi-k/solo/blob/main/packages/solo/doc/…`, как у страницы
  `solo` в обратную сторону (строки 103, 965). `check_links.py`
  и `build_site.py` такие адреса уже понимают. Русский перевод остаётся
  относительным.

Вердикт: принято. Итог: десять ссылок английской страницы ядра на страницы
`solo` — адреса на GitHub, русская страница осталась с относительными. Решение
по ходу задачи 7 об относительной ссылке пересмотрено этой находкой. Коммит
c6baf571.

**I6. `packages/async_job/doc/bloc.md:382–389`. Таблица «Where the queue is the
problem» и абзац над ней неверны для половины строк.**

- **Утверждение.** «in each, what the code of a bloc app has to keep is about
  the queue of bloc», и дальше: «Where a queue is the answer, solo under bloc …
  says … what it takes off the code».
- **Что на деле.** Четыре строки из восьми — не об очереди:
  - охрана наблюдателя: «the failure is the observer's»;
  - сброс из `CancelRefresh`: про эмиттер;
  - функции-события и `void`: про `add`;
  - completer: «`add` returns nothing».
- **Обе страницы.** Страница `solo` оставляет за bloc ровно эти четыре сценария
  (`packages/solo/doc/bloc.md:961–964`). Читатель ядра уходит по ссылке туда,
  где ответа нет.
- **Правка.** Разделить таблицу на две части: «где ответ — очередь» (1, 5, 7,
  9, ведут на страницу `solo`) и «где ответ остаётся у bloc при любом пакете»
  (2, 4, 6, 8). Либо переименовать раздел и переписать первую фразу абзаца.

Вердикт: принято, вторым путём: раздел переименован, таблица не делится. Итог:
раздел — «Where bloc keeps its answer» / «Где ответ остаётся за bloc», как
на странице `solo`. Абзац над таблицей говорит, что оставшееся принадлежит
самому bloc — его очереди, эмиттеру, `add` или наблюдателю, — и ведёт
на страницу `solo` для четырёх сценариев, где ответ — очередь: порядок
обновлений, перезапуск одной операции, удаление ожидающей работы, внешнее
изменение. На якорь раздела ссылалось только вступление самой страницы, оно
переименовано вместе с ним. Коммит c6baf571.

### Minor

**M1. Сторож `abandonable` в разделе ресурса не держит прозу.**

- `packages/async_job/doc/bloc.md:371–372`: «`ctx.abandonable` ends a cancelled
  job without waiting for the decoder».
- Мутация `ctx.abandonable(` → `ctx.join(` в `PreviewBloc` переживает драйвер —
  `core_resource_job` зелёный с той же трассой в обоих случаях.
- Правка: драйвер пишет в трассу конец задачи клипа 1 (`job 1 ended`)
  и требует, чтобы он стоял раньше `ready 1`.

Вердикт: принято. Итог: у `core_resource_job` обёртка `watch` записывает длину
трассы в момент конца каждой задачи, и драйвер требует, чтобы задача клипа 1
кончилась раньше `ready 1`; цитируемая трасса не изменилась. Мутация
`ctx.abandonable(` → `ctx.join(` теперь красная: «the job of clip 1 must end
before its buffer arrives». Коммит c6baf571.

**M2. Мост в трёх разделах не держится сторожами.**

- Удаление `add(_Started())` у `PlayerBloc` (`solo_restarting_controller`)
  и у `DeviceBloc` (`solo_removing_*`) — зелёные: драйверы смотрят только
  на трассу фейка и зону, а не на `bloc.state`.
- Правка: в `SEEKING` и `LEAVING` требовать, чтобы последнее состояние bloc
  совпало с `currentState` контроллера.

Вердикт: принято. Итог: `SEEKING` и `LEAVING` зовут `requireFollowed(bloc)`
перед `close()`: у драйверов с контроллером это требование, чтобы состояние
bloc совпало с `currentState` контроллера, у драйверов одного bloc — пустая
функция. Удаление `add(_Started())` у `PlayerBloc` и у `DeviceBloc` теперь
красное. Коммит 945eed0f.

**M3. «What stays with bloc» в нескольких разделах буквально неверно.**

- `packages/solo/doc/bloc.md:510–512`: «a registration for each command and
  nothing else».
- Строка 799 «The bloc has one registration, for the build» и строка 916 «The
  bloc has one registration…»: в коде под ними по две регистрации
  (`on<_Started>`) плюс `add(_Started())` и `close()`.
- Правка: «…and the bridges of The bridges» / «one registration besides the
  bridge».

Вердикт: принято. Итог: «a registration for each command besides the bridges»
в разделе перезапуска, «Besides the bridges, the bloc has one registration»
в разделах внешнего изменения и записи, и то же в переводе. Коммит 945eed0f.

**M4. Итог раздела записи на странице ядра не называет оставшееся правило.**

- `packages/async_job/doc/bloc.md:301–303` против 256–257. У одного bloc проза
  ставит в цену «Every handler that writes to the device has to take the same
  lock».
- У цепочки то же самое: любой другой обработчик, который пишет в устройство,
  обязан взять ту же `_flashing` и встать в цепочку. Итог «one rule instead of
  the lock» это умалчивает.
- Правка: дописать это в «What stays with bloc».

Вердикт: принято. Итог: «What stays with bloc» раздела записи ядра дописан: как
и с блокировкой, правило держит каждый обработчик, который пишет
в устройство, — ждёт задачу в `_flashing` и кладёт туда свою. Коммит c6baf571.

**M5. Карты разделов во вступлениях противоречат решению 107.**

- `packages/async_job/doc/bloc.md:10–22` и `packages/solo/doc/bloc.md:13–34` —
  списки разделов с якорями во вступлении. Решение 107 `docs/settled.md:1036`:
  «Карт разделов с якорями во вступлениях страниц нет».
- Дизайн просил «Вступление одним абзацем», план (задачи 3 и 6, шаг 3) —
  «список ловушек со ссылками». Конфликт с 107 не назван ни в плане, ни в «Что
  вышло».
- Правка: убрать якоря и оставить ловушки прозой, либо вынести пересмотр 107
  владельцу.

Вердикт: принято: решение 107 старше плана, который велел список со ссылками.
Итог: вступления обеих страниц и переводов называют требования прозой, без
якорей; ссылка на итоговую таблицу осталась одна. Коммиты c6baf571 и 945eed0f.

**M6. Шапки и handoff устарели.**

- Шапки `2026-11-04-bloc-pages-plan.md` и `2026-11-04-bloc-pages-report.md`
  после коммита задачи 8 по-прежнему говорят «задача 8 впереди», хотя шаги 1–3
  отмечены `[x]`, а отчёт описывает задачу 8.
- `docs/handoff.md:10`: «дальше задача 8 — записи, полная проверка».
- Правка: в шапках и в handoff — «задача 8, шаги 1–3 сделаны; впереди ревью
  готовой работы и вливание».

Вердикт: принято. Итог: шапки плана, отчёта и дизайна и handoff говорят
о состоянии после ревью и вливания; шаги 4–5 задачи 8 в плане отмечены. Коммит
этой записи.

**M7. Довод в решении по ходу задачи 3 отчёта неверен.**

- `2026-11-04-bloc-pages-report.md:429–431`: «Обработчик bloc запускается прямо
  в `add`». Это не так:
  `_eventController = StreamController<Event>.broadcast()` (`bloc.dart:67`)
  не `sync`, и обработчик идёт микрозадачей после `add`.
- Мутация с `await Future.delayed(const Duration(milliseconds: 1))` перед
  чтением поля тоже зелёная. Настоящая причина — таймеры одинаковой длины
  срабатывают по порядку, и поле всё равно ставится раньше, чем его читает
  следующий обработчик.
- На страницу это не влияет: правило верное, и естественную ошибку (ждать
  прежнюю задачу в обработчике) сторож ловит. Но запись хранит неверное
  объяснение; поправить абзац.

Вердикт: принято; что контроллер событий не `sync`, проверено по исходнику:
`bloc-9.2.1/lib/src/bloc.dart:67` — `StreamController<Event>.broadcast()`.
Довод о таймерах одной длины — ревьюера, его мутации процитированы в находке.
Итог: абзац решения по ходу задачи 3 этого отчёта исправлен. Коммит этой
записи.

**M8. Двусмысленность в переводе.**

- `docs/ru/solo/bloc.md:433`: «пропускает свою первую перемотку на 1».
  По-русски это читается и как «отбрасывает», хотя в оригинале «lets …
  through».
- Правка: «не отбрасывает свою первую перемотку на 1» или «пускает дальше».

Вердикт: принято. Итог: «не отбрасывает свою первую перемотку на 1». Коммит
945eed0f.

**M9. Неточности о bloc.**

- `packages/async_job/doc/bloc.md:53`: «`concurrent()`, the default».
  По умолчанию в bloc стоит не `concurrent()` из `bloc_concurrency`,
  а собственный `_FlatMapStreamTransformer` (`bloc.dart:61–65`); драйвер гоняет
  именно `null`. Правка: «bloc's default, which `concurrent()` repeats».
- `packages/solo/doc/bloc.md:122–123`: «`emit` of a bloc is for its handlers
  and tests». Обработчики получают свой `Emitter`; `Bloc.emit` — «only for
  internal use … outside of tests» (`bloc.dart:129–131`). Правка: «is for bloc
  itself and tests».

Вердикт: принято. Итог: на странице ядра — «under the default of bloc, which
`concurrent()` repeats», на странице `solo` — «`emit` of a bloc is for bloc
itself and tests», и то же в обоих переводах. Коммиты c6baf571 и 945eed0f.

**M10. Фраза в README `solo` потеряла смысл.**

- `packages/solo/README.md:309`: «solo under riverpod and solo under bloc for
  one who stays» — потерялось, на чём остаётся читатель. Перевод при этом
  добавляет «на одном из них», и русский говорит больше английского.
- Правка: «for one who stays on either», если бюджет абзаца
  в `check_doc_shape.py` позволит.

Вердикт: принято. Итог: «for one who stays on either». Чтобы абзац остался
в восьми строках и `check_doc_shape.py` зелёным, «for a reader who comes from
bloc» стало «for one who comes from bloc», а в переводе «для читателя, который
пришёл» — «для того, кто пришёл»; «на одном из них» перевода теперь говорит
то же, что оригинал. Коммит 945eed0f.

---

### Мутации страниц (вне дерева, генерация и прогон заново)

| Мутация | Итог |
|---|---|
| ядро, `PreviewBloc`: `abandonable` → `join` | **выжила** (M1) |
| ядро, `FirmwareBloc`: `await Future.delayed(Duration.zero)` и 1 мс перед чтением `_flashing` | **выжили обе** (M7, правило всё равно верно) |
| `solo`, `PlayerBloc` без `add(_Started())` | **выжила** (M2) |
| `solo`, `DeviceBloc` без `add(const _Started())` | **выжила** (M2) |
| `solo`, `SendMessage` без `sequential()` | красная только на `solo_closing_bloc_first` и в анализе; сам ответ верен (I4) |
| ядро, `close()`: `_sending?.cancel()` без `await` | красная в анализе (`unawaited_futures`), драйвер зелёный |
| ядро, ответ чата без `if (isClosed) return;` | красная: зона `Cannot add new events after calling close` |
| ядро, ответ чата: `abandonable` → `join` | красная: `close took 90ms` |
| ядро, `FirmwareBloc`: `await job.done` вместо `forEach(watch(job))` | красная (`only 0 of 3 jobs started`) |
| ядро, `FirmwareBloc` без `restartable()` | красная: провод `[0, 1, 2, 3, 100, …]` |
| `solo`, `ChatBloc.close()` через `unawaited(_chat.close())` | генератор: «the close of the page moved» |
| `solo`, мост счётчика под `sequential()`-подобным трансформером | зелёная; страница этого и не утверждает |

### Проверено и верно

- **bloc 9.2.1 по исходникам.**
  - `close()`: сначала `await _eventController.close()`, затем отмена
    эмиттеров. Отсюда «под `sequential()` отменять нечего, очередь
    прогоняется».
  - `restartable()` (`switchMap`) отменяет подписку заменённого обработчика.
  - `emit` после отмены эмиттера молча отбрасывается.
  - `emit.forEach` завершается вместе со стримом.
  - Ошибка обработчика идёт в `onError` и через `rethrow` — в зону.
  - Обработчик идёт после возврата `add`, поэтому строки таблицы ядра «after
    `add` has returned» верны.
- **async_job и solo.**
  - `done` не бросает, `value` бросает `Cancelled`.
  - `ctx.join` ждёт до конца и потом бросает.
  - `abandonable`: `dispose` — при любом исходе, `discard` — кроме `Done`.
    Текст о `dispose`/`discard` верен.
  - `SoloStream.close()` закрывает стрим после закрытия движка.
  - Исходы `Cancelled(closed)` у «hi» и «bye» под закрытым контроллером: зонд
    вывел `[Cancelled(closed), Cancelled(closed)]`.
  - Анализатор на `stream.listen(emit)` действительно выдаёт
    `invalid_use_of_visible_for_testing_member`.
- **Числа прозы против фейков стенда** — все сходятся: 50/10 мс у чата, 20 мс
  и зазоры 30/5/0 у записи, 50/20/5 у клипов, 10 мс шаг и закрытие на 35 мс
  у счётчика, 40/60 у заметок, 30 и 3×10 у плеера, 30/10 у устройства, 50/20
  у отчёта, 190 = 90 + 100 у моста. Серия записи из трёх загрузок требует
  `maxInFlight == 1` и ни одного куска средней загрузки; оба зазора гоняются.
- **Исходы задач:** `requireEnded` требует только `Done` или `Cancelled`,
  у `RecordedFirmware` — `Cancelled(replaced)` ×2 и `Done(null)`,
  у `RecordedReport` — `Cancelled(rules: is not SignedIn)`. Генератор держит
  байт в байт `watch` соседки и блоки `vs-bloc.md` (`from_vs_bloc`); ни один
  драйвер ядра не импортирует `solo`; `unbuilt()` пуст.
- **Переводы:** блоки кода совпадают с оригиналом, кроме комментариев (dartdoc
  `watch` и пометка первой попытки). Заголовки, абзацы и таблицы на своих
  местах (`check_translations.py`). По смыслу добавленных утверждений нет,
  кроме M8 и M10.
- **Проверки, все зелёные:** `check_translations.py`, `check_links.py`,
  `check_links_test.py`, `check_doc_shape.py`, `reflow.py --check`,
  `check_line_width.py` (вместе с тремя новыми записями), `check_page_code.py`,
  `check_dartdoc.py`, `archive_floor_test.py`, `reflow_test.py`,
  `build_site.py` (94 страницы) и `build_site_test.py` (27 тестов).
- **Сайт и вход.** Страницы стоят в своих темах (`async_job/bloc` — в теме
  ядра, `solo/bloc` — в теме `solo`), ссылки сайта ведут
  на `/async_job/bloc/#the-bridge` и на якоря `/solo/vs-bloc/…` на обоих
  языках. Задание `snippets` в `gate.yml` разводит вывод драйверов `solo_*`
  и ядра по разным файлам.
- **Тон по решению 133:** призыва уйти с bloc нет ни на одной странице,
  ни в фразе `vs-bloc.md`, ни в README и CHANGELOG.
- **Попутный коммит `aea7ab0a`** (Minor-находки страницы riverpod): стенд
  `riverpod_snippets.py` собирается и проходит, `check_traces.py`
  по `riverpod.md` — 10 из 10.
