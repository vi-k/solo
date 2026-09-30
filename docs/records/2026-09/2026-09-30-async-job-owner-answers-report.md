# Ответы владельца по L5, L16 и L43

> **Состояние на 2026-09-30:** сделано, закоммичено вместе с этой записью
> и отправлено в `origin`, CI зелёный; независимое ревью Codex проведено, обе
> его находки приняты и исправлены.
> **Что это:** отчёт о правках по трём вопросам владельцу из
> `2026-09-26-async-job-project-review.md`: какая отмена побеждает (L5),
> сужение защищённых членов без потребителя (L16) и первая попытка в разделе
> «Reacting before the outcome» (L43).
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-async-job-core-edges-report.md`,
> `2026-09-28-cancellation-outcomes-pages-report.md`.

## Решение

Владелец 2026-09-30 на три совета ответил «как советуешь». Побеждает
неотклоняемая отмена движка. Из семи защищённых членов, которых не зовёт даже
`solo`, сужаются два. Аннотации `@mustCallSuper` и `@visibleForOverriding`
остаются в «Breaking». Раздел «Reacting before the outcome» получает первую
попытку.

## L5. Какая отмена побеждает

Зонд на `47a1b00`, `.artifacts/2026-09-30-owner-questions/probe_l5_test.dart`:
тело в `ctx.uncancellable`, пользователь зовёт `cancel(reason: mine)`, секция
её придерживает, потом движок зовёт `cancelOwnJob`.

```text
in section: held=Cancelled(mine) pending=null
whenCancelled: rule
after rule: held=Cancelled(mine) pending=Cancelled(rule: rule)
outcome: Cancelled(rule: rule)
```

Правило побеждало и раньше; неверны были dartdoc `cancel` («another
cancellation does not replace it, even while it is held») и `heldCancel`,
который до конца секции называл отмену, уже не способную приземлиться. В `solo`
то же показывал `SoloPending.heldCancellation`.

**Правка.** `JobBase.cancelWith`, помечая задачу, сбрасывает `_heldCancel`:
внутри секции сюда доходит только отмена, от которой задача отказаться
не может. По находке ревью сброс стоит ещё в двух местах, где придержанная
отмена тоже уже не приземлится: там, где задача принимает отмену, брошенную
её же телом, и в `finish`. Конец тела его не сбрасывает: пока ребёнок работает,
секция ещё вправе выпустить отмену на живую задачу. Dartdoc `cancel`,
`heldCancel`, `ctx.uncancellable` и `SoloPending.heldCancellation` говорят, что
такая отмена не придерживается и придержанную до неё отбрасывает.
`packages/async_job/doc/extending.md` с переводом — то же в абзаце
о `cancelOwnJob`. CHANGELOG ядра — пункт в Fixed; `solo` — фраза в пункте
о `Solo.pending`, который ещё не выпущен.

**Сторожа.** В `packages/async_job/test/extending_test.dart` движок
`SectionJob` получил контекст с правилом `breakRule` и `end` для `finish`:

- `a cancellation the job cannot refuse drops the one a section holds` —
  `heldCancel`, прочитанный в `onCancel` и `whenCancelled`, уже `null`,
  а future первого `cancel()` не завершена при правиле и завершена в конце;
- `a job the engine finishes drops what a section holds`;
- `a body that gives itself up drops what a section it left open holds` —
  ребёнок ещё работает, задача не кончилась;
- `a body that returns before its child keeps what a section holds` — граница:
  здесь придержанная отмена остаётся и становится исходом.

`a rule drops the cancellation a section holds`
в `packages/solo/test/pending_test.dart`: правило типа `solo` отменяет задачу
в секции, `pending.heldCancellation` возвращается к `null`.

## L16. Сужение защищённых членов

Семь членов без потребителя: `solo` и `flutter_solo` не зовут ни одного, все
семь были в `0.2.0`. Сужены два:

- сеттер `JobBase.level` — уровень выставляет `startChild` при усыновлении,
  а движок, выставивший его сам, меняет ответ публичного `isChild`; геттер
  остался;
- `JobBase.cascadeToChildren` — каскад идёт внутри `cancelWith` после отметки,
  а вызванный в обход отменял детей неотмеченного родителя.

Оба стали приватными: `_level` пишет `startChild`, `_cascadeToChildren` зовёт
`cancelWith`. Остались `addCleanup`, `addCancelCallback`, `enterUncancellable`
с `leaveUncancellable` и `throwIfUnattended`: из них движок собирает
собственные члены контекста, ради этого написана `extending.md`,
и `throwIfUnattended` она называет прямо. CHANGELOG ядра — пункт в «Breaking
changes» с миграцией. Сторожа в наборе нет: его работу сделала бы проверка
компиляции внешнего наследника. Ревьюер собрал такой наследник: оба члена ему
недоступны, вариант миграции через `startChild` и `cancelOwnJob` собирается.

Вторая половина L16 — «Breaking» или «Added» для аннотаций: остаются
в «Breaking», CHANGELOG не менялся.

## L43. Первая попытка в «Reacting before the outcome»

Раздел `packages/async_job/doc/outcomes.md` начинался с ответа. Теперь он
открывается задачей `report` с шагом, который отмена прервать не может,
и уборкой после него. Первая попытка ждёт `report.done` и печатает отмену после
шага и уборки:

```text
step finished
cleanup
cancelling: manual
```

Абзац под ней объясняет, что исход появляется только после тела, детей
и уборки, и что `await report.cancel()` быстрее не будет. Прежний текст
с `whenCancelled` стал подразделом «Listening for the cancellation», и под его
кодом встала трасса:

```text
cancelling: manual
step finished
cleanup
```

Перевод — с оригиналом, новые абзацы прошли сканер humanizer-ru: 100 из 100,
тире нет. Сторож `packages/async_job/test/outcomes_rakes_test.dart`: тест
первой попытки добавлен, тест ответа переписан под новую задачу, `quoted`
получил обе трассы. По находке ревью добавлен тест
`awaiting cancel is no quicker than awaiting done`: он держит фразу абзаца
о `report.cancel()`. Подмена строки трассы и строки кода на странице краснит
сторож.

## Ревью

Codex, `gpt-6-astra` с усилием `xhigh`, 952 с, в клоне с правкой одним
коммитом. Отчёт, зонды и журналы мутаций —
`.artifacts/2026-09-30-owner-questions/reviewer/`. Все обязательные проверки он
прогнал, P1 не нашёл.

1. **P2: `_heldCancel` оставался после самоотмены и после `finish`.** Зонд
   ревьюера: движок кончает задачу `finish` при открытой секции, и `heldCancel`
   называет отмену у законченной задачи; тело, оставившее секцию без `await`,
   бросает свой `Cancelled` при живом ребёнке, и `SoloPending` говорит сразу
   «cancelled by» и «holding back». Остаток был и до правки. Вердикт: принято,
   сброс добавлен в обе точки, как ревьюер и предложил; его 13 зондов ядра
   и зонд `solo` зелёные.
2. **P2: сторожа не держали момент сброса и future `cancel()`.** Его мутации:
   сброс после `_markCancelled` (M2), `cancel()`, возвращающий готовую future
   (M3), и future, не завершающаяся для придержанной отмены (M10), проходили
   зелёными. Вердикт: принято, сторожа усилены, см. выше и таблицу ниже.
3. **Мелочи.** Шапка отчёта и handoff говорили «не закоммичено»; фраза «тест её
   не увидит» о L16 слишком категорична. Вердикт: принято, обе поправлены.

Его мутации M4 (поздняя придержанная заменяет первую) и M11 (внутренняя секция
выпускает отмену) прошли три файла сторожей, но полный набор ядра ловит обе:
четыре и один красный. M6 (отметка после каскада) — старое поведение вне этой
правки.

## Мутации

Скрипты `.artifacts/2026-09-30-owner-questions/mut3.py` и `mut4.py`, файл
возвращается копией. Сторожа: `extending_test.dart`
и `outcomes_rakes_test.dart` ядра, `pending_test.dart` `solo`.

| Подмена | Красных |
| --- | --- |
| M1: без сброса в `cancelWith` | 2 |
| M2: сброс после `_markCancelled` | 1 |
| M3: `cancel()` возвращает готовую future | 2 |
| M10: для придержанной отмены future не завершается | 1 |
| N1: без сброса при самоотмене | 1 |
| N2: без сброса в `finish` | 1 |
| N3: сброс в конце любого тела | 1 |

## Проверки

`packages/async_job`: формат, анализ, `dart doc --dry-run` — 0 предупреждений,
`dart test` 921. `packages/solo`: формат, анализ, `dart test` 809, пример 47.
`packages/flutter_solo`: анализ, 85, пример 4. Из корня: `reflow.py --check`,
`check_line_width.py`, `check_translations.py`, `check_doc_shape.py`,
`check_links.py` зелёные; ширину этой записи и изменённых абзацев записи ревью
сверил отдельно.
