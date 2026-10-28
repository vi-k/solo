> **Состояние на 2026-10-28:** сделано на ветке `worktree-solo-lints-2`,
> в `main` не влито: коммиты от `8429328a` до `b7186b09`, `42d2a693`,
> `70aa950a`, `e418d69c` и правка после итогового ревью. Ревью на Opus влито:
> одиннадцать находок, прототип подтвердил строки журнала всех таблиц задач
> 1–3. Исполнение — субагентами по задачам, выбор владельца 2026-10-28.
> **Что это:** план реализации предиката `isExpectedError` по дизайну, семь
> задач: три кода, четыре документов.
> **Связанные записи:** `2026-10-28-if-failed-answer-design.md`.

# План: ожидаемые ошибки задачи

> **Для агентов-исполнителей:** обязательный скилл —
> superpowers:subagent-driven-development (рекомендуется) или
> superpowers:executing-plans, задача за задачей. Шаги отмечаются
> чекбоксами (`- [ ]`).

**Цель:** задача `solo` называет свои ожидаемые ошибки предикатом
`isExpectedError`, и они не доходят до `onUnanswered`, `unansweredHandler`
и зоны; баг доходит, как прежде.

**Устройство:** всё в `packages/solo`, ядро `async_job` не меняется. Предикат
живёт на `_SoloJob`, вердикт считается в `_SoloJobObserver.onError`
и забирается в `_SoloJobObserver.onUnanswered`; ребёнок наследует предикат
в `adoptedBy`; ошибки слушателей вызывающего отделяет окно в обёртках
`whenFinished` и `whenCancelled`.

**Стек:** Dart 3.10, `package:test`, `package:fake_async`; Flutter для README
`flutter_solo`.

**Дизайн:** `2026-10-28-if-failed-answer-design.md`. Исполнитель читает его
целиком до первой задачи: план спорит от дизайна и не повторяет его доводов.

## Общие ограничения

- Ядро `packages/async_job` не меняется ни строкой.
- Тип параметра — `bool Function(Object error)?`, имя — `isExpectedError`,
  у `job`, `enqueue`, `collect`, `accumulate`; у `SoloContext.child` и `each`
  его нет.
- `ifFailed` не требуется; без `isExpectedError` маршрут ошибок прежний, байт
  в байт по журналу существующих тестов.
- Предикат спрашивают только об ошибках с `JobErrorAnswer.answered`
  и `JobErrorAnswer.later`; `cancellation` и `never` идут как есть.
- Код, комментарии, сообщения коммитов и тексты ошибок — по-английски;
  документы для владельца — по-русски.
- Ширина 79, `python3 tool/reflow.py` и `python3 tool/check_line_width.py`
  перед каждым коммитом с Markdown; `reflow.py` — только для `.md`.
- Перевод правится тем же коммитом, что оригинал;
  `python3 tool/check_translations.py` зелёный; правленые абзацы переводов
  проходят линтер скилла `humanizer--ru`, считаются только `ERROR`, шаг «Голос»
  пропускается.
- Перед коммитом кода из `packages/solo`: `dart format .`,
  `dart analyze --fatal-infos`, `dart test`. В `packages/flutter_solo` —
  `flutter test` и `dart analyze --fatal-infos`; `pub get` там —
  `flutter pub get`, в `packages/solo` — только `dart pub get`.
- Коммиты — Conventional Commits, по одному на задачу,
  с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git status`
  перед каждым, чужое не коммитить.

## Фокус ревью

Пять случаев, которые дизайн подразумевает, а тесты задач ловят хуже всего:

1. Ошибка без предиката: каждый существующий тест `solo` проходит без правки
   журнала. Ошибка в ветке «предиката нет» меняет маршрут для всех.
2. Ошибка, которую ядро передаёт дважды: `onError` с `later`, затем
   `onUnanswered` через микротаску. Вердикт обязан дожить до второго вызова —
   тест «нечистый предикат» в задаче 1. Что запись после этого удаляется, тест
   не видит: наружу это не выходит, и держит это довод дизайна о слабой ссылке,
   а не набор.
3. Строка, число или запись, брошенные как ошибка: `Expando` на них бросает.
   Тест «строка как ожидаемая ошибка» в задаче 1.
4. Окно внутри окна: ошибка слушателя, пока окно другого слушателя открыто.
   Окно восстанавливает внешнее, а не обнуляет его. Тест «a listener error
   while another one is answered for» в задаче 3; мутация `= null` вместо
   `= outer` теряет в нём последнюю строку.
5. Каскад, кончившийся стеком: `StackOverflowError` обёртка пропускает в охрану
   ядра. Ни один тест `solo` не проводит переполнение через слушателя
   `_SoloJob`, и мутация, которая его глотает, остаётся зелёной; держит это код
   и ревью задачи 3. Переполнение, брошенное слушателем вне такого каскада,
   ядро передаёт `notifyError` уже мимо окна, и предикат о нём спрашивают —
   предикат, который назвал бы `StackOverflowError`, нелеп, и случай
   не закрывается.

---

### Задача 1: предикат, вердикт и ответ

**Файлы:**

- Изменить: `packages/solo/lib/src/solo.dart` — `job`, `enqueue`, `collect`,
  `accumulate`, `_SoloJobObserver.onError`, `_SoloJobObserver.onUnanswered`,
  dartdoc `Solo.onError`, `Solo.onUnanswered`.
- Изменить: `packages/solo/lib/src/job.dart` — поле, вердикт, `_isExpected`.
- Изменить: `packages/solo/lib/src/accumulator.dart` — поле и передача в `job`,
  рядом с `_ifFailed`.
- Изменить: `packages/solo/lib/src/observer.dart` — dartdoc
  `SoloObserver.onError`.
- Изменить: `packages/solo/test/support/test_solo.dart` — `OpenSolo` передаёт
  новый параметр в `job`, `enqueue`, `collect`, `accumulate`.
- Изменить: `packages/solo/test/support/journal.dart`,
  `packages/solo/test/support/run_solo.dart` — журнал с ответом.
- Изменить: `packages/solo/doc/reference.md` и `docs/ru/solo/reference.md` —
  строка таблицы «Parameters of a job».
- Изменить: `docs/settled.md` — пункты 44, 109 и 15; дизайн велит пересмотреть
  44 тем же коммитом, что и реализацию.
- Изменить: `docs/handoff.md` — абзац о работе, после каждой задачи.
- Создать: `packages/solo/test/expected_error_test.dart`.

**Интерфейсы:**

- Даёт:
  - `Solo.job/enqueue/collect/accumulate(...,
    bool Function(Object error)? isExpectedError)` — именованный, после
    `ifFailed`, перед `ifCancelled`.
  - `_SoloJob`: поле `bool Function(Object error)? _isExpectedError`
    (не `final`: задача 2 пишет его в `adoptedBy`).
  - `_SoloJob._judge(Object error) → bool` — для `onError`: спрашивает,
    запоминает, отвечает «ожидаемая ли».
  - `_SoloJob._answersFor(Object error) → bool` — для `onUnanswered`: забирает
    вердикт или спрашивает, не запоминая.
  - `_SoloJob._isExpected(Object error) → bool` — сам вопрос предиката.
    Проверка окна задачи 3 встаёт в `_judge` и `_answersFor`, не сюда: здесь
    `_judge` записал бы «нет» поверх вердикта исхода.
  - `runSolo(..., {bool answers = false})`,
    `JournalObserver({bool answers = false})`.

- [ ] **Шаг 1: журнал с ответом.** `JournalObserver` получает
  `final bool answers` (по умолчанию `false`); при `true` строка `onError` —
  `'${_label(job)} error $error (${answer.name})'`. `runSolo` и `runSoloStream`
  получают `{bool answers = false}` и передают его. Набор зелёный без правки
  ни одного теста: `dart test` — `All tests passed!`.

- [ ] **Шаг 2: падающие тесты.** Файл `test/expected_error_test.dart`,
  `@Timeout(Duration(seconds: 5))`, в нём тип

  ```dart
  final class ApiError implements Exception {
    const ApiError();
    @override
    String toString() => 'ApiError';
  }
  ```

  и `_inZone` — копия из `test/unobserved_failure_test.dart`. Каждый тест —
  `runSolo(answers: true, ...)`, ошибки зоны в `errors`, журнал сравнивается
  целиком `journal.take()`. Образец:

  ```dart
  test('an expected failure nobody observed', () {
    runSolo(answers: true, (solo, journal, async) {
      final errors = <String>[];
      _inZone(errors, () {
        solo.enqueue<TestState, void>(
          key: 'load',
          isExpectedError: (error) => error is ApiError,
          (ctx) async => throw const ApiError(),
        );
      });
      async.flushTimers();
      expect(errors, isEmpty);
      expect(journal.take(), [
        '[load] started',
        '[load] error ApiError (never)',
        '[load] finished Failed(ApiError)',
      ]);
    });
  });
  ```

  Остальные — по таблице; «молчит» значит: в журнале нет строки `unanswered`,
  `errors` пуст. Строки журнала, которые таблица не называет, берутся
  из прогона и сверяются с дизайном.

  | Имя теста | Что делает | Ждём |
  | --- | --- | --- |
  | `a bug in a job that names its expected errors` | предикат `ApiError`, тело бросает `StateError('bug')` | `error Bad state: bug (later)`, затем `unanswered Bad state: bug` |
  | `a failure observed through value` | тот же `ApiError`, `await job.value` в `try` | `(never)`; пойман `ApiError` — `job.value` по-прежнему бросает |
  | `an expected failure and a bug in one ParallelWaitError` | `(f(ApiError), f(StateError)).wait` | `ApiError (never)`, `Bad state: bug (later)`, `unanswered` только у `Bad state: bug` |
  | `an expected failure of the body after a cancel` | тело ждёт `delay`, `job.cancel()`, тело бросает `ApiError` | `ApiError (never)`, молчит |
  | `an expected late failure of an abandonable call` | `ctx.abandonable` бросает `ApiError` после `cancel()` | `(never)`, молчит |
  | `an expected failure of a disposer` | `ctx.onDispose(() => throw const ApiError())` | `(never)`, молчит |
  | `an expected failure after keepWhile revoked the correction` | `keepWhile: (s) => s is! Disposed`, `ifFailed`, `externalSetState(const Disposed())`, тело бросает | состояние `Disposed`, `(never)`, молчит |
  | `a job without ifFailed names its expected errors` | только `isExpectedError` | `(never)`, молчит |
  | `a predicate that throws` | `(e) => throw StateError('predicate')`, тело бросает `ApiError` | `errors == ['Bad state: predicate']`, `ApiError (later)`, `unanswered ApiError` |
  | `a predicate that throws inside unattended work` | предикат бросает, `ctx.unattended` с поздним провалом `abandonable`, задачу отменили | в `errors` бросок предиката ровно один раз, одна строка `error` и одна `unanswered` у исходной ошибки, предикат спрошен один раз |
  | `an impure predicate` | первый вызов `true`, дальше `false`, счётчик вызовов | `(never)`, молчит, вызовов — 1 |
  | `a string thrown as an expected error` | `(e) => e is String`, тело бросает `'offline'` | `error offline (never)`, молчит |
  | `an error Job.isCancellationError names` | `Job.isCancellationError = (e) => e is ApiError` (сброс в `tearDown`), тело бросает под отменой | `(cancellation)`, предикат не спрошен |
  | `an expected failure of a collect group` | `solo.collect(..., isExpectedError: ...)`, обработчик бросает | `(never)`, молчит |
  | `an expected failure of an accumulate group` | то же для `accumulate` | `(never)`, молчит |
  | `an expected failure under Solo.debug` | `Solo.debug = lines.add` (сброс в `tearDown`) | среди строк есть `'Job(load) expected ApiError: nobody is asked to answer'` |
  | `an expected failure of a droppable job continued with shared and dropped` | `enqueue(policy: Policy.droppable, isExpectedError: ..., throw ApiError).shared()`, ручку выбросили | `[load] error ApiError (never)`, `errors == ['ApiError']`: продолжение отвечает своей ручкой, как описано в дизайне |

- [ ] **Шаг 3: запустить, убедиться, что падают.**
  `dart test test/expected_error_test.dart` — ошибка компиляции «No named
  parameter with the name 'isExpectedError'».

- [ ] **Шаг 4: параметр.** `isExpectedError` у `job`, `enqueue`, `collect`,
  `accumulate` в `solo.dart`; `enqueue` передаёт его в `job`, `collect`
  и `accumulate` — в `_SoloAccumulator`, тот — в `_SoloJob` рядом
  с `ifFailed: _ifFailed`. `OpenSolo` в `test/support/test_solo.dart` — то же.
  Строка в `doc/reference.md`, «Parameters of a job», после `ifFailed`:

  ```markdown
  | `isExpectedError` | `enqueue`, `job`, `collect`, `accumulate` | Names the errors the job expects: one it names is heard by `onError` and answered for by nobody | [Handled and unhandled failures](errors.md#handled-and-unhandled-failures) |
  ```

  и её перевод в `docs/ru/solo/reference.md`. Сторож справочной страницы
  гоняется в шаге 7, когда параметр дойдёт до `_SoloJob`.

  Dartdoc параметра у `job` — абзац рядом с абзацем `[ifFailed]`, не больше
  шести строк: `check_dartdoc.py` держит блок в 30 строк, у `job` их уже 23.
  В абзаце: ошибку, которую назвал предикат, `onError` слышит
  с `JobErrorAnswer.never`, а ответа за неё не просят — ни `onUnanswered`,
  ни `unansweredHandler`, ни зону; `value` её по-прежнему бросает; предикат
  спрашивают о каждой ошибке задачи по одной, части `ParallelWaitError` тоже,
  позвали `ifFailed` или нет, и ребёнок, запущенный в теле, берёт его; держать
  его проверкой типа. Остальное — отмены, бросивший предикат,
  `Policy.droppable` и продолжения `shared()` и `then`, широкий тип у детей —
  говорит страница ошибок (задача 4); `job` ведёт туда своей ссылкой
  на «Parameters of a job». Это отступление от списка «Документы» дизайна, где
  всё перечислено в dartdoc, и причина — предел `check_dartdoc.py`. `enqueue`,
  `collect`, `accumulate` ссылаются на `job`, как уже делают для `ifFailed`.

- [ ] **Шаг 5: вердикт на `_SoloJob`.** В `job.dart`:

  - поле `_isExpectedError` из конструктора; не отпускается в `finished()`,
    и dartdoc поля говорит почему — ненаблюдённый `Failed` идёт к ответу
    микротаской позже, — рядом с комментарием над `_body`, который объясняет,
    почему отпускают остальное;
  - `Expando<bool>? _verdicts` и `List<(Object, bool)>? _plainVerdicts`, оба
    ленивые; `static bool _isPlain(Object error)` — тот же признак, что
    `JobBase._isPlain` в `packages/async_job/lib/src/job_base.dart` (`String`,
    `num`, `bool`, `Record`, иначе проба своим `Expando`, бросок — «да»),
    с комментарием, что это копия и почему;
  - `void _noteVerdict(Object error, bool expected)`
    и `bool? _takeVerdict(Object error)` — забирает и удаляет; список ищется
    по `identical`;
  - `bool _isExpected(Object error)`: предиката нет — `false`; бросок
    предиката — `_reportToZone(error, stackTrace)` и `false`;
  - `bool _judge(Object error)`: предиката нет — `false` без записи; иначе
    `_isExpected`, `_noteVerdict`, результат;
  - `bool _answersFor(Object error)`: предиката нет — `false`; иначе
    `_takeVerdict(error) ?? _isExpected(error)`, без записи.

- [ ] **Шаг 6: наблюдатель.** `_SoloJobObserver.onError`: для `answered`
  и `later` — `(job as _SoloJob)._judge(error)`, при `true` хукам идёт
  `JobErrorAnswer.never`. `_SoloJobObserver.onUnanswered`: при
  `_answersFor(error)` —
  `Solo._debug(() => '$job expected $error: nobody is asked to answer')`
  и возврат, иначе `_solo.onUnanswered(...)` как прежде. Dartdoc `Solo.onError`
  и `SoloObserver.onError`: «as in the core» получает оговорку — ошибку,
  которую назвал `isExpectedError`, хук получает с `never`; dartdoc
  `Solo.onUnanswered`, «What comes here»: ожидаемая ошибка сюда не приходит.

- [ ] **Шаг 7: тесты зелёные.** `dart test test/expected_error_test.dart` — все
  проходят; `dart test test/reference_page_test.dart` — зелёный; `dart test`
  целиком — `All tests passed!`; `dart analyze --fatal-infos` —
  `No issues found!`; `python3 tool/check_dartdoc.py` из корня — зелёный.

- [ ] **Шаг 8: решения и состояние.** `docs/settled.md`: пункт 44 переписан —
  ожидаемый провал от бага отделяет не только ответчик приложения, но и сама
  задача, назвав тип; дата 2026-10-28
  и `2026-10-28-if-failed-answer-design.md`. Пункт 109 — оговорка: ошибку,
  которую назвал `isExpectedError`, хуки получают с `never`, не как ядро. Пункт
  15 — ссылка на предикат рядом с «Глушит провал `ignoreFailure()`».
  `docs/handoff.md` — абзац о работе: задача 1 сделана, дальше задача 2.
  `python3 tool/reflow.py --check`, `python3 tool/check_line_width.py`.

- [ ] **Шаг 9: коммит.**
  `feat: name the expected errors of a job with isExpectedError`.

### Задача 2: наследование детьми

**Файлы:**

- Изменить: `packages/solo/lib/src/job.dart` — `_SoloJob.adoptedBy`.
- Изменить: `packages/solo/lib/src/job_context.dart` — dartdoc
  `SoloContext.child` и `each`.
- Тест: `packages/solo/test/expected_error_test.dart`, группа `children`.

**Интерфейсы:**

- Берёт: `_SoloJob._isExpectedError` из задачи 1.
- Даёт: ничего нового — тот же предикат у ребёнка.

- [ ] **Шаг 1: падающие тесты.** Родитель — `enqueue`
  с `isExpectedError: (e) => e is ApiError`; строки ребёнка в журнале — с `> `.

  | Имя теста | Что делает | Ждём |
  | --- | --- | --- |
  | `a ctx.child started and left fails with an expected error` | `ctx.start(ctx.child((c) async => throw const ApiError()))` | `> [...] error ApiError (never)`, молчит |
  | `two branches of runAll fail with expected errors` | `ctx.runAll` из двух веток, обе бросают `ApiError`; `ifFailed` пишет `Disposed` | обе ветки `(never)`, состояние `Disposed`, молчит |
  | `each inside a ctx.child fails with an expected error` | `ctx.start(ctx.child((c) async { c.each(stream, (_, _) => throw const ApiError()); }))` | `(never)`, молчит |
  | `a child of job(...) with a predicate of its own` | `ctx.start(solo.job(..., isExpectedError: (e) => e is StateError))`, бросает `ApiError` | `(later)` у ребёнка, `unanswered ApiError` |
  | `a child of job(...) without a predicate` | `ctx.start(solo.job(...))` без своего, бросает `ApiError` | `(never)`, молчит |
  | `a child under a parent without a predicate` | у родителя предиката нет | маршрут прежний: `(later)`, `unanswered` |

- [ ] **Шаг 2: убедиться, что падают.** Первые три и пятый — красные: у ребёнка
  `(later)` и строка `unanswered`.

- [ ] **Шаг 3: `adoptedBy`.** После `_parentJob = parent._job;` —
  `_isExpectedError ??= parent._job._isExpectedError;`. `ctx.child`
  и `createEachJob` предикат не передают. Dartdoc `SoloContext.child` и `each`:
  своего предиката нет, ребёнок берёт предикат родителя, когда его запускают
  в теле родителя.

- [ ] **Шаг 4: зелёные.** `dart test` целиком — `All tests passed!`,
  `dart analyze --fatal-infos` — `No issues found!`,
  `python3 tool/check_dartdoc.py` — зелёный. `docs/handoff.md` — задача 2
  сделана.

- [ ] **Шаг 5: коммит.**
  `feat: let a child take the isExpectedError of its parent`.

### Задача 3: окно для ошибок слушателей

**Файлы:**

- Изменить: `packages/solo/lib/src/job.dart` — переопределения `whenFinished`,
  `whenCancelled`, поле окна, проверка в начале `_judge` и `_answersFor`.
- Изменить: `docs/handoff.md` — задача 3 сделана.
- Тест: `packages/solo/test/expected_error_test.dart`, группа `listeners`.

**Интерфейсы:**

- Берёт: `_judge`, `_answersFor`, `_isExpected` из задачи 1.
- Даёт: `List<Object>? _listenerFailures`,
  `bool _isListenerFailure(Object error)` — по `identical`.

- [ ] **Шаг 1: падающие тесты.** Задача
  с `isExpectedError: (e) => e is ApiError`.

  | Имя теста | Что делает | Ждём |
  | --- | --- | --- |
  | `a whenFinished listener throws an ApiError` | задача кончилась `Done`, слушатель бросает `const ApiError()` | `error ApiError (answered)`, `unanswered ApiError` |
  | `a whenCancelled listener throws an ApiError` | `job.cancel()`, слушатель бросает | `(answered)`, `unanswered ApiError` |
  | `a listener throws a ParallelWaitError of an ApiError` | слушатель бросает `ParallelWaitError` с `ApiError` внутри | у части `(answered)`, `unanswered ApiError` |
  | `a listener rethrows the expected failure of its job` | тело бросает `ApiError`, `whenFinished` перебрасывает его с его же `stackTrace` | `error ApiError (never)` исхода, `error ApiError (answered)` слушателя, ровно одна строка `unanswered ApiError` |
  | `a listener error while another one is answered for` | контроллер теста переопределяет `onError`: на первой ошибке он регистрирует на той же задаче `whenFinished`, который бросает `StateError('inner')`; задача кончилась `Done`, её слушатель бросает `const ApiError()` | по порядку `error ApiError (answered)`, `error Bad state: inner (answered)`, `unanswered Bad state: inner`, `unanswered ApiError` |
  | `a listener of a job without a predicate throws` | без `isExpectedError` | как сейчас: `(answered)`, `unanswered` |

- [ ] **Шаг 2: убедиться, что падают.** Первые пять — красные: ошибки слушателя
  идут с `(never)` и молчат.

- [ ] **Шаг 3: обёртка.** `whenFinished` и `whenCancelled` у `_SoloJob` отдают
  в `super` обёрнутый колбэк:

  ```dart
  void Function(A) _windowed<A>(void Function(A) callback) => (event) {
    try {
      callback(event);
    } on Object catch (error, stackTrace) {
      if (error is StackOverflowError) rethrow;
      final outer = _listenerFailures;
      final failures = [...?outer];
      Job.visitErrors(
        error,
        stackTrace,
        onFailure: (failure, _) => failures.add(failure),
      );
      _listenerFailures = failures;
      try {
        notifyError(error, stackTrace);
      } finally {
        _listenerFailures = outer;
      }
    }
  };
  ```

  Ловля — `on Object` с проверкой типа внутри, как в `_guardListener` ядра
  (`job_base.dart`): `on StackOverflowError` роняет `avoid_catching_errors`.
  Комментарий над ним: `StackOverflowError` уходит в охрану ядра, чьё правило
  читает приватный `_outOfStack`; `notifyError` зовёт `onError` и спрашивает
  ответ синхронно, поэтому окно закрывается после ответа; регистрации
  `_SharedJob` и `_ThenJob` ядра идут через обёртку и не бросают.
  `_isListenerFailure` в начале `_judge` и `_answersFor` — `false` без чтения
  и записи вердикта.

- [ ] **Шаг 4: зелёные.** `dart test test/expected_error_test.dart`; затем
  `test/listeners_test.dart` с `test/when_cancelled_test.dart`; затем
  `dart test` целиком — `All tests passed!`; `dart analyze --fatal-infos` —
  `No issues found!`. Переполнение через слушателя `_SoloJob` тестом
  не держится (пункт 5 фокуса ревью): его проверяет ревью задачи по коду.
  `docs/handoff.md` — задача 3 сделана.

- [ ] **Шаг 5: коммит.**
  `feat: keep the listener errors of a caller out of isExpectedError`.

### Задача 4: страница ошибок

**Файлы:**

- Изменить: `packages/solo/doc/errors.md`, `docs/ru/solo/errors.md`.
- Изменить: код страницы в `packages/solo/test/support/errors_page.dart`,
  `errors_first_attempts.dart`, `errors_page_answering.dart`,
  `errors_stubs.dart`, `errors_rakes.dart` — что из них держит правленые блоки;
  сторож — `packages/solo/test/errors_rakes_test.dart`.

- Создать: `packages/solo/test/support/errors_page_expected.dart` — код раздела
  `### Naming the expected errors`: его `load` с предикатом не уживётся
  в `errors_page.dart` рядом с `load` без предиката.
- Изменить: `docs/handoff.md` — задача 4 сделана.

- [ ] **Шаг 1: тип ошибки примеров.** В `errors_stubs.dart` —
  `final class ApiException implements Exception` с `final String message`,
  `const ApiException(this.message)`, `toString() => 'ApiException: $message'`.
  Где страница бросает `StateError('no network')` как провал сети, —
  `ApiException('no network')`; трассы на странице меняются вслед
  (`report: ApiException: no network`). `StateError`, который на странице
  значит баг (`no free slot` и подобные), остаётся.

- [ ] **Шаг 2: разделы.** По списку «Документы» дизайна:
  - таблица вступления, строка «A failure kept out of the zone» — добавить
    `isExpectedError`;
  - «Where each error goes» — строка «Answer» первой таблицы; ячейки
    `onUnanswered` второй там, где предикат действует: ошибка тела, правила
    старта, `abandonable`, диспоузера, `ctx.onCancel`, обработчика состояния,
    `keepWhile`, `unattended`, ветки `runAll`. Строку «An error of a disposer,
    a `ctx.onCancel` callback, a `whenCancelled` or `whenFinished` listener, or
    a state handler of a job» (строка 69) разделить надвое: слушатели
    `whenCancelled` и `whenFinished` идут отдельной строкой с прежним
    `onUnanswered` — их ошибок предикат не видит (задача 3). Новая строка
    второй таблицы после строки `Job.isCancellationError`: «An error
    `isExpectedError` names» | `onError`, with `never` | Nobody;
  - список «These are the errors that no outcome carries» (строки 232–240) —
    тот же раздел: слушатели отдельным пунктом, и абзац под списком говорит,
    что ошибки, которые назвал предикат, до переопределения не доходят;
  - опора на быстрый старт. README получает предикат в задаче 6, а страница
    показывает, куда идёт ошибка задачи, которая своих ошибок не назвала.
    Комментарий `// ...the jobs from the quick start...` (строка 107) и dartdoc
    `Not on the page: the job of the quick start in the README.`
    в `errors_page.dart` — «the jobs of the quick start, without its
    `isExpectedError`»; абзац строки 147 («A screen starts a job of the profile
    from the quick start…») и строка 438 («The job is `load()` of the quick
    start…») — та же оговорка;
  - «Reporting an error» — абзац об `answer`: случай `never` для ожидаемой
    ошибки назван здесь, страница ядра его не знает;
  - «Handled and unhandled failures» — после «Observing the outcome» третий
    раздел `### Naming the expected errors`: `load`
    с `isExpectedError: (error) => error is ApiException`, трасса прогона, что
    баг (`TypeError` из кода самой задачи) по-прежнему доходит до ответчика;
    продолжения `shared()` и `then` отвечают за ошибку своей ручкой — одна
    фраза со ссылкой на раздел о продолжениях;
  - «Answering for an error» — переопределение `onUnanswered`
    с `_apiFailures.add(error)` ожидаемых ошибок задачи с предикатом
    не получает: одна фраза.

  Новый раздел открывается ответом, а не первой попыткой: первая попытка
  у «Handled and unhandled failures» уже есть, этот раздел — ещё одно решение
  рядом с «Observing the outcome».

- [ ] **Шаг 3: код раздела.** Блок `### Naming the expected errors` стоит
  в `errors_page_expected.dart`. В `errors_rakes_test.dart` карта `holders`
  получает строку `'### Naming the expected errors': expected` с константой
  `const expected = 'test/support/errors_page_expected.dart';` — без неё тест
  «every heading with code under it is held to a file» красный. Трасса раздела
  сверяется тем же сторожем, через `errorsPage.quoted`, как у соседних
  разделов. `dart test test/errors_rakes_test.dart` — зелёный.

- [ ] **Шаг 4: перевод.** `docs/ru/solo/errors.md` — те же правки;
  `python3 tool/check_translations.py`; линтер `humanizer--ru` по правленым
  абзацам, ноль `ERROR`.

- [ ] **Шаг 5: проверки.** Из корня: `python3 tool/reflow.py --check`,
  `python3 tool/check_line_width.py`, `python3 tool/check_links.py`,
  `python3 tool/check_doc_shape.py` (новый раздел доходит до кода за десять
  строк прозы), `python3 tool/build_site.py`
  и `python3 -m unittest tool/build_site_test.py`. Трассы страницы держит
  `errors_rakes_test.dart`, не `check_traces.py`: гейт гоняет тот только
  по выводу стендов. `dart test` целиком. Ссылка из dartdoc `job` (задача 1)
  переключается со строки справочника на раздел
  `errors.md#naming-the-expected-errors`; `python3 tool/check_dartdoc.py`.
  `docs/handoff.md` — задача 4 сделана.

- [ ] **Шаг 6: коммит.** `docs: name the expected errors on the errors page`.

### Задача 5: остальные страницы `solo`

**Файлы:**

- Изменить: `packages/solo/doc/state.md`, `testing.md`, `children.md`,
  `jobs.md`, `mistakes.md` и их переводы в `docs/ru/solo/`.
- Изменить: код страниц в `packages/solo/test/support/testing_*.dart`,
  `children_*.dart`; новый `testing_page_expected.dart` (шаг 2); сторожа —
  `testing_rakes_test.dart`, `children_rakes_test.dart`,
  `state_rakes_test.dart`, `jobs_rakes_test.dart`, `mistakes_page_test.dart`.

- [ ] **Шаг 1: `state.md`, «The handlers».** Фраза, что обработчик не наблюдает
  исход, получает продолжение: задача, которая знает свои ожидаемые ошибки,
  называет их `isExpectedError`, со ссылкой на новый раздел `errors.md`.

- [ ] **Шаг 2: `testing.md`, «A failure nobody read».** Вся страница переходит
  на `ApiException('no network')` (тип — из `errors_stubs.dart` или своя копия
  в `testing_stubs.dart`). Контроллер страницы остаётся без предиката: на нём
  стоит первая попытка. Третий раздел после `### ignoreFailure` —
  `### isExpectedError`: `load` с предикатом и тест без `ignoreFailure()`,
  зелёный; фраза, что баг такой тест всё равно роняет. «A test that expects
  such an error» остаётся о тесте. Правила во вступлении страницы (строки 16
  и 29: тест, который задачу не ждёт, даёт ей `ignoreFailure()`) получают
  вторую форму: задача, которая называет свои ожидаемые ошибки, этого
  не требует. Остальные `ignoreFailure()` страницы (разделы о `fakeAsync`)
  стоят на контроллере страницы без предиката и не меняются.

  Опора на быстрый старт. Первый блок страницы — контроллер README, и после
  задачи 6 он уже не совпадает с ним: в README у `load` появится строка
  `isExpectedError:`. Решение — контроллер страницы есть контроллер быстрого
  старта без его `isExpectedError`, и это сказано в прозе: строки 42–44 («all
  but the last drive the `load` of the controller from Quick start») получают
  оговорку «without its `isExpectedError`, so that the failure is the test's to
  read». Сторож `the controller is the one of the quick start of the README`
  (`testing_rakes_test.dart`) сравнивает блок с быстрым стартом, из которого
  вынута строка `isExpectedError:` —
  `quickStart.replaceAll(RegExp(r'\n *isExpectedError: [^\n]*'), '')`, — и его
  `_says` следует за новой фразой. Пока задача 6 не сделана, строки в README
  нет, и замена ничего не вынимает: сторож зелёный в обоих коммитах.

  Код раздела `### isExpectedError` — новый файл
  `packages/solo/test/support/testing_page_expected.dart`: свой
  `final class ProfileController` с предикатом у `load` рядом с тестом раздела;
  с контроллером `testing_page_fixtures.dart` он в одном файле не уживётся.
  Карта `holders` в `testing_rakes_test.dart` получает
  `'### isExpectedError': [expected]` с константой
  `const expected = 'test/support/testing_page_expected.dart';`.

- [ ] **Шаг 3: `children.md`.** Абзац о наследовании: ребёнок, запущенный
  в теле, берёт предикат родителя; свой бывает только у `job(...)`; широкий тип
  гасит и баги детей. Таблица «Three ways to ignore a child» — сноска под
  таблицей, что ошибку, которую назвал предикат, «goes to `onUnanswered`»
  не касается.

- [ ] **Шаг 4: `jobs.md` и `mistakes.md`.** `jobs.md`: строка таблицы
  `job.ignoreFailure()` (строка 38) и абзац строк 49–52 — вторая форма,
  `isExpectedError`. `mistakes.md`: абзацы строк 178 и 198–201 — то же, одной
  фразой каждый; пример `profile.load().ignoreFailure()` остаётся: там он
  о задаче, исход которой не нужен.

- [ ] **Шаг 5: переводы и проверки.** Переводы пяти страниц; линтер
  `humanizer--ru`; из корня `check_translations.py`, `reflow.py --check`,
  `check_line_width.py`, `check_links.py`, `check_doc_shape.py`,
  `build_site.py`, `python3 -m unittest tool/build_site_test.py`; трассы
  страниц держат их сторожа; `dart test` целиком. `docs/handoff.md` — задача 5
  сделана.

- [ ] **Шаг 6: коммит.** `docs: tell the solo pages about isExpectedError`.

### Задача 6: README `solo` и `flutter_solo`

**Файлы:**

- Изменить: `packages/solo/README.md`, `packages/solo/README.ru.md`,
  `packages/solo/test/support/readme_quick_start.dart` (и `readme_stubs.dart`,
  если блок там), сторож `packages/solo/test/readme_rakes_test.dart`.
- Изменить: `packages/flutter_solo/README.md`, `README.ru.md`,
  `packages/flutter_solo/doc/testing.md`, `docs/ru/flutter_solo/testing.md`,
  `packages/flutter_solo/test/support/readme_profile.dart`,
  `readme_widgets.dart`, `readme_variants.dart`, `readme_scopo.dart` (строка 46
  держит строку README 537 дословно) — что держит правленые блоки; сторожа
  `readme_rakes_test.dart`, `testing_rakes_test.dart`,
  `readme_scopo_test.dart`.
- Изменить: `tool/flutter_snippets.py` — стенд задания `flutter`
  в `.github/workflows/gate.yml`.
- Изменить: `packages/flutter_solo/example/lib/main.dart` — только комментарий
  строки 6.
- Изменить: `docs/handoff.md` — задача 6 сделана.

- [ ] **Шаг 1: README `solo`, быстрый старт.** Рядом с `ProfileApi` —
  `final class ApiException implements Exception` (как в задаче 4) и фраза, что
  `fetchName` настоящего клиента бросает её, когда вызов не удался. `load`
  получает `isExpectedError: (error) => error is ApiException`. Абзац «A
  `Failed` that nobody observes…» (строки 149–155) — ожидаемая ошибка, которую
  назвала задача, дальше не идёт; баг идёт; `ignoreFailure()` остаётся вызову,
  которому исход не нужен вовсе. Пример `profile.load().ignoreFailure()`
  из абзаца уходит: у `load` теперь предикат, и `ignoreFailure()` на нём
  глушил бы баги, как кнопка `flutter_solo`. Выброшенный `profile.load()` —
  пример формы, которой хватает предиката.

- [ ] **Шаг 2: README `flutter_solo`.** `load` — тот же предикат и тот же тип
  у API. Кнопка — `onPressed: controller.load`: лямбда роняет
  `unnecessary_lambdas`, а блок README анализируется в `readme_profile.dart`
  и в стенде с `--fatal-infos`. `initState` строки 494 и `ScopeModel.create`
  строки 537 (scopo) — `controller.load();` без `ignoreFailure()`. Абзац «They
  answer on the screen…» (строки 168–175) и абзац строк 609–612 — по дизайну:
  две формы; абзац 614–620 не меняется. Абзац о `save` (строки 260–266)
  не меняется: у `save` предиката нет.

- [ ] **Шаг 3: тесты README `flutter_solo`.** Тест, где фейк проваливает
  `load`, отдаёт `ApiException` и зелёный без `ignoreFailure()`; новый тест
  `a load that fails with a bug`: фейк бросает `StateError`, тест ловит её
  в зоне — баг по-прежнему роняет виджет-тест.

- [ ] **Шаг 4: `flutter_solo/doc/testing.md`.** Абзац строк 90–96 («A load that
  fails makes a test red even though it reads `done`, if it reads it after the
  pump») для `ApiException` больше не верен: провал, который назвал предикат,
  тест не роняет, роняет баг. Строка 98 — задача, контроллер которой называет
  свои ожидаемые ошибки, ничего больше не требует; брошенная тестом задача без
  предиката говорит это `ignoreFailure()`.

- [ ] **Шаг 5: стенд `tool/flutter_snippets.py`.** Он собирает README
  `flutter_solo`, его `doc/testing.md` и быстрый старт `solo`; `ProfileApi`
  берёт из `README_API` (строки 1176–1204), README его не объявляет.
  - в `README_API` — тот же `ApiException`, что в README; `FailingApi` бросает
    `ApiException('no network')`;
  - драйвер «a failed load is what the toast says too» ждёт
    `['ApiException: no network']`;
  - драйвер «a tap on Load that fails puts the button back, and no more»
    держится уже предикатом, а не `ignoreFailure()` кнопки; комментарий в нём —
    о предикате;
  - новый драйвер рядом: фейк бросает `StateError('bug')`, нажатие на Load —
    и баг доходит до зоны теста; ловить его тем же способом, что тест
    `a load that fails with a bug` шага 3;
  - свои `controller.load().ignoreFailure()` стенда (`loaded` и драйверы
    `fakeAsync`) остаются: это не текст README.

  Прогон — как в задании `flutter`:
  `python3 tool/flutter_snippets.py <каталог>` вне репозитория, в нём
  `flutter pub get`, `flutter analyze`,
  `flutter test --concurrency=1 | tee <вывод>`, затем
  `python3 tool/check_traces.py packages/flutter_solo/doc/mixins.md <вывод>`.

- [ ] **Шаг 6: комментарий примера.**
  `packages/flutter_solo/example/lib/main.dart` строка 6: «The model and the
  job of the README's Usage» — «The model of the README's Usage, its job
  without `isExpectedError`»: пример ждёт `load().done`, исход наблюдает,
  и предикат ему не нужен. Поведение не меняется; `flutter analyze`
  в `packages/flutter_solo/example`.

- [ ] **Шаг 7: переводы и проверки.** `README.ru.md` обоих пакетов
  и `docs/ru/flutter_solo/testing.md`; линтер `humanizer--ru`; из корня
  `check_translations.py`, `reflow.py --check`, `check_line_width.py`,
  `check_links.py`, `check_doc_shape.py`, `build_site.py`,
  `python3 -m unittest tool/build_site_test.py`; `dart test` в `packages/solo`
  (в нём сторож `testing_rakes_test.dart` из задачи 5 сравнивает уже
  с предикатом в README); `flutter test` и `dart analyze --fatal-infos`
  в `packages/flutter_solo`. `docs/handoff.md` — задача 6 сделана.

- [ ] **Шаг 8: коммит.** `docs: name the expected errors in the READMEs`.

### Задача 7: CHANGELOG, решения и записи

**Файлы:**

- Изменить: `packages/solo/CHANGELOG.md`, `docs/ru/solo/CHANGELOG.md`,
  `packages/flutter_solo/CHANGELOG.md`, `docs/ru/flutter_solo/CHANGELOG.md`.
- Изменить: `docs/backlog.md`, `docs/handoff.md`, шапки
  `2026-10-28-if-failed-answer-design.md` и этого плана. `docs/settled.md`
  правит задача 1.

- [ ] **Шаг 1: CHANGELOG `solo`, «Unreleased».** В «Breaking changes»: `job`,
  `enqueue`, `collect`, `accumulate` получают именованный `isExpectedError`,
  и подкласс, который их переопределяет, должен его принять. После «Breaking
  changes» — раздел «Added»: `isExpectedError`, одной записью со ссылкой
  на «Naming the expected errors» страницы ошибок. CHANGELOG `flutter_solo`,
  «Unreleased», «Documentation»: README называет ожидаемые ошибки `load`,
  и кнопка больше не зовёт `ignoreFailure()`. Переводы обоих.

- [ ] **Шаг 2: бэклог и записи.** Из `docs/backlog.md` удалить запись «Сделать
  `ifFailed` отвечающим». Шапки дизайна и плана — «сделано», с коммитами.
  `docs/handoff.md` — абзац о работе: сделано, что дальше.

- [ ] **Шаг 3: проверки.** `python3 tool/reflow.py --check` и названные записи,
  `check_line_width.py`, `check_translations.py`, `check_links.py`,
  `build_site.py` и `python3 -m unittest tool/build_site_test.py`: запись
  «Added» ссылается на новый якорь страницы ошибок.

- [ ] **Шаг 4: коммит.** `docs: record isExpectedError in the changelogs`.

## Что не трогается

- `packages/solo/doc/vs-bloc.md`, `accumulation.md`, `accumulation-rules.md`
  и их стенды: страницы сравнивают и объясняют накопление, а без предиката
  маршрут прежний.
- Код примера `packages/flutter_solo/example/`: он ждёт `load().done`, то есть
  исход наблюдает; задача 6 правит только его комментарий.
- `packages/solo_lints`: правила о брошенной задаче там нет.
