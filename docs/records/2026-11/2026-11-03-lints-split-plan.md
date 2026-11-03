# Два пакета линтов: `async_job_lints` и `solo_lints` — план

> **Состояние на 2026-11-03:** план по одобренному дизайну, пересмотрен
> по независимому ревью Opus: одна находка Critical, четыре Important и шесть
> Minor, все приняты, главная перепроверена своим зондом на обоих SDK (раздел
> «Ревью плана»). Исполнен самим агентом по слову владельца «сам, исполняй»,
> прошёл независимое ревью Opus всей ветки и влит в `main` коммитами
> `82a3ebb4`…`aef32b50`; отчёт — `2026-11-03-lints-split-report.md`.
> Публикации — отдельные связки, раздел «После плана — выпуски».
> **Что это:** задачи, по которым пять правил ядра уходят из `solo_lints`
> в новый пакет `async_job_lints`, а `solo_lints` регистрирует их поверх себя.
> **Связанные записи:** `2026-11-03-lints-split-design.md`,
> `2026-10-28-solo-lints-design.md`, `2026-10-29-bare-await-design.md`.

> **Для исполнителя-агента:** обязательный скилл —
> superpowers:subagent-driven-development (рекомендуется) или
> superpowers:executing-plans. Шаги отмечаются чекбоксами (`- [ ]`).

**Цель:** правила ядра живут в своём плагине `async_job_lints`, а пользователь
`solo_lints` после обновления не замечает ничего.

**Устройство:** пять правил, два исправления и `context.dart` переезжают
`git mv` в `packages/async_job_lints`. Наружу пакет отдаёт одну библиотеку для
плагинов поверх: функцию регистрации и четырнадцать распознавателей.
`solo_lints` зависит от `async_job_lints`, регистрирует правила ядра этой
функцией и свои три правила.

**Стек:** Dart 3.10+, `analysis_server_plugin` 0.3, `analyzer` 12–14,
`analyzer_testing`, Python 3 для инструментов.

**Дизайн:** `2026-11-03-lints-split-design.md`. План спорит от него; где они
расходятся, прав дизайн, кроме отступлений, перечисленных ниже с причиной.

## Общие ограничения

- `environment: sdk: ^3.10.0`; пол — Flutter 3.38.1 с Dart 3.10.0
  (`~/fvm/versions/3.38.1`).
- Зависимости `async_job_lints` — как у `solo_lints` сейчас:
  `analysis_server_plugin: ^0.3.14`, `analyzer: '>=12.1.0 <15.0.0'`,
  `analyzer_plugin: '>=0.14.8 <0.15.0'`; `dev_dependencies` те же, что
  у `solo_lints`, включая `async_job: ^1.0.0` и `solo: ^1.0.0`.
- `async_job_lints` — версия 0.1.0, имя плагина `async_job_lints`. `solo_lints`
  остаётся 0.1.4 в `pubspec.yaml` до выпуска; выпуск — 0.1.5, ограничение
  `async_job_lints: ^0.1.0`.
- Имена правил, их вид (warning или lint) и исправления — по таблице «Что
  выяснено» дизайна, ни одно не переименовывается.
- Коды диагностик — `static const LintCode` в классе правила, по коду
  на правило или на вид диагностики (`BareAwait.code`, `BareAwait.loopCode`).
- Комментарии и dartdoc — по-английски; записи — по-русски, ширина 79,
  `python3 tool/reflow.py`; перевод — тем же коммитом, что оригинал, русские
  переводы через скилл `humanizer--ru` (только `ERROR`).
- Перед каждым коммитом в каждом затронутом пакете: `dart format`,
  `dart analyze --fatal-infos`, `dart test`.
- После каждой задачи — `docs/handoff.md` тем же коммитом.
- Публикации и push в плане нет. Коммиты — Conventional Commits по-английски,
  в конце `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Задача 7 — тексты, которые ведут читателя на `async_job_lints`. Её коммиты
  не уходят в `origin` раньше публикации `async_job_lints`; всё до неё может
  уйти раньше (раздел «Push и окно»).

## Что ревьюеру проверить особо

Пять случаев, которые тесты задач трогают меньше всего и которые больнее всего
ударят по пользователю:

- Пользователь `solo_lints` обновился: все восемь правил приходят,
  `// ignore: solo_lints/catch_without_check` глушит, линты включаются его
  `diagnostics:`. Держит зонд задачи 3 на обоих SDK и шаг гейта.
- Пользователь `solo`, назвавший один `async_job_lints`: ожидание собственной
  очереди сообщает `bare_await`, а `ctx.emit` в теле задачи `solo` правила ядра
  считают точкой проверки, как сейчас. Держат перенесённые тесты правил
  и фикстура зонда.
- Названы оба плагина в любом порядке: ни одна пара «правило, строка»
  не приходит дважды на Dart 3.13. Держат `identical`-сторож задачи 1 и зонд
  задачи 3.
- Пол Dart 3.10.0: оба плагина загружаются и сообщают то же, что на свежем SDK.
  Держат зонд задачи 3 на полу и `floor` в задаче 5.
- Окно до публикации: ни README ядра, ни сайт, ни корневой README не называют
  `async_job_lints`, пока не вышла задача 7. Держит раздел «Push и окно»
  и проверка в задаче 6.

## Отступления от дизайна

- **Зонд дерева — после переноса кода, а не до.** Дизайн просит зонд «настоящих
  пакетов из дерева» «до переноса кода», но до переноса пакета
  `async_job_lints` нет. Зонд идёт задачей 3, сразу за переносом и до любых
  текстов: если он покажет беду, переделывать придётся только код.
- **Плагин из дерева в зонде — копия `solo_lints` с путевой зависимостью.**
  Сервер анализа собирает свой пакет из названных плагинов, и оверрайды плагина
  в нём не действуют, а `async_job_lints` 0.1.0 до публикации нет на pub.dev.
  Зонд кладёт копию `solo_lints`, где `async_job_lints` взят путём на дерево, —
  так же, как `tool/archive_floor.py` раскладывает оверрайды. Разрешение
  по версии проверит только публикация.
- **Шаг гейта с плагином из дерева — да.** Дизайн оставил его плану. Сторож
  регистрации ловит забытый вызов на уровне кода, но не то, что сервер анализа
  на самом деле загрузит и покажет. Шаг идёт под `timeout`: четыре набора
  с холодной сборкой плагинов на CI занимают минуты, а зависший сервер
  не должен держать задание.
- **Решения 129 и 144 и «Ставка — ядро» `AGENTS.md` — в задаче 7,
  а не в «Правилах для агентов».** Они говорят о теме сайта, а тема меняется
  только в задаче 7; правка раньше записала бы в правила то, чего на сайте ещё
  нет.

## Карта файлов

Создаются, `packages/async_job_lints/`:

- `pubspec.yaml`, `analysis_options.yaml` (копия у `solo_lints`), `LICENSE`
  (копия), `.pubignore`, `README.md`, `README.ru.md`, `CHANGELOG.md`,
  `example/example.md`;
- `lib/main.dart` — `final plugin = AsyncJobLintsPlugin();`;
- `lib/async_job_lints.dart` — `AsyncJobLintsPlugin`;
- `lib/plugin_api.dart` — функция регистрации и распознаватели;
- `test/support/recording_registry.dart`, `test/plugin_test.dart`,
  `test/example_page_test.dart`, `test/readme_version_test.dart`.

Переезжают `git mv` из `packages/solo_lints/` в `packages/async_job_lints/`:

- `lib/src/context.dart`;
- `lib/src/rules/` — `ctx_in_cleanup.dart`, `release_on_the_call.dart`,
  `catch_without_check.dart`, `sync_fake_async.dart`, `bare_await.dart`;
- `lib/src/fixes/` — `add_check.dart`, `release_on_the_call.dart`;
- `test/` — тесты этих пяти правил и двух исправлений:
  `ctx_in_cleanup_test.dart`, `release_on_the_call_test.dart`,
  `catch_without_check_test.dart`, `sync_fake_async_test.dart`,
  `bare_await_test.dart`, `add_check_fix_test.dart`,
  `release_on_the_call_fix_test.dart`;
- `test/support/rule_base.dart` и `test/support/fix_base.dart` — `git mv`,
  потом копия обратно в `solo_lints`: тестовая поддержка нужна обоим, история
  идёт за ядром.

Меняются в `packages/solo_lints/`: `pubspec.yaml`, новый
`pubspec_overrides.yaml`, `lib/solo_lints.dart`, три правила
и `lib/src/fixes/key_per_request.dart` (импорт), `test/example_page_test.dart`,
`test/mistakes_page_test.dart`, новые `test/support/recording_registry.dart`
и `test/plugin_test.dart`; в задаче 7 — `README.md`, `README.ru.md`,
`CHANGELOG.md`.

Инструменты: новый `tool/plugin_probe.py` с фикстурой
`tool/plugin_probe/fixture.dart`; `tool/archive_floor.py`,
`tool/check_dartdoc.py`, `tool/check_translations.py`,
`.github/workflows/gate.yml`; в задаче 7 — `tool/build_site.py`,
`site/astro.config.mjs`, `site/README.md`, `site/content/index.md`,
`site/content/ru/index.md`.

## Задача 1. Раздел кода: `async_job_lints` и `solo_lints` поверх него

Одна задача на оба пакета: между переносом и правкой `solo_lints` дерево
не собирается, и коммит у задачи один.

**Файлы:** перенос по «Карте файлов»; создаются `pubspec.yaml`,
`analysis_options.yaml`, `LICENSE`, `.pubignore`, `lib/main.dart`,
`lib/async_job_lints.dart`, `lib/plugin_api.dart`,
`test/support/recording_registry.dart`, `test/plugin_test.dart`
в `async_job_lints`; в `solo_lints` — всё из «Карты файлов», кроме текстов.

**Интерфейсы, которые задача производит:**

```dart
// package:async_job_lints/plugin_api.dart
void registerAsyncJobLints(
  PluginRegistry registry, {
  bool ownQueueReportedElsewhere = false,
});
export 'src/context.dart'
    show
        cleanupContext, firstPositional, functionOf, isDartCoreClass,
        isFromJobPackages, isJobContext, isSolo, isSoloContext, isSoloMember,
        jobContextOf, namedValue, ownQueueCall, returnedValues,
        waitingContext;

// package:async_job_lints/async_job_lints.dart
class AsyncJobLintsPlugin extends Plugin; // name => 'async_job_lints'

// lib/src/rules/bare_await.dart
BareAwait({this.ownQueueReportedElsewhere = false});
final bool ownQueueReportedElsewhere;

// test/support/recording_registry.dart, в обоих пакетах
final class RecordingRegistry implements PluginRegistry {
  final List<AbstractAnalysisRule> warnings;
  final List<AbstractAnalysisRule> lints;
  final Set<String> fixedRules; // имена правил, у кодов которых есть fix
  AbstractAnalysisRule rule(String name); // из warnings и lints
}
```

`registerAsyncJobLints` регистрирует правила и исправления в том же порядке
и того же вида, что `SoloLintsPlugin.register` сейчас: warning —
`ctx_in_cleanup`, `release_on_the_call`, `sync_fake_async`; lint —
`catch_without_check`, `bare_await`; исправления — `PassReleaseToCall`
к `ReleaseOnTheCall.code`, `AddCheck` к `CatchWithoutCheck.code`. Параметр
передаётся в `BareAwait`; правило с ним молчит на ожидании, которое нашёл
`ownQueueCall`, без него — сообщает его кодом `BareAwait.code`.

`RecordingRegistry` переопределяет `registerWarningRule`, `registerLintRule`
и `registerFixForRule(DiagnosticCode code, Function generator)` — параметр
шире, чем `ProducerGenerator`, который пакет не экспортирует; остальное —
`noSuchMethod`, бросающий `UnsupportedError`. Импорта `src/` чужого пакета
в нём нет.

Решения внутри задачи:

- dartdoc `plugin_api.dart` говорит, что библиотека — API для плагинов поверх
  `async_job_lints`, а не для пользователя, и что она под обещанием semver;
- у четырнадцати распознавателей dartdoc уже есть; если `dart doc` найдёт
  недокументированный, его документируют в `context.dart`;
- три правила `solo_lints` и `PutArgumentsIntoKey` импортируют
  `package:async_job_lints/plugin_api.dart` вместо `../context.dart`; если
  анализ требует имени, которого нет в списке, — это находка против дизайна:
  имя добавляется в `show` и записывается отступлением в отчёт;
- `.pubignore` у `async_job_lints` исключает `README.ru.md`, как
  у `solo_lints`;
- `packages/solo_lints/pubspec_overrides.yaml`: первая строка — комментарий
  «Lives until async_job_lints 0.1.0 is on pub.dev.», затем
  `dependency_overrides: async_job_lints: path: ../async_job_lints`.

Шаги:

- [ ] **1. Перенос.** `git mv` всего, что перечислено в «Карте файлов», и копия
  `rule_base.dart` и `fix_base.dart` обратно
  в `packages/solo_lints/test/support/`. Импорты `package:solo_lints/src/…`
  в перенесённых тестах — на `package:async_job_lints/src/…`.
- [ ] **2. Каркас пакета** — `pubspec.yaml` (описание, `repository`,
  `documentation: https://docs.yet-another.dev/async_job_lints/`,
  `issue_tracker`, `topics` как у `solo_lints`), `analysis_options.yaml`,
  `LICENSE`, `.pubignore`, `lib/main.dart`, `lib/async_job_lints.dart`,
  `lib/plugin_api.dart` с пустым телом `registerAsyncJobLints`; поле
  `BareAwait.ownQueueReportedElsewhere` и параметр конструктора — пока без
  действия, чтобы тесты шагов 3 и 4 компилировались; `dart pub get`.
- [ ] **3. Красный сторож регистрации.** `test/plugin_test.dart`
  в `async_job_lints`:

  ```dart
  test('the five rules of the core are registered, each with its kind', () {
    final registry = RecordingRegistry();
    registerAsyncJobLints(registry);
    expect(registry.warnings.map((r) => r.name), unorderedEquals([
      'ctx_in_cleanup', 'release_on_the_call', 'sync_fake_async']));
    expect(registry.lints.map((r) => r.name),
        unorderedEquals(['catch_without_check', 'bare_await']));
    expect(registry.fixedRules,
        {'release_on_the_call', 'catch_without_check'});
  });
  test('the plugin registers through registerAsyncJobLints', ...);
      // AsyncJobLintsPlugin().name == 'async_job_lints', тот же состав
  test('two registrations share each diagnostic code', ...);
      // для каждого имени: коды первой и второй регистрации попарно identical
  test('the parameter reaches bare_await', ...);
      // (rule('bare_await') as BareAwait).ownQueueReportedElsewhere —
      // false без параметра, true с ним
  ```

  Ожидается: компилируется и падает на пустых списках.
- [ ] **4. Красный тест собственной очереди.** В `bare_await_test.dart`
  `test_own_queue` ждёт `['[[await]] close()']`; новый класс
  `BareAwaitOwnQueueReportedElsewhereTest`
  с `BareAwait(ownQueueReportedElsewhere: true)` и тем же кодом ждёт `[]`.
  Ожидается: первый падает — правило молчит; второй зелёный.
- [ ] **5. Зелёный.** Тело `registerAsyncJobLints`, `AsyncJobLintsPlugin`, поле
  `BareAwait`. `dart test` в `async_job_lints` — всё зелёное.
- [ ] **6. `solo_lints` поверх.** Зависимость и оверрайд, импорты трёх правил
  и исправления, `SoloLintsPlugin.register`:
  `registerAsyncJobLints(registry, ownQueueReportedElsewhere: true)`, затем
  `AwaitOwnQueue` (warning), `KeyPerRequest` (lint) с `PutArgumentsIntoKey`,
  `IgnoreFailureHidesBugs` (lint).
- [ ] **7. Сторож регистрации `solo_lints`.** `test/plugin_test.dart`:

  ```dart
  test('the plugin registers the eight rules, each with its kind', ...);
      // warnings: ctx_in_cleanup, release_on_the_call, sync_fake_async,
      //           await_own_queue
      // lints:    catch_without_check, key_per_request,
      //           ignore_failure_hides_bugs, bare_await
      // fixedRules: release_on_the_call, catch_without_check, key_per_request
      // name == 'solo_lints'
  ```

  и `RuleTest`, у которого `underTest` — `rule('bare_await')`
  из `SoloLintsPlugin().register(...)`, с `test_own_queue` из шага 4, ожидание
  `[]`. Проверка, что сторож краснеет: убрать вызов `registerAsyncJobLints` —
  первый тест падает; убрать параметр — падает второй. Вернуть.
- [ ] **8. Сторожа страниц.** `example_page_test.dart`
  и `mistakes_page_test.dart` берут правила из `RecordingRegistry` после
  `SoloLintsPlugin().register(...)`, а не из `src/`. Пример заводит свежий
  реестр на каждый прогон правила, как сейчас `rule()`; страница ошибок
  регистрирует в `Registry.ruleRegistry` предупреждения и линты по спискам
  реестра. Импортов `package:solo_lints/src/rules/` в них не остаётся.
- [ ] **9. Проверки.** В обоих пакетах `dart format lib test`,
  `dart analyze --fatal-infos`, `dart test`. Ожидается: чисто, все тесты
  зелёные; ни один тест `solo_lints` до задачи не пропал — каждый либо остался,
  либо переехал.
- [ ] **10. Коммит**
  `refactor: move the rules of the core into async_job_lints`, вместе
  с `docs/handoff.md`.

## Задача 2. Фикстура зонда и `tool/plugin_probe.py`

**Файлы:** `tool/plugin_probe.py`, `tool/plugin_probe/fixture.dart`.

**Интерфейсы:** потребляет пакеты задачи 1; производит команду

```sh
python3 tool/plugin_probe.py [--fixes] [--keep]
```

Скрипт:

- создаёт свой каталог в `tempfile.mkdtemp()` и удаляет только его;
- кладёт туда копию `lib/` и `pubspec.yaml` пакета `packages/solo_lints`, где
  вместо `async_job_lints: ^…` стоит `path:` на дерево; без
  `pubspec_overrides.yaml`, `.dart_tool/` и `pubspec.lock`. Путь
  к `async_job_lints` в копии и в `analysis_options.yaml` пакета-пользователя —
  один и тот же абсолютный путь;
- создаёт пакет-пользователь с зависимостями `async_job: ^1.0.0`,
  `solo: ^1.0.0`, `fake_async` и копией фикстуры в `lib/`, `dart pub get`;
- для каждого набора из таблицы ниже пишет `analysis_options.yaml` с плагинами
  путём и `diagnostics:` на линты каждого: у `async_job_lints` —
  `catch_without_check` и `bare_await`, у `solo_lints` — ещё `key_per_request`
  и `ignore_failure_hides_bugs`; гоняет `dart analyze --format=machine`
  и сверяет с метками фикстуры только диагностики восьми правил, прочие
  отбрасывает;
- ненулевой код выхода `dart analyze` при диагностиках — не ошибка зонда;
- печатает по строке на набор и выходит с ненулевым кодом на первом
  расхождении, напечатав ожидаемое и полученное.

Имени плагина в выводе нет ни в одном формате: строка машинного вывода —
`WARNING|STATIC_WARNING|CTX_IN_CLEANUP|<файл>|<строка>|…`. Хозяина правила ядра
зонд узнаёт только по строкам под `// ignore:`.

Фикстура: каждая строка, которую правило должно сообщить, кончается
комментарием `// rule_name`; восемь правил, по строке на каждое, ожидание
собственной очереди помечено `// await_own_queue`. Ещё в ней:

- две строки с `catch_without_check`: одна под
  `// ignore: solo_lints/catch_without_check` с меткой
  `// catch_without_check unless solo_lints`, другая под
  `// ignore: async_job_lints/catch_without_check` с меткой
  `// catch_without_check unless async_job_lints`. Строку глушит `ignore`,
  только когда хозяин правила — плагин из метки. Хозяин правила ядра — плагин,
  который назван один, а у двух — названный первым, на обоих SDK;
- тело задачи `solo`, где `ctx.emit` стоит в уборке, с меткой
  `// ctx_in_cleanup`: правило ядра знает точки проверки `solo`;
- тело задачи `solo`, где `ctx.emit` стоит проверкой после `catch`, — без
  метки: `catch_without_check` здесь молчит.

Строка собственной очереди не выражается меткой: её ожидание зависит от набора
и зашито в скрипт по таблице. У двух плагинов работают не только правила
хозяина. На Dart 3.13 работают экземпляры обоих плагинов, и их диагностики
с одним кодом склеиваются в одну; на Dart 3.10 работает экземпляр плагина,
названного последним. Поэтому `bare_await` на строке собственной очереди
в наборах «оба» зависит от SDK и порядка, и зонд его там не сверяет.

| Названы | Ожидается |
| --- | --- |
| `async_job_lints` | метки пяти правил ядра; молчит строка под `ignore: async_job_lints/…`; строку собственной очереди сообщает `bare_await`; правил `solo` нет |
| `solo_lints` | все восемь меток; молчит строка под `ignore: solo_lints/…`; строку собственной очереди сообщает только `await_own_queue` |
| `async_job_lints`, `solo_lints` | все метки; пары «правило, строка» без дублей; молчит строка под `ignore: async_job_lints/…`; `bare_await` на строке собственной очереди не сверяется |
| `solo_lints`, `async_job_lints` | то же, но молчит строка под `ignore: solo_lints/…` |

`--fixes` — только для зонда, в гейт не идёт. Для каждого набора скрипт:

- поднимает `dart language-server --protocol=lsp` с корнем
  в пакете-пользователе, `initialize` с `rootUri`
  и `capabilities.textDocument.codeAction.codeActionLiteralSupport`, затем
  `initialized`;
- открывает фикстуру `textDocument/didOpen` и ждёт
  `textDocument/publishDiagnostics` для неё, где есть диагностики всех трёх
  правил с исправлениями — `release_on_the_call`, `catch_without_check`,
  `key_per_request` (у одного `async_job_lints` — только два первых);
  диагностики плагина приходят позже диагностик самого сервера, поэтому ждёт
  до них, не дольше 120 секунд;
- на каждую такую диагностику шлёт `textDocument/codeAction` с её `range`
  и с ней самой в `context.diagnostics`;
- считает действия, чей `title` совпадает с сообщением исправления из `FixKind`
  его класса;
- печатает «набор, правило: N»; ожидается по одному исправлению в одиночных
  наборах; число в наборах «оба» записывается, каким пришло;
- закрывает сервер `shutdown` и `exit`, а на таймауте убивает процесс
  и печатает, чего не дождался.

`--keep` оставляет каталог и печатает путь.

Шаги:

- [ ] **1. Фикстура** — собирается против опубликованных `async_job` и `solo`
  без ошибок компилятора (`dart analyze` без плагинов).
- [ ] **2. Скрипт** без `--fixes`. Прогон на свежем SDK. Ожидается: четыре
  строки «ok».
- [ ] **3. Скрипт краснеет.** Мутации по одной, каждая в копии дерева: убрать
  `registerAsyncJobLints` из `SoloLintsPlugin` — красный набор `solo_lints`;
  убрать параметр — красная строка `await_own_queue` у `solo_lints`; заменить
  код `CtxInCleanup` на создаваемый в конструкторе экземпляр — на Dart 3.13
  красный набор «оба». Вывод каждой мутации — в отчёт.
- [ ] **4. `--fixes`** на свежем SDK. Ожидается: в одиночных наборах по одному
  исправлению на диагностику, процесс сервера закрыт.
- [ ] **5. Коммит**
  `test: probe the plugins from the tree through the analysis server`.

## Задача 3. Зонд дерева на обоих SDK

**Интерфейсы:** потребляет `tool/plugin_probe.py`.

- [ ] **1.** `python3 tool/plugin_probe.py --fixes` на свежем SDK
  и `PATH=~/fvm/versions/3.38.1/bin:$PATH python3 tool/plugin_probe.py --fixes`
  на полу. Ожидается: четыре «ok» на каждом SDK.
- [ ] **2.** Записать в отчёт (задача 8) обе таблицы, включая число исправлений
  в наборах «оба». Два исправления на одну диагностику — не беда кода: README
  и так советует не называть оба; это записывается в решение 145 (задача 6)
  одной фразой.
- [ ] **3.** Красный набор на любом SDK — стоп: в отчёт, вопрос владельцу,
  дальше задачи не идут.

Коммита у задачи нет, если зонд не потребовал правки.

## Задача 4. `async_job_lints` для читателя

**Файлы:** `packages/async_job_lints/README.md`, `README.ru.md`,
`CHANGELOG.md`, `docs/ru/async_job_lints/CHANGELOG.md`, `example/example.md`,
`test/example_page_test.dart`, `test/readme_version_test.dart`;
`tool/check_translations.py`.

Содержание:

- README: что это и для кого — для кода на `async_job`; пользователю `solo`
  и `flutter_solo` нужен `solo_lints`, где эти правила уже есть; оба плагина
  не называть, потому что версии обоих разрешаются вместе и несогласие роняет
  все плагины. Установка — блоки `yaml`, как у `solo_lints`: короткий
  в «Install» и длинный с `diagnostics:`, оба с версией `^0.1.0`. Таблица пяти
  правил и раздел на каждое, тексты — из README `solo_lints`. Ссылки —
  на страницы ядра; раздел, чья ошибка показана только
  в `packages/solo/doc/mistakes.md`, обходится своим примером. Раздел
  `bare_await` говорит про ожидание собственной очереди контроллера `solo`
  и про `solo_lints`. Раздел «Versions» — о версиях `async_job`, которые знают
  правила, и о `analyzer`. Публичная библиотека `plugin_api.dart` — одной
  фразой: API для плагинов поверх, не для пользователя.
- `CHANGELOG.md`: `## 0.1.0` — первый выпуск, пять правил и два исправления
  перенесены из `solo_lints` 0.1.4 без перемен в поведении, кроме `bare_await`
  и собственной очереди.
- Пример: рекордер на `async_job` без `solo` с тремя ошибками —
  `release_on_the_call`, `ctx_in_cleanup`, `catch_without_check`, — блок `yaml`
  и исправленная версия вторым блоком `dart`, как в примере `solo_lints`.
- `example_page_test.dart` — по образцу сторожа `solo_lints`: блок `yaml`
  с `async_job_lints`, три метки, исправленная версия чистая; правила —
  из `RecordingRegistry` после `registerAsyncJobLints`; плюс
  `expect(page, isNot(contains('package:solo/')))`.
- `readme_version_test.dart` — как у `solo_lints`, регулярное выражение
  `^  async_job_lints:(?: |\n    version: )(\S+)$`, два блока.
- `tool/check_translations.py`: пары README и CHANGELOG `async_job_lints`
  в `PAIRS` и в списке докстринга.

Шаги:

- [ ] **1.** Сторожа примера и версии README — красные (файлов нет).
- [ ] **2.** README, CHANGELOG, пример; сторожа зелёные.
- [ ] **3.** Переводы; `humanizer--ru` на оба — без `ERROR`;
  `python3 tool/check_translations.py` чисто.
- [ ] **4.** `python3 tool/reflow.py --check`,
  `python3 tool/check_line_width.py`, `python3 tool/check_links.py` чисто.
- [ ] **5.** `python3 -m unittest tool/build_site_test.py` зелёный: пакета ещё
  нет в `PACKAGES` `tool/build_site.py`, и сайт его не видит.
- [ ] **6. Коммит**
  `docs: describe async_job_lints in its README, changelog and example`.

## Задача 5. Гейт и инструменты

**Файлы:** `.github/workflows/gate.yml`, `tool/archive_floor.py`,
`tool/check_dartdoc.py`.

- `gate.yml`, задание `dart`: `packages/async_job_lints` в циклах
  «Dependencies», «Analyze» и «Tests» перед `packages/solo_lints`; строки
  в «Formatting» (`lib test`) и «Dartdoc»; новый шаг «Plugins» после «Tests»:
  `timeout 900 python3 tool/plugin_probe.py`, с комментарием, что он ловит,
  чего не ловит сторож регистрации.
- `archive_floor.py`: `PACKAGES = ('async_job', 'solo', 'async_job_lints',
  'solo_lints', 'flutter_solo')`.
- `check_dartdoc.py`: `async_job_lints` в `PACKAGES`.

Шаги:

- [ ] **1.** `python3 tool/check_dartdoc.py` — чисто, пакет в выводе.
- [ ] **2.** `floor` локально: `python3 tool/archive_floor.py stage <каталог>`
  и `PATH=~/fvm/versions/3.38.1/bin:$PATH python3 tool/archive_floor.py run
  <каталог>`. Ожидается: dry-run без предупреждений у пяти пакетов, оба прохода
  зелёные у `async_job_lints` и `solo_lints`.
- [ ] **3.** Шаги задания `dart` руками, по `gate.yml`, из корня копии.
  Ожидается: всё зелёное, включая «Plugins».
- [ ] **4. Коммит** `build: gate async_job_lints and probe the plugins`.

## Задача 6. Правила для агентов

**Файлы:** `AGENTS.md`, `docs/architecture.md`, `docs/conventions.md`,
`docs/settled.md`, `docs/handoff.md`.

- `AGENTS.md`:
  - «Публикация на pub.dev» — `async_job_lints` выходит после того выпуска
    `async_job` и `solo`, под имена которых подогнаны правила; `solo_lints` —
    после `async_job_lints`; минор `async_job_lints` 0.x требует выпуска
    `solo_lints` с новым ограничением, патч доходит до пользователя
    `solo_lints` сам;
  - «Оверрайды разработки» — `packages/solo_lints/pubspec_overrides.yaml`
    держит `async_job_lints`;
  - «Проверки» — `async_job_lints` в задании `dart`, шаг «Plugins»; пол
    поднимают в `pubspec.yaml` всех пяти; один SDK «на все пять пакетов».
- `docs/architecture.md` — строка `packages/async_job_lints` и новая строка
  `packages/solo_lints` (правила `solo` и правила ядра через
  `registerAsyncJobLints`).
- `docs/conventions.md` — список пакетов с `dart test` и абзац о semver
  плагинов (оба 0.x). Абзац о README, называющих плагин, — в задаче 7.
- `docs/settled.md`:
  - **145** — два пакета линтов: почему не переименование (слово владельца
    2026-11-03), какой плагин назвать и почему не оба, `bare_await` без
    параметра сообщает ожидание собственной очереди; у двух названных плагинов
    работают экземпляры правил не только хозяина, и `bare_await` на ожидании
    собственной очереди зависит от SDK и порядка — ещё одна причина не называть
    оба; итог зонда задачи 3 об исправлениях;
  - **131** — запрет с `async_job_lints` снят словом владельца 2026-11-03;
  - раздел `## solo_lints` — заголовок `## async_job_lints и solo_lints`,
    вводный абзац: решения 116–127 о правилах ядра относятся
    к `async_job_lints`; в 119 у пользователя ядра
    `// ignore_for_file: async_job_lints/bare_await`.

Шаги:

- [ ] **1.** Правки; `reflow --check`, `check_line_width.py` чисто.
- [ ] **2.** Окно: `git grep -n async_job_lints -- packages/async_job
  packages/solo packages/flutter_solo site README.md docs/ru/async_job
  docs/ru/solo docs/ru/flutter_solo docs/ru/solo_lints` — пусто;
  в `packages/solo_lints` — только код, тесты, `pubspec*.yaml`.
- [ ] **3. Коммит** `docs: record the split of the lints for agents`.

## Задача 7. Тексты, которые ведут на `async_job_lints`

Коммиты этой задачи уходят в `origin` только вместе с публикацией
`async_job_lints` 0.1.0 или после неё.

**Файлы и что в них:**

- `packages/solo_lints/README.md` и `README.ru.md`: в начале — пакет для
  пользователя `solo` и `flutter_solo`, включает правила `async_job_lints`,
  нужен только он, оба не называть (та же причина); таблица восьми правил,
  строки правил ядра ведут на разделы README `async_job_lints`; разделы правил
  ядра уходят; «Versions» — о версиях `solo` и одна фраза: правила ядра и их
  изменения — в `CHANGELOG.md` `async_job_lints`.
- `packages/solo_lints/pubspec.yaml` `description`, dartdoc
  `lib/solo_lints.dart`: пакет для `solo`, включает правила `async_job_lints`.
- `packages/solo_lints/CHANGELOG.md` и перевод, «Unreleased»: правила ядра
  приходят из `async_job_lints`, имена и `ignore` те же; та же фраза о списке
  изменений ядра.
- `packages/async_job/README.md` и `README.ru.md`, «Install»:
  `async_job_lints: ^0.1.0` и ссылка на его «Install»; фраза: пользователю
  `solo` нужен `solo_lints`. `doc/cleanup-rules.md:268` и перевод: «the
  `bare_await` rule of `async_job_lints`». `test/readme_recipe_test.dart:1509`:
  `^plugins:\n  async_job_lints: \^\d+\.\d+\.\d+$`. `CHANGELOG.md` и перевод,
  «Unreleased»: README называет `async_job_lints`.
- `docs/conventions.md`: абзац о README, называющих плагин в «Install».
- Корневой `README.md`: строка `packages/async_job_lints`, новое описание
  `packages/solo_lints`.
- Сайт: `tool/build_site.py` — `'async_job_lints': 'async_job_lints'`
  в `PACKAGES`; `site/astro.config.mjs` — тема `async_job` из двух групп,
  `async_job` (нынешние страницы) и `async_job_lints` (обзор и список
  изменений), комментарий над `topics` и абзац `details` о `llms.txt`;
  `site/content/index.md` и `site/content/ru/index.md` — строка таблицы и абзац
  «… is not a dependency»; `site/README.md` — описание тем.
- `AGENTS.md`, «Ставка — ядро»: `async_job_lints` — в теме ядра.
  `docs/settled.md`, решения 129 и 144: то же, место `solo_lints` уже
  не вопрос.

Шаги:

- [ ] **1.** Сторож `readme_recipe_test.dart` с новым выражением — красный.
- [ ] **2.** README ядра и переводы; сторож зелёный, `dart test`
  в `packages/async_job`.
- [ ] **3.** README `solo_lints`, описание, dartdoc, списки изменений, корневой
  README; `dart test` в `solo_lints` (сторож версии README) зелёный.
- [ ] **4.** Сайт; `python3 -m unittest tool/build_site_test.py` зелёный —
  `TheSidebarTopics` видит новые страницы.
- [ ] **5.** Переводы через `humanizer--ru`; `check_translations.py`,
  `reflow --check`, `check_line_width.py`, `check_links.py` чисто.
- [ ] **6. Коммит** `docs: point the core and the site at async_job_lints`.

## Задача 8. Отчёт, ревью и вливание

- [ ] **1.** `docs/records/2026-11/2026-11-0X-lints-split-report.md`: что
  сделано, итог зонда на обоих SDK с выводом мутаций, отступления. Шапка
  дизайна и плана — «сделано».
- [ ] **2.** Независимое ревью всей ветки на Opus в отдельной копии (агент
  `reviewer`, первой командой `git merge --ff-only <ветка>`). Находки
  с вердиктами — в отчёт; принятые — правкой с тестом.
- [ ] **3.** `docs/handoff.md`: что в `main`, какие коммиты ждут публикации
  (раздел «Push и окно»), шаги выпуска.
- [ ] **4.** Вливание в `main` `--ff-only` по правилу «Слияние из worktree».

## Push и окно

Сайт выкладывается на push в `main`, который трогает README пакетов, `docs/ru/`
или `site/`. Коммиты задач 1–6 читателя на `async_job_lints` не ведут: README
нового пакета есть, но на сайте его нет, пока он не в `PACKAGES`.

Задание `floor` на коммитах задач 1–4 заведомо красное: оверрайд `solo_lints`
ведёт на раскладку `async_job_lints`, а в `PACKAGES` `tool/archive_floor.py`
пакет попадает только в задаче 5, когда у него есть README и CHANGELOG
и dry-run проходит без предупреждений. Поэтому граница префикса — не раньше
последнего коммита задачи 5. Владелец может отправить коммиты задач 1–6, когда
захочет: `git push origin <последний коммит задачи 6>:main`. Коммиты задачи 7
и отчёт за ней уходят вместе со связкой публикации `async_job_lints`.

## После плана — выпуски

Это не задачи плана: публикация — отдельная связка по отдельному слову
владельца. Порядок, чтобы handoff его держал:

1. `async_job_lints` 0.1.0 — связка, затем перенос пакета к издателю
   `yet-another.dev`.
2. `solo_lints` 0.1.5 — снять `pubspec_overrides.yaml` (удаление в индекс),
   связка.
3. Патч `async_job`, README которого называет `async_job_lints`.
4. Зонд по версии: пакет-пользователь называет `solo_lints: ^0.1.5`
   и `async_job_lints: ^0.1.0` по `version:` — каждый один и оба; итог —
   в отчёт.

## Ревью плана

Независимое ревью Opus 2026-11-03 по коммиту плана `fb82dcb7`, в отдельной
копии дерева. Ревьюер проверил зондами `RecordingRegistry`, dry-run
с оверрайдом на неопубликованный пакет, коды `static const` у двух плагинов,
хозяина `// ignore:` и машинный вывод; четырнадцать имён и порядок коммитов —
чтением. Пересказ находок; главную я перепроверил своим зондом.

**C1. Ожидания таблицы зонда для наборов «оба» на строке собственной очереди
расходятся с тем, как сервер запускает правила.** План считал, что у двух
плагинов работает экземпляр правила первого названного. Зонд ревьюера: на Dart
3.13 работают экземпляры обоих плагинов, коды склеиваются в одну диагностику,
и экземпляр нижнего без параметра сообщает строку в обоих порядках; на 3.10
работает экземпляр, зарегистрированный последним. Хозяин `// ignore:` — первый
названный на обоих SDK, дублей нет. Задача 3 остановилась бы без дефекта
в коде, шаг гейта «Plugins» краснел бы всегда.

Вердикт: принято, перепроверено своим зондом на обоих SDK: два игрушечных
плагина, верхний регистрирует правило нижнего с параметром «молчать
на `own()`». На 3.13.0 в порядке (верхний, нижний) строка `own()` сообщается,
на 3.10.0 в порядке (нижний, верхний) молчит, а в порядке (верхний, нижний)
сообщается; строка под `// ignore: top_lints/…` в порядке (верхний, нижний)
молчит на обоих. Сделано: в задаче 2 абзац о том, какие экземпляры работают,
таблица без сверки `bare_await` на строке собственной очереди в наборах «оба»
и ожидание этой строки, зашитое в скрипт; фраза в решение 145 (задача 6).

**I1. Имени плагина в выводе `dart analyze` нет ни в одном формате.** Ожидания
«под `async_job_lints/`» не проверить; хозяин виден только по строке под
`// ignore:`, а она одна, с `solo_lints/`. `dart analyze` с диагностиками
выходит с ненулевым кодом.

Вердикт: принято, проверено тем же зондом: машинная строка —
`WARNING|STATIC_WARNING|CORE_RULE|<файл>|4|3|11|core await`, обычный вывод —
`core await - core_rule`. Сделано: факт и код выхода в задаче 2, вторая строка
под `// ignore: async_job_lints/catch_without_check`, таблица говорит о хозяине
через строки под `ignore`.

**I2. `ctx.emit` в уборке правило ядра сообщает, а фикстура ждала тишины.**
`CtxInCleanup` включает `soloCheckpoints` в бросающие члены и сообщает
`readsState`.

Вердикт: принято, проверено по `ctx_in_cleanup.dart:30` и `:93`. Сделано:
`ctx.emit` в уборке — с меткой `// ctx_in_cleanup`, тихий случай — `ctx.emit`
проверкой после `catch`.

**I3. Задание `floor` красное на коммитах задач 1–4.** Оверрайд `solo_lints`
копируется в раскладку и ведёт на `async_job_lints`, которого в `PACKAGES`
`tool/archive_floor.py` до задачи 5 нет.

Вердикт: принято, проверено по `archive_floor.py`, функция `stage`. Перенести
пакет в `PACKAGES` раньше нельзя: без README и CHANGELOG dry-run кончится
предупреждением. Сделано: «Push и окно» называет границу префикса — не раньше
последнего коммита задачи 5 — и красный `floor` между задачами 1 и 5.

**I4. Шаг `--fixes` пустой,** хотя это самая сложная часть зонда: параметры
`initialize`, ожидание диагностик плагина, контекст `codeAction`, что считать
одним исправлением, таймаут.

Вердикт: принято. Сделано: режим `--fixes` расписан в задаче 2 по этим пунктам
с таймаутом 120 секунд и ожидаемым выводом; шаг 4 называет ожидаемое.

**M1. Красные тесты шагов 3 и 4 задачи 1 падают на компиляции,**
а не по названной причине: поле `BareAwait` появляется в шаге 5.

Вердикт: принято. Сделано: поле и параметр без действия — в каркасе, шаг 2.

**M2. Линтов четыре, а не пять;** посторонние диагностики попали бы
в сравнение.

Вердикт: принято. Сделано: `diagnostics:` по плагину и сверка только восьми
правил.

**M3. Копия `solo_lints` в зонде** — только `lib/` и `pubspec.yaml`, путь
к `async_job_lints` — один абсолютный.

Вердикт: принято. Сделано: в описании скрипта.

**M4. «Минута гейта» не обещана:** один набор — около 15 секунд при тёплом
кеше, на CI четыре с холодной сборкой.

Вердикт: принято. Сделано: шаг «Plugins» под `timeout 900`, отступление
переписано.

**M5. Проверка окна `git grep` не смотрит в `docs/ru/`.**

Вердикт: принято. Сделано: каталоги `docs/ru/` четырёх пакетов в шаге 2 задачи
6.

**M6. Перенос решений 129 и 144 и «Ставки — ядро» в задачу 7 не назван
отступлением.**

Вердикт: принято. Сделано: пункт в «Отступлениях от дизайна».
