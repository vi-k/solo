> **Состояние на 2026-10-28:** дизайн, не реализован; ждёт ревью и ответов
> владельца на вопросы в конце. Пересматривает пункт 44 `docs/settled.md`.
> **Что это:** задача отвечает за ожидаемые ошибки своего типа — параметр
> `answers` рядом с `ifFailed`, — а баг по-прежнему идёт к ответчику.
> **Связанные записи:** `2026-10-12-solo-project-review.md` (M3),
> `2026-10-20-solo-project-review.md` (M7),
> `2026-10-24-observer-answer-design.md`,
> `2026-10-27-solo-error-answer-report.md`.

# `ifFailed`, который отвечает за провал

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

Решение владельца: задача отвечает за провал, только если явно сказала это для
своего типа ошибки. Баг, который `ifFailed` тоже переводит в состояние,
по-прежнему идёт к ответчику.

## Форма

Новый именованный параметр `answers` у `job`, `enqueue`, `collect`
и `accumulate`:

```dart
Job<String> load() => enqueue<ProfileState, String>(
  key: 'load',
  policy: Policy.droppable,
  ifFailed: (state, error, stackTrace) => Failure(error),
  answers: (error) => error is ApiException,
  ifCancelled: (state, cancelled) => const Initial(),
  (ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  },
);
```

Тип — `bool Function(Object error)?`. Ошибка, на которую он ответил `true`,
отвечена задачей: ни `onUnanswered` контроллера, ни `Solo.unansweredHandler`,
ни зона её не получают. `onError` и `SoloObserver.onError` слышат её
по-прежнему. Без параметра поведение прежнее, и старый код не меняется.

`answers` без `ifFailed` — `ArgumentError` при создании, как нулевой `timeout`:
отвечена та ошибка, которую состояние показало. Задаче, которой провал не нужен
совсем, по-прежнему служит `ignoreFailure()` у вызывающего.

## Что считается отвеченным

Каждая ошибка этой задачи, которая иначе дошла бы до `onUnanswered`, если
предикат сказал `true`:

- ненаблюдённый `Failed`;
- каждый провал внутри `ParallelWaitError` по отдельности, как их обходит
  `visitErrors` (пункт 22): ожидаемая часть отвечена, баг рядом идёт дальше;
- провал тела задачи, которая кончилась `Cancelled`;
- ошибки вне исхода: провал, которого `abandonable` перестал ждать, очистка,
  колбэк `ctx.onCancel`, слушатели, `unattended`, бросивший `keepWhile`.

Ответ не зависит от того, позвали ли `ifFailed`. Коррекцию отзывают
`keepWhile`, родитель или бросивший обработчик, и тогда состояние не меняется,
но ошибка того же типа ожидаема всё равно. Иначе ответ снова стал бы условным:
обычно тихо, а иногда крэш, и почему — без правил отзыва не понять.

Последний пункт шире, чем «провал, который показал `ifFailed`». Он нужен ради
`abandonable`: быстрый старт ждёт `api.fetchName` через него, и сетевая ошибка
запроса, который перестали ждать, — та же ожидаемая ошибка, что и провал тела.
Правило для читателя одно: задача отвечает за свои ошибки названного типа,
откуда бы они ни пришли. Вопрос 3 — сузить ли.

Чего предикат не трогает: `Cancelled` и ошибки, которые назвал
`Job.isCancellationError`, до ответа не доходят и так; `Failed` из отмены идёт
в зону мимо ответа, как прежде. Ошибки детей — дело предиката ребёнка: каждая
ошибка приходит к ответу со своей задачей.

## `JobErrorAnswer`

`onError` получает `answer`. Для ошибки, на которую предикат ответил `true`,
`solo` передаёт `JobErrorAnswer.never` вместо `answered` и вместо `later`:
задача за неё не попросит ответа никогда, а исход, который прочтут, бросит
ошибку вызывающему, как и после `ignoreFailure()`. `cancellation` остаётся как
есть. Наблюдатель, который пишет отчёт в `onError` только для того, что
до `unansweredHandler` не дойдёт, ожидаемую ошибку так и запишет.

## Устройство

Всё в `solo`, ядро не меняется. Зонд ниже собран на прототипе, который выглядел
так:

- `_SoloJob` хранит предикат и не отпускает его в `finished()`: ненаблюдённый
  `Failed` идёт к ответу микротаской позже.
- `_SoloJobObserver.onUnanswered` спрашивает предикат задачи и при `true`
  возвращается, не зовя `Solo.onUnanswered`. Переопределение `onUnanswered`
  в контроллере отвеченную ошибку не слышит.
- `_SoloJobObserver.onError` заменяет `answered` на `never` для такой ошибки
  до обоих вызовов. Прототип заменял только `answered`; `later` — правка
  к реализации.

Предикат зовётся на одну ошибку до двух раз — в `onError` и в ответе — и должен
быть проверкой типа, без побочных эффектов; dartdoc говорит это. Бросивший
предикат — ошибка не отвечена: ядро шлёт её в зону, а потом то, что бросил
предикат, как с бросившим ответчиком. В `onError` бросок предиката ловится
и значение `answer` остаётся прежним. Этого прототип не проверял.

### Зонд

Наблюдатель записывает `onError`, `unansweredHandler` — что дошло до ответа.
У контроллера `keepWhile: (state) => state is! Other`, `ifFailed` пишет
`Failure(error)`, `answers: (e) => e is ApiError`; задача выброшена.

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

## Что ломается

Новый именованный параметр у `@protected` методов ломает подкласс, который их
переопределяет: `OpenSolo` в тестах — такой подкласс. Кто открывает операции
так же, получит ошибку компиляции. Выпуск — 0.6.0, минорный и так ломающий
из-за пола SDK; в CHANGELOG `solo` пункт назван ломающим для переопределений.

Поведение старого кода не меняется: без `answers` маршрут прежний.

## Документы

- dartdoc `job`, `enqueue`, `collect`, `accumulate`: абзац об `answers`;
  `Solo.onUnanswered`, «What comes here»: отвеченное задачей сюда не приходит;
  `Solo.onError`: значение `never` для отвеченного.
- `packages/solo/doc/errors.md`, «Handled and unhandled failures»: после
  «Observing the outcome» — решение для задачи, которая знает свои ожидаемые
  ошибки. Пример там бросает `StateError('no network')`, тип, который в Dart
  означает баг; с `answers: (e) => e is StateError` замолчали бы и баги.
  Примеры страниц, где провал ожидаем, получают свой тип исключения —
  `ApiException` или подобный, имя — в плане.
- `packages/solo/doc/state.md`, «The handlers»: фраза «does not mark the
  outcome as handled» получает продолжение про `answers`.
- `packages/solo/doc/reference.md`, «Parameters of a job»: новый параметр.
- `packages/solo/doc/testing.md`, «A failure nobody read»: `answers` — вторая
  форма рядом с `ignoreFailure()`, для задачи, которая знает свои ошибки.
- README `solo`, быстрый старт: `load` с `answers`, абзац о ненаблюдённом
  `Failed` — с ним.
- Переводы всех перечисленных, CHANGELOG `solo` и его перевод.
- `docs/settled.md`, пункт 44: пересмотр, ниже.

Стенды `snippets` берут код `vs-bloc.md` и `accumulation.md`; затронуты ли они,
решит план.

## Пересмотр пункта 44

Правило «`ifFailed` не наблюдает исход» остаётся: без `answers` всё по-старому.
Меняется вторая половина: ожидаемый провал от бага отделяет не только ответчик
приложения, но и сама задача, когда назвала тип. Пункт переписывается тем же
коммитом, что и реализация, с датой и именем этой записи.

## Вопросы владельцу

1. **Имя.** `answers` — от «answer for an error» в словаре страницы ошибок;
   читается «отвечает за то, на что предикат сказал да». Другие: `expects`
   (ожидаемые ошибки), `ifFailedAnswers` (привязка к `ifFailed` в имени).
   Рекомендую `answers`.
2. **`answers` только вместе с `ifFailed`.** Рекомендую да: отвечена ошибка,
   которую показало состояние; без `ifFailed` это молчаливое `ignoreFailure()`
   на уровне задачи. Если нет — задача вроде `save` из README `flutter_solo`
   могла бы объявить ожидаемые ошибки без состояния, пункт 45 это не задевает.
3. **Охват.** Рекомендую все ошибки задачи, раздел «Что считается отвеченным».
   Узкий вариант — только исход и провал тела под отменой; тогда поздний провал
   `abandonable` с тем же типом пойдёт к ответчику.

## Код зонда

Файл в `packages/solo/test/` на прототипе из раздела «Устройство».

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
        answers: (e) => e is ApiError,
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
