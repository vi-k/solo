# Документы ядра по второму полному ревью: M5, M6, L2–L4, L7, L9, L12, L15–L19

> **Состояние на 2026-10-17:** сделано в `main` одним коммитом, не отправлено.
> **Что это:** вторая из пяти волн правок по второму полному ревью — документы
> ядра и dartdoc, тринадцать находок записи
> `2026-10-17-async-job-project-review.md`, с переводами и сторожами.
> **Связанные записи:** `2026-10-17-async-job-project-review.md`,
> `2026-10-17-async-job-code-fixes-report.md`,
> `2026-10-15-failure-after-cancellation-design.md`.

Владелец 2026-10-17 на первый вопрос записей ревью ответил «да, чини всё
с твоими рекомендациями». Правки идут пятью волнами: код ядра, документы ядра,
код `solo` и `flutter_solo`, пример камеры, документы `solo`. Эта запись —
о второй. Код ядра в ней не менялся: правки в `lib/` — только dartdoc.

## Что сделано

**M5.** Цена рецепта названа на обеих страницах. На `cancellation.md`, «Asking
the job», после рецепта — абзац о провалах, которые приходят после отмены:
`ctx.check()` бросает принятую отмену, что бы ни поймал `catch`, и настоящий
провал миграции не слышат ни лог, ни `onError`, ни зона. Там же вариант,
который провал сохраняет: `if (ctx.job.isCancelled) rethrow;` вместо
`ctx.check()`. Провал тогда доходит до `onError` и зоны, а остановка миграции —
только до `onError`, потому что фильтр в `main` страницы её называет.
На `observing.md`, «Errors of a cancellation», фильтр идёт первым и называет
обёртку отмены по причине; рецепт с `ctx.check()` идёт после как замена
фильтру, с той же ценой. Цена названа для тела, которое ждёт через `ctx.join`:
открытие, которое нашло базу заблокированной после отмены, теряется. Тело
страницы ждёт через `ctx.abandonable`, и там брошенное ожидание слышно
по-прежнему. Запись CHANGELOG о замене рецепта `0.2.0` тоже называет цену
и `rethrow`.

**M6.** В пункте о `migrate` под Quick start одна фраза: клиент, который
останавливается броском, заставляет `join` бросить его ошибку, и она доходит
до зоны всякий раз, когда отмена останавливает миграцию, если приложение
не назвало её один раз в `Job.isCancellationError`; ссылка на «Errors of a
cancellation». Кода в примере не прибавилось.

**L2.** Фраза «Nor does it see an error that the body makes of its own
cancellation» заменена: такая ошибка до фильтра доходит, но проверка типа выше
её не узнаёт, и фильтр называет обёртку по причине.

**L3.** В списке того, что наблюдает исход, у `then` оговорка: продолжение,
которое отменили раньше, чем упал его источник, ничего не передаёт, и провал
остаётся ненаблюдаемым; ссылка на «A failure nobody waits for».

**L4.** «Why» в README сравнивает с флагом честно: у флага теперь
`try/finally`, и база закрывается, чем бы ни кончилась работа. Проза говорит,
что остаётся неудобным и тогда: каждый новый `await` требует своей проверки,
пропущенная проверка ни на что не указывает, а `load` возвращается одинаково,
отменили его или он дошёл до конца, и вызывающий их не различит. Абзац
о `CancelableOperation` возвращает к проверке после каждого `await`
и `finally`, «as with the flag».

**L7.** На `streams.md` после абзаца о том, что `ctx.each` не ждёт future
`cancel()` подписки и куда идёт её провал, добавлена разница: `await for`,
из которого вышли раньше конца, эту future ждёт, код после цикла выполняется,
когда источник уже закрылся, а её провал бросает сам цикл.

**L9.** Договором, а не кодом. Dartdoc `run`: `ArgumentError` или `StateError`
ребёнка не трогают, он остаётся у кода, который его создал, и отвергнутая так
`Job.deferred` остаётся незапущенной, а её `done` ждёт, пока тот код её
не запустит или не отменит. Под отменённым родителем ребёнок отменяется
до старта — прежнее «with the child dropped» сказано теперь так же, как
в таблице `children.md`. Dartdoc `runAll` ссылается на то же правило.
На `children.md` после таблицы «When `ctx.run` refuses a child» — абзац
о том же для `run` и `runAll`.

**L12.** Договором в dartdoc `onCancel`: колбэк, который регистрирует ещё один,
бежит в задаче, уже отменённой, поэтому регистрация тоже бросает `Cancelled`,
и колбэк на ней останавливается. Слышит эту `Cancelled` только `onError`, как
любую брошенную вне тела, и задача всё равно кончается своей отменой. Что
должно случиться на отмене, колбэк делает сам.

**L15.** В «Added» `CHANGELOG.md` строка: `JobObserver` теперь
`abstract mixin class`, а в `0.2.0` был `abstract class`, и наблюдатель,
который уже наследует другой класс, подмешивает `JobObserver`:
`with JobObserver`.

**L16.** Вступление `children.md` больше не обещает неверный вариант перед
тремя верными: «The words for the three are close, and the wrong one compiles
as well as the right one. Each in its place:».

**L17.** Текст `ArgumentError` в «Steps in a row» стоит одной строкой, как его
печатает Dart. Сторож прежде склеивал строки блока пробелом и прощал ровно этот
разрыв; теперь сверяет блок дословно.

**L18.** «Deferred start» объявляет зону, прежде чем ею пользоваться:
`final zone = Zone.current;` рядом с `Job.deferred`, затем
`zone.run(job.start)`.

**L19.** В «Why» перед фрагментом с задачей фраза о разнице: фрагмент
регистрирует закрытие базы через `dispose`, который закрывает её при любом
исходе, а Quick start — через `discard`, который на `Done` оставляет базу
открытой вызывающему. Там же задача теперь «ends `Cancelled` when it stops for
one» — то, чего флаг из L4 вызывающему не говорит.

Каждая правка английского текста сопровождается правкой перевода:
`README.ru.md` и `docs/ru/async_job/` — `cancellation.md`, `observing.md`,
`streams.md`, `children.md`, `extending.md`, `CHANGELOG.md`. Изменённые абзацы
перевода прошли линтер `humanizer--ru`: ошибок 0.

## Сторожа

Каждое новое утверждение о поведении держит тест; где утверждение уже держал
тест, назван он.

- M5: `cancellation_rakes_test.dart` — «check in the catch loses a failure that
  comes after the cancellation» и два прогона «a rethrow on a cancelled job
  sends that failure on to the zone, and the stop no further than onError»,
  с поздним провалом и с остановкой; `observing_rakes_test.dart` — «a catch
  that asks the job first loses a failure after the cancel», с контрольным
  прогоном того же тела без `ctx.check()`: там провал слышат `onError` и зона.
- M6: `readme_recipe_test.dart` — «a client that stops by throwing sends the
  stop to the zone on every cancellation, unless the app names it» и «the Quick
  start names that filter and the page that takes it apart», второй читает
  пункт `migrate` обоих README.
- L3: прежний `then_test.dart`, «a cancelled continuation does not hide a
  refused source failure».
- L4: зеркало блока флага в `readme_recipe_test.dart` и два новых теста: база
  закрывается при упавшем чтении, а провал доходит до зоны; `load` возвращается
  одинаково без отмены, с отменой на 10 и на 50 мс.
- L7: `streams_rakes_test.dart` — «an await for left early waits for the source
  to shut down».
- L9: `run_all_test.dart` — «an ArgumentError or a StateError leaves the jobs
  untouched»: `runAll([repeated, repeated])` и `run` после конца тела, `done`
  обеих задач не завершается, пока код их не запустит или не отменит. Что
  `Cancelled` родителя ребёнка отменяет, держат прежние тесты таблицы.
- L12: `waiting_test.dart` — «onCancel from a callback of onCancel throws and
  registers nothing», с наблюдателем и без.
- L17: `children_rakes_test.dart`, «ctx.run refuses the continuation with the
  error the page quotes», теперь без склейки строк.
- L18: поведение держал прежний `extending_rakes_test.dart`, «a queue starts a
  deferred job in the zone the job was made in»; прозу «Deferred start»
  не сверяет никто.

## Проверки

В `packages/async_job`: `dart format --output=none --set-exit-if-changed .` — 0
changed; `dart analyze --fatal-infos` — No issues found! (с первого прогона два
замечания в новых тестах: незакрытый `StreamController` и запятая; исправлены);
`dart test` — `+1564: All tests passed!`; пример
`dart run example/example.dart` доходит до `Cancelled(manual)`. Из корня:
`check_line_width.py`, `reflow.py --check`, `check_doc_shape.py`,
`check_translations.py`, `check_links.py`, `build_site_test.py` (26 тестов)
и `build_site.py` (56 страниц) — зелёные.

Что сторожа текста кусаются, проверено мутациями в отдельной копии дерева —
отвязанный worktree на снимке правок, скрипт `mutate_w2.py` в скретч-каталоге
сессии, откат копией файла:

```text
== flag-check: 2 red
    and each of them runs whole, with nothing more
    every block of the README runs in this file
== flag-finally: 2 red
    and each of them runs whole, with nothing more
    every block of the README runs in this file
== m6-filter: 1 red
    the Quick start the Quick start names that filter and the page that takes it apart
== m6-filter-ru: 1 red
    the Quick start the Quick start names that filter and the page that takes it apart
== l17-text: 1 red
    The code of the page ctx.run refuses the continuation with the error the page quotes
== l18-zone: 0 red
== l12-core: 2 red
    every member throws up front once the job is marked
    onCancel from a callback of onCancel throws and registers nothing
== l17-split: 1 red
    The code of the page ctx.run refuses the continuation with the error the page quotes
== m5-observing-unlocked: 1 red
    Where errors go a catch that asks the job first loses a failure after the cancel
```

`flag-check` убирает из блока README одну проверку флага, `flag-finally` меняет
`finally` на `catch`, `m6-filter` и `m6-filter-ru` убирают имя фильтра
из пункта `migrate`, `l17-text` меняет слово в тексте ошибки, `l18-zone`
возвращает в прозу `job.start()` без зоны, `l12-core` убирает
`throwIfCancelled()` из `onCancel` в коде ядра. Две последние — после ревью
(`mutate_w2b.py`): `l17-split` возвращает текст ошибки на две строки,
`m5-observing-unlocked` открывает базу без провала.

## Ревью

Ревью на Opus по копии дерева — отвязанный worktree на снимке правок. Итог
ревьюера: двенадцать находок из тринадцати закрыты, L9 частично; одно замечание
Medium, одиннадцать Low и одно о процессе. Поведение, на котором стоят новые
утверждения, — шесть пунктов задания — он подтвердил своими зондами. Каждое
замечание, на которое опирается правка, я проверил кодом или своим зондом.

1. Medium: правило в dartdoc `run` шире кода. «An error leaves [child] as it
   was» верно для `ArgumentError` и `StateError`, но `Cancelled` родителя
   ребёнка отменяет (`_refuseChild` → `_cancelChild`), а брошенное правило
   домена кончает его `Failed` (`_startAdopted`). Мой зонд: `run` бросил
   `Cancelled(manual)`, а у ребёнка `child=Cancelled(parent) settled=true`.
   Правило сужено до двух ошибок в dartdoc `run` и `runAll`, на `children.md`
   и в переводе; «with the child dropped» сказано как в таблице, «cancelled
   before its start»; тест переименован.
2. «never starts» и «until that code starts it» спорили друг с другом. Теперь
   «stays unstarted», в переводе «остаётся незапущенной».
3. Сторож M5 на странице наблюдения проверял только отсутствие строк и был
   зелёным и без провала. Добавлен контрольный прогон без `ctx.check()`;
   мутация `m5-observing-unlocked` его краснит.
4. Сторож L17 склеивал строки блока и прощал тот самый разрыв. Склейка убрана;
   мутация `l17-split` его краснит.
5. Фраза об `await for` встала между `each` и провалом его future, и «If that
   future fails» читалось и про цикл. Переставлена после фразы о провале,
   и сказано, что у цикла провал бросает сам цикл. Мой зонд:
   `thrown=Bad state: close failed zone=[]`.
6. На `observing.md` цена показана на теле с `ctx.join`, а тело страницы ждёт
   через `ctx.abandonable`, где брошенное ожидание слышно по-прежнему. Цена
   теперь названа для тела, которое ждёт через `ctx.join`.
7. В переводе `cancellation.md` «и настоящий провал тоже» цеплялось
   к «бросает». Теперь «даже настоящий провал».
8. В строке CHANGELOG о `JobObserver` местоимение читалось как «другой класс».
   Теперь класс назван.
9. Запись CHANGELOG о замене рецепта `0.2.0` подавала `ctx.check()` без цены.
   Добавлены цена и `rethrow`, с переводом.
10. В dartdoc `onCancel` «That holds» отсылало к соседней фразе, которая
    говорит обратное. Абзац переписан без отсылки.
11. «reaches the zone on every cancellation» в пункте `migrate` шире правды:
    ошибку даёт только отмена, которая останавливает миграцию. Сужено,
    с переводом. Ту же формулу в «Why» оставил: там она сказана об операции,
    которую отмена останавливает.
12. В переводе `children.md` «оставляет как был» звучало разговорно. Теперь
    «не трогают», «не трогает ни одной задачи».
13. Процесс: итогов в вердиктах и `docs/handoff.md` в снимке не было. Они идут
    этим же коммитом.

Ещё ревьюер уточнил L3: у отменяемого источника отмена продолжения отменяет
и источник, и провал доходит до зоны как провал тела отменённой задачи,
а не как ненаблюдённый `Failed`. Для читателя итог тот же, фраза верна.

После правок: `dart format` — 0 changed, `dart analyze --fatal-infos` — No
issues found!, `dart test` — `+1564: All tests passed!`, пять проверок
документов из корня и сборка сайта зелёные, линтер `humanizer--ru`
по изменённым абзацам перевода — ошибок 0. Второго круга ревью не было: правки
после первого узкие, каждая проверена зондом или мутацией.
