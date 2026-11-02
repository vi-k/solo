# solo под riverpod

Приложение на riverpod остаётся на riverpod: граф провайдеров, кеш,
`AsyncValue`, по которому ветвится экран. Эта страница о том, что встаёт под
провайдер, когда у работы в нём есть порядок, который надо держать, и ресурс,
который надо закрыть. Контроллер `solo` живёт в провайдере: провайдер его
создаёт, экран читает через провайдер его состояние, а освобождение провайдера
контроллер закрывает. Код идёт на riverpod 3, на чистом Dart:
`flutter_riverpod` даёт тот же `Ref`.

Каждый раздел открывается версией, к которой ведёт документация самого
riverpod, и показывает, что этот код делает. Состояния и трассы под
фрагментами — то, что код печатает при запуске.

## Контроллер под провайдером

Контроллер — камера. `open()` публикует `Opening`, открывает устройство
и публикует `Ready` с ним:

```dart
sealed class CameraState {
  const CameraState();
}

final class Closed extends CameraState {
  const Closed();
}

final class Opening extends CameraState {
  const Opening();
}

final class Ready extends CameraState {
  const Ready(this.device);

  final Device device;
}
```

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Closed());

  Job<void> open() => enqueue<CameraState, void>(
    key: #camera,
    policy: Policy.restart,
    ifCancelled: (state, cancelled) => const Closed(),
    (ctx) async {
      ctx.emit(const Opening());
      final device = await ctx.join(
        Device.open,
        discard: (device) => device.close(),
      );
      ctx.emit(Ready(device));
    },
  );
}
```

`Device` изображает камеру платформы: открытие занимает 50 мс, а `close()` её
освобождает. `ctx.join` ждёт открытия, даже если задачу тем временем отменили,
а его `discard` закрывает устройство, которое пришло к задаче, не закончившейся
`Done`. `ifCancelled` возвращает камеру в `Closed`, когда задачу отменяют, —
следующим `open()` при `Policy.restart` или `close()` контроллера. В трассах
устройство названо номером: `Ready(1)` держит первое открытое.

Провайдер создаёт контроллер и закрывает его при освобождении. Экрану нужно
и состояние, а контроллер зовёт своих слушателей при каждом изменении.
`ref.notifyListeners` — то, что riverpod даёт провайдеру, чей объект меняется
на месте, поэтому слушателем контроллера становится этот вызов.

### Первая попытка

```dart
// Первая попытка: контроллер зовёт уже освобождённый Ref.
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() => unawaited(controller.close()));
  return controller;
});
```

Экран открывает камеру и уходит через 10 мс, пока устройство ещё открывается.
`outcome` — исход задачи, которую вернул `open()`, `states` — состояния,
которые видел экран, а `device` — то, что стало с устройством:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
zone: Cannot use the Ref of Provider<Camera> after it has been disposed.
```

Экран был последним слушателем провайдера, поэтому riverpod освобождает
провайдер, а `onDispose` закрывает контроллер. `close()` отменяет открытие,
и его `ifCancelled` публикует `Closed`. Слушатель контроллера — всё ещё
`ref.notifyListeners` у `Ref`, освобождённого мгновением раньше; вызов бросает,
а ошибку слушателя контроллер отдаёт зоне.

### Снятие слушателя

```dart
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() {
    controller.removeListener(ref.notifyListeners);
    unawaited(controller.close());
  });
  return controller;
});

// Экран: ref.watch(camera.select((camera) => camera.currentState))
```

Тот же экран уходит через 10 мс:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
```

Слушатель уходит раньше, чем закрывается контроллер, и `Closed` отмены
не доходит ни до кого: экран ушёл вместе с провайдером. `removeListener`
сравнивает через `==`, а два отрыва метода `ref.notifyListeners` равны, поэтому
второе упоминание метода снимает то, что добавила первая строка.

Экран читает состояние через `select`: сам провайдер ничего не меняет, а только
оповещает, и `select` отдаёт экрану каждый новый `currentState`.
`StreamProvider` над потоком `SoloStream` не подошёл бы: поток несёт изменения,
а не состояние, в котором камера находится, когда экран подписывается.
Во Flutter экран может и взять контроллер через `ref.watch(camera)`, и строить
по нему `SoloBuilder`
из [`flutter_solo`](https://pub.dev/packages/flutter_solo).

## Камера, которую закрывают при уходе экрана

Экран открывает камеру, когда появляется, и закрывает её, когда уходит,
в какой бы момент это ни случилось: пока устройство ещё открывается или после
того, как оно открылось. Без контроллера riverpod держит устройство
в собственном провайдере и закрывает его в `onDispose`.

### Первая попытка

```dart
// Первая попытка: уборка регистрируется после await.
final camera = FutureProvider.autoDispose<Device>((ref) async {
  final device = await Device.open();
  ref.onDispose(device.close);
  return device;
});
```

Экран уходит через 10 мс, пока устройство открывается:

```text
screen left at 10 ms
device: open 1 start, open 1 done
```

Устройство остаётся открытым, и никто об этом не сообщает. riverpod освобождает
провайдер, когда экран уходит, а `onDispose`, который закрыл бы устройство, ещё
не зарегистрирован: строка, которая его регистрирует, ждёт за `await`. Когда
открытие кончается, провайдера уже нет.

### Флаг до await

Руководство riverpod по [отмене](https://riverpod.dev/docs/how_to/cancel) велит
провайдеру отметить своё освобождение до первого `await` и проверить отметку
после него:

```dart
final camera = FutureProvider.autoDispose<Device>((ref) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final device = await Device.open();
  if (disposed) {
    await device.close();
    throw StateError('the screen left while the camera opened');
  }
  ref.onDispose(device.close);
  return device;
});
```

Экран уходит через 10 мс, а затем, со свежим провайдером, через 80 мс:

```text
screen left at 10 ms
device: open 1 start, open 1 done, close 1
screen left at 80 ms
device: open 1 start, open 1 done, close 1
```

Это работает: устройство закрывается по обе стороны открытия. Уборка живёт
в двух местах, в проверке после `await` и в `onDispose` следом за ней,
а порядок держит автор: флаг регистрируется до `await`.

### Уход после открытия камеры

Под контроллером из первого раздела уход во время открытия устройство
закрывает: `discard` забирает устройство, которое пришло к отменённой задаче.
Тот же экран уходит через 80 мс, после открытия:

```text
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done
```

Устройство остаётся открытым. `close()` отменяет задачи контроллера, а открытие
к этому времени кончилось `Done`: отменять уже нечего. Устройство в `Ready`
теперь принадлежит контроллеру, а не задаче, и `close()` его не закрывает.

### onClose

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Closed());

  Job<void> open() => enqueue<CameraState, void>(
    key: #camera,
    policy: Policy.restart,
    ifCancelled: (state, cancelled) => const Closed(),
    (ctx) async {
      ctx.emit(const Opening());
      final device = await ctx.join(
        Device.open,
        discard: (device) => device.close(),
      );
      ctx.emit(Ready(device));
    },
  );

  @override
  void onClose() {
    if (currentState case Ready(:final device)) {
      unawaited(device.close());
    }
  }
}
```

Экран уходит через 10 мс, а затем, со свежим провайдером, через 80 мс:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done, close 1
```

`onClose` выполняется один раз, когда все задачи контроллера закончились,
и закрывает устройство, которое держит состояние. Уход во время открытия идёт
как раньше: задача кончается `Cancelled`, `ifCancelled` публикует `Closed`,
а `discard` закрывает устройство. Ни флаг, ни порядок регистраций автору
держать не нужно: гонку ухода с открытием держит `discard` в месте, где
устройство берётся, а то, что контроллер держит после этого, — `onClose`.
Контроллер, у которого закрытие — отдельная задача, ждущая оборудование,
разобран в разделе [Освобождение камеры](camera.md#освобождение-камеры).
