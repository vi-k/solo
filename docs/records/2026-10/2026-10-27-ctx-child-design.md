> **Состояние на 2026-10-27:** ревью дизайна на Opus и codex разобрано,
> дизайн исправлен по вердиктам; реализация идёт по плану, ядро и `solo` готовы.
> **Что это:** дизайн `ctx.child` — фабрики ребёнка, которого примет движок
> контекста, для кода, которому передан только `JobContext`.
> **Связанные записи:** `2026-10-06-job-timeout-design.md` — срок задачи
> и ребёнок со сроком; `2026-10-19-child-job-report.md` — `ctx.run` берёт
> `ChildJob<T>`; `2026-10-27-ctx-child-plan.md` — план работ и его ревью.

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

Раздел переписан по ревью дизайна: разделы «Ревью дизайна: Opus» и «Ревью
дизайна: codex» ниже, номера находок — О1–О8 и К1–К3.

### Ядро

В `JobContext`:

```dart
/// Makes an unstarted child that this job's engine accepts, for [run],
/// [start] and [runAll].
@useResult
ChildJob<T> child<T>(
  Future<T> Function(JobContext ctx) body, {
  Object? key,
  String Function()? describe,
  Duration? timeout,
});
```

- Фабрика: ничего не запускает и ничего не проверяет. Запуск и все отказы —
  у `run`, `start` и `runAll`, как сейчас. Вызов из `unattended`, из очистки,
  после конца тела или на законченной задаче возвращает ребёнка; запуск тем же
  контекстом там отвергается по правилам `run`. Запрещено место запуска,
  а не происхождение ребёнка (К2).
- Правила ребёнку выбирает контекст, который его сделал; родителем становится
  задача, которая его запустила: она ждёт его, её отмена каскадом идёт на него,
  её наблюдатель достаётся ребёнку без своего. Чаще всего это одна задача,
  но ребёнка можно передать другой задаче того же движка, и запрета на это нет
  (О2, К2).
- Незапущенный ребёнок принадлежит тому, кто его держит. Он не входит в дерево
  создателя: создатель его не ждёт и не отменяет, `close()` контроллера `solo`
  его не видит, срок до старта не идёт, `done` не завершается. Он держит тело
  со всем захваченным — в `solo` и контроллер, — пока жива ручка. Если запуск
  больше не нужен, держатель отменяет его (К3, О8).
- `timeout` — как у `Job.deferred`: считается от старта тела ребёнка, ноль
  и отрицательный — `ArgumentError` синхронно, из самого `child`.
- Реализация в `JobContextBase` —
  `Job.deferred<T>(body, key:, describe:, timeout:)`: ребёнок ядра с контекстом
  ядра. Правил движка он не знает: движок со своим контекстом, своими правилами
  в `check()` или ограничением детей переопределяет `child` (О1). Отдельной
  защищённой фабрики под публичным членом не будет: точка расширения — сам
  `child`, как `run` и `each`, которые `solo` уже переопределяет.
- `@useResult` из `meta`: `ctx.child(step);` без запуска — холостой вызов,
  а `Job` не `Future`, и линты будущих его не поймают. Переопределение
  аннотацию не наследует, поэтому она стоит и на `SoloContext.child` (О7).

Dartdoc класса `JobContext` перечисляет члены, которые не бросают после конца
задачи и после принятой отмены; `child` встаёт в оба списка (О3, К1).

`createEachJob` остаётся крючком `each`, а его реализация по умолчанию
становится `child<void>(body, key: key, describe: describe)`. Движку, которому
для `each` не нужно ничего сверх своего `child`, переопределять его больше
не надо. Удалить его нельзя: `solo` проверяет в нём правила родителя после
отказов ядра (`unattended`, конец тела) и до старта ребёнка, а `_checkCanRun`
ядра приватный; `child` этого места не даёт — фабрика ничего не проверяет.

### `solo`

`SoloContext` переопределяет `child` с телом на своём контексте:

```dart
@override
@useResult
SoloJob<T> child<T>(
  Future<T> Function(SoloContext<S, W> ctx) body, {
  Object? key,
  String Function()? describe,
  Duration? timeout,
});
```

Переопределение законно: функция от `JobContext` — подтип функции
от `SoloContext<S, W>`, поэтому вызов ядра `child<void>((c) => ...)` из `each`
проходит и в `solo`. Оба прототипа ревью это подтвердили.

Ребёнок — `job<W, T>(body, key:, describe:, timeout:, keepWhile: создателя)`
того же контроллера, ровно как ребёнок `each`: рабочий тип `W` и `keepWhile`
задачи, чей контекст его сделал, в том числе после конца её тела, `canStart`
не повторяется, отменяем независимо от `cancellable` создателя, `ifFailed`
и `ifCancelled` нет. Правила ребёнок проверяет на своём старте, как любой
ребёнок `run`: состояние, которое они отвергают, отвергнет и его, и `ctx.run`
бросит его `Cancelled(rules)`. Запущенный другой задачей того же контроллера,
он проверяет правила создателя, а не её: `W` вшит в тип тела и подменён быть
не может.

`createEachJob` в `solo` остаётся: проверка правил родителя, затем
`child<void>(...)` вместо прямого `_solo.job`.

Текст отказа `_own` в `solo.dart` («make it with job(...) of this controller»)
называет и `ctx.child`, его цитата в `solo/doc/children.md` — тоже (О3).

### Чего не будет

- `cancellable:` у `child`. Срок требует отменяемого ребёнка, и заявке нужен
  именно он. Шаг со сроком, который отмена родителя не прерывает, пишется
  `ctx.uncancellable(() => ctx.run(ctx.child(step, timeout: d)))`. Это
  не замена `cancellable: false`: секция придерживает отмену родителя, а отмену
  самого ребёнка не отклоняет (ответ codex на вопрос 3). Параметр можно
  добавить позже отдельной работой.
- `keepWhile:`, `canStart:` и прочие параметры движка. `child` — общий
  знаменатель всех движков; свои параметры движок даёт своим `job(...)`.
- Проверки в момент создания. `each` проверяет, потому что возвращает уже
  запущенного ребёнка; `child` не запускает ничего.
- Запрета на передачу ребёнка другой задаче, который О2 предлагал в `solo`: он
  был бы новым правилом `ChildJob`, которого не требует ни один случай заявки.

## Почему ломающее

Новый член интерфейса `JobContext` ломает того, кто его `implements`,
а не наследует `JobContextBase`. Новый член `JobContextBase` ломает подкласс
с членом того же имени: зонд codex дал «Can't declare a member that conflicts
with an inherited one». Расширение приложения `extension on JobContext`
с членом `child` молча уступит новому члену. Новый член `SoloContext` ломает её
реализации вне библиотеки. Поэтому `async_job` выходит 0.5.0, а не 0.4.1,
и запись `solo` — тоже Breaking, с отсылкой на ядро (О5). Порядок выпусков
из `AGENTS.md`: ядро, `solo`, scopo под новое ядро, `flutter_solo`. scopo
наследует `JobContextBase` (`_ScopeInitContext`) и получает `child`
по умолчанию без правок; его ребёнок получает `JobContext`,
а не `ScopeInitContext`.

Между выпусками нужны оверрайды (О4): `async_job` из дерева в `packages/solo`
и `packages/solo/example`, а в `packages/flutter_solo` и его примере — рядом
с уже живущим `solo`. Первая строка — комментарий «до выпуска `async_job`
0.5.0».

## Документы

- `async_job`:
  - `README.md` и `README.ru.md`, таблица «the context at a glance»: строка
    `ctx.child`, после отмены — «Works as usual»; `readme_recipe_test.dart` —
    вызов `child` в `calls` (О3, К1);
  - `children.md`, «Running a child»: абзац «A child is made with
    `Job.deferred`…» называет `ctx.child` — ребёнка, которого примет движок
    тела, для кода, который движка не знает; там же — кто владеет незапущенным
    ребёнком и чьи у него правила; код страницы держит
    `test/support/children_page.dart`;
  - `time.md`, «A deadline for one step»: пример переходит
    на `ctx.child(renderThumbnail, key: 'thumbnail', timeout: …)`, потому что
    так шаг получает срок на любом движке; трасса та же; вместе с ним
    `test/support/time_page.dart` и `time_rakes_test.dart`;
  - `extending.md` и `engine.md` («A rule of your own»): движок со своим
    контекстом, правилами или ограничением детей переопределяет `child`
    и ставит на переопределение `@useResult`; `each` по умолчанию берёт ребёнка
    оттуда же; поддержка страниц — `extending_rakes_test.dart` и её
    `test/support`, если правка заденет код блоков;
  - dartdoc класса `JobContext` (оба списка исключений), `child`,
    `createEachJob`, `Job.deferred` (фраза о шаге со сроком);
  - `CHANGELOG.md`: Breaking — новый член `JobContext` и `JobContextBase`,
    затенение расширения с именем `child`; Added — `child`.
- `solo`:
  - `children.md`: где сказано, что ребёнка делает `job(...)` того же
    контроллера, — `ctx.child` для кода, у которого есть только контекст;
    цитата отказа; `children_rakes_test.dart`;
  - `reference.md` и `docs/ru/solo/reference.md`: член `child`
    (`reference_page_test.dart`);
  - dartdoc `SoloContext` (абзац о детях `run`, `start`, `runAll`), `child`,
    текст отказа `_own`;
  - `CHANGELOG.md`: Breaking — `SoloContext.child`, отсылка на ядро.
- Переводы всего названного, `docs/architecture.md` (абзац о `createEachJob`),
  `docs/handoff.md`, сообщение сессии scopo в день выпуска ядра.

Рецепта паузы с пробуждением на страницах не будет: решение владельца снять его
(заявка HisBible 3) не пересматривается. `child` её только делает возможной
в общем коде.

## Тесты

Ядро:

1. `ctx.run(ctx.child(...))` отдаёт значение; ребёнок получает наблюдателя
   родителя, `key` и `describe` видны в его имени.
2. Срок: `ctx.run(ctx.child(step, timeout: d))` бросает в родителя
   `Cancelled(TimeoutCancelReason(d))`, в точке перехвата родитель не отменён;
   выпущенный наружу, срок кончает родителя `Cancelled(handler: …)`
   с `HandlerCancelReason`.
3. `timeout` ноль и отрицательный — `ArgumentError` из `child`, до `run`.
4. Незапущенный ребёнок: не стартовал, срок не идёт, `done` не завершён после
   конца создателя; явный `cancel()` кончает его `Cancelled`; `start`
   и `runAll` его берут.
5. Места вызова: из `unattended`, из очистки, после конца тела и на законченной
   задаче `child` возвращает ребёнка, а запуск тем же контекстом бросает свой
   `StateError`; на задаче с принятой отменой запуск бросает отмену родителя,
   ребёнок кончается `Cancelled(parent)`.
6. Передача: ребёнок `child` законченной задачи успешно идёт у другой;
   родитель — запустившая задача, и её отмена каскадом идёт на ребёнка.
7. `child` внутри `uncancellable`: отмена родителя удержана, срок ребёнка
   срабатывает.
8. `extending_test.dart`: движок, переопределивший `child`, получает через него
   и детей `each`; движок, переопределивший `createEachJob`, — как прежде;
   движок с правилом в `check()`, не переопределивший `child`, получает ребёнка
   с контекстом ядра, который правила не видит.

`solo`:

9. Общий код на `JobContext` внутри `enqueue`: `run` проходит, срок шага
   приходит `Cancelled(timeout)`.
10. Ребёнок `child` получает `SoloContext<S, W>`, читает `state`, делает
    `emit`.
11. Правила создателя: `W` и `keepWhile` создателя, в том числе после конца его
    тела; состояние, которое они отвергают, кончает ребёнка `Cancelled(rules)`
    на старте, и `ctx.run` бросает его; `canStart` не повторяется; ребёнок
    отменяем при `cancellable: false` создателя.
12. Передача внутри контроллера: задача B с другим `W` запускает ребёнка задачи
    A и получает `Cancelled(rules)` по правилам A.
13. Срок у ребёнка `solo`: перехваченный — родитель `Done`, `ifCancelled`
    не зван; выпущенный — `ifCancelled` родителя видит `HandlerCancelReason`;
    очередь идёт дальше в обоих случаях.
14. Незапущенный ребёнок `solo`: `close()` контроллера кончается, `done`
    ребёнка — нет; `cancel()` его кончает.
15. `start` и `runAll` с детьми `child`: `runAll` останавливает соседнюю ветку
    на провале.
16. `each` в `solo` после правки `createEachJob` — существующий набор зелёный
    без правок, включая порядок отказов и уже принятую отмену.
17. Пауза, которую будит `cancel()` ребёнка `child`, — на общем коде, как
    у HisBible; вторая ветка — родитель отменён во время паузы.
18. `@useResult`: `ctx.child(step);` даёт `unused_result` и через `JobContext`,
    и через `SoloContext` — зонд анализатора в тесте.

Мутации:

- снять `child` из `SoloContext` и `_SoloContext` — краснеет 9: `ArgumentError`
  вместо значения; снять только из `_SoloContext` нельзя — не собирается (О6);
- без `keepWhile` в `_SoloContext.child` — 11;
- без `timeout` в `_SoloContext.child` и в `JobContextBase.child` — 2, 13;
- `createEachJob` по умолчанию мимо `child` — 8;
- `@useResult` снят с `SoloContext.child` — 18.

## Открытые вопросы

Закрыты ревью: имя `child` остаётся, `createEachJob` остаётся, `cancellable:`
не нужен; ответы обоих ревьюеров — ниже.

## Ревью дизайна: Opus

Субагент-ревьюер на Opus, своя копия дерева на `418e5223`, прототип и зонды.
Отчёт пришёл сообщением и перенесён сюда; находки — О1–О8.

Предмет: `docs/records/2026-10/2026-10-27-ctx-child-design.md`, копия
на `418e5223`. Дизайн проверен прототипом:

- `child` добавлен в `JobContext` и `JobContextBase` ровно по дизайну;
- `SoloContext` и `_SoloContext` его переопределяют;
- `createEachJob` ядра по умолчанию идёт через `child`;
- `createEachJob` в `solo` проверяет правила и зовёт `child<void>`.

После ревью файлы возвращены копией, зонды удалены.

### Прогон

Прототип ядра (`packages/async_job`):

1. `dart analyze --fatal-infos` — `No issues found!`
2. `dart test -r failures-only` — итог `+1866 -2: Some tests failed.`
3. `dart test test/readme_recipe_test.dart -r expanded | grep [E]` —
   `00:00 +49 -2: Some tests failed.`
4. `dart run tool/zz_probe_core.dart` — `another job runs it: Done(2)`
5. `dart analyze tool/zz_unused.dart` с `@useResult` на `JobContext.child` —
   `2 issues found.`
6. `dart run tool/zz_engine_rule.dart` — `engine job: Cancelled(signed out)`
7. `dart run tool/zz_nap.dart` — `parent cancelled: Cancelled(manual)`

Прототип `solo` (`packages/solo`, временный `pubspec_overrides.yaml` с путём
на `../async_job`):

8. `dart analyze --fatal-infos` — `No issues found!`
9. `dart test -r failures-only` — итог `+2115 -2: Some tests failed.`
10. `dart test test/reference_page_test.dart -r expanded | grep [E]` —
    `00:00 +20 -2: Some tests failed.`
11. `dart run tool/zz_probe.dart` — `closed; orphan finished: false`
12. Мутация: снято переопределение `child` в `_SoloContext`,
    `dart analyze lib` — `1 issue found.`

В прогонах 2 и 9 упали только сторожа документов (находка 3). Остальной набор
обоих пакетов на прототипе зелёный, включая `each` в `solo`.

### Проверка утверждений дизайна о коде

| Утверждение | Итог | Чем проверено |
| --- | --- | --- |
| `SoloContext.run` отвергает `Job.deferred` с `ArgumentError` | верно | `_own` в `solo.dart:26`, трасса в `solo/doc/children.md` |
| `createEachJob` в `solo` делает `_solo.job<W, void>(…, keepWhile: родителя)` после проверки правил, а отказы ядра (`unattended`, конец тела) идут раньше | верно | `solo/lib/src/job_context.dart:124-151`; `JobContextBase.each` зовёт `_checkCanRun` до фабрики |
| `Job.deferred` с нулевым сроком бросает `ArgumentError` синхронно | верно, и из `child` до `run` | `zero: ArgumentError from child, before run: must be positive, not 0:00:00.000000` |
| Ребёнок без наблюдателя берёт родительского на старте | верно | `startChild`: `_observer ??= _owner._observer` |
| Ребёнок `each` в `solo` получает `W` и `keepWhile` родителя; `canStart`, `ifFailed` и `ifCancelled` у него нет; отменяем независимо от `cancellable` родителя | верно | `job<W, void>` с `cancellable = true` по умолчанию; `_keepWhile` объявлен `final` и переживает задачу |
| Переопределение `child<T>` в `SoloContext` законно, вызов ядра `child<void>((c) => …)` из `each` проходит | верно | прогоны 8–9 |
| Ребёнок `solo` проверяет правила родителя на старте, `ctx.run` бросает `Cancelled(rules)` | верно | `after emit: Cancelled(rules: keepWhile); parent cancelled: false` |
| Срок ребёнка `solo` даёт `Cancelled(timeout)` в родителя, очередь идёт дальше | верно | `generic: Done(value; deadline: Cancelled(timeout))` |
| scopo наследует `JobContextBase` и получает `child` без правок | верно | `_ScopeInitContext extends JobContextBase` |
| `async_job` выходит 0.5.0 | верно | новый член интерфейса, которую можно `implements` вне библиотеки, — ломающая правка |

В дереве никто не делает `implements JobContext`. У 19 наследников
`JobContextBase` члена `child` нет, прогон 1 чистый.

#### О1. P2 — `child` по умолчанию — ребёнок ядра, а не движка, и правило движка он не спрашивает

**Место.** «API → Ядро»: «Движок, который ограничивает детей, переопределяет
`child`». План документов: `children.md` назовёт его «ребёнок движка,
на котором идёт тело». Dartdoc: «Makes an unstarted child of this job's
engine».

**Суть.** Реализация по умолчанию — `Job.deferred`, задача ядра
с `_CoreContext`. Движок, который детей не ограничивает, но держит правило
в `check()`, как в разделе «A rule of your own» `engine.md`, получает ребёнка,
который правило не спрашивает: контрольные точки ребёнка проходят и после того,
как правило перестало выполняться. С `Job.deferred` сегодня то же самое,
но дизайн подаёт `ctx.child` общему коду как «ребёнка движка», и общий код
в это поверит. Критерий «ограничивает детей» неполон.

**Доказательство.** Зонд: `MyJob`/`MyContext` с правилом в `check()`.

```dart
final job = MyJob<String>(key: "engine", (ctx) async {
  final kid = ctx.child((c) async {
    signedIn = false;
    c.check();
    print("child passed its checkpoint after sign-out; child context: ${c.runtimeType}");
    return "rows";
  });
  return ctx.run(kid);
})..launch();
```

```text
child passed its checkpoint after sign-out; child context: _CoreContext
engine job: Cancelled(signed out)
```

**Предложение.** В dartdoc `child` и на `extending.md`: по умолчанию это
`Job.deferred`, ребёнок ядра с контекстом ядра; движок со своим контекстом,
своими правилами или ограничением детей переопределяет `child`. На `engine.md`,
в «A rule of your own», — фраза о `child`. На `children.md` писать «ребёнок,
которого примет движок», а не «ребёнок движка». В тест 6 — движок с правилом
в `check`, который `child` не переопределил.

**Вердикт.** Принято. Dartdoc и страницы говорят «ребёнок, которого примет
движок», а не «ребёнок движка»; реализация по умолчанию названа ребёнком ядра
с контекстом ядра; переопределять `child` должен движок со своим контекстом,
правилами в `check()` или ограничением детей, и это сказано на `extending.md`
и `engine.md`. Тест 8 держит движок с правилом, который `child`
не переопределил.

#### О2. P2 — правила ребёнка `solo` берутся от задачи, чей контекст его сделал, а не от той, что его запустила

**Место.** «API → `solo`»: «job<W, T>(…, keepWhile: родителя)». «Ядро»: «ничего
не запускает и ничего не проверяет».

**Суть.** `child` — фабрика, и ребёнок живёт отдельно от вызова. `adoptedBy`
в `solo` пускает ребёнка в любую задачу того же контроллера, а `W`
и `keepWhile` у него от задачи A, чьим `ctx` он сделан. Задача B с другим `W`
запускает такого ребёнка, и его отвергают правила A, хотя правила B
выполняются; правила B ребёнок не спрашивает вовсе. Дизайн пишет «родитель»
так, будто создатель и запускающий — одна задача.

**Доказательство.** Задача A (`enqueue<Loading, void>`) кладёт `ctx.child(...)`
в поле и пишет `Idle`, задача B (`enqueue<Idle, Object?>`) запускает этого
ребёнка.

```text
cross-job: Done(B got Cancelled(rules: is not Loading))
```

Ядро, где `saved` — `ctx` законченной задачи:

```text
child on finished ctx: Job(), finished: false
run on finished ctx: Bad state: Job(root) has already finished, cannot run a child
another job runs it: Done(2)
```

**Предложение.** Решить явно и записать в дизайн. Выбор ревьюера: в `solo`
отказывать в `adoptedBy`, если ребёнка `ctx.child` усыновляет не та задача, что
его сделала. В ядре оставить как есть и сказать об этом в dartdoc.
Альтернатива: оставить поведение и описать его — «правила той задачи, чей
контекст сделал ребёнка». В любом случае нужен тест.

**Вердикт.** Принято наполовину. Разницу создателя и запустившего дизайн теперь
называет: правила — от контекста, который сделал ребёнка, родитель — тот, кто
запустил; в `solo` правила создателя, потому что `W` вшит в тип тела. Запрет
передачи не принят: он был бы новым правилом `ChildJob`, которого не требует
ни один случай заявки, — довод К2. Тесты 6 и 12.

#### О3. P2 — план не видит контракта `JobContext`, четыре сторожа документов краснеют на прототипе

**Суть.** Новый член меняет списки, которые держат код и тесты:

- dartdoc класса `JobContext`: «every member throws a [StateError] once the job
  has finished, except [check], [log], [job] and [heldCancellation]» —
  по дизайну `child` не бросает, и контракт станет ложным;
- таблица «the context at a glance» в `packages/async_job/README.md`
  и `README.ru.md`: сторож `readme_recipe_test.dart`;
- `packages/solo/doc/reference.md` и `docs/ru/solo/reference.md`: сторож
  `reference_page_test.dart`;
- сторожа кода страниц: `time.md` ↔ `test/support/time_page.dart`,
  `children.md` ядра ↔ `test/support/children_page.dart`, `children.md` `solo`
  ↔ `children_rakes_test.dart`;
- текст отказа `solo` (`solo.dart:26`, «make it with job(...) of this
  controller») и его цитата в `solo/doc/children.md` не называют `ctx.child`.

**Доказательство.**

```text
00:00 +30 -1: the context at a glance names every member of the context, and nothing else [E]
00:00 +30 -2: the context at a glance says which of them throw once the job is cancelled [E]
00:00 +1 -1: doc/reference.md lists every member of SoloContext and nothing else [E]
00:00 +8 -2: ../../docs/ru/solo/reference.md lists every member of SoloContext and nothing else [E]
```

**Предложение.** Добавить всё названное в план.

**Вердикт.** Принято, вместе с К1: всё названное — в разделе «Документы», оба
списка dartdoc `JobContext` — в «API».

#### О4. P2 — без оверрайдов `solo` план не собирается

**Суть.** `packages/solo` сейчас без `pubspec_overrides.yaml` и берёт
`async_job` 0.4.0 с pub.dev; переопределение `child` там не скомпилируется.
`flutter_solo` и его пример переопределяют только `solo`. После
`async_job: ^0.5.0` в `solo/pubspec.yaml` зависимости не разрешатся вовсе.

**Предложение.** Первым шагом плана — оверрайд `async_job` в `packages/solo`
и `packages/solo/example`, `async_job` в оверрайдах `packages/flutter_solo`
и его примера, комментарий «до выпуска async_job 0.5.0», абзац в handoff.

**Вердикт.** Принято: оверрайды — первый шаг работы, раздел «Почему ломающее».

#### О5. P3 — для `solo` правка тоже ломающая, а не «Added»

**Суть.** `SoloContext` — `abstract interface class`, её можно реализовать вне
библиотеки, и новый член такую реализацию ломает. Тихий слом: расширение
приложения `extension on JobContext { child(...) }` молча уступит новому члену.

**Предложение.** В `CHANGELOG.md` `solo`: Breaking — `SoloContext.child`, плюс
отсылка на Breaking ядра; в Breaking ядра — фраза о расширении с именем
`child`; сессии scopo — то же в сообщении о выпуске.

**Вердикт.** Принято: запись `solo` — Breaking с отсылкой на ядро, в Breaking
ядра — затенение расширения с именем `child`; сообщение сессии scopo —
в «Документах».

#### О6. P3 — мутация «`child` в `_SoloContext` без переопределения» не собирается

**Доказательство.**

```text
error - src/job_context.dart:125:13 - 'JobContextBase.child' (...) isn't a valid concrete implementation of 'SoloContext.child' (...) - invalid_implementation_override
```

**Предложение.** Мутант для теста 7: снять `child` и из `SoloContext`,
и из `_SoloContext`.

**Вердикт.** Принято: мутант для теста 9 снимает `child` из обоих классов.

#### О7. P3 — `ctx.child(step);` без `run` — тихий холостой вызов

**Суть.** `each` запускает ребёнка, а `child` — нет. `Job` — не `Future`,
поэтому `discarded_futures` и `unawaited_futures` не помогут.

**Доказательство.**

```text
warning - zz_unused.dart:4:7 - The value of 'child' should be used. ... - unused_result
```

Для вызова через `SoloContext` предупреждения нет: переопределение аннотацию
не наследует.

**Предложение.** `@useResult` на `JobContext.child` и на `SoloContext.child`.

**Вердикт.** Принято: `@useResult` на `JobContext.child` и `SoloContext.child`,
тест 18 и мутант на снятую аннотацию `solo`.

#### О8. P3 — пробелы в списке тестов

- **Тест 10.** Срок ребёнка, выпущенный наружу, кончает родителя
  с `HandlerCancelReason`, и это видит `ifCancelled` родителя:
  `parent ifCancelled sees: Cancelled(handler: Job(slow): Cancelled(timeout)),
  reason HandlerCancelReason`.
- **Тест 12.** Ветка «родитель отменён во время паузы»: общий код различает её
  по `ctx.job.isCancelled`.
- **Незапущенный ребёнок (тест 4).** Его `done` ждёт, `close()` его не трогает,
  а сам он держит тело со всем захваченным (в `solo` — и контроллер), пока жива
  ручка: `closed; orphan finished: false`.
- **`child` внутри `uncancellable`.** Отмена родителя удержана, а срок ребёнка
  срабатывает: `inside section: Cancelled(timeout)`, затем
  `root: Cancelled(manual)`.
- `runAll` и `start` с детьми `child` в `solo`.

**Вердикт.** Принято: тесты 2, 4, 7, 13, 14, 15, 17.

### Ответы на открытые вопросы

1. **Имя: оставить `child`, с `@useResult`.** Пара к `run`/`start`/`runAll`;
   `childJob` повторяет тип, `makeChild` длинное, `deferred` обещал бы
   `start()`, которого у ребёнка `solo` нет. Параметры `child` в наследниках
   `JobContextBase` (`startChild(child)`) затеняют член — видно сразу, лечится
   `this.child`.
2. **`createEachJob` оставить.** Правила родителя в `solo` должны стоять после
   отказов ядра и до старта ребёнка, а `_checkCanRun` приватный. Dartdoc
   `createEachJob` переписать: по умолчанию он берёт ребёнка из `child`.
3. **`cancellable:` не нужен.** Шаг со сроком, который нельзя прервать снаружи:
   `ctx.uncancellable(() => ctx.run(ctx.child(step, timeout: d)))`.
   `cancellable: false` вместе со сроком уже сегодня даёт `ArgumentError`.

## Ревью дизайна: codex

`gpt-6-astra`, усилие `xhigh`, своя копия на `418e5223`, 24 минуты; прогон
по его разделу ПРОГОН — 22 команды, прототип в обоих пакетах, полные наборы:
ядро 1866 зелёных и 2 красных, `solo` 2115 и 2, все четыре — сторожа документов
из К1. Приложение с исходниками одиннадцати зондов не перенесено: их выводы
стоят в находках. Находки — К1–К3.

### Находки

Проверен дизайн `docs/records/2026-10/2026-10-27-ctx-child-design.md`. Номера
строк ниже относятся к нему. P1 не нашёл: предложенные сигнатуры компилируются,
основная механика работает. До плана нужно закрыть три P2. Ни одна находка
не требует пересматривать решения `docs/settled.md`.

#### К1. P2 — в плане документов пропущены две проверяемые поверхности API

**Место:** строки 130–149, «Документы»; строки 155–186, «Тесты».

**Суть.** Перечень изменений не включает таблицу контекста в README ядра
и справочник `solo/doc/reference.md`. Прототип, буквально добавляющий
предложенный API, ломает четыре существующих теста этих документов. Кроме того,
общий dartdoc `JobContext` обещает `StateError` после завершения задачи для
каждого члена, кроме четырёх перечисленных. Новый `child` станет пятым
исключением, но изменение этого договора в плане тоже не названо.

**Механика.** `readme_recipe_test.dart` сравнивает таблицу README со всеми
членами `JobContext`, а затем требует вызов каждого в таблице `calls`.
`reference_page_test.dart` сравнивает справочник с членами `SoloContext`.
Добавление `child` расширяет оба множества. Это обнаруженный пробел плана,
а не претензия к ещё не написанной реализации: документы в прототипе намеренно
не менялись.

**Доказательство.** Зонд `zz_doc_surface.dart` читает сами классы через
`dart:mirrors` и вычитает имена таблиц. Фрагмент запущенного кода:

```dart
final coreMembers = reflectClass(JobContext).declarations.values
    .whereType<MethodMirror>()
    .where((m) => !m.isConstructor &&
        !m.metadata.any((a) => a.reflectee is Deprecated))
    .map((m) => MirrorSystem.getName(m.simpleName)).toSet();
```

Полный файл приведён в приложении. Точный вывод исправленного зонда:

```text
core README missing: [child]
solo reference missing: [child]
```

В полном прогоне ядра упали ровно два теста:

```text
  test/readme_recipe_test.dart: the context at a glance names every member of the context, and nothing else
  test/readme_recipe_test.dart: the context at a glance says which of them throw once the job is cancelled
```

В полном прогоне `solo` — ещё два:

```text
  test/reference_page_test.dart: ../../docs/ru/solo/reference.md lists every member of SoloContext and nothing else
  test/reference_page_test.dart: doc/reference.md lists every member of SoloContext and nothing else
```

Точное сообщение второго набора:

```text
  Expected: equals ['child', 'state', 'stateAs', 'emit', 'run', 'start', 'runAll', 'each'] unordered
    Actual: ['state', 'stateAs', 'emit', 'run', 'start', 'runAll', 'each']
     Which: has too few elements (7 < 8)
```

После восстановления исходных файлов эти два тестовых файла прошли целиком: 51
тест ядра и 22 теста `solo`. Следовательно, причина красного прогона —
расширение API, а не исходное состояние копии.

**Предложение.** Добавить в план:

- `packages/async_job/README.md` и `README.ru.md`: строку `ctx.child`
  со значением `Works as usual` / «Работает как обычно» на отменённой задаче;
- `packages/async_job/test/readme_recipe_test.dart`: вызов `child` в `calls`;
- `packages/solo/doc/reference.md` и `docs/ru/solo/reference.md`;
- общий dartdoc `JobContext` в `packages/async_job/lib/src/job_context.dart`:
  исключение для фабрики на завершённом контексте;
- синхронизацию примеров и их `test/support` при правке страниц из дизайна.

**Вердикт ревьюера:** дополнить перечень документов и проверок до плана.

**Вердикт.** Принято, вместе с О3.

#### К2. P2 — «родитель» смешивает создателя ребёнка и задачу, которая его запустит

**Место:** строки 61–70 и 100–106; тесты 1, 4, 7–9.

**Суть.** Дизайн говорит о наследовании `W` и `keepWhile` «родителя»,
но не определяет, разрешена ли передача незапущенного ребёнка другой задаче
того же контроллера. Предложенная реализация разрешает её. Правила берутся
у создателя, а ожидание, каскад отмены и уровень — у запустившей задачи. При
несовпадающих правилах это наблюдаемая разница, а не вопрос терминов.

**Механика.** `_solo.job<W, T>` записывает `W` и `_job._keepWhile` при
создании. `_SoloJob.adoptedBy` проверяет тождественность контроллера, очередь
и одноразовость, но не создавший контекст; `_parentJob` записывает там же
из нового контекста. В ядре `startChild` задаёт `_parent`, `_level`
и отсутствующего наблюдателя при запуске. Для `each` эти два момента
практически слиты; новый API разделяет их явно.

**Доказательство.** В `zz_child.dart` задача `maker` создаёт ребёнка
с `keepWhile: (s) => s < 5` и заканчивается. После `change(6)` задача `runner`
с рабочим типом `Object` запускает этот хэндл. Фрагмент:

```dart
final maker = controller.run<int, void>((ctx) async {
  saved = ctx;
  child = ctx.child<int>((c) async => c.state);
}, key: 'maker', keepWhile: (s) => s < 5);
clock.flushMicrotasks();
controller.change(6);
final runner = controller.run<Object, String>((ctx) async {
  try {
    return '${await ctx.run(child)}';
  } on Cancelled catch (error) {
    return '$error; selfCancelled=${ctx.job.isCancelled}';
  }
}, key: 'runner');
```

Точные строки вывода этого и соседних сценариев полного зонда:

```text
creator rules: maker=Done(null); runner=Done(Cancelled(rules: keepWhile); selfCancelled=false)
finished context keeps rule: Done(Cancelled(rules: keepWhile))
adopter: maker=Done(null); actualParent=Job(runner); level=1
adopter cancellation: child=Cancelled(parent); runner=Cancelled(manual)
factory after finish, other task: Done(10)
```

Последняя строка существенна: `child` на сохранённом после конца задачи
контексте не только возвращает хэндл; другая задача действительно может его
успешно запустить. Отказ старого `ctx.run` не делает ребёнка негодным. То же
относится к ребёнку, сделанному в `unattended` или уборщике: запрещено место
запуска, а не происхождение хэндла.

**Предложение.** Сохранить эту механику и назвать её явно: фабрика выбирает
движок и правила создавшего контекста; родитель назначается при запуске.
В `solo` разрешён другой контекст того же контроллера, но не другого
контроллера. `W` и функция `keepWhile` остаются от создателя; это не снимок
состояния и не правила нового родителя. Для ядра наблюдатель без своего
значения берётся у фактического родителя. Добавить тесты передачи хэндла,
правил создателя и каскада нового родителя, в том числе после завершения
создателя. Запрет такой передачи был бы отдельным изменением нынешнего договора
`ChildJob`, для него в заявке нет необходимости.

**Вердикт ревьюера:** зафиксировать происхождение правил и момент назначения
родителя до плана; не добавлять проверки привязки без отдельного основания.

**Вердикт.** Принято: механика оставлена и названа в «API», тесты 5, 6, 12.
Предложение О2 запретить передачу в `solo` отклонено по доводу этой находки.

#### К3. P2 — договор незапущенного `child` обрывается на «не стартовал»

**Место:** строки 61–66, 133–145; тест 4, строки 164–165.

**Суть.** Не сказано, что хэндл без запуска не входит в дерево ожидания,
не отменяется вместе с создателем, не заканчивается по своему `timeout`
и в `solo` не заканчивается при `close()`. Его `done` остаётся незавершённым.
Он также сохраняет тело, а задача `solo` — контроллер и функцию правила. Для
API, который вызывается через контекст и называется `child`, эту границу нужно
назвать прямо.

**Механика.** Фабрика только вызывает конструктор. Включение в дерево
происходит в `startChild` / `_waitFor`, таймер появляется в `_start`,
а освобождение тела — в `finished`. Незарегистрированного `_SoloJob` нет
ни в очереди, ни в `_running`, поэтому `close()` его не видит. `_keepWhile`
у `solo` — `final`, он намеренно живёт и после завершения задачи; `cancel()`
освобождает тело, но не этот захват и не `_solo`.

**Доказательство.** Фрагмент `zz_child.dart`; полный файл и функция `field`
из `zz_lifecycle.dart` приведены в приложении:

```dart
final maker = controller.run<int, void>((ctx) async {
  unused = ctx.child<int>((c) async => c.state,
      timeout: const Duration(seconds: 1));
  unawaited(unused.done.then((_) => done = true));
}, keepWhile: (s) => s > 0);
clock.flushMicrotasks();
var closed = false;
unawaited(controller.close().then((_) => closed = true));
clock.flushMicrotasks();
clock.elapse(const Duration(days: 1));
```

Точный вывод:

```text
unused solo: maker=Done(null); closed=true; child=null; done=false; timers=0; controllerHeld=true; bodyHeld=true; keepHeld=true
unused solo cancel: Cancelled(manual); done=true; bodyHeld=false; keepHeld=true
```

Отдельный зонд ядра даёт:

```text
unused: owner=Done(null); child=null; done=false; timers=0; bodyHeld=true; parentHeld=false
unused cancel: Cancelled(manual); done=true; bodyHeld=false
```

`child=null` в этих строках — значение `outcome`, а не отсутствие хэндла. Поля
проверены отражением на VM: это доказательство сохранённых ссылок, не измерение
сборщика мусора. У недостижимого хэндла сами эти поля не препятствуют сборке.
Произвольное замыкание тела или правило могут держать дополнительные объекты;
их состав зонд не измеряет.

**Предложение.** В договор фабрики и «Running a child» добавить: созданный
хэндл принадлежит вызывающему до успешного запуска; если запуск больше
не нужен, вызывающий отменяет его, когда ждёт исход или хочет отпустить тело,
и затем отпускает сам хэндл. `timeout` действует только после старта. Тест 4
должен проверять также незавершённый `done`, отсутствие таймера, завершение
создателя и `close()` без завершения хэндла, явный `cancel()`. Это пояснение
существующего поведения, согласованное с решениями 29 и 100 `docs/settled.md`;
автоматическую отмену при отказе запуска не предлагаю.

**Вердикт ревьюера:** дополнить договор владения незапущенным хэндлом и тест 4;
поведение ядра сохранять.

**Вердикт.** Принято: договор незапущенного ребёнка — в «API» и в плане
`children.md`, тесты 4 и 14; автоматической отмены нет.

### Проверка утверждений и пограничных случаев

**Сигнатуры законны.** `Future<T> Function(JobContext)` является подтипом
`Future<T> Function(SoloContext<S, W>)`: обработчик общего контекста умеет
принять и контекст `solo`. Поэтому переопределение расширяет допустимый тип
параметра метода, а возвращаемый `SoloJob<T>` сужает `ChildJob<T>`.
`covariant`, `dynamic` и приведения для этого не потребовались.

Отдельный файл `zz_types.dart` собрал и выполнил три пути: типизированный
`SoloContext.child`, `JobContext.child` и `JobContext.each` с виртуальным
переходом в `solo`. Точный вывод:

```text
typed=2; generic=3
core each: 4; solo=true
types: Done(2)
```

**Утверждения о нынешнем коде подтвердились.** На исходных файлах:

```text
zero: Invalid argument(s) (timeout): must be positive, not 0:00:00.000000; returned=false
observer start: Job(parent)
observer start: Job(child)
parent: Done(42)
```

`returned=false` доказывает синхронность броска из `Job.deferred`, а два старта
получены одним наблюдателем родителя. Отдельный зонд воспроизвёл обе строки
из раздела «Откуда» дизайна дословно:

```text
deferred: Failed(Invalid argument (job): was not created by this Solo (make it with job(...) of this controller): "Job()")
each: Done(woken: Cancelled(manual))
```

Свойства нынешнего ребёнка `each` в `solo`:

```text
each state: 1; typed=true
canStart calls: 1; parent before=null
keepWhile after body: child=Cancelled(rules: keepWhile); parent=Done(null)
independent cancel: child=Cancelled(manual); parent=Done(null)
W: child=Cancelled(rules: is not int); parent=Done(null)
```

Причина проверки в `_SoloContext.createEachJob` описана в дизайне верно. После
собственного `emit` родитель ещё может не знать о нарушении своих правил.
Простой запуск ребёнка мог бы вернуть уже отклонённую подписку, оставив
родителя успешным. `_checkedState` превращает `each` в контрольную точку
родителя. Ядро до этого проверяет `unattended` и конец тела, а ветка
`pendingCancel == null` сохраняет ранее принятую отмену и право `ifCancelled`
исправить состояние. Перенос такой проверки в `child` нарушил бы обещание
фабрики. Все 25 существующих тестов `each_test.dart` и `each_child_test.dart`
прошли на прототипе без изменений.

**Границы фабрики и запуска.** Проверено на прототипе:

| Место вызова | `child` | Запуск тем же контекстом |
| --- | --- | --- |
| Собственная работа `unattended` | создаёт | `StateError`; ребёнок остаётся незапущенным |
| После выхода из `unattended`, пока тело живо | хэндл остаётся пригодным | успешно запускает ребёнка из той работы |
| Уборщик | создаёт | `StateError`; исход ребёнка не устанавливается |
| Тело закончено, родитель ещё ждёт ребёнка | создаёт | `StateError` о конце тела |
| Задача окончательно закончена | создаёт | `StateError` о завершении |
| Отмена уже принята, тело ещё живо | создаёт | бросает отмену родителя; ребёнок получает `Cancelled(parent)` до старта |
| Другой живой контекст допустимого движка | принимает ранее созданный хэндл | возможен успешный запуск; находка 2 |

Точные сообщения всех отказов сохранены с полным кодом `zz_lifecycle.dart`
в приложении. Из вывода важно не потерять различие:

```text
cancelled factory: null
cancelled run: Cancelled(manual); child=Cancelled(parent)
cancelled owner: Cancelled(manual)
```

**`runAll` совместим с новыми хэндлами.** В ядре два ребёнка, созданные
в уборке и после завершения старой задачи, успешно вернули `Done([8, 9])`
новому родителю. В `solo` проверен провал одной ветки и остановка другой:

```text
runAll: parent=Done(Bad state: boom); slow=Cancelled(sibling); timers=0
```

Барьер группы, судьба `discard` и запрет ждать соседнюю ветку остаются
договором существующего `runAll`; это не основание заново открывать решение 27
`docs/settled.md`.

**Срок ребёнка и `ifCancelled` родителя.** Тесты 2 и 10 следует уточнить:
«родитель не отменён» верно в точке перехвата, а окончательный исход зависит
от того, выпустит ли тело отмену наружу. В прогоне:

```text
deadline caught=true: Cancelled(timeout); selfCancelled=false
deadline result caught=true: parent=Done(fallback); ifCancelled=0/null; next=Done(42)
deadline caught=false: Cancelled(timeout); selfCancelled=false
deadline result caught=false: parent=Cancelled(handler: Job(step): Cancelled(timeout)); ifCancelled=1/handler; next=Done(42)
```

У ребёнка нет собственных `ifFailed` / `ifCancelled`, но это не отключает
обработчик родителя. Неперехваченная отмена ребёнка становится
`HandlerCancelReason` родителя; его обработчик вызывается, если не отозвано
право коррекции состояния. Очередь продолжилась в обоих сценариях. Это
согласуется с нынешним `time.md`; при замене фабрики эту часть сохранять.

Дополнительные три теста прототипа подтвердили передачу `each` через
переопределённый `child`, сохранение имени, отсутствие отсчёта срока
до запуска, срабатывание после запуска, синхронный отказ нулю и отрицательному
сроку. Общий код с `JobContext` также разбудил паузу отменой нового ребёнка:

```text
wake: Done(woken: Cancelled(manual)); timers=0
```

### Совместимость и выпуск

Вывод о `async_job 0.5.0` верен. Добавление обязательного члена интерфейса
ломает конкретные реализации `implements JobContext` без такого члена или
покрывающего `noSuchMethod`. Добавление реализации в базовый класс не спасает
подклассы с конфликтующим именем.

Последнее проверено компилятором отдельным файлом:

```dart
import 'package:async_job/engine.dart';

final class ExistingContext extends JobContextBase {
  ExistingContext(super.owner);
  final int child = 7;
}

void main() => print('existing subclass compiles');
```

На прототипе код завершился с кодом 254:

```text
test/zz_collision.dart:5:13: Error: Can't declare a member that conflicts with an inherited one.
  final int child = 7;
            ^^^^^
lib/src/job_context.dart:498:15: Context: This is the inherited member.
  ChildJob<T> child<T>(
              ^^^^^
```

После восстановления исходного API тот же файл завершился с кодом 0:

```text
existing subclass compiles
```

В рабочем коде монорепозитория `JobContext` реализуют абстрактные
`JobContextBase` и `SoloContext`; конкретные `_CoreContext` и `_SoloContext`
наследуют базовую реализацию. В `flutter_solo/lib` своих реализаций контекста
не обнаружено. В тестах наследники находятся в следующих файлах:

- `async_job/test/timeout_test.dart`: `EngineContext`;
- `async_job/test/extending_test.dart`: `DomainContext`, `EachContext`;
- `async_job/test/extending_rakes_test.dart` и двух support-файлах
  `extending_plain.dart`, `extending_first_attempts.dart`: `MyContext` (две
  support-копии плюс класс в тесте);
- `async_job/test/cleanup_test.dart`: `_RuleContext`;
- `async_job/test/children_test.dart`: `_SwitchableRulesContext`,
  `_NamedContext`;
- `async_job/test/support/probe_job.dart`: `ProbeContext`, `RefusingContext`,
  `SelfCancellingContext`, `NoStackForGroupContext`, `OverflowingRulesContext`,
  `ThrowingRulesContext`, `ChildEndingRulesContext`, `RulesContext`,
  `CheckingContext`;
- `solo/test/support/foreign_job.dart`: `ForeignContext`.

Здесь префиксы пакетов означают каталоги под `packages/`. В этом перечне
конфликтующего `child` нет. Из переопределений `createEachJob` существенны
`_SoloContext` и `EachContext`; последнее продолжает работать со старым хуком.
Зелёная компиляция обоих полных наборов подтверждает отсутствие конфликта
в дереве; красные тесты были проверками содержания документов.

Порядок выпуска из дизайна соответствует `AGENTS.md`: ядро, `solo`, scopo под
новое ядро, затем `flutter_solo`. Это порядок зависимостей, а не запрос
на публикацию. Никаких действий связки выпуска не выполнялось.

До выпуска реализации потребуется вернуть четыре оверрайда по правилам
репозитория, включая `solo/example` и `flutter_solo/example`, чтобы проверки
верхних пакетов использовали ядро из дерева. Для этого ревью временный оверрайд
был у `solo`; в полном прогоне он видел прототип соседнего ядра. Проверок
примеров и Flutter здесь не было.

Утверждение про `_ScopeInitContext` дополнительно сверено по исходникам
локально установленного scopo 0.19.0: класс наследует `JobContextBase`,
добавляет `progress` и не объявляет конфликтующего `child`. Он получит базовую
фабрику без правки этого класса. Полная сборка scopo не выполнялась; обновление
ограничения `async_job` в его выпуске всё равно требуется. Новый ребёнок
получает обычный `JobContext`, а не `ScopeInitContext` — обещание дизайна
относится к допустимости ребёнка движком, не к наследованию всех возможностей
контекста.

Для `solo/CHANGELOG.md` одного `Added` недостаточно как всей записи выпуска:
должна быть ссылка на новый выпуск ядра и его ломающие изменения по соглашениям
проекта. Новый член `SoloContext` затрагивает и собственные реализации этого
интерфейса; не следует обещать отсутствие слома `solo`. В дереве уже есть
отдельная ломающая правка `onError`, это также не выпуск патч-версии `solo`.

### Ответы на три открытых вопроса

#### 1. Имя `child` оставить

`ctx.child(step)` согласуется с `ctx.run(child)` и существующим `job(...)`
у контроллера: существительное уже обозначает фабрику. `childJob` добавляет
слово без нового различия, `makeChild` допустимо, но не решает вопрос
отложенного назначения родителя. Это объясняет договор из находки 2. В примерах
контекст ребёнка можно назвать `c` или `childCtx`. Локальная переменная `child`
не конфликтует с членом у `ctx`; реальный конфликт у подкласса уже учтён
минорным выпуском до 1.0.

#### 2. `createEachJob` оставить

У него остаётся отдельное назначение: подготовить запускаемую подписку после
отказов ядра и перед запуском. В `solo` это место контрольной точки родителя;
чистая фабрика `child` такой точкой быть не должна. Сохранение хука также
оставляет работающими внешние движки, которые его уже переопределяют.
Делегирование по умолчанию в `child<void>` даёт новой фабрике единый путь для
обычного случая.

«Удалить нельзя» в дизайне лучше понимать как «в этой модели без замены точки
расширения». Технически можно придумать новый pre-start-хук, но это ещё один
API и миграция без выигрыша для текущей заявки. Отдельный тест прототипа
доказал вызов переопределённого `child` из `each`, а полный набор — сохранение
старого `EachContext.createEachJob`.

#### 3. `cancellable:` сейчас не добавлять, но не называть `uncancellable` эквивалентом

Для срока шага и пробуждаемой паузы нужен именно отменяемый ребёнок.
Предъявленного случая, которому необходимо отклонять отмену целиком, в заявке
нет. Добавить необязательный параметр позже возможно отдельной работой с учётом
переопределений фабрики.

При этом `uncancellable` лишь придерживает отмену до конца секции,
а `cancellable: false` её отклоняет. Секция не обещает успешный исход ребёнка
и выдачу его значения. Для `runAll` это также меняет судьбу значения
и `discard`. Проверено отдельным зондом `zz_uncancellable.dart`; его два тела:

```dart
Job.deferred<int>(cancellable: false, (_) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return 42;
})
```

```dart
Job.deferred<int>((c) => c.uncancellable(() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return 42;
}))
```

После `step.cancel()` во время ожидания точный вывод:

```text
cancellable:false: child=Done(42); parent=Done(null)
uncancellable body: child=Cancelled(manual); parent=Done(null)
```

Строки 113–115 стоит уточнить: секция защищает выполнение участка,
но не заменяет неотменяемую задачу. Если потребитель потребует сохранить
успешный результат при отмене извне, вопрос о параметре нужно решать заново.
Это соответствует различию решений 5 и 6 `docs/settled.md`.

### Что добавить и чего не расширять в плане

Помимо трёх находок, в тестовом плане явно назвать следующие сценарии:

- `child` в уборке и на сохранённом завершённом контексте; тест 5 сейчас
  называет только `unattended` и конец тела. На отменённой ещё работающей
  задаче нужен другой результат: отмена родителя, а не `StateError`.
- При переносе `_solo.job` в `child` проверить сам новый путь на `W`,
  отсутствие повторного `canStart`, независимость `cancellable` и работу
  `keepWhile` после конца тела. Тест 9 проверяет только отказ при старте.
  Старые тесты `each` полезны, но не заменяют все эти утверждения о `child`.
- Срок до запуска не идёт; ноль и отрицательное значение бросают синхронно
  в обоих движках. В `solo` проверить оба исхода перехвата срока
  и `ifCancelled`, показанные выше, а не только продолжение очереди.
- `start` ждётся родителем без чтения исхода; `runAll` принимает новые хэндлы
  и останавливает соседнюю ветку на провале. Сам барьер группы повторно
  проектировать и весь набор `runAll` дублировать не требуется.
- Сохранить тесты порядка отказов и уже принятой отмены у `each`. Проверка
  «родитель нарушил правило, но уже отменён вручную» защищает `ifCancelled`;
  без неё перенос `_checkedState` кажется безобидным.
- Обновить `time_rakes_test.dart` и `test/support/time_page.dart` вместе
  с примером `time.md`; для других изменяемых блоков обновить соответствующие
  `children_rakes_test.dart`, `extending_rakes_test.dart` и support-файлы.
  Сверять оригинал, перевод, код блока и трассу, а не только компиляцию API.

Лишних функциональных пунктов в текущих 12 тестах не вижу. Тест пробуждаемой
паузы нужен как проверка заявки, даже если рецепт не публикуется. Не нужно
из-за этой работы добавлять рецепт на страницы, менять семантику `runAll`,
открывать защищённый `Solo.job`, переносить владение ресурсами или заводить
новый движок. Нужны уточнение договора, недостающие страницы и адресные
проверки, а не расширение возможностей.

Границы проверки: SDK Dart 3.13.0 на macOS arm64; пол Dart 3.6.0, Flutter,
веб-компиляция, пакеты примеров и полный scopo не прогонялись. Прототип не был
законченной реализацией с документацией и анализом линтов. Его цель — проверить
проектируемый контракт на нынешнем ядре.
