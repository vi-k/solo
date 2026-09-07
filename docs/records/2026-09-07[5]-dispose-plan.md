> **Состояние на 2026-09-07:** первая редакция, написана по спеке с тремя
> дополнениями и трём кругам её ревью. К исполнению не приступали; ревью
> самого плана ещё не было.
> **Что это:** план работ по уборке ресурсов задачи — стек
> `dispose`/`discard`, параметры у `wait` и `join`, `disown`, фаза уборки,
> снятие `ifCancelled` — задачами с TDD и коммитом на каждую.
> **Связанные записи:** `2026-09-07[1]-dispose-design.md` (спека и три
> дополнения; план аргументирует от неё),
> `2026-09-07[2]-dispose-design-review.md`,
> `2026-09-07[3]-dispose-addendum-review.md`,
> `2026-09-07[4]-dispose-addendum-2-review.md` (три круга ревью спеки,
> вердикт стоит у каждой находки), `2026-09-05[9]-jobs-plan.md` (план
> выноса ядра, тот же формат).

# Уборка ресурсов: план работ

> **Для агентов:** выполнять задачу за задачей по
> `superpowers:subagent-driven-development` (рекомендуется) или
> `superpowers:executing-plans`. Шаги отмечены чекбоксами.

**Цель:** заменить `ifCancelled` — три несвязанных механизма уборки —
одним: стеком регистраций, который раскручивает движок после детей и до
завершения задачи. `dispose` убирает при любом исходе, `discard` — когда
значение никому не досталось; значение из вызова регистрирует сам вызов,
остальное — члены контекста.

**Архитектура:** стек живёт на `JobBase` рядом со списком колбэков отмены;
запись несёт уборщика, признак «всегда» и, для записей от `wait`/`join`,
значение — по нему работает `disown`. Раскрутку ведёт `_execute` между
ожиданием детей и `finish`. Жизнь задачи получает четвёртую, внутреннюю
фазу — уборку: тела уже нет, исход решён, задача ещё не завершена; в ней
контекст тела закрыт, а открыты только регистрация и снятие.

**Стек:** Dart 3.13.0 (stable) локально, пол `^3.6.0`; `package:meta`,
тесты на `package:test` и `package:fake_async`; Flutter 3.47.0 для
`flutter_solo`.

**Спецификация:** `docs/records/2026-09-07[1]-dispose-design.md` вместе с
тремя дополнениями в её конце. План аргументирует от неё; исполнитель
читает обе записи. Правило чтения спеки: где дополнение расходится с
основным текстом, верно дополнение; где дополнения расходятся между собой,
верно позднейшее. Ссылки вида «спека, дополнение 3» — на неё.

## Когда это делать

До публикации пакетов на pub.dev. Причина в `docs/handoff.md`: работа
меняет публичное API обоих пакетов, а опубликовать `ifCancelled` и снять
его следующим релизом — значит сломать тех, кто успел им воспользоваться.

Публикация в план не входит: это отдельная связка по правилам `AGENTS.md`,
только по отдельному запросу владельца.

## Глобальные ограничения

- Пол SDK во всех пакетах — `environment: sdk: ^3.6.0`. Ничего из языка
  новее 3.6.
- Зависимости не выше пинов Flutter на полу SDK: рантайм `meta: ^1.15.0`;
  dev `fake_async: ^1.3.1`, `test: ^1.26.3`, `lints: ^5.1.1`.
- Ядро без Flutter и без зависимостей, кроме `meta`.
- `dart analyze` без предупреждений и info; `dart test` зелёный в
  `packages/jobs` и `packages/solo`, `flutter test` — в
  `packages/flutter_solo`, `dart test` из `packages/solo/example/`.
- Публичные документы по-английски, записи и общение — по-русски.
  `README.ru.md` правится тем же коммитом, что оригинал; сверка —
  `python3 tool/check_translations.py` из корня.
- Строки кода до 80 колонок, одинарные кавычки, завершающие запятые,
  поля выше конструктора.
- Асинхронность в тестах — только `FakeAsync`, время сдвигается явно.
- Один коммит — одна задача, вместе с её тестами и документами.

## Решения, принятые в плане сверх спеки

1. **Порядок задач.** Сначала стек и раскрутка (задачи 1–2), потом фаза и
   запреты (3), потом значение из вызова и снятие `ifCancelled` (4–5).
   Так каждая задача оставляет дерево зелёным: `ifCancelled` живёт рядом
   со стеком две задачи и уходит целиком в 4 и 5.
2. **Имена внутренних членов.** `_Cleanup` — запись стека; `_cleanups` —
   список; `_bodyEnded`, `_disposing` — флаги фазы; `bodyEnded`,
   `isDisposing` — их защищённые геттеры; `throwIfDisposing` — проверка
   для чтений. Спека называет только публичные имена, эти выбраны здесь.
3. **Где `solo` берёт фазу.** `_SoloJob` заводит приватные обёртки
   `_bodyEnded` и `_isDisposing` над защищёнными геттерами: `SoloBase` —
   не наследник задачи, и `@protected` до него не дотягивается. Тот же
   приём, что у `_cancelWith` и `_rejectKeep`.
4. **`each` не трогаем.** Спека, раздел «Почему не другие формы»:
   переезд `each` на стек — отдельный вопрос.

## Карта файлов

**Ядро, `packages/jobs`:**

- `lib/src/job_base.dart` — запись стека `_Cleanup`, список, флаги фазы,
  раскрутка в `_execute`, заполнение `_pendingCancel`, строка `debug` у
  прямого `finish`, снятие `_ifCancelled`.
- `lib/src/job_context.dart` — `onDispose`, `onDiscard`, `disown` в
  интерфейсе и в основе; `throwIfDisposing`; фаза в `throwIfFinished`;
  `dispose`/`discard` у `wait` и `join` вместо `ifCancelled`; ветка
  позднего значения.
- `test/cleanup_test.dart` (создать) — стек, порядок, ожидание, второй
  проход.
- `test/disposal_phase_test.dart` (создать) — запреты фазы и что в ней
  легально.
- `test/late_value_test.dart` — переписывается на новый API.
- `test/waiting_test.dart` — `ifCancelled` у `wait`/`join` меняется на
  `dispose`/`discard`.
- `README.md`, `README.ru.md`, `CHANGELOG.md`, `example/example.dart`.

**Надстройка, `packages/solo`:**

- `lib/src/solo_base.dart` — снятие проброса `ifCancelled` в `job` и
  `run`; `_reevaluate` пропускает задачу после конца тела.
- `lib/src/job.dart` — снятие `ifCancelled` у `_SoloJob`; приватные
  обёртки фазы.
- `lib/src/job_context.dart` — `state`, `stateAs`, `check` закрыты в
  уборке.
- `test/late_value_test.dart`, `test/wait_test.dart`, `test/join_test.dart`
  — на новый API.
- `test/disposal_test.dart` (создать) — запреты и правила в уборке.
- `README.md`, `README.ru.md`, `CHANGELOG.md`.

**Репозиторий:** `docs/architecture.md` (инварианты 2, 3, 8, 9),
`docs/handoff.md`.

---

## Фаза A. Ядро

### Задача 1. Стек уборки: `onDispose`, `onDiscard` и раскрутка

Спека, разделы «Решение» и «Когда стек раскручивается». Стек и его
раскрутка появляются рядом с сегодняшним `ifCancelled` у задачи: тот
остаётся до задачи 5, и обе уборки работают одновременно.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart` (запись, список,
  раскрутка в `_execute:569-593`), `lib/src/job_context.dart` (интерфейс
  `JobContext:14-183`, основа `JobContextBase:185+`)
- Создать: `packages/jobs/test/cleanup_test.dart`

**Интерфейсы:** даёт `void Function() onDispose(FutureOr<void> Function()
disposer)` и `void Function() onDiscard(FutureOr<void> Function()
disposer)` у `JobContext`; защищённый `void Function()
addCleanup(FutureOr<void> Function() disposer, {required bool always,
Object? value})` у `JobContextBase` — им же будут пользоваться `wait` и
`join` в задаче 4.

- [ ] **Шаг 1.** Написать падающие тесты в
      `packages/jobs/test/cleanup_test.dart`:

```dart
@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  test('onDispose runs on every outcome', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDispose(() => order.add('disposed'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        // Пять миллисекунд, чтобы тело успело стартовать и
        // зарегистрировать уборщика: отмена до старта не пустила бы тело
        // вовсе, и регистрировать было бы нечего.
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(order, ['disposed'], reason: 'scenario: $scenario');
      });
    }
  });

  test('onDiscard is silent on Done and runs on the other two', () {
    for (final scenario in ['done', 'failed', 'cancelled']) {
      fakeAsync((async) {
        final order = <String>[];
        final job = Job<int>((ctx) async {
          ctx.onDiscard(() => order.add('discarded'));
          await ctx.wait(() => delay(10));
          if (scenario == 'failed') {
            throw StateError('boom');
          }
          return 1;
        })
          ..ignore();
        async.elapse(const Duration(milliseconds: 5));
        if (scenario == 'cancelled') {
          job.cancel().ignore();
        }
        async.flushTimers();
        expect(
          order,
          scenario == 'done' ? <String>[] : ['discarded'],
          reason: 'scenario: $scenario',
        );
      });
    }
  });

  test('the stack unwinds last in, first out', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => order.add('first'));
        ctx.onDiscard(() => order.add('second'));
        ctx.onDispose(() => order.add('third'));
        await ctx.wait(() => delay(10));
        throw StateError('boom');
      }).ignore();
      async.flushTimers();
      expect(order, ['third', 'second', 'first']);
    });
  });

  test('children run before the cleanup, and the outcome waits for it',
      () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.onDispose(() async {
          order.add('cleanup starts');
          await delay(50);
          order.add('cleanup ends');
        });
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) async {
              await ctx.wait(() => delay(30));
              order.add('child');
            },
          ),
        );
      });
      job.done.then((_) => order.add('finished'));
      async.flushTimers();
      expect(order, [
        'child',
        'cleanup starts',
        'cleanup ends',
        'finished',
      ]);
    });
  });

  test('an unregistered cleanup does not run, and dropping twice is safe',
      () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        final drop = ctx.onDispose(() => order.add('kept'));
        final dropTwice = ctx.onDispose(() => order.add('dropped'));
        dropTwice();
        dropTwice();
        await ctx.wait(() => delay(10));
        expect(drop, isNotNull);
      }).ignore();
      async.flushTimers();
      expect(order, ['kept']);
    });
  });

  test('a cleanup may register another one', () {
    fakeAsync((async) {
      final order = <String>[];
      Job<void>((ctx) async {
        ctx.onDispose(() {
          order.add('outer');
          ctx.onDispose(() => order.add('nested'));
        });
      }).ignore();
      async.flushTimers();
      expect(order, ['outer', 'nested']);
    });
  });

  test('an error of a cleanup goes to the observer and the rest still runs',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      final order = <String>[];
      final job = Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          ctx.onDispose(() => order.add('below'));
          ctx.onDispose(() => throw StateError('cleanup failed'));
          return 7;
        },
      );
      async.flushTimers();
      expect(order, ['below']);
      expect(errors.single, isA<StateError>());
      expect(job.outcome, isA<Done<int>>());
    });
  });
}

class _CollectingObserver extends JobObserver {
  _CollectingObserver(this.errors);

  final List<Object> errors;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}
```

- [ ] **Шаг 2.** Прогнать и убедиться, что падает.

Команда: `cd packages/jobs && dart test test/cleanup_test.dart`
Ожидание: ошибки компиляции — `onDispose` и `onDiscard` не определены.

- [ ] **Шаг 3.** Завести запись и список в `job_base.dart`. Рядом с
      `_onCancel`, полем выше конструктора:

```dart
/// One registration on the cleanup stack of a job.
///
/// [always] tells the two kinds apart: a `dispose` registration runs
/// whatever the outcome, a `discard` one only when the value reached
/// nobody. [value] is set for registrations made by `wait` and `join`,
/// and it is what `disown` looks up.
final class _Cleanup {
  _Cleanup(this.run, {required this.always, this.value});

  final FutureOr<void> Function() run;
  final bool always;
  final Object? value;
}
```

и поле `final List<_Cleanup> _cleanups = [];`

- [ ] **Шаг 4.** Добавить членов в `JobContext` (интерфейс) и
      `JobContextBase` (основа). В интерфейсе, рядом с `onCancel`:

```dart
  /// Registers [disposer] to run when the job ends, whatever the outcome.
  ///
  /// The engine unwinds the stack after the children and before the
  /// outcome, last registration first, and it waits for every disposer.
  /// Returns a function that unregisters this one; calling it twice, or
  /// after the disposer has run, is safe.
  ///
  /// A disposer runs outside the body: nothing cancels it and nothing
  /// interrupts it, so keep it short and unconditional. It must not wait
  /// for its own job — `job.done`, `job.value` and `job.cancel()` all
  /// complete after the cleanup that would be waiting for them.
  void Function() onDispose(FutureOr<void> Function() disposer);

  /// Registers [disposer] to run only if the job ends without handing its
  /// value over: cancelled, or failed.
  ///
  /// For what the body returns or hands outside; everything else — a
  /// lock, a temporary file, a subscription — takes [onDispose], or it
  /// leaks on the successful path where no test on cancellation will see
  /// it. Returns a function that unregisters it.
  void Function() onDiscard(FutureOr<void> Function() disposer);
```

в основе:

```dart
  /// Puts a registration on the cleanup stack of the owner.
  ///
  /// The public [onDispose] and [onDiscard] are this with [value] unset;
  /// `wait` and `join` pass the value they hand to the body, so that
  /// [disown] can find the registration by it.
  @protected
  void Function() addCleanup(
    FutureOr<void> Function() disposer, {
    required bool always,
    Object? value,
  }) {
    final cleanup = _Cleanup(disposer, always: always, value: value);
    _owner._cleanups.add(cleanup);
    return () => _owner._cleanups.remove(cleanup);
  }

  @override
  void Function() onDispose(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: true);

  @override
  void Function() onDiscard(FutureOr<void> Function() disposer) =>
      addCleanup(disposer, always: false);
```

- [ ] **Шаг 5.** Раскрутить стек в `_execute`, между `_awaitChildren()` и
      `finish`, до сегодняшней ветки `_ifCancelled` (она уйдёт в задаче 5):

```dart
    await _awaitChildren();
    await _unwindCleanups(_pendingCancel ?? outcome);
    // Ниже, до задачи 5, остаётся сегодняшняя ветка `_ifCancelled`
    // и вызов `finish(_pendingCancel ?? outcome)`.
```

и сам метод:

```dart
  /// Unwinds the cleanup stack, last registration first.
  ///
  /// Takes one at a time rather than a snapshot: a disposer may register
  /// another one, and that one runs too.
  Future<void> _unwindCleanups(Outcome<T> decided) async {
    while (_cleanups.isNotEmpty) {
      final cleanup = _cleanups.removeLast();
      if (!cleanup.always && decided is Done<T>) {
        continue;
      }
      try {
        await cleanup.run();
      } on Object catch (error, stackTrace) {
        notifyError(error, stackTrace);
      }
    }
  }
```

- [ ] **Шаг 6.** Прогнать сьюту ядра целиком.

Команда: `cd packages/jobs && dart test`
Ожидание: `cleanup_test.dart` зелёный, прежние 85 тестов зелёные.

- [ ] **Шаг 7.** `dart analyze` без предупреждений в `packages/jobs`.

- [ ] **Шаг 8.** Коммит.

```bash
git add packages/jobs/lib/src/job_base.dart \
        packages/jobs/lib/src/job_context.dart \
        packages/jobs/test/cleanup_test.dart
git commit -m "feat(jobs): a cleanup stack the engine unwinds"
```

### Задача 2. Граница исхода: `_pendingCancel` до раскрутки и второй проход

Спека, разделы «Отмена, пришедшая внутрь уборки», дополнение 2 («Как
именно заполняется `_pendingCancel`») и дополнение 3 («Граница „тело
кончилось“» — здесь появляется только флаг, пользуются им задачи 4 и 7).

Три вещи одной задачей, потому что они об одном моменте: движок решает
исход до раскрутки, и всё, что смотрит на исход, должно видеть решённое.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart` (`_execute:569-593`,
  `whenCancelled` дартдок `:126-136`, `isCancelled` дартдок `:107`)
- Изменить: `packages/jobs/test/cleanup_test.dart`

**Интерфейсы:** даёт защищённый `bool get bodyEnded` у `JobBase` — им
пользуются задачи 4 (позднее значение) и 7 (правила `solo`).

- [ ] **Шаг 1.** Дописать падающие тесты в `test/cleanup_test.dart`:

```dart
  test('a cancellation arriving during the cleanup still discards', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        ctx.onDiscard(() => order.add('discarded'));
        ctx.onDispose(() async {
          order.add('slow starts');
          await delay(100);
          order.add('slow ends');
        });
        return 7;
      })
        ..ignore();
      // Уборка идёт: медленный уборщик снят со стека первым и держит
      // задачу; отмена приходит внутрь него, когда исход был `Done`.
      async.elapse(const Duration(milliseconds: 50));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['slow starts', 'slow ends', 'discarded']);
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('isCancelled tells the truth inside a cleanup', () {
    fakeAsync((async) {
      final seen = <bool>[];
      Job<void>((ctx) async {
        ctx.onDispose(() => seen.add(ctx.job.isCancelled));
        await ctx.wait(() => delay(10));
        // Тело бросает отмену само: пометки не было, и до этой задачи
        // `isCancelled` в уборке врал.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      }).ignore();
      async.flushTimers();
      expect(seen, [true]);
    });
  });

  test('whenCancelled closes before the first cleanup', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.onDispose(() => order.add('cleanup'));
        await ctx.wait(() => delay(10));
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      job.whenCancelled.then((_) => order.add('whenCancelled'));
      async.flushTimers();
      expect(order, ['whenCancelled', 'cleanup']);
    });
  });

  test('a wait the body walked away from gets no error of its own', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<void>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          // Тело не дожидается своего же ожидания и бросает отмену сама:
          // колбэки гонки не должны побежать от заполнения
          // `_pendingCancel`.
          unawaited(ctx.wait(() => delay(50)));
          await ctx.wait(() => delay(10));
          throw Cancelled.by(
            reason: CancelReason.manual,
            started: true,
            stackTrace: StackTrace.current,
          );
        },
      ).ignore();
      async.flushTimers();
      expect(errors, isEmpty);
    });
  });

  test('cancelling a parent that waits for children still cascades', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<void>((ctx) async {
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) async {
              ctx.onCancel(() => order.add('child cancelled'));
              await ctx.wait(() => delay(100));
            },
          ),
        )..ignore();
        await ctx.wait(() => delay(10));
        // Тело кончилось своей отменой, а дети ещё бегут: внешний
        // `cancel()` обязан дотянуться до ребёнка.
        throw Cancelled.by(
          reason: CancelReason.manual,
          started: true,
          stackTrace: StackTrace.current,
        );
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(order, ['child cancelled']);
    });
  });
```

```dart
  test('a section the body walked away from holds the cancellation', () {
    fakeAsync((async) {
      final order = <String>[];
      final job = Job<int>((ctx) async {
        ctx.onDiscard(() => order.add('discarded'));
        // Ошибка тела: секцию не дождались, глубина осталась ненулевой.
        // Движок этого не чинит — тест фиксирует, что придержанная
        // отмена в уборку не приходит и `Done` уезжает отменившему.
        unawaited(ctx.uncancellable(() => delay(100)));
        await ctx.wait(() => delay(10));
        return 1;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 20));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(order, isEmpty);
    });
  });
```

Импорт `dart:async` для `unawaited` — вверху файла.

- [ ] **Шаг 2.** Прогнать и убедиться, что падают тесты про `isCancelled`,
      `whenCancelled` и второй проход, а два последних — зелёные
      (сегодняшнее поведение, они регрессионные).

Команда: `cd packages/jobs && dart test test/cleanup_test.dart`

- [ ] **Шаг 3.** Переписать хвост `_execute`:

```dart
    // Тело кончилось: с этого момента значение, пришедшее из брошенного
    // вызова, до тела уже не доедет — задачи 4 и 7 смотрят на этот флаг.
    _bodyEnded = true;
    await _awaitChildren();
    // Исход решён. Отмену кладём сырым присваиванием: `_markCancelled`
    // погнал бы колбэки `onCancel` и завершил бы ошибкой ожидания,
    // которые тело бросило, — сегодня они тихо получают значение.
    // После детей, а не в `catch`: до этого `cancelWith` обязан
    // каскадировать на детей, а заполненный `_pendingCancel` его
    // останавливает.
    if (outcome is Cancelled) {
      _pendingCancel ??= outcome;
      if (!_cancelled.isCompleted) {
        _cancelled.complete();
      }
    }
    _disposing = true;
    await _unwindCleanups(outcome);
    _disposing = false;
    finish(_pendingCancel ?? outcome);
```

Поля рядом с `_pendingCancel`:

```dart
  bool _bodyEnded = false;
  bool _disposing = false;
```

и защищённые геттеры рядом с `status`:

```dart
  /// Whether the body has ended — returned or thrown.
  ///
  /// From this moment a value coming out of a call the body walked away
  /// from can no longer reach it, and the rules of a domain have nothing
  /// left to guard.
  @protected
  bool get bodyEnded => _bodyEnded;

  /// Whether the engine is unwinding the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, but the job has not
  /// finished: `isFinished` is still `false`.
  @protected
  bool get isDisposing => _disposing;
```

- [ ] **Шаг 4.** Второй проход в `_unwindCleanups` — переписать метод
      задачи 1 на живое условие и отложенный список:

```dart
  /// Unwinds the cleanup stack, last registration first.
  ///
  /// Takes one at a time rather than a snapshot: a disposer may register
  /// another one, and that one runs too. The condition of a `discard`
  /// registration is read when it is taken off the stack, from the
  /// outcome as it stands then — a cancellation may arrive into the
  /// unwinding itself, and the ones it passed over run in a second pass.
  Future<void> _unwindCleanups(Outcome<T> outcome) async {
    final skipped = <_Cleanup>[];
    while (_cleanups.isNotEmpty) {
      final cleanup = _cleanups.removeLast();
      if (!cleanup.always && (_pendingCancel ?? outcome) is Done<T>) {
        skipped.add(cleanup);
        continue;
      }
      await _runCleanup(cleanup);
    }
    while (skipped.isNotEmpty && (_pendingCancel ?? outcome) is! Done<T>) {
      await _runCleanup(skipped.removeLast());
      while (_cleanups.isNotEmpty) {
        await _runCleanup(_cleanups.removeLast());
      }
    }
  }

  Future<void> _runCleanup(_Cleanup cleanup) async {
    try {
      await cleanup.run();
    } on Object catch (error, stackTrace) {
      notifyError(error, stackTrace);
    }
  }
```

Вызов из `_execute` — без аргумента исхода в сигнатуре не обойтись:
`await _unwindCleanups(outcome);`.

- [ ] **Шаг 5.** Поправить дартдоки: `isCancelled` — «в уборке отвечает по
      решённому исходу»; `whenCancelled` — «завершается, когда тело
      кончилось и дети дожданы, перед уборкой» вместо «когда задача
      завершится».

- [ ] **Шаг 6.** Прогнать сьюту ядра.

Команда: `cd packages/jobs && dart test`
Ожидание: всё зелёное.

- [ ] **Шаг 7.** Мутант: убрать второй проход (оба `while` после первого
      цикла) — тест «a cancellation arriving during the cleanup still
      discards» обязан покраснеть. Вернуть.

- [ ] **Шаг 8.** `dart analyze` и коммит.

```bash
git add packages/jobs/lib/src/job_base.dart \
        packages/jobs/test/cleanup_test.dart
git commit -m "feat(jobs): the outcome is decided before the stack unwinds"
```

### Задача 3. Фаза уборки: запреты и то, что в ней открыто

Спека, дополнение 2 («Контекст тела в уборке закрыт весь») и дополнение 3
(«Чтения закрыты только в уборке»). Флаг фазы завела задача 2; здесь он
начинает запрещать.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_context.dart` (`throwIfFinished`
  `:213-218`, `check` `:196`, шапка класса `:1-13`)
- Создать: `packages/jobs/test/disposal_phase_test.dart`

**Интерфейсы:** даёт защищённый `void throwIfDisposing(String action)` у
`JobContextBase` — им пользуется `solo` в задаче 6.

- [ ] **Шаг 1.** Написать падающие тесты в
      `packages/jobs/test/disposal_phase_test.dart`:

```dart
@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';

void main() {
  test('the writing members are closed during the cleanup of a Done job',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          // Исход `Done`: задача не помечена, и без проверки фазы все эти
          // вызовы прошли бы — `run` завёл бы ребёнка после того, как
          // детей уже дождались.
          ctx.onDispose(() => ctx.run(Job.deferred<void>((ctx) async {})));
          ctx.onDispose(() => ctx.wait(() => delay(1)));
          ctx.onDispose(() => ctx.join(() => delay(1)));
          ctx.onDispose(() => ctx.uncancellable(() => delay(1)));
          ctx.onDispose(() => ctx.onCancel(() {}));
          ctx.onDispose(ctx.check);
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(errors, hasLength(6));
      expect(errors.every((e) => e is StateError), isTrue);
      expect(
        errors.every((e) => '$e'.contains('is disposing')),
        isTrue,
        reason: 'сообщение говорит про уборку, а не про завершённость',
      );
    });
  });

  test('registration and disown stay open during the cleanup', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final order = <String>[];
      Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          ctx.onDispose(() {
            ctx.onDispose(() => order.add('nested'));
            ctx.log('cleaning up');
            order.add('outer');
          });
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(order, ['outer', 'nested']);
      expect(errors, isEmpty);
    });
  });

  test('a cancellation from a child inside a cleanup is its own error',
      () {
    fakeAsync((async) {
      final errors = <Object>[];
      final job = Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          final child = ctx.run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(100)),
            ),
          );
          ctx.onDispose(() async {
            // Уборщик сам решил ждать чужого исхода: ребёнка увёл каскад
            // от родителя, и его отмена — собственная ошибка уборщика.
            await child.value;
          });
          await ctx.wait(() => delay(50));
          return 1;
        },
      )..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(errors.single, isA<Cancelled>());
    });
  });

  test('check stays legal after the job has finished', () {
    fakeAsync((async) {
      late JobContext leaked;
      final job = Job<void>((ctx) async {
        leaked = ctx;
      })
        ..ignore();
      async.flushTimers();
      expect(job.isFinished, isTrue);
      expect(leaked.check, returnsNormally);
      leaked.log('still legal');
    });
  });
}

class _CollectingObserver extends JobObserver {
  _CollectingObserver(this.errors);

  final List<Object> errors;

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) =>
      errors.add(error);
}
```

- [ ] **Шаг 2.** Прогнать и убедиться, что первый тест падает (вызовы
      проходят, ошибок нет), а третий зелёный.

Команда: `cd packages/jobs && dart test test/disposal_phase_test.dart`

- [ ] **Шаг 3.** Ввести проверку фазы в `job_context.dart`:

```dart
  /// Throws [StateError] if the job has finished: a context that outlived
  /// its job neither writes nor starts anything. Also throws while the
  /// engine unwinds the cleanup stack — see [throwIfDisposing].
  @protected
  void throwIfFinished(String action) {
    if (_owner.isFinished) {
      throw StateError('$_owner has already finished, cannot $action');
    }
    throwIfDisposing(action);
  }

  /// Throws [StateError] while the engine unwinds the cleanup stack.
  ///
  /// The body is gone and the outcome is decided, so nothing of the body
  /// runs any more: a disposer takes what it needs from its closure and
  /// asks `job.isCancelled` about the outcome. Reads go through this one
  /// alone — after the job has finished they stay legal, as they were.
  @protected
  void throwIfDisposing(String action) {
    if (_owner.isDisposing) {
      throw StateError('$_owner is disposing, cannot $action');
    }
  }
```

и `check`:

```dart
  @override
  void check() {
    throwIfDisposing('check');
    throwIfCancelled();
  }
```

- [ ] **Шаг 4.** Поправить шапку `JobContext`: перечень членов, которые не
      отказывают отменённой задаче, — `log`, `job`, `onDispose`,
      `onDiscard`, `disown` (последний появится в задаче 4; здесь пишем
      два); абзац про переживший задачу контекст дополнить фразой о фазе
      уборки: в ней закрыто всё, кроме `log`, `job` и регистрации.

- [ ] **Шаг 5.** Прогнать сьюту ядра и `packages/solo`.

Команда: `cd packages/jobs && dart test` и `cd packages/solo && dart test`
Ожидание: всё зелёное. Если в `solo` что-то краснеет — это чтение
контекста из `ifCancelled`, и это задача 6; здесь такого быть не должно.

- [ ] **Шаг 6.** Мутант: убрать `throwIfDisposing` из `throwIfFinished` —
      первый тест обязан покраснеть на пяти пишущих членах. Вернуть.

- [ ] **Шаг 7.** `dart analyze` и коммит.

```bash
git add packages/jobs/lib/src/job_context.dart \
        packages/jobs/test/disposal_phase_test.dart
git commit -m "feat(jobs): the body's context is closed while cleaning up"
```

### Задача 4. Значение из вызова: `dispose`, `discard` и `disown`

Спека, разделы «Значение пришло из вызова» и «Снятие регистрации»,
дополнение 2 («Позднее значение убирают без условия по исходу») и
дополнение 3 («Граница „тело кончилось“»). Здесь же `ifCancelled` уходит
у `wait` и `join`.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_context.dart` (`join:262-278`,
  `wait:327-336`, `_race:338-386`, интерфейс)
- Изменить: `packages/jobs/test/waiting_test.dart`,
  `packages/solo/test/wait_test.dart`, `packages/solo/test/join_test.dart`
- Изменить: `packages/jobs/test/cleanup_test.dart` (новые тесты)

**Интерфейсы:** `wait` и `join` получают `{FutureOr<void> Function(T
value)? dispose, FutureOr<void> Function(T value)? discard}` вместо
`ifCancelled`; `JobContext` получает `bool disown(Object value)`.

- [ ] **Шаг 1.** Дописать падающие тесты в `test/cleanup_test.dart`:

```dart
  test('join keeps the value and cleans it up at the end', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(
          () async {
            await delay(10);
            return 'db';
          },
          discard: closed.add,
        );
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 15));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db'], reason: 'значение доехало, ушло в стек');
      expect(job.outcome, isA<Cancelled>());
    });
  });

  test('join cleans up on the spot when the cancellation beat the value',
      () {
    fakeAsync((async) {
      final closed = <String>[];
      final order = <String>[];
      final job = Job<void>((ctx) async {
        try {
          await ctx.join(
            () async {
              await delay(50);
              return 'db';
            },
            discard: (value) async {
              await delay(20);
              closed.add(value);
            },
          );
        } on Cancelled {
          order.add('body sees the cancellation');
          rethrow;
        }
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 10));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['db']);
      expect(order, ['body sees the cancellation']);
    });
  });

  test('a value that arrives after the body is cleaned up whatever the '
      'outcome', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<int>((ctx) async {
        // Тело не дожидается своего вызова: значение приедет, когда тела
        // уже нет, — до него оно не доехало, значит убирают без условия.
        unawaited(
          ctx.join(
            () async {
              await delay(50);
              return 'db';
            },
            discard: closed.add,
          ),
        );
        // Ребёнок держит задачу живой, пока значение едет.
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) => ctx.wait(() => delay(80)),
          ),
        )..ignore();
        return 1;
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(closed, ['db'], reason: 'на Done тоже');
    });
  });

  test('an abandoned join is silent on the successful path', () {
    fakeAsync((async) {
      final errors = <Object>[];
      Job<int>(
        observer: _CollectingObserver(errors),
        (ctx) async {
          unawaited(
            ctx.join(
              () async {
                await delay(50);
                return 'db';
              },
              discard: (_) {},
            ),
          );
          ctx.run(
            Job.deferred<void>(
              key: 'child',
              (ctx) => ctx.wait(() => delay(80)),
            ),
          )..ignore();
          return 1;
        },
      ).ignore();
      async.flushTimers();
      expect(errors, isEmpty, reason: 'ни StateError, ни отмены');
    });
  });

  test('disown drops the top registration for that value', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(() async => 'db', dispose: closed.add);
        expect(ctx.disown(db), isTrue);
        expect(ctx.disown(db), isFalse, reason: 'снимать больше нечего');
        expect(ctx.disown('someone else'), isFalse);
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Done<String>>());
      expect(closed, isEmpty);
    });
  });

  test('disown does not see a registration made by a member', () {
    fakeAsync((async) {
      final closed = <String>[];
      Job<void>((ctx) async {
        const db = 'db';
        ctx.onDispose(() => closed.add(db));
        expect(ctx.disown(db), isFalse);
      }).ignore();
      async.flushTimers();
      expect(closed, ['db'], reason: 'запись члена disown не тронул');
    });
  });

  test('disown after the job has finished is a StateError', () {
    fakeAsync((async) {
      late JobContext leaked;
      Job<void>((ctx) async => leaked = ctx).ignore();
      async.flushTimers();
      expect(() => leaked.disown('anything'), throwsStateError);
    });
  });

  test('a parameter and a member on one value both run', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final db = await ctx.join(
          () async => 'db',
          discard: (value) => closed.add('by parameter'),
        );
        // Документированное поведение: две независимые записи, и снятие
        // члена снимает только свою. Так делать нельзя — тест держит
        // границу, о которой говорит дартдок.
        ctx.onDiscard(() => closed.add('by member'))();
        await ctx.wait(() => delay(10));
        return db;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 5));
      job.cancel().ignore();
      async.flushTimers();
      expect(closed, ['by parameter']);
    });
  });

  test('passing both dispose and discard is an ArgumentError', () {
    fakeAsync((async) {
      final job = Job<void>((ctx) async {
        await ctx.join(
          () async => 'db',
          dispose: (_) {},
          discard: (_) {},
        );
      })
        ..ignore();
      async.flushTimers();
      expect(job.outcome, isA<Failed>());
      expect((job.outcome! as Failed).error, isA<ArgumentError>());
    });
  });
```

- [ ] **Шаг 2.** Прогнать: падают все семь.

Команда: `cd packages/jobs && dart test test/cleanup_test.dart`

- [ ] **Шаг 3.** Переписать `join` в `JobContextBase`:

```dart
  @override
  Future<T> join<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('join');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = await action();
    if (_owner.bodyEnded) {
      // Тело кончилось, пока вызов был в полёте: значение до него не
      // доехало. Вызов кончается здесь и в `check` не заходит — в фазе
      // уборки тот бросил бы `StateError` в future, которого никто не
      // ждёт, и Dart отдал бы его в зону на успешном пути.
      await _keep(dispose, discard, result);
      final pending = pendingCancel;
      if (pending != null) {
        throw pending;
      }
      return result;
    }
    try {
      check();
    } on Cancelled {
      final disposer = dispose ?? discard;
      if (disposer != null) {
        await _dispose(disposer, result);
      }
      rethrow;
    }
    await _keep(dispose, discard, result);
    return result;
  }

  void _oneCleanupOnly(Object? dispose, Object? discard) {
    if (dispose != null && discard != null) {
      throw ArgumentError('pass either dispose or discard, not both');
    }
  }

  /// Puts the cleanup of [value] where it belongs.
  ///
  /// While the body can still use the value, on the stack — as `dispose`
  /// or as `discard`, whichever was given. Once the body has ended the
  /// value reached nobody, so the registration is unconditional; and if
  /// the job has finished there is no stack left, so the disposer runs on
  /// the spot and nobody waits for it.
  Future<void> _keep<T>(
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
    T value,
  ) async {
    final disposer = dispose ?? discard;
    if (disposer == null) {
      return;
    }
    if (_owner.isFinished) {
      await _dispose(disposer, value);
      return;
    }
    addCleanup(
      () => disposer(value),
      always: dispose != null || _owner.bodyEnded,
      value: value,
    );
  }
```

- [ ] **Шаг 4.** Переписать `wait` и `_race`:

```dart
  @override
  Future<T> wait<T>(
    FutureOr<T> Function() action, {
    FutureOr<void> Function(T value)? dispose,
    FutureOr<void> Function(T value)? discard,
  }) async {
    throwIfFinished('wait');
    _oneCleanupOnly(dispose, discard);
    check();
    final result = action();
    if (result is! Future<T>) {
      await _keep(dispose, discard, result);
      return result;
    }
    return _race(result, dispose, discard);
  }
```

В `_race` — та же пара вместо `ifCancelled`, и обе ветки `forward`:

```dart
    Future<void> forward() async {
      try {
        final value = await future;
        if (completer.isCompleted) {
          // Значение до тела не доехало: убираем без условия по исходу,
          // и ждать эту уборку некому.
          final disposer = dispose ?? discard;
          if (disposer != null) {
            await _dispose(disposer, value);
          }
        } else {
          await _keep(dispose, discard, value);
          completer.complete(value);
        }
      } on Object catch (error, stackTrace) {
        ...
```

- [ ] **Шаг 5.** Добавить `disown` — в интерфейс `JobContext`:

```dart
  /// Drops the cleanup registered for [value] by [wait] or [join].
  ///
  /// Returns whether anything was dropped. Registrations made by
  /// [onDispose] and [onDiscard] carry no value and are invisible here —
  /// they are dropped by the function those members return; an unknown
  /// value is not an error. With two registrations for one value the top
  /// one goes, one per call.
  ///
  /// Stands next to the hand-over: before it, when the hand-over is
  /// synchronous and may throw after its own work (`emit` of `solo`), and
  /// inside the same uncancellable section, when it is asynchronous.
  bool disown(Object value);
```

и в основу:

```dart
  @override
  bool disown(Object value) {
    throwIfFinished('disown');
    final cleanups = _owner._cleanups;
    for (var i = cleanups.length - 1; i >= 0; i--) {
      if (identical(cleanups[i].value, value)) {
        cleanups.removeAt(i);
        return true;
      }
    }
    return false;
  }
```

`throwIfFinished` здесь не запрещает уборку: `disown`, как `onDispose` и
`onDiscard`, в фазе открыт — значит в нём стоит только проверка
завершённости, без `throwIfDisposing`. Заменить на явную проверку:

```dart
    if (_owner.isFinished) {
      throw StateError('$_owner has already finished, cannot disown');
    }
```

То же самое сделать в `addCleanup` — регистрация в фазе уборки законна.

- [ ] **Шаг 6.** Перевести на новые имена тесты, которые звали
      `ifCancelled` у `wait`/`join`: `packages/jobs/test/waiting_test.dart`,
      `packages/solo/test/wait_test.dart`,
      `packages/solo/test/join_test.dart`. `ifCancelled:` → `discard:` там,
      где значение уходило наружу, и `dispose:` там, где ресурс держат до
      конца задачи. Смысл тестов не менять.

- [ ] **Шаг 7.** Прогнать обе сьюты.

Команда: `cd packages/jobs && dart test`, затем
`cd packages/solo && dart test`
Ожидание: всё зелёное.

- [ ] **Шаг 8.** Мутант: убрать ветку `_owner.bodyEnded` из `join` — тест
      «a value that arrives after the body…» обязан покраснеть (значение
      ляжет условной записью и на `Done` пропадёт), а «an abandoned join is
      silent…» — поймать `StateError`. Вернуть.

- [ ] **Шаг 9.** `dart analyze` в обоих пакетах и коммит.

```bash
git add packages/jobs/lib/src/job_context.dart \
        packages/jobs/test/cleanup_test.dart \
        packages/jobs/test/waiting_test.dart \
        packages/solo/test/wait_test.dart \
        packages/solo/test/join_test.dart
git commit -m "feat(jobs)!: wait and join register the cleanup of a value"
```

### Задача 5. `ifCancelled` уходит у задачи, прямой `finish` пишет строку

Спека, раздел «Что уходит» и дополнение 3 («Ещё четыре уточнения», про
`finish`). После этой задачи слова `ifCancelled` в дереве не остаётся.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart` (`Job:44-83`,
  `Job.deferred:60-82`, конструктор `JobBase:230-241`, поле `_ifCancelled`
  `:193`, ветка в `_execute`, `finish:467`), `lib/src/job_context.dart`
  (дартдок `finish` в части про `ifCancelled`)
- Изменить: `packages/solo/lib/src/solo_base.dart` (`job:97`, `run:200`),
  `packages/solo/lib/src/job.dart` (`:28`)
- Изменить: `packages/jobs/test/late_value_test.dart`,
  `packages/solo/test/late_value_test.dart`,
  `packages/jobs/test/debug_test.dart`

- [ ] **Шаг 1.** Переписать `packages/jobs/test/late_value_test.dart` на
      стек: `ifCancelled: closed.add` у конструктора превращается в
      `ctx.onDiscard(() => closed.add(resource))` сразу после того, как
      значение получено. Смысл каждого теста сохранить: поздний результат,
      порядок «дети → уборка → исход», ошибка уборщика в наблюдателя.
      Например, первый:

```dart
  test('a value returned after cancellation goes to the disposer', () {
    fakeAsync((async) {
      final closed = <String>[];
      final job = Job<String>((ctx) async {
        final resource = await ctx.join(() async {
          await delay(10);
          return 'db';
        });
        ctx.onDiscard(() => closed.add(resource));
        ctx.run(
          Job.deferred<void>(
            key: 'child',
            (ctx) => ctx.wait(() => delay(100)),
          ),
        )..ignore();
        return resource;
      })
        ..ignore();
      async.elapse(const Duration(milliseconds: 30));
      job.cancel().ignore();
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(closed, ['db']);
    });
  });
```

- [ ] **Шаг 2.** То же в `packages/solo/test/late_value_test.dart`:
      `ifCancelled:` у `solo.run` уходит, регистрация переезжает в тело.

- [ ] **Шаг 3.** Дописать тест в `packages/jobs/test/debug_test.dart`:

```dart
  test('finish called by hand tells the debug tracer about the stack', () {
    fakeAsync((async) {
      final lines = <String>[];
      JobBase.debug = lines.add;
      addTearDown(() => JobBase.debug = null);
      final job = ProbeJob<void>((ctx) async {
        ctx.onDispose(() {});
        await ctx.wait(() => delay(100));
      })..launch();
      async.elapse(const Duration(milliseconds: 10));
      // Движок домена завершает задачу сам: детей он не ждёт и стек не
      // раскручивает, поэтому об оставшихся уборщиках должна остаться
      // строка.
      job
        ..drop(const Done(null))
        ..ignore();
      async.flushTimers();
      expect(
        lines.where((line) => line.contains('cleanups pending')),
        hasLength(1),
      );
    });
  });
```

`ProbeJob` — уже готовый хелпер `test/support/probe_job.dart`: `launch()`
стартует задачу как движок домена, `drop(outcome)` завершает её напрямую.

- [ ] **Шаг 4.** Прогнать: падает тест на строку `debug`, остальные
      компилируются (в них `ifCancelled` уже нет).

- [ ] **Шаг 5.** Снять `ifCancelled` из ядра: параметр у `Job`,
      `Job.deferred` и конструктора `JobBase`, поле `_ifCancelled`, ветка в
      `_execute` (в `_execute` остаётся только `_unwindCleanups`). В
      `finish` добавить строку:

```dart
    if (_cleanups.isNotEmpty) {
      _debug(
        () => '$this finished with ${_cleanups.length} cleanups pending',
      );
    }
```

и дописать в дартдок `finish`: прямое завершение не ждёт детей и не
раскручивает стек — ресурсы тела остаются на месте; отменять надо через
`cancelWith`.

- [ ] **Шаг 6.** Снять проброс в `solo`: параметр `ifCancelled` у
      `SoloBase.job` и `SoloBase.run`, `required super.ifCancelled` в
      `packages/solo/lib/src/job.dart`.

- [ ] **Шаг 7.** Убедиться, что слова не осталось:

Команда: `grep -rn "ifCancelled" packages/*/lib packages/*/test
packages/*/example`
Ожидание: пусто.

- [ ] **Шаг 8.** Прогнать обе сьюты, `dart analyze` в обоих пакетах,
      `flutter test` в `packages/flutter_solo` (он реэкспортирует ядро).

- [ ] **Шаг 9.** Коммит.

```bash
git add packages/jobs/lib packages/jobs/test \
        packages/solo/lib packages/solo/test
git commit -m "feat(jobs)!: the job's ifCancelled gives way to the stack"
```

---

## Фаза B. `solo`

### Задача 6. Чтения `solo` закрыты в уборке

Спека, дополнение 2 («Контекст тела в уборке закрыт весь») и дополнение 3
(«Чтения закрыты только в уборке»). `emit` закрывается сам — он идёт через
`throwIfFinished`, а тот с задачи 3 смотрит на фазу; чтения `solo` идут
через `_checkedState` и своей проверки не имеют.

**Файлы:**
- Изменить: `packages/solo/lib/src/job_context.dart` (`check:45`,
  `_checkedState:47-62`, `state:65`, `stateAs:68-81`)
- Создать: `packages/solo/test/disposal_test.dart`

- [ ] **Шаг 1.** Написать падающие тесты в
      `packages/solo/test/disposal_test.dart`:

```dart
@Timeout(Duration(seconds: 5))
library;

import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/run_solo.dart';
import 'support/test_state.dart';

void main() {
  test('reading the state from a disposer is a StateError, not a flip', () {
    runSolo((solo, journal, async) {
      final errors = <Object>[];
      final job = solo.run<Idle, int>(
        key: 'load',
        (ctx) async {
          ctx.onDispose(() {
            // Без запрета это чтение проверило бы правила по состоянию,
            // которое тело же и излучило, и перевернуло бы исход в
            // `Cancelled(rules)`.
            try {
              ctx.state;
            } on Object catch (error) {
              errors.add(error);
            }
          });
          await ctx.wait(() => delay(10));
          ctx.emit(const Loaded(7));
          return 7;
        },
      );
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(errors.single, isA<StateError>());
      expect('${errors.single}', contains('is disposing'));
    });
  });

  test('emit from a disposer is a StateError', () {
    runSolo((solo, journal, async) {
      final errors = <Object>[];
      final solo2 = solo..onErrorHook = errors.add;
      final job = solo2.run<Idle, int>(
        key: 'load',
        (ctx) async {
          ctx.onDispose(() => ctx.emit(const Idle()));
          return 7;
        },
      );
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(errors.single, isA<StateError>());
    });
  });

  test('check, disown and emit hand the value over in one go', () {
    runSolo((solo, journal, async) {
      final closed = <String>[];
      final job = solo.run<Idle, void>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(() async => 'db', discard: closed.add);
          // Хук ставит состояние реентерабельно из `onChange`: `emit`
          // бросит после записи, а снятие уже позади.
          ctx.check();
          ctx.disown(db);
          ctx.emit(Loaded(db.length));
        },
      );
      async.flushTimers();
      expect(closed, isEmpty, reason: 'база уехала в состояние');
      expect(job.outcome, isA<Done<void>>());
    });
  });

  test('join inside an uncancellable section breaks the pair', () {
    runSolo((solo, journal, async) {
      final rolled = <String>[];
      final job = solo.run<Idle, void>(
        key: 'load',
        (ctx) async {
          final tx = await ctx.join(() async => 'tx', dispose: rolled.add);
          await ctx.uncancellable(() async {
            // Так писать нельзя, и тест это документирует: `join` внутри
            // секции бросит после шага на отмене по правилам, и снятие
            // не состоится.
            await ctx.join(() async => delay(10));
            ctx.disown(tx);
          });
        },
      );
      async.elapse(const Duration(milliseconds: 5));
      solo.externalSetState(const Loaded(1));
      async.flushTimers();
      expect(job.outcome, isA<Cancelled>());
      expect(rolled, ['tx'], reason: 'снятие не состоялось — уборка идёт');
    });
  });

  test('reads after the job has finished are still legal', () {
    runSolo((solo, journal, async) {
      late SoloContext<TestState, Idle> leaked;
      solo.run<Idle, void>(
        key: 'load',
        (ctx) async => leaked = ctx,
      ).ignore();
      async.flushTimers();
      expect(() => leaked.state, returnsNormally);
      expect(leaked.check, returnsNormally);
    });
  });
}
```

Хук ошибок в `runSolo` — тот, что уже есть в `support/test_solo.dart`;
если поля `onErrorHook` там нет, поставить наблюдателя, как это делает
`unobserved_failure_test.dart`. Тест обязан ставить наблюдателя явно: без
него ошибка уборщика в `solo` не доходит никуда, и тест был бы зелен на
молчании.

- [ ] **Шаг 2.** Прогнать: первые два падают.

Команда: `cd packages/solo && dart test test/disposal_test.dart`

- [ ] **Шаг 3.** Закрыть чтения в `_SoloContext`:

```dart
  @override
  void check() {
    throwIfDisposing('check');
    _checkedState();
  }

  W _checkedState() {
    throwIfDisposing('read the state');
    throwIfCancelled();
    ...
  }
```

`state` и `stateAs` идут через `_checkedState`, поэтому отдельной строки
не требуют; сообщения — `'check'`, `'state'`, `'stateAs'`, значит
`_checkedState` принимает имя члена:

```dart
  W _checkedState([String action = 'state']) {
    throwIfDisposing(action);
    ...
  }
```

и `stateAs` зовёт `_checkedState('stateAs')`, `check` —
`_checkedState('check')`.

- [ ] **Шаг 4.** Прогнать сьюту `solo` целиком: 238 тестов плюс новые.

Команда: `cd packages/solo && dart test`

- [ ] **Шаг 5.** Мутант: убрать `throwIfDisposing` из `_checkedState` —
      первый тест обязан покраснеть, и исход в нём станет
      `Cancelled(rules)`. Вернуть.

- [ ] **Шаг 6.** `dart analyze` и коммит.

```bash
git add packages/solo/lib/src/job_context.dart \
        packages/solo/test/disposal_test.dart
git commit -m "feat(solo): reads are closed while the job is cleaning up"
```

### Задача 7. Правила `solo` не смотрят на задачу после конца тела

Спека, дополнение 3, раздел «Правила `solo` после конца тела задачу не
смотрят». Смена семантики: внешняя установка состояния больше не отменяет
задачу, чьё тело кончилось.

**Файлы:**
- Изменить: `packages/solo/lib/src/solo_base.dart` (`_reevaluate:393-415`),
  `packages/solo/lib/src/job.dart` (приватная обёртка)
- Изменить: `packages/solo/test/disposal_test.dart`

- [ ] **Шаг 1.** Дописать падающий тест:

```dart
  test('a state change during the cleanup no longer cancels by rules', () {
    runSolo((solo, journal, async) {
      final closed = <String>[];
      final job = solo.run<Idle, int>(
        key: 'load',
        (ctx) async {
          final db = await ctx.join(() async => 'db', discard: closed.add);
          ctx.onDispose(() async => delay(50));
          // Форма из README: рабочий тип `Idle`, последнее состояние вне
          // него, значение возвращается наружу.
          ctx.emit(const Loaded(7));
          return db.length;
        },
      );
      // Пока уборщик спит, «железо» ставит состояние: правила задачи
      // больше не держатся, но тела уже нет — стеречь нечего.
      async.elapse(const Duration(milliseconds: 10));
      solo.externalSetState(const Loaded(4));
      async.flushTimers();
      expect(job.outcome, isA<Done<int>>());
      expect(closed, isEmpty, reason: 'значение уехало вызывающему');
    });
  });
```

И второй, регрессионный, — очередь и политики уборку дожидаются:

```dart
  test('restart and externalSetState wait for the cleanup', () {
    runSolo((solo, journal, async) {
      final order = <String>[];
      solo.run<Idle, void>(
        key: 'load',
        policy: Policy.restart,
        (ctx) async {
          ctx.onDispose(() async {
            order.add('cleanup starts');
            await delay(50);
            order.add('cleanup ends');
          });
          await ctx.wait(() => delay(10));
        },
      ).ignore();
      async.elapse(const Duration(milliseconds: 15));
      // Следующая задача той же очереди стартует только после `finish`,
      // а он ждёт уборку.
      solo.run<Idle, void>(
        key: 'load',
        policy: Policy.restart,
        (ctx) async => order.add('second starts'),
      ).ignore();
      async.flushTimers();
      expect(order, ['cleanup starts', 'cleanup ends', 'second starts']);
    });
  });
```

- [ ] **Шаг 2.** Прогнать: падает — исход `Cancelled(rules)`, значение
      закрыто.

- [ ] **Шаг 3.** Завести приватную обёртку в
      `packages/solo/lib/src/job.dart`, рядом с `_cancelWith` и
      `_rejectKeep`:

```dart
  /// `bodyEnded` of the core, for `SoloBase`: `@protected` reaches inside
  /// an heir, and the controller looks at the job from the outside.
  bool get _bodyEnded => bodyEnded;
```

- [ ] **Шаг 4.** Пропустить такую задачу в `_reevaluate`:

```dart
    for (final job in _running.reversed.toList()) {
      // Тела нет — правилам нечего стеречь: они держат работу тела, а не
      // ожидание детей и не уборку. `cancel()`, `close()` и каскад
      // родителя дотягиваются до задачи по-прежнему.
      if (identical(job, except) || job.isCancelled || job._bodyEnded) {
        continue;
      }
```

- [ ] **Шаг 5.** Прогнать сьюту `solo`. Ожидание: новый тест зелёный.
      Если краснеет что-то из `scenario_*` или `start_rules_test.dart` —
      разобрать: тест мог опираться на отмену по правилам в окне детей.
      Такой тест переписать, а разбор записать в отчёт задачи.

- [ ] **Шаг 6.** Мутант: убрать `job._bodyEnded` из условия — новый тест
      обязан покраснеть. Вернуть.

- [ ] **Шаг 7.** `dart analyze` и коммит.

```bash
git add packages/solo/lib/src/solo_base.dart \
        packages/solo/lib/src/job.dart \
        packages/solo/test/disposal_test.dart
git commit -m "feat(solo)!: the rules let go of a job whose body has ended"
```

---

## Фаза C. Документы

### Задача 8. Документы и дартдоки ядра

Спека, разделы «Что правится вокруг» во всех трёх дополнениях.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart` (дартдоки `Job`,
  `Job.deferred`, `isRunning`, `JobStatus.running`, `isCancelled`,
  `whenCancelled`, `finish`), `lib/src/job_context.dart` (шапка класса,
  `check`, `wait`, `join`, `uncancellable`, `onDispose`, `onDiscard`,
  `disown`)
- Изменить: `packages/jobs/README.md`, `README.ru.md`, `CHANGELOG.md`,
  `example/example.dart`

- [ ] **Шаг 1.** Дартдоки, по одной фразе на каждый:

  - `wait` и `join` — три случая правила («не доехало — убрать здесь,
    доехало — в стек, тело кончилось — убрать без условия»); что движок
    ловит позднее значение с момента, когда узнал о конце тела, а не с
    `return`; что `unawaited` на вызове, отдающем ресурс, — ошибка тела;
    что оба параметра сразу — `ArgumentError`.
  - `check` — окно уборки: в нём `StateError`, а не `Cancelled`; цена для
    брошенного действия, которое опрашивает `check` в цикле.
  - `uncancellable` — правило пары: между шагом и `disown` не должно
    стоять ничего, что бросает отмену этой задачи, — ни член контекста, ни
    `await child.value`, ни `ctx.run`.
  - `onDispose`, `onDiscard` — уборщик не ждёт ни свою задачу, ни задачу
    своей очереди: обе ждут его.
  - `isRunning` и `JobStatus.running` — в фазе уборки оба ещё `true`.
  - `isCancelled` — в уборке отвечает по решённому исходу.

- [ ] **Шаг 2.** Переписать «Quick start» в `README.md`: он построен
      вокруг `ifCancelled` у задачи. Новая форма — та, что в спеке,
      раздел «Решение»: лок через `dispose`, база через `discard`,
      `return` без церемоний. Рядом — абзац «`discard` только для того,
      что уходит наружу».

- [ ] **Шаг 3.** Заменить `example/example.dart` на новый «Quick start»
      дословно и прогнать его.

Команда: `cd packages/jobs && dart run example/example.dart`

- [ ] **Шаг 4.** Перевести правки в `README.ru.md` и сверить.

Команда: `python3 tool/check_translations.py` из корня

- [ ] **Шаг 5.** `CHANGELOG.md` пакета: запись первого релиза
      переписывается, а не дополняется — `ifCancelled` в ней не было
      публично никогда, поэтому в описании 0.1.0 остаётся только новый
      словарь.

- [ ] **Шаг 6.** `dart doc` без предупреждений.

Команда: `cd packages/jobs && dart doc`

- [ ] **Шаг 7.** Коммит.

```bash
git add packages/jobs
git commit -m "docs(jobs): cleanup as its user sees it"
```

### Задача 9. Документы `solo`, инварианты, handoff

**Файлы:**
- Изменить: `packages/solo/README.md`, `README.ru.md`, `CHANGELOG.md`,
  `lib/src/solo_base.dart` (дартдоки `job`, `run`, `onError`)
- Изменить: `docs/architecture.md` (инварианты 2, 3, 8, 9),
  `docs/handoff.md`

- [ ] **Шаг 1.** Абзац «Taking ownership» в README `solo` переписать. В
      нём должно быть четыре вещи:

  - стек вместо `try/finally` как главная форма, `try/finally` не
    запрещён;
  - тройка `ctx.check(); ctx.disown(db); ctx.emit(Ready(db));` для
    передачи владения через состояние — и почему не секция;
  - «состояние на выходе пишут в теле»: на успехе `emit` до `return`, на
    ошибке `try/catch` с `emit` и `rethrow`, на отмене — только `onFinish`
    контроллера с `externalSetState`;
  - ошибка уборщика доходит только до `onError` и `SoloBase.observer`; без
    них уборщик, тронувший контекст, замолкает на полпути.

- [ ] **Шаг 2.** Там же — фраза про правила: после конца тела они задачу
      не смотрят, поэтому установка состояния во время уборки её не
      отменяет.

- [ ] **Шаг 3.** `docs/architecture.md`:

  - инвариант 2 — `onDispose`, `onDiscard` и `disown` в список членов,
    которые правил не смотрят; чтения в уборке бросают `StateError`;
  - инвариант 3 — правила после конца тела задачу не трогают;
  - инвариант 8 — фаза уборки: что в ней закрыто, и что чтения после
    `finish` остаются законны;
  - инвариант 9 — чинится заодно: он устарел с `439c8fb`, «отклонённая
    отмена нигде не копится» больше не так, секция её придерживает.

- [ ] **Шаг 4.** Перевод `README.ru.md` и сверка.

Команда: `python3 tool/check_translations.py` из корня

- [ ] **Шаг 5.** `docs/handoff.md`: работа сделана, что дальше — план
      перевода `scopo` (`releaseLateData` → `discard`, запись `_data` из
      ветки `Done`) и публикация.

- [ ] **Шаг 6.** Полный прогон перед коммитом: `dart analyze` и
      `dart test` в `packages/jobs` и `packages/solo`, `flutter test` в
      `packages/flutter_solo`, `dart test` из `packages/solo/example/`,
      `dart doc` в обоих пакетах, `python3 tool/check_translations.py`.

- [ ] **Шаг 7.** Коммит.

```bash
git add packages/solo docs/architecture.md docs/handoff.md
git commit -m "docs(solo): the cleanup stack as its user sees it"
```

---

## Чего в плане нет

- **Публикации.** Отдельная связка по правилам `AGENTS.md`, только по
  отдельному запросу владельца.
- **Перевода `scopo`.** Соседний репозиторий; `releaseLateData` ложится в
  `discard`, а `_data`/`_hasData` должны переехать из тела в ветку `Done`
  — это записано в `docs/handoff.md`, пункт 4 «Следующих шагов».
- **Переезда `each` на стек.** Спека прямо оставляет это отдельным
  вопросом: `each` про время жизни подписки внутри тела.
- **Второго канала для ошибок уборщиков в `solo`.** Отклонён третьим
  кругом ревью: он ломает документированное «stops there» и инвариант 4.
- **Записи бэклога «ловить ошибку брошенной футуры».** Отдельная работа,
  зона на задачу.

## Как план сверялся со спекой

По разделам спеки и трёх дополнений, каждый — в задачу:

- «Решение», два вида записи и стек → задача 1.
- «Когда стек раскручивается», второй проход, синхронный переход к
  `finish` → задача 2; там же дополнение 2 про `_pendingCancel` и
  дополнение 3 про флаг «тело кончилось».
- «Ошибки и границы уборщика», фаза → задача 3; дополнение 2 про закрытый
  контекст и дополнение 3 про объём закрытия — задачи 3 и 6.
- «Значение пришло из вызова», «Снятие регистрации», дополнение 2 про
  позднее значение, дополнение 3 про ветку `join` → задача 4.
- «Что уходит» → задача 5 (у задачи и в `solo`) и задача 4 (у `wait` и
  `join`); строка `debug` у прямого `finish` — задача 5.
- Передача владения: тройка и секция → документы, задачи 8 и 9; тест
  тройки — задача 6 (`disposal_test.dart`), тест `join` внутри секции —
  задача 4.
- «Правила `solo` после конца тела» → задача 7.
- «Что правится вокруг» и «Что добавилось в списки» всех трёх дополнений
  → задачи 8 и 9.

Тесты из списков спеки разложены так: стек, порядок, ожидание, ошибка
уборщика, вложенная уборка, снятие — задача 1; второй проход с мутантом,
`whenCancelled`, брошенное ожидание, каскад — задача 2; запреты фазы с
мутантом, чтения после `finish` — задача 3; параметры, `ArgumentError`,
`disown` в трёх видах, позднее значение в окне детей и в уборке, тишина
брошенного `join` — задача 4; поздний результат на новом API — задача 5;
чтения и `emit` из уборщика в `solo` с явным наблюдателем, тройка
`check`/`disown`/`emit` и `join` внутри секции — задача 6; внешняя
установка состояния во время уборки и очередь с `Policy.restart` — задача
7. Отдельно: двойная регистрация на одно значение, `disown` на
завершённой задаче — задача 4; `Cancelled` из `child.value` внутри
уборщика — задача 3; придержанная отмена от незакрытой секции — задача 2;
строка `debug` у прямого `finish` — задача 5.
