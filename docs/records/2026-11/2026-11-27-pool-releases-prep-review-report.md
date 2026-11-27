> **Состояние на 2026-11-27:** ревью закончено, все четыре находки приняты
> и закрыты: в `main` — коммитом «docs: answer the review of the release
> preparation», в ветке `pool-lints-release` — в коммитах подготовки линтов.
> **Что это:** независимое ревью подготовки выпусков `solo` 2.1.0,
> `async_job_lints` 0.2.4 и `solo_lints` 0.4.0 до связок, с вердиктами.
> **Связанные записи:** `2026-11-27-solo-2-1-0-release-report.md`,
> `2026-11-27-async-job-lints-0-2-4-release-report.md`,
> `2026-11-27-solo-lints-0-4-0-release-report.md`,
> `2026-11-27-solo-pool-report.md`.

# Ревью подготовки выпусков solo 2.1.0, async_job_lints 0.2.4, solo_lints 0.4.0

По слову владельца 2026-11-27 «отдай подготовку на ревью». Ревьюер — отдельный
агент на Opus в своей копии дерева на `213dd1c5`, диапазон
`9ef17e81..pool-lints-release`: подготовка поверх влитого и отдельно
отревьюенного пула. Ничего не коммитил и не публиковал. Ниже — его ответы
и находки без правки прозы, вердикты — после каждой находки. Хеши ветки
`pool-lints-release` в тексте ревьюера — до её перестройки.

## Ответы ревьюера на семь вопросов

1. Семвер. `solo` 2.1.0 (минор) верен: новый защищённый член `pool` и геттер
   `pools` у `SoloLanes`, от которого наследуются (решение 134), и новые типы
   `SoloPool`, `SoloQueueOwner`; ничего не удалено, сигнатуры не менялись,
   `_SoloPendingPlaces` — закрытый подкласс `SoloPendingQueue`, исчерпывающий
   `switch` по `SoloPending` не ломается. `solo_lints` 0.4.0 (минор) верен:
   `lane_outside_constructor` (warning) теперь видит `pool(...)` — новое
   предупреждение на коде, который 0.3.1 пропускал. `async_job_lints` 0.2.4
   (патч): для пользователя одного `async_job_lints` верен (четыре новых
   экспорта, без флага `ownLaneReportedElsewhere` правила говорят то же),
   но патч меняет, что сообщает опубликованный `solo_lints` 0.3.1, — см. В1.
2. CHANGELOG. Разделы `solo` 2.1.0 и обоих линтов сходятся с `lib/` с прошлых
   тегов; выдуманного нет; переводы говорят то же (`check_translations.py` —
   «no differences», сверено и чтением). Чего не хватает: в 0.2.4 нет ни слова
   о том, что меняется для `solo_lints` 0.3.1, а в 0.4.0 пункты
   о `key_per_request` и `ignore_failure_hides_bugs` приписаны выпуску, хотя
   в `lib/` `solo_lints` эти правила не менялись: поведение приходит
   из `isSoloMember` 0.2.4 и достаётся 0.3.1 так же (В1).
3. Ограничения и строки версий верны: `solo` — `async_job '>=1.0.0 <1.1.0'`,
   оверрайдов нет; `async_job_lints` — dev `solo: ^2.1.0`; `solo_lints` —
   `async_job_lints: ^0.2.4` в `dependencies`, dev `solo: ^2.1.0`; первые
   строки оверрайдов соответствуют ожидаемым выпускам; README, переводы
   и `example.md` линтов просят `^0.2.4` / `^0.4.0` (сторожа
   `readme_version_test.dart` и `example_page_test.dart` требуют именно
   `^$version`). README `solo` и `flutter_solo` и примеры остаются
   на `solo_lints: ^0.3.0` — по плану. README ядра на `async_job_lints ^0.2.1`
   поднимать не надо (патч). Лишних старых или преждевременных новых версий
   в `packages/`, `site/`, `docs/*.md`, `AGENTS.md` нет. Но на `main` уже лежат
   «Unreleased» обоих линтов и разделы README о пулах при блоках установки
   `^0.2.3` / `^0.3.1` — см. В2.
4. План исполним по шагам: связка `solo` трогает только документы (как прошлые
   релизные коммиты), коммиты ветки переносятся без конфликтов (ветка трогает
   только пакеты линтов и свои записи), снятие оверрайда и проверки против
   опубликованного расписаны. `flutter_solo` 2.0.1 с `solo` 2.1.0 работает:
   `lib/` `flutter_solo` с тега не менялся, а CI `flutter` на `3d2830db`
   прогнал его против `solo` из дерева. Не вовремя станет видно: (а) пуш связки
   `solo` выкладывает на сайт страницы и списки изменений линтов о пулах раньше
   их выпуска (В2); (б) между выходом `solo` 2.1.0 и `async_job_lints` 0.2.4
   опубликованные линты на коде с пулом дают ложное предупреждение
   `outcome_after_await`, а `doc/lanes.md` 2.1.0 обещает `await_own_queue`
   о пуле, которого ещё нет (М1); (в) после выхода 0.2.4 пользователи
   `solo_lints` 0.3.1 получают новое предупреждение о пуле словами о линии
   (В1).
5. Тест «a second call joins the load already in flight» теперь детерминирован:
   всё время фейковое, перед вторым вызовом проверено `api.started == 1` без
   прошедшего времени, т. е. загрузка именно в полёте. Доказывает то же, что
   раньше, и строже. Страницу держит: мутант фикстуры `Policy.sequential`
   роняет `same(job)`, мутант без `key: 'load'` падает на «Policy.droppable
   requires a job key». Закрытие корректно: зонд после
   `unawaited(profile.close()); async.flushMicrotasks();` —
   `[finished 1, pendingTimers 0, microtaskCount 0, isClosed true]`. Соседи
   пишут `profile.close(); async.flushTimers();` — разница в идиоме,
   не в смысле. Файл в копии: «+125: All tests passed!».
6. Записи: шапки по формату, имена полные, на временное не ссылаются; ширина
   ≤79 по символам у всех трёх, `reflow.py --check` — «every paragraph is
   filled to 79 columns». Проверенные утверждения сходятся: «не убрано
   ни строки» (`--numstat` с тегов: только добавления в тестах обоих пакетов),
   сторожа и что они требуют, мутант `Policy.sequential`, CI `gate`
   на `3d2830db` (все пять заданий success, ветка `release-check-solo-2.1.0`
   на origin удалена — 404), версии на pub.dev (solo 2.0.1, async_job_lints
   0.2.3, solo_lints 0.3.1, flutter_solo 2.0.1, async_job 1.0.6), тегов новых
   нет. Неверны утверждения о поведении опубликованных линтов (В1, М1).
7. Пробная публикация `solo` в чистой копии на Dart 3.14.0: «Publishing solo
   2.1.0», «Package has 0 warnings.», в архиве нет `pubspec_overrides.yaml`
   и `README.ru.md`; описание 175 символов (≤180). До первой связки не решено
   только то, что в В1 и В2: оба вопроса — к владельцу до связки `solo`, потому
   что пуш этой связки уже выкладывает на сайт тексты, которых они касаются.

## Находки

**В1. Важная. Патч `async_job_lints` 0.2.4 меняет то, что сообщает
опубликованный `solo_lints` 0.3.1, а записи, CHANGELOG и README говорят
обратное.**

Где:
`docs/records/2026-11/2026-11-27-async-job-lints-0-2-4-release-report.md:49-51`
(«Пользователь `solo_lints` 0.3.1 получит 0.2.4 и сам, через `^0.2.3`, но пулов
0.3.1 не знает»); `packages/async_job_lints/CHANGELOG.md:1-22` (о `solo_lints`
0.3.1 ни слова); `packages/async_job_lints/README.md:232-235` и `:272`
(и перевод `README.ru.md:235`, `:275`): пул своей очереди отдаётся
`await_own_queue` «solo_lints newer than 0.3.1»;
`packages/solo_lints/CHANGELOG.md:9-16` и перевод: `key_per_request`
и `ignore_failure_hides_bugs` записаны в изменения 0.4.0, а `dart analyze`
«fails on code with a pool that it passed before».

Что не так. Распознавание пула живёт в `async_job_lints` (`queueLaneOf`,
`isSoloMember`, `_laneField`), а `solo_lints` 0.3.1 спрашивает его и передаёт
`ownLaneReportedElsewhere: true` (тег `solo_lints-v0.3.1`,
`packages/solo_lints/lib/solo_lints.dart:33`) при `async_job_lints: ^0.2.3`.
Сервер анализа у любого, кто назвал `solo_lints: ^0.3.x` (так велят README
`solo` 2.1.0 и `flutter_solo`), возьмёт 0.2.4 сам. С ним 0.3.1 на коде с пулом:

- `await_own_queue` (WARNING, включён по имени плагина) сообщает об ожидании
  своего пула и об `await close()` / `cancelAll()` из тела пула — но сообщением
  о линии: «'enqueue' waits for the running job of the lane '_likes', and the
  running job waits for 'enqueue'.», совет «queue it in another lane». С 0.2.3
  о пуле он молчал;
- `key_per_request` и `ignore_failure_hides_bugs` начинают видеть члены пула —
  ровно как 0.4.0;
- `bare_await` и `discarded_outcome` замолкают на ожидании своего пула (с 0.2.3
  при том же флаге — сообщали).

Чем кончится. Пользователь `solo_lints` 0.3.x с пулом получает новое
предупреждение, роняющее `dart analyze`, через патч чужого пакета и с неверными
словами («lane», «the running job» у пула из нескольких мест). Выбор «патч»
и строка «пулов 0.3.1 не знает» сделаны на ложной посылке; README 0.2.4 обещает
тишину `bare_await` и разбор пула только с `solo_lints` новее 0.3.1. Минор
`solo_lints` 0.4.0 остаётся оправдан (его держит `lane_outside_constructor`
на `pool(...)`), но фраза о `dart analyze` и пункты о двух правилах описывают
то, что 0.3.1 после 0.2.4 уже делает.

Как исправить (решать владельцу до связки `solo`, потому что README и CHANGELOG
линтов уже на `main`): (а) оставить патч, но сказать правду: в CHANGELOG
0.2.4 — что `solo_lints` 0.3.1 с ним сообщает `await_own_queue` об ожидании
своего пула сообщением о линии и что `key_per_request` /
`ignore_failure_hides_bugs` видят пул; поправить фразы «newer than 0.3.1»
в README и переводе; в 0.4.0 — что нового именно в 0.4.0 (своё сообщение
о пуле, `lane_outside_constructor` на `pool(...)`, `stale_emit`); исправить
запись; (б) выпустить `async_job_lints` как 0.3.0, чтобы `^0.2.3` его не брал
(по `docs/conventions.md`: «минор `async_job_lints` — ломающий для
`solo_lints`»), а `solo_lints` 0.4.0 просить `^0.3.0`; цена — README ядра
(`^0.2.1`) поднимается со следующим выпуском `async_job`, а пользователь одного
`async_job_lints` не получит исправление `outcome_after_await` сам.

На чём основано. Зонды в копиях дерева, где `lib/` пакета линтов взят
из прошлого тега, а тесты — из `HEAD`:

- `lib/` `async_job_lints` 0.2.3, тесты `-N test_pool`:
  `BareAwaitOwnLaneReportedElsewhereTest test_pools` — «Found but did not
  expect: bare_await.bare_await [623, 5 …] [646, 5 …] [858, 5 …]»;
  `DiscardedOutcomeOwnLaneReportedElsewhereTest test_pools` — «Found but did
  not expect: discarded_outcome … [416, 4 …] [474, 4 …]».
- `lib/` `solo_lints` 0.3.1 поверх `async_job_lints` 0.2.4 из дерева,
  `test/await_own_queue_test.dart -N pool`: «Expected but did not find:
  await_own_queue [614, 41, messageContains: ["'enqueue' waits for a job of the
  pool '_likes' this job runs in"]] Found but did not expect:
  await_own_queue.await_own_queue [614, 41, 'enqueue' waits for the running job
  of the lane '_likes', and the running job waits for 'enqueue'., "Run the job
  with 'ctx.run' instead of the lane, or queue it in another lane."]», итог «+2
  -2» (`test_close_of_lanes_from_a_pool` прошёл);
  `key_per_request_test.dart -N pool`
  и `ignore_failure_hides_bugs_test.dart -N pool` — «All tests passed!».
- `lib/` `solo_lints` 0.3.1 поверх `lib/` 0.2.3: те же тесты пула — только
  «Expected but did not find» (о пуле молчит, итог «+1 -3»); `key_per_request`
  и `ignore_failure_hides_bugs` — «Expected but did not find».

Вердикт: принято, подтверждено своими зондами. `lib/` `solo_lints` 0.3.1 поверх
`async_job_lints` 0.2.4 из дерева на `await_own_queue_test.dart -N pool` даёт
«'enqueue' waits for the running job of the lane '_likes', and the running job
waits for 'enqueue'.», а тесты пула `key_per_request`
и `ignore_failure_hides_bugs` у него проходят; `stale_emit`
и `lane_outside_constructor` о пуле молчат — это новое именно в 0.4.0. `lib/`
`async_job_lints` 0.2.3 на тестах пула — «Found but did not expect»
у `bare_await` и `discarded_outcome`. Выбран путь (а): 0.2.4 остаётся патчем,
документы говорят правду — решение 172 `docs/settled.md`. Под 0.3.1 перемена —
исправление: ложное `outcome_after_await` о `job` пула уходит, ожидание своего
пула переходит из `bare_await` и `discarded_outcome` в правило о самоожидании,
и обещание `doc/lanes.md` о пуле становится правдой для того, кто ставит
`solo_lints` по README `solo` (`^0.3.0`). Новое предупреждение на коде, который
проходил, возможно только у кода с пулом, написанного против опубликованного
`solo` 2.1.0 до выхода 0.2.4. Путь (б) оставил бы пользователей README `solo`
на 0.2.3 с ложным предупреждением, пока следующий выпуск `solo` не поднимет
`solo_lints` до `^0.4.0`. Сделано коммитом «docs: answer the review of the
release preparation» в `main`: раздел 0.2.4 `CHANGELOG.md` `async_job_lints`
и перевод говорят, что видит с ним `solo_lints` 0.3.1; README и перевод —
«0.3.1 or newer» вместо «newer than 0.3.1» и что сообщение о пуле приходит
с 0.4.0. В ветке `pool-lints-release`: раздел 0.4.0 `CHANGELOG.md` `solo_lints`
и перевод отделяют то, что 0.3.1 уже делает под 0.2.4, от нового в 0.4.0,
и минор держит `lane_outside_constructor`; записи
`2026-11-27-async-job-lints-0-2-4-release-report.md`
и `2026-11-27-solo-lints-0-4-0-release-report.md` исправлены.

**В2. Важная. Пуш связки `solo` выкладывает на сайт страницы линтов о пулах
до выпуска линтов.**

Где: `docs/handoff.md:12-14`,
`docs/records/2026-11/2026-11-27-solo-2-1-0-release-report.md:62-66`,
`2026-11-27-async-job-lints-0-2-4-release-report.md:53-55`,
`2026-11-27-solo-lints-0-4-0-release-report.md:57-59`: ветка
`pool-lints-release` объяснена тем, что иначе сайт покажет `^0.2.4` и `^0.4.0`
раньше pub.dev.

Что не так. Вне `main` держатся только строки версий. Всё остальное о пулах
в линтах уже на `main` (`55ad7952`) и уйдёт на сайт с пушем связки `solo`
(`site.yml` собирает по пушу в `main` при изменении `packages/*/README.md`,
`packages/*/CHANGELOG.md`, `docs/ru/**`): `packages/solo_lints/CHANGELOG.md`
и `packages/async_job_lints/CHANGELOG.md` начинаются с `## Unreleased` о пулах
(страницы `<пакет>/changelog/` на обоих языках); README `solo_lints` в таблице
правил называет `lane(...) or pool(...)` у `lane_outside_constructor`
и описывает пул в `await_own_queue` (`README.md:84`, `:116-125`, `:241-252`),
а блок установки — `solo_lints: ^0.3.1` (`:30`, `:49`); README
`async_job_lints` — `^0.2.3` (`:30`, `:48`) рядом с текстом о пуле.

Чем кончится. До связки `solo_lints` (два отдельных запроса владельца спустя)
читатель сайта ставит `solo_lints ^0.3.1` по блоку установки и не получает
обещанного рядом правила на `pool(...)`; на странице списка изменений висит
«Unreleased». Это то, от чего владелец просил уберечь сайт («сайт подождёт
выпуска»), а записи утверждают, что ветка это решает.

Как исправить. Минимум — записать в handoff и записях правду и вынести
владельцу до связки `solo`: либо принять окно, либо держать его коротким
(запросы на связки линтов сразу за `solo`). Вынести разделы README
и «Unreleased» линтов с `main` в ветку задним числом дороже и рискованнее.

На чём основано. Файлы на коммите `55ad7952` (это `main`):
`packages/solo_lints/CHANGELOG.md` открывается «## Unreleased / - Five rules
learn the pools…», `packages/async_job_lints/CHANGELOG.md` — «## Unreleased / -
`plugin_api.dart` exports `isSoloQueueOwner`…»;
в `packages/solo_lints/README.md` слово `pool` — строки 84, 116-125, 199,
241-252, а версии — «30: solo_lints: ^0.3.1», «49: version: ^0.3.1»;
в `packages/async_job_lints/README.md` — «30: async_job_lints: ^0.2.3», «48:
version: ^0.2.3», «232: … one newer than 0.3.1». `.github/workflows/site.yml`:
`push: branches: [main]` с путями выше; `tool/build_site.py:16` — список
изменений — страница пакета на обоих языках.

Вердикт: принято. Ветка держит вне `main` только версии и заголовки разделов,
а тексты линтов о пуле — README и «Unreleased» обоих списков изменений — пришли
в `main` с пулом и выйдут на сайт с пушем связки `solo`. Из `main` их не уношу:
это переписывать влитое ради окна, которое закрывают связки линтов. Решение 173
`docs/settled.md`. Сделано тем же коммитом: запись
`2026-11-27-solo-2-1-0-release-report.md`, записи обоих линтов
и `docs/handoff.md` говорят, что держит ветка и что окно открывает пуш связки
`solo`; владельцу — держать окно коротким.

**М1. Мелочь. «Опубликованные линты о пуле молчат» — неверно; окно между `solo`
2.1.0 и `async_job_lints` 0.2.4 даёт ложное предупреждение.**

Где: `docs/records/2026-11/2026-11-27-solo-2-1-0-release-report.md:48-51`
(«Опубликованные `async_job_lints` 0.2.3 и `solo_lints` 0.3.1 пула не знают
и о нём молчат»); связано — `packages/solo/doc/lanes.md:751-758` (уходит
на pub.dev и сайт со связкой `solo`).

Что не так. 0.2.3 на коде с пулом не молчит: `outcome_after_await` (WARNING)
ложно сообщает на `_likes.job(...)` → `await` → `step.ignoreFailure()` →
`_likes.enqueueJob(step)` («The job can end during a wait above…»), потому что
0.2.3 не знает, что `job` пула задачу не ставит; `discarded_outcome` (WARNING)
на `await` своего пула `.done` говорит «outcome is dropped», хотя беда там —
ожидание самого себя. А `doc/lanes.md` 2.1.0 обещает: «the `await_own_queue`
lint of solo_lints reports a wait for a job of the own pool whatever the key» —
до выхода 0.2.4 это неправда для любого опубликованного `solo_lints`, после —
правда со словами о линии (В1), со своим сообщением — только с 0.4.0, которого
README `solo` (`solo_lints: ^0.3.0`) не пускает.

Чем кончится. Пользователь, взявший пул сразу после `solo` 2.1.0, получит
ложное предупреждение, роняющее `dart analyze`, и не получит обещанного
страницей; запись вводит владельца в заблуждение о цене паузы между связками.

Как исправить. Исправить фразу записи (назвать оба предупреждения и окно);
держать паузу между связками `solo` и `async_job_lints` короткой.

На чём основано. `lib/` `async_job_lints` 0.2.3, тест из `HEAD`
`outcome_after_await_test.dart -N test_pool_job` — «Found but did not expect:
outcome_after_await.outcome_after_await [342, 13, The job can end during a wait
above, and its failure is then answered for before this line reads
'ignoreFailure()'.…]»; `discarded_outcome` — зонд из В1; `severity`
в `lib/src/rules/outcome_after_await.dart`
и `lib/src/rules/discarded_outcome.dart` у 0.2.3 —
`DiagnosticSeverity.WARNING`.

Вердикт: принято, подтверждено зондом: `lib/` `async_job_lints` 0.2.3,
`outcome_after_await_test.dart -N pool` — «Found but did not expect:
outcome_after_await.outcome_after_await [342, 13, The job can end during a wait
above…]». Фраза записи `2026-11-27-solo-2-1-0-release-report.md` исправлена
тем же коммитом: опубликованные линты на коде с пулом не молчат, и пауза между
связками `solo` и `async_job_lints` — окно ложного предупреждения.
`doc/lanes.md` не тронут: с выходом 0.2.4 его обещание верно и под `solo_lints`
0.3.1 (В1).

**М2. Мелочь. `AGENTS.md` называет локальный пол приложения, которого на машине
нет.**

Где: `AGENTS.md:291-292` («пол приложения — в `~/fvm/versions/3.44.0`»).

Что не так. Запись о выпуске честно говорит, что 3.44.0 не установлен и пол
приложения взят из CI, но правило `AGENTS.md` осталось прежним.

Чем кончится. Следующий агент по `AGENTS.md` пойдёт в несуществующий каталог
при проверке пола `camera_example` перед связкой `flutter_solo`.

Как исправить. Поставить 3.44.0 (`fvm install 3.44.0`) или поправить фразу
`AGENTS.md`: пол приложения локально не стоит, его гоняет CI.

На чём основано. `ls ~/fvm/versions/` — «3.27.0/ 3.38.1/ 3.47.1/ 3.50.0/
stable/»; запись `2026-11-27-solo-2-1-0-release-report.md:111-112` — «Пол
приложения `camera_example` на Flutter 3.44.0 локально не прогнан: SDK
не установлен».

Вердикт: принято. Тем же коммитом `AGENTS.md` говорит, что пол приложения лежит
в `~/fvm/versions/3.44.0`, если поставлен (`fvm install 3.44.0`), а без него
его проверяет только задание `floor` CI.

## Что ревьюер проверил без находок

- Прогоны в копии на `213dd1c5`: `testing_rakes_test.dart` — +125,
  `async_job_lints` — +234, `solo_lints` — +174; `reflow.py --check`,
  `check_line_width.py`, `check_translations.py`, `check_links.py`,
  `check_dartdoc.py` — чисто.
- `dart pub publish --dry-run` `solo` — 0 warnings.
- CI `gate` 46024688950 на `3d2830db`: dart, docs, flutter, snippets, floor —
  success.
- Якоря `doc/lanes.md#a-pool-of-places` и `lanes.md#пул-мест` существуют.
