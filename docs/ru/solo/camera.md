# Пример камеры

Следующий пример объединяет правила состояния, политики очереди и явное
освобождение устройства. Он использует свою иерархию состояний, отдельную от
примера профиля. `NotDisposed` объединяет все состояния, в которых ещё
разрешена работа с устройством:

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
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

`FakeCameraHardware` и `Photo` определены в запускаемом пакете
[`example/`](../../../packages/solo/example). Контроллер ниже показывает
основные операции:

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

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

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
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
}
```

`init` начинается только из `Initial`, но использует `NotDisposed` как рабочий
тип, чтобы продолжить после публикации `Preparing`. `setZoom` заменяет
ожидающие запросы масштаба и позволяет работающему запросу закончиться.

После снимка `takePhoto` удаляет отменяемые команды из очереди. Этот пример
считает команды, накопленные во время съёмки, относящимися к этой съёмке;
очистка не даёт применить их к следующей. Работающую `Job` `queue.clear()` не
затрагивает.

`dispose()` является операцией приложения, которая закрывает устройство и
публикует `Disposed`. Она очищает ожидающую работу и запрашивает отмену
работающей `Job`, после чего ставит в очередь собственную неотменяемую `Job`
освобождения. Ребёнок `_closeCameraJob` также отклоняет обычную отмену.
`close()` контроллера является отдельной операцией жизненного цикла, поэтому
сначала дождитесь освобождения устройства:

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

Запускаемый пример расширяет контроллер состоянием `Broken`, повторным
открытием, паузой, возобновлением и фокусировкой. Фейковое устройство отвечает
с задержкой и может сломаться независимо. Тесты проверяют упорядоченные журналы
событий, а `bin/main.dart` печатает такой журнал во время выполнения сценария:

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
