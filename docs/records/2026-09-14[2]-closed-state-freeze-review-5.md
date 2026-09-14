> **Состояние на 2026-09-14:** все шесть находок приняты и закрыты правками;
> вердикты стоят в конце каждой.
> **Что это:** ревью исполнения заморозки — коммиты `365d7b9` и `3f7542b`, —
> `agy` (`gemini-3.8-flash-high`, 483 с), один из двух ревьюеров круга.
> **Связанные записи:** второй ревьюер того же круга —
> `2026-09-14[3]-closed-state-freeze-review-6.md`; спека
> `2026-09-13[10]-closed-state-freeze-design.md`; план
> `2026-09-14[1]-closed-state-freeze-plan.md`.

# Ревью коммитов 365d7b9 и 3f7542b (заморозка состояния закрытого контроллера)

## 1. Дартдок SoloBuilder привязывает сброс слушателей к завершению close()

- **Место:** `packages/flutter_solo/lib/src/solo_builder.dart`, строки 23–24.
- **Цитата:**
  ```dart
  /// If [SoloBase.close] has finished, the controller drops all listeners and
  /// stops notifying; connecting an already closed controller displays its
  /// current state and receives no further updates.
  ```
- **Что неверно:** Дартдок утверждает, что контроллер сбрасывает слушателей, если `[SoloBase.close]` завершился (`If [SoloBase.close] has finished, the controller drops all listeners...`). Это не совпадает с движком: движок сбрасывает слушателей синхронно в точке `_finishClose` в момент окончания собственной работы, не дожидаясь завершения публичного `close()`. Для контроллера `Solo` (наследника `SoloBase`), закрытие которого ждёт закрытия стрима, завершение `close()` и сброс слушателей движком разнесены во времени.
- **Чем доказано:** Зонд с приостановленной подпиской на стрим `Solo` (`packages/solo`):
  ```dart
  final solo = TestStreamSolo();
  solo.addListener(() {});
  final sub = solo.stream.listen((_) {})..pause();
  var closeFinished = false;
  solo.close().then((_) => closeFinished = true);
  await Future<void>.delayed(Duration.zero);
  print('closeFinished: $closeFinished, isFinished: ${solo.isFinished}, hasListeners: ${solo.hasListeners}');
  ```
  Вывод:
  ```
  closeFinished: false, isFinished: true, hasListeners: false
  ```
  `closeFinished` равен `false` (вызов `close()` ещё не завершился), тогда как `isFinished` равен `true`, а слушатели уже сброшены (`hasListeners: false`).
- **Во что обходится читателю:** Читатель и разработчик подкласса рассчитывают, что слушатели остаются активными до тех пор, пока не завершится `Future` от `close()`, тогда как движок сбрасывает их до завершения закрытия стрима или дочерних ресурсов.

**Вердикт:** принято. Дартдок переписан: «once the engine has finished closing
— [SoloBase.isFinished], which is not the same moment as the future of
[SoloBase.close] completing». Отдельно стоит отметить, откуда взялась эта
неправда: в самом коммите `365d7b9` прежнее «If close was called» было
поправлено на «has finished» — одна неточность сменилась другой, и ни один тест
этого не ловит, потому что предмет тут только текст.

---

## 2. В vs-bloc.md осталась старая рекомендация гасить внешний источник до close()

- **Место:** `packages/solo/doc/vs-bloc.md`, строка 1505 и перевод `docs/ru/solo/vs-bloc.md`, строка 1517.
- **Цитата:**
  В `packages/solo/doc/vs-bloc.md:1505`:
  ```markdown
  Stop the auth listener before closing either controller. How is up to the
  application; the snippets show registration only.
  ```
  В `docs/ru/solo/vs-bloc.md:1517`:
  ```markdown
  Остановите слушатель авторизации до закрытия любого из контроллеров. Как
  именно, решает приложение; фрагменты показывают только регистрацию.
  ```
  При этом в коде контроллера выше (строка 1481 / 1489):
  ```dart
  auth.onRevoked = (reason) => externalSetState(SignedOut(reason));
  ```
- **Что неверно:** Текст сохранил старое правило («Stop the source ... before closing the controller»), процитированное в спеке `docs/records/2026-09-13[10]-closed-state-freeze-design.md` (строки 36–37) из прежнего дартдока `externalSetState`. Новый документированный порядок (`doc/state.md:219–225`, `packages/solo/CHANGELOG.md:16–18`) прямо требует противоположного: источник не гасится до `super.close()`, а защищается `!isFinished` и отменяется после `super.close()`, чтобы не лишать событий дренирующуюся очередь при `SoloCloseMode.drain`. В сниппете `ReportController` защиты `!isFinished` нет.
- **Чем доказано:** Прямое противоречие с `packages/solo/CHANGELOG.md:16–18`:
  > «The documented order changes with it: a source is no longer stopped before `super.close()`, it is guarded and cancelled afterwards, which is the one order that serves both close modes.»
- **Во что обходится читателю:** Читатель, скопировавший этот паттерн из сценария 10 `vs-bloc`, получит либо зависание/голодание очереди при `SoloCloseMode.drain` (если погасит источник до `close`), либо необработанный `StateError` при попытке вызвать `auth.onRevoked` после завершения закрытия (так как проверка `!isFinished` в сниппете отсутствует).

**Вердикт:** принято, и это самое дорогое из найденного: четырнадцатое место,
которое читатель копирует к себе. Мой греп его не нашёл, потому что фраза не
содержит ни «after close», ни `externalSetState` рядом. Правка в обоих языках:
проза называет разный порядок для bloc и для контроллера, а сниппет получил
защиту `if (!isFinished)`. Стенд после правки собирает 22 драйвера и проходит
все.

---

## 3. Нестыковки в CHANGELOG flutter_solo: обещание кеша у SoloBuilder и привязка сброса слушателя к завершению close

- **Место:** `packages/flutter_solo/CHANGELOG.md`, строки 19–20 и строки 59–61.
- **Цитата 1 (строки 19–20):**
  ```markdown
  Both take any SoloBase -- a plain Solo included -- read the state after
  subscribing and cache it, compare controllers by identity when the parent
  hands over a new one, and pass child through untouched.
  ```
- **Цитата 2 (строки 59–61):**
  ```markdown
  - **Fix:** a listener registered after `close` had finished was kept in memory
    for good. It was never notified -- a flag saw to that -- but it was held; now
    the registration is refused outright and nothing is retained.
  ```
- **Что неверно:**
  1. В одном и том же разделе `## Unreleased` строка 20 обещает, что `SoloBuilder` кеширует состояние (`and cache it`), тогда как первая запись того же раздела (строки 3–7) сообщает, что кеш снят: `SoloBuilder no longer keeps a copy of the state... and the promise in the dartdoc are gone together`.
  2. Строка 59 привязывает сброс регистрации к моменту `after close had finished` вместо окончания работы движка (`after the engine has finished closing`), повторяя формулировку, которая была специально исправлена в `packages/solo/CHANGELOG.md:58–62`.
- **Чем доказано:** Дифф коммита `365d7b9` удалил поле `_state` и кеширование из `SoloBuilder`. Прогон зонда `paused_probe.dart` показал, что регистрация слушателя отклоняется сразу по наступлении `isFinished`, даже когда `close()` ещё не завершился (`closeFinished == false`).
- **Во что обходится читателю:** Читатель видит взаимоисключающие описания `SoloBuilder` в рамках одного невыпущенного релиза и получает неточную ментальную модель момента отключения слушателей.

**Вердикт:** принято обе половины. «read the state after subscribing and cache
it» заменено на «subscribe in `initState`, read the controller's state on every
build»; запись о поздней регистрации привязана к концу работы движка, а не к
завершению `close`. Первое — моя недоработка: запись о снятом кеше я добавил
сверху, а соседнюю в том же невыпущенном разделе не перечитал.

---

## 4. В CHANGELOG solo не сказано, как теперь выставлять терминальное состояние при закрытии

- **Место:** `packages/solo/CHANGELOG.md`, строки 3–8.
- **Цитата:**
  ```markdown
  - **Breaking:** the state of a closed controller is final. Once the engine has
    finished closing, `externalSetState` throws a `StateError` where it used to
    change `currentState` and call the change hooks with nobody left to hear them
    -- the listeners were gone and a closed stream dropped the event, so the
    state moved in silence and every reader had to choose for itself between the
    last thing it was told and what the controller holds now.
  ```
- **Что неверно:** Запись объясняет, что запись после закрытия теперь бросает `StateError`. Однако разработчик подкласса, который ранее устанавливал финальное состояние после закрытия (например, `await super.close(); externalSetState(TerminalState());`), не получает из записи ответа на вопрос: как теперь корректно перевести контроллер в терминальное состояние при закрытии?
- **Чем доказано:** В спеке `docs/records/2026-09-13[10]-closed-state-freeze-design.md` (строки 273–275) этот вопрос прямо разобран:
  > «после `await super.close()` наследник записать уже ничего не может: базовый `Future` завершается за чертой. Терминальное состояние пишется до `super.close()` или синхронно изнутри `observer.onClose`».
  В тексте `CHANGELOG.md` это руководство полностью опущено.
- **Во что обходится читателю:** Мигрирующий разработчик видит запрет и падение с `StateError`, но не получает явного рецепта миграции для финального состояния (писать до `super.close()` или синхронно из `onClose`).

**Вердикт:** принято. В `CHANGELOG` ядра добавлен пункт «Migrating a subclass»:
терминальное состояние пишется до `super.close()` или синхронно из
`observer.onClose`, а после `await super.close()` его девать уже некуда. Спека
это знала, читатель — нет.

---

## 5. Неточная формулировка границы закрытия в CHANGELOG solo («where close returns»)

- **Место:** `packages/solo/CHANGELOG.md`, строки 13–14.
- **Цитата:**
  ```markdown
  The line is where the listeners are dropped, not where `close` returns.
  ```
- **Что неверно:** В Dart метод `Future<void> close()` возвращает объект `Future` немедленно (синхронно). Формулировка `where close returns` вводит в заблуждение: имелось в виду `not where the Future returned by close completes` (не момент завершения `Future` от `close()`). Синхронный возврат метода `close` происходит в первой строке закрытия, когда `isFinished` ещё ложен и идёт дренаж; завершение же `Future` у подклассов со стримом наступает позже сброса слушателей.
- **Чем доказано:** Сигнатура `Future<void> close()` в Dart. Метод возвращает `Future` синхронно при вызове; завершение асинхронной операции обозначается как `completes`, а не `returns`.
- **Во что обходится читателю:** Путаница между синхронным возвратом метода `close()` и завершением возвращённого им `Future`.

**Вердикт:** принято. «not where `close` returns» заменено на «not where the
future `close` returns completes», с примером про приостановленную подписку. В
Dart метод возвращает `Future` синхронно, и прежняя фраза называла ровно тот
момент, который я хотел исключить.

---

## 6. Изменения в flutter_solo CHANGELOG не имеют статуса Breaking

- **Место:** `packages/flutter_solo/CHANGELOG.md`, строки 62–68.
- **Цитата:**
  ```markdown
  - A change delivered from a microtask scheduled inside the observer's `onClose`
    no longer reaches listeners -- and with `solo` freezing the state of a closed
    controller, it is no longer a change at all: the engine has finished by then,
    so `externalSetState` from there throws a `StateError`. The list used to be
    dropped one microtask later, in the continuation of the engine's close; the
    engine now drops it synchronously, right after the hook. A change made
    *inside* the hook still reaches them.
  ```
- **Что неверно:** Запись описывает ломающее изменение поведения: ранее `externalSetState` из микротаски `onClose` молча отбрасывался, а теперь бросает `StateError`. Поскольку микротаска выполняется асинхронно в корневой зоне событий, брошенный `StateError` становится необработанным исключением (`unhandled asynchronous error`), которое роняет процесс или завершает тесты ошибкой. Запись оформлена обычным пунктом списка без метки `**Breaking:**`.
- **Чем доказано:** Тест `packages/flutter_solo/test/solo_listenable_test.dart:272–276` и план (строки 138–143):
  > «тест про микротаску падает дважды. Отвергнутая запись бросает внутри микротаски, ошибка уходит в зону, и тест получает второй провал уже после собственного конца».
- **Во что обходится читателю:** Пользователь, обновляющий `flutter_solo`, не видит ломающего изменения при беглом просмотре changelog и сталкивается с аварийным падением приложения из-за необработанного `StateError` в зоне.

**Вердикт:** принято, с оговоркой по цене. Оценка «роняет процесс» завышена:
ошибка из микротаски уходит в зону, и в приложении это репорт, а не
обязательный крэш. Но пометка заслужена по другой причине — молчаливая потеря
доставки стала ошибкой, и беглый читатель обязан это увидеть. `**Breaking:**`
поставлено.

---

## Анализ вопросов без дефектов (подтверждённые свойства)

### Вопрос 2: Рецепт Camera и соответствие документов коду
- Рецепт `Camera` из `packages/solo/doc/state.md` собран в отдельном тестовом проекте `scratch/camera_check` с путевой зависимостью на `packages/solo`.
- Код компилируется без ошибок и предупреждений анализатора.
- Поведение проверено в обоих режимах:
  - `SoloCloseMode.cancel`: контроллер закрывается, `isFinished` переходит в `true`, событие от устройства игнорируется условием `!isFinished`, `_link.cancel()` корректно завершается.
  - `SoloCloseMode.drain`: во время опустошения очереди `isFinished` равен `false`, внешнее событие от устройства принимается через `externalSetState` и отменяет зависящую задачу; после завершения дренажа `isFinished` равен `true`, поздние события безопасно отбрасываются.
  - Зонд на ловушку с `await` между проверкой и записью подтвердил бросок `StateError: Bad state: Camera has finished closing, cannot set state`.
- Русский перевод `docs/ru/solo/state.md` полностью соответствует английскому оригиналу по смыслу.
- Инвариант 8 в `docs/architecture.md` точно описывает контракт заморозки состояния и совпадает с поведением движка.

### Вопрос 3: Проверка переписанных тестов мутациями
Все шесть переписанных тестов проверены мутациями:
1. `listeners_base_test.dart` (`after close addListener does not retain listener and does not notify`):
   - Мутация `addListener` (отключение проверки `_finished`): падение на строке 257 (`Expected: false, Actual: <true>`).
   - Мутация `externalSetState` (тихий возврат): падение на строке 259 (`Expected: throws StateError, Actual: returned null`).
2. `solo_listenable_test.dart` (`close removes every listener`):
   - Мутация `_finishClose` (отключение сброса списка слушателей): падение на строке 213 (`Expected: false, Actual: <true>`).
3. `solo_listenable_test.dart` (`a listener added after close hears nothing and is not retained`):
   - Сторожит отказ в удержании и бросок `StateError`.
4. `solo_listenable_test.dart` (`a microtask scheduled from observer.onClose does not notify listeners`):
   - Мутация `_finishClose` (перенос сброса слушателей в `scheduleMicrotask`): падение на строке 283 (`Expected: false, Actual: <true>`).
5. `solo_selection_test.dart` (`a selection of a closed controller answers from the state`):
   - Сторожит чтение финального состояния из закрытого источника и бросок `StateError` на позднюю запись.
6. `solo_builder_test.dart` (`connecting an already closed controller shows its state and does not update further`):
   - Сторожит отображение финального состояния при подключении к закрытому контроллеру и неизменность при перестроении родителя.

Снятые тесты:
- `externalSetState after close rebuilds nothing` снят обоснованно: довести состояние закрытого контроллера до нового значения невозможно, а поведение смонтированного билдера при закрытии и попытке записи проверяется тестом `a controller closed under a mounted builder keeps showing its state`.
- `the builder is handed the cached state, not a fresh read` снят обоснованно: кеш удалён из `SoloBuilder`, а при замороженном состоянии прямое чтение и кеш тождественны.

### Вопрос 4: Проверка фактов компилятором
- Наличие геттера `isFinished` у класса `Job` в `packages/async_job`: подтверждено (`packages/async_job/lib/src/job_base.dart:111`, `bool get isFinished;`).
- Ошибки компиляции при наличии собственного члена `isFinished` в подклассе `SoloBase`: проверено запуском `dart analyze` на тестовом файле с конфликтующими членами (`int isFinished` вызывает `invalid_override`, `bool isFinished()` вызывает `conflicting_method_and_field`).

---

## Чем проверял

1. `git status` — проверка чистоты рабочей копии.
2. `git show --stat 365d7b9` и `git show --stat 3f7542b` — анализ состава коммитов.
3. `git diff 365d7b9^! ...` и `git diff 3f7542b^! ...` — детальный построчный анализ изменений во всех затронутых файлах.
4. `cd packages/solo && dart test && dart analyze` — базовый прогон тестов ядра (526 тестов, анализ чист).
5. `cd packages/solo/example && dart test && dart analyze` — прогон тестов примера solo (9 тестов, анализ чист).
6. `cd packages/flutter_solo && flutter test && flutter analyze` — прогон тестов flutter_solo (87 тестов, анализ чист).
7. `cd packages/flutter_solo/example && flutter analyze` — анализ примера flutter_solo (чист).
8. Сборка отдельного проекта `camera_check` (`dart pub get && dart run bin/main.dart`):
   - Компиляция и выполнение рецепта `Camera` из `packages/solo/doc/state.md`.
   - Проверка поведения в режимах `SoloCloseMode.cancel` и `SoloCloseMode.drain`.
   - Проверка ловушки с `await` между проверкой `!isFinished` и вызовом `externalSetState`.
9. Запуск зонда `paused_probe.dart` (`dart run bin/paused_probe.dart`):
   - Проверка состояния `isFinished` и `hasListeners` при закрытии `Solo` с приостановленной подпиской на `stream`.
10. Мутационное тестирование тестов в `packages/solo` и `packages/flutter_solo`:
    - Мутация `addListener` (отключение проверки `_finished`):
      `dart test test/listeners_base_test.dart -n "after close addListener"` -> FAILED (Expected: false, Actual: <true>).
    - Мутация `externalSetState` (замена броска `StateError` на silent return):
      `dart test test/listeners_base_test.dart -n "after close addListener"` -> FAILED (Expected: throws StateError, Actual: returned null).
    - Мутация `_finishClose` (отключение сброса `_listeners`):
      `flutter test test/solo_listenable_test.dart --name "close removes every listener"` -> FAILED (Expected: false, Actual: <true>).
    - Мутация `_finishClose` (перенос сброса `_listeners` в `scheduleMicrotask`):
      `flutter test test/solo_listenable_test.dart --name "a microtask scheduled from observer.onClose does not notify listeners"` -> FAILED (Expected: false, Actual: <true>).
    - Все мутации выполнялись по строгому регламенту: `cp file file.orig`, внесение мутации, запуск теста, `cp file.orig file && rm file.orig`, верификация `git status --short`.
11. Проверка конфликтов компилятором `dart analyze bin/conflict_check.dart`:
    - Подтверждение ошибок `invalid_override` и `conflicting_method_and_field` при совпадении имени `isFinished`.
12. `git status --short` в конце работы — подтверждение отсутствия несохранённых изменений в репозитории (единственный созданный файл — `REVIEW.md`).
