# Ревью сделанного: разделение хука ошибки в ядре

> **Состояние на 2026-09-25:** круг пройден, все девять находок приняты
> и внесены следующим коммитом после `d7b33a2`.
> **Что это:** независимое ревью коммита `d7b33a2` на Opus, по копии дерева,
> с прогонами, зондами и мутациями в скретч-каталоге; вердикты в конце каждой
> находки.
> **Связанные записи:** `2026-09-25-core-error-hook-split-report.md`,
> `2026-09-25-core-error-hook-split-plan.md`,
> `2026-09-25-core-error-hook-split-plan-review.md`.

## Копия

```text
$ /usr/bin/git checkout --detach d7b33a2
HEAD is now at d7b33a2 feat(async_job)!: split the observer's error hook into a notice and an answer
$ /usr/bin/git log --oneline -4
d7b33a2 feat(async_job)!: split the observer's error hook into a notice and an answer
8a7f90a docs: review the plan of the core error hook split
e2e8375 docs: plan the split of the error hook in async_job
2a8feca docs: note the open question of a split error hook in async_job
$ /usr/bin/grep -n "abstract mixin class JobObserver" packages/async_job/lib/src/observer.dart
18:abstract mixin class JobObserver {
```

## Что проверено прогоном

Где: скретч-каталог сессии, `scratchpad/rv/packages/`. Там копии `async_job`,
`solo` и `flutter_solo` вместе с их `pubspec_overrides.yaml`. Dart SDK 3.13.0,
зависимости через `pub get --offline`.

- **`async_job`:** `dart analyze` — «No issues found!».
  `dart format --output=none --set-exit-if-changed .` — 0 changed.
  `dart test` — «+582: All tests passed!». `dart doc --dry-run` — «Found 0
  warnings and 0 errors».
- **`solo`:** анализ чист, 791 тест зелёный; пример — анализ чист, 47.
- **`flutter_solo`:** анализ чист, 85; пример — 4.
- **Документные проверки** из корня копии зелёные: `reflow.py --check`,
  `check_line_width.py`, `check_translations.py`, `check_links.py`,
  `check_doc_shape.py`. Три тронутые записи в `docs/records/`
  и `docs/handoff.md` залиты и не шире 79 символов.

Зонды. Файл `rv/zz_probe_test.dart.keep`; наблюдатель `Rec` пишет `onError`
и `onUnanswered`, а без `answers` зовёт `super`.

- **P1.** Корень упал на 5 мс, отмена на 10 мс, задача ждёт неотменяемого
  ребёнка. С наблюдателем: `onError root`, затем `zone`, исход
  `Cancelled(manual)`. Без наблюдателя: только `zone`. Строка 2 таблицы
  подтверждена.
- **P2.** Тот же провал у ребёнка через `await ctx.run`. С наблюдателем звучит
  только `onError child`, без наблюдателя — ничего. Это открытый вопрос 5, так
  было и до правки.
- **P3.** `FailingHookJob` (бросающий `finished()`) со смотрящим наблюдателем:
  `onError j`, `onUnanswered j`, `zone`, исход `Done(1)`.
- **P4.** `extends Other implements JobObserver`, ответ делегирован экземпляру
  `extends JobObserver`. Ошибка уборки пришла в зону создания, зона запуска
  пуста.
- **P5.** Ребёнок создан в зоне A, запущен родителем из зоны B с наблюдателем
  родителя. `onUnanswered child` вызван, ошибка ушла в A, B пуста.
- **P6.** `runAll` из трёх веток, две неотменяемые падают после того, как
  группа бросила первую. `onError` — по разу у a, b, c. `onUnanswered` и зона —
  по разу у b и c.
- **P7.** Задача создана внутри `unattended`, её собственная `unattended`
  падает: `onError`, `onUnanswered`, зона — по одному разу.
- **P8/P9.** Продолжение `then`, провал источника переслан. Наблюдатель
  продолжения слышит его один раз через `onError`. Зона получает его один раз,
  через ненаблюдённый исход.
- **P10/P11.** `ctx.join` с бросающим `discard`, отмена во время действия.
  Со смотрящим наблюдателем: `onError`, `onUnanswered`, зона. С отвечающим —
  зоны нет.

**Итог по механике.** Я не нашёл пути, где ошибка без исхода получает
`onUnanswered` дважды или ни разу, уходит в зону дважды или где ошибка тела
попадает в `onUnanswered`. Исключение одно, и оно задумано: ветка `runAll`,
которую группа не бросила. Порядок хуков `solo` прежний.

**Код против вердиктов ревью плана.** Внесены находки 1–10, 12 и 13.

- По находке 1: `parallel_wait_test.dart:501` остался на смотрящем
  `ErrorObserver`.
- По находке 4f: шапку плана `2026-09-22` поправил `8a7f90a`, а не этот коммит.
- Находка 11 внесена не целиком: пункты a–c есть, пункта d нет — это находка 3
  ниже.

Мутации. Откат из копии файла, после каждой хэш сверен, `diff -r` скретч-копии
`lib/` с деревом пуст. Это мутации сверх двенадцати из отчёта:

| Мутация | Где | Красных |
| --- | --- | --- |
| `notifyError`: ответ раньше оповещения | `job_base.dart:1015-1016` | 10 |
| без наблюдателя — текущая зона вместо `_toZone` | `job_base.dart:1048` | 5 |
| без наблюдателя — никуда | там же | 14 |
| `onUnanswered` без охраны `_notify` | `job_base.dart:1051` | 2 |
| ветка `runAll`, законченная движком, не оповещена | `job_context.dart:1741` | 1 |
| ошибка `finished()` — только оповещение | `job_base.dart:951` | **0** |
| ошибка `finished()` проглочена | там же | 1 |
| переполнение каскада — только оповещение | `job_base.dart:1209` | **0** |
| описание отмены ребёнка — только оповещение | `job_base.dart:1378` | 1 |
| `_dispose` — только оповещение | `job_context.dart:823` | **0** |
| `_dispose` проглочен | там же | **0** |
| провал после ухода тела через `.timeout` — только оповещение | `job_context.dart:1049` | 1 |
| поздний провал брошенного `wait` — только оповещение | `job_context.dart:1062` | 8 |
| `unattended` — только оповещение | `job_context.dart:1294` | 13 |
| пересылка отмены у `then` — только оповещение | `job_then.dart:46` | **0** |
| пересылка отмены у `then` проглочена | там же | **0** |
| тело по умолчанию фильтрует только `Cancelled` | `observer.dart:79-80` | 3 |
| `_SoloJobObserver.onUnanswered` зовёт ещё и `SoloObserver.onError` | `solo.dart:1229` | 7 (`solo`) |
| `_SoloJobObserver.onUnanswered` идёт в зону мимо `Solo.onUnanswered` | там же | 23 (`solo`) |

Прогон с выключенным ответом. `ErrorObserver.answering`
и `JobJournal(answers: true)` сделаны смотрящими, скрипт `rv/answering_off.py`.
Красных 25 из 27 мест, где стоит отвечающий вариант.

## Находки

1. **Medium. Отвечающий вариант спрятал маршрут двух источников ошибок без
   исхода: хука `finished()` движка и переполнения каскада.**

   Суть. Для этих двух источников теперь нигде не проверено, что ошибка
   получает ответ. Единственные тесты, где они встречаются, —
   `lifecycle_test.dart:229` («a finished hook that throws still lets the job
   finish», `JobJournal(answers: true)`) и семь тестов
   `cascade_depth_test.dart` (`ErrorObserver.answering`). До правки оба теста
   стояли на обычном наблюдателе и заодно утверждали старый маршрут: ошибка
   в тестовую зону не приходит. После правки их перевели на отвечающий вариант,
   а тест маршрута для этих источников нигде не появился. Без наблюдателя их
   маршрут тоже не проверен: это пробел и до правки.

   Свидетельство.

   - Мутация «ошибка `finished()` — только оповещение» (`job_base.dart:951`): 0
     красных.
   - Мутация «переполнение — только оповещение» (`job_base.dart:1209`): 0
     красных.
   - Зонд P3: со смотрящим наблюдателем ошибка `finished()` доходит
     до `onUnanswered` и зоны, то есть маршрут сейчас верен, его просто никто
     не держит.
   - Копия `cascade_depth_test.dart` со смотрящими наблюдателями: шесть тестов
     красные с «Stack Overflow» в тестовой зоне. Значит, и переполнение идёт
     по маршруту.

   Предложение. Добавить в `unanswered_test.dart` два сторожа:

   - `FailingHookJob` со смотрящим наблюдателем → зона получает `hook failed`
     один раз;
   - один каскадный тест (например, «a body giving itself up reports a cascade
     out of stack») со смотрящим `ErrorObserver` под `runZonedGuarded` → зона
     получает ровно один `StackOverflowError`, `expect` — вне зоны.

   Вердикт: принято. Проверил сам: обе мутации на `d7b33a2` не краснили ничего.
   Сторож `finished()` — в `unanswered_test.dart` («an error of the finished
   hook of an engine is answered for»: `onError`, `onUnanswered`, зона по разу,
   исход `Done`). Сторож переполнения — в `cascade_depth_test.dart`, где лежит
   цепочка («a cascade out of stack goes on to the zone like any error»:
   смотрящий `ErrorObserver`, зона получает ровно один `StackOverflowError`).
   Мутации теперь краснят по одному тесту.

2. **Medium. Путь `_dispose` не покрыт ни одним тестом, и пересылка отмены
   у `then` тоже.**

   Суть. Через `_dispose` идёт disposer, переданный в `join` или `wait`, когда
   падает проверка после действия (`job_context.dart:742-748`, `:970-977`).
   Тем же путём идёт поздний результат, пришедший после конца задачи
   (`_keepLate`, `:799-808`; `_keepOnStack`, `:785`). Dartdoc `join`,
   правленный этим коммитом (`job_context.dart:135-136`), обещает: «An error
   from the disposer goes to `onError` and `onUnanswered`». Этого не проверяет
   ни один тест: даже полное проглатывание ошибки ничего не краснит. Сторожа
   `unanswered_test.dart` берут уборку только через `onDispose`, это другой
   путь — `_runCleanup`.

   Свидетельство.

   - Мутации «`_dispose` — только оповещение» и «`_dispose` проглочен»
     (`job_context.dart:823`): 0 красных обе.
   - Мутации «пересылка отмены у `then` — только оповещение» и «проглочена»
     (`job_then.dart:46`): 0 красных обе.
   - Зонд P10 показывает, что маршрут `_dispose` сейчас верен: `onError j`,
     `onUnanswered j`, `zone`, исход `Cancelled(manual)`.

   Предложение. Добавить в `failingOutside` (`unanswered_test.dart:90`)
   `ctx.join` с бросающим `discard`, который отменяют посреди действия, как
   в P10. Тогда путь покроют все пять сторожей файла, которые берут этот
   список, и таблица на странице («cleanup») будет подтверждена и для этого
   пути. Для `then` — либо сторож на движке, чей `cancelWith` бросает, либо
   честная строка в отчёте, что этот источник не охраняется.

   Вердикт: принято, оба пути сторожем. `failingOutside` кончается `ctx.join`
   с бросающим `discard`, отменённым посреди действия, и список ошибок вне тела
   стал шестью: `Bad state: discard` в нём первой. Пересылку отмены держит
   новый тест «a source that fails to stop is answered for on the continuation»
   на `UncancellableByBugJob` из `test/support/probe_job.dart`, чей
   `cancelWith` бросает. Мутации: `_dispose` только оповещает — 4 красных,
   проглочен — 4; пересылка у `then` только оповещает — 1, проглочена — 1.

3. **Low. Пункт d находки 11 ревью плана не внесён, и отчёт об этом молчит.**

   Суть. План в разделе «Документация» требует: «Страница `observing.md` прямо
   говорит, что `JobObserver` — место того, кто запускает задачу, и что
   продолжение `then` наблюдателя источника не наследует». Про `then` сказано
   (`observing.md:54-56`). Про то, чей это наблюдатель, — нет.

   Свидетельство. Поиск «whoever|runs it» по `observing.md` и переводу ничего
   не находит. Это сказано только в dartdoc (`observer.dart:5`). Раздел
   «Документы» отчёта называет `then` и ничего больше.

   Предложение. Одна фраза в разделе «Observer» с переводом. Либо запись
   в отчёте, что пункт снят. Довод для снятия: после разделения смотрящий
   `JobObserver` тоже ничего не меняет в маршруте, и противоречие с «An
   observer only watches» у `solo`, которого боялась находка, исчезло.

   Вердикт: принято, фразой. Раздел «Observer» говорит: «Whoever runs the job
   passes the observer when creating it», перевод — «Наблюдателя передаёт при
   создании задачи тот, кто её запускает».

4. **Low. Неточности dartdoc.**

   - a) `job_base.dart:1010-1012`, `notifyError`: «A [Cancelled] is the one
     thing that never reaches the zone from here … without an observer
     answering for it, it is heard by nobody». Это неверно дважды:
     - смотрящий наблюдатель слышит отмену через `onError`:
       `observing_rakes_test` с `Reporter` даёт
       `['onError: Cancelled(manual)', 'outcome: Done(null)']`;
     - в зону не идёт и конверт из одних отмен (`_isCancellation`,
       `job_base.dart:1057-1063`).
   - b) `observer.dart:55-62` перечисляет провал ветки `runAll`, а следом
     говорит «A failure of the body does not come here». Но это тоже провал
     тела: строка таблицы так и называется — «The body's, in a branch of
     `ctx.runAll`…».
   - c) `job_context.dart:136-138`: переносы в тронутом абзаце не жадные —
     «…and the» / «[Cancelled] is thrown all the same. Throws» / «[Cancelled]
     up front…». Такой же огрызок в `:510` правка починила.

   Предложение.

   - a) «A cancellation — a [Cancelled], or an envelope of nothing but
     cancellations — never reaches the zone from here…; without an observer
     nobody hears it.»
   - b) «Any other failure of a body does not come here…»
   - c) Перезалить абзац.

   Вердикт: принято, все три, формулировками ревьюера: a) отмена — `Cancelled`
   или конверт из одних отмен, наблюдатель слышит её через `onError`, без него
   никто; b) «Any other failure of a body»; c) абзац перезалит.

5. **Low. Соседние страницы говорят «и дальше в зону» без оговорки
   «по умолчанию».**

   Суть. После переопределения `onUnanswered` без `super` ошибка в зону
   не идёт — это проверяет тест «an override without super answers, and nothing
   reaches the zone». Страница `observing.md` в таблице пишет «the zone by
   default», а соседние страницы — без оговорки.

   Свидетельство.

   - Оригиналы: `doc/cancellation.md:102`, `:177-178`; `doc/cleanup.md:227`;
     `doc/outcomes.md:278-279`.
   - Переводы: `docs/ru/async_job/cancellation.md:102`, `:178`;
     `cleanup.md:226`; `outcomes.md:277`.
   - `CHANGELOG.md` `async_job`: запись о каскаде в `Unreleased` по-прежнему
     кончает маршрут на `onError` (`:240` и `:248` — «its error goes to
     `onError` and changes nothing else, as it always has»), хотя такую же
     запись на `:52-53` этот коммит поправил.

   Предложение. «to `onError` and, by default, on to the zone» /
   «и по умолчанию дальше в зону», либо «to `onError` and `onUnanswered`».
   В `CHANGELOG` `:240` и `:248` — «to `onError` and `onUnanswered`».

   Вердикт: принято. Четыре места оригиналов и четыре перевода получили «by
   default» / «по умолчанию», обе строки `CHANGELOG` — «`onError` and
   `onUnanswered`».

6. **Low. `docs/architecture.md:183-185` называет не всех, кто идёт через
   фильтр отмен.**

   Абзац говорит: «и маршрут ядра без наблюдателя, и `reportToZone` … идут
   через один фильтр». Через `_toZone` теперь идёт и тело `onUnanswered`
   по умолчанию (`observer.dart:79-80`).

   Предложение. «и маршрут ядра — без наблюдателя и через тело `onUnanswered`
   по умолчанию, — и `reportToZone`…».

   Вердикт: принято, формулировкой ревьюера.

7. **Low. В отчёте неверные числа, и одна правка приписана не тому коммиту.**

   - «шесть в `cascade_depth_test`»: на деле семь (`:75`, `:164`, `:209`,
     `:242`, `:273`, `:297`, `:311`).
   - «четыре в `run_all_test`»: на деле пять (`:444`, `:772`
     `JobJournal(answers: true)`, `:1323`, `:1485`, `:1549`).
   - В `cascade_depth_test.dart:307` («a callback that runs out of stack is not
     a callback that failed») отвечающий вариант не нужен: тест зелёный
     со смотрящим наблюдателем в обоих моих прогонах. Комментарий файла при
     этом говорит, что каждый наблюдатель отвечает, и называет причину, которая
     к этому тесту не относится.
   - «Шапка `2026-09-22-error-hook-split-plan.md` говорит, что его вопрос 4
     пересмотрен» стоит в списке документов этой работы. Но шапку правил
     `8a7f90a`, а `git show --stat d7b33a2` этого файла не содержит.

   Предложение. Поправить числа; в `:311` взять смотрящий `ErrorObserver`;
   строку о шапке пометить как сделанную раньше.

   Вердикт: принято. Тест `:307` взял смотрящий `ErrorObserver`, комментарий
   файла больше не говорит «every observer». Отвечающих в `cascade_depth_test`
   теперь шесть — отчёт называет это число уже по нынешнему дереву и говорит
   о возврате; в `run_all_test` — пять; строка о шапке помечена как `8a7f90a`.

8. **Low. Новые тестовые классы объявляют поля ниже конструктора или методов.**

   Суть. `docs/conventions.md` требует: «Поля класса объявляются выше
   конструктора … и в коде». В новых классах поля ниже:

   - `Counting` (`unanswered_test.dart:24-27`);
   - `ThrowingAnswer` (`:48-57`, поле после методов);
   - `Answering` (`observing_rakes_test.dart:79-81`);
   - `AnsweringJob` (`extending_test.dart`: фабрика и приватный конструктор
     на `:25`–`:40`, поля `_body` и `_answer` — на `:48-49`).

   Соседи в тех же файлах (`Hooks`, прежний `AnsweringJob`) устроены так же —
   это давняя местная привычка.

   Предложение. Поднять поля в новых классах. Либо, если тестам это разрешено,
   сказать об этом в соглашениях.

   Вердикт: принято, поля подняты во всех четырёх. Соседей не трогал: правка
   не про них.

9. **Low, вне этой работы, было и до неё. Dartdoc `Solo.onUnanswered`
   расходится с кодом.**

   Суть. `solo.dart:853-860` говорит «neither does a rule that threw»,
   и в перечне нет ветки `runAll`. На деле `keepWhile`, бросивший при
   переоценке (`solo.dart:1029`) и в `_checkCorrectionState` (`job.dart:208`),
   идёт через `notifyError` в `Solo.onUnanswered`. Туда же приходит провал
   ветки `runAll`, который группа не бросила.

   Свидетельство. Мутация «`_SoloJobObserver.onUnanswered` мимо
   `Solo.onUnanswered`» краснит «a keep rule that throws does not stop the
   reevaluation», «a throwing external rule is reported once and blocks
   correction» и «a failure the group did not throw reaches the handler of the
   engine». Страница `doc/errors.md:494-498` сходится с кодом, а не с dartdoc.
   Переопределения, снятые этим коммитом, вели эти ошибки туда же.

   Предложение. Отдельной правкой: «neither does a start rule that threw».
   В перечень добавить ветку `runAll` и правило при переоценке.

   Вердикт: принято, в этом же круге: перечень называет `keepWhile`, бросивший
   не на проверке тела, и ветку `runAll`, а исключение — «a `canStart` that
   threw». Там же фраза «the same thing the core does when a job has no
   observer at all» стала «the same thing the core does by default, with an
   observer or without one»: после разделения прежняя была неполной.

## Вывод

Как есть работа годится. Механика верна: зонды и мутации не нашли ни двойного
ответа, ни потерянного, ни ошибки тела в `onUnanswered`. Решения владельца
соблюдены, `solo` ведёт себя по-прежнему, все наборы тестов и документные
проверки зелёные.

Обязательно поправить:

- находку 1 — сторожа маршрута для `finished()` и переполнения каскада, которые
  спрятал отвечающий вариант;
- находку 2 — сторож пути `_dispose`, чей маршрут обещает правленный dartdoc
  `join`.

Желательно в этом же круге: находки 3–6 (пункт d находки 11, неверная фраза
dartdoc `notifyError`, «по умолчанию» на соседних страницах и в `CHANGELOG`,
`docs/architecture.md`). Находки 7–9 — по усмотрению.
