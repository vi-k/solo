# Пример камеры

Камера — это контроллер над устройством: каждая операция занимает время,
устройство может сломаться само, а закрывать его приходится намеренно. Эта
страница собирает такой контроллер по одному решению за раз — правила
состояния, политики очереди, освобождение устройства — и заканчивается кодом
запускаемого пакета [`example/`](../../../packages/solo/example): последний
фрагмент каждого метода ниже — его код
в `example/lib/src/camera_controller.dart`, если не считать комментариев.

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
работать, а `Disposed` — то, в котором уже нельзя. `Broken` — то, куда попадает
сбой устройства; он не назван `Failed`, потому что так называется исход.
В примере каждое состояние ещё и печатает себя, и этот текст — то, что
показывают журналы ниже.

`null`, переданный в `copyWith`, оставляет старое значение, поэтому `copyWith`
не может очистить `focusPoint`, где `null` означает автоматический фокус.
`resetFocusPoint` в примере публикует новый `Ready` и сохраняет в нём текущий
масштаб.

Устройство — `FakeCameraHardware` из примера. Каждая операция занимает десять
миллисекунд, а съёмка — тридцать; `failures` заставляет названную операцию
упасть после её задержки, `onError` сообщает о сбое вне всякой `Job`, а `log`
записывает, где каждая операция начинается и кончается. Журналы ниже — то, что
печатает для этого кода наблюдатель примера: `Job` `started`, `finished`
с исходом или `dropped` до старта, `error`, о которой она сообщила, строка
`log` и каждая смена `state:`. Строки дочерней `Job` начинаются с `>`.

Разделы открываются версией, к которой ведёт словарь API, — рабочим типом,
названным по состоянию, из которого `Job` стартует, политикой по умолчанию,
освобождением, поставленным в очередь как любая другая `Job`, — показывают, что
этот код делает, и потом дают версию, которую использует пример. В разделе
о командах, пришедших во время снимка, ошибаться не на чем, и он открывается
ответом.

## Открытие камеры

`init` публикует `Preparing`, открывает устройство и публикует `Ready`.
Стартовать она может только из `Initial`.

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

Рабочий тип — это состояние, которого правила `Job` требуют, пока она идёт,
и `run<Initial, void>` требует `Initial`. Первый же `emit` тела из него уходит,
и `Job` кончается `Cancelled` раньше, чем `hw.open` вообще вызван: журнал
устройства остаётся пустым. Контроллер остаётся в `Preparing`, и следующая
`init()` отбрасывается на старте по той же причине — открыть камеру больше
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

`NotDisposed` — то, что нужно телу на всём его протяжении: `Preparing`
и `Ready` оба в него входят, и публикации остаются внутри правил. Откуда `Job`
может стартовать — отдельный вопрос, и на него отвечает `canStart`. Без него
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
а `Job` могут отменить посреди открытия. В обоих случаях контроллер должен
оказаться в состоянии, из которого что-то может стартовать, чтобы камеру можно
было открыть позже.

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

Сбой попадает куда нужно: `catch` публикует `Broken`, и `Job` кончается
`Failed`. Отмена проходит через тот же `catch`, и там `emit` ничего
не публикует. На уже отменённой `Job` он — точка проверки и вместо публикации
бросает `Cancelled`:

```text
[init] started
state: Preparing()
[init] finished Cancelled(manual)
```

`join` дождался открытия, так что устройство открыто, а состояние говорит, что
оно ещё открывается. Из `Preparing` не стартует ничего: `init` хочет `Initial`,
а `reopen`, обратный путь примера, — `Ready` или `Broken`. Это ловушка
из [Состояния после ошибки или отмены](state.md#состояние-после-ошибки-или-отмены),
только за спиннером стоит устройство.

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

`Job`, отброшенная до старта, не доходит ни до одного обработчика, так что
вторая `init()` из раздела выше по-прежнему кончается одной строкой `dropped`.
`reopen` приземляется так же.

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
запрос ждёт своей очереди и доходит до объектива:

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

`replace` отбрасывает ждущую `Job` с тем же ключом и встаёт на её место, так
что те же три вызова доходят до устройства один раз:

```text
[setZoom: zoom: 2.0] dropped Cancelled(manual)
[setZoom: zoom: 3.0] dropped Cancelled(manual)
[setZoom: zoom: 4.0] started
state: Ready(zoom: 4.0, focusPoint: null, paused: false)
[setZoom: zoom: 4.0] finished Done(null)
```

`Job`, которая уже идёт, доработает. Если `setZoom(3)` и `setZoom(4)` приходят,
пока масштаб 2 ещё выставляется, объектив всё равно встанет на 2, запрос на 3
отбрасывается, а потом объектив встаёт на 4. `canStart` не даёт камере на паузе
принять команду вовсе.

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
не трогает работающую `Job`, а работающая `Job` здесь — сам снимок. Не трогает
она и неотменяемые `Job`, а таких этот контроллер ставит в очередь один вид —
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
после того, как ей велели выключаться. Сама `Job` при этом верна: отменить её
после старта нельзя, как и её дочернюю `Job`, закрывающую устройство, так что
устройство никогда не остаётся закрытым наполовину.

### Расчистить дорогу

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
`Job` только тогда, когда начатая операция закончилась, — таблица в начале
[Отмены](cancellation.md) показывает каждый метод ожидания. Отмена экономит
остаток тела: масштаб не публикует состояния для камеры, которую вот-вот
закроют, и освобождение стартует, как только устройство свободно.

Очистка не принудительная. Освобождение, которое ещё стоит в очереди, её
переживает, потому что оно неотменяемое, и `Policy.droppable` отдаёт его
второму вызову: два `dispose()` подряд получают одну и ту же `Job`, и оба
вызывающих видят `Done`. `queue.clear(force: true)` вместо этого отбросил бы ту
`Job`, и её вызывающий получил бы `Cancelled(manual)` за камеру, которая
всё-таки освобождена.

По той же причине `Disposed` проверяется в теле, а не в `canStart`. Вызов после
конца освобождения ставит свою `Job`, и проверка сразу завершает её `Done`.
`canStart: (state) => state is! Disposed` отбросил бы эту `Job` до старта, и её
вызывающий получил бы `Cancelled(rules: canStart)`.

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

`cancellable: false` отклоняет `cancel()`. Он не удерживает `Job`
в контроллере, который закрывается раньше, чем она стартовала: `dispose()`
поставил `Job` в очередь, `close()` пришёл в том же такте и завершил каждую
ждущую `Job` с `Cancelled(closed)`, как описывает
[Отмена работы и закрытие контроллера](cancellation.md#отмена-работы-и-закрытие-контроллера).
В журнале устройства нет `close`. Камера остаётся открытой, состояние всё ещё
говорит `Ready`, а контроллер, который мог бы её закрыть, закрыт сам.

### Дождаться освобождения

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // await не нужен, и линта об этом нет

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

Освобождение заканчивается до вызова `close()`, и `close()` нечего отменять.
Освобождению, которое уже стартовало, `close()` тоже не страшен: `close()` ждёт
идущую `Job`, а неотменяемая `Job` доходит до конца.

`Failed` — случай, который надо обработать: закрытие, которое упало, —
не освобождение. `ctx.run` бросает то, что бросила дочерняя `Job`, тело
не доходит до `emit(Disposed())`, и состояние остаётся прежним. `Cancelled`
возвращает контроллер, закрытый раньше, чем вызвали `dispose()`.

`setZoom(2)` не ждут: `Job` — не `Future`, и `unawaited_futures` сказать о ней
нечего. Снимок ждёт в очереди за масштабом, и `value` отдаёт его фотографию —
или бросает, если снимок упал или отменён.

## Сбой после освобождения

Устройство сообщает о сбое само, и контроллер превращает его в `Broken`:

```dart
CameraController(this.hw) : super(const Initial()) {
  hw.onError = (error) => externalSetState(Broken(error));
}
```

### Первая попытка

Освобождение из раздела выше, а слушатель оставлен на месте. Устройство
сообщает о сбое после `Disposed` и до `close()`:

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
одно освобождение, а сбою, о котором устройство сообщит после него — или после
`close()`, — сообщать некому. Камера остаётся `Disposed`.

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
