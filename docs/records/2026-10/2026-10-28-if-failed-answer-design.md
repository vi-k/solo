> **Состояние на 2026-10-28:** дизайн, не реализован. Имя `isExpectedError`
> выбрал владелец 2026-10-28; вторая редакция после первого ревью ждёт
> второго круга. Пересматривает пункт 44 `docs/settled.md`.
> **Что это:** задача называет свои ожидаемые ошибки предикатом
> `isExpectedError`, и они не доходят до ответчика; баг доходит, как прежде.
> **Связанные записи:** `2026-10-12-solo-project-review.md` (M3),
> `2026-10-20-solo-project-review.md` (M7),
> `2026-10-24-observer-answer-design.md`,
> `2026-10-27-solo-error-answer-report.md`.

# Ожидаемые ошибки задачи

## Повод

Запись бэклога владельца «Сделать `ifFailed` отвечающим», 2026-10-28.
Потребители несколько раз спрашивали об одном: провал переведён в состояние,
экран показал `Failure`, а тест краснеет или приложение падает.

Зонд на ядре `826d2b4f`, контроллер как в быстром старте README, `load()`
выброшен:

| Случай | Что вышло |
|---|---|
| обычный `test`, ничего не задано | состояние `Failure(offline)`, тест красный на `Bad state: offline` |
| внутри `runZonedGuarded` | зона получила `offline` |
| `TypeError` в теле, `unansweredHandler` задан | состояние `Failure(TypeError)`, обработчик слышит `TypeError` |

Это правило пункта 44: `ifFailed` бага от ожидаемой ошибки не отличает
и поэтому не наблюдает исход, а приложение отделяет одно от другого в одном
месте, по типу ошибки. Поднимали дважды, M3 и M7. Новый довод — не о правиле,
а о том, как его встречают: `ifFailed` читается как `catch`, и после него никто
не ждёт, что ошибку надо ещё и наблюсти.

Решение владельца: задача отвечает за ошибку, только если явно назвала её тип.
Баг, который `ifFailed` тоже переводит в состояние, по-прежнему идёт
к ответчику.

## Форма

Новый именованный параметр `isExpectedError` у `job`, `enqueue`, `collect`
и `accumulate`:

```dart
Job<String> load() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.droppable,
  ifFailed: (state, error, stackTrace) => Failure(error),
  isExpectedError: (error) => error is ApiException,
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

Тип — `bool Function(Object error)?`, как у `Job.isCancellationError` ядра,
и поведение то же, только для одной задачи: ошибку, которую он назвал, слышит
`onError`, а ответа за неё не просят ни у кого — ни `onUnanswered` контроллера,
ни `Solo.unansweredHandler`, ни зону. Исход не меняется: `job.value` бросает
ошибку `Failed` тому, кто его читает. Без параметра маршрут прежний, и старый
код не меняется.

Имя. `is…Error` — предикат над ошибкой, а не над состоянием, как `canStart`
и `keepWhile` рядом, и пара `Job.isCancellationError`. Слова «answer» в имени
нет: `JobErrorAnswer.answered` значит «ошибка идёт к ответу», и параметр,
названный от того же корня, читался бы наоборот. Корня `expect` в глаголе тоже
нет: `expect`, `expectLater` и `expectAsync1` из `package:test` — утверждения,
и `expects: (error) => …` в тестовом файле читается как «задача должна упасть
с этой ошибкой». Имя выбрано по двум независимым разборам, Opus и Sol; оба
поставили его первым, `isExpected` — вторым: без `Error` его легко прочесть как
ещё одно правило о состоянии.

`ifFailed` не требуется. Ответ не зависит от того, позвали ли `ifFailed`,
а ошибка очистки или позднего `abandonable` в состоянии не показывается
никогда; требование обходилось бы пустой строкой
`ifFailed: (state, error, stackTrace) => state` (пункт 95) и закрыло бы
наследование детьми, раздел ниже.

## Что считается ожидаемым

Предикат спрашивают о каждой ошибке задачи, которая иначе дошла бы
до `onUnanswered`:

- ненаблюдённый `Failed`;
- каждый провал внутри `ParallelWaitError` по отдельности, как их обходит
  `visitErrors` (пункт 22): ожидаемая часть отвечена, баг рядом идёт дальше.
  `ifFailed` получает весь `ParallelWaitError`, предикат — его части,
  и `error is ParallelWaitError` не совпадает никогда; dartdoc говорит это;
- провал тела задачи, которая кончилась `Cancelled`;
- ошибки вне исхода, если их бросил код самой задачи: провал, которого
  `abandonable` перестал ждать, очистка, колбэк `ctx.onCancel`, `unattended`,
  `ifFailed` и `ifCancelled`, бросивший `keepWhile`.

Ответ не зависит от того, позвали ли `ifFailed`. Коррекцию отзывают
`keepWhile`, родитель или бросивший обработчик, и тогда состояние не меняется,
но ошибка того же типа ожидаема всё равно. Иначе ответ снова стал бы условным:
обычно тихо, а иногда крэш, и почему — без правил отзыва не понять.

Поздний провал `abandonable` в охвате ради быстрого старта: `load` ждёт
`api.fetchName` через него, и сетевая ошибка запроса, который перестали
ждать, — та же ожидаемая ошибка, что и провал тела.

### Чего предикат не трогает

- **Слушателей вызывающего.** `job.whenFinished` и `job.whenCancelled`
  регистрирует виджет или другой вызывающий, а не задача, и их ошибка — баг
  вызывающего: широкий предикат `e is Exception` гасил бы и `FormatException`
  из колбэка виджета. Ядро ведёт ошибку слушателя тем же `notifyError`, что
  и ошибку очистки, поэтому `_SoloJob` переопределяет `whenFinished`
  и `whenCancelled`: обёртка запоминает то, что бросил колбэк, и бросает
  дальше, в охрану ядра. Такую ошибку предикат не спрашивают.
- **Продолжения.** `job.shared()` и `job.then(...)` делают свою ручку, и провал
  исходной задачи она несёт со своим ответом: у ручки свой наблюдатель, без
  наблюдателя — зона, мимо `unansweredHandler`. Исходная задача с предикатом
  говорит в `onError` `never`, а выброшенное продолжение отдаёт ту же ошибку
  в зону. Так ручка ведёт себя и с `ignoreFailure()` у исходной задачи; правка
  ядра ради этого не делается, dartdoc и страница ошибок называют случай.
  `Policy.droppable` у быстрого старта продолжается только через `shared()`
  (пункт 91), поэтому случай попадает в документы.
- **Отмену.** `Cancelled` и ошибки, которые назвал `Job.isCancellationError`,
  до ответа не доходят и так; ядро решает это раньше, предикат о них
  не спрашивают. `Failed` из отмены ядро объявляет как `cancellation`, и туда
  предикат тоже не доходит.

### Дети

Ребёнок без своего предиката берёт предикат родителя. `ctx.child` уже так
передаёт `keepWhile` (`_SoloContext.child`
в `packages/solo/lib/src/job_context.dart`), и `isExpectedError` идёт рядом;
ребёнок `each` — через `createEachJob` там же; ребёнок из `job(...)`,
запущенный `ctx.run` или `ctx.start`, — при усыновлении, если своего нет. Свой
предикат ребёнка сильнее родительского.

Без наследования вернулся бы исходный симптом. Первое ревью показало это
на прототипе, где ребёнок предиката не получал, а у родителя он был:

```text
B3 runAll, two branches fail ApiError:
   state=Failure(ApiError) [onError(Job()) ApiError later, onError(Job()) ApiError answered, handler(Job()) ApiError, onError(Job(load)) ApiError never]
B2 ctx.start(ctx.child(...)) fails:   [onError(Job()) ApiError later, handler(Job()) ApiError]
B4 ctx.run(ctx.child(k => k.abandonable(...throw ApiError))), parent cancelled:
   outcome=Cancelled(manual) [onError(Job()) ApiError answered, handler(Job()) ApiError]
B4b same abandonable in the parent's own body:   [onError(Job(load)) ApiError never]
```

В B3 экран показывает `Failure(ApiError)`, а обработчик получает `ApiError`
второй ветки, которую `ctx.runAll` не бросил. Наследование хранится
в собственном поле ребёнка: `_parentJob` отпускается в `finished()`, а ответ
за ветку или за ненаблюдённый провал приходит позже.

Обратное направление остаётся как есть: ребёнок с предикатом, которого ждёт
родитель без предиката, свою ошибку не отдаёт, но родитель падает с ней
и отдаёт её сам — это провал родителя, и он его не назвал.

## `JobErrorAnswer`

Для ошибки, которую предикат назвал, `solo` передаёт в `Solo.onError`
и `SoloObserver.onError` `JobErrorAnswer.never` вместо `answered` и вместо
`later`: задача за неё не попросит ответа никогда, а исход, который прочтут,
бросит ошибку вызывающему, как и после `ignoreFailure()`. `cancellation`
остаётся как есть. Наблюдатель, который пишет отчёт в `onError` только для
того, что до `unansweredHandler` не дойдёт, ожидаемую ошибку так и запишет.

С этого места `solo` передаёт не то значение, что ядро. Dartdoc `Solo.onError`
сейчас говорит «as in the core», а пункт 109 — что хуки получают
`JobErrorAnswer`, «как `JobObserver.onError` ядра»; оба получают оговорку.
Список случаев `never` в dartdoc перечисления живёт в ядре, и нового случая там
не будет: его называет `Solo.onError`.

## Устройство

Всё в `solo`, ядро не меняется.

- `_SoloJob` хранит предикат и не отпускает его в `finished()`: ненаблюдённый
  `Failed` идёт к ответу микротаской позже.
- **Вердикт считается один раз.** Каждая ошибка, которая доходит
  до `onUnanswered`, сначала прошла `onError` (`packages/solo/doc/errors.md`,
  «Where each error goes»). `_SoloJobObserver.onError` для `answered` и `later`
  спрашивает предикат, запоминает вердикт на задаче — список пар
  по идентичности ошибки, не `Expando` (пункт 18: записи и строки) — и при «да»
  передаёт хукам `never`. `_SoloJobObserver.onUnanswered` берёт вердикт оттуда
  и при «да» возвращается, не зовя `Solo.onUnanswered`; переопределение
  `onUnanswered` в контроллере такую ошибку не слышит. Ошибку без вердикта
  ответ спрашивает сам и тоже запоминает. Иначе нечистый предикат давал бы
  `never` в `onError`, а потом ту же ошибку отдавал обработчику — первое ревью
  это показало: `calls=2 [onError ApiError never, handler ApiError]`.
- **Предикат, который бросил, ничего не назвал.** Ошибка идёт дальше своим
  маршрутом — к `Solo.onUnanswered` и `unansweredHandler`, — а то, что бросил
  предикат, — в зону через `reportHookError`, как у бросившего хука; брошенный
  `Cancelled` пропадает. Так ядро обходится с бросившим
  `Job.isCancellationError`. Без этого бросок предиката внутри ответа ловило бы
  ядро и отдавало исходную ошибку в зону мимо обработчика — прототип так
  и делал: `[zone ApiError, zone Bad state: predicate]`.
- **Ошибки слушателей вызывающего** `_SoloJob` отмечает в обёртках
  `whenFinished` и `whenCancelled`, тем же списком по идентичности; для
  отмеченной ошибки вердикт — «нет», предикат не спрашивают.
- **Отладка.** Ядро пишет в `Job.debug` «error nobody answered for» до того,
  как `solo` ошибку отпустит. `_SoloJobObserver.onUnanswered` пишет
  в `Solo.debug` следом, что задача назвала ошибку ожидаемой.
- **Наследование** — раздел «Дети».
- При `Policy.droppable` вызывающему возвращается задача первого вызова, с её
  предикатом, как и с её `ifFailed`; dartdoc говорит это одной фразой.

Предикат зовётся синхронно, по одной ошибке, никогда не с `Cancelled`; dartdoc
просит держать его проверкой типа, как у `Job.isCancellationError`.

### Зонд первой редакции

Прототип без вердикта на задаче, без наследования и без обёрток слушателей;
наблюдатель записывает `onError`, `unansweredHandler` — что дошло до ответа.
У контроллера `keepWhile: (state) => state is! Other`, `ifFailed` пишет
`Failure(error)`, предикат — `(e) => e is ApiError`; задача выброшена.

```text
1 state=Failure(ApiError) [onError ApiError later]
2 state=Failure(Instance of 'TypeError') [onError Instance of 'TypeError' later, handler Instance of 'TypeError']
3 state=Failure(ParallelWaitError(2 errors): ApiError) [onError ApiError later, onError Bad state: bug later, handler Bad state: bug]
4 state=Other [onError ApiError never]
5 state=Idle outcome=Cancelled(manual) [onError ApiError never]
6 state=Idle [onError ApiError never]
```

1 — ожидаемая ошибка: тихо. 2 — баг: дошёл до обработчика. 3 — `(a, b).wait`
с `ApiError` и `StateError`: ответ получил только `StateError`. 4 — внешний
`Other` отменил задачу через `keepWhile`, коррекции нет, ответ есть. 5 — тело
бросило после отмены. 6 — бросила очистка. `later` в 1–3 — то, что прототип
не менял; по дизайну там `never`.

Весь набор `solo` на прототипе: красны только два сторожа
`test/reference_page_test.dart` — справочная страница и её перевод должны
перечислять новый параметр. Сначала не грузились 62 файла: подмешивание
`OpenSolo` в `test/support/test_solo.dart` переопределяет `job`, `collect`
и `accumulate`, и переопределение без нового параметра не собирается.

Остальное первое ревью проверило на своём прототипе: `Job.isCancellationError`
берёт верх над предикатом (`cancellation`, дальше ничего), отозванная коррекция
и провал под отменой ведут себя как здесь, `collect` и `accumulate` — как
`enqueue`.

## Что ломается

Новый именованный параметр у `@protected` методов ломает подкласс, который их
переопределяет: `OpenSolo` в тестах — такой подкласс. Кто открывает операции
так же, получит ошибку компиляции. Выпуск — 0.6.0, минорный и так ломающий
из-за пола SDK; в CHANGELOG `solo` пункт назван ломающим для переопределений.

Поведение старого кода не меняется: без `isExpectedError` маршрут прежний.

## Документы

- dartdoc `job`, `enqueue`, `collect`, `accumulate`, `SoloContext.child`: абзац
  о предикате — охват, дети, части `ParallelWaitError`, `onError` слышит,
  `job.value` бросает; `Solo.onUnanswered`, «What comes here»: ожидаемое сюда
  не приходит; `Solo.onError` и `SoloObserver.onError`: `never` для ожидаемого
  и оговорка «as in the core».
- `packages/solo/doc/errors.md`:
  - «Where each error goes» — ячейки `onUnanswered` второй таблицы;
  - «Handled and unhandled failures» — после «Observing the outcome» решение
    для задачи, которая знает свои ожидаемые ошибки;
  - «Answering for an error» — переопределение с `_apiFailures.add(error)`
    ожидаемых ошибок больше не получает;
  - продолжения `shared()` и `then`.

  Пример там бросает `StateError('no network')`, тип, который в Dart означает
  баг; с `isExpectedError: (e) => e is StateError` замолчали бы и баги. Примеры
  страниц, где провал ожидаем, получают свой тип исключения — `ApiException`
  или подобный, имя — в плане.
- `packages/solo/doc/state.md`, «The handlers»: фраза «does not mark the
  outcome as handled» получает продолжение про `isExpectedError`.
- `packages/solo/doc/reference.md`, «Parameters of a job»: новый параметр.
- `packages/solo/doc/testing.md`, «A failure nobody read»: предикат — вторая
  форма рядом с `ignoreFailure()`, для задачи, которая знает свои ошибки; фраза
  «A test that expects such an error» там же остаётся о тесте.
- `packages/solo/doc/children.md` — наследование; `mistakes.md` и `jobs.md` —
  места, где сказано старое правило, найдёт план.
- README `solo`, быстрый старт: `load` с предикатом, абзац о ненаблюдённом
  `Failed` — с ним.
- README `flutter_solo`, абзац о том, что провал после `ifFailed` уходит в зону
  и роняет виджет-тест, и `packages/flutter_solo/doc/testing.md` там же, —
  отсюда и пришла жалоба.
- Переводы всех перечисленных, CHANGELOG `solo` и его перевод.
- `docs/settled.md`: пункт 44 — пересмотр, ниже; пункт 109 — оговорка
  о значении `never`.

Стенды `snippets` берут код `vs-bloc.md` и `accumulation.md`; затронуты ли они,
решит план.

## Пересмотр пункта 44

Правило «`ifFailed` не наблюдает исход» остаётся: без предиката всё по-старому.
Меняется вторая половина: ожидаемый провал от бага отделяет не только ответчик
приложения, но и сама задача, когда назвала тип. Пункт переписывается тем же
коммитом, что и реализация, с датой и именем этой записи.

## Вопросы владельцу

Имя решено. Решения второй редакции, которые стоит подтвердить:

1. `ifFailed` не требуется — раздел «Форма».
2. Дети без своего предиката берут родительский — раздел «Дети».
3. Ошибки слушателей вызывающего, `whenFinished` и `whenCancelled`, в охват
   не входят — раздел «Чего предикат не трогает».

## Код зонда

Файл в `packages/solo/test/` на прототипе первой редакции, раздел «Зонд первой
редакции».

```dart
import 'dart:async';

import 'package:solo/solo.dart';
import 'package:test/test.dart';

sealed class S {
  const S();
}

final class Idle extends S {
  const Idle();
  @override
  String toString() => 'Idle';
}

final class Other extends S {
  const Other();
  @override
  String toString() => 'Other';
}

final class Failure extends S {
  final Object error;
  const Failure(this.error);
  @override
  String toString() => 'Failure($error)';
}

final class ApiError implements Exception {
  @override
  String toString() => 'ApiError';
}

final heard = <String>[];

final class Watch extends SoloObserver {
  @override
  void onError(
    Solo<Object> solo,
    Job<Object?> job,
    Object error,
    StackTrace stackTrace, {
    required JobErrorAnswer answer,
  }) => heard.add('onError $error ${answer.name}');
}

final class C extends Solo<S> {
  C() : super(const Idle());
  S get now => currentState;
  void moveOn() => externalSetState(const Other());

  Job<void> load(Future<void> Function(SoloContext<S, S> ctx) body) =>
      enqueue<S, void>(
        key: 'load',
        keepWhile: (state) => state is! Other,
        ifFailed: (state, e, st) => Failure(e),
        isExpectedError: (e) => e is ApiError,
        body,
      );
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() {
    heard.clear();
    Solo.observer = Watch();
    Solo.unansweredHandler = (solo, job, error, st) =>
        heard.add('handler $error');
  });
  tearDown(() {
    Solo.observer = null;
    Solo.unansweredHandler = null;
  });

  test('1 expected error, job dropped', () async {
    final c = C();
    c.load((ctx) async => throw ApiError());
    await flush();
    print('1 state=${c.now} $heard');
  });

  test('2 a bug, job dropped', () async {
    final c = C();
    c.load((ctx) async => throw TypeError());
    await flush();
    print('2 state=${c.now} $heard');
  });

  test('3 ParallelWaitError, one expected and one bug', () async {
    final c = C();
    c.load((ctx) async {
      await (
        Future<void>.error(ApiError()),
        Future<void>.error(StateError('bug')),
      ).wait;
    });
    await flush();
    print('3 state=${c.now} $heard');
  });

  test('4 correction revoked by keepWhile', () async {
    final c = C();
    c.load((ctx) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw ApiError();
    });
    await Future<void>.delayed(Duration.zero);
    c.moveOn();
    await flush();
    print('4 state=${c.now} $heard');
  });

  test('5 body fails after cancellation (covered)', () async {
    final c = C();
    final job = c.load((ctx) async {
      await ctx.uncancellable(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      throw ApiError();
    });
    await Future<void>.delayed(Duration.zero);
    unawaited(job.cancel());
    await flush();
    print('5 state=${c.now} outcome=${job.outcome} $heard');
  });

  test('6 a disposer throws an expected error', () async {
    final c = C();
    c.load((ctx) async {
      ctx.onDispose(() => throw ApiError());
    });
    await flush();
    print('6 state=${c.now} $heard');
  });
}
```
