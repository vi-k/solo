> **Состояние на 2026-10-27:** план написан, ждёт ревью на Opus.
> **Что это:** план работ по `ctx.child` — шаги, коммиты, проверки.
> **Связанные записи:** `2026-10-27-ctx-child-design.md` — дизайн и оба его
> ревью; номера тестов и находок ниже — оттуда.

# План: `ctx.child`

Работа идёт в своей копии, ветка `worktree-ctx-child`, и вливается в `main`
перемоткой после ревью работы на Opus и codex. Каждый шаг кончается коммитом
и прогоном проверок затронутых пакетов: `dart format`,
`dart analyze --fatal-infos`, `dart test` (`flutter test` для `flutter_solo`).

## 1. Оверрайды

`chore:` — оверрайды на `async_job` из дерева (находка О4):

- `packages/solo/pubspec_overrides.yaml`,
  `packages/solo/example/pubspec_overrides.yaml` — новые,
  `async_job: path: ../async_job` и `../../async_job`;
- `packages/flutter_solo/pubspec_overrides.yaml` и его пример — `async_job`
  рядом с `solo`.

Первая строка каждого — «Use local async_job until 0.5.0 is published.»
(у `flutter_solo` — общая строка для обоих пакетов). Пример `flutter_solo`
держит комментарий о том, почему файл нужен отдельно, — так же, как сейчас.

Проверка: `dart pub get` в четырёх корнях, `package_config.json` указывает
на `packages/async_job`; полные наборы `solo` и `flutter_solo` зелёные ещё
до правки ядра — оверрайд ничего не меняет, пока ядро прежнее.

## 2. Ядро

`feat(async_job)!: add ctx.child, a child the engine accepts`:

- `JobContext.child` с `@useResult` и dartdoc: фабрика, ничего не запускает
  и не проверяет; правила — от контекста, который сделал ребёнка, родитель —
  тот, кто запустил; незапущенный ребёнок принадлежит держателю, срок до старта
  не идёт, `done` ждёт; реализация по умолчанию — ребёнок ядра, и движок
  со своим контекстом или правилами переопределяет `child`;
- dartdoc класса `JobContext`: `child` в обоих списках исключений — после
  принятой отмены и после конца задачи;
- `JobContextBase.child` — `Job.deferred<T>(body, key:, describe:, timeout:)`;
- `createEachJob` по умолчанию — `child<void>(body, key:, describe:)`, dartdoc:
  переопределять его нужно, только если ребёнку `each` нужно что-то сверх
  `child` или проверка перед ним;
- dartdoc `Job.deferred`: шаг со сроком — `ctx.child(step, timeout: …)`;
- `test/child_factory_test.dart` — тесты 1–7 дизайна;
- `test/extending_test.dart` — тест 8: три движка (переопределённый `child`,
  прежний `createEachJob`, правило в `check()` без `child`).

Проверка ядра; затем `solo` и `flutter_solo` целиком против нового ядра до шага
3 — должны быть зелёными, кроме сторожей документов: README ядра
(`readme_recipe_test.dart`) краснеет здесь же, и его строка таблицы входит
в этот коммит (шаг 4 правит остальные страницы). Красный `reference.md` `solo`
чинится в шаге 3.

## 3. `solo`

`feat(solo)!: add SoloContext.child for code that holds only a context`:

- `SoloContext.child` с `@override`, `@useResult` и dartdoc: ребёнок того же
  контроллера с `W` и `keepWhile` создателя; запущенный другой задачей
  контроллера, проверяет правила создателя;
- `_SoloContext.child` — `_solo.job<W, T>(…, keepWhile: _job._keepWhile)`;
- `_SoloContext.createEachJob` — проверка правил, затем `child<void>`;
- абзац dartdoc `SoloContext` о детях `run`, `start`, `runAll` — «made by
  `job(...)` of the same controller or by `ctx.child`»;
- текст отказа `_own` в `solo.dart` называет `ctx.child`; его цитаты
  в `children_test.dart`, `children_rakes_test.dart`, `doc/children.md`
  и `docs/ru/solo/children.md` — в том же коммите, потому что сторожа сверяют
  их с выводом;
- `doc/reference.md` и `docs/ru/solo/reference.md` — член `child`;
- `test/child_factory_test.dart` — тесты 9–18 дизайна; тест 18 — анализатор
  на временном файле, как в сторожах dartdoc.

## 4. Документы ядра

`docs(async_job): show ctx.child where a child is made`:

- `README.md` / `README.ru.md` — абзац «What the cells leave out»
  о `ctx.child`: строка таблицы уже стоит с шага 2;
- `doc/children.md` и `docs/ru/async_job/children.md`, «Running a child»: абзац
  о `ctx.child` для кода, который движка не знает, и о незапущенном ребёнке;
  `test/support/children_page.dart`, если блок кода меняется;
- `doc/time.md` и перевод, «A deadline for one step»: пример на `ctx.child`;
  `test/support/time_page.dart`, `time_rakes_test.dart`; трасса прежняя;
- `doc/extending.md`, `doc/engine.md` («A rule of your own») и переводы: движок
  со своим контекстом или правилами переопределяет `child` с `@useResult`;
  `each` берёт ребёнка оттуда же;
- `CHANGELOG.md` и `docs/ru/async_job/CHANGELOG.md`: Breaking — новый член
  `JobContext` и `JobContextBase`, расширение с именем `child` уступает ему;
  Added — `ctx.child`.

## 5. Документы `solo` и проекта

`docs(solo): show ctx.child on the children page`:

- `doc/children.md` и перевод: где сказано, что ребёнка делает `job(...)`, —
  `ctx.child` для общего кода, с правилами создателя;
- `CHANGELOG.md` и `docs/ru/solo/CHANGELOG.md`: Breaking — `SoloContext.child`,
  отсылка на ядро;
- `docs/architecture.md` — абзац о `createEachJob` и новый `child`;
- `docs/handoff.md`.

Переводы — humanizer--ru по изменённым абзацам, только `ERROR` линтера.

## 6. Проверки и ревью работы

- Мутации из дизайна, по одной, откат копией: снять `child` из `SoloContext`
  и `_SoloContext` — 9; без `keepWhile` — 11; без `timeout` — 2 и 13;
  `createEachJob` мимо `child` — 8; без `@useResult` на `SoloContext.child` —
  18.
- Все пакеты и оба примера; `python3 tool/reflow.py --check`,
  `check_line_width.py`, `check_translations.py`, `check_links.py`,
  `check_doc_shape.py`, `check_dartdoc.py`, `check_page_code.py`,
  `python3 -m unittest tool/build_site_test.py`, `tool/build_site.py`; стенды
  `tool/doc_snippets.py` и `tool/accumulation_snippets.py`;
  `tool/archive_floor.py` на полу 3.27.0 — в отдельной копии на коммите.
- Ревью работы: Opus и codex (`gpt-6-astra`, `xhigh`), каждому своя копия;
  разбор находок с вердиктами — в отчёте `2026-10-27-ctx-child-report.md`.
- Вливание в `main` перемоткой; push — по слову владельца.

## Что за рамками

- Выпуск: `async_job` 0.5.0, `solo`, scopo, `flutter_solo` — каждый отдельной
  просьбой владельца.
- Сообщение сессии HisBible — после вливания, о том, что `ctx.child` в `main`
  и выйдет с `async_job` 0.5.0.
- Рецепт паузы с пробуждением на страницах.
