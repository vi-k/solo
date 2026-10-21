# Волна по шестому полному ревью

> **Состояние на 2026-10-21:** сделано, в `main`, не отправлено. Закрыты
> находки волны по вопросу 1 обеих записей ревью и M2 ядра геттером
> `ctx.heldCancellation`; остальные вопросы ревью ждут ответа владельца.
> **Что это:** что сделано по находкам шестого ревью `async_job` и `solo`, чем
> проверено и что нашло независимое ревью сделанного на Opus.
> **Связанные записи:** `2026-10-21-async-job-project-review-3.md`,
> `2026-10-21-solo-project-review-3.md`,
> `2026-10-21-held-cancellation-design.md`.

## Что сделано

По ответам владельца 2026-10-21: волна по вопросу 1 обеих записей — да, геттер
`ctx.heldCancellation` — в 0.3.0, `Solo.run` не переименовывается. Вопросы
о форме dartdoc и страниц, `restart` с `ifCancelled`, обработчиках накопителя,
отказе `runAll` кодом, файлах примеров и разделении `add` и `_pump` владелец
решит позже; волна их не трогала.

### `solo`, коммит волны `solo`

- L1. `_SoloJob.cancelWith` больше не смотрит, правила ли причина отмены: флаг
  `_stateCorrectionRevoked` ставят до `cancelOwnJob` сами `_checkedState`
  и `stateAs`, как уже делал `Solo` при смене состояния. Три теста
  в `state_handlers_test.dart`; оба мутанта убиты.
- L3. Ветка `restart` в `Solo.add` пишет в отладку ответ текущей задачи:
  отменена, придерживает отмену до конца секции или отказывает. Тест
  в `hooks_test.dart`.
- L2, L7. Dartdoc `SoloCloseMode.drain`, `SoloAccumulator.add`
  и `AccumulationPolicy.replace`.
- L6. Черновые строки убраны из трёх `analysis_options.yaml`.
- L8–L12, L14. README: абзац после `main()` короче; фраза о выводе типов
  в README и `doc/jobs.md`; первый пункт «Breaking changes» `CHANGELOG.md`
  начинается с действия; `SoloSelection.from` в `CHANGELOG.md` `flutter_solo`;
  в `mistakes.md` помощники названы до «Don't do this»; четыре строки
  `reference.md` короче. Переводы тем же коммитом.

### Ядро

- M1. Пункт о дедлайне и секции в `doc/time.md`, dartdoc `timeout` у `Job.new`
  и `TimeoutCancelReason`: запрос ложится, когда секция закрывается, раньше
  `return`, задача кончается `Cancelled(timeout)`, значение секции не доходит
  ни до исхода, ни до `value`, и регистрации `onDiscard` срабатывают. «Ends
  with what the body returned» — только о теле, которое не дождалось секции,
  со ссылкой на «Holding the cancellation back». Ссылка ведёт на раздел,
  а не на абзац «Always await»: своего якоря у абзаца нет. Тест страницы
  `a section the body returns lands the request before the return`
  в `time_rakes_test.dart`.
- M2. Геттер `JobContext.heldCancellation`
  по `2026-10-21-held-cancellation-design.md`: в `JobContextBase` это
  `_owner.heldCancel`. Dartdoc с примером чека, строки в таблице контекста
  README и `readme_recipe_test.dart`, «Added» и оба списка «Breaking changes»
  `CHANGELOG.md`. На `doc/cancellation.md` в «Holding the cancellation back»
  абзац о том, что `return ctx.uncancellable(...)` значения не выносит, блок
  с чеком и абзац о неотклоняемой отмене, которую геттер не показывает. Блок
  держит область `keepTheReceipt` страницы и тест с отменой и без неё.
  В `solo` — фраза на странице отмены и тест в `pending_test.dart`: тело видит
  ту же отмену, что `Solo.pending`, и `null` после правила. Тесты ядра: пять
  в `cancel_test.dart`, два в `extending_test.dart`. Мутант `=> null` роняет
  все, кроме теста с правилом движка: тот проходит на мутанте законно, через
  `isCancelled`, ради второй проверки он и написан. Решение 5 `docs/settled.md`
  дописано.
- M4. `errors.md`: «Reporting each error once» вторым разделом, «Where each
  error goes» перед «An observer», в конце новый раздел «Rare cases» с «Limits
  of the filter» и «Rare routes», куда ушёл и блок о том, что Dart отдаёт зоне
  мимо задачи. Якоря не переименованы; изменились только связки «above»
  и «below» в четырёх абзацах.
- L1. Строка отладки о придержанной отмене, которая пропадает: в `finish` —
  «ends with a held cancellation, which is dropped», в `_liftTimeout` — «drops
  the deadline a section held, along with its timer». Вторую нашло ревью
  сделанного (находка 3 ниже). Тест на каждую в `debug_test.dart`, мутант
  второй убит.
- L2. Отказ `runAll` документами, как предложил вердикт: в dartdoc `runAll`
  и у таблицы отказов. Таблица отказов живёт не на `groups.md`, а в разделе
  «When `ctx.run` refuses a child» `children.md`, и оговорка встала в абзац
  о `runAll` там: группа не запускает ни одну задачу списка, исправные тоже,
  `done` каждой ждёт, пока её не запустит или не отменит создавший её код,
  а тело, которое поймало отказ и ждёт задачу из списка, ждёт вечно.
- L3. Тест `arriving behind the deadline with a reason of the deadline`
  в `timeout_test.dart`; мутант `identical` на `is TimeoutCancelReason` его
  роняет. Мёртвый `started: target.isRunning` убран из `_forwardCancellation`:
  `cancelWith` ставит `started` по статусу сам.
- L4. Фраза в dartdoc `shared()`: ручка законченной задачи кончается
  на следующей микрозадаче, до неё `outcome` — `null`, как у `then`.
- L6. Вступление `children.md` дожидается продолжения
  `ctx.abandonable(() => tail.value)`, той же идиомой, что `chains.md`; фраза
  о трассах отнесена к разделам ниже. Тест вступления проверяет, что отчёт
  пишется до конца задачи; мутант без ожидания его роняет.
- L8. README: ошибки `ctx.unattended` идут в `onError`, затем к ответу;
  «Observe a failure» ведёт на «A failure nobody waits for» `outcomes.md`, где
  разобрана микрозадача.
- L9. Вариант с `rethrow` в «Asking the job» — блоком кода под первым,
  с областью `rethrowOnACancelledJob` и тестом, и строка о выборе: первый
  теряет сбой после отмены, второму нужен `Job.isCancellationError` в `main`.

## Ревью сделанного

Независимое ревью на Opus, только чтение, по копии с работой. High нет, семь
Low; все приняты и исправлены:

1. Dartdoc `runAll` и абзац на `groups.md` говорили, что ручки отказанной
   группы не стартуют никогда. Зонд ревьюера запустил исправную ручку после
   отказа, и она кончилась `Done(1)`. Верно другое: группа их не запускает,
   и они остаются у кода, который их создал.
2. Оговорка L2 стояла на `groups.md`, внутри раздела о провале ветки, а таблица
   отказов — в `children.md`. Абзац перенесён к таблице.
3. L1 был закрыт наполовину: `_liftTimeout` сбрасывал придержанный дедлайн
   секции, от которой тело ушло, раньше `finish`, и трасса молчала. Добавлена
   строка и тест.
4. «Only `ctx.job.isCancelled` says so» — неточно: неотклоняемую отмену видит
   и `ctx.check()`. Абзац говорит теперь, что её не показывает геттер.
5. M1 в dartdoc не называл `onDiscard`. Дописано в обоих местах.
6. Рваные переносы в dartdoc `heldCancel` и `timeout`, и «is the only place»
   вместо «are the only places». Перезалито.
7. Тест вступления `children.md` не держал ожидание продолжения. Держит.

## Проверки

- `async_job`: `dart format` без изменений, `dart analyze` чистый, `dart test`
  +1788.
- `solo`: +2047, пример `solo` +112; `flutter_solo` +241, его пример +6;
  `format` и `analyze` чистые во всех корнях.
- `check_line_width.py`, `reflow.py --check`, `check_doc_shape.py`,
  `check_page_code.py`, `check_translations.py`, `check_links.py`,
  `build_site_test.py` зелёные; сайт собирается.
- Линтер `humanizer--ru` по добавленным строкам переводов: 0 ошибок.
