> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана в третью редакцию.
> **Что это:** второй круг независимого ревью спеки
> `2026-09-13[2]-solo-listeners-design.md`. Прогон `agy`,
> `gemini-3.8-flash-high`, 338 с, зонды в отдельном пакете вне дерева.
> Дерево не менял.
> **Связанные записи:** `2026-09-13[5]-solo-listeners-design-review-3.md`
> (второй ревьюер этого же круга), `2026-09-13[3]` и `2026-09-13[4]` —
> первый круг.

# ПРОГОН

Ничего в дереве репозитория не менялось. Все зонды, проверочные пакеты
и черновики запускались в изолированном каталоге
`/tmp/solo_probe_round2_dtvwjp`.

Перечень выполненных команд и точная последняя строка каждой:

| Команда и каталог запуска | Точная последняя строка |
|---|---|
| `git status --short` (в `/Users/user/development/my/solo`) | *(пустой вывод, код 0)* |
| `mktemp -d /tmp/solo_probe_round2_XXXXXX` (в `/Users/user/development/my/solo`) | `/tmp/solo_probe_round2_dtvwjp` |
| `dart --version && flutter --version` (в `/Users/user/development/my/solo`) | `Tools • Dart 3.13.0 • DevTools 2.60.0` |
| `flutter pub get` (в `/tmp/solo_probe_round2_dtvwjp`) | `Try 'flutter pub outdated' for more information.` |
| `flutter pub get && flutter test test_view_selector.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `00:00 +1: All tests passed!` |
| `dart run probe_close_listeners.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `RESULTS: inOnClose=true firedInOnClose=true` |
| `flutter test probe_change_notifier.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `No tests were found.` |
| `flutter test probe_duplicate_removal.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `No tests were found.` |
| `flutter test probe_cn_readd.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `No tests were found.` |
| `dart run probe_container_algorithms.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `  Re-add: bCalls=0 (expected 0)` |
| `dart analyze test_select_compile.dart` (в `/tmp/solo_probe_round2_dtvwjp`) | `2 issues found.` |
| `git status --short` (в `/Users/user/development/my/solo`) | *(пустой вывод, код 0)* |

---

## Конфликты с правилами репозитория ([`AGENTS.md`](file:///Users/user/development/my/solo/AGENTS.md))

1. **[`AGENTS.md`](file:///Users/user/development/my/solo/AGENTS.md#L23-L35)
   требует обновлять
   [`docs/handoff.md`](file:///Users/user/development/my/solo/docs/handoff.md)**
   после каждого законченного шага. Задание прямо запрещает менять дерево:
   *«Ничего в дереве не менять. После тебя git status --short пуст»*. Конфликт
   разрешён в пользу задания: файлы в репозитории не изменялись.
2. **Инструкции среды запрещают использовать каталог `/tmp`**, тогда как
   задание прямо указывает: *«Зонды и стенды — вне дерева, в своём каталоге
   в /tmp, свободно»*. Конфликт разрешён в пользу задания: зонды выполнялись
   в отдельной временной папке `/tmp/solo_probe_round2_dtvwjp`, не оставляя
   артефактов в репозитории.

---

## 1. Закрыты ли находки первого круга на самом деле

Всего в первом круге было 15 находок (8
в [`docs/records/2026-09-13[3]-solo-listeners-design-review.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[3]-solo-listeners-design-review.md)
от Codex и 7
в [`docs/records/2026-09-13[4]-solo-listeners-design-review-2.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[4]-solo-listeners-design-review-2.md)
от agy). Автор специи выставил всем 15 вердикт «Принято». Ниже сопоставление
заявки автора и фактического состояния текста редакции 2:

| Находка первого круга | Заявка автора | Фактический статус | Обоснование |
|---|---|---|---|
| **Codex 1**: `Listeners` нельзя перенести целиком | Принято | **Закрыта на словах** | Обещание перенести файл снято, но сам алгоритм учёта регистраций не описан: спека заявляет одновременно «как у `ChangeNotifier`» и «проход по копии регистраций», что технически противоречиво. В `flutter_solo` контейнер `SoloSelection` оставлен сломанным со словами «чинится в том же плане». |
| **Codex 2**: Ошибка отчётчика `reportListenerError` не изолирована | Принято | **Закрыта** | В спеке явно указана изоляция вызова через `_callHook`, направление ошибки в зону и сохранение переоценки `_reevaluate`. |
| **Codex 3**: Замена `buildWhen` недоступна целевой аудитории | Принято | **Не закрыта** | Введён `SoloView`, но `controller.select(...)` не компилируется (ошибка анализатора), а в `SoloSelector` обёртка ломает жизненный цикл виджета (сброс подписки на каждом кадре из-за `!identical`). |
| **Codex 4**: Перенос сброса меняет контракт закрытия | Принято | **Закрыта** | Сброс перемещён строго после `observer?.onClose`, поздняя подписка больше не удерживает замыкание в памяти (`Fix`). |
| **Codex 5**: Завышенное требование отсутствия перестроений после `close` | Принято | **Закрыта** | Формулировка скорректирована: гарантируется отсутствие новых уведомлений, а не отмена уже запланированных кадров; зафиксирован жизненный цикл `SoloBuilder`. |
| **Codex 6**: Старый рецепт не превращается в «лишний список» | Принято | **Закрыта** | Добавлен раздел «Миграция чужой доставки»: чётко сформулировано правило удаления собственных списков и вызова `super.addListener` при переопределении. |
| **Codex 7**: При переносе контейнера пропущен `SoloSelection` | Принято | **Закрыта на словах** | Спека признаёт, что `SoloSelection` остаётся со своим `Listeners`, но не определяет, как чинить его дефект повторных регистраций. |
| **Codex 8**: Очередь `publish` не сериализует вложенный переход | Принято | **Закрыта** | Зафиксировано, что уведомление снимка не несёт, слушатель читает актуальный `currentState`, трасса утверждена как тестовый контракт. |
| **agy 1**: `buildWhen` vs `SoloSelection`/`SoloSelector` (дубль Codex 3) | Принято | **Не закрыта** | Проблема остаётся нерешённой для `SoloSelector` и `select`. |
| **agy 2**: Не определён момент no-op при drain (дубль Codex 4) | Принято | **Закрыта** | Разведены `isClosed`, `drain` и сброс в `_finishClose`. |
| **agy 3**: Утечка памяти при поздней подписке (дубль Codex 4) | Принято | **Закрыта** | Зафиксирован no-op без удержания колбэка. |
| **agy 4**: Падение `reportListenerError` (дубль Codex 2) | Принято | **Закрыта** | Защищено через изоляцию хука. |
| **agy 5**: Вложенный `externalSetState` (дубль Codex 8) | Принято | **Закрыта** | Описано и специфицировано трассой. |
| **agy 6**: `SoloBuilder` в `didUpdateWidget` (дубль Codex 5) | Принято | **Закрыта** | Контракт переподписки и кеширования состояния вписан в спеку. |
| **agy 7**: Архитектурный конфликт с решением от 2026-09-12 | Принято | **Закрыта** | В шапку спеки добавлено прямое признание пересмотра архитектурных границ. |

**Итог проверки закрытия находок:** из 15 находок реально закрыты 11, 2 закрыты
на словах (контейнер ядра и `SoloSelection`), 2 не закрыты вовсе (фильтрация
выборочных перестроений через `SoloView`).

---

## 2. Что сломали правки редакции 2 (Проверка зондами и кодом)

### Зонд 1: `SoloView` ломает `SoloSelector` и не обеспечивает работу `select`

Спека заявляет (строки 196–204):
> *«С ней — SoloSelection(SoloView(controller), (state) => state.canSave) и всё остальное работает без правок в самих классах... SoloView годится для SoloSelection, SoloSelector и select»*.

**Что показали проверки:**

1. **[`SoloSelector`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selector.dart#L29)** сравнивает слушаемый объект в [`didUpdateWidget`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selector.dart#L97):
   ```dart
   if (!identical(widget.listenable, oldWidget.listenable) ||
       !identical(widget.selector, oldWidget.selector) ||
       !identical(widget.compare, oldWidget.compare)) {
     _selection = _select();
   }
   ```
   В коде виджета контроллер создаётся в состоянии родителя или передаётся снаружи, но `SoloView(controller)` создаётся **внутри метода `build()`**. Конструктор `SoloView(controller)` не может быть `const`, поскольку контроллер — динамический объект во времени.
   Зонд `test_view_selector.dart` (последняя строка: `00:00 +1: All tests passed!`) показал диагностику:
   ```text
   INITIAL: adds=1 removes=0 listeners=1
   AFTER_REBUILD: adds=2 removes=1 listeners=1
   EQUALITY: v1==v2 is false, identical is false
   ```
   При каждом обычном перестроении родительского виджета создаётся новый `SoloView`. Проверка `!identical` срабатывает всегда, старый `SoloSelection` уничтожается, отписывается от контроллера (`removes=1`), создаётся новый `SoloSelection` и подписывается заново (`adds=2`). Это полностью уничтожает смысл `SoloSelector`, который задумывался именно ради сохранения подписки между перестроениями. При этом `SoloView` в спеке не имеет ни `operator ==`, ни `hashCode`, но даже при их наличии `SoloSelector` сравнивает строго по `identical`!

2. **Расширение `select`:**
   В [`listenable.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L133)
   метод `select` объявлен как `extension SoloSelect<S> on ValueListenable<S>`.
   Экземпляр `Solo` или `SoloBase` **не реализует** `ValueListenable`. Зонд
   `test_select_compile.dart` при проверке `solo.select(...)` завершился
   ошибкой анализатора (код 3, последняя строка: `2 issues found.`): ```text
   error - test_select_compile.dart:7:20 - The method 'select' isn't defined
   for the type 'Solo'. ``` Следовательно, синтаксис `controller.select(...)`
   **не работает**. Пользователю навязано писать громоздкое
   `SoloView(controller).select(...)`.

### Зонд 2: Слушатель из `observer.onClose` и жизненный цикл закрытия

Спека (строки 161–165) помещает сброс слушателей
в [`_finishClose`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L570)
после вызова `observer?.onClose`.

Зонд `probe_close_listeners.dart` (последняя строка:
`RESULTS: inOnClose=true firedInOnClose=true`):
- Во время вызова `observer?.onClose` сброс ещё не наступил.
- Если наблюдатель вызывает `addListener`, слушатель успешно регистрируется.
- Если наблюдатель тут же вызывает `externalSetState(9)`, этот слушатель
  синхронно вызывается (`firedInOnClose=true`).
- Однако сразу после завершения `_callHook(() => observer?.onClose(this))`
  следующая строка сброса **безусловно уничтожает** всех слушателей.
- Если же `onClose` добавил слушателя без изменения состояния, регистрация
  уничтожается в следующей строке, так и не получив ни одного уведомления.
  Поздняя подписка после завершения `_finishClose` — чистый no-op.

### Зонд 3: `hasListeners` во время закрытия и после сброса

1. До закрытия: `hasListeners` отражает наличие активных подписчиков.
2. Во время вызова `close()` и в процессе `SoloCloseMode.drain`:
   `isClosed == true`, но `hasListeners == true` (подписчики продолжают
   получать уведомления).
3. Внутри `observer?.onClose`: `hasListeners == true`.
4. После выхода из `_finishClose`: слушатели сброшены, `hasListeners == false`.
5. Попытка вызова `addListener` после сброса: подписчик не сохраняется,
   `hasListeners` остаётся `false`.

### Зонд 4: Счёт регистраций и алгоритм прохода

Спека утверждает:
> *«Считаются регистрации, а не функции... как у ChangeNotifier»* (строка 99)
> *«проход идёт по копии регистраций и пропускает снятые по дороге; регистрация, добавленная во время прохода, слышит следующее изменение»* (строки 126–128)

Зонды `probe_change_notifier.dart`, `probe_cn_readd.dart`
и `probe_container_algorithms.dart` доказали:
- **`ChangeNotifier` не использует копию списка.** Он итерируется
  по фиксированному диапазону `0..end`, где `end = _count` на момент старта.
  Слушатели, удалённые во время прохода, обнуляются на месте
  (`_listeners[i] = null`), а добавленные во время прохода добавляются
  с индексом `>= end` и в текущий проход не попадают. Очистка `null` происходит
  только по завершении внешнего прохода (`_depth == 0`).
- Если же в ядре делать буквально **«проход по копии»** списком колбэков,
  то снятие одного из дубликатов и повторное добавление функции невозможно
  различить без выделения объектов-токенов (`Entry` с флагом `cancelled`).
- Спека создаёт техническое противоречие между «как у `ChangeNotifier`»
  и «проход по копии», скрывая конкретную структуру данных контейнера.

---

## Новые находки

### Находка 1: `SoloView` ломает `SoloSelector` и блокирует вызов `select`
- **Что:** `SoloView` не решает проблему выборочной перестройки для `SoloBase`
  и `Solo`. В `SoloSelector` обёртка вызывает отписку и повторную подписку
  на каждом кадре из-за проверки `!identical`, а расширение `select`
  на `SoloBase` не компилируется. Заявка «всё работает без правок в самих
  классах» ложна.
- **Тяжесть:** **блокирует план**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[2]-solo-listeners-design.md),
  раздел «`SoloView`» (строки 181–204);
  [`packages/flutter_solo/lib/src/solo_selector.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selector.dart#L97),
  `_SoloSelectorState.didUpdateWidget`;
  [`packages/flutter_solo/lib/src/solo_selection.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L133),
  `SoloSelect`.
- **Чем доказано:** 1. Зонд `test_view_selector.dart` (последняя строка:
  `00:00 +1: All tests passed!`, диагностика:
  `AFTER_REBUILD: adds=2 removes=1 listeners=1 EQUALITY: v1==v2 is false,
  identical is false`). 2. Зонд `test_select_compile.dart` (код 3, последняя
  строка: `2 issues found.`, ошибка:
  `The method 'select' isn't defined for the type 'Solo'`).
- **Что делать:** 1. Внести изменения в `SoloSelector`: сравнивать
  `widget.listenable != oldWidget.listenable` и добавить реализацию
  `operator ==` и `hashCode` в `SoloView` (по идентичности `solo`). Либо
  предусмотреть конструктор `SoloSelector.solo(SoloBase<S> solo, ...)`. 2.
  Объявить расширение `select` для `SoloBase<S>` в `listenable.dart`. 3. Убрать
  из спеки ложное утверждение, будто `SoloView` работает «без правок
  в существующих классах».

**Вердикт:** Принято. Совпадает с находкой 1 Codex: обёртка убрана, выборки
принимают контроллер напрямую.

### Находка 2: Контейнер ядра и контейнер `SoloSelection` не имеют алгоритмической спецификации
- **Что:** Спека декларирует учёт регистраций, но не специфицирует структуру
  контейнера ядра и оставляет нерешённым исправление аналогичного дефекта
  в `SoloSelection`. Текст спеки противоречив: «как у `ChangeNotifier`»
  исключает «проход по копии регистраций».
- **Тяжесть:** **блокирует план**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[2]-solo-listeners-design.md),
  разделы «Контейнер» (строки 93–110), «Проход» (строки 126–128), «Цена»
  (строки 281–286).
- **Чем доказано:** Чтение и зонды `probe_change_notifier.dart` (последняя
  строка: `No tests were found.`) и `probe_container_algorithms.dart`
  (последняя строка: `  Re-add: bCalls=0 (expected 0)`).
- **Что делать:** Явно выбрать и описать алгоритм: - Вариант А: реализация
  по образцу `ChangeNotifier` (плоский список `List<void Function()?>`, обход
  `0..end`, обнуление при удалении во время итерации, сжатие при `depth == 0`,
  без создания копии). - Вариант Б: список токенов/записей `_Entry` с булевым
  флагом `cancelled` и явным копированием списка ссылок при старте уведомления.
  Указать, будет ли контейнер ядра переиспользован в `flutter_solo` для
  `SoloSelection`.

**Вердикт:** Принято. Алгоритм назван: запись на каждую регистрацию с признаком
живости, проход по снимку записей; ссылка на `ChangeNotifier` оставлена только
там, где речь о числе вызовов, а не об устройстве.

### Находка 3: Нерешённые проектные развилки вынесены в раздел «Что решить в плане»
- **Что:** Раздел «Что решить в плане» содержит не задачи планирования,
  а непринятые архитектурные решения: выбор имени метода (`reportListenerError`
  vs `onListenerError`), имя класса (`SoloView` vs `SoloValue`), состав
  публичного экспорта `flutter_solo.dart`.
- **Тяжесть:** **правит спеку**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[2]-solo-listeners-design.md),
  раздел «Что решить в плане» (строки 306–310).
- **Чем доказано:** Чтение. В базовом классе
  [`SoloBase`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L33)
  все хуки следуют единому стилю именования `on...`: `onCreate`, `onClose`,
  `onChange`, `onStart`, `onFinish`, `onError`, `onLog`. Имя
  `reportListenerError` выбивается из соглашений движка, но автор не принял
  окончательного решения. Исполнитель не имеет права выбирать публичные имена
  API за автора.
- **Что делать:** Принять решения в теле спеки: - Утвердить единое имя хука
  (рекомендуется `onListenerError` в соответствии с остальными хуками
  `SoloBase`). - Утвердить имя `SoloView` и явно зафиксировать библиотеки его
  экспорта (`flutter_solo.dart` или `listenable.dart`).

**Вердикт:** Принято. Развилки имён из «что решить в плане» убраны, решения
стоят в тексте.

### Находка 4: Не специфицирована судьба слушателей, зарегистрированных из `observer.onClose`
- **Что:** Сброс слушателей происходит сразу после вызова `observer?.onClose`.
  Регистрация слушателя из `onClose` технически возможна, но после завершения
  хука слушатель уничтожается сбросом.
- **Тяжесть:** **правит спеку**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[2]-solo-listeners-design.md),
  раздел «Закрытие» (строки 161–171).
- **Чем доказано:** Зонд `probe_close_listeners.dart` (последняя строка:
  `RESULTS: inOnClose=true firedInOnClose=true`).
- **Что делать:** Зафиксировать в контракте закрытия: вызов `addListener`
  из `observer.onClose` допускается и может услышать синхронный
  `externalSetState` из того же хука, но по завершении `onClose` все
  зарегистрированные слушатели очищаются и дальнейшие подписки игнорируются.

**Вердикт:** Принято. Контракт дописан: подписка из `observer.onClose`
разрешена, слышит синхронный `externalSetState` того же хука и сбрасывается
вместе со всеми сразу после него.

### Находка 5: Противоречие в заявленной цене хранения (одно поле против признака сброса)
- **Что:** Спека утверждает, что контроллер без слушателей платит «одним
  null-полем», и тут же указывает: «отдельно хранится только признак
  окончательного отключения». Флаг отключения требует либо второго поля
  (`bool _dropped`), либо кодирования через сигнальное значение (sentinel).
- **Тяжесть:** **на усмотрение**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13[2]-solo-listeners-design.md),
  раздел «Цена» (строки 281–286).
- **Чем доказано:** Чтение.
- **Что делать:** Уточнить реализацию: признак сброса хранится в том же поле
  через sentinel-объект (например, `_listeners = _droppedSentinel`), что
  сохраняет обещание одного `null`-поля в экземпляре `SoloBase`.

---

**Вердикт:** Принято. Признак окончательного сброса живёт в том же поле
сигнальным значением, обещание одного поля сохраняется.

## 3. Что ещё не решено и что утверждается, но не проверено

### Не решено автором (требует решений от исполнителя):
1. **Способ сопряжения `SoloSelector` и `SoloBase`:** Будет ли изменён
   `_SoloSelectorState.didUpdateWidget` на проверку `!=`, получит ли `SoloView`
   реализацию `operator ==`, либо появится прямой конструктор
   `SoloSelector.solo`?
2. **Доступность `select` на контроллерах:** Будет ли добавлено расширение
   `select` на `SoloBase`?
3. **Конкретная алгоритмическая модель контейнера слушателей:** Будет ли это
   копия записей с токенами или массив с обнулением индексов в стиле
   `ChangeNotifier`?
4. **Судьба контейнера в `flutter_solo`:** Переиспользует ли `SoloSelection`
   ядерный контейнер или получит отдельный дубликат кода?
5. **Финальные имена методов и классов:** `reportListenerError` или
   `onListenerError`, `SoloView` или `SoloValue`, экспорт в `flutter_solo.dart`
   или `listenable.dart`.

### Утверждается в спеке, но не проверено:
1. Заявление, что `SoloView` позволяет использовать `SoloSelector` и `select`
   «без правок в самих классах» — **опровергнуто зондами** (ломает подписки
   и не компилируется).
2. Заявление о цене ровно в одно `null`-поле при наличии отдельного флага
   отключения — не подтверждено конкретной структурой полей.
3. Исправление бага учёта регистраций в `SoloSelection` — отложено без
   проверки.

---

## Итог: годится ли редакция 2 для плана

**НЕТ, редакция 2 для составления плана реализации НЕ ГОДИТСЯ.**

Попытка составить план сейчас вынудит исполнителя самостоятельно проектировать
алгоритм ядра и переделывать контракт виджетов Flutter-слоя.

### Что обязано измениться до передачи в план:

1. **Починить интеграцию с выборочным перестроением:** - Либо научить
   `SoloSelector` и `SoloSelection` принимать `SoloBase` напрямую без
   промежуточных обёрток; - Либо специфицировать в `SoloView` реализацию
   `operator ==` и `hashCode`, а в `SoloSelector.didUpdateWidget` заменить
   проверку `!identical` на `!=`; - Добавить расширение `select` на `SoloBase`
   в `listenable.dart`.
2. **Специфицировать алгоритм контейнера ядра:** устранить противоречие между
   «как у `ChangeNotifier`» и «проход по копии», явно описать структуру данных
   и определить механизм устранения дефекта в `SoloSelection`.
3. **Принять проектные решения по именам:** убрать развилки из раздела «Что
   решить в плане» и зафиксировать финальные имена членов и экспорты в основном
   тексте спеки.
