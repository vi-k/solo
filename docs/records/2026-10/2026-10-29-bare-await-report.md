> **Состояние на 2026-10-29:** сделано в ветке работы, не опубликовано; новая
> версия `solo_lints` с правилом выходит отдельным выпуском.
> **Что это:** отчёт о правиле `bare_await` и ответ на отчёт сессии tez: что
> сделано, что проверено, ревью дизайна и прототипа с вердиктами.
> **Связанные записи:** `2026-10-29-bare-await-design.md`,
> `2026-10-28-solo-lints-report.md`, `2026-10-28-solo-lints-wave-2-report.md`.

# `bare_await`: отчёт

## Что сделано

Отчёт tez пришёл четырьмя пунктами. Три первых в коде `solo_lints` не чинятся,
их диагнозы — в «Что ещё в этой работе» записи
`2026-10-29-bare-await-design.md`; README получил абзацы об уровне правила,
о `dart fix` и о двойных диагнозах Dart 3.12.

Четвёртый пункт — правило `bare_await`, линт. Прототип с дизайном лежал
в коммите `f9621115`; независимое ревью нашло 17 пунктов, и правило переписано
по ним, дизайн тоже. Что правило ловит и пропускает — в записи дизайна. Вместе
с правилом:

- признак вопроса к задаче в `catch` (`askingStatement`, `isRethrowIf`,
  `isRethrow`) переехал из `catch_without_check` в `lib/src/context.dart`,
  и оба правила берут его оттуда;
- сторож страницы ошибок ждёт `bare_await` у пары «Each wait in its place»;
- README и его перевод получили раздел правила, строку таблицы и линт в списке
  установки; CHANGELOG и перевод — раздел «Unreleased».

## Что проверено

- `dart format`, `dart analyze --fatal-infos` и `dart test` в `solo_lints`:
  набор зелёный.
- Мутации: 40 мутаций исключений правила, по одной; каждая роняет тест.
  Выжившую в первом проходе — префикс импорта у `Future.wait` — убил тест
  `test_prefixed_future`.
- Замер шума по дереву — в записи дизайна; нули примеров подтверждены
  контрольным файлом.
- Уровень `warning` и код выхода 2 — на Dart 3.10.0 и 3.13.0; двойные
  диагнозы — на Dart 3.12.2 есть, на 3.10.0 и 3.13.0 нет.

## Независимое ревью

Ревьюер на Opus читал коммит `f9621115` в своей копии дерева и доказывал
находки зондами через `RuleTest`. Ниже его отчёт как есть, под каждой
находкой — вердикт. Случаи зондов вошли в `test/bare_await_test.dart`.

Ревью дизайна `2026-10-29-bare-await-design.md` и прототипа `bare_await`
(коммит f9621115)

Проверено так: в копии на f9621115 (`git log --oneline -2`:
`f9621115 feat(solo_lints): add a first version of the bare_await lint`, ниже
`daa51c55 docs: record the releases of flutter_solo 0.6.0 and solo_lints
0.1.0`; файл `packages/solo_lints/lib/src/rules/bare_await.dart` на месте)
выполнены `dart pub get` в трёх пакетах и `dart analyze .` по `async_job`
и `solo` с включённым правилом. Кроме того, зонды через `RuleTest` (24 теста)
и прогон сторожа `mistakes_page_test.dart` с `bare_await` в наборе. Собственный
набор `solo_lints` на прототипе зелёный: 149 тестов.

Итог прогона по дереву (Dart 3.13.0): `async_job` 202 находки, `solo` 154.
В коде страниц у `async_job` 8 находок, плюс одна в `observing_rakes.dart`;
у `solo` 7.

**1. Бесконечная рекурсия на финальной переменной, которая ссылается на себя.**
Критично.

`through` (bare_await.dart:157–159) и `_isChild` (:196) идут по инициализатору
финальной локальной переменной, а множества посещённых у них нет. Падает
и `late final`, и обычная `final` с ошибкой компиляции. Вторая получается сама,
пока пользователь набирает код, так что в редакторе плагин будет падать
на незаконченном коде. Зонд:

```dart
final job = Job<void>((ctx) async {
  final Future<void> f = f;   // и late final Future<void> f = f;
  await f;                    // и late final Job<void> c = c; await c.value;
});
```

Все три варианта дают `Stack Overflow` в `_Waits.through`
и `_Waits._finalLocalValue`.

Предлагаю завести в `_Waits` множество посещённых элементов, а инициализатор
принимать только тогда, когда объявление стоит до использования и использование
не лежит внутри него. Заодно стоит сузить `_InitializerFinder` (:241–245):
сейчас он обходит весь файл на каждом идентификаторе и не останавливается после
находки. Локальная переменная всегда лежит в объемлющей функции, искать
достаточно там.

**Вердикт.** Принята. Сделано: `_finalLocalValue` берёт инициализатор, только
если объявление кончилось до использования, — самоссылка и взаимная ссылка двух
переменных значения не дают, и множество посещённых не понадобилось. Сужение
поиска объявления до объемлющей функции не сделано: обход файла остаётся, как
в пункте 118 `docs/settled.md`, решение — пункт 125. Тест
`test_read_in_its_own_initializer` проверяет код с ошибкой самоссылки.

**2. Прототип ловит правильный ответ страницы, а дизайн записывает его
в неправильные.** Критично.

`packages/async_job/test/support/cleanup_page.dart:118–125` (`plainAwait`) —
это код раздела «Registering after a plain `await`» страницы `cleanup-rules.md`
(строки 242–256). Шапка файла говорит: «The code … that works, verbatim».
Страница прямо учит: «Registration works after a plain `await` as well. A plain
`await` is no checkpoint … nothing can throw between the call and the line
under it». Прогон даёт на этом месте `bare_await` (cleanup_page.dart:120:22).
В дизайне, в «Замере шума», эта находка названа «открытие ресурса голым
`await`, где у страницы `ctx.abandonable` с `dispose:` (`cleanup.md`)», то есть
неправильной формой. Это не так.

Здесь спорят доктрина и страница. Заменить на член контекста нечем: любой
член — контрольная точка, и строка регистрации под ним может не выполниться.
Зонд `test_cleanup_rules_plain_await` красный:

```dart
final job = Job<Api>((ctx) async {
  final database = await Future.value(api);
  ctx.onDiscard(database.close);
  return database;
});
```

Предлагаю решение владельца, одно из двух:
- (а) Исключение по форме: голый `await` — инициализатор финальной локальной
  переменной, а следующий оператор — `ctx.onDispose`/`ctx.onDiscard`, который
  её упоминает. Это ровно та форма, за которой `release_on_the_call` следит
  после `join`, только наоборот.
- (б) Раздел страницы получает `// ignore:` с объяснением.

Абзац «Замер шума» в любом случае надо исправить.

**Вердикт.** Принята частично. «Замер шума» исправлен: находка названа
правильным ответом страницы. Ни (а), ни (б) не сделано: правило стоит
на доктрине и находку оставляет, а исключение по форме сделало бы законным
голый `await` перед любой регистрацией. Судьба раздела `cleanup-rules.md` —
вопрос владельцу, он в `docs/handoff.md`.

**3. Исключение «`catch` целиком» пропускает канонический голый `await`.**
Важно.

bare_await.dart:105 молчит на любом `await` внутри `catch`. Доктрина
(`docs/architecture.md`, «Кооперативная отмена») оставляет голый `await` только
«там, где обернуть нечем: уборка после уже случившейся отмены». Узкий `catch`
с задержкой перед повтором — это не уборка. Ровно эту ошибку разбирает
`solo/doc/errors.md:447–461` («A plain `Future.delayed` is no checkpoint»),
а правильный ответ там — `ctx.pause`. Страница сама советует заменить
`on Object` на `on ApiException`, и тогда ни `bare_await`,
ни `catch_without_check` форму не видят. Зонд `test_catch_retry_delay` красный,
диагноза нет:

```dart
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(() => api.upload('note'));
      return;
    } on ApiException {
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
});
```

Тем же исключением молчит и `await for` в `catch` (`test_await_for_in_catch`).

Предлагаю в `catch` пропускать `await` только после того, как `catch` спросил
задачу. Признак тот же, что у `catch_without_check`: контрольная точка после
строк `if (...) rethrow;` или `if (ctx.job.isCancelled) rethrow;`. Клауза
`on Cancelled` пропускается целиком. Последствие для сторожа — в находке 13.

`finally` (:106) молчит и на сетевом вызове (`test_finally_upload`:
`finally { await api.upload('report'); }`). Оставить его можно как уборку
уровня тела, но тогда это надо сказать в «Что правило пропускает» прямо.

**Вердикт.** Принята. Сделано: `catch` пропускается, только если он
`on Cancelled`, кончается `rethrow;` или `await` стоит после оператора, которым
`catch` спросил задачу; признак вопроса вынесен из `catch_without_check`
в `context.dart` (`askingStatement`), и оба правила берут его оттуда. Сверх
предложенного пропускается `catch`, который кончается `rethrow;`: это
освобождение на выходе, и пара страницы ошибок остаётся за одним правилом
(находка 13). `finally` пропускается целиком, и дизайн говорит это прямо,
решение — пункт 121. Тесты `test_retry_delay_in_a_catch`,
`test_await_for_in_a_catch`, `test_broad_catch_that_goes_on`,
`test_catch_that_handles_a_cancellation`.

**4. «Ребёнок контекста» определён неверно в обе стороны.** Важно.

`_children = {'each', 'child'}` (bare_await.dart:63). Dartdoc
`JobContext.child` (`packages/async_job/lib/src/job_context.dart:272–282`):
«Starts nothing … Until it starts, the child belongs to whoever holds it: no
job waits for it or cancels it … its `done` does not complete». Значит,
`final rows = ctx.child(...); await rows.value;` — вечное ожидание, которое
отмену не слышит, а правило молчит (`test_unstarted_child_value` красный).

И наоборот: ребёнок, запущенный через `ctx.start(rows)`
(`solo/doc/reference.md:118`: «leaves its outcome to whoever holds it»; dartdoc
`start`: «the parent's cancellation cascades onto it»), читателю ждать законно.
Прототип такое ожидание ловит (`test_started_child` красный):

```dart
final rows = Job.deferred<int>((c) => c.abandonable(() async => 1));
ctx.start(rows);
await rows.value;
```

Предлагаю считать ребёнком результат `ctx.each(...)` и переменную, которую
раньше в том же или объемлющем блоке передали в `ctx.start(v)`. Обход для этого
тот же, что у `_releases`. `ctx.child(...)` без запуска ребёнком не считать.

**Вердикт.** Принята, сделано как предложено: ребёнок — результат
`ctx.each(...)` и переменная, переданная раньше в `ctx.start(v)`; `ctx.child`
без запуска ребёнком не считается. Тесты `test_children`,
`test_unstarted_child`.

**5. `_handsOverContext`: годится любой параметр.** Важно.

bare_await.dart:203–206 пропускает любой вызов, которому передан `ctx`,
какого бы типа ни был параметр. Зонд `test_hands_over_to_object` красный: оба
`await` молчат.

```dart
Future<void> track(Object anything) async {}
...
await track(ctx);
await api.upload('note', ctx);   // параметр Object?
```

Предлагаю засчитывать передачу, только если параметр, которому соответствует
аргумент, объявлен типом `JobContext` или его подтипом (`isJobContext` по типу
соответствующего параметра). `runInIsolate(ctx, …)` из `cancellation.md` под
это условие подходит.

**Вердикт.** Принята, сделано как предложено: передача засчитывается, только
если соответствующий параметр типа `JobContext`. Тесты
`test_hands_over_the_context`, `test_hands_over_to_an_object`.

**6. `_releases`: после `ctx.disown(v)` годится любой метод `v`, без
ограничения расстояния.** Важно.

bare_await.dart:214–238. Зонд `test_disown_then_any_method` красный: после
`ctx.disown(db)` молчат и `await db.migrate()`, и `await db.upload('note')`.
Обратная сторона: `if (ctx.disown(db)) await db.close();` (dartdoc говорит, что
`disown` возвращает, нашёл ли он значение) и каскад `ctx..check()..disown(db)`
(`solo/doc/resources.md:255`) правило ловит (`test_disown_in_condition`
и `test_disown_cascade` красные).

Предлагаю пропускать только `await v.m()` в операторе сразу после `disown`, как
в `cleanup.md:181–183`. Ещё точнее — когда `m` совпадает с методом
из `dispose:`/`discard:` вызова, принёсшего `v`. Форму в условии `if` и каскад
узнавать.

**Вердикт.** Принята. Сделано: пропускается только оператор сразу после
`disown`, форма в условии `if` и каскад узнаются. Сверка метода с `dispose:`
не сделана: освобождение не обязано повторять то, что было передано очистке,
решение — пункт 123. Тесты `test_release_later_than_disown`,
`test_release_after_disown_in_a_condition`,
`test_release_after_disown_in_a_cascade`.

**7. Тело с параметром `_` правило не проверяет вовсе.** Важно.

`jobContextOf` (context.dart:93) возвращает `null` для `_`: другим правилам
на таком теле нечего проверять. Для `bare_await` это наоборот: тело, которое
не назвало контекст, ждать через него не может, и каждый `await` в нём голый.
Зонд `test_wildcard_body` красный:
`Job<void>((_) async { await api.upload('x'); })` молчит.

Предлагаю для этого правила признавать тело по типу первого параметра, даже
если это `_`. В сообщении тогда вместо `'_'` должно стоять `'ctx'` или «the
context».

**Вердикт.** Принята, сделано как предложено: тело признаётся по типу первого
параметра, и `_` тоже; в сообщении тогда стоит `'ctx'`. Тест
`test_wildcard_context`.

**8. `cancellable: false`: узнаётся слишком узко, а сказано о нём слишком
широко.** Важно.

(а) bare_await.dart:116–120 узнаёт только литерал `false` и только
у тела-литерала в списке аргументов. Ложные срабатывания: функция верхнего
уровня, переданная по имени (`Job<void>(backup, cancellable: false)`
с `Future<void> backup(JobContext ctx) async { await api.upload('backup'); }`,
зонд `test_top_level_body_cancellable_false`), и константа
(`const refuse = false; Job<void>(cancellable: refuse, …)`, зонд
`test_cancellable_const`). Функцию верхнего уровня как тело правило признаёт
(пункт 117 `docs/settled.md`), а её `cancellable: false` не видит. Предлагаю
предварительный проход по файлу: вызовы с `cancellable:`, константное значение
которого `false`, плюс `functionOf` от аргумента-тела дают множество
отказывающих тел.

(б) Фраза дизайна «Отмена до такого тела не доходит» неверна.
`solo/doc/cancellation.md:28–29, 216–223`: «neither a section nor
`cancellable: false`» не удерживает отмену по правилам состояния. В ядре
`cancelOwnJob` с `rejectable: false` доходит тоже
(`async_job/doc/engine.md:370, 430`). Пункт 80 `settled.md` верен для оплаты
`vs-bloc.md` только потому, что её рабочий тип — весь `CheckoutState`, и правил
у задачи нет. Предлагаю либо сузить исключение для `solo`: рабочий тип равен
типу состояния контроллера и нет `keepWhile`. Либо оставить как есть,
но переписать причину честно: «отклоняется отмена-запрос; отмену по правилам
голый `await` всё равно не слышит, это принятый пробел».

**Вердикт.** Принята. (а) Сделано: константа `false` узнаётся, а функция
верхнего уровня пропускается, если каждый вызов, которому она передана
по имени, отказывается от отмены; вместо предварительного прохода — обход файла
на такую функцию. (б) Причина в дизайне переписана честно, вторым вариантом:
исключение остаётся для любого тела, отмену по правилам состояния голый `await`
не слышит, это принятый пробел, решение — пункт 124. Тест
`test_body_declared_at_the_top_level`.

**9. Засчитывается любой контекст, а не контекст этого тела.** Мелко.

`callsOn(node, owner, _waiting)` (:143) берёт `owner` из цели вызова, а не тело
`ctx`. В колбэке `each` правило пропускает `await ctx.join(...)` родителя
(`test_parent_ctx_in_child` красный). Страница
`async_job/doc/streams.md:180–183` говорит, что так ребёнок, отменённый
в одиночку, «runs both steps to the end». Предлагаю засчитывать только члены
контекста ближайшего тела. Если оставить как есть, сказать об этом в дизайне.

**Вердикт.** Принята, сделано как предложено: засчитываются только члены
контекста ближайшего тела. Тест `test_context_of_the_parent`.

**10. `_isFuture`: `Object` и параметры типа не считаются future.** Мелко.

bare_await.dart:254: всё, что не `InterfaceType`, считается не future.
`await f` с `F extends Future<void>` (`test_type_parameter_future`) и `await x`
с `final Object x = api.upload('n')` (`test_object`) молчат. При этом `dynamic`
считается future (так и есть, зонд `test_dynamic` зелёный). Предлагаю
перевернуть проверку: «не future» — только известный класс, который
не реализует `Future` и не равен `Object`. Параметр типа брать по его границе.

**Вердикт.** Принята. Сделано: future — ещё `Object` и параметр типа по его
границе, вместе с `dynamic`. Тест `test_hidden_futures`.

**11. Мелкие ложные срабатывания на формах, которые читатель напишет
по тексту.** Мелко.

- `var saving = ctx.each(...)` вместо `final` (`test_var_child`).
- `await Future.wait([for (final j in jobs) ctx.run(j)])`
  (`test_future_wait_for_element`): `_all` не принимает `ForElement` и spread.
- `async.Future.wait` с префиксом импорта: `_isFutureClass` (:259) смотрит
  только `SimpleIdentifier`.

Их достаточно назвать в «Чего правило не ловит / ловит лишнее», либо узнать:
локальная переменная без повторного присваивания; элемент `for` и `if`, тело
которого разрешено.

**Вердикт.** Принята частично. Элементы `for` и `if` списка и префикс импорта
у `Future.wait` узнаются (тесты `test_collection_elements`,
`test_prefixed_future`). Ребёнок в `var` и `...` в списке названы в дизайне
и README лишними находками, решение — пункт 122.

**12. Исключение «вложенная функция» молчит на цикле внутри одного `join`.**
Мелко, но о нём надо сказать.

`await ctx.join(() async { for (final c in chunks) await device.write(c); })`
правило пропускает, хотя это та же ошибка, что в неправильном блоке пары «Each
wait in its place»: отменённая выгрузка дописывает всё. Подсказка правила
(«Wait through 'ctx.join'») ведёт читателя именно к такой обёртке. Предлагаю
хотя бы назвать это в «Чего правило не ловит» и в README. Локальную функцию,
наоборот, правило ловит в месте вызова: `await step()` даёт диагноз
(`test_local_function_call` зелёный). Пункт «Локальную функцию тела, которая
ждёт мимо контекста» в «Чего правило не ловит» неточен, мимо правила проходит
только незаавейченный вызов.

**Вердикт.** Принята. Цикл внутри одного `join` назван в дизайне («Чего правило
не ловит») и в README, решение — пункт 120. Пункт о локальной функции
исправлен: правило ловит её в месте, где тело ждёт вызова.

**13. Пересечение с другими правилами и сторож страницы ошибок.** Важно для
плана.

Проверено: если добавить `BareAwait()` в `_lints` сторожа
`packages/solo_lints/test/mistakes_page_test.dart` и записать
`('Each wait in its place', 1): 'bare_await'`, сторож зелёный: 25 из 25. Сейчас
ни одна пара не ломается. Двойных диагнозов с `await_own_queue` нет:
`ownQueueCall` общий, правило молчит. С `ctx_in_cleanup` их тоже нет: уборку
правило не смотрит.

Сломается всё при исправлении находки 3. Неправильный блок пары «Letting
cancellation through a catch» (`await hw.reset()` первой строкой
`on Object catch`) получит два правила, `catch_without_check` и `bare_await`.
А сторож требует ровно одно (`expect(reported, {expected})`). Так же двумя
правилами станет первая попытка из `errors.md:447`. Надо заранее решить одно
из двух:
- (а) значения `_table` становятся множествами, и пара называет оба правила;
- (б) `bare_await` молчит в широком `catch`, о котором уже говорит
  `catch_without_check`. Но `catch_without_check` — lint и может быть выключен,
  так что этот вариант хуже.

Правильный блок этой пары (`ctx.check();` перед `await hw.reset()`) при
предложенном сужении молчит.

**Вердикт.** Принята, решено третьим путём: `catch`, который кончается
`rethrow;`, `bare_await` пропускает (находка 3), поэтому неправильный блок пары
«Letting cancellation through a catch» остаётся за одним `catch_without_check`.
Таблица сторожа осталась с одним правилом на пару, сторож зелёный.

**14. Уровень lint против warning.** Решение верное. Мелкие поправки к README.

Довод дизайна подтверждён замером: 194 из 202 и 148 из 154 находок лежат
в тестах, где голый `await` стоит нарочно. Подъём до `warning` работает:
с `bare_await: warning` прогон `async_job` дал 202 диагноза уровня `warning`
и код выхода 2 на Dart 3.13.0 и на полу, Dart 3.10.0 (Flutter 3.38.1).

Но у пользователя, который поднимет правило ради CI, его тесты загорятся
так же. Чем их исключить, замерено:
- Вложенный `test/analysis_options.yaml` с секцией
  `plugins: … bare_await: false` правило в `test/` гасит. Но сам файл даёт
  `warning - Plugins can only be specified in the root of a pub workspace or
  the root of a package…`, то есть тот же код выхода 2.
- `analyzer: errors: bare_await: ignore` и `solo_lints/bare_await: ignore` дают
  `unrecognized_error_code`, а правило продолжает работать.
- Остаётся `// ignore_for_file: solo_lints/bare_await` в каждом файле.

README должен сказать это прямо. Либо дизайн решает, что правило само
пропускает файлы под `test/`; это вопрос владельцу.

**Вердикт.** Принята. README говорит, что проект с гейтом ставит
`// ignore_for_file: solo_lints/bare_await` в файлы тестов, где тело стоит
на голом ожидании. Пропускать `test/` правило само не будет: голый `await`
в теле теста пользователя бывает и ошибкой. Решение — пункт 119.

**15. Текст сообщения и подсказки.** Мелко.

- `await for` получает ту же подсказку про `join`/`abandonable`/`pause`
  (bare_await.dart:93), а дизайн говорит, что ответ — `ctx.each`. Нужен
  отдельный `LintCode` или своя подсказка для `await for`.
- «put the call in 'ctx.uncancellable' when it must not be cut short»: вызов
  не обрывает и `join`. Отличие `uncancellable` в том, что после вызова
  выполняются и следующие шаги секции. Предлагаю: «…or 'ctx.uncancellable' when
  the steps after it must run too».
- Для тела с `_` (находка 7) подставится `'_'`.

**Вердикт.** Принята, сделано как предложено: у `await for` свой код
с подсказкой `'{0}.each'`, подсказка про `uncancellable` теперь «put the steps
that must all run in '{0}.uncancellable'», у тела с `_` в тексте `'ctx'`.

**16. Неточности в «Замере шума».** Мелко.

- У `solo` 154 находки, а не 156; в коде страниц 7, а не 8.
- Находка `observing.md` — это не «правка документа». В самом блоке страницы
  стоит только строка `ctx.log(...)` (`async_job/doc/observing.md:150, 160`),
  а `await migrate()` живёт в обёртке
  `packages/async_job/test/support/observing_page.dart:65`
  и `observing_first_attempts.dart:19`. Править надо код страницы.
- Находка 2 выше — вторая находка на правильном ответе, а не неправильная
  форма.

**Вердикт.** Принята. Числа перемерены на переписанном правиле: `async_job`
215, `solo` 156, примеры 0 с контрольным файлом. Находка `observing.md` названа
правкой кода страницы, `cleanup-rules.md` — правильным ответом.

**17. Что недоопределено для реализации.**

- Чей контекст засчитывается: ближайшего тела или любой (находка 9).
- Тело с `_` (находка 7).
- Тела по ссылке при `cancellable: false`, а также `cancellable:` через
  константу (находка 8а).
- Что значит `cancellable: false` для `solo` (находка 8б).
- Какой `catch` уборка, а какой нет; судьба `finally` (находка 3).
- Ребёнок: `ctx.child` против `ctx.start` (находка 4).
- Поведение на коде с ошибками: рекурсия (находка 1) и неразрешённые типы.
- Определение тела расходится с `bodyContextAround` у `catch_without_check`:
  для того действие `join` и локальная функция — часть тела, для `bare_await`
  нет. Это осознанно, но об этом надо сказать в дизайне.
- Как пользователю держать гейт CI без тестов (находка 14).
- Отдельная подсказка для `await for` (находка 15).
- Как сторож страницы ошибок примет пару с двумя правилами (находка 13).

**Вердикт.** Принята. Дизайн отвечает на каждый пункт: контекст ближайшего тела
(пункт 1 «пропускает»), тело с `_` («ловит»), `cancellable: false` (пункт 10),
`catch` и `finally` (пункты 7 и 8), ребёнок (пункт 2), код с ошибками («Чего
правило не ловит»), расхождение с `bodyContextAround` (абзац после списка),
гейт CI без тестов («Уровень»), подсказка `await for` («ловит»), сторож
(«Проверка правила»).

**Код зондов.** Общая обвязка — `RuleTest` из `test/support/rule_base.dart`,
правило `BareAwait()`, у каждого теста префикс:

```dart
const _api = r'''
import 'package:async_job/async_job.dart';

abstract interface class Api {
  Future<void> upload(Object note, [Object? extra]);
  Future<void> close();
  Future<void> migrate();
}

class ApiException implements Exception {}

late final Api api;
late final Stream<int> events;

Future<void> track(Object anything) async {}
''';
```

Каждый тест — `assertAt('''$_api …тело из находки…''', [...])`, где список
задаёт, что правило должно сказать. 21 из 24 зондов красные, то есть правило
ведёт себя не так. Это `hands_over_to_object`, `disown_then_any_method`,
`catch_retry_delay`, `finally_upload`, `cleanup_rules_plain_await`,
`top_level_body_cancellable_false`, `cancellable_const`, `started_child`,
`var_child`, `future_wait_for_element`, `parent_ctx_in_child`,
`await_for_in_catch`, `type_parameter_future`, `object`, `self_reference_late`,
`self_reference_child`, `self_reference_plain`, `wildcard_body`,
`disown_in_condition`, `disown_cascade`, `unstarted_child_value`. Зелёные:
`await_for_element` (`await for` в `ForElement` ловится), `dynamic`
и `local_function_call`.

**Общий вердикт.** По дизайну реализовывать пока рано, но править нужно
немного. Уровень lint, подсветка на `await`, общий с `await_own_queue` признак
своей очереди и сторож страницы ошибок выбраны верно, и сейчас ни одна пара
страницы не ломается. До реализации надо:

1. Исправить рекурсию (находка 1).
2. Решить спор с `cleanup-rules.md` и исправить «Замер шума» (находки 2 и 16).
3. Сузить исключения `catch` (3), «ребёнок» (4), «передан контекст» (5)
   и `disown` (6). Признавать тело с `_` (7).
4. Переписать пункт 9 о `cancellable: false`: что именно он узнаёт и какую
   отмену на самом деле отклоняет (8).
5. Заранее решить, как сторож страницы ошибок примет пару с двумя правилами
   (13), и записать в README, как держать тесты вне гейта (14).

Остальное (9–12, 15) можно оставить исполнителю. Достаточно, чтобы дизайн
называл каждый пункт либо исключением, либо известным пробелом.

Ничего не закоммичено. В копии остались изменённые `analysis_options.yaml`
у `async_job` и `solo`, правка `mistakes_page_test.dart`
и `test/review_probe_test.dart` в `solo_lints`; копию удалят.
