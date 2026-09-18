> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана в третью редакцию.
> **Что это:** второй круг независимого ревью спеки
> `2026-09-13[10]-closed-state-freeze-design.md`. Прогон `agy`,
> `gemini-3.8-flash-high`, 589 с, зонды на своей копии пакетов. Рабочее дерево
> владельца не тронуто.
> **Связанные записи:** `2026-09-13[15]-closed-state-freeze-review-4.md`
> (второй ревьюер этого круга, прогон шёл одновременно); первый круг —
> `2026-09-13[11]` и `2026-09-13[12]`; спека
> `2026-09-13[10]-closed-state-freeze-design.md`.

WaitMsBeforeAsync:5000 was exceeded, waiting for find task.
Я запустил поиск репозитория `solo` на диске и ожидаю завершения задачи.
Ожидаю результат поиска.
# Второй круг ревью спецификации `docs/records/2026-09-13[10]-closed-state-freeze-design.md` (вторая редакция)

Проверка проводилась на изолированной копии пакетов вне рабочего каталога с имплементацией предлагаемого API (`isFinished` на основе `identical(_listeners, _closedListeners)` и бросок `StateError` в [`SoloBase.externalSetState`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L545)). Исходное дерево не изменялось; финальный `git status --short` в `/Users/user/development/my/solo` пуст.

---

## Находки

### Находка 1. Тест `externalSetState after close rebuilds nothing` теряет предмет проверки и не может быть просто «переписан»

- **Что не так:** Спека утверждает, что снимается только один тест ([`the builder is handed the cached state, not a fresh read`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L338)), а остальные семь тестов якобы «меняют только способ довести состояние до нужного, а проверяют по-прежнему своё». Для теста [`externalSetState after close rebuilds nothing`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L184) это неверно: довести состояние закрытого контроллера до нового значения невозможно в принципе, а проверка отсутствия перестройки при броске `StateError` теряет смысл.
- **Где:** [`packages/flutter_solo/test/solo_builder_test.dart:184`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L184), тест `externalSetState after close rebuilds nothing`; [`docs/records/2026-09-13[10]-closed-state-freeze-design.md:184`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B10%5D-closed-state-freeze-design.md#L184).
- **Доказательство:**
  Исходный тест проверял, что вызов `controller.set(const _Screen(name: 'Grace'))` после закрытия обновляет `currentState`, но виджет не перестраивается (остаётся 'Ada', `buildCount == 1`):
  ```dart
  await controller.close();
  controller.set(const _Screen(name: 'Grace'));
  await tester.pump();

  expect(buildCount, 1);
  expect(find.text('Ada'), findsOneWidget);
  ```
  Под предлагаемым запретом строка 204 бросает `StateError`, и состояние контроллера вообще не меняется:
  ```bash
  (cd packages/flutter_solo && flutter test test/solo_builder_test.dart --name="after close rebuilds nothing")
  ```
  Вывод:
  ```text
  00:00 +0: loading /Users/user/.gemini/antigravity-cli/scratch/solo_work/packages/flutter_solo/test/solo_builder_test.dart
  00:00 +0: externalSetState after close rebuilds nothing
  ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
  The following StateError was thrown running a test:
  Bad state: Cannot change state after closing has finished.

  When the exception was thrown, this was the stack:
  #0      SoloBase.externalSetState (package:solo/src/solo_base.dart:552:7)
  #1      _Controller.set (file:///Users/user/.gemini/antigravity-cli/scratch/solo_work/packages/flutter_solo/test/solo_builder_test.dart:15:29)
  #2      main.<anonymous closure> (file:///Users/user/.gemini/antigravity-cli/scratch/solo_work/packages/flutter_solo/test/solo_builder_test.dart:204:18)
  ...
  The test description was:
    externalSetState after close rebuilds nothing
  ════════════════════════════════════════════════════════════════════════════════════════════════════
  00:00 +0 -1: externalSetState after close rebuilds nothing [E]
  ```
  Если заменить вызов `set` на `expect(() => controller.set(...), throwsStateError)`, тест проверяет лишь то, что бросившая функция не перестроила виджет (состояние даже не успело измениться). А то, что `SoloBuilder` отображает закрытый контроллер и не меняется дальше, уже полноценно проверяется следующим тестом [`connecting an already closed controller shows its state and does not update further`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L212).
- **Что предлагаешь:**
  Признать, что тест `externalSetState after close rebuilds nothing` теряет самостоятельный предмет тестирования вслед за тестом кеша. Либо прямо удалить его (снимаются 2 теста, а не 1), либо переименовать его и объединить сценарий с тестом на `throwsStateError`.

**Вердикт:** принято. Снимается два теста, а не один: довести состояние
закрытого контроллера до нового значения под запретом нечем, и «виджет
не перестроился от бросившей функции» — проверка ни о чём. Предмет, ради
которого тест писался, целиком лежит в соседнем `connecting an already closed
controller shows its state and does not update further`. Второй ревьюер этого
круга пришёл с другой стороны к тому же выводу об этой фразе спеки: механически
переписать удаётся не всё.

---

### Находка 2. Список устаревающих мест пропускает русский перевод `Observing state`, `docs/architecture.md` и дартдок `SoloBase.close()`

- **Что не так:** Перечень устаревающих мест во второй редакции (7 пунктов) неполон:
  1. В `doc/state.md` для раздела «External state» спека упомянула русский перевод `docs/ru/solo/state.md`, а для раздела «Observing state» (строка 113: *«и `externalSetState` после этого не уведомляет никого»*) перевод не назван. Правка оригинала без правки перевода уронит проверку `python3 tool/check_translations.py` на CI.
  2. В [`docs/architecture.md:185`](file:///Users/user/development/my/solo/docs/architecture.md#L185) (Инвариант 8) перечислены писатели, бросающие `StateError` вне жизненного цикла: `emit, ctx.run, each, wait, join и uncancellable`. Появление броска из `externalSetState` после `isFinished` меняет архитектурный инвариант ядра и должно быть там зафиксировано.
  3. В дартдоке [`SoloBase.close()`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L551) фраза `The state is left as is` оставляет читателю ложное впечатление, что состояние просто остаётся текущим, но может быть изменено позже.
- **Где:**
  - [`docs/ru/solo/state.md:113`](file:///Users/user/development/my/solo/docs/ru/solo/state.md#L113)
  - [`docs/architecture.md:185`](file:///Users/user/development/my/solo/docs/architecture.md#L185)
  - [`packages/solo/lib/src/solo_base.dart:551`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L551)
- **Доказательство:**
  Команда:
  ```bash
  grep -n "не уведомляет никого" docs/ru/solo/state.md
  sed -n '185,191p' docs/architecture.md
  sed -n '550,553p' packages/solo/lib/src/solo_base.dart
  ```
  Вывод:
  ```text
  113:и `externalSetState` после этого не уведомляет никого.
  185:8. Состояние меняет и работу начинает только работающая задача. `emit`,
  186:   `ctx.run`, `each`, `wait`, `join` и `uncancellable` из завершившейся задачи
  187:   бросают `StateError`: утёкший контекст не пишет состояние вне критической
  188:   секции и не запускает действие рядом с уже идущей следующей задачей — такое
  189:   действие не считает ни очередь, ни `close`. Чтения (`state`, `stateAs`,
  190:   `check`, `log`) после завершения задачи законны.
  550:  /// Closes the controller, then calls the observer's `onClose`. Repeated
  551:  /// calls return the same future. The state is left as is.
  552:  ///
  553:  /// [SoloCloseMode.cancel], the default, drops every queued job with
  ```
- **Что предлагаешь:**
  Дополнить раздел «Что становится неправдой»:
  1. Включить явную правку `docs/ru/solo/state.md:113` («Observing state»).
  2. Обновить Инвариант 8 в `docs/architecture.md`, закрепив: после завершения работы движка (`isFinished`) вызов `externalSetState` бросает `StateError`.
  3. Уточнить дартдок `SoloBase.close`: `The state is frozen and cannot be changed further; externalSetState throws StateError after closing finishes`.

---

## Ответы на 8 обязательных вопросов с прогонами

### 1. Закрывает ли `isFinished` дыру с `drain` полностью?

**Да, закрывает полностью.**
Во время дренажа очередь выполняет оставшиеся задачи. В этот период `isClosed == true`, `isDraining == true`, но `isFinished == false`. Внешние события, защищённые `if (!isFinished)`, свободно проходят в `externalSetState`, обновляют `currentState`, доставляются слушателям и считываются задачами в очереди.
Как только очередь пустеет и `_finishClose` переводит `_listeners` в `_closedListeners`, `isFinished` синхронно становится `true`. Все последующие внешние вызовы безопасно отсекаются условием, молча отбрасываются, и `StateError` не выбрасывается.

- **Доказательство (зонд):**
  Команда:
  ```bash
  (cd packages/solo && dart test test/probe_question1_test.dart)
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_question1_test.dart
  00:00 +0: isFinished protects drain completely: facts arrive during drain, dropped after, no StateError
  00:00 +1: All tests passed!
  ```
  Тест подтвердил:
  - До закрытия и во время дренажа: факты приняты (`accepted: 1`, `currentState: 10`, задача увидела `[0, 10]`).
  - После завершения дренажа (`drainFuture` завершён, `isFinished: true`): новые факты отброшены (`dropped: 1`, `currentState: 10`), исключений нет.
  - Незазищённый вызов `externalSetState` после черты выбрасывает `StateError`.

---

### 2. Правда ли между проверкой и записью выполниться нечему?

**Да, правда. Гонки нет.**
В однопоточной модели изолята Dart синхронный код выполняется без прерываний:
1. **Точки приостановки (suspension points):** между `if (!isFinished)` и `externalSetState(payload)` отсутствуют `await` и `yield`. Вызов `externalSetState` следует непрерывно за чтением геттера.
2. **Синхронность закрытия:** метод `_finishClose` (единственное место, где `_listeners` становится `_closedListeners`) **никогда не выполняется синхронно** внутри вызова `close()`. Закрытие всегда планирует `_finishClose` через `scheduleMicrotask`, либо ожидает завершения задачи через `current._whenDone.then(...)`, либо вызывается из `_pump()`, работающего на микротаске. Поэтому даже если вычисление аргумента записи вызовет `close()`, `isFinished` останется `false` до возврата управления в event loop.
3. **Реентрантность и зоны:** реентрантный вызов из `onChange` или зоны выполняется в том же синхронном стеке и видит консистентное состояние; таймеры и микротаски зон не могут вклиниться в середину синхронного выражения.

- **Доказательство (зонд):**
  Команда:
  ```bash
  (cd packages/solo && dart test test/probe_question2_test.dart)
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_question2_test.dart
  00:00 +0: closing inside argument computation does not finish synchronously
  00:00 +1: reentrant call from onChange does not encounter isFinished race
  00:00 +2: zone runBinary or runUnary cannot preempt synchronous execution
  00:00 +3: All tests passed!
  ```

---

### 3. Остаётся ли путь, на котором корректная программа всё-таки получит `StateError`?

**Нет, такого пути не остаётся.** Бросок `StateError` верен и не должен заменяться молчанием.
Проверены все потенциально опасные точки:
- **`drain`**: `isFinished` остаётся `false` на протяжении всей работы очереди; задачи пишут через `ctx.emit` штатно.
- **Дети (`ctx.each` / дочерние задачи)**: родительская задача ожидает завершения детей в `_awaitChildren()` перед завершением. Дочерние задачи завершаются строго до наступления черты закрытия контроллера.
- **`cancellable: false`**: закрытие ожидает завершения неотменяемой задачи через `current._whenDone`. Черта наступает только после завершения её тела и очистки.
- **Аккумуляция (`debounce`, `throttle`, `collect`, `accumulate`)**: при `cancel` таймеры окон отменяются в `_stopWork`; при `drain` окна отрабатывают до наступления `_finishClose`.
- **`onDispose` / `onDiscard`**: диспозеры выполняются внутри `JobBase._execute` в цикле `_cleanup` **до** вызова `finish()`. В этот момент задача ещё не завершена, `_whenDone` не сработал, и `isFinished` контроллера равен `false`. Запись или очистка из диспозера безопасна.
- **Приостановленная подписка на стрим (`stream.listen()..pause()`)**: `Solo.close()` ждёт `_controller.close()`, но `_finishClose` в базовом классе наступает раньше. Корректный наследник, защищающий источник через `if (!isFinished)`, видит `isFinished == true` и отбрасывает запись без ошибки.

- **Доказательство (зонд):**
  Команда:
  ```bash
  (cd packages/solo && dart test test/probe_question3_test.dart)
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_question3_test.dart
  00:00 +0: onDispose/onDiscard running during close: can write or finish safely
  00:00 +1: can onDispose call ctx.emit?
  ctx.emit in onDispose error: null
  00:00 +2: children (each) during drain / close
  00:00 +3: paused stream subscription in Solo subclass
  00:00 +4: All tests passed!
  ```

---

### 4. `isFinished` — новый член наследуемого класса

**Да, добавление `isFinished` в `SoloBase` — это breaking change.**
1. **Проверка анализатором:** Если наследник объявляет поле, метод или геттер с именем `isFinished`, компилятор Dart бракует класс:
   - При несовпадающем типе: `error: 'ConflictSoloInt.isFinished' ('int Function()') isn't a valid override of 'SoloBase.isFinished' ('bool Function()'). - invalid_override`
   - При методе вместо геттера: `error: Class 'ConflictSoloMethod' can't define method 'isFinished' and have field 'SoloBase.isFinished' with the same name. - conflicting_method_and_field`
   - При поле `bool isFinished`: линтер требует `@override`, а внешние вызовы начинают переопределять контракт.
2. **Конфликты в репозитории:**
   Внутри монорепозитория `solo` (в `packages/solo`, `packages/flutter_solo`, `example`) членов с именем `isFinished` у контроллеров **нет** (0 конфликтов).
   Однако в соседнем пакете `async_job` геттер с именем `isFinished` уже есть у интерфейса `Job`. Поэтому в контроллерах, управляющих сложными задачами или процессами скачивания/синхронизации, имя `isFinished` — одно из самых вероятных пользовательских имён для флагов состояния.
   Спека абсолютно обоснованно квалифицирует это как ломающее изменение (`**Breaking:**`), требующее фиксации в `CHANGELOG.md`.

---

### 5. Переписываются ли семь тестов на самом деле?

Спека утверждает: 1 снимается, 7 переписываются.
Детальный аудит каждого из 8 тестов:
1. `listeners_base_test.dart:248` (`after close addListener does not retain listener and does not notify`): **переписывается**. Вызов `externalSetState` заменяется на `expect(..., throwsStateError)`. Проверка `hasListeners == false` сохраняется.
2. `solo_builder_test.dart:184` (`externalSetState after close rebuilds nothing`): **ТЕРЯЕТ СМЫСЛ (Находка 1)**. Тест проверял отсутствие перестройки `SoloBuilder` при изменении `currentState` закрытого контроллера. Так как после закрытия `currentState` не меняется в принципе, тестировать реакцию виджета не на что. Этот тест — виджетный близнец снятого теста 4.
3. `solo_builder_test.dart:212` (`connecting an already closed controller shows its state and does not update further`): **переписывается**. Состояние задаётся до вызова `close()`, закрытый контроллер подключается к виджету, а попытка изменить его после закрытия проверяется на `throwsStateError`.
4. `solo_builder_test.dart:338` (`the builder is handed the cached state, not a fresh read`): **снимается** (разница между кешем и чтением перестаёт быть наблюдаемой).
5. `solo_listenable_test.dart:199` (`close removes every listener`): **переписывается**. Проверка сброса слушателей выполняется через `expect(counter.hasListeners, isFalse)`.
6. `solo_listenable_test.dart:221` (`a listener added after close hears nothing and is not retained`): **переписывается**. Строка `expect(counter.value, 7)` заменяется на `expect(counter.value, 0)`, а попытка записи ожидает `throwsStateError`.
7. `solo_listenable_test.dart:246` (`a microtask scheduled from observer.onClose does not notify listeners`): **переписывается**. Микротаска оборачивается в обработку ошибки записи (иначе необработанный `StateError` роняет тест Flutter-раннера).
8. `solo_selection_test.dart:405` (`a selection of a closed controller answers from the state`): **переписывается**. Исходное значение задаётся до закрытия, проверяется `name.value == 'Ada'`, а вызов `set` после закрытия бросает `StateError`.

**Итог:** смысл теряют **два** теста (`the builder is handed the cached state...` и `externalSetState after close rebuilds nothing`), а не один.

---

### 6. Полон ли теперь список устаревающих мест?

Спека насчитала 7 мест (плюс пометка в `2026-09-13[2]`).
Список **не полон**. В него необходимо добавить ещё 3 места:
1. **`docs/ru/solo/state.md:113`** (русский перевод абзаца «Observing state»): строка *«и `externalSetState` после этого не уведомляет никого»* осталась без внимания спеки, хотя для «External state» перевод был назван.
2. **`docs/architecture.md:185`** (Инвариант 8): документ фиксирует фундаментальные инварианты ядра. В перечень операций, бросающих `StateError` после завершения, необходимо включить `externalSetState` после `isFinished`.
3. **`packages/solo/lib/src/solo_base.dart:551`** (дартдок `SoloBase.close`): фраза *«The state is left as is»* требует уточнения о том, что состояние окончательно замораживается и попытки его записи бросают ошибку.

---

### 7. Черта и наследник: работа после `await super.close()`

Для наследника, который переопределяет метод `close()`:
```dart
@override
Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
  await super.close(mode: mode);
  // Что происходит здесь?
}
```
`super.close(mode: mode)` завершается только тогда, когда метод `_finishClose` уже полностью отработал, перевёл `_listeners` в сигнальное состояние `_closedListeners` и вызвал `completer.complete()`.
Следовательно:
1. **Успеть записать что-либо после `await super.close()` невозможно.** В момент возобновления выполнения кода наследника `isFinished` уже строго равен `true`. Любой вызов `externalSetState(...)` немедленно завершится выбросом `StateError`.
2. **Что наследник обязан делать вместо этого:**
   - Если наследнику требуется записать терминальное состояние, он обязан сделать это **до** вызова `super.close()`:
     ```dart
     @override
     Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
       externalSetState(FinalState());
       await super.close(mode: mode);
     }
     ```
     (Либо внутри синхронного хука `observer.onClose`, который вызывается до черты).
   - Если наследник гасит внешние источники: при `cancel` отписка выполняется до `super.close()`; при `drain` внешний источник продолжает работать во время дренажа под защитой `if (!isFinished)`, а код после `await super.close()` занимается исключительно освобождением ресурсов, не пытаясь мутировать контроллер.

- **Доказательство (зонд):**
  Команда:
  ```bash
  (cd packages/solo && dart test test/probe_question7_test.dart)
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_question7_test.dart
  00:00 +0: writing after await super.close() throws StateError
  00:00 +1: writing before super.close() succeeds and reaches listeners
  00:00 +2: All tests passed!
  ```

---

### 8. Что делать с `SoloBuilder`?

**Рекомендация: снять кеш.**

- **Обоснование:**
  1. **Принцип проверяемости обещаний (Testing what is promised):** Спека прямо констатирует: *«Проверка показала, что обещание кеша держать нечем — подмена кеша на чтение currentState прямо в build переживала весь набор»*. Тест на кеш снимается именно потому, что после запрета записи после закрытия кеш и прямое чтение `currentState` становятся неразличимы при любых условиях. Сохранять в кодовой базе кеш, контракт которого невозможно верифицировать ни одним тестом, противоречит инженерным принципам проекта.
  2. **Упрощение кода виджета:** Удаление кеша ликвидирует приватное поле `_state`, избавляет от необходимости инициализировать его в `initState`, синхронизировать при смене контроллера в `didUpdateWidget` и перезаписывать в `_valueChanged`. Метод `_valueChanged` сокращается до чистого `setState(() {})`, а метод `build` просто вызывает `widget.builder(context, widget.solo.currentState, widget.child)`.
  3. **Снятие ложного обещания из документации:** Исчезает необходимость объяснять в дартдоке разницу между «cached state» и «fresh read on each frame».
- **Проверка прогоном:**
  После удаления `_state` из `_SoloBuilderState` и удаления неактуального теста кеша все 7 сценариев `solo_builder_test.dart`, тестирующих штатную работу виджета, проходят безупречно:
  ```bash
  (cd packages/flutter_solo && flutter test test/solo_builder_test.dart)
  ```
  Вывод:
  ```text
  00:00 +0: rebuilds on state change and builder receives the new state
  00:00 +1: a change before subscription is visible on the very first build
  00:00 +2: didUpdateWidget with a different controller switches subscription and shows the new state on the first build
  00:00 +3: dispose removes listener so state change neither rebuilds nor throws
  00:00 +4: child is handed back to builder untouched and not recreated
  00:00 +5: switching to a controller that is merely equal still switches the subscription
  00:00 +6: takes a plain Solo, which no ValueListenableBuilder would
  00:00 +7: All tests passed!
  ```

---

## Что в спеке верно и подтверждено проверками

1. **`isFinished` полностью решает проблему `drain`**: наследник с внешним источником, защищённым `if (!isFinished)`, больше не глушит поток событий на старте `close(mode: drain)` и не падает после его окончания (проверено в Вопросе 1).
2. **Отсутствие точек гонки**: в синхронном шаге между чтением геттера `isFinished` и `externalSetState` выполниться нечему; `_finishClose` никогда не вызывается синхронно (проверено в Вопросе 2).
3. **Использование `identical(_listeners, _closedListeners)` в качестве sentinel**: не требует заведения нового поля, корректно работает во всех 5 маршрутах закрытия и точно определяет окончание работы движка (подтверждено набором из 516 тестов `solo`).
4. **Обоснованность выбора `StateError`**: в ядре `solo` действительно 0 `assert`, а прецедент `ctx.emit` (`throwIfFinished`) строго гармонирует с броском при записи после черты (подтверждено в Вопросе 3).
5. **Разделение черты движка и публичного `close()`**: на примере контроллера с приостановленной подпиской на стрим доказано, что `isFinished` наступает строго в конце работы движка, даже если `Solo.close()` ещё ожидает закрытия стрима (проверено в Вопросе 3 и Вопросе 7).
6. **Квалификация `isFinished` как ломающего изменения (`Breaking`)**: добавление нового публичного члена в `SoloBase` ломает подклассы при конфликте имён (проверено анализатором в Вопросе 4).
{"analyze_result":"Clean: dart analyze and flutter analyze passed.","done":true,"files_changed":[],"mutation_kills_test":true,"not_done":"","notes":"Второй круг ревью спецификации docs/records/2026-09-13[10]-closed-state-freeze-design.md завершён. Проведены прогоны зондов по всем 8 вопросам, выявлены 2 находки (тест externalSetState after close rebuilds nothing теряет смысл, неполнота списка устаревающих мест в переводах, architecture.md и дартдоках). Дерево чистое.","tests_command":"dart test (solo, example), flutter test (flutter_solo)","tests_result":"612 тестов зелёные на базовом дереве (516 solo + 9 example + 87 flutter_solo); зонды подтвердили поведение под запретом.","toolAction":"Finishing task","toolSummary":"Finish review task"}

**Вердикт:** принято, все три. Пропуск перевода «Наблюдения за состоянием»
— чистая ошибка редактуры: для «External state» перевод назван, для соседней
секции забыт, и `check_translations.py` уронил бы гейт. Инвариант 8
в `docs/architecture.md` перечисляет писателей, бросающих `StateError` вне
жизненного цикла, и `externalSetState` туда добавляется. Дартдок
`SoloBase.close()` с «The state is left as is» читается теперь наоборот.
Второй ревьюер добавил к списку ещё три места; все в третьей редакции.

