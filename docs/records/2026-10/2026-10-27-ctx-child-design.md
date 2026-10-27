> **Состояние на 2026-10-27:** дизайн написан, ждёт ревью на Opus и codex.
> **Что это:** дизайн `ctx.child` — фабрики ребёнка, которого примет движок
> контекста, для кода, которому передан только `JobContext`.
> **Связанные записи:** `2026-10-06-job-timeout-design.md` — срок задачи
> и ребёнок со сроком; `2026-10-19-child-job-report.md` — `ctx.run` берёт
> `ChildJob<T>`.

# `ctx.child`: ребёнок, которого примет любой движок

## Откуда

Заявка сессии HisBible, 2026-10-27. Общий код приложения — источник загрузок,
сторож связи — получает только `JobContext` и не знает, какой движок его
запустил. Ребёнка такой код делает через `Job.deferred`, и внутри задачи
контроллера `solo` это не работает: `SoloContext.run` отвергает `Job.deferred`
с `ArgumentError`. Ребёнок должен быть сделан `job(...)` того же контроллера,
а `job` защищён (пункт 46 `docs/settled.md`) и общему коду недоступен.

Зонд на дереве 2026-10-27, задача `enqueue<int, String>` зовёт общий код:

```text
deferred: Failed(Invalid argument (job): was not created by this Solo (make it with job(...) of this controller): "Job()")
each: Done(woken: Cancelled(manual))
```

Вторая строка — обход через `ctx.each(Stream.value(0), (c, _) => c.pause(d))`:
`each` делает ребёнка через фабрику `createEachJob`, которую `solo`
переопределяет, и такого ребёнка движок принимает. Срока у него нет, и как
совет он не годится.

Чего общий код лишён без ребёнка:

- **срока одного шага.** Ядро даёт его ребёнком со сроком — раздел «A deadline
  for one step» `time.md` `async_job`. Без ребёнка общий код ведёт свой таймер
  поверх `abandonable`, и его отмена — не `Cancelled(timeout)`;
- **паузы, которую можно разбудить.** Ребёнок с `pause(d)` и его `cancel()`.
  Это в 0.4.0 закрывает и `pauseOrWake` на `abandonable` и таймере, к которому
  HisBible вернулась.

Решение владельца 2026-10-27: брать `ctx.child(body, {timeout})`,
а не `timeout:` у `abandonable` и `join`. Ревью — на Opus и дополнительно
на codex.

## API

### Ядро

В `JobContext`:

```dart
/// Makes an unstarted child of this job's engine, for [run], [start] and
/// [runAll].
ChildJob<T> child<T>(
  Future<T> Function(JobContext ctx) body, {
  Object? key,
  String Function()? describe,
  Duration? timeout,
});
```

- Ничего не запускает и ничего не проверяет: это фабрика. Запуск и все отказы —
  у `run`, `start` и `runAll`, как сейчас. Вызов из `unattended`, после конца
  тела, из очистки или на отменённой задаче возвращает ребёнка, которого `run`
  затем отвергнет по своим правилам.
- `timeout` — как у `Job.deferred`: считается от старта тела ребёнка, ноль
  и отрицательный — `ArgumentError` синхронно, из самого `child`.
- Реализация в `JobContextBase` —
  `Job.deferred<T>(body, key:, describe:, timeout:)`. Наблюдателя ребёнок
  не получает: без своего он берёт родительский на старте, как любой ребёнок
  `run`.
- Движок, который ограничивает детей, переопределяет `child`. Отдельной
  защищённой фабрики под публичным членом не будет: точка расширения — сам
  `child`, как `run` и `each`, которые `solo` уже переопределяет.

`createEachJob` остаётся крючком `each`, а его реализация по умолчанию
становится `child<void>(body, key: key, describe: describe)`. Движку, которому
для `each` не нужно ничего сверх общего ребёнка, переопределять его больше
не надо. Удалить его нельзя: `solo` проверяет в нём правила родителя после
отказов ядра (`unattended`, конец тела) и до старта ребёнка, и `child` этого
места не даёт — фабрика ничего не проверяет.

### `solo`

`SoloContext` переопределяет `child` с телом на своём контексте:

```dart
@override
SoloJob<T> child<T>(
  Future<T> Function(SoloContext<S, W> ctx) body, {
  Object? key,
  String Function()? describe,
  Duration? timeout,
});
```

Переопределение законно: функция от `JobContext` — подтип функции
от `SoloContext<S, W>`, поэтому вызов ядра `child<void>((c) => ...)` из `each`
проходит и в `solo`.

Ребёнок — `job<W, T>(body, key:, describe:, timeout:, keepWhile: родителя)`
того же контроллера, ровно как ребёнок `each`: рабочий тип `W` и `keepWhile`
родителя, в том числе после конца тела родителя, `canStart` родителя
не повторяется, отменяем независимо от `cancellable` родителя, `ifFailed`
и `ifCancelled` нет. Правила родителя ребёнок проверяет на своём старте, как
любой ребёнок `run`: состояние, которое они отвергают, отвергнет и его,
и `ctx.run` бросит его `Cancelled(rules)`.

`createEachJob` в `solo` остаётся: проверка правил родителя, затем
`child<void>(...)` вместо прямого `_solo.job`.

### Чего не будет

- `cancellable:` у `child`. Срок требует отменяемого ребёнка, а шаг, который
  нельзя прервать, общий код пишет через `uncancellable`. Если ревью найдёт
  случай, где общему коду нужен неотменяемый ребёнок, — добавляется отдельно.
- `keepWhile:`, `canStart:` и прочие параметры движка. `child` — общий
  знаменатель всех движков; свои параметры движок даёт своим `job(...)`.
- Проверки в момент создания. `each` проверяет, потому что возвращает уже
  запущенного ребёнка; `child` не запускает ничего.

## Почему ломающее

Новый член интерфейса `JobContext` ломает того, кто его `implements`,
а не наследует `JobContextBase`. Новый член `JobContextBase` ломает подкласс
с членом того же имени. Поэтому `async_job` выходит 0.5.0, а не 0.4.1; `solo`
переходит на него своим выпуском, затем scopo под новое ядро и только потом
`flutter_solo` — порядок из `AGENTS.md`. scopo наследует `JobContextBase`
(`_ScopeInitContext`) и получает `child` по умолчанию без правок.

## Документы

- `async_job`:
  - `children.md`, «Running a child»: абзац «A child is made with
    `Job.deferred`…» называет `ctx.child` — ребёнок движка, на котором идёт
    тело, для кода, который движка не знает;
  - `time.md`, «A deadline for one step»: пример переходит
    на `ctx.child(renderThumbnail, key: 'thumbnail', timeout: …)`, потому что
    так шаг получает срок на любом движке; трасса та же;
  - `extending.md`: движок, который ограничивает детей, переопределяет `child`,
    и `each` по умолчанию берёт ребёнка оттуда же;
  - dartdoc `child`, `createEachJob`, `Job.deferred` (фраза о шаге со сроком);
  - `CHANGELOG.md`: Breaking — новый член `JobContext`; Added — `child`.
- `solo`:
  - `children.md`: где сказано, что ребёнка делает `job(...)` того же
    контроллера, — `ctx.child` для кода, у которого есть только контекст;
  - dartdoc `SoloContext` (абзац о детях `run`, `start`, `runAll`) и `child`;
  - `CHANGELOG.md`: Added.
- Переводы всего названного, `docs/architecture.md` (абзац о `createEachJob`),
  `docs/handoff.md`.

Рецепта паузы с пробуждением на страницах не будет: решение владельца снять его
(заявка HisBible 3) не пересматривается. `child` её только делает возможной
в общем коде.

## Тесты

Ядро (`job_context` или `children`):

1. `ctx.run(ctx.child(...))` отдаёт значение; ребёнок получает наблюдателя
   родителя, `key` и `describe` видны в его имени.
2. Срок: `ctx.run(ctx.child(step, timeout: d))` бросает в родителя
   `Cancelled(TimeoutCancelReason(d))`, родитель не отменён.
3. `timeout: Duration.zero` — `ArgumentError` из `child`, до `run`.
4. `child` ничего не запускает: ребёнок, которого никто не взял, не стартовал;
   `start` и `runAll` его берут.
5. Из `unattended` и после конца тела `child` возвращает ребёнка, а `run`
   бросает свой `StateError`.
6. `extending_test.dart`: движок, переопределивший `child`, получает через него
   и детей `each`; движок, переопределивший `createEachJob`, — как прежде.

`solo`:

7. Общий код на `JobContext` внутри `enqueue` — зонд выше, `run` проходит.
8. Ребёнок `child` получает `SoloContext<S, W>`, читает `state`, делает `emit`.
9. `keepWhile` родителя: состояние, которое оно отвергает, кончает ребёнка
   `Cancelled(rules)` на старте, и `ctx.run` бросает его.
10. Срок у ребёнка `solo`: `Cancelled(timeout)` в родителя, очередь идёт
    дальше.
11. `each` в `solo` после правки `createEachJob` — существующий набор зелёный
    без правок.
12. Пауза, которую будит `cancel()` ребёнка `child`, — на общем коде, как
    у HisBible.

Мутации: `child` в `_SoloContext` без переопределения (тест 7 краснеет), без
`keepWhile` (9), без `timeout` (10), `createEachJob` по умолчанию мимо `child`
(6).

## Открытые вопросы к ревью

1. Имя. `child` занято в примерах как имя переменной и параметра
   (`final child = …`, `(child, event)` у `each`): `child.child(...)` читается
   плохо. Альтернативы — `childJob`, `makeChild`. Предлагаю `child`: член
   короткий, а `ctx.child(step)` читается как то, что делает.
2. Правильно ли оставлять `createEachJob` вместо одной фабрики.
3. Нужен ли `cancellable:`.
