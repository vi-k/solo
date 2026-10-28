> **Состояние на 2026-10-28:** план, не начат; ждёт владельца.
> **Что это:** план реализации второй волны `solo_lints` по дизайну, семь
> задач: стенд и два исправления, два правила с исправлением одного, сторож
> страницы ошибок, документы.
> **Связанные записи:** `2026-10-28-solo-lints-wave-2-design.md`,
> `2026-10-28-solo-lints-design.md`, `2026-10-28-solo-lints-report.md`.

# План: `solo_lints`, вторая волна

> **Для агентов-исполнителей:** обязательный скилл —
> superpowers:subagent-driven-development (рекомендуется) или
> superpowers:executing-plans, задача за задачей. Шаги отмечаются чекбоксами
> (`- [ ]`).

**Цель:** правила `key_per_request` и `ignore_failure_hides_bugs`, быстрые
исправления `release_on_the_call`, `catch_without_check` и `key_per_request`,
сторож страницы ошибок.

**Устройство:** всё в `packages/solo_lints`. Правило — `AnalysisRule`
в `lib/src/rules/`, исправление — `ResolvedCorrectionProducer`
в `lib/src/fixes/`, регистрация — `SoloLintsPlugin.register`. Типы `async_job`
и `solo` опознаются по имени и библиотеке через `lib/src/context.dart`. Тесты —
`analyzer_testing` на настоящих исходниках пакетов через
`test/support/rule_base.dart`.

**Стек:** Dart 3.10, `analysis_server_plugin` 0.3.14+, `analyzer` 12.1.0–14.x,
`analyzer_plugin` 0.14.8+, `analyzer_testing`, `test_reflective_loader`.

**Дизайн:** `2026-10-28-solo-lints-wave-2-design.md`. Исполнитель читает его
целиком до первой задачи: план спорит от дизайна и не повторяет его доводов.

## Общие ограничения

- `lib/` не зависит от `async_job` и `solo`: тип опознаётся по имени
  и библиотеке, хелперами `lib/src/context.dart`.
- Зависимости `lib/`: прежние плюс `analyzer_plugin: '>=0.14.8 <0.15.0'`,
  в алфавитном порядке (`sort_pub_dependencies`). Других новых нет.
- Оба новых правила — линты: `LintCode` без `severity`, регистрация
  `registerLintRule`. Имена, сообщения и исправления в `LintCode` — дословно
  из дизайна.
- Исправление ничего не строит там, где правка неоднозначна; у всех трёх
  `applicability` — `CorrectionApplicability.singleLocation`.
- Перенос строк в исправлениях — не забота продюсера: ожидаемый текст
  в тестах — сырой результат правок, без `dart format`.
- Оверрайды `pubspec_overrides.yaml` остаются как есть.
- Перед коммитом кода из `packages/solo_lints`: `dart pub get`
  (не `flutter pub get`), `dart format lib test`, `dart analyze --fatal-infos`,
  `dart doc --dry-run`, `dart test` — всё зелёное.
- Код, комментарии, сообщения коммитов и диагнозов — по-английски; записи для
  владельца — по-русски.
- Markdown — ширина 79: `python3 tool/reflow.py`
  и `python3 tool/check_line_width.py` из корня перед каждым коммитом с `.md`;
  запись в `docs/records/` заливается названной по имени, `reflow.py` — только
  для `.md`. Шапки записей (цитаты) заливаются руками.
- Перевод правится тем же коммитом, что оригинал;
  `python3 tool/check_translations.py` зелёный; правленые абзацы переводов
  проходят линтер скилла `humanizer--ru`, считаются только `ERROR`, шаг «Голос»
  пропускается.
- Коммиты — Conventional Commits, по одному на задачу,
  с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git status`
  и ветка `worktree-solo-lints-wave-2` перед каждым, чужое не коммитить.
- Push, публикация, теги — нет.

## Фокус ревью

Случаи, которых дизайн прямо не называет, а пользователь встретит первыми.
Каждый закреплён тестом в своей задаче.

1. Вызов, принёсший ресурс, записан в несколько строк с висящей запятой:
   `ctx.join(\n  Database.open,\n)`. Исправление `release_on_the_call` даёт
   разбираемый код, без `,,` — задача 2.
2. Цель `ignoreFailure()` в скобках или с `this.`: `(load()).ignoreFailure()`,
   `this.load().ignoreFailure()` — диагноз как без них, задача 5.
3. Ключ, в который параметр входит через интерполяцию или выражение:
   `key: 'load-$id'`, `key: id.hashCode` — правило молчит, задача 3.
4. Ключ — уже запись без параметров: `key: (_Op.load, 1)`. Исправление
   оборачивает её целиком: `((_Op.load, 1), id)` — задача 4.
5. На странице ошибок у раздела «Don't do this» без пары «Do this» или
   наоборот. Сторож краснеет с именем раздела, а не падает индексом — задача 6.

---

### Задача 1: стенд исправлений и `catch_without_check`

Первым шагом — зонд из дизайна: собирается ли контекст исправления в тесте.
Опорный путь — только публичный API, и он, по чтению исходников, есть:

- `result` — `ResolvedUnitResult` теста, его ставит `assertDiagnostics` (поле
  есть в `analyzer_testing` 0.2.5 и 0.4.4);
- `result.session.getResolvedLibrary(result.path)` — `ResolvedLibraryResult`;
- `CorrectionProducerContext.createResolved(libraryResult:, unitResult:,
  selectionOffset:, selectionLength:)`
  из `package:analysis_server_plugin/edit/dart/correction_producer.dart`;
  `DartFixContext` необязателен;
- `ChangeBuilder(session: result.session)` из
  `package:analyzer_plugin/utilities/change_builder/change_builder_core.dart`,
  `producer.compute(builder)`, правки — `builder.sourceChange.edits`, текст —
  `SourceEdit.applySequence`
  из `package:analyzer_plugin/protocol/protocol_common.dart`.

**Правило по итогу зонда.** Обошлись публичным API — тесты исправлений входят
в архив и идут на `floor`; в отчёт — что довод дизайна об `src/`
не подтвердился. Понадобился `src/` — тесты исправлений исключает `.pubignore`,
как в дизайне. Не собралось вовсе — остановиться и доложить: по дизайну решает
владелец.

**Files:**

- Modify: `packages/solo_lints/pubspec.yaml` — `analyzer_plugin`
  в `dependencies`.
- Create: `packages/solo_lints/test/support/fix_base.dart`.
- Modify: `packages/solo_lints/lib/src/context.dart` — сюда переезжает
  `_contextAround` из `catch_without_check.dart`.
- Modify: `packages/solo_lints/lib/src/rules/catch_without_check.dart`.
- Create: `packages/solo_lints/lib/src/fixes/add_check.dart`.
- Modify: `packages/solo_lints/lib/solo_lints.dart`.
- Create: `packages/solo_lints/test/add_check_fix_test.dart`.
- Modify (если зонд потребовал `src/`): `packages/solo_lints/.pubignore`.

**Interfaces:**

- Produces:
  - `Element? bodyContextAround(AstNode node)` в `context.dart` — прежний
    `_CatchWithoutCheck._contextAround`, поведение то же;
  - `abstract class FixTest extends RuleTest` в `fix_base.dart`:
    - `ResolvedCorrectionProducer Function({required CorrectionProducerContext
      context}) get producer` — генератор исправления под тестом; тип выписан,
      а не `ProducerGenerator`: тот объявлен в `src/`;
    - `Future<void> assertFix(String code, String span, String expected)` —
      `span` в форме `assertAt` (с `[[ ]]`), правило даёт диагноз ровно там,
      правка продюсера по этому месту даёт `expected`;
    - `Future<void> assertNoFix(String code, String span)` — диагноз есть,
      правок нет;
  - `class AddCheck extends ResolvedCorrectionProducer`
    в `lib/src/fixes/add_check.dart`, `FixKind('solo_lints.fix.addCheck', 50,
    "Add '{0}.check();' as the first line of the catch")`, `fixArguments` —
    `[имя контекста]`.

- [ ] **Шаг 1: зонд.** В `fix_base.dart` — `FixTest` по пути выше. Временный
  продюсер, вставляющий `// probe` в начало файла, и один тест
  на `catch_without_check` проверяют, что путь работает. Прогон:
  `dart test test/add_check_fix_test.dart` из `packages/solo_lints`. Временный
  продюсер в коммит не идёт.

- [ ] **Шаг 2: тесты `AddCheck`** в `test/add_check_fix_test.dart`:
  - `test_on_object` — `on Object catch (error) {\n    await hw.reset();` →
    первой строкой блока `ctx.check();` с отступом `await hw.reset();`;
  - `test_bare_catch` — `catch (e) {` без `on`, диагноз на `catch`;
  - `test_empty_block` — `on Object catch (_) {}` → `ctx.check();` с отступом
    блока плюс два пробела, блок многострочный;
  - `test_context_named_otherwise` — контекст назван `c`: вставка `c.check();`.

- [ ] **Шаг 3: прогон** — красные: `AddCheck` нет.

- [ ] **Шаг 4: `AddCheck`.** От `node` вверх до `CatchClause`, контекст —
  `bodyContextAround`; нет контекста — ничего не строит. Регистрация
  в `SoloLintsPlugin.register`:
  `registry.registerFixForRule(CatchWithoutCheck.code, AddCheck.new)`.
  `catch_without_check.dart` зовёт `bodyContextAround` вместо своего метода.

- [ ] **Шаг 5: прогон всего пакета** — зелёный, включая
  `test/catch_without_check_test.dart` без правок.

- [ ] **Шаг 6: коммит**
  `feat(solo_lints): offer ctx.check() for a catch without a check`.

### Задача 2: исправление `release_on_the_call`

**Files:**

- Create: `packages/solo_lints/lib/src/fixes/release_on_the_call.dart`.
- Modify: `packages/solo_lints/lib/src/rules/release_on_the_call.dart` —
  `_broughtBy` выносится так, чтобы продюсер нашёл вызов и переменную тем же
  кодом.
- Modify: `packages/solo_lints/lib/solo_lints.dart`.
- Create: `packages/solo_lints/test/release_on_the_call_fix_test.dart`.

**Interfaces:**

- Consumes: `FixTest` (задача 1).
- Produces: `class PassReleaseToCall extends ResolvedCorrectionProducer`,
  `FixKind('solo_lints.fix.passReleaseToCall', 50,
  "Pass the release as '{0}:' of the call")`, `fixArguments` — `['dispose']`
  или `['discard']`.

- [ ] **Шаг 1: тесты** в `test/release_on_the_call_fix_test.dart`, с `_core`
  из `release_on_the_call_test.dart`:
  - `test_tear_off` —
    `final db = await ctx.join(Database.open);\n ctx.onDispose(db.close);` →
    `final db = await ctx.join(Database.open, dispose: (db) => db.close());`,
    строки `onDispose` больше нет;
  - `test_literal_without_parameters` — `ctx.onDiscard(() => a.close());` после
    `ctx.abandonable(...)` → `discard: (a) => a.close()`;
  - `test_async_block_literal` —
    `ctx.onDispose(() async { await b.close(); });` →
    `dispose: (b) async { await b.close(); }`;
  - `test_trailing_comma` (фокус ревью 1) —
    `ctx.join(\n    Database.open,\n  )` → `dispose:` встаёт после висящей
    запятой, результат разбирается без ошибок;
  - `test_no_fix_for_function_name` — `ctx.onDispose(closeAll);`, где
    `closeAll` упоминает `db`, → `assertNoFix`.

- [ ] **Шаг 2: прогон** — красные.

- [ ] **Шаг 3: `PassReleaseToCall`.** Две правки: аргумент `dispose:` или
  `discard:` в конец списка аргументов вызова и удаление инструкции
  с освобождением целиком, с её строкой. Отрыв `x.m` — только если `x` и есть
  объявленная переменная; литерал — только без параметров. Регистрация
  `registerFixForRule(ReleaseOnTheCall.code, PassReleaseToCall.new)`.

- [ ] **Шаг 4: прогон пакета** — зелёный.

- [ ] **Шаг 5: коммит**
  `feat(solo_lints): offer to pass a release to the call that brings it`.

### Задача 3: правило `key_per_request`

**Files:**

- Create: `packages/solo_lints/lib/src/rules/key_per_request.dart`.
- Modify: `packages/solo_lints/lib/src/context.dart` — опознание вызовов `Solo`
  и `Policy.droppable`, если их нет.
- Modify: `packages/solo_lints/lib/solo_lints.dart` —
  `registerLintRule(KeyPerRequest())`, doc-комментарий класса называет три
  линта.
- Create: `packages/solo_lints/test/key_per_request_test.dart`.

**Interfaces:**

- Produces:
  - `class KeyPerRequest extends AnalysisRule`, `static const LintCode code`:
    имя `'key_per_request'`, сообщение `"'{0}' is one key for every call:
    Policy.droppable hands a later caller the result of the first."`,
    исправление `"Put the arguments the body reads into the key."`; диагноз
    на выражении ключа, `{0}` — его `toSource()`;
  - для задачи 4 — функция в `key_per_request.dart`, видимая продюсеру:
    `({Expression key,
    List<FormalParameterElement> read})? sharedKey( MethodInvocation call)` —
    ключ и параметры, которые читает тело, в порядке объявления, или `null`,
    если правило здесь молчит. Правило и продюсер решают одним кодом.

- [ ] **Шаг 1: тесты** в `test/key_per_request_test.dart` с обвязкой: класс
  `Profiles extends Solo<Ready>`, `enum _Op { load }`, заглушка `api`:
  - `test_enqueue` — блок «Don't do this» раздела «A key for each request»
    страницы ошибок → диагноз на `_Op.load`;
  - `test_enqueue_job` — `enqueueJob(job(key: _Op.load, (ctx) => api.load(id)),
    policy: Policy.droppable)` → диагноз на `_Op.load`;
  - `test_key_with_parameter` — `key: (_Op.load, id)` → тишина;
  - `test_key_reads_parameter_otherwise` (фокус ревью 3) — `key: 'load-$id'`
    (в строке теста — `\$id`) и `key: id.hashCode` → тишина;
  - `test_other_policy` — `Policy.sequential` и без `policy:` → тишина;
  - `test_body_reads_no_parameter` — тело не читает `id` → тишина;
  - `test_key_from_field` — ключ `_key`, поле класса, тело читает `id` →
    диагноз;
  - `test_body_is_tear_off` — тело `_load` вместо литерала → тишина;
  - `test_local_function` — объемлющий — локальная функция с параметром, тело
    читает его → диагноз.

- [ ] **Шаг 2: прогон** — красные.

- [ ] **Шаг 3: `KeyPerRequest`.** `addMethodInvocation`; `enqueue`
  и `enqueueJob` — члены `Solo` из `solo`, цель — нет, `this` или выражение
  типа `Solo`. `Policy.droppable` — константа `droppable` перечисления `Policy`
  из `solo`. Объемлющий — ближайший `MethodDeclaration` или
  `FunctionDeclaration`; ссылка — `SimpleIdentifier` с элементом параметра.

- [ ] **Шаг 4: прогон пакета** — зелёный.

- [ ] **Шаг 5: коммит**
  `feat(solo_lints): report one droppable key for every request`.

### Задача 4: исправление `key_per_request`

**Files:**

- Create: `packages/solo_lints/lib/src/fixes/key_per_request.dart`.
- Modify: `packages/solo_lints/lib/solo_lints.dart`.
- Create: `packages/solo_lints/test/key_per_request_fix_test.dart`.

**Interfaces:**

- Consumes: `FixTest` (задача 1), `sharedKey` (задача 3).
- Produces: `class PutArgumentsIntoKey extends ResolvedCorrectionProducer`,
  `FixKind('solo_lints.fix.putArgumentsIntoKey', 50,
  'Put the arguments the body reads into the key')`.

- [ ] **Шаг 1: тесты:**
  - `test_one_parameter` — `key: _Op.load` → `key: (_Op.load, id)`;
  - `test_two_parameters_in_order` — `load(String id, int page)`, тело читает
    `page`, потом `id` → `(_Op.load, id, page)`;
  - `test_unread_parameter_left_out` — `load(String id, bool force)`, тело
    читает только `id` → `(_Op.load, id)`;
  - `test_record_key` (фокус ревью 4) — `key: (_Op.load, 1)` →
    `key: ((_Op.load, 1), id)`;
  - `test_enum_and_nullable` — параметры `_Op kind` и `String? id` → правка
    есть;
  - `test_no_fix_for_list` — параметр `List<String> ids` → `assertNoFix`;
  - `test_no_fix_for_callback` — параметр `void Function() onDone` →
    `assertNoFix`.

- [ ] **Шаг 2: прогон** — красные.

- [ ] **Шаг 3: `PutArgumentsIntoKey`.** Одна правка — замена текста ключа. Тип
  каждого параметра — `String`, `int`, `double`, `num`, `bool` из `dart:core`
  или перечисление, с `?` или без; иначе ничего не строит. Регистрация
  `registerFixForRule(KeyPerRequest.code, PutArgumentsIntoKey.new)`.

- [ ] **Шаг 4: прогон пакета** — зелёный.

- [ ] **Шаг 5: коммит**
  `feat(solo_lints): offer to put the arguments into a droppable key`.

### Задача 5: правило `ignore_failure_hides_bugs`

**Files:**

- Create: `packages/solo_lints/lib/src/rules/ignore_failure_hides_bugs.dart`.
- Modify: `packages/solo_lints/lib/src/context.dart` — если нужен общий хелпер.
- Modify: `packages/solo_lints/lib/solo_lints.dart` —
  `registerLintRule(IgnoreFailureHidesBugs())`, doc-комментарий.
- Create: `packages/solo_lints/test/ignore_failure_hides_bugs_test.dart`.

**Interfaces:**

- Produces: `class IgnoreFailureHidesBugs extends AnalysisRule`,
  `static const LintCode code`: имя `'ignore_failure_hides_bugs'`, сообщение
  `"'ignoreFailure()' also hides the bugs that '{0}' lets through."`,
  исправление `"Drop 'ignoreFailure()': isExpectedError already keeps the
  expected errors quiet."`; диагноз на `methodName` вызова `ignoreFailure`.

- [ ] **Шаг 1: тесты.** Обвязка: `class Profiles extends Solo<Ready>` с методом
  `load()` через `enqueue(..., isExpectedError: (e) => e is ApiException)`.
  `{0}` в ожиданиях — по дизайну.
  - `test_method_of_same_library` — `profiles.load().ignoreFailure();` →
    диагноз, `{0}` = `load's isExpectedError`;
  - `test_direct_call` — внутри класса
    `enqueue(..., isExpectedError: ...).ignoreFailure();` → `{0}` =
    `enqueue's isExpectedError`;
  - `test_job_through_enqueue_job` — метод
    `load() => enqueueJob(job(..., isExpectedError: ...))` → диагноз;
  - `test_chain` — `load() => _load()`, `_load() => enqueue(...)` → `{0}` про
    `load`;
  - `test_single_return` — метод с блочным телом из одного `return` → диагноз;
  - `test_accumulator_field` —
    `late final _saves = collect(..., isExpectedError: ...)`,
    `_saves.add(e).ignoreFailure();` → диагноз, `{0}` про `_saves`;
  - `test_cascade_statement` — `profiles.load()..ignoreFailure();` → диагноз;
  - `test_cascade_in_void_callback` —
    `onPressed: () => profiles.load()..ignoreFailure()`, параметр типа
    `void Function()` → диагноз;
  - `test_cascade_kept` — `final job = profiles.load()..ignoreFailure();` →
    тишина;
  - `test_parentheses_and_this` (фокус ревью 2) — `(load()).ignoreFailure();`
    и `this.load().ignoreFailure();` внутри класса → два диагноза;
  - `test_no_predicate` — `load()` без `isExpectedError` → тишина;
  - `test_variable` — `final job = load(); job.ignoreFailure();` → тишина;
  - `test_other_library` — `load()` объявлен во втором файле теста (`newFile`)
    и импортирован → тишина;
  - `test_recursion` — `a() => b()`, `b() => a()`, `a().ignoreFailure();` →
    тишина, тест не виснет.

- [ ] **Шаг 2: прогон** — красные.

- [ ] **Шаг 3: `IgnoreFailureHidesBugs`.** `addMethodInvocation`;
  `ignoreFailure` — член из `async_job` или `solo`. Сведение — рекурсивная
  функция с множеством пройденных элементов; объявления берутся
  из `RuleContext.allUnits`. Каскад: `node.isCascaded`, цель —
  `CascadeExpression.target`; значение выброшено, если родитель каскада без
  скобок — `ExpressionStatement` или `ExpressionFunctionBody` функции с типом
  возврата `void`. Для объявления — тип возврата её элемента, для литерала —
  тип возврата параметра, которому он передан, или объявленного типа
  переменной, которую он инициализирует; иначе — его статический тип.

- [ ] **Шаг 4: прогон пакета** — зелёный.

- [ ] **Шаг 5: коммит** `feat(solo_lints): report ignoreFailure() on a job that
  names its expected errors`.

### Задача 6: сторож страницы ошибок

**Files:**

- Create: `packages/solo_lints/test/mistakes_page_test.dart`.
- Modify: `packages/solo_lints/.pubignore` — строка
  `test/mistakes_page_test.dart` с комментарием по-английски.

**Interfaces:**

- Consumes: все семь правил пакета; `rule_base.dart` — источники пакетов
  (`_sources` становится видимым тесту, если нужно).

Сторож — наследник `PubPackageResolutionTest` (экспортирует
`package:analyzer_testing/analysis_rule/analysis_rule.dart`),
а не `AnalysisRuleTest`: в `setUp` он регистрирует все семь правил
в `Registry.ruleRegistry` и пишет `analysisOptionsContent(rules: [...])`
со всеми именами, как `AnalysisRuleTest.setUp` для одного. Источники пакетов —
как в `RuleTest.setUp`, до `super.setUp()`.

- [ ] **Шаг 1: тест.** Читает `../solo/doc/mistakes.md` из каталога пакета.
  Пара — «Don't do this:», ближайший за ним блок ```dart, затем «Do this:»
  и его блок, по порядку в разделе `## `. Таблица — дословно из дизайна, ключ —
  `(раздел, номер пары)`. Для каждой пары и блока — свой тест с именем раздела
  и пары. Проверки:
  - фрагмент в обвязке раздела разрешается без ошибок компиляции; ошибка —
    отдельное падение с текстом ошибки;
  - Don't: диагнозы ровно одного правила пакета — правила пары, хотя бы один;
    у пары «без правила» — ни одного;
  - Do: ни одного диагноза правил пакета;
  - пара, которой нет в таблице, и строка таблицы без пары на странице —
    падение с именем раздела;
  - у раздела число «Don't do this» не равно числу «Do this» — падение с именем
    раздела (фокус ревью 5).

  Обвязки — по разделам, на выбор исполнителя. Обязательное: «Answering for
  every failure» — `profile.load()` без `isExpectedError`; «Moving the clock in
  fakeAsync» — заглушки `test`, `expect`, `isA` в самой обвязке, потому что
  `package:test` в источниках теста нет.

- [ ] **Шаг 2: прогон** `dart test test/mistakes_page_test.dart` — зелёный
  на нынешней странице. Проверка, что сторож ловит, — две мутации по одной:
  на странице стереть `ctx.check();` в «Do this» раздела «Letting cancellation
  through a catch»; в таблице сторожа поменять правило строки на чужое.
  Каждая — красный прогон с именем раздела в тексте. До мутации файл копируется
  вне репозитория, откат — этой копией, не `git checkout`; после отката
  `git diff` по обоим файлам пуст.

- [ ] **Шаг 3: архив.** `.pubignore` исключает сторожа. Из корня:
  `python3 tool/archive_floor.py stage <каталог вне репозитория>` — в раскладке
  `solo_lints` нет `test/mistakes_page_test.dart`.

- [ ] **Шаг 4: прогон пакета** — зелёный.

- [ ] **Шаг 5: коммит**
  `test(solo_lints): guard the mistakes page with the rules`.

### Задача 7: документы

**Files:**

- Modify: `packages/solo_lints/README.md`, `packages/solo_lints/README.ru.md`.
- Modify: `packages/solo_lints/CHANGELOG.md`,
  `docs/ru/solo_lints/CHANGELOG.md`.
- Modify: `packages/solo_lints/pubspec.yaml` — `description`.
- Create: `docs/records/2026-10/2026-10-28-solo-lints-wave-2-report.md`.
- Modify: шапки `2026-10-28-solo-lints-wave-2-design.md`,
  `2026-10-28-solo-lints-design.md`, `2026-10-28-solo-lints-report.md`, этого
  плана; `docs/handoff.md`.

- [ ] **Шаг 1: README.** Вступление: «Each rule stands for a section of Common
  mistakes» уже неверно — у `ignore_failure_hides_bugs` раздела нет; переписать
  без этого обещания. «Install»: линтов три, пример `diagnostics:` называет все
  три. Таблица «Rules» — две строки, `lint`. Разделы `### key_per_request`
  и `### ignore_failure_hides_bugs` — по образцу соседних: фрагмент
  с диагнозом, что идёт не так, как правильно. Исправления — в разделах трёх
  правил одной фразой: какой код получится. Фрагменты README, которые даёт
  правило, сверить с тестами правил глазами.

- [ ] **Шаг 2: перевод `README.ru.md`** тем же содержанием; линтер
  `humanizer--ru` по правленым абзацам, только `ERROR`.

- [ ] **Шаг 3: CHANGELOG.** В тот же `## 0.1.0` — два пункта линтов в формате
  соседних и пункт об исправлениях трёх правил. Перевод —
  `docs/ru/solo_lints/CHANGELOG.md`, линтер.

- [ ] **Шаг 4: `pubspec.yaml`.** `description` называет и новые правила, 60–180
  символов: длиннее pub предупреждает, а предупреждение dry-run роняет `floor`.

- [ ] **Шаг 5: отчёт** `2026-10-28-solo-lints-wave-2-report.md` с шапкой: что
  сделано по задачам, итог зонда задачи 1 и где он разошёлся с дизайном,
  расхождения с дизайном и планом, числа тестов пакета. Шапки дизайна и записей
  первой волны — «вторая волна сделана», с коммитами; handoff — текущее
  состояние.

- [ ] **Шаг 6: проверки.** Из корня: `python3 tool/reflow.py --check`,
  `python3 tool/check_line_width.py`, `python3 tool/check_translations.py`,
  `python3 tool/check_links.py`; ширина новой записи — своим счётом.
  Из корня же — пол: `python3 tool/archive_floor.py stage <каталог>`
  и `PATH=~/fvm/versions/3.38.1/bin:$PATH python3 tool/archive_floor.py run
  <каталог>` — зелёные для `solo_lints`.

- [ ] **Шаг 7: коммит** `docs(solo_lints): describe the second wave`.

## Что не трогается

- `packages/async_job`, `packages/solo`, `packages/flutter_solo` — ни строки;
  `packages/solo/doc/mistakes.md` — тоже.
- `.github/workflows/gate.yml`: `solo_lints` уже в заданиях `dart` и `floor`.
- Правила первой волны — только переезд хелперов в `context.dart` без изменения
  поведения.
