> **Состояние на 2026-09-06:** все четырнадцать находок и список «Что
> дописать» приняты и закрыты правкой документов — тем же коммитом, что
> и эта запись. Вердикт стоит в конце каждой находки.
> **Что это:** ревью `packages/jobs` 0.1.0 глазами пользователя пакета:
> README, `example/`, dartdoc, `pubspec.yaml`, `CHANGELOG.md`, вид на
> pub.dev. Не код и не архитектура — лицо пакета и путь новичка.
> **Связанные записи:** `2026-09-06[1]-jobs-review.md`,
> `2026-09-06[2]-jobs-fixes-review.md`, `2026-09-06[3]-jobs-third-review.md`
> (три круга ревью кода того же пакета),
> `2026-09-03[2]-readme-review.md` (ревью README `solo`).

# Ревью документации `jobs` глазами пользователя

## Вердикт ревьюера

Проза README хорошая: плотная, без воды, каждый абзац о деле. Утверждения
о поведении — исходы, дети, `handler` с именем ребёнка, поздние значения,
два пути ошибки, необслуженный `Failed` в зону — я проверил прогонами, и
все до одного оказались верны. Техническая сторона публикации чистая:
`dry-run` без предупреждений, `dart doc` без единого warning, pana
150/160, пример pub.dev видит.

Мешает выйти к людям другое. README ни разу не называет механизм, которым
пакет работает: **отмена приходит в тело брошенным `Cancelled`**, и
`Cancelled implements Exception`. Слова «throw», «catch», «exception» в
README о теле задачи нет вообще. Дартдок это говорит, титульная страница —
нет, а привычный `try/catch` вокруг тела глушит отмену молча: тело идёт
дальше, исход при этом остаётся `Cancelled`, и найти это в чужом коде
почти нельзя. Это находка 1, единственная критическая.

Рядом с ней — три вещи, каждая из которых стоит новичку получаса.
«Quick start», запущенный ровно как написан, **не входит в тело**: отмена
приходит раньше стартовой микротаски, и все пять строк работы с
контекстом, ради которых пример и написан, не исполняются. `ctx.each` —
публичный член, ради которого стоит брать пакет для стримов, — в README
отсутствует целиком, а тот способ, который README подсказывает вместо
него, оставляет подписку висеть навсегда (прогон ниже: программа не
завершается). И заголовок обещает «A cancellable `Future`», тогда как
`Job` — не `Future`; `await job` компилируется и возвращает саму задачу.

Публиковать это можно: ничего из перечисленного не ломает код и не требует
смены версии. Но README сегодня экономит слова там, где пользователь
платит временем, и все четырнадцать находок закрываются правкой одних
только документов — кода трогать не нужно ни в одной.

## Что проверено

Стенд: `<scratchpad>/bench` — отдельный пакет `jobs_doc_bench` с
`jobs` по пути `/Users/user/development/my/solo/packages/jobs`,
`dart pub get`, `analysis_options.yaml` скопирован из пакета. Локально
Dart SDK 3.13.0 (stable, macos_arm64).

Собраны и прогнаны **все** фрагменты: восемь блоков `dart` из README
(девятый блок — `sh` с `dart pub add`), семь фрагментов из дартдоков
(`Job(...)`, `Job.ignore`, `wait`, `join`, `uncancellable`, `onCancel`,
`each`) и `example/example.dart`. Недостающие типы (`Database`,
`CancelToken`, `device`, `api`) объявлены в общем `stubs.dart` — их пришлось
придумать, но это нормальная цена иллюстративного фрагмента, находкой я это
не считаю.

```
$ dart analyze bin
  error - d07_each.dart:16:45 - The method 'emit' isn't defined for the
          type 'JobContext'. - undefined_method
1 issue found.
```

Единственный некомпилируемый фрагмент во всём пакете — пример `each` в
дартдоке (находка 4). Остальные пятнадцать компилируются и запускаются;
вывод каждого сверен с окружающей прозой. Отдельно прогнаны девять проб
поведения: старт с отменой на той же полосе и через 10 мс, диспозеры
`wait` против `join`, поздние значения, отмена ребёнка через `child.value`,
четыре пути ошибки, `whenCancelled` в трёх случаях, стрим двумя способами,
проглоченный `Cancelled`, `MyJob` из «Building on the core».

Проверки публикации из `packages/jobs`:

```sh
dart pub publish --dry-run   # Package has 0 warnings; 30 KB, 25 файлов
dart doc                     # Found 0 warnings and 0 errors; 1 public library
```

В архив идут `README.md`, `CHANGELOG.md`, `LICENSE`, `pubspec.yaml`,
`analysis_options.yaml`, `lib/`, `example/example.dart` и `test/`.
`README.ru.md`, `doc/api/` и `pubspec.lock` не идут — `.pubignore` и
корневой `.gitignore` отработали. `python3 tool/check_translations.py`
зелёный.

pana 0.23.19 на пакете (полный отчёт — `<scratchpad>/pana/jobs.json`):

```
TOTAL 150 / 160
[20/30] Follow Dart file conventions (failed)
        [x] 0/10 Provide a valid `pubspec.yaml`
            Failed to verify repository URL.
            Repository URL doesn't exist.
[20/20] Provide documentation (passed)
        [*] 10/10 99.1 % API элементов с дартдоком (108 из 109)
        [*] 10/10 Package has an example
[20/20] Platform support   [50/50] Pass static analysis
[40/40] Support up-to-date dependencies
tags: sdk:dart, sdk:flutter, все шесть платформ, is:wasm-ready,
      is:dart3-compatible, license:osi-approved
```

Пример pub.dev **видит**: `example/example.dart` — кандидат из списка pana,
и десять баллов за пример начислены. Вкладка Example покажет исходник
файла (`example/README.md` нет, и он не нужен). Единственные потерянные
десять баллов — за `repository` (находка 14).

## Находки

### 1. [critical] README ни разу не говорит, что отмена приходит в тело брошенным `Cancelled`

`README.md:81-99` — весь раздел «Cancellation». Механизм назван словами
«ends the waiting», «gives up», «refuses», «fires». Ни «throw», ни «catch»,
ни «exception» в README о теле задачи нет: три единственных вхождения
`throw` (`:75-76`, `:151`) — про `job.value` и про хук наблюдателя.
Раздел «Outcomes» вводит `Cancelled` как **исход**, а не как исключение,
которое летит сквозь тело.

Между тем `outcome.dart:88-93`: `final class Cancelled extends
Outcome<Never> implements Exception`, и дартдок там же — «Thrown by every
[JobContext] member once the job is marked cancelled». То есть API-справка
это говорит, титульная страница — нет.

Чего это стоит. Тело, написанное обычным аккуратным дартистом с README в
руках, глушит отмену первым же `catch`:

```dart
final job = Job<String>((ctx) async {
  try {
    await ctx.wait(() => step('read'));
    await ctx.wait(() => step('write'));
    await ctx.wait(() => step('commit'));
  } on Exception catch (e) {
    print('  [body] caught $e, carrying on');
  }
  await ctx.wait(() => step('cleanup'));

  return 'all done';
});
```

Прогон (`bin/p9_swallowed.dart`, отмена на 30-й мс):

```
  did read
  cancel() ...
  [body] caught Cancelled(manual), carrying on
  outcome: Cancelled(manual)
  did write
```

Тело поймало отмену и пошло дальше; `did write` печатается уже после того,
как `cancel()` вернулся и исход объявлен. Исход при этом честный —
`Cancelled(manual)`, — и в этом худшая часть: снаружи всё выглядит
правильно, а тело отработало половину лишней работы. Отладить такое по
исходу невозможно, потому что исход не врёт.

Направление правки: одна фраза в начале «Cancellation» — что члены
контекста бросают в тело `Cancelled`, что `Cancelled` — это `Exception`, и
что `catch` вокруг них отменяет отмену. И вторая: как ловить свои ошибки, не
глуша чужую отмену (`on Cancelled { rethrow }` или ловить конкретный тип).

**Вердикт (2026-09-06):** Принято. «Cancellation» теперь открывается
механизмом: пометка доходит до тела броском, каждый член контекста бросает
`Cancelled`, а `Cancelled` — это `Exception`, поэтому достаточно широкий
`catch` его глотает, и исход при этом остаётся `Cancelled`. Рядом фрагмент
с `on Cancelled { rethrow; }` и абзац о том, почему проглоченную отмену
дорого искать. Прогон стенда на обоих телах: с `rethrow` тело
останавливается на месте, с голым `on Exception` печатает «caught
Cancelled(manual), carrying on» и идёт дальше; исход у обоих
`Cancelled(manual)`.

### 2. [important] «Quick start», запущенный как написан, не входит в тело

`README.md:31-51`. Отмена стоит сразу за конструктором:

```dart
job.cancel().ignore();
```

а `README.md:53-55` тут же объясняет, что тело стартует следующей
микротаской. Значит, к моменту `cancel()` задача ещё в `created`, и она
завершается, не начавшись. Прогон (`bin/p1_quickstart_probe.dart`, тело и
все методы `Database` инструментированы печатью):

```
README Quick start, verbatim (cancel on the same stripe):
  outcome: Cancelled(manual)  started=false
```

Ни `body entered`, ни `open() called`, ни `close()`. Ни `join`, ни `wait`,
ни `uncancellable`, ни `ifCancelled` — ничего из показанного не
исполняется. Первая программа читателя демонстрирует ровно один факт:
«отменённая до старта задача не стартует».

Тот же код с задержкой в 10 мс перед отменой — а это ровно то, что делает
`example/example.dart:42` — показывает всё:

```
Same body, but cancelled 10 ms in (as example/example.dart does):
  body entered
  open() called
  close()
  outcome: Cancelled(manual)  started=true
```

Заодно: `docs/handoff.md:249-252` утверждает, что `example/example.dart` —
это «Quick start» целиком. Это не так. Пример добавляет `key: 'open'`,
задержку и комментарии, и **выбрасывает** строку
`await ctx.uncancellable(database.markReady);` — единственное место, где
показан `uncancellable`. То есть постоянного стенда у главного фрагмента
README, ради которого пример и заводился (находка 12 первого круга), так и
нет: пример проверяет свою редакцию, а не README.

Направление правки: в «Quick start» поставить между конструктором и
`cancel()` то же ожидание, что в примере, и привести `example/example.dart`
к фрагменту дословно — тогда стенд наконец совпадёт с текстом.

**Вердикт (2026-09-06):** Принято. Между конструктором и `cancel()` в
«Quick start» встало то же десятимиллисекундное ожидание, что в примере, а
абзац под фрагментом объясняет, зачем оно и что бывает без него.
`example/example.dart` приведён к фрагменту дословно: вернулась строка
`await ctx.uncancellable(database.markReady)`, у фальшивой `Database`
появился `markReady()`, `key: 'open'` снят. Пример печатает `database
closed` и `Cancelled(manual)`; README называет его стендом этого
фрагмента.

### 3. [important] `ctx.each` в README нет вовсе, а способ, который README подсказывает вместо него, течёт

`README.md` — ни одного вхождения слова `each` (проверено `grep`).
`CHANGELOG.md:14-15` о нём пишет: «`ctx.each` follows a stream for as long
as the job lives». `lib/src/job_stream.dart:29` его экспортирует. То есть
пользователь узнаёт о члене из changelog или из автодополнения, но не из
документа, по которому решает, брать ли пакет.

Раздел «Cancellation» (`:87-96`) перечисляет пятерых — `wait`, `join`,
`uncancellable`, `onCancel`, `check` — и стрима среди них нет. Человек с
потоком событий (сокет, датчик, прогресс загрузки — типичная отменяемая
работа) собирает из README вот это:

```dart
await ctx.wait(() => ticks().forEach((e) => print('  got $e')));
```

Прогон (`bin/p6_stream.dart`, отмена на 35-й мс):

```
-- README-only way: ctx.wait(() => stream.forEach(...)) --
  got 0 / got 1 / got 2
  job outcome: Cancelled(manual); waiting 50 ms more...
    source emitted 3
  got 3
    ... got 4 ... got 13 ...
```

Подписка живёт после отмены, колбэк продолжает работать, источник не
закрыт, программа не завершается вообще (прогон я снял по таймауту в две
минуты). Это ровно то, от чего пакет и защищает, — и README ведёт прямо в
эту яму. С `ctx.each` в том же прогоне:

```
-- ctx.each --
  got 0 / got 1 / got 2
    source cancelled
  job outcome: Cancelled(manual)
```

Направление правки: шестой пункт в список «Cancellation» и короткий
фрагмент — `await ctx.each(stream, onData)`, с фразой, что подписка живёт
ровно столько, сколько задача.

**Вердикт (2026-09-06):** Принято. `ctx.each(stream, onData)` — третий
пункт списка в «Cancellation», с тем, что подписка снимается в момент
пометки, до того как тело узнает об отмене, и слушать не остаётся никто.
В соседнем фрагменте — `Job<void>((ctx) => ctx.each(socket.messages,
handle))`. Способ через `stream.forEach` README больше не подсказывает.

### 4. [important] Единственный некомпилируемый фрагмент пакета — пример `each` в дартдоке

`lib/src/job_stream.dart:26-28`:

```dart
/// await ctx.each(hw.positions, (p) => ctx.emit(Tracking(p)));
```

`emit` — член `SoloContext` из `solo`, а не `JobContext` из этого пакета.
Фрагмент приехал вместе с кодом при выносе ядра и остался. `dart analyze`
на стенде:

```
error - d07_each.dart:16:45 - The method 'emit' isn't defined for the type
        'JobContext'. - undefined_method
```

`docs/conventions.md:34-35` требует прямо: «Примеры в dartdoc — минимальные
и компилируемые». Здесь нарушено не «минимальные»: `Database` и `device` в
соседних дартдоках тоже не объявлены, и это нормально — читатель видит свой
тип. А `ctx.emit` читается как член того самого `ctx`, который у читателя в
руках; он пойдёт его искать и не найдёт. Единственный фрагмент пакета,
который врёт про его собственное API.

Направление правки: заменить на член ядра — `ctx.log(p)` или присваивание
в локальную переменную.

**Вердикт (2026-09-06):** Принято. `job_stream.dart:27` — теперь
`ctx.log('at $p')` вместо `ctx.emit(Tracking(p))`. Все фрагменты пакета
собраны в стенде заново: `dart analyze` чист, `dart doc` — 0 warnings и 0
errors.

### 5. [important] «A cancellable `Future`», но `Job` — не `Future`, и README этого нигде не говорит

`README.md:3` и `pubspec.yaml:2-4` — первая строка, которую человек видит
и на pub.dev, и в результатах поиска: «A cancellable `Future`». Дартдок
`job_base.dart:12-14` честно предупреждает: «Not a [Future]: a method that
starts a job may be called without an `await`... Await [done], [value] or
[whenCancelled] where you need to». В README этого предупреждения нет.

Чего это стоит. `await job` — первое, что напишет человек, купившийся на
заголовок, — компилируется:

```
$ dart analyze bin/p5_await_job.dart
   info - Uses 'await' on an instance of 'Job<int>', which is not a subtype
          of 'Future'. - await_only_futures
$ dart run bin/p5_await_job.dart
await job -> _AutoJob<int>
```

Всего лишь `info`, и только если у человека включён
`package:lints/recommended` (в чистом проекте по `dart create` — включён, в
чужом наборе может и не быть). Без него `await job` молча возвращает саму
задачу, типизированную как `Job<int>`, и код едет дальше с мусором.

Направление правки: во второй абзац «Why» или сразу под заголовок — одна
фраза «`Job` is not a `Future`: await `done` or `value`». Метафора в
заголовке при этом остаётся, она хорошая; её просто надо закрыть.

**Вердикт (2026-09-06):** Принято. Вторым абзацем под заголовком, до
«Why»: «`Job` is not a `Future`, and nothing awaits it directly» с
указанием на `done` и `value`. Метафора в заголовке и в `description`
пакета осталась — закрыта, а не убрана.

### 6. [important] `wait(ifCancelled:)` никто не ждёт, `join(ifCancelled:)` ждут — README подаёт их одинаково

`README.md:87-90`:

```
- `ctx.wait(action)` ends the waiting, not the work. The action runs on,
  its result is dropped — or handed to `ifCancelled`.
- `ctx.join(action)` waits for all of the action and gives up afterwards
```

Из этого читается, что `ifCancelled` — одна и та же вещь у обоих. Она
разная, и разница — про порядок с внешним миром. `job_context.dart:36-42`
про `wait`: «It runs late and alone — the job is over by then and nothing
waits for it, not even the closing of an engine». `job_context.dart:76-82`
про `join`: «It is awaited before the [Cancelled] is thrown, so an engine
waiting for the job waits for the disposal too, and the next job starts
with the resource gone». Прогон (`bin/p2_wait_vs_join.dart`, диспозер сам
по себе занимает 5 мс):

```
-- ctx.wait(..., ifCancelled:) --
  cancel() returned; outcome=Cancelled(manual)
  <- is the disposer done here?
  [late] disposer for A ran

-- ctx.join(..., ifCancelled:) --
  [late] disposer for B ran
  cancel() returned; outcome=Cancelled(manual)
  <- is the disposer done here?
```

Чего это стоит. Классический сценарий — «отменил и сразу переоткрыл»:
`await job.cancel(); final next = open();`. С `join` ресурс к этому моменту
закрыт, с `wait` — ещё нет, и второе открытие идёт против живого первого.
Это та самая цена, о которой README умалчивает, и найти её можно только в
API-справке.

Направление правки: одна фраза к пункту про `wait` — что диспозер там
поздний и его никто не ждёт, в отличие от `join`.

**Вердикт (2026-09-06):** Принято. В пункте про `wait` сказано, что
`ifCancelled` работает поздно и один и что его никто не ждёт; в пункте про
`join` — что его дожидаются до броска `Cancelled`, так что ждущий задачу
дождётся и освобождения.

### 7. [important] «Building on the core»: задачу из фрагмента нельзя запустить

`README.md:199-215` — фрагмент, ради которого пакет и выделен из `solo`:
`MyJob<T> extends JobBase<T>` плюс `MyContext extends JobContextBase`.
Компилируется (проверено). Но запустить получившуюся задачу читатель не
может: `job_base.dart:399-400` — `@protected void start()`.

```
$ dart analyze bin/p8_start_protected.dart
warning - The member 'start' can only be used within instance members of
          subclasses of 'JobBase'. - invalid_use_of_protected_member
```

Проза это, строго говоря, объясняет: `:194-197` перечисляет `the start` среди
защищённого, а `:221-222` советует «private wrappers on its own subclass».
Но во фрагменте обёртки нет, и читатель, скопировавший его целиком, упирается
в тупик на первом же шаге — у него объект, который нечем оживить. Ядро само
решает это одной строкой (`job_base.dart:683-684`:
`void start() => super.start();` в `_DeferredJob`), и во фрагменте её не хватает
ровно так же.

Направление правки: добавить во фрагмент строку публичной обёртки старта и
показать её вызов — три строки, и раздел становится рабочим.

**Вердикт (2026-09-06):** Принято. Во фрагменте появилась
`void launch() => start();` с комментарием, зачем она, и строка
`final job = MyJob<int>((ctx) => ctx.wait(load))..launch();`. Абзац про
`@protected` и приватные обёртки теперь ссылается на неё прямо. Прогон
стенда: `Done(3)`.

### 8. [important] Ответ на «нужен ли мне второй пакет» лежит на 224-й и 226-й строках

Человек, попавший на страницу `jobs`, первым делом спрашивает: а что тогда
`solo`, и не надо ли брать оба. README отвечает дважды, и оба раза внизу:
`:224` — «`solo` is built this way, and re-exports this package whole» —
спрятано в конце «Building on the core», раздела для тех, кто пишет свой
движок; `:226-231` — секция `## solo`, самая последняя.

«Why» (`:7-21`) о `solo` не говорит вовсе, и нигде прямым текстом не
сказано главного следствия из «re-exports whole»: **пользователю `solo`
не нужно добавлять `jobs` в `pubspec.yaml`**. Сегодня это надо вывести
самому из фразы в чужом разделе.

Заодно `:228` ведёт на `https://pub.dev/packages/solo`, которого между
публикацией `jobs` и публикацией `solo` не существует.
`docs/handoff.md:66-68` это признаёт и называет терпимым, если публиковать
подряд, — согласен, отдельной находкой не считаю, но раз связка идёт
подряд, стоит просто не разрывать её.

Направление правки: одна строка в «Why» — что это ядро, вынутое из `solo`,
что `solo` его переэкспортирует целиком и что брать оба не нужно.
Симметрия с `packages/solo/README.md:30`, где обратная ссылка уже стоит
ровно там, где надо.

**Вердикт (2026-09-06):** Принято. Последний абзац «Why» говорит, чего
в пакете нет — состояния, очереди, правил, повторов, таймаутов, пула, — и
что это ядро `solo`, который реэкспортирует его целиком, поэтому зависящий
от `solo` от `jobs` отдельно не зависит. Та же мысль одной строкой
повторена в разделе `solo`.

### 9. [minor] `JobObserver` показан через `implements` с четырьмя переопределениями

`README.md:154-169`: `final class Log implements JobObserver` и все четыре
хука. `observer.dart:8-25`: `abstract class JobObserver` — обычный класс, у
всех четырёх хуков пустые тела по умолчанию. То есть достаточно:

```dart
final class OneHook extends JobObserver {
  @override
  void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');
}
```

Проверено прогоном (`bin/p4_errors.dart`): работает, печатает
`Job(c): Done(3)`. README об этом не говорит, и человек, которому нужен
один `onError`, напишет четыре метода, три из которых пустые. Мелочь, но
она стоит на пути самого частого сценария «хочу видеть ошибки».

Направление правки: показать `extends` с одним хуком, а про `implements`
сказать словом — что он тоже годится, когда наблюдатель уже что-то
наследует.

**Вердикт (2026-09-06):** Принято. Фрагмент — `final class Log extends
JobObserver` с одним `onFinish`; проза говорит, что у всех четырёх хуков
тела пустые и что `implements` тоже годится, когда слушатель уже что-то
наследует.

### 10. [minor] `key` и `describe` не введены — весь журнал состоит из `Job(null)`

`README.md` не упоминает ни `key`, ни `describe`; единственное вхождение
слова `key` — `super.key` во фрагменте `:203`, где оно ничего не
объясняет. Между тем `job_base.dart:617-621`: `toString()` печатает
`Job($key)`, а `:84-92` описывает оба параметра.

Следствие видно прямо в прогонах README-фрагментов: «Building on the core»
печатает `built Job(null)`, а раздел «Observer» — единственное место, где
`toString` вообще показан читателю, — работает у меня только потому, что я
сам дописал `key: 'x'`; во фрагменте README ключа нет, и весь журнал
наблюдателя выглядел бы как `Job(null): Done(1)`.

Направление правки: `key:` во фрагменте «Observer» и полстроки о том, что
ключ — это то, чем задача называется в журнале (и то, по чему `solo`
сравнивает задачи в очереди).

**Вердикт (2026-09-06):** Принято. Во фрагменте наблюдателя `key:
'load'` и `observer: Log()`, в комментарии — вывод `Job(load): Done(3)`
(прогон стенда даёт ровно его). Абзац под фрагментом объясняет, что задача
печатает себя как `Job($key)`, что по ключу её сравнивает движок сверху и
что добавляет `describe`.

### 11. [minor] Правило «тело ничего не ждёт само» заявлено как факт и нарушено в собственном фрагменте

`README.md:19-21`: «the body never awaits anything by itself: every call
goes through the context». Сказано как свойство пакета, а это правило,
которое пакет соблюсти не может: `await foo()` в теле никто не перехватит,
зоны тут нет. `:83-85` повторяет ту же формулировку.

А `:135-140`, «Late values», сам её нарушает:

```dart
final job = Job<Database>(
  ifCancelled: (database) => database.close(),
  (ctx) async => Database.open(),
);
```

`async =>` ждёт `Database.open()` мимо контекста. Для показа `ifCancelled`
это сокращение оправдано — фрагмент, кстати, работает ровно как обещано
(прогон: отмена на 10-й мс даёт `close()` и `Cancelled(manual)`), — но
читатель видит правило и тут же контрпример, и не понимает, насколько
правило обязательно.

Направление правки: «never» → «must never» (или «нигде в этом README, кроме
фрагмента ниже, где это сокращение»), и одна фраза о цене нарушения:
прямой `await` не узнает об отмене.

**Вердикт (2026-09-06):** Принято. В «Why» и в «Cancellation» — «must
never await anything by itself», и там же цена: прямой `await` не ошибка
Dart, он слеп, ему никто не скажет, что задача кончилась. Во фрагменте
«Late values» ничего менять не пришлось: под ним теперь стоит абзац о том,
что прерывать в этом теле нечего — оно отдаёт ядру future, ядро её и ждёт,
— и что это единственное место, где обход контекста ничего не стоит.

### 12. [minor] `whenCancelled` описан сильнее, чем он есть

`README.md:76-78`: «`job.whenCancelled` completes the moment the job is
marked cancelled, before the body finishes». Дартдок `job_base.dart:126-132`
честнее и разбирает три случая, третий из которых README и опровергает:
тело, отменившее себя через `throw Cancelled(...)`, ничем заранее не
отмечено, и `whenCancelled` завершается только вместе с задачей. Прогон
(`bin/p7_whencancelled.dart`):

```
-- README claim --
  [a] whenCancelled fired
  [a] body still inside join          <- верно, до конца тела
-- body that cancels itself --
  [b] about to throw Cancelled
  [b] whenCancelled fired             <- уже после того, как тело кончилось
  [b] outcome Cancelled(handler: no reason to go on)
```

Цена низкая (кто ждёт `whenCancelled`, обычно не он же и бросает
`Cancelled`), но это ровно тот случай, когда README обещает больше кода.

Направление правки: снять «the moment» до «completes on every `Cancelled`
outcome», как в дартдоке, — или дописать оговорку про самоотмену.

**Вердикт (2026-09-06):** Принято. Формулировка снята до дартдоковой:
завершается на любом исходе `Cancelled`; у работающей задачи — в момент
пометки, ещё до конца тела, у тела, отменившего себя само, — вместе с
концом задачи.

### 13. [minor] Цена отмены при детях не названа: `ctx.run` у отменённого родителя бросает и роняет ребёнка

`README.md:109-126` описывает детей полно и верно (каскад, ожидание,
`handler` с именем ребёнка — всё проверил прогоном,
`bin/p3_late_and_children.dart` даёт
`Cancelled(handler: child rows: Cancelled(manual))`). Не сказано, что
`ctx.run` умеет отказать: `job_context.dart:155-158` перечисляет
`ArgumentError` для чужого хэндла, `StateError` для уже запущенного и —
самое важное — «the parent's own `Cancelled`, with the child dropped, if
the parent is already cancelled».

То есть в гонке «родителя отменили ровно тогда, когда тело запускает
ребёнка» ребёнок создаётся, немедленно получает `Cancelled(parent)` и
выбрасывается, а тело получает свою отмену. Тело, где `ctx.run` стоит после
долгого `await`, попадает в это регулярно. README на эту тему молчит.

Направление правки: полстроки в «Children» — что `run` у отменённого
родителя бросает родительскую отмену, а ребёнок не запускается.

**Вердикт (2026-09-06):** Принято. Абзац в «Children»: чужой для этого
ядра хэндл — `ArgumentError`, уже запущенная задача — `StateError`, а уже
отменённый родитель бросает собственный `Cancelled` и роняет ребёнка —
на это наткнётся тело, запускающее детей после долгого ожидания.

### 14. [minor] pubspec: нет `topics` и `issue_tracker`, а `repository` сегодня отдаёт 404

`pubspec.yaml:1-9`. Три вещи.

**`topics` нет** — ни у `jobs`, ни у двух соседей. Пакет с именем `jobs`
про отмену фьючеров конкурирует за внимание с `async`, `cancellation`,
`cancelable_operation`; топики — единственный механизм pub.dev, которым
человек, ищущий «cancellation», может на него набрести. Баллов pana за них
не даёт, но и не отнимает — это чистая находимость. Напрашиваются
`cancellation`, `async`, `concurrency`, `state-management`.

**`issue_tracker` нет.** pub.dev выведет ссылку из `repository`, но
`repository` указывает в подкаталог монорепозитория, и куда именно уедет
«View/report issues», не проверить, пока пакета нет на pub.dev. Строка
стоит одну.

**`repository` сегодня 404.** pana снимает за это ровно те десять баллов,
которых пакету не хватает до 160:

```
[x] 0/10 points: Provide a valid `pubspec.yaml`
    Failed to verify repository URL.
    Repository has no matching `pubspec.yaml` with `name: jobs`.
    Repository URL doesn't exist.
```

Причина точная и лечится сама:

```
$ curl -I -L https://github.com/vi-k/solo                          -> 200
$ curl -I -L https://github.com/vi-k/solo/tree/main/packages/solo  -> 200
$ curl -I -L https://github.com/vi-k/solo/tree/main/packages/jobs  -> 404
$ git ls-tree --name-only origin/main packages/
packages/flutter_solo
packages/solo
```

`packages/jobs` ещё не запушен — он весь в тех 33 локальных коммитах, о
которых пишет `docs/handoff.md:213-215`. Порядок связки в
`AGENTS.md` ставит push перед `dart pub publish`, так что при соблюдении
порядка проблемы не будет. Но проверить это стоит одной командой, а цена
ошибки — пакет, вышедший на люди со 150/160 и без отметки о проверенном
репозитории.

Направление правки: `topics` и `issue_tracker` в pubspec; перед
`dart pub publish` — `curl -I -L` на `repository` каждого из трёх пакетов,
уже после push.

**Вердикт (2026-09-06):** Принято частично. `issue_tracker` и `topics`
(`async`, `cancellation`, `concurrency`) стоят в `pubspec.yaml` пакета.
404 у `repository` здесь не правится: он лечится push'ем, который в связке
публикации и так стоит перед `dart pub publish`, — проверка `curl -I -L`
на `repository` всех трёх пакетов после push вписана в «Следующие шаги»
handoff. У `solo` и `flutter_solo` топиков по-прежнему нет: их `pubspec`
в предмет этого ревью не входил, и решение о топиках соседей за
владельцем.

## Что дописать

README отвечает на вопросы первого дня и молчит про второй. Чего в нём нет
и что человек спросит:

- **Как это тестировать.** Ни слова. У самого пакета 82 теста на
  `package:fake_async` — приём рабочий и неочевидный (задачи стартуют
  микротаской, `scheduleMicrotask` вместо `Future(...)` выбран именно ради
  `FakeAsync`, `job_base.dart:660-661`). Десять строк с `fakeAsync` и
  проверкой исхода закрыли бы вопрос целиком. Для пакета про асинхронность
  это самый частый второй вопрос после «как отменить».
- **Как жить с Flutter.** Слова «Flutter» в README нет. pana проставил
  `sdk:flutter` и все шесть платформ — то есть ответ «никак специально, всё
  работает», и его надо просто сказать, вместе с указанием на
  `flutter_solo` для тех, кому нужен виджетный слой.
- **Что этот пакет не делает.** Нет очереди, нет состояния, нет `retry`,
  нет `timeout`, нет пула. Для решения «моё / не моё» за 60 секунд граница
  важнее половины возможностей: сейчас её приходится выводить из того, чего
  в README не написано.
- **Чем это отличается от `CancelableOperation`.** `:10` называет его в
  ряду «the usual answers» и дальше не возвращается. Три строки — исход
  вместо `null`, дети, кооперативные точки проверки внутри тела,
  наблюдатель — и вопрос закрыт. `Completer` и `Stream` из задания в
  README не упоминаются вовсе; `Completer` упоминать, по-моему, и не надо,
  а вот `Stream` стоит — вместе с `each` (находка 3).
- **Куда идти за справкой.** Ссылки на API-доки в README нет (для `solo`
  это находка M14 из `2026-09-03[2]-readme-review.md`, отклонённая).
  pub.dev даёт свою кнопку, так что это не обязательно, — но у `jobs`
  половина API (`JobBase`, `JobContextBase`, `@protected`-поверхность)
  живёт только в справке, и раздел «Building on the core» без ссылки
  обрывается на полуслове.
- **`cancellable: false`** назван в прозе (`:98`), но ни разу не показан
  как аргумент конструктора. Читателю приходится догадываться, что это
  именованный параметр `Job(...)`, а не что-то из движка сверху.

**Вердикт (2026-09-06):** Написано всё, кроме одного. Тестирование —
новый раздел «Testing» с фрагментом на `fakeAsync` (в стенде прогнан как
настоящий тест, зелёный) и правилом «`Future(...)` — таймер, а не
микротаска». Flutter — строка в разделе `solo`. Границы пакета — последний
абзац «Why». `CancelableOperation` — отдельный абзац там же; `Stream`
закрыт через `each` (находка 3). Ссылка на справку — в конце «Building on
the core», на `JobBase`. `cancellable: false` показан как `Job(body,
cancellable: false)`. Не написан только `Completer`: ревьюер сам считает,
что он и не нужен.

## Что хорошо

Не трогать:

- **Проза.** Плотная, ритмичная, без маркетинга и без воды; каждый абзац
  несёт факт. Формулировки вроде «`wait` lets go of the action, `join`
  stays with it» стоят абзаца объяснений. Это редкое качество, и оно и
  делает README читаемым за минуту.
- **Точность утверждений о поведении.** Я проверил прогоном всё, что README
  обещает про исходы, детей, каскад, `handler` с именем ребёнка, поздние
  значения, порядок «дети → диспозер → исход», два пути ошибки и уход
  необслуженного `Failed` в зону. Все сошлись, ни одного «никогда» или
  «всегда» без основания я не нашёл. Раздел «Observer» (`:171-176`) о двух
  путях ошибки — образцовый: он честно называет и то, что молчание есть
  выбор слушателя.
- **Дартдок.** 99,1 % публичного API (108 из 109), `dart doc` без единого
  warning. Он местами точнее README (находки 1, 5, 6, 12 — все закрываются
  переносом фразы из дартдока наверх), и по нему видно, что человек,
  дошедший до справки, получит правильный ответ.
- **`example/example.dart`.** Запускается, печатает ровно то, что обещает
  комментарий в нём (`// Cancelled(manual)`), и в отличие от «Quick start»
  показывает настоящий путь отмены с диспозером. pub.dev его видит.
- **Публикационная гигиена.** `dry-run` без предупреждений, 30 КБ, ничего
  лишнего в архиве: `README.ru.md`, `doc/api/` и `pubspec.lock` отсечены
  правильно. `CHANGELOG.md` для первого релиза необычно хорош — он
  читается как оглавление возможностей, а не как список коммитов.
  Переводы в синхроне.
