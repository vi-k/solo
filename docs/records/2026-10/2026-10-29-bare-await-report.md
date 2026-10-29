> **Состояние на 2026-10-29:** сделано и опубликовано в `solo_lints` 0.1.1,
> `2026-10-29-solo-lints-release-report.md`.
> **Что это:** отчёт о правиле `bare_await` и ответ на отчёт сессии tez: что
> сделано, что проверено, ревью дизайна и прототипа, повторное ревью
> переписанного правила и третье ревью правок по нему, с вердиктами.
> **Связанные записи:** `2026-10-29-bare-await-design.md`,
> `2026-10-29-solo-lints-release-report.md`,
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
  `isRethrow`) и признак `catch`, который ловит отмену (`takesCancelled`),
  переехали из `catch_without_check` в `lib/src/context.dart`; вопрос к задаче
  после повторного ревью нужен одному `catch_without_check`, `isRethrow`
  и `takesCancelled` — обоим правилам;
- сторож страницы ошибок ждёт `bare_await` у пары «Each wait in its place»;
- README и его перевод получили раздел правила, строку таблицы и линт в списке
  установки; CHANGELOG и перевод — раздел «Unreleased»;
- раздел «Registering after a plain `await`» `cleanup-rules.md` ядра и его
  перевод получили по слову владельца фразу: такое ожидание называет
  `bare_await`, регистрация после него надёжна, но задача кончается не раньше
  вызова.

Повторное ревью переписанного правила, коммит `3a61a484`, нашло 10 пунктов.
По ним из `catch` убрано исключение «спросил задачу», `rethrow;` пропускает
только `catch`, который ловит отмену, засчитан именованный параметр
`JobContext`, запущенный ребёнок в `var` больше не засчитывается, пустой список
`Future.wait` не называется; редкие формы названы в README и решениях 126
и 127.

Третье ревью на `d957ca0b` нашло пять пунктов у Opus и один у Codex, и он же —
второй пункт Opus. По ним широкий `catch` с `rethrow;` в конце проверяется как
тело, если раньше из него уходят `return`, `break` или `continue`; прежний
`ctx.start(v)` засчитывается только для финальной переменной или геттера
финального поля; тесты держат все широкие типы `catch`; README называет
`on Outcome`.

## Что проверено

- `dart format`, `dart analyze --fatal-infos` и `dart test` в `solo_lints`:
  набор зелёный.
- Мутации: 40 мутаций исключений правила, по одной; каждая роняет тест.
  Выжившую в первом проходе — префикс импорта у `Future.wait` — убил тест
  `test_prefixed_future`. После повторного ревью — 45 мутаций, и каждая роняет
  тест, `every` на `any` у тела верхнего уровня тоже. После третьего ревью — 10
  мутаций правок, K1–K10, и каждая роняет тест; выжившую в первом проходе K7,
  вычисляемый геттер, убил геттер в `test_child_replaced_after_start`.
- Замер шума по дереву — в записи дизайна; нули примеров подтверждены
  контрольным файлом. После повторного ревью список находок `async_job`
  и `solo` совпал с прежним построчно, после третьего — тоже.
- Пол по коммиту `2449e246`: `tool/archive_floor.py` на Flutter 3.38.1 с Dart
  3.10.0 зелёный по всем пакетам, и набор `solo_lints` на нижних границах,
  analyzer 12.1.0 и analyzer_testing 0.2.5, — 190 тестов зелёные. На `3a61a484`
  пол краснел: `testFilePath`, которым тест кода с ошибкой записывал файл,
  в analyzer_testing 0.2.5 нет, и тест теперь пишет через `testFile`.
- Пол по коммиту `3083654b`, правкам третьего ревью: `tool/archive_floor.py`
  зелёный по всем пакетам, набор `solo_lints` на analyzer 12.1.0
  и analyzer_testing 0.2.5 — 191 тест зелёный.
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
вопрос владельцу, он в `docs/handoff.md`. Итог: владелец выбрал фразу
в разделе. В `cleanup-rules.md` ядра и переводе дописано, что такое ожидание
и называет `bare_await`: регистрация после него надёжна, но задача кончается
не раньше вызова. Вопрос из `docs/handoff.md` снят.

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
`test_catch_that_handles_a_cancellation`. Итог второго ревью: исключение «после
вопроса» убрано (находка 1 второго ревью), а `rethrow;` в конце пропускает
только `catch`, который ловит отмену (находка 4). `on Cancelled` и `finally` —
как были.

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
`test_hands_over_the_context`, `test_hands_over_to_an_object`. Итог второго
ревью: засчитывается и именованный параметр (находка 2 второго ревью).

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
`test_body_declared_at_the_top_level`. Итог второго ревью: тест на функцию,
переданную дважды, с отказом и без (находка 8 второго ревью), и README называет
тело верхнего уровня (находка 6).

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
Таблица сторожа осталась с одним правилом на пару, сторож зелёный. Итог второго
ревью: `rethrow;` пропускает только широкий `catch` (находка 4 второго ревью);
`catch` пары «Letting cancellation through a catch» — `on Object`, и сторож
остался зелёным.

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
правкой кода страницы, `cleanup-rules.md` — правильным ответом. Итог второго
ревью: ожидание своего продолжения разбирает `chains.md` ядра,
а не `children.md` (находка 7 второго ревью); числа на правиле после второго
ревью те же, список совпал построчно.

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

## Повторное ревью

Второй ревьюер на Opus читал коммит `3a61a484`, переписанное правило, в своей
копии дерева: сверил 17 находок первого ревью и искал новое. Зонды — через
`RuleTest`, на настоящем SDK и мутациями правила. Ниже его отчёт как есть, под
каждой находкой — вердикт; случаи зондов вошли в `test/bare_await_test.dart`.

Проверено в копии на отвязанном HEAD `3a61a484` (`git log --oneline -1`:
`3a61a484 feat(solo_lints): finish the bare_await lint after review`). Dart
3.13.0, analyzer 14.6.0 из `pubspec.lock` пакета.

Как проверял:

- зонды через `RuleTest` во временных файлах `test/zz_rereview_probe_test.dart`
  и `test/zz_rereview_probe2_test.dart` (удалены), каждый печатает найденные
  диагнозы;
- зонды на настоящем SDK: файл `test/zz_probe.dart` в `async_job` копии
  и плагин из дерева в `analysis_options.yaml` (`bare_await: true`, для сверки
  `catch_without_check` ещё и `catch_without_check: true`);
- полный `dart analyze .` по `async_job` и `solo` с правилом, до и после двух
  мутаций правила (копия исходника, не checkout);
- `dart test` в `solo_lints`: 187 зелёных до и после; `dart format`,
  `dart analyze --fatal-infos`, `check_translations.py`, `check_line_width.py`,
  `reflow.py --check` чистые.

Всё временное удалено, `analysis_options.yaml` и `bare_await.dart`
восстановлены из копий (`cmp` совпал), `git status` копии пуст.

Итог: 10 находок. Важная — 1 (№1). Мелкие — 9: расхождение с дизайном в коде —
2 (№2, №3), спорное исключение — 1 (№4), документы — 3 (№5–№7), пробел
в тестах — 1 (№8), ложные срабатывания и пропуск на редких формах — 2 (№9,
№10). Критичных нет. Регресса `catch_without_check` нет, падений на коде
с ошибками нет. Ложных срабатываний на правильных ответах страниц, кроме
известных (`cleanup-rules.md` и обёртки `observing.md`), нет.

### Сверка 17 находок первого ревью

| № | Состояние | Чем проверено |
|---|---|---|
| 1 | закрыта | `final Future<void> f = f; await f;` (ошибка компиляции), `late final Job<void> c = c; await c.value;`, взаимная `late final a = b; late final b = a;` — падения нет, на каждом `await` по одному `bare_await` |
| 2 | закрыта по вердикту | зонд страницы `Database.open()` даёт `bare_await`; «Замер шума» исправлен; вопрос владельцу в `docs/handoff.md`, строки 31–33 |
| 3 | закрыта не до конца | задержка в узком `catch` и `await for` в `catch` ловятся; новая дыра в исключении «спросил задачу» — находка 1 |
| 4 | закрыта | незапущенный `ctx.child` ловится; `ctx..start(a)..start(b)` и затем `await a.value`, `await b.done` молчат; `start` после `await` ловится; пробел с `var` — находка 10 |
| 5 | закрыта для позиционного аргумента | `track(Object)` ловится; `generic<C extends JobContext>(ctx)` молчит; именованный параметр `JobContext` не засчитывается — находка 2 |
| 6 | закрыта | тесты `test_release_*` |
| 7 | закрыта | `(_) async { await commit(); }` и колбэк `each` с `(_, tick)` ловятся, в тексте `ctx` |
| 8 | закрыта | `cancellable: Config.refuse` (static const) молчит; тело верхнего уровня, переданное дважды, с отказом и без, ловится; `cancellable: !true` ловится (не константа по форме, это честно); пробел в тестах — находка 8 |
| 9 | закрыта | `ctx.join` родителя в колбэке `each` ловится, сообщение называет контекст ребёнка (`child`) |
| 10 | закрыта | `T` без границы, `FutureOr<void>`, `Object?` ловятся; `N extends int` молчит |
| 11 | закрыта по вердикту | `for`/`if` в списке и префикс — тесты; `var` и `...` — пункт 122 |
| 12 | закрыта | дизайн, README, пункт 120; вызов локальной функции ловится — но и тогда, когда она ждёт через `ctx`, находка 3 |
| 13 | закрыта | сторож с `bare_await` в таблице зелёный |
| 14 | закрыта | README говорит про `ignore_for_file` |
| 15 | закрыта | тексты сообщений совпадают с дизайном, у `await for` свой код |
| 16 | закрыта | перемерено: `async_job` 215 (206 тесты, 1 `observing_rakes.dart`, 8 код страниц), `solo` 156 (142, 6 `lifecycle.dart`, 8); неточность в названии страницы — находка 7 |
| 17 | закрыта | кроме формулировки «`await for` ловится всегда» — находка 5 |

Сверка `catch_without_check` после переезда помощников: старый
`skipWhile(_isRethrowIf).firstOrNull` и новый цикл `askingStatement`
эквивалентны по чтению; зонд на настоящем SDK: `on Object { await reset(); }`,
`on Object { await reset(); rethrow; }` и `catch`, где все строки
`if (...) rethrow;` идут перед действием, — диагноз есть; после
`if (attempt == 3) rethrow; ctx.check();`, после
`if (ctx.job.isCancelled) rethrow;`, с `print` перед `rethrow;`
и с `final n = await ctx.join(...)` первой строкой — молчит. Как и раньше.

Код с ошибками: `await ctx.disown();`, `await Future.wait();`,
`await unknown.value;`, `await (ctx.join(commit), x: 1).wait;`, неразрешённый
тип переменной и контекста, `on {` без типа — падений нет.

Правильные ответы страниц: кроме полного прогона по дереву, прошёл по всем
блокам `dart` в `packages/async_job/doc/*.md` и `packages/solo/doc/*.md`
со словом `await` не через член контекста. Все правильные стоят внутри
`join`/`uncancellable`, в очистке, вне тела, у ребёнка `ctx.each`, у финальной
переменной с `ctx.run(...)` (`children.md`, `${await count}`) или под
`cancellable: false` (`vs-bloc.md`, пункт 80). Новых ложных нет.


### Находки

#### 1. Исключение «`catch` спросил задачу» пропускает задержку перед повтором. Важно.

`_handles` (`bare_await.dart:150–151`) молчит на любом `await` после
`askingStatement`: после `ctx.check();` или
`if (ctx.job.isCancelled) rethrow;`. Но проверка ловит только отмену, которая
уже пришла. Отмену, которая придёт во время `Future.delayed`, такой `catch`
не слышит: это та самая ошибка `solo/doc/errors.md`, «A plain `Future.delayed`
is no checkpoint», только на одну задержку короче. Страница говорит
о правильном ответе: «A cancellation that comes during a pause ends the pause
there». Хуже того, подсказка `catch_without_check` («Make ctx.check(); the
first line of the catch»), если пользователь применит её к первой попытке
страницы, приводит ровно к этой форме, и после этого молчат оба правила.

Зонд (`RuleTest` и настоящий SDK, `zz_probe.dart:47`):

```dart
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(commit);
      return;
    } on Object {
      ctx.check();
      if (attempt == 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
});
```

Результат: 0 диагнозов. Так же молчит вариант с `on DeviceError`
и `if (ctx.job.isCancelled) rethrow;` первой строкой.

Цена правки замерена мутацией: `_handles` без ветки `askingStatement` (то есть
`catch` пропускается только как `on Cancelled` или с `rethrow;` в конце).
Полный `dart analyze .` с правилом: `async_job` 215 и `solo` 156 — список
находок совпал построчно, ни одной новой. В наборе `solo_lints` падает один
тест, `test_catch_that_handles_a_cancellation` (третья клауза:
`if (ctx.job.isCancelled) rethrow; await reset();`). Сторож страницы ошибок
зелёный: правильный блок пары «Letting cancellation through a catch»
(`ctx.check(); await hw.reset(); ... rethrow;`) молчит за счёт `rethrow;`.
Мутированный плагин действительно загрузился: на нём зонд выше даёт диагноз.

Предложение: убрать исключение «спросил задачу» из `bare_await` (признак
остаётся общим для `catch_without_check`), третью клаузу теста переписать
на ожидаемый диагноз, в дизайне (пункт 8 «пропускает») и README убрать «or has
asked the job before the wait». Если владелец хочет его оставить — тогда
решение в `docs/settled.md` с честной причиной и строка в «Чего правило
не ловит». В пунктах 119–125 этого решения нет: 121 — только `finally`.

**Вердикт.** Принята, сделано как предложено: исключение «`catch` спросил
задачу» из `bare_await` убрано, признак `askingStatement` остался общим для
`catch_without_check`. Из `test_catch_that_handles_a_cancellation` клауза
с вопросом ушла; зонд ревьюера и `if (ctx.job.isCancelled) rethrow;` перед
`await reset();` стоят в новом тесте `test_catch_that_lets_a_cancellation_wait`
и ждут диагноза. Пункт 8 «пропускает» дизайна и README на обоих языках
переписаны: проверка слышит отмену, которая уже пришла, а не ту, что придёт
во время ожидания. На дереве находки совпали с прежними построчно: `async_job`
215, `solo` 156, примеры 0 с контрольным файлом. Итог третьего ревью: форма,
где широкий `catch` кончается `rethrow;`, а ожидание стоит в ветке с `continue`
или `return`, жила и теперь называется — находка 1 отчёта Opus третьего ревью.

#### 2. Именованный параметр `JobContext` не засчитывается. Мелко, расходится с дизайном.

Пункт 4 «пропускает»: «если параметр, которому соответствует аргумент, объявлен
типом `JobContext`». `_handsOverContext` (`bare_await.dart:274–281`) берёт
`correspondingParameter` у значения аргумента. У позиционного родитель
значения — `ArgumentList`, и параметр находится. У именованного на analyzer 13+
родитель значения — `NamedArgument`, а `ArgumentImpl.correspondingParameter`
(`analyzer-14.6.0/lib/src/dart/ast/ast.dart:1332`) отвечает только узлу, чей
родитель `ArgumentList`, поэтому получается `null`.

Зонд (оба способа):

```dart
Future<void> named({required JobContext ctx}) => ctx.join(commit);

final job = Job<void>((ctx) async {
  await named(ctx: ctx);
});
```

Результат: `bare_await` на `await named(ctx: ctx);`.

Предложение: для именованного аргумента брать тип параметра по имени
(`argumentName(argument)`) из `staticInvokeType` вызова
(`FunctionType.namedParameterTypes[name]`) — это одинаково работает на analyzer
12 и 13+, не называя ни `NamedExpression`, ни `NamedArgument`. Тест на форму
`helper(ctx: ctx)`.

**Вердикт.** Принята, сделано как предложено: для именованного аргумента тип
параметра берётся по имени из `staticInvokeType` вызова
(`namedParameterTypes`), позиционный — как раньше. Тест
`test_hands_over_the_context` получил `await named(ctx: ctx);`. Пункт 4 дизайна
и README говорят «позиционному или именованному».

#### 3. Локальная функция, которая сама ждёт через `ctx`, ловится в месте вызова. Мелко.

Пункт 9 и README: «A local function is reported where the body awaits its
call». Но локальная функция, которая сама ждёт через контекст, — тот же случай,
что пункт 4 «вызов, которому передан контекст»: она захватывает `ctx`
замыканием, а не параметром. Сообщение «This wait doesn’t go through ctx» тогда
неверно по факту.

Зонд (`RuleTest`):

```dart
final job = Job<int>((ctx) async {
  Future<int> load() => ctx.join(commit);
  final viaVariable = () => ctx.abandonable(commit);
  await viaVariable();
  return await load();
});
```

Результат: два диагноза, на обоих `await`.

На страницах такой формы нет (прогон по дереву её не показал), поэтому это
не срочно. Предложение: либо засчитывать вызов локальной функции или финальной
переменной с литералом (`functionOf` уже есть в `context.dart`), если каждое её
возвращаемое значение (`returnedValues`) проходит `through`; либо назвать форму
в «ловит лишнее» дизайна и README. Пункт 120 о другом: он про `await` внутри
действия, а не про вызов.

**Вердикт.** Принята вторым вариантом: форма названа в «Чего правило не ловит
и что ловит лишнее» дизайна и в README на обоих языках. Разбор возвращаемых
значений локальной функции ради формы, которой на страницах нет, не делается;
решение — пункт 126 `docs/settled.md`.

#### 4. Исключение «`catch` кончается `rethrow;`» шире освобождения. Мелко, спорно.

Исключение добавлено сверх предложенного первым ревью: им решён сторож страницы
ошибок (находка 13). Дизайн называет его «освобождение на выходе», но правило
пропускает в таком `catch` всё: задержку, `await for`, сетевой вызов. Кроме
того, это противоречит доктрине соседнего правила: `catch_without_check`
в `_leavesAtOnce` пропускает выход через `rethrow;` только тогда, когда
по дороге ничего не ждёт («a release or a log on the way out holds up nobody»),
а `await` по дороге для него — находка.

Зонд (`RuleTest`):

```dart
final job = Job<void>((ctx) async {
  try {
    await ctx.join(commit);
  } on DeviceError {
    await Future<void>.delayed(const Duration(seconds: 5));
    await for (final t in ticks()) {
      print(t);
    }
    await commit();
    rethrow;
  }
});
```

Результат: 0 диагнозов.

Цена другой формы замерена мутацией: без исключения `rethrow;` в `solo`
добавляются 3 находки, все на неправильных формах страницы ошибок, которые уже
ловит `catch_without_check`: `test/support/errors_first_attempts.dart:63`,
`test/errors_rakes_test.dart:177` и `:186`; в `async_job` изменений нет.
То есть исключение ничего правильного не спасает, оно только убирает второй
диагноз.

Предложение: решить владельцу и записать в `docs/settled.md` (сейчас решения
нет). Варианты: (а) оставить, но в дизайне и README сказать прямо, что
пропускается любой `await` такого `catch`, а не только освобождение; (б)
пропускать по `rethrow;` только `catch`, который ловит отмену (`on Object`,
`on Exception`, без типа, как `_takesCancelled` у `catch_without_check`): там
второй диагноз дублирует первый, а узкий `catch` проверяется как тело. При (б)
зонд выше даёт три диагноза, страница ошибок остаётся за одним правилом.

**Вердикт.** Принята, вариантом (б); выбор между (а) и (б) сделал исполнитель,
потому что (б) сходится с доктриной `catch_without_check` и ничего правильного
на страницах не задевает. `rethrow;` в конце пропускает только `catch`, который
ловит отмену: без типа, `on Object`, `on Exception`, `on Outcome`. Признак
`takesCancelled` переехал из `catch_without_check` в `context.dart`, и оба
правила берут его оттуда. Узкий `catch` с `rethrow;` проверяется как тело:
клауза `on DeviceError { await reset(); rethrow; }`
в `test_catch_that_lets_a_cancellation_wait` ждёт диагноза. Широкий `catch`
с `rethrow;` по-прежнему пропускается целиком, не только освобождение, и дизайн
говорит это прямо; решение — пункт 127. На дереве изменений нет: три находки
`solo`, которые ревьюер получил, выключив исключение целиком, стоят в широком
`catch`, и список совпал с прежним построчно. Итог третьего ревью: широкий
`catch` с `rethrow;` проверяется как тело, если до `rethrow;` из него уходят
`return`, `break` или `continue` (находка 1 отчёта Opus); тесты держат все
четыре широких типа (находка 3).

#### 5. Дизайн: «`await for` в теле ловится всегда» — неправда. Мелко.

`_awaitFor` (`bare_await.dart:94–98`) идёт через `_bodyContextOf`, поэтому
`await for` молчит в `finally`, в `catch` под исключениями находки 4 и 1
и в теле с `cancellable: false`.

Зонд (`RuleTest`): `await for` в `finally` и в теле
`Job<void>((ctx) async { await for (final t in ticks()) { print(t); } },
cancellable: false)` — 0 диагнозов.

Предложение: в дизайне написать «`await for` ловится там же, где `await`, своим
кодом…». Поведение кода разумное, неверна только формулировка.

**Вердикт.** Принята, сделано как предложено: дизайн говорит, что `await for`
ловится там же, где `await`, и что исключения места — `finally`, `catch`,
вложенная функция, `cancellable: false` — действуют и на него.

#### 6. README: про `cancellable: false` не сказано о теле верхнего уровня. Мелко.

Дизайн, пункт 10: «для функции верхнего уровня — если каждый вызов, которому
она передана по имени, так отказывается». В README раздела `### bare_await`: «A
body of a job made with `cancellable: false`, as a literal or a constant, is
left alone» — и только. Читатель, у которого тело передано по имени в двух
местах, не поймёт, почему правило его называет.

Предложение: дописать «…and a top-level function every job of which is made
so». Тем же коммитом — перевод.

**Вердикт.** Принята, сделано как предложено, в README и переводе: тело
верхнего уровня, все задачи которого созданы с `cancellable: false`, правило
не трогает.

#### 7. Дизайн: ожидание своего продолжения — не `children.md`, а `chains.md`. Мелко.

«Замер шума» дизайна: «ожидание своего продолжения (`children.md` ядра)».
Находка стоит в `packages/async_job/test/support/children_page.dart:346`,
но раздел — в `packages/async_job/doc/chains.md`: «a source that waits for its
own continuation waits forever» (строка 407). `children.md` такой формы
не содержит (`grep -i "own continuation"` — только `chains.md`).

Предложение: заменить на `chains.md` ядра.

**Вердикт.** Принята, сделано как предложено: в «Замере шума» дизайна стоит
`chains.md` ядра.

#### 8. Мутация `every` → `any` в отказе тела верхнего уровня выживает. Мелко, тест.

Отчёт: «40 мутаций исключений правила, по одной; каждая роняет тест». Мутация
`uses.lists.every(_refuses)` → `uses.lists.any(_refuses)`
(`bare_await.dart:165`) оставляет `test/bare_await_test.dart` зелёным: 40
из 40. У теста `test_body_declared_at_the_top_level` тело передано один раз.

Зонд, который мутацию убивает (на настоящем SDK, диагноз есть
на `await commit();` в `backupA`):

```dart
Future<void> backupA(JobContext ctx) async {
  await commit();
}

final one = Job<void>(backupA, cancellable: false);
final two = Job<void>(backupA);
```

Предложение: добавить его тестом с ожиданием диагноза.

**Вердикт.** Принята, сделано как предложено: тест
`test_body_declared_at_the_top_level_and_passed_twice` с зондом ревьюера.
Мутация `every` на `any` его роняет; полный проход мутаций — 45, каждая роняет
тест.

#### 9. Ложные срабатывания на редких формах ожидания через контекст. Мелко.

Все на настоящем SDK (`zz_probe.dart`), каждая строка даёт `bare_await`:

```dart
Job<void> shapes(List<ChildJob<int>> jobs) => Job<void>((ctx) async {
  await ctx.join(commit).timeout(const Duration(seconds: 1));
  await Future.any([ctx.join(commit), ctx.abandonable(commit)]);
  await jobs.map(ctx.run).wait;
  await ctx.join(commit).then((v) => v + 1);
  final (a, b) = (ctx.join(commit), ctx.join(commit));
  await a;
});
```

И в `RuleTest`: `await Future.wait(<Future<void>>[]);` (пустой литерал: `_all`
требует непустой) и `await Future.wait(jobs.map(ctx.run));`. На страницах
ни одной из этих форм нет (`grep` по `doc/` и README: `.timeout(` стоит только
на вызовах API, `Future.any` нет), поэтому чинить не обязательно. Предложение:
добавить строку в «ловит лишнее» дизайна и README — «a future of the context
taken further by `timeout` or `then`, `Future.any`, a mapped iterable and a
pattern variable», — либо узнавать `timeout`/`then`/`whenComplete`
и `catchError` на разрешённой цели и `Future.any` как `Future.wait`. Пустой
список чинится одной правкой: убрать `|| list.elements.isEmpty` из `_all`,
`every` на пустом списке и так `true`.

**Вердикт.** Принята частично. Пустой литерал в `Future.wait` починен одной
правкой, как предложено: `_all` без проверки на пустоту; случай стоит
в `test_collection_elements`. Остальные формы — `timeout` и `then` на future
контекста, `Future.any`, `jobs.map(ctx.run)`, переменная шаблона — названы
лишними находками в дизайне и README на обоих языках; узнавать их ради форм,
которых на страницах нет, правило не будет, решение — пункт 126.

#### 10. Запущенный ребёнок в `var`, заменённый незапущенным, проходит молча. Мелко.

`_isChild` (`bare_await.dart:258–270`) засчитывает переменную, если раньше
стоял `ctx.start(v)`, и не проверяет, что `v` финальная. Пункт 122 называет
`var` лишней находкой, а здесь обратная сторона — пропуск.

Зонд (`RuleTest`):

```dart
final job = Job<void>((ctx) async {
  var rows = ctx.child((c) => c.join(commit));
  ctx.start(rows);
  rows = ctx.child((c) => c.join(commit));
  await rows.value;
});
```

Результат: 0 диагнозов, хотя ждётся незапущенный ребёнок, а это вечное ожидание
из находки 4 первого ревью. Форма надуманная. Предложение: засчитывать
`ctx.start(v)` только для финальной переменной (как `_finalLocalValue`) —
ребёнок в `var` и так назван лишней находкой, так что пробел у него уже есть.

**Вердикт.** Принята, сделано иначе, чем предложено: `ctx.start(v)`
не засчитывается для локальной `var`, а не засчитывается только для финальной.
Разница — в параметре и поле: их тело заменить не может так, как свою `var`,
и они остаются как были. Тест `test_child_replaced_after_start`; пункт 2
«пропускает» дизайна говорит про `var`. Итог третьего ревью: довод про параметр
и поле неверен — параметр переприсваивается, поле тоже, — и они больше
не засчитываются; засчитывается только финальная переменная или геттер
финального поля (находка 1 отчёта Codex и 2 отчёта Opus).

### Наблюдение без находки

Широкий `catch`, который действует первым (`on Object { await reset(); }`),
получает два диагноза: `catch_without_check` на типе и `bare_await` на `await`
(`zz_probe_cwc.dart:9` и `:10`). Это разные узлы и разные советы,
и `ctx.check();` первой строкой гасит оба. Если находку 1 принять, после
`ctx.check()` такой `await` снова получит `bare_await`, кроме `catch`
с `rethrow;` в конце.

## Третье ревью

Два ревьюера параллельно, Opus и Codex (`gpt-6-astra`, усилие `xhigh`), каждый
в своей копии дерева на `d957ca0b`, вершине `main` после повторного ревью.
Предмет — дифф `3a61a484..2449e246`, правки по повторному ревью: закрывают ли
они его десять находок, что нового принёс дифф, работает ли тип именованного
параметра на analyzer 12.1.0. Ниже оба отчёта как есть, кроме путей к временным
каталогам; под каждой находкой — вердикт. Отчёт Opus пришёл сообщением:
записать файл ревьюеру не дал харнесс.

Номера мутаций отчётов (M…) — свои у каждого ревьюера. Мутации K1–K10
в вердиктах — проверка правок третьего ревью, по одной, каждая роняет тест.

### Отчёт Codex

Проверял на коммите:

```text
d957ca0b docs: note the reply to tez in the handoff
```

Предмет — дифф `3a61a484..2449e246`. Проверка: чтение кода и документов, зонды
через `RuleTest`, восемь отдельных мутаций, анализ и исполнение зондов
на настоящем SDK. Dart — **3.13.0**; analyzer — **14.6.0** из lock-файла
и **12.1.0** в отдельной копии пакета.

**Осталась одна мелкая находка: №10 закрыта не полностью.** Новых важных
регрессов не обнаружил.

Расхождение с `AGENTS.md`: по прямому условию задания не обновлял handoff,
не сохранял отчёт в репозитории и не делал коммит. После проверки дерево
чистое.

#### Сверка десяти находок второго ревью

| № | Состояние | Чем проверено |
|---|---|---|
| 1. Проверка в начале `catch` скрывает последующее ожидание | **Закрыта** | После `ctx.check()` и `if (ctx.job.isCancelled) rethrow` обычные ожидания получают диагноз. Зонд `checks`, мутация M1. |
| 2. Именованный параметр `JobContext` | **Закрыта** | 12 корректных форм вызова без диагнозов на analyzer 12.1.0 и 14.6.0. Возврат прежнего способа определения параметра роняет тест — M3. Границы вызовов разобраны ниже. |
| 3. Вызов локальной функции, захватившей контекст | **Закрыта по вердикту** | Зонд `captured` по-прежнему даёт два диагноза. Это теперь явно описано в дизайне, обоих README и решении 126. |
| 4. Любой `catch` с завершающим `rethrow` | **Закрыта** | Узкий `on DeviceError` получает диагнозы на `await` и `await for`; широкие типы пропускаются. Мутации M2 и M7 обнаружены тестами. Решение 127 не оспариваю. |
| 5. Формулировка о безусловном обнаружении `await for` | **Закрыта** | Зонд `loop_places`: ноль диагнозов в `finally`, разрешённых `catch`, вложенном действии и теле с `cancellable: false`. Дизайн перечисляет эти исключения. |
| 6. Тело верхнего уровня и `cancellable: false` | **Закрыта** | Два использования с отказом от отмены — ноль диагнозов; смешанные использования — один. README и перевод соответствуют. |
| 7. `children.md` вместо `chains.md` | **Закрыта** | Дизайн исправлен; пример находится в `packages/async_job/doc/chains.md:407`. |
| 8. Выживающая мутация `every` → `any` | **Закрыта** | M6 роняет новый `test_body_declared_at_the_top_level_and_passed_twice`. |
| 9. Пустой список и редкие формы композиции | **Закрыта по вердикту** | Пустые `Future.wait([])` и `[].wait` проходят; M4 обнаружена тестом. Остальные шесть проверенных форм дают диагнозы на настоящем SDK и описаны как ограничения. |
| 10. Замена запущенного ребёнка незапущенным | **Закрыта не до конца** | Локальная `var` получает диагноз; изменяемый параметр и поле — нет. На обоих analyzer. Подробности ниже. |

#### Находки

##### 1. Мелко: защита от замены ребёнка не распространяется на параметры и поля

Координаты: `packages/solo_lints/lib/src/rules/bare_await.dart:264`,
`_Waits._isChild`.

Новое условие признаёт заменяемой только нефинальную `LocalVariableElement`.
Параметр и идентификатор поля проходят проверку предыдущего `ctx.start(...)`,
даже если после запуска им присвоен другой ребёнок.

Утверждение вердикта №10, что параметр и поле тело заменить не может, неверно.
Например:

```dart
class Host {
  late ChildJob<int> rows;

  Job<void> work() => Job<void>((ctx) async {
    rows = ctx.child((c) async => 1);
    ctx.start(rows);
    rows = ctx.child((c) async => 2);
    await rows.value;
  });
}
```

Ожидается новый, незапущенный ребёнок. Предыдущий `ctx.start(rows)` запускал
другой объект. Отмена родителя это ожидание не завершает.

Зонды через `RuleTest`, одинаково на analyzer 12.1.0 и 14.6.0:

```text
PROBE replaced_local bare_await: 1; compileErrors=0
PROBE replaced_parameter bare_await: 0; compileErrors=0
PROBE replaced_field bare_await: 0; compileErrors=0
```

Вариант с параметром использует допустимое тело:

```dart
Future<void> body(
  JobContext ctx, [
  ChildJob<int>? rows,
]) async {
  rows = ctx.child((c) => c.join(commit));
  ctx.start(rows);
  rows = ctx.child((c) => c.join(commit));
  await rows.value;
}

final job = Job<void>(body);
```

Настоящий `dart analyze` с плагином также не сообщает `bare_await` для обоих
вариантов. Исполнение варианта с полем — отмена после запуска тела, затем
проверка состояния — печатает:

```text
cancelled=true, finished=false, replacementRunning=false, replacementFinished=false
```

Предложение: засчитывать предыдущий `start` только для доказанно неизменной
ссылки. Консервативный вариант — финальная локальная переменная; более широкий
требует учитывать присваивания параметрам и изменяемость полей. Добавить оба
зонда в тесты и исправить обоснование вердикта №10.

**Вердикт ревью:** остаток прежней находки, не новый регресс. Тяжесть мелкая:
последовательная замена хэндла незапущенным ребёнком — редкая форма. Решения
119–127 её не разрешают.

**Вердикт.** Принята, сделано шире предложенного: прежний `ctx.start(v)`
засчитывается только для неизменной ссылки — финальной переменной или геттера
финального поля (`_fixed` в `bare_await.dart`). Параметр, нефинальное поле
и вычисляемый геттер, который на каждом чтении даёт нового ребёнка,
не засчитываются. Цена: запущенный и не заменённый ребёнок в параметре или
нефинальном поле теперь назван, как `var` в пункте 122. Довод вердикта 10
повторного ревью был неверен, итог дописан к нему. Тесты: параметр, поле
и вычисляемый геттер в `test_child_replaced_after_start`, финальное поле
в `test_children`; мутации K4–K7 роняют тест. Пункт 2 «пропускает» дизайна,
README и перевод говорят про неизменную ссылку, пункт 122 — про параметр
и поле.

#### Совместимость и документы

`staticInvokeType` работает одинаково на обеих проверенных версиях analyzer.
Для следующих именованных вызовов получен `FunctionType` с параметром
`JobContext`, диагнозов нет:

- функция верхнего уровня;
- аргумент `(ctx)` в скобках;
- generic-функция с `C extends JobContext`;
- метод объекта;
- вызываемый объект и его явный `.call`;
- функция, возвращённая getter;
- функция в локальной переменной;
- `(named)(ctx: ctx)` и `named.call(ctx: ctx)`;
- вызов метода через `?.`;
- непосредственный вызов литерала функции.

Характерный вывод:

```text
INVOKE named(ctx: ctx) => Future<int> Function({required JobContext ctx})
```

Границы:

| Форма | Результат |
|---|---|
| `dynamic`-функция и её `.call` | `staticInvokeType == dynamic`; исключение не применяется, диагноз есть |
| Неразрешённый вызов | `InvalidType`; падения нет |
| Прямой конструктор `Task(ctx: ctx)` или `Task.new(ctx: ctx)` | Это `InstanceCreationExpression`, не `InvocationExpression`; до `_parameterType` правило не доходит |
| Вызов constructor tear-off: `(Task.new)(ctx: ctx)` или через переменную | Есть `FunctionType`; контекст засчитывается |

Последняя пара проверена на классе `Task implements Future<int>`, который
передаёт ожидание в `ctx.join`. На обеих версиях прямые конструкторы дают два
диагноза, tear-off — ноль. Настоящий SDK подтверждает результат. Это прежняя
граница `_Waits.through`, а не регресс рассматриваемого диффа; отдельной
находкой её не считаю.

Перенос `takesCancelled` не изменил его вычисление. Штатные тесты и зонды
`catch_without_check` не показали регресса: широкие `catch` с ожиданием без
проверки получают диагноз, проверившие контекст — нет; `Cancelled` и узкий
`DeviceError` пропускаются этим соседним правилом.

Изменённые положения дизайна и обоих README соответствуют проверенному
поведению. Оговорки решений 126–127 действительно сохранены. Фраза
в `cleanup-rules.md` тоже соответствует правилу: `await Database.open()` перед
`ctx.onDiscard(...)` даёт один `bare_await`. Ошибочное обоснование про
неизменяемость параметров и полей относится к находке выше.

#### ПРОГОН

Команды запускались через `rtk proxy`; ниже приведены сами команды
и фактические результаты.

##### Обязательные проверки

Из `packages/solo_lints`, после удаления временного теста и восстановления
исходника:

| Команда | Точная последняя строка |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | `Formatted 28 files (0 changed) in 0.09 seconds.` |
| `dart analyze --fatal-infos` | `No issues found!` |
| `dart test` | `00:06 +190: All tests passed!` |

Все три завершились с кодом 0. Начальный прогон до зондов также прошёл:

```text
00:04 +190: All tests passed!
```

##### Зонды через `RuleTest`

Основная команда:

```sh
dart test test/zz_probe_test.dart --reporter expanded
```

В таблице указано число диагнозов выбранного правила. Результаты совпали
на analyzer 12.1.0 и 14.6.0.

| Зонд | Что проверял | Вывод |
|---|---|---|
| `checks` | Проверки отмены перед ожиданием; узкий `catch` с `rethrow` | `bare_await: 4; compileErrors=0` |
| `named_calls` | 12 форм именованного вызова | `bare_await: 0; compileErrors=0` |
| `named_unsafe` | Параметр `Object`, вызовы через `dynamic` | `bare_await: 3; compileErrors=0` |
| `captured` | Локальная функция и замыкание, захватившие `ctx` | `bare_await: 2; compileErrors=0` |
| `loop_places` | Исключения места для `await for` | `bare_await: 0; compileErrors=0` |
| `all_false` | Два использования тела с отказом от отмены | `bare_await: 0; compileErrors=0` |
| `mixed` | Использования тела с отказом и без | `bare_await: 1; compileErrors=0` |
| `rare_and_empty` | Композиции future и пустые списки | `bare_await: 4; compileErrors=2` |
| `replaced_local` | Замена локальной `var` после запуска | `bare_await: 1; compileErrors=0` |
| `replaced_parameter` | Та же замена параметра | `bare_await: 0; compileErrors=0` |
| `replaced_field` | Та же замена поля | `bare_await: 0; compileErrors=0` |
| `broad_types` | Untyped, Object, Exception, Outcome, dynamic, typedef, Cancelled, DeviceError | `bare_await: 1; compileErrors=0` |
| `cleanup_page` | Регистрация после обычного ожидания | `bare_await: 1; compileErrors=0` |
| `broken_arguments` | Пропущенное значение аргумента, дубликат, неизвестные имена, отсутствующие аргументы | `bare_await: 2; compileErrors=6` |
| `broken_without_bound` | Самоссылки, взаимные ссылки, незаконченный `on` | `bare_await: 3; compileErrors=6` |
| `checks`, соседнее правило | Проверки контекста и узкий `catch` | `catch_without_check: 0; compileErrors=0` |
| `broad_types`, соседнее правило | Матрица типов `catch` | `catch_without_check: 6; compileErrors=0` |
| `broken_arguments`, соседнее правило | Ошибочные аргументы | `catch_without_check: 0; compileErrors=6` |

В `rare_and_empty` тестовый SDK не предоставляет `Future.any`
и `Future.timeout`; поэтому результат этого зонда для них непоказателен. Эти
формы отдельно проверены настоящим SDK.

Зонд `broken_types` с `T extends T` **упал: `Stack Overflow`** на обеих версиях
analyzer. Повтор с правилом, у которого `registerNodeProcessors` пуст, упал
так же. Стек идёт через `TypeParameterTypeImpl.asInstanceOf` и разрешение
типов, до запуска обработчиков линта. Это не дефект рассматриваемого диффа.

Первый запуск временного набора закончился:

```text
00:01 +17 -2: Some tests failed.
```

После добавления контрольного пустого правила и отдельного зонда без
циклической границы:

```text
00:02 +18 -3: Some tests failed.
```

Все три падения — один ошибочный `T extends T` под тремя вариантами правила.

В копии с analyzer 12.1.0 запускал:

```sh
dart test test/bare_await_test.dart test/catch_without_check_test.dart \
  test/zz_probe_test.dart --reporter expanded
```

Результат:

```text
00:03 +76 -3: Some tests failed.
```

Причина трёх падений та же. Отдельный запуск **только штатных тестов** двух
правил:

```sh
dart test test/bare_await_test.dart test/catch_without_check_test.dart \
  --reporter expanded
```

завершился:

```text
00:02 +58: All tests passed!
```

Конструкторы проверены отдельно на обеих версиях:

```sh
dart test test/zz_probe_test.dart --plain-name constructors \
  --reporter expanded
```

Вывод:

```text
PROBE constructors bare_await: 2; compileErrors=0
```

Оба запуска зелёные: `+1: All tests passed!`.

##### Настоящий SDK

В отдельном пакете вне дерева подключён плагин из проверяемого дерева, включены
`bare_await` и `catch_without_check`.

Первый `dart analyze` **упал** из-за запрета записи:

```text
PathAccessException: Creation failed, path = '/Users/user/.dartServer/.plugin_manager/e296029f584f87de0d07eaf940f3d549' (OS Error: Operation not permitted, errno = 1)
```

Повторил с `ANALYZER_STATE_LOCATION_OVERRIDE`, направленным в разрешённый
scratch-каталог. Результат:

```text
7 issues found.
```

Это шесть `bare_await` на `timeout`, `Future.any`, двух вариантах `map`, `then`
и переменной шаблона, плюс предупреждение о ненужном `?.`. На пустых списках,
именованных корректных вызовах, заменённых параметре и поле диагнозов
`bare_await` нет.

Отдельный `dart analyze constructors.dart`:

```text
2 issues found.
```

Оба — ожидаемые для текущей реализации `bare_await` на прямых конструкторах.

Исполняемый зонд `dart run runtime.dart` сначала упал
с `LateInitializationError`: отмена была отправлена до начала тела. После
переноса отмены за первый асинхронный такт завершился с кодом 0 и напечатал:

```text
cancelled=true, finished=false, replacementRunning=false, replacementFinished=false
```

##### Мутации

Каждая мутация запускалась отдельно на analyzer 14.6.0 командой:

```sh
dart test test/bare_await_test.dart --plain-name <имя> \
  --reporter expanded
```

Перед первой мутацией исходник сохранён через `cp` вне дерева. После
**каждой** — восстановлен через `cp`, затем `cmp` завершился с кодом 0.

| Мутация | Фильтр теста | Результат |
|---|---|---|
| M1: вернуть освобождение `catch` по `askingStatement` | `catch_that_lets_a_cancellation_wait` | `00:01 +0 -1: Some tests failed.` |
| M2: убрать требование `takesCancelled` перед `rethrow` | `catch_that_lets_a_cancellation_wait` | `00:01 +0 -1: Some tests failed.` |
| M3: для именованного аргумента снова брать `value.correspondingParameter` | `hands_over_the_context` | `00:01 +0 -1: Some tests failed.` |
| M4: снова запрещать пустой список | `collection_elements` | `00:00 +0 -1: Some tests failed.` |
| M5: убрать ограничение заменяемой локальной переменной | `child_replaced_after_start` | `00:01 +0 -1: Some tests failed.` |
| M6: `every(_refuses)` → `any(_refuses)` | `body_declared_at_the_top_level_and_passed_twice` | `00:01 +0 -1: Some tests failed.` |
| M7: отключить освобождение широкого `catch` с `rethrow` | `catch_that_handles_a_cancellation` | `00:00 +0 -1: Some tests failed.` |
| M8: убрать защиту от чтения собственного инициализатора | `read_in_its_own_initializer` | `00:01 +0 -1: Some tests failed.`; `Stack Overflow` в `_Waits.through` |

Все восемь обнаружены тестами. M8 отдельно подтверждает, что исправленный тест
самоссылки действительно исполняет нужный сценарий.

Дополнительные проверки:

```text
python3 tool/reflow.py --check
every paragraph is filled to 79 columns

python3 tool/check_line_width.py
no Markdown line over 79 columns, no blank line doubled

python3 tool/check_translations.py
no differences
```

Финальные `git status --short` и `git diff --exit-code` — пустой вывод, код 0.
Временный тест удалён.

**Итог: 0 важных, 1 мелкая находка. Девять вердиктов подтверждены; №10 закрыт
не полностью.**

### Отчёт Opus

Проверял в копии дерева, отвязанный HEAD. `git log --oneline -1`:
`d957ca0b docs: note the reply to tez in the handoff`. Основная среда — Dart
3.13.0 и analyzer 14.6.0 из `pubspec.lock`. Пол — Dart 3.10.0
(`~/fvm/versions/3.38.1`) и analyzer 12.1.0.

**Как проверял:**
- **Зонды через `RuleTest`.** Временные файлы `test/zz_probe_test.dart`,
  `test/zz_probe_ba_test.dart` и `test/zz_probe_fixtures.dart`. Каждый фрагмент
  пишется в свой файл `lib/p_<имя>.dart`, разрешается отдельно, и зонд печатает
  диагнозы линтов.
  - Прогонялись три правила: текущий `bare_await`, `catch_without_check`
    и `bare_await` из `3a61a484`.
  - Старое правило на время лежало в `lib/src/rules/bare_await_old.dart`.
  - Все временные файлы удалены.
- **Зонд на настоящем SDK.** Пакет вне дерева. В нём `async_job` по пути
  из копии и плагин по пути из копии с `bare_await: true`
  и `catch_without_check: true`, затем `dart analyze`.
- **Пол.** `git archive` пакета `solo_lints` и `solo/doc` вне дерева. Затем
  `dart pub get` и `dart pub downgrade <прямые зависимости>`, как делает
  `tool/archive_floor.py`. Получились analyzer 12.1.0, analyzer_testing 0.2.5,
  analysis_server_plugin 0.3.14 и analyzer_plugin 0.14.8.
- **Мутации.** 14 штук по одной, своим скриптом.
  - До мутаций сделаны копии `bare_await.dart.orig` и `context.dart.orig`.
  - После каждой файл возвращается `cp` и сверяется `filecmp`.
  - В конце ещё раз `cmp`.
- **Документы.** `check_translations.py`, `check_line_width.py`,
  `reflow.py --check` (общий проход и обе записи `bare-await`),
  `check_links.py`.

#### Десять находок второго ревью

| № | Состояние | Чем проверено |
|---|---|---|
| 1 | закрыта не до конца | Формы находки ловятся: зонд `f1_isCancelled_first_broad` даёт 1 диагноз, старое правило давало 0. Тест `test_catch_that_lets_a_cancellation_wait` держит форму: мутация M2 (вернуть исключение «спросил задачу») его роняет. Жива форма, где широкий `catch` кончается `rethrow;`, а задержка стоит в ветке с `continue` — новая находка 1 |
| 2 | закрыта | Зонд `f2_named_forms` молчит на всех формах передачи контекста (список ниже таблицы). `obj({required Object ctx})` ловится. Старое правило ловило все 7 вызовов. На analyzer 12.1.0 вывод тот же. Мутация M6 роняет `test_hands_over_the_context`. Неточный комментарий — новая находка 4 |
| 3 | закрыта документом | Код не менялся. Форма названа в дизайне, в README:264–267, в README.ru:269–272 и в пункте 126 |
| 4 | закрыта | `f4_narrow_kinds_rethrow` (`on DeviceError`, `on StateError` и `on Error` с `rethrow;`) — 3 диагноза, у старого правила 0. Зонд ревьюера `f4_reviewer_probe` — 3. `f4_broad_kinds_rethrow` (`on Exception`, `on Outcome`, без типа, `on dynamic`) — 0. Мутация M1 роняет тест. Пробел в тестах — новая находка 3 |
| 5 | закрыта | Прочитан раздел дизайна «Что правило ловит». `_awaitFor` (`bare_await.dart:94–98`) не менялся |
| 6 | закрыта | Прочитаны README:256–257 и README.ru:262–263. Мутация M7 роняет `test_body_declared_at_the_top_level_and_passed_twice` |
| 7 | закрыта | В дизайне стоит `chains.md`. `grep "own continuation"` находит только `chains.md:407` |
| 8 | закрыта | M7 роняет новый тест |
| 9 | закрыта | `f9_empty_and_any`: `Future.wait(<Future<void>>[])`, `Future.wait([])` и `Future.wait(const <Future<void>>[])` — 0 диагнозов, у старого правила 3. M3 роняет `test_collection_elements`. Остальные формы названы в README и пункте 126 |
| 10 | закрыта для `var` | M4 роняет `test_child_replaced_after_start`. Довод про параметр неверен и не покрыт тестом — новая находка 2 |

Формы зонда `f2_named_forms`, на которых правило молчит:
- метод экземпляра и статический метод;
- обобщённый `<C extends JobContext>` и параметр `JobContext?`;
- смешанный вызов `both(1, ctx: ctx)`;
- параметр-функция и локальная функция;
- `call()`, `super.save(ctx: ctx)` и тир-офф `super.save`.

Регресса `catch_without_check` после переезда `takesCancelled` нет:
- функция перенесена в `context.dart:87–95` без изменений;
- набор из 190 тестов зелёный;
- M12 и M13 роняют тесты `catch_without_check` и `add_check_fix`.

Падений на коде с ошибками нет. Проверены `on Unknown`, `on {`, незакрытый
`catch`, `named(ctx: ctx, ctx: ctx)`, `named(cxt: ctx)`, `unknown(ctx: ctx)`,
`named(ctx: )` и незакрытый вызов `named(ctx: ctx`.

#### Новые находки

##### 1. Широкий `catch` с `rethrow;` в конце прячет задержку перед повтором. Важно. Повтор решения 127

**Механика.** `_Visitor._handles` (`bare_await.dart:144–151`) пропускает
`catch`, если выполнены два условия:
- `takesCancelled(type)`;
- последний оператор — `rethrow;`.

Тогда `_bodyContextOf` (`:121`) молчит на всех `await` этого `catch`.

**Почему решение 127 здесь не держит.** Оно называет такие ожидания «путь
отмены наружу». Это неверно, когда `catch` выходит раньше через `continue`,
`break` или `return`. Ожидание в такой ветке — задержка перед повтором. Это
та же ошибка, что в находке 1 второго ревью и в `solo/doc/errors.md:438–477`.

Форма обычная. Страница пишет `if (attempt == 3) rethrow; …; continue;`,
а обратная запись `if (attempt < 3) { await …; continue; } rethrow;` так же
естественна.

**Новый довод.** Два правила складываются в ловушку:
1. На форме без проверки `catch_without_check` справедливо называет `catch`
   и советует «Make 'ctx.check();' the first line».
2. Пользователь применяет совет или быстрое исправление `add_check`.
3. После этого молчат оба правила. `catch_without_check` видит вопрос задаче,
   `bare_await` видит широкий `catch` с `rethrow;`.

Отмену, которая придёт во время задержки, при этом никто не слышит.

**Зонд** (`RuleTest`, `f1_retry_rethrow_last_checked` и `_unchecked`; во втором
варианте нет строки `ctx.check();`):
```dart
final job = Job<void>((ctx) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await ctx.abandonable(commit);
      return;
    } on Object {
      ctx.check();
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt));
        continue;
      }
      rethrow;
    }
  }
});
```

Вывод `RuleTest`:
```text
[bare_await] f1_retry_rethrow_last_checked: 0 lint(s)
[bare_await] f1_retry_rethrow_last_unchecked: 0 lint(s)
[catch_without_check] f1_retry_rethrow_last_checked: 0 lint(s)
[catch_without_check] f1_retry_rethrow_last_unchecked: 1 lint(s)  L6: } on Object {
[OLD bare_await 3a61a484] f1_retry_rethrow_last_checked: 0 lint(s)
```

Настоящий SDK, `dart analyze` в пакете зонда. В файле вариант с проверкой
(строки 10–16), без проверки (26–30) и контрольное `await commit();` (37):
```text
info - lib/probe.dart:26:10 - This catch takes the cancellation ... Make 'ctx.check();' the first line of the catch ... - catch_without_check
info - lib/probe.dart:37:3 - This wait doesn't go through 'ctx' ... - bare_await
2 issues found.
```

Это не регресс диффа: старое правило молчало так же. Но вердикт 1 объявляет
форму закрытой, а README:254–256 обещает «A check at the top of a catch is not
enough».

**Предложение.** Пропускать по `rethrow;` только `catch`, в теле которого вне
вложенных функций нет `continue`, `break` и `return`.

**Цена.** Замерена мутацией M14: условие `!_goesOn(clause.body)` и посетитель
`_Exits`.
- Набор — `+190: All tests passed!`, сторож страницы ошибок зелёный.
- Оба варианта зонда дают по диагнозу на `await Future<void>.delayed`.
- Остальные зонды не изменились.
- Прогон по дереву `async_job` и `solo` с этой мутацией я не делал.

Тестом закрепить оба варианта зонда. Оговорку добавить в пункт 127, в пункт 8
дизайна и в README.

**Вердикт.** Принята, повтор решения 127 с новым доводом принят. Сделано как
предложено, с уточнением: `break` и `continue`, цель которых внутри самого
`catch`, и `return` вложенной функции выходом не считаются (`_Exits`
в `bare_await.dart`). Тест `test_catch_that_goes_on_before_rethrow` держит зонд
ревьюера и ветку с `return`; внутренний цикл с `break` и локальная функция
с `return` стоят в `test_catch_that_handles_a_cancellation` и ждут тишины.
Мутации K1–K3 роняют тест. На дереве находки совпали с прежними построчно:
`async_job` 215, `solo` 156. Пункт 8 «пропускает» дизайна, README, перевод
и пункт 127 говорят про выход раньше `rethrow;`.

##### 2. Вердикт 10: довод про параметр и поле неверен, признак не покрыт тестом. Мелко

**Механика.** `_Waits._isChild` (`bare_await.dart:264–266`) не засчитывает
`ctx.start(v)` только для `LocalVariableElement`, который не `final`. Вердикт
объясняет это так: «их [параметр и поле] тело заменить не может так, как свою
`var`». Но параметр объемлющей функции переприсваивается, а поле — через
`this`.

**Зонд:**
```dart
Job<void> pair(ChildJob<int> first, ChildJob<int> second) =>
    Job<void>((ctx) async {
  ctx.start(first);
  first = second;
  await first.value;
});
```
- `f10_parameter_reassigned`: 0 lint(s), 0 других диагнозов.
- `f10_field_reassigned`: 0 lint(s).

Ждётся незапущенный `second`, то есть ожидание висит вечно. Форма редкая.

**Тест.** Мутация M5 делает параметр и поле «заменяемыми», и набор остаётся
`+190`.

**Попутно.** Теперь называются `var` без переприсваивания
(`f10_var_not_reassigned`: 1 диагноз, у старого правила 0) и
`for (var job in jobs) { ctx.start(job); await job.done; }`
(`f10_for_var_loop`: 1 против 0). Это сходится с пунктом 2 дизайна
и пунктом 122. В дереве таких форм нет: у пакетов включены
`prefer_final_locals` и `prefer_final_in_for_each`.

**Предложение.** Поправить довод вердикта: параметр и поле оставлены ради
обычной формы `ctx.start(c); await c.value;`, а не потому, что их нельзя
заменить. Тестом закрепить запущенный параметр, который не переприсвоен: такой
тест убивает M5.

**Вердикт.** Принята, это находка 1 отчёта Codex; сделано, как сказано в её
вердикте. Мутация M5 этого отчёта теперь не выживает: K4 («параметр неизменен»)
роняет `test_child_replaced_after_start`.

##### 3. Тесты `bare_await` держат пропуск широкого `catch` только для `on Object`. Мелко, тест

Пропуск по `rethrow;` проверяется только на `on Object`:
`test_catch_and_finally` и `test_catch_that_handles_a_cancellation`. Каждая
из мутаций M8–M11 сужает `_handles` (`bare_await.dart:148`), и с каждой набор
остаётся `+190`:
- M8: широкий только `on Object`;
- M9: без `catch` без типа;
- M10: без `on Exception`;
- M11: без `on Outcome`.

Переезд `takesCancelled` защищён тестами `catch_without_check` (M12, M13).
Но сам пропуск в `bare_await` — нет.

**Предложение.** Добавить в `test_catch_that_handles_a_cancellation` три клаузы
с `await reset(); rethrow;`: без типа, `on Exception` и `on Outcome`. Зонд
`f4_broad_kinds_rethrow` на этих формах даёт 0.

**Вердикт.** Принята, сделано как предложено, по форме иначе: три отдельных
`try` — без типа, `on Exception`, `on Outcome<Object?>` —
в `test_catch_that_handles_a_cancellation`, потому что `catch` после
`on Object` недостижим и тест получил бы лишний диагноз. Мутации K8–K10 (без
типа, `on Exception`, `on Outcome` перестают быть широкими) роняют тест.

##### 4. Комментарий `_parameterType` неверно называет версию analyzer. Мелко

`bare_await.dart:288–289`: «analyzer 13 and later give the value of one no
parameter».

На полу (analyzer 12.1.0, Dart 3.10.0) мутация, которая берёт
`value.correspondingParameter?.type`, как до диффа, даёт:
- `f2_named_forms: 7 lint(s)`, как на 14.6.0;
- падение `test/bare_await_test.dart`.

Значит, и analyzer 12 не даёт параметр значению именованного аргумента.

**Предложение.** Убрать версию из комментария.

**Вердикт.** Принята. На полу, analyzer 12.1.0 и Dart 3.10.0, мутация
к `value.correspondingParameter?.type` роняет `test_hands_over_the_context`
и там: версия в комментарии была неверна. Комментарий `_parameterType` теперь
без версии.

##### 5. README не называет `on Outcome` среди широких `catch`. Мелко, документ

README:253–254 и README.ru:258–259 перечисляют только «untyped, `on Object` or
`on Exception`». Дизайн (пункт 8) и `takesCancelled` (`context.dart:92–94`)
пропускают ещё `on Outcome`. Зонд: `on Outcome { await reset(); rethrow; }` — 0
диагнозов.

**Предложение.** Дописать `on Outcome` в README и перевод одним коммитом.

**Вердикт.** Принята, сделано как предложено: README и перевод называют
`on Outcome` среди широких `catch`, тем же предложением — выход раньше
`rethrow;` из находки 1.

##### Наблюдения без находки

- **`staticInvokeType`.** На 12.1.0 и 14.6.0 вывод одинаковый. Тип не дают:
  - вызовы через `Function` и `dynamic`: `f2_dynamic_calls` — 4 диагноза,
    именованный и позиционный ведут себя одинаково;
  - неразрешённые вызовы: `unknown(ctx: ctx)` молчит, тип там не future; так
    было и раньше.
- **Неразрешённый `on Unknown { await reset(); rethrow; }`** теперь считается
  узким `catch` и даёт диагноз; старое правило молчало. В редакторе это видно,
  пока тип не дописан, — безобидно.
- **`cleanup-rules.md` и перевод** говорят то же, что код.

#### ПРОГОН

**`packages/solo_lints` копии.** Гейт запускался до мутаций и после всех
мутаций, последние строки одинаковые:
- `dart format --output=none --set-exit-if-changed .` —
  `Formatted 28 files (0 changed) in 0.03 seconds.`, exit 0;
- `dart analyze --fatal-infos` — `No issues found!`;
- `dart test` — `00:04 +190: All tests passed!`.

**Пол** (Dart 3.10.0, analyzer 12.1.0):
- `dart test` — `00:03 +190: All tests passed!`;
- `dart analyze lib` — `No issues found!`;
- первые попытки собрать пол руками падали на транзитивных пакетах,
  несовместимых с analyzer 12.1.0: `frontend_server.dart.snapshot`,
  analyzer_testing 0.4.3, analyzer_plugin 0.14.18, dart_style 3.1.9. Это беда
  стенда, а не пакета.

**Документы:**
- `check_translations.py` — `dashes: em dashes only` / `no differences`;
- `check_line_width.py` —
  `no Markdown line over 79 columns, no blank line doubled`;
- `reflow.py --check`, и общий проход, и обе записи —
  `every paragraph is filled to 79 columns`;
- `check_links.py` — `every document link resolves`.

**Зонды, текущее правило** (в скобках — правило `3a61a484`):
- `f1_retry_rethrow_last_checked` 0 (0)
- `f1_retry_rethrow_last_unchecked` 0 (0)
- `f1_retry_catch_e_is` 1 (1)
- `f1_isCancelled_first_broad` 1 (0)
- `f4_broad_kinds_rethrow` 0 (0)
- `f4_narrow_kinds_rethrow` 3 (0)
- `f4_reviewer_probe` 3 (0)
- `f4_narrow_inside_broad` 0 (0)
- `f4_broad_rethrow_in_block` 0 (0)
- `f4_broad_throw_with_trace` 1 (1)
- `err_unresolved_on_type` 1 (0)
- `err_on_without_type` 1 (0)
- `err_catch_no_body_end` 0 (0)
- `f2_named_forms` 1, только `obj(ctx: ctx)` (7)
- `f2_named_solo_context_and_call` 0 (2)
- `err_named_errors` 2 (4)
- `f10_var_not_reassigned` 1 (0)
- `f10_for_var_loop` 1 (0)
- `f10_parameter_reassigned` 0 (0)
- `f10_field_reassigned` 0 (0)
- `f10_late_final` 0 (0)
- `f9_empty_and_any` 0 (3)
- `f2_dynamic_calls` 4 (старое правило не запускал)
- `f2_super_and_tearoff` 0 (старое правило не запускал)

`catch_without_check` на тех же фрагментах даёт диагноз только на `catch`
в девяти местах: `f1_retry_rethrow_last_unchecked`, `f1_retry_catch_e_is`,
во всех четырёх `catch` `f4_broad_kinds_rethrow`, `f4_narrow_inside_broad`,
`f4_broad_rethrow_in_block`, `f4_broad_throw_with_trace`,
`err_catch_no_body_end`. На остальных — 0. На полу зонды `f1_*`, `f2_*`
и `f10_*` дали тот же вывод.

**Мутации.** Полный `dart test` после каждой, итог скрипта `restored, cmp ok`.

| | мутация | итог |
|---|---|---|
| M1 | `_handles` без `takesCancelled` | упал `test_catch_that_lets_a_cancellation_wait` |
| M2 | вернуть исключение «спросил задачу» | упал `test_catch_that_lets_a_cancellation_wait` |
| M3 | `_all`: снова `\|\| list.elements.isEmpty` | упал `test_collection_elements` |
| M4 | `replaceable = false` | упал `test_child_replaced_after_start` |
| M5 | `replaceable` для любой нефинальной переменной и поля | **выжила**, `+190` |
| M6 | именованный аргумент: `return null` | упал `test_hands_over_the_context` |
| M7 | `every` → `any` | упал `test_body_declared_at_the_top_level_and_passed_twice` |
| M8 | широкий только `on Object` | **выжила** |
| M9 | без `catch` без типа | **выжила** |
| M10 | без `on Exception` | **выжила** |
| M11 | без `on Outcome` | **выжила** |
| M12 | `takesCancelled` без `Outcome` | упал `test_clauses_that_take_cancelled` |
| M13 | `takesCancelled`: без типа → `false` | упали 3 теста `AddCheckFixTest` и `test_clauses_that_take_cancelled` |
| M14 | предложение находки 1 | `+190` — это цена правки, а не проверка теста |

На полу мутация через `correspondingParameter` дала `f2_named_forms: 7 lint(s)`
и уронила `bare_await_test.dart`; файл возвращён, `cmp` совпал.

**Расхождение задания с регламентом.** Одно: файл отчёта не записан, потому что
харнесс заблокировал Bash. Отчёт целиком в этом сообщении.

#### Итог

5 новых находок: важная — 1 (№1, повтор решения 127 с новым доводом), мелких —
4 (№2–№5). Из десяти находок второго ревью закрыты 9, не до конца — 1 (№1).
