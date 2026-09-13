> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана во вторую редакцию.
> **Что это:** первый круг независимого ревью спеки
> `2026-09-13[10]-closed-state-freeze-design.md`. Прогон `codex exec`,
> `gpt-6-astra:xhigh`, 774 с, зонды на временной копии пакетов и полные
> наборы под вставленным запретом. Дерево не менял.
> **Связанные записи:** `2026-09-13[11]-closed-state-freeze-review.md`
> (второй ревьюер этого круга, прогон шёл одновременно); спека
> `2026-09-13[10]-closed-state-freeze-design.md`.

Нашёл четыре пробела в [docs/records/2026-09-13[10]-closed-state-freeze-design.md](/private/tmp/fz8-rev/clone/docs/records/2026-09-13[10]-closed-state-freeze-design.md).

Будущий запрет проверял на временной копии пакетов: перед присваиванием в `_setState` добавил `StateError` при `identical(_listeners, _closedListeners)`. Исходное дерево не менял. Ниже — дословные значимые строки вывода; временные файлы уже удалены.

## Находки

**1. [P2] Рекомендованная защита через `isClosed` может повесить `drain`.**

**Где:** спека, «Чего спека не делает», около строки 153; [solo_base.dart — `isClosed`, `_reevaluate`](/private/tmp/fz8-rev/clone/packages/solo/lib/src/solo_base.dart:119).

Внешний источник может быть нужен продолжающейся задаче: например, отключение устройства меняет состояние и нарушает `keepWhile`, освобождая ожидание через `ctx.wait`. После начала `drain` задача ещё работает. Если источник выполняет рекомендованное `if (!isClosed) externalSetState(...)`, отключение теряется, задача и закрытие остаются ждать.

Зонд запускал задачу с `keepWhile: (s) => s == 0`, ожидающую незавершающийся `Future` через `ctx.wait`. После начала `drain` внешний источник присылал состояние `1`.

**Доказательство:**

```sh
rtk proxy dart --packages=packages/solo/.dart_tool/package_config.json /tmp/fz8_state_probe.dart
```

```text
SOURCE guarded=false: isClosed=true drainDone=true state=1 pending=null
SOURCE guarded=true: isClosed=true drainDone=false state=0 pending=body
```

На копии с будущим запретом результат тот же: необходимая запись находится **до** точки заморозки.

**Что предлагаю:** убрать утверждение, что `isClosed` — универсально безопасная защита. Для источников, необходимых продолжающейся работе, предусмотреть защищённый геттер заморозки на том же sentinel. Добавить приведённый сценарий в тесты. Остановка источника до закрытия годится, когда оставшаяся работа от него уже не зависит.

**Вердикт:** принято. То же нашёл второй ревьюер этого круга, независимо
и другим зондом. Мой довод «`isClosed` строже нужного, и это безопасная
сторона» неверен: под `drain` такая защита глушит внешние факты ровно тогда,
когда очередь их ждёт. Вторая редакция заводит публичный признак окончания
работы движка.

---

**2. [P2] Sentinel обозначает конец работы движка, но не завершение `Solo.close()`.**

**Где:** спека, «Где черта», около строки 45; [solo_base.dart — `_finishClose`](/private/tmp/fz8-rev/clone/packages/solo/lib/src/solo_base.dart:636); [solo.dart — `Solo.close`](/private/tmp/fz8-rev/clone/packages/solo/lib/src/solo.dart:24).

`Solo.close()` после базового закрытия ещё закрывает стрим. При приостановленной подписке его `Future` остаётся незавершённым, хотя `_listeners` уже заменён. Поэтому новый запрет начинает действовать раньше завершения публичного `close()` — потенциально на неограниченное время раньше.

Зонд приостанавливал подписку, вызывал `close()`, прокручивал микротаски, пробовал зарегистрировать слушателя и записать состояние, затем возобновлял подписку.

**Доказательство на копии с запретом:**

```sh
rtk proxy dart --packages=/private/tmp/fz8-freeze-probe/packages/solo/.dart_tool/package_config.json /tmp/fz8_state_probe.dart
```

```text
PAUSED_STREAM: closeDone=false streamDone=false retained=false events=[hook:7, listener:7, onClose-microtask:retained=false]
GAP_WRITE: closeDone=false error=StateError state=7
RESUMED_STREAM: closeDone=true streamDone=true
```

В исходном дереве та же запись проходит:

```text
GAP_WRITE: closeDone=false error=null state=8
```

**Что предлагаю:** сохранить выбранную точку, но назвать её точно: «завершение работы движка в `SoloBase`, перед завершением базового `Future`; закрытие доставки наследника может продолжаться». Добавить тест с приостановленной подпиской. Равенство sentinel и завершения любого публичного `close()` обещать нельзя.

**Вердикт:** принято, и находка своя — второй ревьюер до неё не дошёл.
Формулировка «черта — конец закрытия» неточна: у `Solo` за базовым закрытием
идёт закрытие стрима, и при приостановленной подписке публичный `Future`
не завершается сколь угодно долго, а запрет уже действует. Во второй редакции
черта названа концом работы движка в `SoloBase`, и тест с приостановленной
подпиской добавлен в список.

---

**3. [P2] Покраснеет восемь тестов, а не один; семь сценариев миграции пропущены.**

**Где:** спека, «Что становится неправдой» и «Тесты»; символы тестов перечислены ниже.

На временной копии выполнил полные наборы:

```sh
# /private/tmp/fz8-freeze-probe/packages/solo
rtk proxy sh -c 'dart test --reporter expanded > /tmp/fz8-freeze-solo.log 2>&1; tail -n 15 /tmp/fz8-freeze-solo.log'

# /private/tmp/fz8-freeze-probe/packages/flutter_solo
rtk proxy sh -c 'flutter test --reporter expanded > /tmp/fz8-freeze-flutter.log 2>&1; tail -n 22 /tmp/fz8-freeze-flutter.log'
```

```text
00:00 +515 -1: Some tests failed.
```

```text
00:00 +80 -7: Some tests failed.
```

**Доказательство полного списка — выполненный разбор журналов:**

```sh
rtk proxy python3 - <<'PY'
from pathlib import Path
import re
for kind in ('solo','flutter'):
 lines=Path('/tmp/fz8-freeze-'+kind+'.log').read_text().splitlines()
 failed=sorted(set(re.sub(r'^.*?test/', 'test/', line).removesuffix(' [E]') for line in lines if re.match(r'^\d\d:\d\d .*\[E\]$', line)))
 print(f'{kind}: {len(failed)} failing tests')
 print('\n'.join(failed))
PY
```

```text
solo: 1 failing tests
test/listeners_base_test.dart: after close addListener does not retain listener and does not notify
flutter: 7 failing tests
test/solo_builder_test.dart: connecting an already closed controller shows its state and does not update further
test/solo_builder_test.dart: externalSetState after close rebuilds nothing
test/solo_builder_test.dart: the builder is handed the cached state, not a fresh read
test/solo_listenable_test.dart: a listener added after close hears nothing and is not retained
test/solo_listenable_test.dart: a microtask scheduled from observer.onClose does not notify listeners
test/solo_listenable_test.dart: close removes every listener
test/solo_selection_test.dart: a selection of a closed controller answers from the state
```

Это восемь тестовых сценариев записи за предлагаемой чертой: семь после `await close()`, один — из микротаски `observer.onClose`. Сегодня они законны по действующему дартдоку `externalSetState`.

**Что предлагаю:** включить все восемь в план. Сохранить проверки освобождения слушателей, подключения закрытого контроллера и чтения выборки; заменить поздние записи ожиданием `StateError` и неизменного значения. Отдельно закрепить ошибку микротаски `onClose`. Снимать остальные тесты вместе с тестом кеша нельзя: они проверяют самостоятельные контракты.

**Вердикт:** принято. Список из восьми имён совпал с тем, что нашёл второй
ревьюер, до последнего. Предложение взято целиком: снимается один тест,
остальные семь переписываются на ожидание `StateError` и неизменного
состояния, потому что проверяют они самостоятельные обещания, а не кеш.

---

**4. [P3] Перечень устаревающей документации пропускает `SoloSelection` и комментарий примера камеры.**

**Где:** [solo_selection.dart — дартдок `SoloSelection`](/private/tmp/fz8-rev/clone/packages/flutter_solo/lib/src/solo_selection.dart:42); [camera_controller.dart — `CameraController.dispose`](/private/tmp/fz8-rev/clone/packages/solo/example/lib/src/camera_controller.dart:188).

Оба места прямо опираются на отсутствие запрета записи после закрытия.

**Доказательство:**

```sh
rtk proxy rg -n -A2 'externalSetState.*is not|close\(\).*does not block' packages/flutter_solo/lib/src/solo_selection.dart packages/solo/example/lib/src/camera_controller.dart
```

```text
packages/solo/example/lib/src/camera_controller.dart:188:    // The source of external states goes first: `close()` does not block
packages/solo/example/lib/src/camera_controller.dart-189-    // `externalSetState`, and a `Broken` arriving after the camera is gone
packages/solo/example/lib/src/camera_controller.dart-190-    // would set a state nobody is listening for any more.
--
packages/flutter_solo/lib/src/solo_selection.dart:45:/// answering, because it reads the source and `externalSetState` is not
packages/flutter_solo/lib/src/solo_selection.dart-46-/// blocked by closing either.
packages/flutter_solo/lib/src/solo_selection.dart-47-///
```

Обещание `SoloSelection` также подтверждено поведением: одноимённый тест из находки 3 проходит сейчас и падает с запретом.

**Что предлагаю:** добавить оба места в перечень правок. Для выборки написать, что она продолжает читать окончательное состояние; для камеры — что источник останавливают до заморозки, иначе поздняя запись бросит.

Также уточнить текущую запись `Unreleased` в [flutter_solo/CHANGELOG.md](/private/tmp/fz8-rev/clone/packages/flutter_solo/CHANGELOG.md:56): микротаска `onClose` теперь получает ошибку записи, а не просто теряет доставку. Старое обоснование в `docs/records/2026-09-13[2]-solo-listeners-design.md`, раздел «Закрытие», отметить пересмотренным; исторические трассы переписывать не нужно. В остальных актуальных README и переводах дополнительных прямых обещаний разрешённой записи после завершённого закрытия не нашёл.

## Что в спеке верно и проверено

**Список непосредственных писателей полный.** Помимо инициализации конструктора, присваивание одно; вызывающих `_setState` — три:

```sh
rtk proxy rg -n '_setState\(|_state =' packages/solo/lib/src
```

```text
packages/solo/lib/src/solo_base.dart:89:  SoloBase(S initialState) : _state = initialState {
packages/solo/lib/src/solo_base.dart:547:    _setState(state, emitter: null, stackTrace: StackTrace.current);
packages/solo/lib/src/solo_base.dart:731:  void _setState(
packages/solo/lib/src/solo_base.dart:737:    _state = next;
packages/solo/lib/src/job.dart:190:    _solo._setState(next, emitter: this, stackTrace: StackTrace.current);
packages/solo/lib/src/job_context.dart:132:    _solo._setState(next, emitter: _job, stackTrace: StackTrace.current);
```

Добиться поздней записи через другой штатный путь не удалось. Зонд сохранял контексты, дожидался закрытия и повторно вызывал `emit`; отдельно проверял отложенные действия:

```sh
rtk proxy dart --packages=packages/solo/.dart_tool/package_config.json /tmp/fz8_state_probe.dart
```

```text
MATRIX onCancel-after-cleanup: state=2 writes=[2] heard=[2] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX onError-uncancellable: state=3 writes=[3] heard=[3] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX child-uncancellable: state=4 writes=[4] heard=[4] lateEmit=StateError(2/2) onClose=1 sameFuture=true retained=false
MATRIX each-cancel: state=0 writes=[] heard=[] lateEmit=StateError(2/2) onClose=1 sameFuture=true retained=false
MATRIX each-drain: state=6 writes=[5, 6] heard=[5, 6] lateEmit=StateError(3/3) onClose=1 sameFuture=true retained=false
MATRIX collect-debounce-cancel: state=0 writes=[] heard=[] lateEmit=StateError(0/0) onClose=1 sameFuture=true retained=false
MATRIX collect-debounce-drain: state=7 writes=[7] heard=[7] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX accumulate-throttle-cancel: state=3 writes=[3] heard=[3] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX accumulate-throttle-drain: state=4 writes=[3, 4] heard=[3, 4] lateEmit=StateError(2/2) onClose=1 sameFuture=true retained=false
ESCAPED: closeDone=true state=0 late=[unattended:StateError, abandoned:StateError, chain:alive]
```

Продолжение цепочки действительно переживает контроллер, но собственного `SoloContext` для записи не получает. Утёкшие контексты из `unattended` и брошенного ожидания запись отвергают.

**Для завершения движка sentinel подходит.** В проверенных маршрутах не нашёл завершения базового закрытия без сброса или сброса до окончания принадлежащей движку работы. Тот же зонд:

```text
MATRIX idle-cancel: state=0 writes=[] heard=[] lateEmit=StateError(0/0) onClose=1 sameFuture=true retained=false
MATRIX idle-drain: state=0 writes=[] heard=[] lateEmit=StateError(0/0) onClose=1 sameFuture=true retained=false
MATRIX uncancellable: state=1 writes=[1] heard=[1] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX drain-stopped-running: state=8 writes=[8] heard=[8] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
MATRIX drain-stopped-window: state=0 writes=[] heard=[] lateEmit=StateError(0/0) onClose=1 sameFuture=true retained=false
MATRIX close-from-body: state=12 writes=[12] heard=[12] lateEmit=StateError(1/1) onClose=1 sameFuture=true retained=false
SELF_AWAIT: closeDone=false pending=body
```

Повторные вызовы возвращают один `Future`, `onClose` вызывается один раз. `await close()` внутри текущего тела ждёт само себя, как и документировано. Синхронная запись из `observer.onClose` доставляется до сброса — это также видно по `listener:7` в доказательстве находки 2.

**Хуки после закрытия сегодня действительно вызываются; запрет убирает оба.**

Исходное дерево, команда зонда выше:

```text
POST_CLOSE: error=null state=9 events=[observer:9, hook:9]
```

Копия с запретом:

```sh
rtk proxy dart --packages=/private/tmp/fz8-freeze-probe/packages/solo/.dart_tool/package_config.json /tmp/fz8_state_probe.dart
```

```text
POST_CLOSE: error=StateError state=0 events=[]
```

Поиск `onChange` по Dart-файлам и полный прогон не выявили потребителя, специально использующего **послезакрытийные** хуки для дальнейшей работы. Это ограниченный вывод о данном дереве; документированная совместимость для внешних наследников действительно меняется.

**Рецепт `Camera` из `doc/state.md` новый запрет выдерживает.** Класс извлечён из документа дословно; зонд добавлял события во время асинхронной отмены подписки и после закрытия:

```sh
rtk proxy dart --packages=/private/tmp/fz8-freeze-probe/packages/solo/.dart_tool/package_config.json /tmp/fz8_camera_probe.dart
```

```text
CAMERA_DOC: closeDone=true state=Ready sourceHasListener=false
```

В примерах и документах не нашёл предписанного порядка «сначала дождаться закрытия контроллера, потом записать состояние». Восемь найденных намеренных сценариев находятся в тестах.

**`addListener` я оставил бы молчаливым.** Замороженный контроллер остаётся полезным источником окончательного значения. Подключение к нему билдера законно и проверяется без единой поздней записи:

```sh
# /private/tmp/fz8-freeze-probe/packages/flutter_solo
rtk proxy flutter test --reporter expanded test/fz8_contract_probe_test.dart
```

```text
CLOSED_MOUNT: selection=14 built=[7, 14] addError=null flutterError=null
00:00 +1: All tests passed!
```

Здесь уже действовал запрет записи. Старое обоснование молчания нужно заменить: подписка на окончательное значение безопасна и ничего не удерживает. Необходимости одновременно вводить исключение из `addListener` не вижу.

**Базовые наборы зелёные.** Выполнены `dart analyze` / `dart test --reporter expanded` в `solo` и его примере, `flutter analyze` / `flutter test --reporter expanded` во Flutter-пакете:

```text
solo:
No issues found!
00:00 +516: All tests passed!
example:
No issues found!
00:00 +9: All tests passed!
flutter:
No issues found! (ran in 2.9s)
00:00 +87: All tests passed!
```

В текущем клоне Flutter-тестов **87**, не 81. Проверки переносов, ширины и переводов тоже прошли.

Временная копия, зонды и журналы удалены. Финальный `rtk git status --short` дал пустой вывод.

**Вердикт:** принято. Второй ревьюер назвал те же два места и добавил
третье — дартдок `SoloBuilder`. Обе добавки этой находки тоже приняты: запись
`## Unreleased` в `packages/flutter_solo/CHANGELOG.md` про микротаску
из `observer.onClose` и пометка «пересмотрено» на разделе «Закрытие»
в `2026-09-13[2]-solo-listeners-design.md`. Исторические трассы, как
и предложено, не переписываются.

