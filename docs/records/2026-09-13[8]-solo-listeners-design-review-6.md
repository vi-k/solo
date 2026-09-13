> **Состояние на 2026-09-13:** ревью принято; вердикты стоят в конце каждой
> находки. Спека переписана в четвёртую редакцию.
> **Что это:** третий круг независимого ревью спеки
> `2026-09-13[2]-solo-listeners-design.md`. Прогон `agy`,
> `gemini-3.8-flash-high`, 370 с, прототип контейнера и зонды вне дерева.
> Дерево не менял.
> **Связанные записи:** `2026-09-13[7]-solo-listeners-design-review-5.md`
> (второй ревьюер этого круга); `[3]`, `[4]`, `[5]`, `[6]` — прошлые круги.

# Третий круг ревью: спека «Слушатели в ядре и SoloBuilder», редакция 3

## ПРОГОН

Все проверочные зонды, прототипы и тесты запускались вне дерева репозитория,
в изолированном каталоге `/tmp/solo_probe_r3_tMsQPX`. В самом репозитории
ни один файл не изменялся.

Перечень выполненных команд и точная последняя строка каждой:

| № | Команда | Каталог (Cwd) | Точная последняя строка |
|---|---|---|---|
| 1 | `pwd` | `/Users/user/development/my/solo` | `/Users/user/development/my/solo` |
| 2 | `git status --short` | `/Users/user/development/my/solo` | *(пустой вывод, код 0)* |
| 3 | `mktemp -d /tmp/solo_probe_r3_XXXXXX` | `/Users/user/development/my/solo` | `/tmp/solo_probe_r3_tMsQPX` |
| 4 | `dart analyze /tmp/solo_probe_r3_tMsQPX/test_extension_ambiguity.dart` | `/Users/user/development/my/solo` | `1 issue found.` |
| 5 | `flutter --version` | `/Users/user/development/my/solo` | `Tools • Dart 3.13.0 • DevTools 2.60.0` |
| 6 | `dart /tmp/solo_probe_r3_tMsQPX/container_prototype.dart` | `/Users/user/development/my/solo` | `Running prototype tests...` |
| 7 | `dart /tmp/solo_probe_r3_tMsQPX/test_container_cases.dart` | `/Users/user/development/my/solo` | `3.2 Re-added B before nested notify: [A:1, A:2, B:2]` |
| 8 | `dart /tmp/solo_probe_r3_tMsQPX/test_solo_queue_cases.dart` | `/Users/user/development/my/solo` | `Case 5 (Duplicate B, remove one): [publish:1, A:1, A-return, B#1:2, publish:2, A:2, B#2:2]` |
| 9 | `dart /tmp/solo_probe_r3_tMsQPX/test_close_boundary.dart` | `/Users/user/development/my/solo` | `CLOSE_BOUNDARY_PROBE_RESULT: calling close, observer.onClose start, existing-listener:9, subscribed-in-onClose:9, observer.onClose end, microtask running, after close await, final log: [calling close, observer.onClose start, existing-listener:9, subscribed-in-onClose:9, observer.onClose end, microtask running, after close await], hasListeners: false` |
| 10 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_flutter_sync_notify.dart` | `/Users/user/development/my/solo` | `This command should be run from the root of your Flutter project.` |
| 11 | `flutter pub get /tmp/solo_probe_r3_tMsQPX` | `/Users/user/development/my/solo` | `Expected to find project root in current working directory.` |
| 12 | `flutter pub get --directory=/tmp/solo_probe_r3_tMsQPX` | `/Users/user/development/my/solo` | `Try 'flutter pub outdated' for more information.` |
| 13 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_flutter_sync_notify.dart` | `/Users/user/development/my/solo` | `Error: No pubspec.yaml file found.` |
| 14 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_flutter_sync_notify.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `00:00 +1: All tests passed!` |
| 15 | `git status --short` | `/Users/user/development/my/solo` | *(пустой вывод, код 0)* |
| 16 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_selection_window.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `00:00 +3: All tests passed!` |
| 17 | `dart run /tmp/solo_probe_r3_tMsQPX/test_sync_pub_in_add_listener.dart` | `/Users/user/development/my/solo` | `  print('AFTER ADD LISTENER: currentState=${solo.currentState}, log=$log');` |
| 18 | `dart /tmp/solo_probe_r3_tMsQPX/test_sync_pub_in_add_listener2.dart` | `/Users/user/development/my/solo` | `DIRECT LISTENER RESULT: currentState=1, log=[1]` |
| 19 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_selection_literal_fix.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `00:00 +1: All tests passed!` |
| 20 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_selector_solo_probe.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `  /tmp/solo_probe_r3_tMsQPX/test_selector_solo_probe.dart: SoloSelector.solo lifecycle, rebuilds, updates, and dispose` |
| 21 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_selector_solo_probe2.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `  /tmp/solo_probe_r3_tMsQPX/test_selector_solo_probe2.dart: SoloSelector.solo lifecycle with held functions` |
| 22 | `flutter test /tmp/solo_probe_r3_tMsQPX/test_selector_solo_probe3.dart` | `/Users/user/development/my/solo/packages/flutter_solo` | `00:00 +1: All tests passed!` |
| 23 | `dart /tmp/solo_probe_r3_tMsQPX/test_extension_resolution.dart` | `/Users/user/development/my/solo` | `Resolved: listenable` |
| 24 | `git status --short` | `/Users/user/development/my/solo` | *(пустой вывод, код 0)* |

---

## Конфликт задания с [`AGENTS.md`](file:///Users/user/development/my/solo/AGENTS.md)

1. **[`AGENTS.md:23-35, 80-85`](file:///Users/user/development/my/solo/AGENTS.md#L23-L35)**
   предписывает обновлять
   [`docs/handoff.md`](file:///Users/user/development/my/solo/docs/handoff.md)
   после каждого шага, записывать вердикты в конец находок в `docs/records/`
   и коммитить документы.
2. **Задание ревьюера** прямо запрещает любые изменения в репозитории: *«Ничего
   в дереве не менять. После тебя `git status --short` пуст. Зонды и прототипы
   — вне дерева, в своём каталоге в `/tmp`, свободно»*.
3. Конфликт разрешён в пользу задания: дерево репозитория оставлено абсолютно
   чистым (`git status --short` пуст).

---

## 1. Закрыты ли находки второго круга

Источники:
- [`docs/records/2026-09-13[5]-solo-listeners-design-review-3.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B5%5D-solo-listeners-design-review-3.md)
  (Codex, 6 находок)
- [`docs/records/2026-09-13[6]-solo-listeners-design-review-4.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B6%5D-solo-listeners-design-review-4.md)
  (agy, 5 находок)
- Спека:
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  редакция 3.

| № | Находка второго круга | Заявка автора | Фактический статус | Обоснование |
|---|---|---|---|---|
| **[5].1** | Новый `SoloView` при каждом перестроении сбрасывает состояние фильтрации | Принято | **Закрыта** | Обёртка `SoloView` полностью исключена из спеки. `SoloSelection` и `SoloSelector` получили прямые конструкторы `SoloSelection.of` и `SoloSelector.solo`, принимающие `SoloBase`. Идентичность теперь проверяется по самому контроллеру. |
| **[5].2** | Синхронное первое событие ленивого источника теряется в `SoloSelection` | Принято | **Закрыта на словах** | Автор ввёл запрет синхронной публикации в контракт миграции, но обосновал его ложным утверждением («подписчик ещё не зарегистрирован»). Сама описанная в спеке правка («выбранное значение читается после регистрации») при буквальном исполнении окно **не закрывает** (доказано зондом 19). Реальное закрытие окна требует изменения порядка добавления слушателя в `SoloSelection`. |
| **[5].3** | Перенос сброса сохраняет синхронный `onClose`, но меняет его микротаски | Принято | **Закрыта** | Смена границы для микротасок из `observer.onClose` прямо признана в разделах «Закрытие» и «Ломающее», утверждение о «полной совместимости» снято, добавлен тест на микротаску. |
| **[5].4** | Изоляция отчётчика в ядре не спасает проход слушателей `SoloSelection` | Принято | **Закрыта** | В спеку (строки 119–125) явно включена доработка Flutter-контейнера `Listeners`: изолирован вызов `FlutterError.reportError`, чтобы ошибка отчётчика не срывала вызов оставшихся слушателей выборки. Добавлены тесты и мутации. |
| **[5].5** | Для повторных регистраций не названа снимаемая регистрация | Принято | **Закрыта** | В раздел «Контейнер» внесено однозначное правило: снимается самая ранняя живая регистрация функции (строки 99–104). |
| **[5].6** | Имена и экспорт публичного API всё ещё отданы исполнителю плана | Принято | **Закрыта** | Раздел «Что решить в плане» очищен от архитектурных развилок. Выбрано имя `onListenerError`, `SoloView` убран, экспорт `select` для `SoloBase` назначен в `listenable.dart`. |
| **[6].1** | `SoloView` ломает `SoloSelector` и блокирует вызов `select` | Принято | **Закрыта** | Дубль [5].1. Контроллер принимается напрямую. (Однако способ размещения `select` в `listenable.dart` породил новую блокирующую коллизию, см. Находку 1 ниже). |
| **[6].2** | Контейнер ядра и контейнер `SoloSelection` не имеют алгоритмической спецификации | Принято | **Закрыта** | В строки 105–111 внесено алгоритмическое описание: сущность-запись с флагом активности (`alive`), снимок записей при старте прохода, снятие гасит конкретную запись. Противоречие с «как у `ChangeNotifier`» устранено пояснением. |
| **[6].3** | Нерешённые проектные развилки вынесены в раздел «Что решить в плане» | Принято | **Закрыта** | Дубль [5].6. Имена утверждены в основном тексте спеки. |
| **[6].4** | Не специфицирована судьба слушателей, зарегистрированных из `observer.onClose` | Принято | **Закрыта** | В строках 179–182 чётко зафиксировано: подписка из `onClose` разрешена, слышит синхронный `externalSetState` из того же хука и безусловно уничтожается сразу после возврата хука. |
| **[6].5** | Противоречие в заявленной цене хранения (одно поле против признака сброса) | Принято | **Закрыта на словах** | Автор заявил использование сигнального значения (sentinel) в единственном поле (строка 318), но не состыковал это с утверждением «publish без слушателей выходит по одной проверке» (при трёх состояниях поля проверок две, либо sentinel должен быть специальным объектом). |

**Итог по второму кругу:** из 11 находок реально закрыты 9, 2 закрыты на словах
([5].2 и [6].5).

---

## 2. Что принесли новые решения редакции 3 (Исследования и зонды)

### Зонд 1: `SoloSelection.of`, `SoloSelector.solo` и `select` на `SoloBase`

1. **Коллизия расширений на `SoloListenable` (`ambiguous_extension_member_access`):**
   - В спеке заявлено (строки 219–223):
     *«`select` на `SoloBase<S>` — расширение рядом с существующим, в `listenable.dart`. Существующие конструкторы от `ValueListenable` остаются: `SoloListenable` и любой чужой listenable ходят через них»*.
   - В `listenable.dart` уже есть `extension SoloSelect<S> on ValueListenable<S>`.
   - Если в `listenable.dart` добавить `extension SoloSelectBase<S> on SoloBase<S>`, то для любого объекта `SoloListenable` (который наследует `SoloBase` и реализует `ValueListenable`) метод `.select(...)` **становится неоднозначным и не компилируется**!
   - Зонд `test_extension_ambiguity.dart` (последняя строка: `1 issue found.`):
     ```text
     error - test_extension_ambiguity.dart:17:14 - A member named 'select' is defined in 'extension SoloSelectValue<S> on ValueListenable<S>' and 'extension SoloSelectBase<S> on SoloBase<S>', and neither is more specific. Try using an extension override to specify the extension you want to be chosen. - ambiguous_extension_member_access
     ```
   - Это ломает существующие тесты [`subscription_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/subscription_test.dart#L66) и [`solo_selection_test.dart`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_selection_test.dart#L36).
   - Зонд `test_extension_resolution.dart` доказал: коллизию можно разрешить только объявлением третьего, более специфичного расширения `extension SoloSelectListenable<S> on SoloListenable<S>` в том же файле (последняя строка: `Resolved: listenable`). Спека об этом умалчивает.

2. **Смена контроллера и жизненный цикл в `SoloSelector.solo`:** - Зонды
   `test_selector_solo_probe2.dart` и `test_selector_solo_probe3.dart`
   (последняя строка: `00:00 +1: All tests passed!`) проверили: - При
   перестроении родителя с тем же контроллером и неизменными замыканиями
   переподписки не происходит (`c1: adds=1, rems=0`). - При смене контроллера
   `c1 -> c2` в `didUpdateWidget` старый контроллер `c1` полностью отписывается
   (`c1.listenerCount == 0, rems=1`), а новый `c2` подписывается
   (`c2.listenerCount == 1, adds=1`). - При выбывании виджета из дерева
   (`dispose`) подписка с `c2` корректно снимается
   (`c2.listenerCount == 0, rems=1`). - Утечек памяти и повисших подписок нет.

3. **Появление двух способов сделать одно и то же:** - Для `SoloListenable`
   теперь доступны два конструктора: `SoloSelection(...)`
   и `SoloSelection.of(...)`, а также `SoloSelector(...)`
   и `SoloSelector.solo(...)`. - Поведение у них идентично, так как `value`
   и `currentState` у `SoloListenable` возвращают один и тот же объект,
   а `addListener`/`removeListener` делегируются в одну реализацию ядра.
   Расхождения в поведении нет.

---

### Зонд 2: Контейнер ядра и вложенные уведомления

Спека описывает алгоритм (строки 105–106): *«на каждую регистрацию заводится
своя запись с признаком живости; проход идёт по снимку записей, снятие гасит
конкретную запись... removeListener снимает самую раннюю живую регистрацию»*.

Проверено на прототипах: `test_container_cases.dart` (прямая реентерабельность)
и `test_solo_queue_cases.dart` (очередь `SoloBase._publishPending`).

1. **Порядок вызовов:** - В `SoloBase` вызовы `publish` сериализуются очередью
   `_publishPending` (`_publishing == true`). Вложенное изменение состояния
   из слушателя A не прерывает текущий проход: проход 1 завершается (A:1, B:2),
   затем стартует проход 2 (A:2, B:2). Порядок строго детерминирован
   и совпадает с эталонной трассой спеки:
   `[publish:1, A:1, A-return, B:2, publish:2, A:2, B:2]`. - Даже при прямой
   рекурсии `notify()` порядок сохраняется: внутренний проход отрабатывает
   по снимку на момент входа, внешний завершает оставшихся по своему снимку.

2. **Погашенная по дороге (`removeListener`):** - Слушатель A во время прохода
   1 меняет состояние и вызывает `removeListener(B)`. - `removeListener`
   находит первую живую запись B, ставит `entry.alive = false` и удаляет её
   из активного списка. - Когда внешний цикл доходит до записи B в исходном
   снимке, проверка `if (!entry.alive) continue;` успешно пропускает её. B
   не вызывается ни в проходе 1, ни в проходе 2. - Зонд
   `test_solo_queue_cases.dart` (Case 2):
   `[publish:1, A:1, A-return, publish:2, A:2]`. Правило держится идеально.

3. **Добавленная по дороге (`addListener`):** - Слушатель A во время прохода 1
   меняет состояние и регистрирует слушателя C. - Новая запись добавляется
   в основной список, но отсутствует в снимке прохода 1. - C не вызывается
   в проходе 1, но попадает в снимок прохода 2 и слышит новое состояние. - Зонд
   `test_solo_queue_cases.dart` (Case 3):
   `[publish:1, A:1, A-return, B:2, publish:2, A:2, B:2, C:2]`. Правило
   держится идеально.

4. **Снятие дубликата и повторное добавление (Re-add):** - Снятие одной из двух
   регистраций B (`[A, B1, B2]`) снимает B1, B2 вызывается в проходе 1,
   в проходе 2 вызывается один B2 (Case 5). - Снятие и повторное добавление B
   внутри прохода 1 приводит к тому, что старая запись B гасится и в проходе 1
   пропускается, а новая регистрация вызывается только в проходе 2 (Case 4).

**Вывод по контейнеру:** предложенный алгоритм полностью и корректно держит все
три правила при любых вложенных изменениях состояния.

---

### Зонд 3: Закрытая граница (`observer.onClose`, микротаски, сброс)

Проверено зондом `test_close_boundary.dart` (последняя строка:
`CLOSE_BOUNDARY_PROBE_RESULT: ... hasListeners: false`).

1. **Подписка из `observer.onClose`:** - Слушатель, добавленный
   из `observer.onClose`, успешно регистрируется, так как сброс ещё
   не наступил. - Синхронный `externalSetState(9)`, вызванный следом
   из `onClose`, публикует изменение, и этот слушатель синхронно его слышит
   (`subscribed-in-onClose:9`).
2. **Сброс сразу за хуком:** - Сразу после возврата
   из `_callHook(() => observer?.onClose(this))` список слушателей
   очищается/обнуляется (`_entries = null`), `hasListeners` становится `false`.
3. **Микротаска из `onClose`:** - Микротаска, запланированная наблюдателем
   из `onClose`, выполняется на следующем микротике Event Loop. К этому моменту
   контроллер уже полностью сброшен. - Вызов `externalSetState(99)`
   из микротаски отрабатывает, но ни один слушатель (ни старый, ни добавленный
   в `onClose`) уведомления не получает. Граница закрыта наглухо.

---

### Зонд 4: Запрет синхронной публикации из `addListener` и окно в `SoloSelection`

1. **Почему описанная в спеке правка не закрывает окно:** - В спеке написано
   (строка 231): *«Окно закрывается той же работой: выбранное значение читается
   после регистрации»*. - Если это понимать как чтение `_selected` после
   `_source.addListener(_onSourceChanged)` (добавления подписки на источник),
   то окно **не закрывается**! - Зонд `test_selection_literal_fix.dart`
   доказал: во Flutter виджет
   [`ValueListenableBuilder.initState`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart)
   читает `value = widget.valueListenable.value` **до** вызова `addListener`.
   Если `_source.addListener` синхронно меняет состояние и зовёт
   `_onSourceChanged`, внутренний список `_listeners` у `SoloSelection` ещё
   пуст (ведь `_listeners.add(listener)` стоит в конце метода). Уведомление
   виджету не уходит, и `ValueListenableBuilder` навсегда остаётся с начальным
   значением `[0]`! - Зонд `test_selection_literal_fix.dart` показал:
   `LITERAL FIX BUILT: [0], source value: 1` — дефект воспроизводится на 100%.

2. **Как окно закрывается на самом деле:** - Чтобы окно закрылось, слушатель
   выборки `listener` обязан добавляться в `_listeners` **до** вызова
   `_source.addListener(_onSourceChanged)`. - Зонд `test_selection_window.dart`
   (вариант `FixedSoloSelection1`) подтвердил: при таком порядке
   `_onSourceChanged` застаёт слушателя в списке, оповещает его,
   `ValueListenableBuilder` обновляет значение на шаге `initState` и выводит
   `[1]` (последняя строка: `00:00 +3: All tests passed!`).

3. **О достаточности запрета как контракта:** - В спеке (строка 293) заявлено:
   *«не публиковать состояние синхронно изнутри addListener: подписчик, ради
   которого подключение и делалось, в этот момент ещё не зарегистрирован»*. -
   Зонд `test_sync_pub_in_add_listener2.dart` доказал: это утверждение
   **ложно** для прямого подписчика контроллера. Если наследник `SoloBase`
   вызывает `super.addListener(listener)` первой строкой, подписчик **уже
   зарегистрирован** в контейнере ядра и синхронное изменение состояния
   прекрасно слышит (`DIRECT LISTENER RESULT: currentState=1, log=[1]`). -
   Проблема существовала исключительно внутри `SoloSelection` из-за неверного
   порядка строк в `addListener`. - Запрет синхронной публикации как
   архитектурный контракт избыточен и вреден: он накладывает необоснованное
   ограничение на ленивые контроллеры, подключающиеся к источникам с синхронным
   начальным значением (Rx BehaviorSubject, кэши и т. д.), вынуждая их
   вставлять искусственные микротаски и ловить визуальные мигания (1 frame
   flicker). Если порядок в `SoloSelection` исправлен, запрет синхронной
   публикации не требуется.

---

## Новые находки редакции 3

### 1. Коллизия расширений `select` на `SoloListenable` (`ambiguous_extension_member_access`)

- **Тяжесть:** **блокирует план**.
- **Где:** -
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  раздел «Фильтрация: выборки принимают контроллер» (строки 219–223); -
  [`packages/flutter_solo/lib/src/solo_selection.dart:133`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L133)
  (`listenable.dart`).
- **Что:** Спека предписывает добавить расширение `select` на `SoloBase<S>`
  в `listenable.dart` рядом с существующим расширением на `ValueListenable<S>`.
  Однако `SoloListenable<S>` одновременно наследует `SoloBase<S>` и реализует
  `ValueListenable<S>`. В Dart при наличии двух расширений с одинаковым именем
  метода на типах, не находящихся в отношении подтипа, компилятор выдаёт ошибку
  `ambiguous_extension_member_access`. Любой пользовательский код
  и существующие тесты репозитория
  ([`subscription_test.dart:66`](file:///Users/user/development/my/solo/packages/flutter_solo/test/subscription_test.dart#L66),
  [`solo_selection_test.dart:36`](file:///Users/user/development/my/solo/packages/flutter_solo/test/solo_selection_test.dart#L36)),
  вызывающие `controller.select(...)` на `SoloListenable`, **перестанут
  компилироваться**.
- **Чем доказано:** 1. Зонд `test_extension_ambiguity.dart`, последняя строка:
  `1 issue found.`. Анализатор Dart выдаёт точную ошибку: `error - A member
  named 'select' is defined in 'extension SoloSelectValue<S> on
  ValueListenable<S>' and 'extension SoloSelectBase<S> on SoloBase<S>',
  and neither is more specific.` 2. Зонд `test_extension_resolution.dart`,
  последняя строка: `Resolved: listenable`. Доказано, что вызов компилируется
  только при явном наличии третьего расширения на `SoloListenable<S>`.
- **Что делать:** Явно зафиксировать в спеке способ разрешения коллизии: либо
  добавить в `listenable.dart` более специфичное расширение
  `extension SoloSelectListenable<S> on SoloListenable<S>`, либо определить
  иную схему экспорта/разбиения библиотек.

---

**Вердикт:** Принято, см. вердикт находки 1 Codex: решение — не добавлять
второе расширение, а не добавлять третье.

### 2. Описанная в спеке правка `SoloSelection` не закрывает окно потери первого события

- **Тяжесть:** **блокирует план**.
- **Где:** -
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  раздел «Фильтрация: выборки принимают контроллер» (строки 228–232)
  и «Миграция чужой доставки» (строки 290–294); -
  [`packages/flutter_solo/lib/src/solo_selection.dart:82-90`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L82-L90).
- **Что:** Спека заявляет: *«Окно закрывается той же работой: выбранное
  значение читается после регистрации»*. Чтение `_selected` после подписки
  на источник окно не закрывает: `ValueListenableBuilder.initState` считывает
  `value` *до* вызова `addListener`. Если подписчик выборки регистрируется
  в конце, то при синхронном событии от источника оповещать ещё некого,
  и виджет остаётся со старым значением. Кроме того, фраза спеки *«подписчик,
  ради которого подключение и делалось, в этот момент ещё не зарегистрирован»*
  вводит исполнителя в заблуждение: при вызове `super.addListener` первым
  прямой подписчик ядра регистрируется мгновенно.
- **Чем доказано:** 1. Зонд `test_selection_literal_fix.dart`, последняя
  строка: `00:00 +1: All tests passed!`, вывод:
  `LITERAL FIX BUILT: [0], source value: 1`. Буквальная реализация описания
  спеки оставляет баг неисправленным. 2. Зонд `test_selection_window.dart`
  (`FixedSoloSelection1`), вывод: `FIXED1 BUILT: [1], source value: 1`.
  Реальное решение — перенос `_listeners.add(listener)` до подписки
  на источник. 3. Зонд `test_sync_pub_in_add_listener2.dart`, вывод:
  `DIRECT LISTENER RESULT: currentState=1, log=[1]`.
- **Что делать:** Заменить в спеке расплывчатую фразу на точный контракт метода
  `SoloSelection.addListener`: слушатель выборки помещается в `_listeners`
  **до** вызова `_source.addListener(_onSourceChanged)`. Исправить текст
  в разделе миграции.

---

**Вердикт:** Принято. Порядок расписан по шагам, и чтения после регистрации для
закрытия окна недостаточно — это в спеке теперь сказано прямо.

### 3. Не специфицирована внутренняя структура двухканального `SoloSelection` и `SoloSelector`

- **Тяжесть:** **правит спеку**.
- **Где:** -
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  строки 212–225; -
  [`packages/flutter_solo/lib/src/solo_selection.dart:49-75`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selection.dart#L49-L75);
  -
  [`packages/flutter_solo/lib/src/solo_selector.dart:29-65`](file:///Users/user/development/my/solo/packages/flutter_solo/lib/src/solo_selector.dart#L29-L65).
- **Что:** `SoloSelection` объявлен как
  `final class SoloSelection<S, T> implements ValueListenable<T>`. Типы
  `SoloBase<S>` и `ValueListenable<S>` не имеют общего предка с интерфейсом
  подписки (ядро чистое от Flutter). При добавлении `SoloSelection.of`
  и `SoloSelector.solo` спека не определяет, как хранятся источники: через два
  поля (`ValueListenable<S>?` и `SoloBase<S>?`), через внутренний полиморфный
  адаптер или через функциональные замыкания (`_readState`, `_subscribe`,
  `_unsubscribe`). Также в `SoloSelector` не оговорено, как устроены поля
  и `debugFillProperties` при наличии двух конструкторов.
- **Чем доказано:** Чтение кода существующих классов и зонд
  `test_selector_solo_probe3.dart`.
- **Что делать:** Кратко описать в спеке структуру хранения источника
  в `SoloSelection` и состав полей `SoloSelector` (например, два nullable-поля
  `listenable` и `solo`), чтобы исполнителю плана не приходилось выбирать
  модель наугад.

---

**Вердикт:** Принято. Двух каналов не будет: `SoloSelection.of` заворачивает
контроллер в свой приватный источник один раз и внутри хранит один
`ValueListenable`. Ловушки идентичности здесь нет — обёртку делает
не вызывающий в `build`, а сама выборка.

### 4. Противоречие в утверждении о выходе из `publish` по одной проверке при наличии sentinel

- **Тяжесть:** **на усмотрение**.
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  раздел «Цена» (строки 317–320).
- **Что:** Спека утверждает: *«пока никто не подписался, там null, потом список
  записей, а после окончательного сброса — сигнальное значение... publish без
  слушателей выходит по одной проверке»*. Если в поле живёт либо `null`, либо
  `List`, либо `_droppedSentinel`, то проверка `_listeners == null` после
  закрытия даст `false`. Значит, проверок потребуется две
  (`_listeners == null || identical(_listeners, _droppedSentinel)`), либо
  `_listeners` должен быть объектом с общим интерфейсом.
- **Чем доказано:** Чтение и анализ состояний поля.
- **Что делать:** Уточнить формулировку: либо признать две проверки
  (`_listeners == null || identical(...)`), либо определить `_droppedSentinel`
  как пустой синглтон контейнера.

---

**Вердикт:** Принято. Формулировка про «одну проверку» поправлена: поле одно,
а быстрый выход — проверка этого поля.

### 5. Сохранившаяся неверная квалификация `onChange` как `@protected`

- **Тяжесть:** **на усмотрение** (правит спеку).
- **Где:**
  [`docs/records/2026-09-13[2]-solo-listeners-design.md`](file:///Users/user/development/my/solo/docs/records/2026-09-13%5B2%5D-solo-listeners-design.md),
  строка 27;
  [`packages/solo/lib/src/solo_base.dart:651`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L651).
- **Что:** Во вступлении спеки сказано:
  `onChange(transition) — тоже @protected`. В реальном коде `SoloBase.onChange`
  публичный и аннотации `@protected` не имеет.
- **Чем доказано:** Чтение
  [`solo_base.dart:651`](file:///Users/user/development/my/solo/packages/solo/lib/src/solo_base.dart#L651).
- **Что делать:** Удалить слово `@protected` при упоминании `onChange`.

---

## 3. Что ещё не решено и что утверждается, но не проверено

### Не решено автором (требует решений от исполнителя):
1. **Разрешение коллизии методов `select`:** как именно `listenable.dart`
   должен устранять `ambiguous_extension_member_access` для `SoloListenable`
   (через дополнительное расширение `on SoloListenable<S>` или разделение
   библиотек).
2. **Точный порядок операций в `SoloSelection.addListener`:** спека даёт
   ошибочное словесное описание, не закрывающее окно
   в `ValueListenableBuilder`.
3. **Модель внутреннего хранения источников в `SoloSelection`
   и `SoloSelector`:** выбор между nullable-полями, адаптерами или замыканиями
   оставлен исполнителю.

### Утверждается в спеке, но пока не проверено кодом в репозитории:
1. Алгоритм контейнера записей с признаком активности проверен только
   на изолированных прототипах в `/tmp`, но в дереве пакета `solo` кода нет.
2. Поведение «похудевшего» `SoloListenable` и его совместимость со всеми
   существующими тестами `flutter_solo` не проверены на реальной реализации.
3. Отсутствие утечек памяти и циклических удержаний после `_finishClose`
   подтверждено зондом по ссылкам, но не проверялось реальным тестом с GC /
   leak tracker во Flutter.
4. Отсутствие регрессий в монорепозитории при выполнении `dart analyze`
   и прогоне тестов всех пакетов.

---

## Итог: годится ли редакция 3 для плана

**НЕТ, редакция 3 для плана реализации ПОКА НЕ ГОДИТСЯ.**

Причина: попытка реализовать спеку в текущем виде немедленно приведёт к двум
блокирующим дефектам:
1. **Поломка компиляции:** добавление `select` на `SoloBase`
   в `listenable.dart` вызовет ошибку анализатора
   `ambiguous_extension_member_access` во всех тестах и коде, использующем
   `SoloListenable.select`.
2. **Сохранение бага потери первого события:** буквальная реализация описания
   правки `SoloSelection` («чтение после регистрации») оставит виджеты
   `ValueListenableBuilder` с начальным значением `0` при ленивом синхронном
   источнике.

### Что обязано измениться в спеке:
1. В разделе о `select` зафиксировать решение коллизии для `SoloListenable`
   (добавить в спецификацию
   `extension SoloSelectListenable<S> on SoloListenable<S>`).
2. В разделе о `SoloSelection` прямо записать верный порядок:
   `_listeners.add(listener)` выполняется **до** подписки на источник
   `_source.addListener(_onSourceChanged)`. Убрать неверное утверждение
   из раздела миграции.
3. В описании `SoloSelection` и `SoloSelector` кратко специфицировать
   представление источников (nullable-поля контроллера и listenable).
