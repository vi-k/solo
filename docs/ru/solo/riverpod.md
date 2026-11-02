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

Экран открывает камеру и уходит через 10 мс, пока устройство ещё открывается:

```text
screen left
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

Тот же экран уходит через 10 мс. `outcome` — исход задачи, которую вернул
`open()`, `states` — состояния, которые видел экран, а `device` — то, что стало
с устройством:

```text
screen left
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
