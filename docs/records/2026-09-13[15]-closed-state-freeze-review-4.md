> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана в третью редакцию.
> **Что это:** второй круг независимого ревью спеки
> `2026-09-13[10]-closed-state-freeze-design.md`. Прогон `codex exec`,
> `gpt-6-astra:xhigh`, 928 с, зонды и мутации на временной копии пакетов.
> Дерево не менял.
> **Связанные записи:** `2026-09-13[14]-closed-state-freeze-review-3.md`
> (второй ревьюер этого круга, прогон шёл одновременно); первый круг —
> `2026-09-13[11]` и `2026-09-13[12]`; спека
> `2026-09-13[10]-closed-state-freeze-design.md`.

Нашёл **две неблокирующие находки**. Оба блокера первого круга закрыты. Пути, на котором корректно защищённая запись неизбежно получает новый `StateError`, не нашёл.

Запрет моделировал вне клона: геттер `isFinished` читает sentinel, проверка в `_setState` бросает перед присваиванием. Ниже — дословные значимые строки выполненных команд.

## Находки

**1. [P2] Простая замена поздней записи на `throwsStateError` лишает тест сброса слушателей его смысла.**

**Где:** [спека, «Тесты»](/private/tmp/qr4-two/clone/docs/records/2026-09-13[10]-closed-state-freeze-design.md:178); [solo_listenable_test.dart, `close removes every listener`](/private/tmp/qr4-two/clone/packages/flutter_solo/test/solo_listenable_test.dart:199).

Сейчас отсутствие вызова после записи доказывает отключение слушателя. После введения запрета запись вообще не доходит до доставки: слушатель может остаться зарегистрированным, а тест всё равно пройдёт.

**Доказательство:** мутация сохраняла запрет записи отдельным флагом, но оставляла старый список слушателей. Скрипт сначала запускал механически переписанный тест, затем добавлял `expect(counter.hasListeners, isFalse)`.

```sh
rtk proxy python3 /private/tmp/qr4-freeze-review/mutation.py
```

Механическая миграция:

```text
MUTATION naive: exit=0
```

```text
RETAINED=true calls=0
00:00 +1: All tests passed!
```

С прямой проверкой сброса:

```text
MUTATION direct-check: exit=1
```

```text
RETAINED=true calls=0
00:00 +0 -1: close removes every listener [E]
  Expected: false
    Actual: <true>
```

**Предлагаю:** сохранить тест, но потребовать прямую проверку `hasListeners` до и после закрытия. Для теста микротаски `observer.onClose` также проверять сброс **внутри микротаски**, иначе он превращается преимущественно в ещё один тест запрета записи. Утверждение «меняют только способ довести состояние» нужно уточнить.

**Вердикт:** принято, и мутация тут сильнее слов: запрет записи отдельным
флагом при сохранённом списке слушателей — механически переписанный тест
проходит (`RETAINED=true calls=0`, `All tests passed!`), а с прямой проверкой
падает. Значит, фраза спеки «меняют только способ довести состояние» неверна
как общее правило. В третьей редакции у каждого из переписываемых тестов
назван предмет, который он обязан проверять после правки, а у сброса
слушателей — прямая проверка `hasListeners` до и после, и проверка сброса
внутри микротаски `observer.onClose`.

**2. [P3] Перечень документов пропускает оставшиеся обещания о моменте завершения и исторические обоснования поздней записи.**

**Где:** [SoloObserver.onClose](/private/tmp/qr4-two/clone/packages/solo/lib/src/observer.dart:59), [SoloBase.close](/private/tmp/qr4-two/clone/packages/solo/lib/src/solo_base.dart:550), [solo/CHANGELOG.md, `Unreleased`](/private/tmp/qr4-two/clone/packages/solo/CHANGELOG.md:37); перечисленные ниже записи.

`onClose` всё ещё описан как уведомление о завершившемся закрытии, хотя новый `isFinished` внутри него ложен. Запись CHANGELOG привязывает сброс слушателей к завершению `close`, хотя при приостановленном стриме это разные моменты.

**Доказательство:**

```sh
rtk proxy rg -n -U 'finished closing|Closes the controller, then calls|state is left as is|when `close` finishes' packages/solo/lib/src/observer.dart packages/solo/lib/src/solo_base.dart packages/solo/CHANGELOG.md
```

```text
packages/solo/CHANGELOG.md:37:  state owes it. Listeners are dropped when `close` finishes, after the
packages/solo/lib/src/observer.dart:59:  /// The controller finished closing.
packages/solo/lib/src/solo_base.dart:140:  /// If the controller has finished closing, this is a no-op: the listener
packages/solo/lib/src/solo_base.dart:550:  /// Closes the controller, then calls the observer's `onClose`. Repeated
packages/solo/lib/src/solo_base.dart:551:  /// calls return the same future. The state is left as is.
```

Поиск по истории нашёл ещё семь прямых упоминаний, помимо записей текущего дня:

```sh
rtk proxy rg -n -U 'externalSetState.*после `close\(\)`|externalSetState` пишет его даже|менять не перестаёт|onChange` после `onClose' docs/records --glob '!2026-09-13*'
```

```text
docs/records/2026-09-08[5]-detached-design-review.md:428:`solo` — `onChange` после `onClose` через `externalSetState` из фона и
docs/records/2026-09-06[5]-solo-docs-review.md:470:### 7. [important] `externalSetState` после `close()` меняет состояние, а стрим его роняет
docs/records/2026-09-07[3]-dispose-addendum-review.md:474:куда: состояние живёт своей жизнью, `externalSetState` пишет его даже
docs/records/2026-09-11[8]-external-reviews-plan.md:47:немедленно запрещало запись, а у нас `externalSetState` после `close()`
docs/records/2026-09-06[6]-flutter-solo-docs-review.md:745:Практический сценарий узкий: `externalSetState` после `close()`
docs/records/2026-09-11[10]-selection-report.md:55:менять не перестаёт — `externalSetState` не блокируется закрытием, — и
docs/records/2026-09-07[1]-dispose-design.md:791:`externalSetState` пишет его даже после `close()`. Причина в том, что
```

Есть и старое доказательство различимости кеша:

```sh
rtk proxy sed -n '215,230p' 'docs/records/2026-09-13[3]-solo-listeners-design-review.md'
```

```text
BUILDER_CLOSE builds=[0, 1, 1] currentState=2
BUILDER_SWAP initialNew=7 newUpdate=8 closedSnapshot=3 detached=true
```

**Предлагаю:** добавить актуальные дартдоки и CHANGELOG в план правок. Исторические трассы сохранить; у записей, используемых как действующее обоснование, отметить пересмотр соответствующего контракта. При снятии кеша пометить пересмотренным также раздел `SoloBuilder` в `docs/records/2026-09-13[2]-solo-listeners-design.md`.

Документы обоих языков, дартдоки и примеры просмотрены поиском. Дополнительного прямого обещания разрешённой поздней записи в актуальных README не нашёл; пары `state.md` и комментарий камеры уже учтены спекой.

## Что в спеке верно и проверено

**1. `isFinished` закрывает проверенную дыру с внешним источником при `drain`.**

Наследник подписан на внешний стрим. Его обработчик выполняет:

```dart
if (!isFinished) {
  externalSetState(value);
} else {
  dropped.add(value);
}
```

Задача ждёт внешнего состояния `1`, затем пишет `2`. Источник остаётся подключённым и после завершения присылает `3`.

```sh
rtk proxy dart --packages=/private/tmp/qr4-freeze-review/packages/solo/.dart_tool/package_config.json /private/tmp/qr4-freeze-review/probe.dart
```

```text
DRAIN waiting: isClosed=true isDraining=true isFinished=false done=false
DRAIN final: accepted=[1] dropped=[3] heard=[1, 2] stream=[1, 2] state=2 isFinished=true done=true
DRAIN errors=[]
```

Внешний факт разблокировал работу; оба перехода дошли до слушателя и стрима. Поздний факт отброшен без исключения.

**2. Синхронная проверка безопасна; проверка перед `await` — уже нет.**

Проверил повторный вход из `onChange`, закрытие из диагностического callback перед присваиванием, таймер и зону с перехватом `scheduleMicrotask`, делегирующую планирование.

```sh
rtk proxy dart --packages=/private/tmp/qr4-freeze-review/packages/solo/.dart_tool/package_config.json /private/tmp/qr4-freeze-review/zone_probe.dart
```

```text
ZONE trace=[checked:false, debug-after-close:false, write-return:false] scheduled=4 state=1 dropped=[2, 3] errors=[]
HOOK trace=[hook-return:false] changes=[1, 2] finished=true
```

Пользовательский код внутри записи выполниться может — например, диагностика. Но вызванный им `close()` завершает движок микротаской: синхронную запись черта не обгоняет.

Тем же `probe.dart` проверены вложенная запись из слушателя и запись из `observer.onClose`:

```text
SYNC trace=[listener:1:false, listener:2:false, returned:false, onClose:false, listener:3:false] accepted=[2, 1, 3] dropped=[4, 5] state=3
SYNC errors=[]
```

Контрпример получился при явной точке приостановки:

```dart
if (!c.isFinished) {
  c.raw(await Future<int>(() => 9));
}
```

Вывод `probe.dart`:

```text
AWAIT_GAP caught=StateError
AWAIT_GAP state=0 isFinished=true
AWAIT_GAP errors=[]
```

Это нарушает оговорку спеки об одном синхронном шаге. В рецепте стоит явно написать: **проверять после последнего `await`**. Оснований менять бросок на молчание этот пример не даёт.

**3. Штатного пути к новому `StateError` в проверенной матрице нет.**

Тот же `probe.dart` проверял оба режима закрытия. Ошибки собирались и из зоны, и через `SoloObserver.onError`, поэтому `job.ignore()` не мог скрыть ошибку тела от проверки.

В `writes` после значения указан `isFinished` непосредственно при уведомлении:

```text
MATRIX cancel/uncancellable writes=[1:false] done=true finished=true state=1
MATRIX cancel/uncancellable errors=[]
MATRIX cancel/child writes=[2:false] done=true finished=true state=2
MATRIX cancel/child errors=[]
MATRIX cancel/dispose writes=[3:false] done=true finished=true state=3
MATRIX cancel/dispose errors=[]
MATRIX cancel/discard writes=[4:false] done=true finished=true state=4
MATRIX cancel/discard errors=[]
MATRIX cancel/onCancel writes=[6:false] done=true finished=true state=6
MATRIX cancel/onCancel errors=[]
MATRIX cancel/collect writes=[] done=true finished=true state=0
MATRIX cancel/collect errors=[]
MATRIX cancel/accumulate writes=[1:false] done=true finished=true state=1
MATRIX cancel/accumulate errors=[]
MATRIX cancel/each writes=[] done=true finished=true state=0
MATRIX cancel/each errors=[]
MATRIX drain/uncancellable writes=[1:false] done=true finished=true state=1
MATRIX drain/uncancellable errors=[]
MATRIX drain/child writes=[2:false] done=true finished=true state=2
MATRIX drain/child errors=[]
MATRIX drain/dispose writes=[3:false] done=true finished=true state=3
MATRIX drain/dispose errors=[]
MATRIX drain/discard writes=[] done=true finished=true state=0
MATRIX drain/discard errors=[]
MATRIX drain/onCancel writes=[5:false] done=true finished=true state=5
MATRIX drain/onCancel errors=[]
MATRIX drain/collect writes=[3:false] done=true finished=true state=3
MATRIX drain/collect errors=[]
MATRIX drain/accumulate writes=[1:false, 5:false] done=true finished=true state=5
MATRIX drain/accumulate errors=[]
MATRIX drain/each writes=[7:false] done=true finished=true state=7
MATRIX drain/each errors=[]
```

Проверены неотменяемый ребёнок, асинхронные `onDispose`/`onDiscard`, коррекция `onCancel`, debounce у `collect`, throttle у `accumulate` и ребёнок `each`. Все состоявшиеся записи находятся перед чертой.

Приостановлены были также выходной стрим `Solo` и входная подписка наследника:

```text
PAUSED_STREAM gap: finished=true closeDone=false streamDone=false state=7 dropped=[8]
PAUSED_STREAM resumed: closeDone=true streamDone=true state=7 dropped=[8, 9]
PAUSED_STREAM errors=[]
```

Буферизированный вход после возобновления тоже безопасно отбрасывается.

**4. Добавление `isFinished` действительно ломает совместимость наследников.**

В зонде были два ранее допустимых члена: `String get isFinished` и `bool isFinished(int transferId)`.

Против исходного дерева:

```sh
rtk proxy dart --packages=/private/tmp/qr4-two/clone/packages/solo/.dart_tool/package_config.json analyze /private/tmp/qr4-freeze-review/collision.dart
```

```text
Analyzing collision.dart...
No issues found!
```

Против копии с новым членом:

```sh
rtk proxy dart --packages=/private/tmp/qr4-freeze-review/packages/solo/.dart_tool/package_config.json analyze /private/tmp/qr4-freeze-review/collision.dart
```

```text
Analyzing collision.dart...

  error - collision.dart:5:14 - 'Playback.isFinished' ('String Function()') isn't a valid override of 'SoloBase.isFinished' ('bool Function()'). - invalid_override
           - The member being overridden at packages/solo/lib/src/solo_base.dart:125:12.
  error - collision.dart:10:8 - Class 'Transfer' can't define method 'isFinished' and have field 'SoloBase.isFinished' with the same name. Try converting the method to a getter, or renaming the method to a name that doesn't conflict. - conflicting_method_and_field

2 issues found.
```

Поиск:

```sh
rtk proxy rg -n 'isFinished' packages --glob '*.dart'
```

Объявления в выводе:

```text
packages/async_job/lib/src/job_base.dart:111:  bool get isFinished;
packages/async_job/lib/src/job_base.dart:446:  bool get isFinished => _status == JobStatus.finished;
```

В нынешних наследниках `Solo` фактических конфликтов **0**, в примерах упоминаний **0**. Два объявления принадлежат другой иерархии — `Job`/`JobBase`. Синтезированные конфликты подтверждают необходимость `Breaking`, но не означают наличие таких потребителей в дереве. Совместимый собственный `bool`-геттер может продолжить компилироваться — его смысл тоже следует проверить при миграции.

**5. Семь тестов сохранить можно, но не все механически.**

| Файл и тест | Что остаётся после миграции |
|---|---|
| `solo/test/listeners_base_test.dart` — `after close addListener does not retain listener and does not notify` | Проверка поздней регистрации сохраняется: прямые проверки `hasListeners` уже есть. |
| `flutter_solo/test/solo_builder_test.dart` — `externalSetState after close rebuilds nothing` | Сохраняется интеграционная проверка: отвергнутая запись не меняет изображение и не вызывает новый build. |
| Там же — `connecting an already closed controller shows its state and does not update further` | Сохраняется подключение к окончательному состоянию. Нужное значение устанавливается до закрытия. |
| `flutter_solo/test/solo_listenable_test.dart` — `close removes every listener` | Требуется прямая проверка сброса; одной проверки исключения недостаточно — находка 1. |
| Там же — `a listener added after close hears nothing and is not retained` | Смысл сохраняется благодаря существующим проверкам `hasListeners`. |
| Там же — `a microtask scheduled from observer.onClose does not notify listeners` | Проверять `isFinished`, отсутствие слушателей и исключение непосредственно в микротаске. |
| `flutter_solo/test/solo_selection_test.dart` — `a selection of a closed controller answers from the state` | Сохраняется доступность окончательного значения. Прежнее различение свежего чтения и кеша при молчаливой поздней записи исчезает. |

Все семь переписал во временной копии, тест кеша снял. С усиленными проверками и без кеша билдера:

```sh
rtk proxy python3 /private/tmp/qr4-freeze-review/run_checks.py /private/tmp/qr4-freeze-review solo final-solo
rtk proxy python3 /private/tmp/qr4-freeze-review/run_checks.py /private/tmp/qr4-freeze-review flutter_solo final-flutter_solo
```

Скрипт запускал анализатор и полный набор каждого пакета:

```text
final-solo: dart analyze exit=0
No issues found!
final-solo: dart test --reporter expanded exit=0
00:00 +516: All tests passed!
```

```text
final-flutter_solo: flutter analyze --no-pub exit=0
No issues found! (ran in 3.7s)
final-flutter_solo: flutter test --no-pub --reporter expanded exit=0
00:00 +86: All tests passed!
```

**6. Работа наследника после `await super.close()` уже не может записать состояние.**

Проверено тем же `probe.dart`:

```text
AFTER_SUPER finished=true caught=StateError
AFTER_SUPER guardedDropped=[11]
AFTER_SUPER done=true state=0
AFTER_SUPER errors=[]
```

Даже первая синхронная запись после `await super.close()` опаздывает. Проверка признака превращает её в пропуск, а не переносит черту.

Если результат собственной работы должен попасть в состояние, эту работу следует выполнить перед окончанием движка — например, финальной задачей, принятой до `drain`. Освобождение ресурсов после `super.close()` может оставаться там, но состояние уже окончательное.

Отдельный зонд с такой задачей:

```sh
rtk proxy dart --packages=/private/tmp/qr4-freeze-review/packages/solo/.dart_tool/package_config.json /private/tmp/qr4-freeze-review/final_job.dart
```

```text
FINAL_JOB done=true state=10 seen=[10:false] errors=[]
```

**7. Кеш `SoloBuilder` я бы снял.**

Он больше не нужен для сохранения окончательного состояния. Проверил чтение непосредственно в `build`, сохранив подписку, переподписку и `setState` по уведомлению.

Команда до и после удаления кеша, из временного `packages/flutter_solo`:

```sh
rtk proxy flutter test --no-pub --reporter expanded test/review_cache_test.dart
```

С кешем:

```text
CACHE burst: reads=100 built=[0, 100]
CACHE closed-parent: reads=0 built=[0, 100, 100]
00:00 +1: All tests passed!
```

Без кеша:

```text
CACHE burst: reads=1 built=[0, 100]
CACHE closed-parent: reads=1 built=[0, 100, 100]
00:00 +1: All tests passed!
```

Это замер числа чтений, не времени исполнения. При 100 уведомлениях до кадра результат одинаков; дополнительное хранимое состояние и его обновления можно убрать. На родительском rebuild появляется одно обычное чтение геттера. Полный набор из 86 оставшихся Flutter-тестов тоже прошёл.

Временный стенд удалён. Проверки переносов, ширины и переводов прошли. Финальная команда:

```sh
rtk proxy git status --short
```

вернула **пустой вывод**.

**Вердикт:** принято. Дартдок `SoloObserver.onClose` («The controller
finished closing») теперь спорит сам с собой: внутри этого хука `isFinished`
ещё ложен. Запись `## Unreleased` в `packages/solo/CHANGELOG.md` привязывает
сброс слушателей к завершению `close`, а при приостановленной подписке это
разные моменты. Исторические трассы, как и предложено, остаются как есть;
пересмотр отмечается только там, где запись работает действующим
обоснованием, — и раздел `SoloBuilder`
в `2026-09-13[2]-solo-listeners-design.md` помечается вместе со снятием
кеша.

