> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана во вторую редакцию.
> **Что это:** первый круг независимого ревью спеки
> `2026-09-13[10]-closed-state-freeze-design.md`. Прогон `agy`,
> `gemini-3.8-flash-high`, 454 с, зонды и полные наборы под вставленным
> запретом. Работал в рабочем дереве владельца, а не в клоне: время правки
> `packages/solo/lib/src/solo_base.dart` — 22:07:33, посреди прогона. За собой
> прибрал, дерево осталось чистым.
> **Связанные записи:** `2026-09-13[12]-closed-state-freeze-review-2.md`
> (второй ревьюер этого круга, прогон шёл одновременно); спека
> `2026-09-13[10]-closed-state-freeze-design.md`.

# Ревью спецификации `docs/records/2026-09-13[10]-closed-state-freeze-design.md`

---

## Находки (что не так)

### Находка 1. Спека назвала только один ломающийся тест, но на самом деле краснеют 8 тестов в двух пакетах (7 тестов упущены)

- **Что не так:** Спека утверждает, что снимается только один тест [`the builder is handed the cached state, not a fresh read`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L338), однако в действительности при броске `StateError` из `externalSetState` после закрытия падают **8 тестов** (1 в `solo` и 7 в `flutter_solo`).
- **Где:**
  - [`packages/solo/test/listeners_base_test.dart`](file:///Users/user/development/my/solo/packages/solo/test/listeners_base_test.dart#L248), тест `after close addListener does not retain listener and does not notify`
  - [`packages/flutter_solo/test/solo_builder_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L184), тест `externalSetState after close rebuilds nothing`
  - [`packages/flutter_solo/test/solo_builder_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L212), тест `connecting an already closed controller shows its state and does not update further`
  - [`packages/flutter_solo/test/solo_builder_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L338), тест `the builder is handed the cached state, not a fresh read` (единственный названный в спеке)
  - [`packages/flutter_solo/test/solo_listenable_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L199), тест `close removes every listener`
  - [`packages/flutter_solo/test/solo_listenable_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L221), тест `a listener added after close hears nothing and is not retained`
  - [`packages/flutter_solo/test/solo_listenable_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L246), тест `a microtask scheduled from observer.onClose does not notify listeners`
  - [`packages/flutter_solo/test/solo_selection_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_selection_test.dart#L405), тест `a selection of a closed controller answers from the state`
- **Доказательство:**
  Прогон тестов с проверкой `if (identical(_listeners, _closedListeners)) throw StateError(...);` в [`SoloBase.externalSetState`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L545):

  Команда в `packages/solo`:
  ```bash
  dart test test/listeners_base_test.dart -n "after close addListener"
  ```
  Вывод:
  ```text
  00:00 +0: loading test/listeners_base_test.dart
  00:00 +0: after close addListener does not retain listener and does not notify
  00:00 +0 -1: after close addListener does not retain listener and does not notify [E]
    Bad state: Cannot change state after closing has finished.
    package:solo/src/solo_base.dart 547:7  SoloBase.externalSetState
    test/support/test_solo.dart 23:51      TestSolo.externalSetState
    test/listeners_base_test.dart 259:12   main.<fn>
  
  00:00 +0 -1: Some tests failed.
  ```

  Команда в `packages/flutter_solo`:
  ```bash
  flutter test --reporter=json 2>/dev/null | python3 -c "
  import sys, json
  tests = {}
  for line in sys.stdin:
      if not line.strip(): continue
      try:
          obj = json.loads(line)
          if obj.get('type') == 'testStart': tests[obj['test']['id']] = obj['test']['name']
          elif obj.get('type') == 'testDone' and (obj.get('result') in ['error', 'failure']):
              print('FAILED: ' + tests.get(obj['testID'], 'unknown'))
      except Exception: pass
  "
  ```
  Вывод:
  ```text
  FAILED: close removes every listener
  FAILED: a listener added after close hears nothing and is not retained
  FAILED: a microtask scheduled from observer.onClose does not notify listeners
  FAILED: a selection of a closed controller answers from the state
  FAILED: externalSetState after close rebuilds nothing
  FAILED: connecting an already closed controller shows its state and does not update further
  FAILED: the builder is handed the cached state, not a fresh read
  ```
- **Что предлагаешь:**
  Внести все 7 пропущенных тестов в раздел спеки «Что становится неправдой» и «Тесты»:
  1. [`listeners_base_test.dart`](file:///Users/user/development/my/solo/packages/solo/test/listeners_base_test.dart#L248): переписать — вместо вызова `externalSetState` проверять `expect(() => solo.externalSetState(...), throwsStateError)`.
  2. [`solo_listenable_test.dart:199`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L199) (`close removes every listener`): переписать — проверять сброс слушателей без мутации состояния после закрытия (или ловить `StateError`).
  3. [`solo_listenable_test.dart:221`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L221) (`a listener added after close hears nothing and is not retained`): убрать вызов `counter.set(7)` и assertion `expect(counter.value, 7)`.
  4. [`solo_listenable_test.dart:246`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_listenable_test.dart#L246) (`a microtask scheduled from observer.onClose does not notify listeners`): микротаска попадает за черту и падает; переписать тест на `expect(() => counter.set(9), throwsStateError)`.
  5. [`solo_selection_test.dart:405`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_selection_test.dart#L405) (`a selection of a closed controller answers from the state`): удалить вызов `controller.set(...)` после закрытия и проверять чтение сохранённого состояния.
  6. [`solo_builder_test.dart:184`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L184) (`externalSetState after close rebuilds nothing`): заменить мутацию на проверку `throwsStateError`.
  7. [`solo_builder_test.dart:212`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L212) (`connecting an already closed controller...`): убрать строку `controller.set(...)` после `await controller.close()`.

**Вердикт:** принято. Радиус я оценил по памяти и промахнулся в восемь раз.
Второй ревьюер этого круга назвал те же восемь имён, разобрав журналы
прогона, — совпадение полное. В план идут все восемь, но снимается из них
один: остальные семь проверяют самостоятельные обещания (сброс слушателей,
подключение закрытого контроллера, чтение выборки от закрытого источника),
и их надо переписать на ожидание `StateError` и неизменного состояния,
а не выбрасывать.

---

### Находка 2. Дартдоки `SoloSelection`, `SoloBuilder` и комментарий в `CameraController` пропущены в списке документов, становящихся неправдой

- **Что не так:** Спека перечислила дартдок `externalSetState` и две секции `doc/state.md`, но упустила дартдок [`SoloSelection`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L44), дартдок [`SoloBuilder`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_builder.dart#L20) и комментарий в [`CameraController.dispose`](file:///Users/user/development/my/solo/packages/solo/example/lib/src/camera_controller.dart#L188), которые прямо обещают, что закрытие не блокирует `externalSetState`.
- **Где:**
  - [`packages/flutter_solo/lib/src/solo_selection.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L44-L46), дартдок `SoloSelection`:
    ```dart
    /// a closed [SoloListenable] notifies nobody, while [value] goes on
    /// answering, because it reads the source and `externalSetState` is not
    /// blocked by closing either.
    ```
  - [`packages/flutter_solo/lib/src/solo_builder.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_builder.dart#L20-L23), дартдок `SoloBuilder`:
    ```dart
    /// The [builder] receives this cached state rather than reading [SoloBase.currentState] freshly on each frame.
    ```
  - [`packages/solo/example/lib/src/camera_controller.dart`](file:///Users/user/development/my/solo/packages/solo/example/lib/src/camera_controller.dart#L188-L190), комментарий в методе `dispose`:
    ```dart
    // The source of external states goes first: `close()` does not block
    // `externalSetState`, and a `Broken` arriving after the camera is gone
    // would set a state nobody is listening for any more.
    ```
- **Доказательство:**
  Команда:
  ```bash
  python3 -c "
  with open('packages/flutter_solo/lib/src/solo_selection.dart') as f:
      lines = f.readlines()
  for i in range(41, 47):
      print(f'{i+1}: {lines[i].strip()}')
  "
  ```
  Вывод:
  ```text
  42: /// Nothing has to be disposed of — the last listener to go takes the
  43: /// subscription with it — and a selection outlives its source harmlessly:
  44: /// a closed [SoloListenable] notifies nobody, while [value] goes on
  45: /// answering, because it reads the source and `externalSetState` is not
  46: /// blocked by closing either.
  47: ///
  ```
- **Что предлагаешь:**
  Включить в раздел «Что становится неправдой»:
  1. [`SoloSelection`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L44): удалить фразу `and externalSetState is not blocked by closing either`.
  2. [`SoloBuilder`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_builder.dart#L20): актуализировать описание жизненного цикла билдера в зависимости от решения плана по снятию/сохранению кеша.
  3. [`CameraController.dispose`](file:///Users/user/development/my/solo/packages/solo/example/lib/src/camera_controller.dart#L188): обновить комментарий — `externalSetState` после закрытия теперь бросает `StateError`, поэтому отписка источника обязана происходить до черты.

**Вердикт:** принято. К трём названным местам второй ревьюер добавил
четвёртое и пятое: запись `## Unreleased` в `packages/flutter_solo/CHANGELOG.md`
про микротаску из `observer.onClose` — теперь она получает ошибку записи,
а не просто теряет доставку, — и раздел «Закрытие»
в `2026-09-13[2]-solo-listeners-design.md`, который надо пометить
пересмотренным. Все пять в списке второй редакции.

---

### Находка 3. Тезис спеки «наследнику для защиты хватает `isClosed`» ошибочен: `isClosed` ломает внешний источник при `SoloCloseMode.drain` и при неотменяемых задачах

- **Что не так:** Спека отказывается от публичного признака окончания закрытия, утверждая: *«Наследнику для защиты хватает `isClosed`: он строже нужного (истина с вызова), и это безопасная сторона»*. Это не так: `isClosed` становится `true` в первой строке `close()`. Если наследник защищает `externalSetState` проверкой `if (!isClosed)`, он **полностью глушит внешние события во время `drain`**, хотя задачи очереди ещё работают и нуждаются во внешних фактах, а также во время ожидания завершения неотменяемой задачи (`cancellable: false`).
- **Где:**
  - [`packages/solo/lib/src/solo_base.dart`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L122), геттер `isClosed`
  - [`docs/records/2026-09-13[10]-closed-state-freeze-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B10%5D-closed-state-freeze-design.md#L152-L154), раздел «Чего спека не делает»
- **Доказательство:**
  Зонд [`test/probe_guard_test.dart`](file:///Users/user/development/my/solo/packages/solo/test/probe_guard_test.dart):
  ```dart
  class GuardedSolo extends Solo<int> {
    GuardedSolo() : super(0);
    void onExternal(int v) {
      if (!isClosed) externalSetState(v);
    }
  }
  // Запуск solo.close(mode: SoloCloseMode.drain)
  // isClosed истинен сразу, задачи в очереди ещё выполняются.
  // Вызов onExternal(10) отбрасывается условием !isClosed.
  ```
  Команда:
  ```bash
  cat << 'EOF' > test/probe_guard_test.dart
  import 'dart:async';
  import 'package:solo/solo.dart';
  import 'package:test/test.dart';

  class GuardedSolo extends Solo<int> {
    GuardedSolo() : super(0);
    void onExternal(int v) {
      if (!isClosed) externalSetState(v);
    }
  }

  void main() {
    test('isClosed guard blocks external updates during drain', () async {
      final solo = GuardedSolo();
      final executed = Completer<void>();
      solo.run<int, void>((ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        executed.complete();
      });
      final drainFuture = solo.close(mode: SoloCloseMode.drain);
      expect(solo.isClosed, isTrue);
      expect(solo.isDraining, isTrue);

      solo.onExternal(10);
      expect(solo.currentState, 0, reason: 'событие потеряно из-за !isClosed');
      await executed.future;
      await drainFuture;
    });
  }
  EOF
  dart test test/probe_guard_test.dart
  rm test/probe_guard_test.dart
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_guard_test.dart
  00:00 +0: isClosed guard blocks external updates during drain
  00:00 +1: All tests passed!
  ```
- **Что предлагаешь:**
  Пересмотреть раздел «Чего спека не делает». Либо:
  1. Добавить публичный (или `@protected`) геттер `bool get isCloseFinished` (или `bool get canSetExternalState` / `bool get isTerminated`), возвращающий `!identical(_listeners, _closedListeners)`.
  2. Либо документировать, что для дренируемых контроллеров guard должен быть `if (!isClosed || isDraining)`, и при этом в `_finishClose` флаг `_draining = false` должен сбрасываться синхронно с чертой (сейчас он сбрасывается до `onClose`).

**Вердикт:** принято, и это меняет спеку, а не дополняет её. Я написал,
что `isClosed` «строже нужного, и это безопасная сторона»; безопасной она
не является — под `drain` такая защита глушит внешние факты ровно тогда,
когда очередь их ждёт. Второй ревьюер пришёл к тому же независимо. Вторая
редакция заводит публичный признак окончания работы движка, от которого
первая отказалась.

---

### Находка 4. Документированный рецепт «гасить внешний источник до `super.close()`» несовместим с `SoloCloseMode.drain`

- **Что не так:** Спека опирается на то, что `Camera` из [`doc/state.md`](file:///Users/user/development/my/solo/packages/solo/doc/state.md#L191) гасит источник первым (`await _link.cancel(); await super.close();`). Но если закрытие вызвано с `SoloCloseMode.drain`, этот порядок глушит подписку **до** того, как очередь начнёт дренироваться. Если же гасить после `await super.close(mode: drain)`, то завершение `super.close` синхронно совпадает с чертой, и любые поздние события внешнего источника выбросят `StateError`.
- **Где:**
  - [`packages/solo/doc/state.md`](file:///Users/user/development/my/solo/packages/solo/doc/state.md#L191-L195)
  - [`docs/records/2026-09-13[10]-closed-state-freeze-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B10%5D-closed-state-freeze-design.md#L74-L77)
- **Доказательство:**
  В коде `Camera`:
  ```dart
  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) async {
    await _link.cancel();
    await super.close(mode: mode);
  }
  ```
  При `close(mode: SoloCloseMode.drain)` `_link.cancel()` отрабатывает до передачи управления в `super.close(mode: mode)`. Очередь контроллера остаётся без обновлений внешнего источника на всё время дренажа. Если поменять порядок местами (`await super.close(); await _link.cancel();`), то в момент выхода из `await super.close()` контроллер уже закрыт (`_finishClose` завершился). Любое асинхронное событие, успевающее проскочить в стрим до завершения `_link.cancel()`, вызывает `externalSetState` и приводит к `StateError`.
- **Что предлагаешь:**
  В разделе спеки «Что делает запись после черты» (довод 1) и в [`doc/state.md`](file:///Users/user/development/my/solo/packages/solo/doc/state.md) эксплицитно разобрать разницу между `cancel` и `drain`: при `drain` отписка от внешнего источника либо должна инициироваться после завершения очереди, либо обработчик источника должен безопасно игнорировать события после черты.

---

## Что в спеке верно и проверено прогонами

### 1. Список писателей состояния полон (Вопрос 1)
- **Утверждение спеки:** `_setState` вызывается ровно из трёх мест (`externalSetState`, `SoloContext.emit`, `_SoloJob._correctState`), и после завершения закрытия ни один писатель, кроме `externalSetState`, сработать не может.
- **Проверка чтением и grep:**
  Поиск по кодовой базе подтвердил ровно 3 места вызова [`_setState`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L731):
  1. [`packages/solo/lib/src/solo_base.dart:547`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L547) (`externalSetState`)
  2. [`packages/solo/lib/src/job_context.dart:132`](file:///Users/user/development/my/solo/packages/solo/lib/src/job_context.dart#L132) (`SoloContext.emit`)
  3. [`packages/solo/lib/src/job.dart:190`](file:///Users/user/development/my/solo/packages/solo/lib/src/job.dart#L190) (`_SoloJob._correctState` для `onError`/`onCancel`)
- **Проверка зондом механизмов асинхронности:**
  - `cancellable: false`: закрытие ожидает завершения задачи через `current._whenDone`, и `_finishClose` выполняется строго после её окончания. После окончания задачи вызов `ctx.emit` блокируется `throwIfFinished('emit')`.
  - `each` и дочерние задачи: родительская задача дожидается всех детей в [`JobBase._execute`](file:///Users/user/development/my/solo/packages/async_job/lib/src/job_base.dart#L1043), поэтому `_finishClose` не наступает, пока живы дети.
  - Обработчики исхода `_correctState` (`onError`/`onCancel`): вызываются синхронно внутри [`JobBase.finish() -> finished()`](file:///Users/user/development/my/solo/packages/async_job/lib/src/job_base.dart#L748) до вызова `_done.complete()`. А `_finishClose` привязан к `current._whenDone.then(...)` (микротаска после завершения `_done`). То есть `_correctState` **всегда выполняется до `_finishClose`**.
  - Аккумуляция и отложенные окна: таймеры отменяются в `_stopWork`, а при `drain` отрабатывают до наступления `_finishClose`.
- **Доказательство:**
  Команда:
  ```bash
  cat << 'EOF' > test/probe_writers_test.dart
  import 'dart:async';
  import 'package:solo/solo.dart';
  import 'package:test/test.dart';

  class S {
    final int v;
    const S(this.v);
  }

  void main() {
    test('cancellable: false writes before _finishClose, but never after', () async {
      final solo = Solo(const S(0));
      SoloContext<S, S>? leakedCtx;
      final started = Completer<void>();
      final canFinish = Completer<void>();

      final job = solo.run<S, void>(
        cancellable: false,
        (ctx) async {
          leakedCtx = ctx;
          started.complete();
          ctx.emit(const S(1));
          await canFinish.future;
          ctx.emit(const S(2));
        },
      );

      await started.future;
      var closeFinished = false;
      final closeFuture = solo.close().then((_) => closeFinished = true);

      expect(solo.isClosed, isTrue);
      expect(closeFinished, isFalse);
      expect(solo.currentState.v, 1);

      canFinish.complete();
      await job.done;
      await closeFuture;

      expect(closeFinished, isTrue);
      expect(solo.currentState.v, 2);
      expect(() => leakedCtx!.emit(const S(3)), throwsStateError);
    });

    test('state handlers onError/onCancel run before _finishClose and listeners hear it', () async {
      final solo = Solo(const S(0));
      final log = <String>[];
      solo.addListener(() => log.add('listener:${solo.currentState.v}'));
      final started = Completer<void>();

      solo.run<S, void>(
        cancellable: false,
        onCancel: (s, c) {
          log.add('onCancel');
          return const S(99);
        },
        (ctx) async {
          started.complete();
          throw Cancelled();
        },
      );

      await started.future;
      await solo.close();
      expect(log, ['onCancel', 'listener:99']);
      expect(solo.currentState.v, 99);
    });
  }
  EOF
  dart test test/probe_writers_test.dart
  rm test/probe_writers_test.dart
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_writers_test.dart
  00:00 +0: cancellable: false writes before _finishClose, but never after
  00:00 +1: state handlers onError/onCancel run before _finishClose and listeners hear it
  00:00 +2: All tests passed!
  ```

---

### 2. Точка отсечения: «закрытие закончилось» строго совпадает с `identical(_listeners, _closedListeners)` (Вопрос 2)
- **Утверждение спеки:** `_listeners` принимает сигнальное значение `_closedListeners` в `_finishClose` сразу за вызовом `observer.onClose`, и проверка `identical(_listeners, _closedListeners)` точно идентифицирует завершение закрытия без заведения отдельного поля.
- **Проверка:**
  Во всех маршрутах:
  1. `close()` при пустой очереди: `_stopWork` ставит микротаску `scheduleMicrotask(() => _finishClose(completer))`. До микротаски `_listeners` ещё живой; после — `_closedListeners`.
  2. Повторный `close()`: возвращает тот же `closing.future`, `_finishClose` повторно не вызывается, `_listeners` остаётся `_closedListeners`.
  3. `drain`, остановленный обычным `close()`: защищён guard-проверкой `if (completer.isCompleted) return;`. Ровно один маршрут выполняет присваивание `_listeners = _closedListeners;` и завершает completer.
  4. Закрытие из тела задачи: `_finishClose` ждёт завершения тела через `current._whenDone`. Внутри тела подмена не происходит; после завершения тела подмена происходит синхронно с `completer.complete()`.
  5. Внутри `observer?.onClose(this)`: подмена ещё не произошла, `externalSetState` и подписка работают и доходят до слушателей, сбрасываясь сразу следом.
- **Доказательство:**
  Команда:
  ```bash
  cat << 'EOF' > test/probe_path4_detail_test.dart
  import 'dart:async';
  import 'package:solo/solo.dart';
  import 'package:test/test.dart';

  class S {
    final int v;
    const S(this.v);
  }

  void main() {
    test('path 4 detail', () async {
      final solo = Solo(const S(0));
      final fn = () {};

      solo.run<S, void>((ctx) async {
        solo.close();
        solo.addListener(fn);
        print('inside body: hasListeners=${solo.hasListeners}');
      });

      await pumpEventQueue();
      print('after pump: hasListeners=${solo.hasListeners}');
      final fn2 = () {};
      solo.addListener(fn2);
      print('after adding post-close: hasListeners=${solo.hasListeners}');
    });
  }
  EOF
  dart test test/probe_path4_detail_test.dart
  rm test/probe_path4_detail_test.dart
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_path4_detail_test.dart
  00:00 +0: path 4 detail
  inside body: hasListeners=true
  after pump: hasListeners=false
  after adding post-close: hasListeners=false
  00:00 +1: All tests passed!
  ```

---

### 3. Поведение хуков сегодня подтверждено зондом (Вопрос 6)
- **Утверждение спеки:** Сегодня `externalSetState` после закрытия вызывает `onChange` и `observer.onChange`, а после предлагаемой правки перестанет, так как бросок `StateError` прервёт выполнение до входа в `_setState`.
- **Проверка зондом:** Зонд подтвердил, что на текущей кодовой базе `externalSetState` после `await solo.close()` успешно меняет `currentState` и синхронно доставляет переходы и в `observer.onChange`, и в `instance.onChange`.
- **Доказательство:**
  Команда:
  ```bash
  cat << 'EOF' > test/probe_hooks_test.dart
  import 'dart:async';
  import 'package:solo/solo.dart';
  import 'package:test/test.dart';

  class S {
    final int v;
    const S(this.v);
    @override
    String toString() => 'S($v)';
  }

  class HookJournal extends SoloObserver {
    final List<String> events;
    HookJournal(this.events);
    @override
    void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) {
      events.add('observer.onChange: ${transition.previous} -> ${transition.current}');
    }
  }

  class HookSolo extends Solo<S> {
    final List<String> events;
    HookSolo(this.events) : super(const S(0));
    @override
    void onChange(SoloTransition<S> transition) {
      events.add('instance.onChange: ${transition.previous} -> ${transition.current}');
    }
    void externalWrite(int v) => externalSetState(S(v));
  }

  void main() {
    test('today externalSetState after close calls onChange and observer.onChange', () async {
      final events = <String>[];
      SoloBase.observer = HookJournal(events);
      addTearDown(() => SoloBase.observer = null);

      final solo = HookSolo(events);
      await solo.close();
      events.clear();

      expect(solo.isClosed, isTrue);
      solo.externalWrite(42);

      expect(solo.currentState.v, 42);
      expect(events, [
        'observer.onChange: S(0) -> S(42)',
        'instance.onChange: S(0) -> S(42)',
      ]);
    });
  }
  EOF
  dart test test/probe_hooks_test.dart
  rm test/probe_hooks_test.dart
  ```
  Вывод:
  ```text
  00:00 +0: loading test/probe_hooks_test.dart
  00:00 +0: today externalSetState after close calls onChange and observer.onChange
  00:00 +1: All tests passed!
  ```

---

### 4. В ядре `solo` действительно нет ни одного `assert` (Довод 3 спеки)
- **Утверждение спеки:** `solo` не пользуется отладочными проверками `assert`, поэтому введение `StateError` строго следует соглашениям ядра.
- **Доказательство:**
  Команда:
  ```bash
  python3 -c "
  import os, re
  found = []
  for root, dirs, files in os.walk('packages/solo/lib'):
      for f in files:
          if f.endswith('.dart'):
              p = os.path.join(root, f)
              with open(p) as fl:
                  for i, line in enumerate(fl):
                      if re.search(r'\bassert\s*\(', line):
                          found.append(f'{p}:{i+1}: {line.strip()}')
  print('Total asserts found:', len(found))
  "
  ```
  Вывод:
  ```text
  Total asserts found: 0
  ```

---

### 5. Открытый вопрос спеки про `addListener` (Вопрос 8)
- **Утверждение:** Решение спеки оставить `addListener` молчаливым no-op после закрытия — обоснованное и правильное. Менять его поведение на `StateError` не следует.
- **Обоснование и доказательство:**
  Хотя историческое обоснование в [`2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md#L188) звучало как *«исключения подписка после закрытия не бросает... здесь живёт: externalSetState закрытием не запрещён»*, удержание тишины в `addListener` критично для виджетов Flutter:
  1. [`SoloBuilder`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_builder.dart#L66) в `initState` безусловно выполняет `widget.solo.addListener(_handleChange)`.
  2. Тест [`solo_builder_test.dart:212`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_builder_test.dart#L212) (`connecting an already closed controller shows its state and does not update further`) специфицирует, что подключение уже закрытого контроллера к дереву легитимно: виджет показывает последнее состояние и не перестраивается.
  3. Если `addListener` начнёт бросать `StateError`, то любой `SoloBuilder` или `SoloSelection`, смонтированный поверх закрытого контроллера, упадёт при инициализации.
  4. Семантическая асимметрия обоснована контрактом: подписка `addListener` говорит *«уведоми меня, если состояние изменится»* — так как оно никогда не изменится, 0 вызовов абсолютно корректны. Запись `externalSetState` говорит *«измени состояние прямо сейчас»* — отказ молча проглотить эту команду через `StateError` предотвращает скрытый дефект.
{"analyze_result":"Clean: dart analyze and flutter analyze passed.","done":true,"files_changed":[],"mutation_kills_test":true,"not_done":"","notes":"Ревью спецификации docs/records/2026-09-13[10]-closed-state-freeze-design.md завершено с прогонами всех проверочных зондов. Выявлено 8 падающих тестов (спека назвала 1), недокументированные расхождения в дартдоках SoloSelection, SoloBuilder и комментариях примера, а также концептуальная проблема с защитой наследника через isClosed во время drain. Временные зонды удалены, дерево чистое.","tests_command":"dart test (packages/solo), dart test (packages/solo/example), flutter test (packages/flutter_solo)","tests_result":"Базовые наборы зелёные: 516 тестов в solo, 9 в solo/example, 81 в flutter_solo. При мутации (броске StateError после закрытия) краснеют 8 тестов (1 в solo, 7 в flutter_solo).","toolAction":"Finishing task","toolSummary":"Complete spec review"}

**Вердикт:** принято. Эта находка — вторая половина третьей: под `drain`
сегодня нет способа написать внешний источник правильно, в каком бы порядке
его ни гасили. Именно она снимает мой довод «гонки тут нет», которым
отвергался молчаливый вариант. Гонка есть; закрывается она признаком
из вердикта по находке 3, а не молчанием, — но признак теперь обязателен,
а не «не нужен».

