> **Состояние на 2026-10-03:** ревью дизайна и кода сделано в клоне; все
> девять находок разобраны и закрыты тем же коммитом, что и `ctx.pause`, итог
> стоит в вердикте каждой. Вопрос владельцу из находки 9 о примере
> в `outcomes.md` закрыт 2026-10-03: пример переведён на `ctx.pause`.
> **Что это:** независимое ревью `2026-10-03-ctx-pause-design.md` и кода
> `ctx.pause` на Opus — зонды, четырнадцать мутаций, девять находок.
> **Связанные записи:** `2026-10-03-ctx-pause-design.md`.

# Ревью ctx.pause: дизайн, код, тесты

Клон: `.artifacts/2026-10-03-ctx-pause/tree`, HEAD `917ad65`, поверх него
незакоммиченная правка. Зонды в клоне —
`.artifacts/2026-10-03-ctx-pause/review-probes/`: `pause_paths_test.dart`,
`real_loop.dart`, `solo_pause_test.dart`, `mutate_pause.py`. Все прогоны —
на Dart 3.13.0; прогон на полу 3.6.0 не делался.

## Находки

### 1. Medium. «No longer than this job lives» неверно на четырёх путях

Утверждение. Первая фраза dartdoc —
`Waits for [duration], but no longer than this job lives`
(`packages/async_job/lib/src/job_context.dart:239`), шапка дизайна — «пауза,
которая кончается вместе с задачей и уносит свой таймер». Верно только для
задачи, которая кончилась отменой. Если задача кончилась иначе, пауза и её
таймер доживают до конца `duration`.

Свидетельство — зонд `pause_paths_test.dart`:

- тело ушло через `unawaited(ctx.pause(1s))` и вернулось:
  `outcome=Done(1) finished=true timers=1`, через секунду `timers=0`;
- `Future.any([ctx.pause(1s), ctx.pause(100ms)])`: `outcome=Done(1) timers=1`;
- пауза в `unattended`, тело кончилось `Done`: `finished=true timers=1`, через
  секунду работа идёт дальше (`elapsed`), а следующая пауза бросает
  `StateError ... has already finished, cannot wait`;
- движок кончил задачу руками (`finish` во время паузы, `ProbeJob.drop`):
  `outcome=Cancelled(dropped) log=[] timers=1`, через секунду `log=[elapsed]` —
  пауза вернулась нормально, без `Cancelled`.

На настоящем цикле (`real_loop.dart -DWALKED=true`): задача `Done` через 52 мс,
процесс живёт ещё три секунды (`real 3.79` против `0.92`).

Это поведение `wait`, а не дефект `pause`: `_race` слушает только отмену
(`job_context.dart:1257`), а `finish` руками колбэки сбрасывает. В `solo`
четвёртого пути нет: `_drop` зовётся только для незапущенных задач
(`packages/solo/lib/src/solo.dart:478,493,519,762,774,1179,1183`). Самоотмена
тела при брошенной паузе таймер снимает:
`outcome=Cancelled(self) pauseEnd=Cancelled(self) timers=0`.

Предлагаю. Чинить текст, не код: «Waits for [duration], or until the job is
cancelled», и одной фразой сказать, что пауза, от которой тело ушло, идёт
до конца вместе с таймером — как любой вызов, от которого ушли. В дизайне
в «Поведении» дописать тот же пункт. Закрепить тестом хотя бы путь
`unawaited` + `Done` (`pendingTimers` длиной 1), чтобы обещание не вернулось.
Если владелец хочет именно обещанное — это другая конструкция (регистрация
на стеке уборки), и её надо проектировать отдельно: в `unattended` она
оборвала бы паузу нормальным возвратом.

**Вердикт.** Принято: чинится текст. Пауза ведёт себя как `wait`, и вызов,
от которого тело ушло, не её случай. Итог: первая фраза dartdoc — «Waits for
[duration], or until the job is cancelled», абзац о паузе, от которой ушли,
дописан в dartdoc и в «Поведение» дизайна; заголовок записи в `CHANGELOG.md` —
«a delay a cancellation ends». Сторож —
`a pause the body walked away from, in a job that ends Done`; мутация,
снимающая таймер в конце задачи, его роняет.

### 2. Low. Тест 4 не сторожит «таймер не создаётся»

Утверждение. `a pause in a job cancelled already` заканчивается проверкой
`pendingTimers, isEmpty` с причиной `no timer was made`
(`packages/async_job/test/pause_test.dart:83`). Она не отличает «не создан»
от «создан и снят в `finally`».

Свидетельство. Мутант M7 — таймер создаётся до `wait`, снимается в `finally` —
выживает: все девять тестов зелёные.

Предлагаю. В теле теста взять future без `await` и проверить сразу:
`final paused = ctx.pause(second); expect(async.pendingTimers, isEmpty);` —
таймер M7 создаётся синхронно в вызове и попадётся.

**Вердикт.** Принято. Итог: тест считает таймеры сразу после вызова,
до `await`; мутация «таймер до контрольной точки» роняет его и ещё два.

### 3. Low. «После паузы правило не переспрашивается» ничем не закреплено

Утверждение. Последняя фраза раздела «Поведение» верна, но ни один тест её
не держит, и запланированный тест в `solo` («кончается на отмене и спрашивает
`keepWhile` на входе») её тоже не покрывает.

Свидетельство. Мутант M11 — `check()` после `wait` внутри `pause` — выживает.
Что фраза верна, показывает зонд `solo_pause_test.dart`: `keepWhile` на внешнем
флаге, флаг сброшен посреди паузы без смены состояния — `log=[elapsed,
rule asked 1 time(s) around the wait, body went on, outcome=Done(null)]`,
и ровно то же у `ctx.wait(() => Future.delayed(...))`.

Предлагаю. Этот сценарий — третьим утверждением в тест `solo` (счётчик вызовов
`keepWhile` вокруг паузы равен 1). В `async_job` то же можно
на `CheckingContext` из `test/support/probe_job.dart`.

**Вердикт.** Принято. Итог: тест
`a rule that breaks during a pause is asked on the way in only`
в `packages/solo/test/cancel_delay_recipe_test.dart` — правило спрошено один
раз, исход `Done`. В `async_job` второго такого теста нет.

### 4. Medium. Список «Документы» в дизайне неполон

Утверждение. Кроме названного в дизайне, `pause` должна встать в перечисления
членов, и один пример в теле задачи в список не попал.

Свидетельство — перечисления, где сейчас `wait`, `join`, `uncancellable` и нет
`pause`:

- `packages/async_job/lib/src/job_context.dart:6` — члены, которые бросают
  принятую отмену; `:12` — «see [wait], [join] and [uncancellable]»;
- `packages/async_job/lib/src/job_context.dart:601` — «The fourth member of the
  waiting family»;
- `packages/async_job/lib/src/job_context.dart:696` — кто спрашивает `check`
  до действия;
- `packages/async_job/doc/cleanup.md:243` — что бросает `StateError` в уборке;
- `packages/async_job/doc/extending.md:215` — то же про `check()`;
- `packages/solo/doc/cancellation.md:289` — что бросает после конца задачи;
- `packages/solo/README.md:324` — строка таблицы про страницу Cancellation;
- переводы этих страниц в `docs/ru/` и `README.ru.md`.

Пример в теле — `packages/async_job/doc/outcomes.md:269`, см. находку 9.

Предлагаю. Дописать список в дизайне до коммита работы, чтобы приёмка шла
по нему.

**Вердикт.** Принято. Итог: `pause` вписана во все названные перечисления и их
переводы, кроме dartdoc `unattended` — «the fourth member of the waiting
family» там считает способы ждать действие, а пауза действия не ждёт. Список
в дизайне дополнен.

### 5. Low. Сообщение `StateError` называет `wait`, а не `pause`

Утверждение. Пауза в disposer и на законченной задаче бросает ошибку с чужим
глаголом.

Свидетельство. `real_loop.dart`:
`messages: [Job() is cleaning up after its body, cannot wait,
Job() has already finished, cannot wait]`. В том же файле порядок вызовов
подобран так, чтобы сообщение называло свой вызов
(`job_context.dart:1061-1063`, `1597-1600`).

Предлагаю. Первой строкой `pause` — `throwIfFinished('pause');`. Условия те же,
что у `wait`, меняется только текст. Тест 8 тогда может сверять сообщение.

**Вердикт.** Принято. Итог: `throwIfFinished('pause')` первой строкой, тест
`a pause in a disposer` сверяет `cannot pause`.

### 6. Low. Отрицательная длительность не описана

Утверждение. `Timer` считает отрицательную длительность нулевой; dartdoc
об этом молчит. Валидация не нужна: `Future.delayed` и `Future.pause` ведут
себя так же.

Свидетельство. `pause_paths_test.dart`, `negative duration`: после микротасок
`log=[] timers=1`, после `elapse(0)` — `log=[after] outcome=Done(null)`.
`real_loop.dart`: `negative duration took 0 ms`.

Предлагаю. Ничего в коде. По желанию — полфразы в dartdoc («a negative one
counts as zero») и строка в тесте 5.

**Вердикт.** Принято. Итог: полфразы в dartdoc и тест `a negative duration`.

### 7. Low. Пауза в колбэке `onCancel` уходит в зону мимо наблюдателя

Утверждение. Колбэк `onCancel` — `void Function()`, задача уже помечена,
и `ctx.pause(...)` там сразу кончается `Cancelled`; future никто не ждёт,
ошибка идёт в зону, а `onError` наблюдателя её не слышит.

Свидетельство. `pause called bare from an onCancel callback`:
`observer=[] outcome=Cancelled(manual) timers=0`,
`zone errors: [Cancelled(manual)]`. У `ctx.wait` там же то же самое:
`zone errors: [Cancelled(manual)]`. Таймер не создаётся.

Предлагаю. Не дефект `pause`, а общее свойство; новый член делает ошибку
вероятнее («подождать 100 мс и остановить устройство»). Хватит фразы в разделе
о паузе в `cancellation.md`: в `onCancel` время ждут так же, как в disposer, —
голым `Future.delayed` внутри `ctx.unattended`.

**Вердикт.** Принято частично. Итог: фраза в dartdoc `pause` — в колбэке
`onCancel` задача уже отменена, и пауза бросает сразу, — и тест
`a pause in a callback of onCancel`. На страницу рецепт с `ctx.unattended`
не встал: раздел о паузе говорит о теле задачи, а о колбэке, который
останавливается не сразу, страница уже говорит в «A token through `onCancel`».

### 8. Low. Двусмысленная фраза в дизайне

Утверждение. «…таймером нулевой длины, а не микротаской, как
`Future.delayed(Duration.zero)`» читается и как «`Future.delayed(zero)` —
микротаска». Это не так: там тоже таймер.

Свидетельство. `real_loop.dart`: `order: [microtask queued before the pause,
Timer.run queued before the pause, body after pause(), body after await null,
Timer.run queued after the pause]` — пауза встаёт в очередь таймеров по порядку
создания.

Предлагаю. Переставить: «таймером нулевой длины, как
`Future.delayed(Duration.zero)`, а не микротаской».

**Вердикт.** Принято. Итог: фраза дизайна переставлена.

### 9. Low. Где `Future.delayed` в публичных документах

В теле задачи:

- `packages/async_job/doc/children.md:554-556` — `ctx.wait` вокруг
  `Future.delayed`, тело `watchTicks`. В дизайне есть. Перевод:
  `docs/ru/async_job/children.md:554`.
- `packages/async_job/doc/outcomes.md:269` — голый `await Future.delayed`
  в теле ребёнка `cancellable: false`. В дизайне нет. Он изображает шаг,
  а не паузу; замена трассу не меняет — зонд `outcomes.md report`: в обоих
  вариантах `log=[at cancel: finished=false, step finished,
  cleanup] outcome=Cancelled(manual)`. Решение владельца: либо заменить
  (страница не учит голому `await` в теле), либо оставить как «работу шага».
  Перевод: `docs/ru/async_job/outcomes.md:269`.
- `packages/solo/doc/errors.md:308-309` — строки таблицы, остаются как первые
  попытки; строка `ctx.pause` добавляется. В дизайне есть.

Вне тела (не трогать):

- `packages/async_job/README.md:42`, `:138` — вызывающий код ждёт перед
  `job.cancel()`;
- `packages/solo/README.md:68` — заглушка `ProfileApi.fetchName`;
- `packages/solo/doc/testing.md:44` — `FakeProfileApi`; `:392` — проза о ней;
- `packages/async_job/doc/observing.md:605` — проза о `fake_async`.

В `packages/flutter_solo/README.md` и `doc/` совпадений нет. Примеры
(`async_job/example/example.dart:17,30,37,48,110`,
`solo/example/bin/main.dart:14`,
`solo/example/lib/src/fake_camera_hardware.dart:69`,
`flutter_solo/example/lib/main.dart:20`) — все вне тела: заглушки и вызывающий
код.

Попутно: в `packages/solo/test/support/run_solo.dart:62` живёт тестовый хелпер
`pause(ctx, ms)` — это `ctx.wait(() => delay(ms))`, его зовут десятки тестов.
Конфликта имён нет (функция верхнего уровня против члена), но тест `guarded`
в `cancel_delay_recipe_test.dart:55` стоит именно на нём и сторожит строку
таблицы `ctx.wait(() => Future.delayed(...))`. Строке `ctx.pause` нужен свой
тест с прямым вызовом члена; перевод хелпера на `ctx.pause` лишил бы сторожа
старую строку.

**Вердикт.** Принято. Итог: `watchTicks` переведён на `ctx.pause`; строка
таблицы в `errors.md` встала со своим тестом
`a pause of the context is reported as no delay, and leaves no timer`, хелпер
`pause(ctx, ms)` не тронут. Пример в `outcomes.md` оставлен как был — там
задержка изображает работу шага неотменяемого ребёнка — и передан владельцу
вопросом. Владелец 2026-10-03: «меняй голый await Future.delayed». Пример, его
перевод и `test/support/outcomes_page.dart` переведены на `ctx.pause`; ребёнок
неотменяемый, пауза идёт до конца, трассы страницы те же.

## Мутации против `pause_test.dart`

Скрипт `mutate_pause.py`, счёт по меткам `[E]`.

| мутант | итог | кто убил |
| --- | --- | --- |
| M1 таймер не снимается | убит | 2 |
| M2 `join` вместо `wait` | убит | 2 |
| M3 `uncancellable` вместо `wait` | убит | 2, 9 |
| M4 `Future.delayed` вместо таймера | убит | 2 |
| M5 микротаска при нуле | убит | 5 |
| M6 без `finally` | убит | 2 |
| M7 таймер до контрольной точки | **выжил** | — |
| M8 длительность игнорируется | убит | 1, 2, 6, 9 |
| M9 голая задержка и `check` | убит | 2 |
| M10 отмена проглочена | убит | 2, 4, 9 |
| M11 `check()` после паузы | **выжил** | — |
| M12 отказ в `unattended` | убит | 9 |
| M13 своя гонка без `wait` | убит | 8 |
| M14 свой `onCancel`, не снят | убит | 7 |

Таблица мутаций в дизайне подтверждается дословно. Пустых тестов нет: тест 3
кода `pause` не касается, но так и заявлен («сторож утверждения»); тест 6
отдельно убивает только M8 — он проверяет унаследованное от `wait`; тест 7
убивает M14. Не хватает: находки 1, 2, 3 и, по желанию, 6.

## Что держится

- На входе спрашивается `check()`: отменённая задача и нарушенное правило
  бросают сразу, таймеров 0 (`rule of a domain broken before the pause`).
- Отмена и правило домена во время паузы: тот же `Cancelled`, `timers=0`.
- Правило домена внутри `uncancellable` паузу обрывает
  (`thrown=Cancelled( rules: broken) timers=0`) — как и сказано в dartdoc
  `uncancellable`; обычная отмена придержана, тест 6.
- Колбэк `ctx.each`: отмена родителя — `threw Cancelled`, `timers=0`.
- Ветка `runAll`, брат упал: `outcome=Failed log=[threw Cancelled] timers=0`.
- Утечек через `finally` нет: `wait` — `async`, синхронно не бросает; таймер
  снимается только после конца `wait`, поэтому пути, где таймер снят, а future
  висит, нет. Вечной паузы не нашёл.
- Зона: таймер создаётся в зоне вызова, тело продолжается в своей зоне
  (`body resumes in "outer"`, `runZoned part resumes in "inner"`,
  `unattended ... fork mark=true`). Пауза внутри `runZonedGuarded` в теле
  получает отмену (`caught Cancelled`, `inner=[]`). Ошибка после паузы
  в `unattended` доходит до наблюдателя (`observer=[Bad state: late]`).
- «Следующим оборотом цикла событий»: верно, порядок — в находке 8.
- `Future.pause([Duration duration = Duration.zero])` в Dart 3.13 есть, подпись
  совпадает (`dart-sdk/lib/async/future.dart:464`).
- `solo`: `cancelAll`, `job.cancel`, `close` — `Cancelled`, `timers=0`
  (у `wait` + `Future.delayed` там же `timers=1`); `keepWhile` на входе спрошен
  один раз; смена состояния и выход из рабочего типа во время паузы кончают её
  с `Cancelled(rules: ...)`; `cancellable: false` — пауза идёт целиком. Всё
  совпадает с `ctx.wait(() => Future.delayed(...))`, кроме таймера.
- Ломающая правка: рукописного `implements JobContext` или
  `implements SoloContext` нет ни в трёх пакетах, ни в примерах, тестах,
  документах и переводах — только `extends JobContextBase` (18 мест) и сам
  `SoloContext`. Ни одна страница не учит фейку через `implements`.
- Имя: члена `pause` нет ни у наследников `JobContextBase`, ни у `SoloContext`.
  `pause()` в `packages/solo/doc/jobs.md:208` — метод контроллера.
- Гейт в клоне: `async_job` — формат чистый, `dart analyze` без замечаний,
  `dart test` +1231; `solo` — analyze чистый, +868; примеры обоих — analyze
  чистый; `flutter_solo` — `flutter analyze` чистый, `flutter test` +85,
  пример — analyze чистый, +4.

## Вердикт ревьюера

Коммитить можно: ошибок конструкции нет, Critical и High нет. Реализация делает
то, что обещает раздел «Поведение», на всех путях, где тело ждёт свою паузу.
До коммита стоит поправить три вещи: первую фразу dartdoc (находка 1), два
теста, которые не сторожат заявленное (находки 2 и 3), и список документов
в дизайне (находка 4). Остальное — Low, на усмотрение.
