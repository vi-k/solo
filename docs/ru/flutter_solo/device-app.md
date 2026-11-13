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

## Смена камеры во время записи

Пользователь переключается на другую камеру, пока идёт запись видео. Запись
продолжается с другой камеры, и стоп даёт один файл. Нажатие стопа во время
смены ждёт, пока смена кончится.

### Первая попытка

`setDescription` контроллера плагина смотрит на `value.isRecordingVideo`.
Во время записи он отдаёт записи следующую камеру, а иначе освобождает камеру
и открывает следующую. На Android плагин хочет запись, начатую
с `enablePersistentRecording`, и `startVideoRecording` включает его
по умолчанию. Кнопки зовут контроллер, а запись и стоп сперва проверяют флаг:

```dart
// Первая попытка: смена камеры во время старта записи теряет запись.
Future<void> record() async {
  // Запись уже идёт, ничего не делаем.
  if (camera.value.isRecordingVideo) return;
  try {
    await camera.startVideoRecording();
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

Future<void> stop() async {
  if (!camera.value.isRecordingVideo) return;
  try {
    widget.onCaptured(await camera.stopVideoRecording());
  } on CameraException catch (e) {
    show(e);
  }
}
```

Контроллер ставит `isRecordingVideo` только после ответа `startVideoRecording`.
Смена, нажатая раньше, идёт другим путём: освобождает камеру под стартующей
записью и открывает следующую. Старт кончается уже после этого, и контроллер,
к тому времени на новой камере, ставит флаг. Нажатие записи, смены, пока запись
стартует, затем стопа:

```text
record #1 start
dispose #1 start
dispose #1 end
create front #2
initialize #2 start
initialize #2 end
stop #2 start
```

На iPhone 13 mini запись может стартовать дольше полутора секунд, и смена,
нажатая за это время, теряет запись; фейковая платформа здесь следует iPhone.
Флаг говорит, что запись идёт, стоп просит её у платформы, а у платформы записи
нет: экран показывает `Error -1008: Video is not recording!` Когда запись уже
началась, смена переводит её на другую камеру и на iPhone 13 mini, и на Galaxy
A55, а стоп, нажатый во время такой смены, кончается после неё, с одним файлом.

### Запись в очереди

Старт и стоп записи — задачи в очереди кнопок:

```dart
Job<void> startRecording() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  if (recording) return;
  await ctx.join(camera.startVideoRecording);
  ctx.emit(Ready(camera: camera, flash: flash, recording: true));
});

Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
  final Ready(:camera, :flash, :recording) = ctx.state;
  if (!recording) return null;
  final file = await ctx.join(camera.stopVideoRecording);
  ctx.emit(Ready(camera: camera, flash: flash, recording: false));
  onCaptured(file);
  return file;
});
```

Смена, нажатая, пока запись стартует, ждёт за стартом, как смена во время
снимка ждёт за снимком. Когда смена выполняется, запись уже идёт,
и `setDescription` отдаёт ей следующую камеру. Нажатие стопа во время смены
ждёт за сменой. Идёт ли запись, задача читает из состояния, которое ей оставила
предыдущая задача, поэтому второе нажатие записи или стопа ничего не делает.
Нажатие записи, смены, пока запись стартует, затем стопа во время смены,
на фейковой платформе по правилам iPhone:

```text
record #1 start
record #1 started
state Ready
switch #1 front start
switch #1 front end
stop #1 start
record #1 end
state Ready
```

Строки `dispose` в трассе нет: смена не освобождает камеру, и запись идёт
дальше с фронтальной. Стоп начинается, когда смена кончилась, и даёт один файл.

## Уход с экрана

Пользователь уходит с экрана камеры, пока идёт снимок, и может тут же открыть
его снова. Снимок доходит до главного экрана. Заново открытый экран камеры
открывает камеру только после того, как экран до него её отпустил.

### Первая попытка

README плагина освобождает контроллер в `dispose` у `State`, а экран отдаёт
снимок наверх через `onCaptured` — главному экрану, который живёт дольше экрана
камеры:

```dart
// Первая попытка: уход теряет снимок, возврат открывает две камеры.
@override
void dispose() {
  camera.dispose();
  super.dispose();
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
```

`dispose` у `State` приходит, когда маршрут экрана уже ушёл, в конце перехода
`pop`, и `camera.dispose()` освобождает камеру, что бы ни делал контроллер.
Этого освобождения никто не ждёт: экран камеры, открытый снова, создаёт свой
контроллер на первом же кадре, пока экран до него ещё держит камеру. Нажатие
затвора, затем «назад», и сразу снова экран камеры, со снимком дольше перехода,
на фейковой платформе по правилам Galaxy:

```text
capture #1 start
create back #2
initialize #2 start
initialize #2 end
dispose #1 start
capture #1 failed
dispose #1 end
```

Вторая камера создаётся раньше, чем освобождена первая, а освобождение приходит
посреди снимка. На Galaxy A55 освобождение обрывает снимок, и фейковая
платформа делает то же самое. Тогда `takePicture` плагина пишет `value`
контроллера, который к этому времени освобождён, и отладочная сборка бросает
`A CameraController was used after being disposed.` вместо `CameraException`,
которое ловит экран. Снимок до главного экрана не доходит. Вторая камера,
созданная, пока первая была открыта, показывает пустое превью, а её собственное
освобождение бросает `IllegalStateException`. iPhone 13 mini доводит снимок
до конца и только потом освобождает камеру, но снимок, который длится дольше
перехода, бросает в отладочной сборке ту же ошибку. Его плагин держит одну
камеру, и освобождение первой камеры закрывает вторую: превью замирает,
а снимок на ней не приходит никогда.

### Освобождение, которого ждёт следующий экран

`release()` у `CameraSession` — команда в очереди кнопок:

```dart
Job<void> release() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state case Ready(:final camera)) {
    await ctx.join(camera.dispose);
  }
  ctx.emit(const Closed());
});
```

Она начинается, когда кончилась команда перед ней, в том числе снимок,
и кончается, когда платформа освободила камеру. Освобождение, пришедшее, пока
камера открывается, ждёт открытия и освобождает открытую камеру.

`CameraScreen` владеет сессией через `AsyncDataScope` пакета
[scopo](https://pub.dev/packages/scopo). Скоуп создаёт сессию, когда экран
появляется. Когда экран уходит, скоуп запускает `disposeData`, а тот ждёт
освобождения и только после него закрывает сессию: `close()` у `Solo` не ждёт
того, что запущено в `onClose`. `scopeKey` ставит скоупы всех экранов камеры
в одну очередь, которую держит `AsyncScopeCoordinator` над навигатором. Скоуп
с этим ключом начинает работу, когда скоуп перед ним на том же ключе закончил
`disposeData`:

```dart
class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) => const AsyncScopeCoordinator(
    child: MaterialApp(title: 'Camera', home: HomeScreen()),
  );
}
```

Ожидание ключа и ожидание `disposeData` ограничены, по умолчанию 3 с каждое.
Когда одно из них истекает, scopo продолжает работу так, будто ожидание
кончилось, и новый экран открывает камеру, пока старый ещё её держит: это
поломка первой попытки, только позже. На Galaxy A55 снимок длится до 3,4 с,
а на iPhone 13 mini запись стартует до 2,5 с; освобождение ждёт любого из них,
поэтому экран ставит оба ограничения в `releaseTimeout` — десять секунд,
с запасом:

```dart
static const releaseTimeout = Duration(seconds: 10);

@override
Widget build(BuildContext context) => AsyncDataScope<CameraSession>(
  scopeKey: CameraScreen,
  scopeKeyTimeout: releaseTimeout,
  disposeScopeTimeout: releaseTimeout,
  initData: (context, ctx) async =>
      CameraSession(onCaptured: onCaptured)..open(),
  disposeData: (session) async {
    try {
      await session.release().value;
    } finally {
      await session.close();
    }
  },
  progressBuilder: (context, progress) => const SizedBox.expand(),
  errorBuilder: (context, error, stackTrace, progress) =>
      Center(child: Text('$error')),
  builder: (context, session) => CameraView(session: session),
);
```

Те же нажатия: затвор, «назад» и сразу снова экран камеры:

```text
capture #1 start
capture #1 end
dispose #1 start
dispose #1 end
state Closed
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

Освобождение начинается, когда снимок кончился, и снимок уходит на главный
экран. Вторая сессия открывает камеру после того, как первая освободила свою
камеру и закрылась: `state Closed` первой идёт раньше `state Opening` второй.
До тех пор скоуп нового экрана ждёт ключа и строит `progressBuilder` — пустой
экран.

## Уход в фон

Пользователь уходит на главный экран телефона, пока идёт запись видео, и может
тут же вернуться. Запись сохраняется и доходит до главного экрана. Пока
приложение в фоне, камера отпущена, а возврат открывает её снова, и только
после того, как её отпустили.

### Первая попытка

README плагина оставляет жизненный цикл приложения самому приложению. Его
раздел «Handling Lifecycle states» освобождает контроллер на `inactive`
и создаёт новый для той же камеры на `resumed`. Кнопка стопа проверяет, что
запись идёт:

```dart
// Первая попытка: уход посреди записи теряет запись.
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final CameraController? cameraController = controller;

  // Состояние приложения сменилось до инициализации.
  if (cameraController == null || !cameraController.value.isInitialized) {
    return;
  }

  if (state == AppLifecycleState.inactive) {
    cameraController.dispose();
  } else if (state == AppLifecycleState.resumed) {
    _initializeCameraController(cameraController.description);
  }
}

Future<void> stop() async {
  final camera = controller;
  if (camera == null || !camera.value.isRecordingVideo) return;
  try {
    widget.onCaptured(await camera.stopVideoRecording());
  } on CameraException catch (e) {
    show(e);
  }
}
```

На Galaxy A55 и на iPhone 13 mini одинаково: уход на главный экран телефона
даёт `inactive`, `hidden` и `paused`, а возврат — `hidden`, `inactive`
и `resumed`. `dispose()` на первом же `inactive` освобождает камеру из-под
записи, и файл никто не просит. У контроллера, созданного на `resumed`, записи
нет, поэтому нажатие стопа ничего не делает. Нажатие записи, главный экран
телефона и обратно, затем нажатие стопа, на фейковой платформе по правилам
любого из телефонов — здесь они совпадают:

```text
record #1 start
record #1 started
dispose #1 start
dispose #1 end
create back #2
initialize #2 start
initialize #2 end
```

В трассе нет строки `stop`: запись до главного экрана не доходит. На обоих
телефонах запись потеряна, а камера, открытая на `resumed`, работает.

### Приостановка в очереди

`suspend()` и `resume()` у `CameraSession` — команды в очереди кнопок.
`suspend()` останавливает запись и отдаёт файл в `onCaptured`, прежде чем
освободить камеру, и запоминает отпущенную камеру; `resume()` открывает эту
камеру снова через `_initialize` — конец `open()`, который создаёт контроллер
и инициализирует его:

```dart
Job<void> suspend() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state case Ready(:final camera, :final recording)) {
    _suspended = camera.description;
    try {
      if (recording) onCaptured(await ctx.join(camera.stopVideoRecording));
    } finally {
      ctx.emit(const Closed());
      await ctx.join(camera.dispose);
    }
  }
});

Job<void> resume() => enqueue<CameraState, void>((ctx) async {
  final description = _suspended;
  if (description == null) return;
  _suspended = null;
  ctx.emit(const Opening());
  await _initialize(ctx, description);
});
```

`suspend()` выдаёт `Closed` до начала освобождения, и экран убирает превью:
превью, построенное на контроллере, который освобождается, бросает
`buildPreview() was called on a disposed CameraController.` Поэтому здесь
`Closed` приходит чуть раньше, чем камера свободна, тогда как `release()`
выдаёт его, когда камера уже свободна: в `suspend()` он говорит, что превью
убрано, а камера свободна, когда `suspend()` кончился. Упавший стоп всё равно
освобождает камеру, из `finally`, а его сбой становится ошибкой `suspend()`.
`resume()`, пришедший до конца освобождения, ждёт в очереди за ним.

`CameraView`, часть экрана, которая показывает сессию, слушает жизненный цикл
приложения, пока она на экране:

```dart
@override
void initState() {
  super.initState();
  _lifecycle = AppLifecycleListener(
    onHide: () => widget.session.suspend(),
    onShow: () => widget.session.resume(),
  );
}

@override
void dispose() {
  _lifecycle.dispose();
  super.dispose();
}
```

`onHide` приходит, когда приложение переходит из `inactive` в `hidden`,
а `onShow` — на обратном пути, из `hidden` в `inactive`. На `inactive` экран
камеру не освобождает: на обоих телефонах диалог разрешения даёт `inactive`
и `resumed` и больше ничего, а плагин спрашивает разрешение, пока открывает
камеру. Диалог, пришедший, пока камера открывается, ничего не освобождает,
и камера открывается.

Нажатие записи, главный экран телефона и сразу обратно, на фейковой платформе
по правилам любого из телефонов — здесь они совпадают:

```text
record #1 start
record #1 started
state Ready
stop #1 start
record #1 end
state Closed
dispose #1 start
dispose #1 end
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

Остановка приходит раньше освобождения, и запись доходит до главного экрана.
Камера открывается снова, когда освобождение кончилось: `dispose #1 end` идёт
раньше `create back #2`. На Galaxy A55 стоп на `hidden` отдаёт файл, а возврат
сразу приходит посреди стопа и открывает камеру после освобождения, в том же
порядке.
