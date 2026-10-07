# Пример камеры

Контроллер камеры управляет устройством: каждая операция занимает время,
устройство может сломаться само, а закрывать его приходится намеренно. Эта
страница собирает такой контроллер по одному решению за раз: правила состояния,
политики очереди, освобождение устройства. Заканчивается она кодом запускаемого
пакета [`example/`](../../../packages/solo/example): последний фрагмент каждого
метода ниже повторяет его код в `example/lib/src/camera_controller.dart`, если
не считать комментариев.

Состояния:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final Point<double>? focusPoint;
  final bool paused;

  const Ready({this.zoom = 1, this.focusPoint, this.paused = false});

  Ready copyWith({double? zoom, Point<double>? focusPoint, bool? paused}) =>
      Ready(
        zoom: zoom ?? this.zoom,
        focusPoint: focusPoint ?? this.focusPoint,
        paused: paused ?? this.paused,
      );
}

final class Broken extends NotDisposed {
  final Object error;

  const Broken(this.error);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

`NotDisposed` объединяет все состояния, в которых с устройством ещё можно
работать, а в `Disposed` уже нельзя. В `Broken` попадает сбой устройства;
`Failed` это состояние не назвали, потому что так называется исход. В примере
каждое состояние ещё и печатает себя, и этот текст показывают журналы ниже;
а два `Ready` с одинаковыми полями там равны.

`null`, переданный в `copyWith`, оставляет старое значение, поэтому `copyWith`
не может очистить `focusPoint`, где `null` означает автоматический фокус.
`resetFocusPoint` в примере публикует новый `Ready` и сохраняет в нём текущий
масштаб.

Устройством служит `FakeCameraHardware` из примера, и контроллер держит его
в поле `hw`. Каждая операция занимает десять миллисекунд, съёмка занимает
тридцать и возвращает `Photo`. `failures` заставляет названную операцию упасть
после её задержки, `fail` сообщает о сбое вне всякой задачи и для этого
вызывает `onError`, колбэк, который ставит контроллер, а `log` записывает, где
каждая операция начинается и кончается.

Журналы ниже печатает для этого кода наблюдатель примера: задача `started`,
`finished` с исходом или `dropped` до старта, `error`, о которой она сообщила,
строка `log`, каждая смена `state:` и `closed`, когда контроллер закрылся.
Задача названа своим ключом, значением перечисления `CameraKey` из примера,
а за ним идёт текст её `describe`, если он есть: `[setZoom: zoom: 2.0]`. Строки
дочерней задачи начинаются с `>`.

Разделы открываются версией, к которой ведёт словарь API: рабочим типом,
названным по состоянию, из которого задача стартует, политикой по умолчанию,
освобождением, поставленным в очередь как любая другая задача. Под ней
показано, что этот код делает. Если версия, которая это чинит, всё ещё
ошибается, она стоит второй попыткой. Версия, которую использует пример, идёт
под своим заголовком. В разделе о командах, пришедших во время снимка,
ошибаться не на чем, и он открывается ответом.

## Открытие камеры

`init` публикует `Preparing`, открывает устройство и публикует `Ready`.
Стартовать эта задача может только из `Initial`.

### Первая попытка

```dart
Job<void> init() => run<Initial, void>(
      key: CameraKey.init,
      policy: Policy.droppable,
      (ctx) async {
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        ctx.emit(const Ready());
      },
    );
```

```text
[init] started
state: Preparing()
[init] finished Cancelled(rules: is not Initial)
```

Рабочий тип задаёт состояние, которого правила задачи требуют, пока она идёт,
и `run<Initial, void>` требует `Initial`. Первый же `emit` тела из него уходит,
и задача кончается `Cancelled` раньше, чем `hw.open` вообще вызван: журнал
устройства остаётся пустым. Контроллер остаётся в `Preparing`, и следующая
`init()` отбрасывается на старте по той же причине: открыть камеру больше
нельзя вовсе.

### Рабочий тип пошире

```dart
Job<void> init() => run<NotDisposed, void>(
      key: CameraKey.init,
      policy: Policy.droppable,
      canStart: (state) => state is Initial,
      (ctx) async {
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        ctx.emit(const Ready());
      },
    );
```

`NotDisposed` нужен телу на всём его протяжении: `Preparing` и `Ready` оба
в него входят, и публикации остаются внутри правил. Откуда задача может
стартовать, решается отдельно, и на этот вопрос отвечает `canStart`. Без него
вторая `init()` на уже открытой камере запускается снова и открывает устройство
второй раз. С ним вызов кончается до старта:

```text
[init] dropped Cancelled(rules: canStart)
```

Вторая `init()`, вызванная, пока первая ещё идёт, до этого не доходит:
`Policy.droppable` отдаёт ей ту `Job`, что уже в работе, и устройство
открывается один раз.

## Открытие, которое не удалось

Устройство может отказаться открываться, пока камеру держит другое приложение,
а задачу могут отменить посреди открытия. В обоих случаях контроллер должен
оказаться в состоянии, из которого камеру можно будет открыть позже.

### Первая попытка

```dart
(ctx) async {
  ctx.emit(const Preparing());
  try {
    await ctx.join(hw.open);
  } on Object catch (error) {
    ctx.emit(Broken(error));
    rethrow;
  }
  ctx.emit(const Ready());
},
```

Сбой попадает куда нужно: `catch` публикует `Broken`, и задача кончается
`Failed`. Отмена проходит через тот же `catch`, и там `emit` ничего
не публикует. На уже отменённой задаче он работает точкой проверки и вместо
публикации бросает `Cancelled`:

```text
[init] started
state: Preparing()
[init] finished Cancelled(manual)
```

`join` дождался открытия, так что устройство открыто, а состояние говорит, что
оно ещё открывается. Из `Preparing` не стартует ни один из двух способов
открыть камеру: `init` хочет `Initial`, а `reopen`, обратный путь примера,
хочет `Ready` или `Broken`. Это ловушка из раздела
[«Состояние после ошибки или отмены»](state.md#состояние-после-ошибки-или-отмены)
страницы о состоянии, только за спиннером стоит устройство.

### Обработчики run

```dart
Job<void> init() => run<NotDisposed, void>(
      key: CameraKey.init,
      policy: Policy.droppable,
      canStart: (state) => state is Initial,
      onError: (state, error, stackTrace) => Broken(error),
      onCancel: (state, cancelled) => Broken(cancelled),
      (ctx) async {
        ctx.emit(const Preparing());
        await ctx.join(hw.open);
        ctx.emit(const Ready());
      },
    );
```

Обработчики вычисляют состояние, когда тело уже закончилось, поэтому отмена
доходит до своего обработчика, а не до отклонённого `emit`. И сбой, и отмена
приводят в `Broken`, а оттуда стартует `reopen`:

```text
[init] started
state: Preparing()
[init] error Bad state: camera in use
state: Broken(Bad state: camera in use)
[init] finished Failed(Bad state: camera in use)
```

```text
[init] started
state: Preparing()
state: Broken(Cancelled(manual))
[init] finished Cancelled(manual)
```

Задача, отброшенная до старта, не доходит ни до одного обработчика, так что
вторая `init()` из раздела выше по-прежнему кончается одной строкой `dropped`.
У `reopen` те же два обработчика.

## Только последний масштаб

Щипок запрашивает масштаб на каждом кадре, и важен только последний запрос.

### Первая попытка

```dart
Job<void> setZoom(double zoom) => run<Ready, void>(
      key: CameraKey.setZoom,
      describe: () => 'zoom: $zoom',
      (ctx) async {
        await ctx.join(() => hw.setZoom(zoom));
        ctx.emit(ctx.state.copyWith(zoom: zoom));
      },
    );
```

Три вызова в одном такте, `setZoom(2)`, `setZoom(3)` и `setZoom(4)`,
заканчиваются на `Ready(zoom: 4.0, focusPoint: null, paused: false)`, как
и версия ниже: по состоянию их не различить. Устройство различает. Каждый
запрос ждёт в очереди и доходит до объектива:

```text
zoom 2.0: begin
zoom 2.0: end
zoom 3.0: begin
zoom 3.0: end
zoom 4.0: begin
zoom 4.0: end
```

### Policy.replace

```dart
Job<void> setZoom(double zoom) => run<Ready, void>(
      key: CameraKey.setZoom,
      policy: Policy.replace,
      describe: () => 'zoom: $zoom',
      canStart: (state) => !state.paused,
      (ctx) async {
        await ctx.join(() => hw.setZoom(zoom));
        ctx.emit(ctx.state.copyWith(zoom: zoom));
      },
    );
```

`replace` отбрасывает ждущую задачу с тем же ключом и только потом ставит
в очередь новую, так что те же три вызова доходят до устройства один раз:

```text
[setZoom: zoom: 2.0] dropped Cancelled(replaced)
[setZoom: zoom: 3.0] dropped Cancelled(replaced)
[setZoom: zoom: 4.0] started
state: Ready(zoom: 4.0, focusPoint: null, paused: false)
[setZoom: zoom: 4.0] finished Done(null)
```

Задача, которая уже идёт, доработает. Если `setZoom(3)` и `setZoom(4)`
приходят, пока масштаб 2 ещё выставляется, объектив всё равно встанет на 2,
запрос на 3 отбрасывается, а потом объектив встаёт на 4. `canStart` не даёт
камере на паузе принять команду вовсе.

## Команды, пришедшие во время снимка

```dart
Job<Photo> takePhoto() => run<Ready, Photo>(
      key: CameraKey.takePhoto,
      policy: Policy.droppable,
      canStart: (state) => !state.paused,
      (ctx) async {
        final photo = await ctx.join(hw.capture);
        queue.clear();
        ctx.log('captured $photo');
        return photo;
      },
    );
```

Съёмка занимает втрое больше других операций, и команды, запрошенные тем
временем, ждут в очереди. Этот пример считает их частью снимка: когда снимок
готов, `queue.clear()` их отбрасывает. Масштаб, запрошенный на пятой
миллисекунде съёмки:

```text
[takePhoto] started
[setZoom: zoom: 3.0] dropped Cancelled(manual)
[takePhoto] log captured Photo#1
[takePhoto] finished Done(Photo#1)
```

Без очистки этот масштаб выставляется, когда снимок закончен. `queue.clear()`
не трогает работающую задачу, а работает здесь сам снимок. Не трогает очистка
и неотменяемые задачи, а таких этот контроллер ставит в очередь один вид,
освобождение.

## Освобождение камеры

`dispose()` закрывает устройство и публикует `Disposed`, чем бы камера ни была
занята в момент вызова.

### Первая попытка

```dart
Job<void> dispose() => run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      canStart: (state) => state is! Disposed,
      (ctx) async {
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob());
        }
        ctx.emit(const Disposed());
      },
    );

Job<void> _closeCameraJob() => job<NotDisposed, void>(
      key: CameraKey.closeCamera,
      cancellable: false,
      (ctx) async => hw.close(),
    );
```

Вызванное, пока масштаб выставляется, а за ним ждёт снимок, это освобождение
встаёт в конец очереди:

```text
[setZoom: zoom: 2.0] started
state: Ready(zoom: 2.0, focusPoint: null, paused: false)
[setZoom: zoom: 2.0] finished Done(null)
[takePhoto] started
[takePhoto] log captured Photo#1
[takePhoto] finished Done(Photo#1)
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
```

Всё, что стоит перед ним, по-прежнему выполняется, и камера делает снимок уже
после того, как ей велели выключаться. `cancellable: false` при этом верен:
отменить задачу после старта нельзя, как и её дочернюю задачу, закрывающую
устройство, так что устройство никогда не остаётся закрытым наполовину.

### Вторая попытка

```dart
Job<void> dispose() {
  queue.clear();
  current?.cancel();
  return run<CameraState, void>(
    key: CameraKey.dispose,
    policy: Policy.droppable,
    cancellable: false,
    canStart: (state) => state is! Disposed,
    (ctx) async {
      if (ctx.state is! Initial) {
        await ctx.run(_closeCameraJob());
      }
      ctx.emit(const Disposed());
    },
  );
}
```

```text
[setZoom: zoom: 2.0] started
[takePhoto] dropped Cancelled(manual)
[setZoom: zoom: 2.0] finished Cancelled(manual)
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
```

`queue.clear()` отбрасывает то, что не стартовало, и снимок до устройства
не доходит. `current?.cancel()` просит идущую установку масштаба остановиться,
и объектив всё равно встаёт на 2: масштаб ждёт через `join`, а он выпускает
задачу только тогда, когда начатая операция закончилась. Каждый метод ожидания
показывает таблица в начале страницы [«Отмена»](cancellation.md). Отмена
экономит остаток тела: масштаб не публикует состояния для камеры, которую
вот-вот закроют, и освобождение стартует, как только устройство свободно.

Изъян виден на вызове после конца освобождения. Он ставит в очередь свою
задачу, и `canStart` отбрасывает её до старта:

```text
[dispose] dropped Cancelled(rules: canStart)
```

Камера освобождена, а вызывающему сказано, что освобождение отменено.

### Проверка в теле

```dart
Job<void> dispose() {
  queue.clear();
  current?.cancel();
  return run<CameraState, void>(
    key: CameraKey.dispose,
    policy: Policy.droppable,
    cancellable: false,
    (ctx) async {
      if (ctx.state is Disposed) {
        return;
      }
      if (ctx.state is! Initial) {
        await ctx.run(_closeCameraJob());
      }
      ctx.emit(const Disposed());
    },
  );
}
```

```text
[dispose] started
[dispose] finished Done(null)
```

Тот же вызов теперь стартует, видит освобождённую камеру и кончается `Done`;
журнал устройства остаётся пустым. `canStart` нужен задаче, которой в каком-то
состоянии выполняться нельзя, а освобождению освобождённой камеры можно: ему
просто нечего делать.

Очистка не принудительная. Освобождение, которое ещё стоит в очереди, её
переживает, потому что оно неотменяемое, и `Policy.droppable` отдаёт его
второму вызову: два `dispose()` подряд получают одну и ту же `Job`, и оба
вызывающих видят `Done`. `queue.clear(force: true)` вместо этого отбросил бы ту
задачу, и её вызывающий получил бы `Cancelled(manual)` за камеру, которая
всё-таки освобождена.

## Закрытие контроллера

После освобождения сам контроллер отпускается через `close()`.

### Первая попытка

```dart
camera.dispose();
await camera.close();
```

```text
[dispose] dropped Cancelled(closed)
closed
```

`close()` смотрит на то, где задача стоит, а не на её флаг. Идущую задачу он
ждёт, и неотменяемая доходит до конца. Задача, которая ещё в очереди,
не стартует вовсе: `close()` завершает её с `Cancelled(closed)`, отменяемая она
или нет, и тот, кто её ждёт, сразу получает этот исход, как описывает раздел
[«Отмена работы и закрытие контроллера»](cancellation.md#отмена-работы-и-закрытие-контроллера)
страницы об отмене. `dispose()` поставил задачу в очередь, `close()` пришёл
в том же такте, и освобождение кончилось, не выйдя из очереди. В журнале
устройства нет `close`. Камера остаётся открытой, состояние всё ещё говорит
`Ready`, а контроллер, который мог бы её закрыть, закрыт сам.

### Вторая попытка

```dart
camera.dispose();
await camera.close(mode: SoloCloseMode.drain);
```

`SoloCloseMode.drain` выполняет очередь перед закрытием, и освобождение вместе
с ней: устройство закрывается, состояние становится `Disposed`. Изъян виден,
когда устройство не закрывается:

```text
[dispose] started
> [closeCamera] started
> [closeCamera] error Bad state: close timed out
> [closeCamera] finished Failed(Bad state: close timed out)
[dispose] error Bad state: close timed out
[dispose] finished Failed(Bad state: close timed out)
closed
```

Освобождение упало, камера всё ещё открыта, а контроллер закрылся сразу после
него, и второй `dispose()` возвращается `Cancelled(closed)`. Исход первого
никто не читает, поэтому его провал уходит в зону необработанной ошибкой, как
описывает раздел
[«Обработанные и необработанные ошибки»](errors.md#обработанные-и-необработанные-ошибки)
страницы об ошибках. Провал приходит туда, где с ним уже ничего не сделать.

### Дождаться освобождения

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().value;

camera.setZoom(2); // await не нужен, и линта об этом нет

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
    await camera.close();
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}
```

`close()` стоит в ветке `Done`: освобождение заканчивается до его вызова,
и `close()` нечего отменять.

`Failed` надо обработать: закрытие, которое упало, освобождением не считается.
`ctx.run` бросает то, что бросила дочерняя задача, тело не доходит
до `emit(Disposed())`, и состояние остаётся прежним. Код выше в этом случае
оставляет контроллер открытым, так что второй `dispose()` может попробовать
снова. `Cancelled` в этом коде не возвращается. Стартовавшее освобождение
отклоняет любую отмену; ждущее из очереди забирают только `close()` или
принудительное удаление вроде `queue.clear(force: true)`, а здесь
ни то ни другое не вызывается, пока исход не пришёл. `switch` называет этот
случай, потому что исход всегда один из трёх. Возвращается `Cancelled`, когда
`close()` успевает первым, как в первой попытке, или когда контроллер закрыли
раньше, чем вызвали `dispose()`.

`init().value` ничего не возвращает. Ждут его потому, что он бросает, когда
камера не открылась, и код останавливается на этом месте с ошибкой открытия.
`setZoom(2)` не ждут: `Job` не реализует `Future`, и `unawaited_futures`
сказать о ней нечего. Исход этого масштаба никто не читает, поэтому его провал
ушёл бы в зону, как провал освобождения во второй попытке;
`camera.setZoom(2).ignoreFailure()` вместо этого оставляет отчёт хукам. Снимок
ждёт в очереди за масштабом, и `value` отдаёт его фотографию или бросает, если
снимок упал или отменён.

## Сбой после освобождения

Устройство сообщает о сбое само, и контроллер превращает это сообщение
в `Broken`. Когда камера освобождена, сообщение не должно ничего менять:
контроллер заканчивает на `Disposed`.

### Первая попытка

```dart
CameraController(this.hw) : super(const Initial()) {
  hw.onError = (error) => externalSetState(Broken(error));
}
```

Слушатель поставлен, и его никто не снимает. Камеру освобождают, а контроллер
закрывают, как в разделе [«Дождаться освобождения»](#дождаться-освобождения),
и между этими шагами, после `Disposed` и до `close()`, устройство сообщает
о сбое:

```text
[dispose] started
> [closeCamera] started
> [closeCamera] finished Done(null)
state: Disposed()
[dispose] finished Done(null)
state: Broken(Bad state: cable pulled)
```

Освобождение решило, каким будет последнее состояние, а следующее сообщение
устройства его заменило. После `close()` то же сообщение состояния не меняет:
состояние закрытого контроллера окончательно, так что `externalSetState`
бросает `StateError`, и бросает его в собственный колбэк устройства.

### Вторая попытка

```dart
@override
void onClose() => hw.onError = null;
```

Гасить источник в `onClose` советует раздел
[«externalSetState»](state.md#externalsetstate) страницы о состоянии: движок
вызывает `onClose` один раз, когда последняя задача закончилась, а контроллер
вот-вот закончит закрытие. Сообщение, пришедшее после `close()`, теперь
не находит слушателя, и ничего не бросается. Сообщение из журнала выше пришло
до `close()`, и эта версия печатает тот же журнал: камера заканчивает со своим
устройством, когда её освобождают, а контроллер закрывается после этого.

### Сначала отключить источник

```dart
Job<void> dispose() {
  hw.onError = null;
  queue.clear();
  current?.cancel();
  return run<CameraState, void>(
    key: CameraKey.dispose,
    policy: Policy.droppable,
    cancellable: false,
    (ctx) async {
      if (ctx.state is Disposed) {
        return;
      }
      if (ctx.state is! Initial) {
        await ctx.run(_closeCameraJob());
      }
      ctx.emit(const Disposed());
    },
  );
}
```

Слушатель уходит раньше всего остального, так что последнее состояние решает
одно освобождение, а сбою, о котором устройство сообщит после него, сообщать
некому. Камера остаётся `Disposed`. Упавшее освобождение слушателя тоже
не возвращает: пока второй `dispose()` не пройдёт, контроллер своё устройство
не слышит. `onClose` остаётся в примере для контроллера, который закрывают без
освобождения.

## Запуск примера

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```

`bin/main.dart` открывает камеру, меняет масштаб, выставляет точку фокуса,
начинает снимок и освобождает камеру посреди него, печатая журнал по ходу дела.
В примере есть ещё `reopen`, `pause`, `resume` и операции фокуса, и его тесты
проходят каждую из них.
