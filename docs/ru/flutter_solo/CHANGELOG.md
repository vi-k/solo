## Не выпущено

Этот пакет реэкспортирует `solo`, а через него и `async_job`, поэтому их
изменения принадлежат и этому пакету: см.
[список изменений `solo`](../solo/CHANGELOG.md)
и [список изменений `async_job`](../async_job/CHANGELOG.md).

## 0.3.0

Этот пакет реэкспортирует `solo`, а через него и `async_job`, поэтому их
изменения принадлежат и этому пакету: см.
[список изменений `solo`](../solo/CHANGELOG.md)
и [список изменений `async_job`](../async_job/CHANGELOG.md).

### Ломающие изменения

- **В `solo` `Solo.onError` стал уведомлением, а за ошибку, которой больше
  ни у кого нет, отвечает новый `Solo.onUnanswered`: за ту, которой не несёт
  ни один исход, и за `Failed`, который никто не наблюдает.** Заданный
  `Solo.observer` или переопределение `onError`, которое не зовёт `super`,
  больше не удерживают такую ошибку от зоны: см. ту же запись
  в [списке изменений `solo`](../solo/CHANGELOG.md).
- **`Job.ignore()` переименован в `Job.ignoreFailure()`** в `async_job`.
- **В `solo` `Solo.run` переименован в `enqueue`, а `Solo.add` —
  в `enqueueJob`.** См. ту же запись
  в [списке изменений `solo`](../solo/CHANGELOG.md).
- **В `solo` обработчики состояния у `enqueue` и `job` переименованы: `onError`
  в `ifFailed`, `onCancel` в `ifCancelled`.**
- **`ctx.run` и `ctx.runAll` принимают `ChildJob`** в `async_job`, а `SoloJob`
  из `solo` — это `ChildJob`: помощник, который возвращает `job(...)` для
  `ctx.run`, объявляется `SoloJob<T>`, а не `Job<T>`.
- **`SoloListenable` стал миксином на `Solo`,** как `SoloStream` в `solo`:
  `extends SoloListenable<S>` становится `extends Solo<S> with SoloListenable`.
  См.
  [«Контроллер как `ValueListenable`»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#контроллер-как-valuelistenable).
- **`SoloListenable` больше не несёт стрим.** Контроллер, чей `stream` кто-то
  читает, подмешивает оба миксина, `with SoloStream, SoloListenable`. См.
  [«Контроллер с обеими доставками»](mixins.md#контроллер-с-обеими-доставками).
- **В `solo` синхронное чтение контроллера называется `currentState`,
  а не `state`.**
- **`ValueListenable` больше не реэкспортируется.** Файл, который называет этот
  тип, импортирует `package:flutter/foundation.dart`.
- **`close` принимает новый `SoloCloseMode` из `solo`.**
- **`publish` больше не публичный член контроллера с `SoloListenable`.**
- **Слушатели отбрасываются, когда движок заканчивает закрытие, сразу после
  `onClose` наблюдателя и `onClose` самого контроллера.** Пишите последнее
  состояние синхронно, в `onClose` контроллера.

### Устарело

- `ctx.wait` в `async_job` устарел, его заменяет `ctx.abandonable`; старое имя
  уйдёт в следующем выпуске.

### Что вы увидите после обновления

- О слушателе, который бросает, сообщается через `FlutterError.reportError`,
  как о таком сообщает `ChangeNotifier`, и его ошибка больше не вылетает
  из `emit` или `externalSetState`, которые сделали изменение: задача, чей это
  был `emit`, заканчивается `Done` там, где раньше заканчивалась `Failed`.
- Ошибки, которые `0.2.0` оставляла хукам, доходят до `Solo.unansweredHandler`
  или до зоны: см. тот же заголовок
  в [списке изменений `solo`](../solo/CHANGELOG.md).

### Добавлено

- `SoloBuilder`: то же, что `ValueListenableBuilder`, для контроллера, который
  не реализует `ValueListenable`. См.
  [«Как пользоваться»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#как-пользоваться).
- `SoloSelection<S, T>`: проекция, то есть `ValueListenable` одного значения,
  выбранного из другого, который уведомляет, только когда это значение
  меняется. Для контроллера, который не реализует `ValueListenable`, её создаёт
  `SoloSelection.from`. См.
  [«Выбор одного значения»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#выбор-одного-значения).
- `SoloSelector`, виджет, который выбирает за вас: контроллер, `selector`
  и `builder`.
- `select` и `listen` как методы, с `SoloSubscription` и `SoloSubscriptions`,
  в отдельном импорте, `package:flutter_solo/listenable.dart`. См.
  [«Подписка без хранения колбэка»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#подписка-без-хранения-колбэка)
  и [«Методы из второго импорта»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#методы-из-второго-импорта).

### Исправлено

- Слушатель, который бросает, больше не оставляет без уведомления слушателей
  за ним и не даёт задаче работать дальше при состоянии, которое её `keepWhile`
  запрещает.
- Слушатель, добавленный после того, как контроллер закончил закрытие,
  пропускается: он не регистрируется и не хранится, ошибки тоже нет. Раньше он
  оставался в памяти навсегда.
- Один проход уведомления линеен по числу слушателей; раньше он был
  квадратичным.

### Документация

- Примеры README собираются, а на странице появились разделы о контроллере как
  `ValueListenable`, о проекциях и о `listen`.
- У пакета есть собственные страницы, [«Миксины»](mixins.md)
  и [«Тестирование»](testing.md).
- Пример больше не застревает на неудавшейся загрузке.

## 0.2.0

Первый опубликованный выпуск. 0.1.0 так и не покинула дерево.

- `SoloListenable<S>`: `Solo<S>`, который служит ещё и `ValueListenable<S>`,
  для `ValueListenableBuilder`, `ListenableBuilder`, `AnimatedBuilder`
  и `Listenable.merge`. Слушатели вызываются синхронно, в порядке подписки,
  на каждое изменение состояния; `stream` у `Solo` по-прежнему работает
  и приходит на микротаску позже.
- Намеренно только для чтения: `value` и `state` отдают один и тот же объект,
  а сеттера нет, потому что состояние принадлежит задачам.
- `close()` отменяет то, что идёт, отбрасывает всех слушателей и навсегда
  перестаёт уведомлять; ничто другое контроллер за вас не закрывает.
- Реэкспортирует `package:solo/solo.dart`, который реэкспортирует
  `package:async_job/async_job.dart`, поэтому `flutter_solo` остаётся
  единственной зависимостью, которую добавляет приложение, и единственным
  импортом, который оно пишет.
- Нижняя граница: `solo: ^0.2.0`, чьим ядром задач служит `async_job: ^0.2.0`
  с синхронной регистрацией `job.whenCancelled(callback)`.

## 0.1.0

Не публиковалась.
