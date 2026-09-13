> **Состояние на 2026-09-13:** ревью принято целиком; вердикты стоят
> в конце каждой находки. Спека переписана во вторую редакцию.
> **Что это:** независимое ревью спеки
> `2026-09-13[2]-solo-listeners-design.md`, прогон `agy`,
> `gemini-3.8-flash-high`, 259 с, зонды в отдельном пакете вне дерева.
> Дерево ревьюер не менял. Прогон шёл одновременно с ревью Codex, чтобы
> списывать было не у кого.
> **Связанные записи:** `2026-09-13[2]-solo-listeners-design.md` (спека),
> `2026-09-13[3]-solo-listeners-design-review.md` (второй ревьюер).

## ПРОГОН

Перечень команд, выполненных в ходе проверки, с точной последней строкой
каждой:

1. `pwd` (в `/private/tmp/rev-solo-m2x/clone`) Последняя строка:
   `/private/tmp/rev-solo-m2x/clone`
2. `mktemp -d /tmp/solo_probe_XXXXXX` (в `/private/tmp/rev-solo-m2x/clone`)
   Последняя строка: `/tmp/solo_probe_BHz3qN`
3. `pwd` (в `/tmp/solo_probe_BHz3qN`) Последняя строка:
   `/private/tmp/solo_probe_BHz3qN`
4. `dart pub get` (в `/tmp/solo_probe_BHz3qN`) Последняя строка:
   `Changed 2 dependencies!`
5. `dart run bin/probe1.dart` (в `/tmp/solo_probe_BHz3qN`, черновик зонда)
   Последняя строка: `Job outcome after clean publish: null`
6. `dart run bin/probe1.dart` (в `/tmp/solo_probe_BHz3qN`, фиксация синтаксиса
   `ctx.wait`) Последняя строка: `        await ctx.wait(finished.future);`
7. `dart run bin/probe1.dart` (в `/tmp/solo_probe_BHz3qN`, зонд факта
   о `publish` и `keepWhile`) Последняя строка:
   `Job outcome after clean publish: Cancelled(rules: keepWhile)`
8. `dart run bin/probe_nested.dart` (в `/tmp/solo_probe_BHz3qN`, зонд
   вложенного `externalSetState`) Последняя строка: `finished externalSet(1)`
9. `dart run bin/probe_listenable.dart` (в `/tmp/solo_probe_BHz3qN`, зонд
   совместимости `ValueListenable`) Последняя строка: `value: 42`
10. `git status --short` (в `/private/tmp/rev-solo-m2x/clone`) Последняя
    строка: *(пустой вывод)*

---

## Конфликты с правилами репозитория ([`AGENTS.md`](file:///private/tmp/rev-solo-m2x/clone/AGENTS.md))

1. **[`AGENTS.md`](file:///private/tmp/rev-solo-m2x/clone/AGENTS.md#L23-L35)
   предписывает обновлять `docs/handoff.md`** после каждого законченного шага.
   Задание прямо требует: *«Ничего в дереве не менять. После тебя git status
   --short пуст»*. Конфликт разрешён в пользу задания: `docs/handoff.md`
   не изменялся, дерево осталось чистым.
2. **Системные инструкции агента запрещают использовать `/tmp`** в качестве
   рабочего каталога команд. Задание прямо требует: *«Зонды, пакеты-стенды
   и черновики — вне дерева, в своём каталоге в /tmp, свободно»*. Конфликт
   разрешён в пользу задания: все зонды созданы и запущены в изолированном
   `/tmp/solo_probe_BHz3qN`.

---

## Проверка по пунктам задания

### 1. Факты о движке: `publish`, `_publishPending` и отмена по `keepWhile`

**Утверждение спеки:** `publish` вызывается
из [`_publishPending`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L700-L713),
а сразу за ним идёт
[`_reevaluate`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L687-L693),
поэтому ошибка слушателя, выпущенная из `publish`, отменяет переоценку правил
бегущих задач, и задача не получает положенную отмену.

**Проверка зондом:** Вне дерева собран отдельный пакет `solo_probe`
с зависимостью
на [`packages/solo`](file:///private/tmp/rev-solo-m2x/clone/packages/solo)
и оверрайдом
на [`packages/async_job`](file:///private/tmp/rev-solo-m2x/clone/packages/async_job).
Наследник `SoloBase` выбрасывает исключение из `publish` при переходе в новое
состояние, пока выполняется задача
с `keepWhile: (state) => state == 'initial'`.

**Полный вывод зонда (`bin/probe1.dart`):**
```text
Job started, isRunning: true
Caught from triggerExternal: Bad state: listener boom from publish
State after throwing change: changed
Job isRunning after throwing publish: true
Job outcome after throwing publish: null
Job isRunning after clean publish: false
Job outcome after clean publish: Cancelled(rules: keepWhile)
```
*Точная последняя строка:*
`Job outcome after clean publish: Cancelled(rules: keepWhile)`.

**Вывод:** Факт полностью подтверждён. Необработанное исключение из `publish`
прерывает
[`_setState`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L660-L693)
до вызова `_reevaluate`, в результате чего задача продолжает выполняться, хотя
состояние уже не соответствует её `keepWhile`.

---

### 2. Правда ли, что подписаться сейчас не на что

**Чтение кода:**
- [`publish`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L130-L132)
  — `@protected`, доступен только подклассам.
- [`onChange`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L651)
  — `@protected`, также хук экземпляра для подкласса.
- [`observer`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L38)
  — глобальное статическое поле на весь процесс
  (`static SoloObserver? observer`). Один слот, ловит события всех контроллеров
  всех типов, не типизирован по состоянию (`Object?`), предназначен для
  сквозной телеметрии.
- Стрим
  [`Solo.stream`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo.dart#L19)
  принадлежит конкретному подклассу
  [`Solo`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo.dart#L8),
  а не [`SoloBase`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L33).
- `currentState` — пассивный геттер (опрос, а не подписка).

**Вывод:** Утверждение спеки верно: третьего пути для подписки на экземпляр
`SoloBase` в текущей кодовой базе не существует.

---

### 3. Коллизии новой поверхности

Спека добавляет
в [`SoloBase<S>`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L33):
`addListener`, `removeListener`, `@protected hasListeners`,
`@protected reportListenerError`.

**Проверка по кодовой базе репозитория:**
1. [`SoloListenable`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_listenable.dart#L19-L38):
   объявляет `addListener(VoidCallback)` и `removeListener(VoidCallback)`.
   В Dart `typedef VoidCallback = void Function();` — сигнатуры идентичны. Зонд
   `bin/probe_listenable.dart` доказал, что класс, наследующий `SoloBase`
   с этими методами, компилируется и удовлетворяет интерфейсу `ValueListenable`
   без конфликтов типов (вывод: `value: 42`).
2. [`SoloSelection`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_selection.dart#L49)
   и [`SoloSelector`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_selector.dart#L29):
   не содержат полей или методов с именами `hasListeners` или
   `reportListenerError`.
3. Тесты и примеры (`packages/solo/test`, `packages/flutter_solo/test`,
   `packages/solo/example`, `packages/flutter_solo/example`): имён
   `hasListeners` и `reportListenerError` нет ни в одном файле репозитория.

**Коллизии вне дерева (breaking change):** Любой внешний наследник `SoloBase`,
определивший свой `addListener` с сигнатурой, отличной от `void Function()`,
либо имевший поле/геттер `hasListeners`/`reportListenerError`, сломается при
компиляции.

---

### 4. Дыры в самой спеке

- **Слушатель зовёт `close()` изнутри уведомления:** `SoloBase.close()`
  завершается асинхронно (`scheduleMicrotask` или по окончании текущей задачи).
  Поэтому при вызове `close()` из первого слушателя оставшиеся слушатели
  текущего синхронного прохода выполняются штатно. Однако спека
  не специфицирует, что происходит, если слушатель после вызова `close()`
  попытается вызвать `addListener` (см. Находку 2).
- **Слушатель зовёт `externalSetState`:** Зонд `bin/probe_nested.dart` выявил,
  что при вложенном вызове `externalSetState` текущий `_state` контроллера
  перезаписывается немедленно. В результате слушатели, идущие следом
  за инициатором в текущем проходе, читают уже новое состояние, а затем
  в следующем проходе вызываются повторно. Промежуточное состояние они
  пропускают (см. Находку 5).
- **Уведомление во время уведомления:** Правила копирования списка слушателей
  и игнорирования снятых в процессе прохода соответствуют
  [`Listeners`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/listeners.dart).
  Но спека упустила защиту от исключения в самом `reportListenerError` (см.
  Находку 4).
- **Порядок «слушатели ядра против доставки наследника (`Solo.stream`)»:**
  В `Solo.publish` вызов `super.publish` стоит первым. Синхронные ядерные
  слушатели всегда вызываются до того, как событие падает
  в `StreamController.add`.
- **`close(SoloCloseMode.drain)`:** Во время дренажа очередь продолжает
  выполняться и менять состояния. Размещение сброса слушателей в `_finishClose`
  корректно сохраняет их до полного завершения дренажа, но спека
  не оговаривает, как в этот период работает семантика `addListener` (см.
  Находку 2).
- **Подписка после `close`:** Спека декларирует молчаливый no-op «в точности
  как в SoloListenable», но в текущей реализации `SoloListenable.addListener`
  добавляет слушателя в память и порождает утечку (см. Находку 3).
- **Цена контроллера без слушателей:** 1 `null`-ссылка (`_listeners = null`).
  При отсутствии слушателей в `publish` происходит один null-check без
  аллокаций.
- **`SoloBuilder` в `didUpdateWidget`:** Спека не специфицирует переподписку
  при смене контроллера (см. Находку 6).

---

### 5. Виджет: `currentState` против `value` и отказ от `buildWhen`

- `SoloBase` полностью достаточен для `SoloBuilder`: виджету не требуется
  `value`, он читает `solo.currentState`.
- Решение **не давать `buildWhen`** логически сломано текущей формулировкой
  спеки: обоснование «фильтрация уже есть в SoloSelection/SoloSelector»
  не работает для `SoloBase`, так как они требуют `ValueListenable` (см.
  Находку 1).

---

### 6. Классификация правки

Классификация `**Breaking:**` абсолютно **верна**. Добавление методов
в открытый для наследования класс `SoloBase` ломает внешние подклассы при
пересечении имён или несовпадении сигнатур. Это полностью соответствует правилу
репозитория (скилл `dart`, правило 42: «Новый член базового класса ломает
подкласс») и прецеденту
[`JobBase.inUncancellableSection`](file:///private/tmp/rev-solo-m2x/clone/packages/async_job/CHANGELOG.md#L28-L31)
в `async_job`.

---

### 7. Противоречия с прежними решениями

2026-09-12
в [`2026-09-12[5]-own-delivery-recipe-report.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-12[5]-own-delivery-recipe-report.md)
отказались от синхронного контроллера в чистом Dart, аргументируя:
> *«В ядре Dart такого интерфейса нет... В сервере и CLI идиома — Stream... колбэк не складывается ни с чем»*.

Новая спека утверждает, что её предмет иной (не третий класс контроллера).
Формально это так: класс не создаётся. Однако содержательно спека приносит
синхронные колбэки прямо в базовый класс ядра `SoloBase`, навязывая их
и серверным, и CLI-контроллерам ради нужд одного Flutter-виджета `SoloBuilder`.
Кроме того, вчерашний рецепт `Watchable` объявляется устаревшим/избыточным (см.
Находку 7).

---

## Находки

### Находка 1
- **что:** Спека отказывается от `buildWhen` в `SoloBuilder`, ссылаясь
  на наличие `SoloSelection`/`SoloSelector`, но они принимают только
  `ValueListenable`, а поддержку `SoloBase` спека объявляет находящейся вне
  своих рамок.
- **тяжесть:** правит спеку.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 125–128 и 182–184;
  [`packages/flutter_solo/lib/src/solo_selector.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_selector.dart#L29)
  (`SoloSelector`),
  [`packages/flutter_solo/lib/src/solo_selection.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_selection.dart#L49)
  (`SoloSelection`).
- **чем доказано:** чтение: `SoloSelector` требует `ValueListenable<S>`,
  `SoloSelection` требует `ValueListenable<S>`. `SoloBase` не реализует
  `ValueListenable`. В строках 182–184 спека выносит поддержку `SoloBase`
  в `SoloSelection` в раздел «Что вне спеки». Пользователь `SoloBase` (или
  `Solo`) лишается любой возможности выборочного перестроения.
- **что делать:** включить адаптацию `SoloSelection` и `SoloSelector` под
  `SoloBase` в предмет этой же спеки либо предусмотреть `buildWhen`
  непосредственно в `SoloBuilder`.

---

**Вердикт:** Принято. Совпадает с находкой 3 Codex: адаптер `ValueListenable`
над `SoloBase` входит в спеку, и фильтрация становится доступна тому же типу
источника.

### Находка 2
- **что:** Спека не определяет критерий «завершения close» для семантики no-op
  при вызове `addListener`, создавая риск поломки подписок в режиме
  `SoloCloseMode.drain`.
- **тяжесть:** правит спеку.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 98–106;
  [`packages/solo/lib/src/solo_base.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L119)
  (`SoloBase.isClosed`, `addListener`, `_finishClose`).
- **чем доказано:** чтение: геттер `isClosed` становится `true` сразу при
  старте дренажа (`_closing != null`), когда очередь ещё активна и публикует
  состояния. Если реализация проверит `if (isClosed) return;`, то подписка
  на дренируемый контроллер станет no-op преждевременно.
- **что делать:** явно зафиксировать в спеке, что no-op наступает
  не по `isClosed`, а строго по завершении `_finishClose` (через флаг сброса
  слушателей).

---

**Вердикт:** Принято. no-op наступает не по `isClosed`, а по факту сброса
слушателей: во время `SoloCloseMode.drain` подписка работает.

### Находка 3
- **что:** Спека заявляет о переносе «в точности сегодняшнего поведения
  `SoloListenable`» для подписки после `close`, но в существующем коде
  `SoloListenable.addListener` не проверяет закрытие и вызывает утечку памяти.
- **тяжесть:** правит спеку.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 100–103;
  [`packages/flutter_solo/lib/src/solo_listenable.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/flutter_solo/lib/src/solo_listenable.dart#L34)
  (`SoloListenable.addListener`, строка 34; `publish`, строки 57–59).
- **чем доказано:** чтение: `SoloListenable.addListener` делает
  `_listeners.add(listener)` безусловно; вызовы не происходят только из-за
  проверки `_dropped` в `publish`, в то время как колбэк удерживается в памяти
  `_listeners` навсегда.
- **что делать:** специфицировать в ядре явный no-op (не регистрировать колбэк
  в коллекции, если слушатели уже сброшены) и скорректировать формулировку
  в тексте спеки.

---

**Вердикт:** Принято. См. вердикт находки 4 Codex: поздняя подписка
не удерживает колбэк, и это отмечено как `Fix`.

### Находка 4
- **что:** Исключение, выброшенное из `reportListenerError`, не изолировано
  и способно сломать `_reevaluate` точно так же, как исключение самого
  слушателя.
- **тяжесть:** правит спеку.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 54–56, 65–70, 80–86;
  [`packages/solo/lib/src/solo_base.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L686-L693)
  (`SoloBase._publishPending`).
- **чем доказано:** чтение: если переопределённый в подклассе хук или зона
  выбросят ошибку из `reportListenerError`, она выйдет из `publish`, прервёт
  `_publishPending` и оставит задачи без отмены по `_reevaluate`.
- **что делать:** указать в спеке, что вызов `reportListenerError` изолируется
  (по аналогии с `SoloBase._callHook`).

---

**Вердикт:** Принято. Дубль находки 2 Codex.

### Находка 5
- **что:** Вложенный вызов `externalSetState` из слушателя приводит
  к рассинхронизации `currentState`: последующие слушатели видят новое
  состояние дважды и пропускают старое.
- **тяжесть:** правит спеку.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 92–94;
  [`packages/solo/lib/src/solo_base.dart`](file:///private/tmp/rev-solo-m2x/clone/packages/solo/lib/src/solo_base.dart#L660-L713)
  (`SoloBase._setState`, `_publishPending`).
- **чем доказано:** зонд `bin/probe_nested.dart` (последняя строка:
  `finished externalSet(1)`): слушатель 1 меняет состояние с 1 на 2; слушатель
  2 в первой волне видит `state=2`, а затем вызывается во второй волне и снова
  видит `state=2`. Состояние 1 слушатель 2 не увидел вовсе.
- **что делать:** описать этот эффект в секции «Проход» спеки и закрепить его
  тестом ядра.

---

**Вердикт:** Принято. Эффект описан в разделе «Проход» и закреплён тестом ядра.

### Находка 6
- **что:** Спека опускает детали жизненного цикла `SoloBuilder`
  в `didUpdateWidget`.
- **тяжесть:** на усмотрение.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  секция `## SoloBuilder` (строки 107–128).
- **чем доказано:** чтение: в спеке приведен только открытый конструктор без
  уточнения отписки от `oldWidget.solo`, подписки на `widget.solo` и обновления
  локального состояния `state`.
- **что делать:** явно зафиксировать в описании виджета контракт
  `didUpdateWidget` и `dispose`.

---

**Вердикт:** Принято. Совпадает с находкой 5 Codex: контракт `didUpdateWidget`
и `dispose` назван в спеке.

### Находка 7
- **что:** Перенос слушателей в `SoloBase` противоречит архитектурному мотиву
  отказа от чистого Dart-контроллера от 2026-09-12.
- **тяжесть:** на усмотрение.
- **где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-13[2]-solo-listeners-design.md),
  строки 6–7;
  [`docs/records/2026-09-12[5]-own-delivery-recipe-report.md`](file:///private/tmp/rev-solo-m2x/clone/docs/records/2026-09-12[5]-own-delivery-recipe-report.md).
- **чем доказано:** чтение: 2026-09-12 было решено, что ядро должно быть
  свободно от доставки, а синхронные слушатели чужды чистому Dart (CLI/сервер).
  Новая спека пересматривает это решение по существу, наделяя `SoloBase`
  собственной доставкой.
- **что делать:** отразить в шапке спеки явный пересмотр архитектурного
  принципа: появление запроса на `SoloBuilder` сделало универсальную подписку
  в ядре приоритетнее чистоты `SoloBase` от механизмов доставки.

---

**Вердикт:** Принято. Пересмотр архитектурной границы назван прямо в шапке
спеки.

## Итог: годится ли спека для плана как есть

**Не годится.**

Для того чтобы спека стала пригодной для составления плана реализации, в ней
**обязаны измениться** следующие пункты:

1. **Разрешить противоречие с выборочным перестроением (Находка 1):** Либо
   включить в спеку поддержку `SoloBase` в `SoloSelection` / `SoloSelector`
   (через общий интерфейс/extension/адаптер), либо предусмотреть `buildWhen`
   прямо в `SoloBuilder`. Сейчас для контроллеров `SoloBase` в `flutter_solo`
   образуется вакуум: `SoloBuilder` их принимает, а отфильтровать перестроения
   невозможно.
2. **Устранить неопределённость и утечку памяти при `close` (Находки 2 и 3):**
   Чётко описать, что подписка после закрытия является no-op без сохранения
   замыкания в памяти, а сам no-op наступает строго после завершения
   `_finishClose` (чтобы не заблокировать подписку во время
   `SoloCloseMode.drain`).
3. **Защитить вызов `reportListenerError` (Находка 4):** Специфицировать
   изоляцию `reportListenerError` внутри цикла оповещения, чтобы падение
   репортера не срывало `_reevaluate` бегущих задач.
