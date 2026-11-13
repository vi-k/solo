# Приложение устройства

Приложение камеры с двумя экранами. Главный экран показывает последний снимок
или видео. На экране камеры — превью и кнопки снимка, видео, вспышки и смены
камеры. Камера — плагин `camera`, и экран владеет ею через `CameraSession`,
`Solo<CameraState>`. Каждая команда занимает на телефоне время, телефон может
забрать камеру, а камеру нужно отпустить, прежде чем её откроет следующий
экран.

Разделы о ситуациях приложения открываются первой попыткой — версией, к которой
ведут README плагина и его пример. Раздел показывает, что этот код делает
на телефоне, и заканчивается кодом приложения.

Приложение —
[`camera_example`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/camera_example)
в репозитории этого пакета, и оно запускается на Android и iOS:

```sh
git clone https://github.com/vi-k/solo.git
cd solo/packages/flutter_solo/camera_example
flutter run
```

Ответы на этой странице — код приложения; первая попытка помечена своей
строкой: `// Первая попытка:` и что идёт не так. Трасса — то, что приложение
делает с камерой под `flutter test`, где телефон заменяет фейковая платформа
камеры. Вызов к камере — это строка, а вызов, который занимает время, — две:
где он начинается и где кончается; смена состояния — тоже строка. Открытие
камеры:

```text
state Opening
create back #1
initialize #1 start
initialize #1 end
state Ready
```

## Быстрые нажатия

Пользователь нажимает быстрее, чем отвечает камера. Каждое нажатие вспышки
переводит её на один режим дальше, в порядке нажатий, и вспышка остаётся там,
куда её поставило последнее. Нажатие затвора во время снимка ничего
не добавляет: снимок один. Смена камеры во время снимка ждёт, пока снимок
кончится.

### Первая попытка

Пример плагина зовёт контроллер из каждой кнопки, а второй снимок не пускает
проверкой `isTakingPicture`:

```dart
// Первая попытка: смена камеры во время снимка теряет снимок.
Future<void> cycleFlash() async {
  final next = switch (camera.value.flashMode) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.always,
    _ => FlashMode.off,
  };
  try {
    await camera.setFlashMode(next);
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> shoot() async {
  // Снимок уже идёт, ничего не делаем.
  if (camera.value.isTakingPicture) return;
  try {
    widget.onCaptured(await camera.takePicture());
  } on CameraException catch (e) {
    show(e);
  }
}

Future<void> switchCamera() async {
  final next = widget.cameras.firstWhere(
    (c) => c.name != camera.value.description.name,
  );
  try {
    await camera.setDescription(next);
  } on CameraException catch (e) {
    show(e);
  }
}
```

Проверка держит затвор в рамках требования. Смену не держит ничего:
`setDescription` освобождает камеру контроллера и открывает следующую, и идущий
снимок её не останавливает. Нажатие затвора, затем смены:

```text
capture #1 start
dispose #1 start
capture #1 failed
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
```

На Galaxy A55 освобождение теряет снимок, и фейковая платформа делает то же
самое: приходит ошибка `Image capture failed due to the camera being closed.`,
`takePicture` бросает исключение, и экран показывает `ImageCaptureException:
androidx.camera.core.ImageCaptureException: Camera is closed.` Следующая камера
открывается и работает. iPhone 13 mini освобождает камеру только после снимка,
и снимок доходит: один и тот же код сохраняет снимок на одном телефоне и теряет
на другом.

Кнопка вспышки берёт следующий режим из `value.flashMode`, а контроллер плагина
меняет его только после ответа `setFlashMode`. Нажатия быстрее этого ответа
читают один и тот же режим и просят его дважды, и одно нажатие теряется:
на iPhone 13 mini три таких нажатия из `auto` оставляют вспышку на `off`,
а не возвращают в `auto`.

### Одна очередь для кнопок

Каждая команда `CameraSession` — задача в единственной очереди её `Solo`, а он
выполняет задачи по одной:

```dart
Job<XFile?> takePicture() => enqueue<Ready, XFile?>(
  key: _Op.takePicture,
  policy: Policy.droppable,
  (ctx) async {
    final file = await ctx.join(ctx.state.camera.takePicture);
    onCaptured(file);
    return file;
  },
);

Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  final next = switch (flash) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.always,
    _ => FlashMode.off,
  };
  await ctx.join(() => camera.setFlashMode(next));
  ctx.emit(Ready(camera: camera, flash: next, recording: recording));
});

Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
  final cameras = await ctx.join(availableCameras);
  final camera = ctx.state.camera;
  final at = cameras.indexWhere((c) => c.name == camera.description.name);
  final next = cameras[(at + 1) % cameras.length];
  await ctx.join(() => camera.setDescription(next));
});

enum _Op { takePicture }
```

`Policy.droppable` отдаёт второму нажатию затвора задачу первого, пока та стоит
в очереди или выполняется, и до `onCaptured` доходит один снимок. Вспышка
и смена камеры остаются на политике по умолчанию, `Policy.sequential`: каждое
нажатие — своя задача, и она ждёт предыдущую. Смена, нажатая во время снимка,
начинается, когда снимок кончился, и `setDescription` освобождает камеру,
на которой ничего не идёт. Два нажатия затвора, затем одно смены:

```text
capture #1 start
capture #1 end
dispose #1 start
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
```

От второго нажатия затвора строки не остаётся. Нажатие, сделанное, пока камера
открывается, ждёт в той же очереди, за открытием. Нажатие вспышки ждёт там
предыдущее и берёт режим из состояния, куда его положило то нажатие.
