# Приложение устройства

Приложение камеры с двумя экранами. Главный экран показывает последний снимок
или видео. На экране камеры — превью и кнопки снимка, видео, вспышки, фонарика
и смены камеры. Камера — плагин `camera`, и экран владеет ею через
`CameraSession`, `Solo<CameraState>`. Каждая команда занимает на телефоне
время, телефон может забрать камеру, а камеру нужно отпустить, прежде чем её
откроет следующий экран.

Разделы о ситуациях приложения открываются первой попыткой — версией, к которой
ведут README плагина и его пример. Раздел показывает, что этот код делает
на телефоне, и заканчивается кодом приложения. Страницу закрывают два раздела:
тесты приложения и тот же экран камеры на bloc.

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

## Быстрые нажатия фонарика

Пользователь нажимает на фонарик быстрее, чем отвечает камера. Фонарик
оказывается там, куда его поставило последнее нажатие, и по пути ничего
не делает. Выключение и новое включение, пока он загорается, оставляют его
включённым, без мигания; включение и выключение во время снимка оставляют его
выключенным, без вспышки. Кнопка фонарика стоит рядом с кнопкой вспышки,
на задней камере.

### Первая попытка

Своего вызова для фонарика у плагина нет: `setFlashMode` с `FlashMode.torch`
зажигает его, а любой другой режим гасит — и в `camera_avfoundation`,
и в `camera_android_camerax`. Второй к тому же помнит, горит ли фонарик, для
платформы, а не для камеры; чего это стоит, показывает конец раздела. `Ready`
получает поле `torch`, а кнопка фонарика — команду в очереди кнопок, как
у вспышки: каждое нажатие — задача, которая переключает фонарик, взяв его
положение из состояния. Фонарик гаснет в режим кнопки вспышки:

```dart
// Первая попытка: от быстрых нажатий фонарик мигает и вспыхивает.
Job<void> toggleTorch() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  await ctx.join(() => camera.setFlashMode(torch ? flash : FlashMode.torch));
  ctx.emit(
    Ready(camera: camera, flash: flash, recording: recording, torch: !torch),
  );
});
```

Очередь выполняет каждое нажатие по порядку, и фонарик оказывается там, куда
его поставило последнее. По пути он делает то, о чём просило каждое нажатие.
Два нажатия во время снимка ждут за снимком, потом зажигают фонарик и гасят
его — вспышка. Выключение и включение, нажатые, пока фонарик загорается, гасят
его, как только он загорелся, и зажигают снова — мигание. На фейковой платформе
фонарик загорается не сразу, от `flash #N torch start` до `flash #N torch end`,
а гаснет сразу, строкой режима, в который гаснет. Снимок с включением
и выключением во время него, затем включение, выключение и включение, последние
два — пока фонарик загорается:

```text
capture #1 start
capture #1 end
flash #1 torch start
flash #1 torch end
state Ready
flash #1 auto
state Ready
flash #1 torch start
flash #1 torch end
state Ready
flash #1 auto
state Ready
flash #1 torch start
flash #1 torch end
state Ready
```

iPhone 13 mini зажигает фонарик за 1–14 мс, и первая попытка делает там те же
вызовы. Выключение и включение, нажатые через 1 мс после того, как фонарик
загорелся, погасили его и зажгли снова за 7 мс. Включение и выключение, нажатые
во время снимка, зажгли фонарик, когда снимок кончился, и погасили его 1 мс
спустя.

### Последнее нажатие в очереди

`toggleTorch()` у `CameraSession` берёт положение фонарика, о котором просит
нажатие, в момент нажатия, а не когда выполняется его задача: противоположное
предыдущему нажатию, пока задача того нажатия ждёт или выполняется,
и противоположное фонарику в состоянии, когда ни одно нажатие не ждёт. Задача
несёт эту цель. `Policy.keepLatest` под собственным ключом оставляет в очереди
только последнюю из этих задач: новое нажатие встаёт на место ждущего, а идущая
задача доходит до конца. Задача, которая застаёт фонарик там, куда просит её
нажатие, ничего не вызывает:

```dart
({bool on, Job<void> job})? _torchAsked;

Job<void> toggleTorch() {
  final lit = switch (currentState) {
    Ready(:final torch) => torch,
    _ => false,
  };
  final on = !(_torchAsked?.on ?? lit);
  final job = enqueue<Ready, void>(
    key: _Op.torch,
    policy: Policy.keepLatest,
    (ctx) async {
      final Ready(:camera, :flash, :recording, :torch) = ctx.state;
      if (on == torch || !hasTorch(camera.description)) return;
      await ctx.join(() => camera.setFlashMode(on ? FlashMode.torch : flash));
      ctx.emit(
        Ready(camera: camera, flash: flash, recording: recording, torch: on),
      );
    },
  );
  _torchAsked = (on: on, job: job);
  job.whenFinished((_) {
    if (identical(_torchAsked?.job, job)) _torchAsked = null;
  });
  return job;
}

enum _Op { takePicture, torch }
```

`whenFinished` забывает цель, когда задача последнего нажатия закончилась:
когда она выполнилась и когда её отбросили на старте, потому что камера уже
не была `Ready`. Задача, которую заменило новое нажатие, тоже заканчивается,
и её колбэк не трогает новую цель.

Вспышка и фонарик — одна настройка платформы. Пока фонарик горит,
`cycleFlash()` двигает только режим кнопки, и фонарик гаснет в этот режим:

```dart
Job<void> cycleFlash() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  final next = switch (flash) {
    FlashMode.off => FlashMode.auto,
    FlashMode.auto => FlashMode.always,
    _ => FlashMode.off,
  };
  if (!torch) await ctx.join(() => camera.setFlashMode(next));
  ctx.emit(
    Ready(camera: camera, flash: next, recording: recording, torch: torch),
  );
});
```

Плагин не может сказать, есть ли у камеры фонарик, поэтому приложение даёт его
только задней камере. Смена без записи гасит фонарик и зажигает его снова
на следующей камере, если у той он есть, как снова ставит режим вспышки; смена
во время записи оставляет фонарик на камере, у которой он есть, и гасит его
перед камерой без него. [Потеря камеры](#потеря-камеры) показывает смену
целиком. Когда фонарик выключен, смена оставляет состояние как было, поэтому
кнопка слушает контроллер плагина, который держит камеру:

```dart
bool hasTorch(CameraDescription camera) =>
    camera.lensDirection == CameraLensDirection.back;

ValueListenableBuilder<CameraValue>(
  valueListenable: camera,
  builder: (context, value, _) => hasTorch(value.description)
      ? IconButton(
          key: const Key('torch'),
          onPressed: widget.session.toggleTorch,
          icon: Icon(
            torch ? Icons.flashlight_on : Icons.flashlight_off,
          ),
        )
      : const SizedBox.shrink(),
),
```

Те же нажатия: снимок с включением и выключением во время него, затем
включение, выключение и включение, последние два — пока фонарик загорается:

```text
capture #1 start
capture #1 end
flash #1 torch start
flash #1 torch end
state Ready
```

От двух нажатий во время снимка строк не остаётся: выключение встало в очереди
на место включения и застало фонарик выключенным. Из трёх нажатий после снимка
первое зажигает фонарик, третье встаёт на место второго, а когда оно
выполняется, фонарик уже горит.

На iPhone 13 mini те же нажатия через кнопки, на solo и на bloc, в отладочной
и в profile-сборке: выключение и включение пришли через 0–3 мс после начала
вызова фонарика длиной 6–14 мс, и фонарик получил этот один вызов; включение
и выключение во время снимка не дали ни одного вызова.

`camera_android_camerax` 0.7.6+1 хранит, горит ли фонарик, во флаге платформы,
а не камеры, и меняет этот флаг только `setFlashMode`: освобождение оставляет
его поднятым, и следующая камера тоже. При поднятом флаге `FlashMode.torch`
сразу возвращается, поэтому фонарик следующей камеры остаётся тёмным, хотя
состояние и значок говорят, что он горит. Любой другой режим сначала гасит
фонарик на открытой сейчас камере, а камера без фонарика отказывает в этом
ошибкой камеры, которая переводит экран в `Broken`. Поэтому приложение гасит
горящий фонарик, пока его камера ещё открыта: перед освобождением, перед уходом
приложения с переднего плана и перед сменой, кроме смены во время записи
на камеру с фонариком. [Уход с экрана](#уход-с-экрана),
[Уход в фон](#уход-в-фон) и [Потеря камеры](#потеря-камеры) показывают эти
команды целиком. Камера, которую платформа потеряла, больше вызовов
не принимает, поэтому после потери флаг остаётся поднятым: первое нажатие
фонарика на камере, открытой следом, меняет только значок. Фейковая платформа
хранит флаг, когда работает как Galaxy; сам Galaxy фонарик не гонял.

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

На iPhone 13 mini в debug-сборке первая запись процесса стартовала за 6–12,6 с,
а следующие — за 25–138 мс; в profile-сборке первая — примерно за 180 мс.
Смена, нажатая до конца старта, теряет запись, и фейковая платформа, у которой
старт длится секунду, здесь следует правилам iPhone. Флаг говорит, что запись
идёт, стоп просит её у платформы, а у платформы записи нет: экран показывает
`Error -1008: Video is not recording!` Когда запись уже началась, смена
переводит её на другую камеру и на iPhone 13 mini, и на Galaxy A55, а стоп,
нажатый во время такой смены, кончается после неё, с одним файлом.

### Запись в очереди

Старт и стоп записи — задачи в очереди кнопок:

```dart
Job<void> startRecording() => enqueue<Ready, void>((ctx) async {
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  if (recording) return;
  await ctx.join(camera.startVideoRecording);
  ctx.emit(
    Ready(camera: camera, flash: flash, recording: true, torch: torch),
  );
});

Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  if (!recording) return null;
  final file = await ctx.join(camera.stopVideoRecording);
  ctx.emit(
    Ready(camera: camera, flash: flash, recording: false, torch: torch),
  );
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
  if (ctx.state case Ready(:final camera, :final flash, :final torch)) {
    try {
      if (torch) await ctx.join(() => camera.setFlashMode(flash));
    } finally {
      await ctx.join(camera.dispose);
    }
  }
  ctx.emit(const Closed());
});
```

Она начинается, когда кончилась команда перед ней, в том числе снимок,
и кончается, когда платформа освободила камеру. Освобождение, пришедшее, пока
камера открывается, ждёт открытия и освобождает открытую камеру. Горящий
фонарик сначала гаснет, пока камера открыта, по причине, которую называет конец
раздела [Быстрые нажатия фонарика](#быстрые-нажатия-фонарика).

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
поломка первой попытки, только позже. На Galaxy A55 снимок длится до 3,4 с.
На iPhone 13 mini запись в profile-сборке стартует примерно за 180 мс,
но первая запись процесса в debug-сборке стартовала до 12,6 с, а освобождение
ждёт любого из них. Поэтому экран ставит оба ограничения в `releaseTimeout` —
двадцать секунд: один такой старт в debug уже превысил десять.

```dart
static const releaseTimeout = Duration(seconds: 20);

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
  if (ctx.state case Ready(
    :final camera,
    :final flash,
    :final recording,
    :final torch,
  )) {
    _suspended = camera.description;
    try {
      if (recording) onCaptured(await ctx.join(camera.stopVideoRecording));
      if (torch) await ctx.join(() => camera.setFlashMode(flash));
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
Горящий фонарик гаснет после стопа и до освобождения, как в `release()`.
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

## Потеря камеры

Камеру забирает другое приложение, или камера отказывает. Экран показывает сбой
и кнопку повтора, и повтор открывает камеру снова.

### Первая попытка

Пример плагина слушает свой контроллер и, как только в `value` контроллера
появляется ошибка, показывает `Camera error` с описанием ошибки. Пример
показывает этот текст во всплывающей полосе; здесь он остаётся на экране как
`Text`, так что экран в любой момент говорит, что слушатель показал последним:

```dart
// Первая попытка: первая ошибка остаётся, а вторую не видно.
@override
void initState() {
  super.initState();
  camera.addListener(() {
    if (mounted) setState(() {});
    if (camera.value.hasError) {
      show('Camera error ${camera.value.errorDescription}');
    }
  });
  camera.initialize().catchError(show);
}
```

Контроллер плагина слушает ошибки своей камеры через
`onCameraError(cameraId).first`. Первую ошибку он кладёт
в `value.errorDescription`, никогда её не стирает и следующих ошибок не слышит.
Каждое следующее изменение `value` — после снимка или нажатия вспышки — находит
там старую ошибку, и слушатель примера показывает её снова. У экрана нет
состояния для потерянной камеры и нет способа открыть её заново.

На Galaxy A55 камеру забирает собственное приложение камеры телефона, открытое
на весь экран: приложение получает ошибку
`The camera was already in use, possibly by a higher-priority camera client.`
и никакого события закрытия. После возврата в приложение камера сама работает
снова. iPhone 13 mini ошибки не присылает: его приложение камеры уводит это
приложение в фон, а после возврата оттуда камера работает. Строка
`camera #1 error` — ошибка, о которой сообщает платформа. Камеру забрали,
снимок и вторая ошибка той же камеры, на фейковой платформе по правилам Galaxy:

```text
camera #1 error
capture #1 start
capture #1 end
camera #1 error
```

Снимок проходит, а экран всё ещё говорит
`Camera error The camera was already in use,
possibly by a higher-priority camera client.` Вторая ошибка не оставляет следа:
контроллер перестал слушать после первой.

### Сбой в состоянии

`CameraSession` следит за ошибками своей камеры через собственную подписку. Это
поле контроллера, а не джоба: джоба, которая следит за потоком, держит очередь,
пока поток открыт. `id` камеры меняется с каждым открытием и со сменой камеры
без записи, поэтому `_watch` снимает подписку прежней камеры и оформляет новую,
а `onClose` снимает последнюю:

```dart
StreamSubscription<CameraErrorEvent>? _errors;

@override
void onClose() => unawaited(_errors?.cancel());

void _watch(CameraController camera) {
  unawaited(_errors?.cancel());
  _errors = CameraPlatform.instance
      .onCameraError(camera.cameraId)
      .listen((event) => _lose(event.description));
}

void _lose(String description) {
  if (currentState case Ready(:final camera)) {
    externalSetState(Broken(description));
    _letGo(camera);
  }
}

void _letGo(CameraController camera) => enqueueJob(
  job<CameraState, void>((ctx) => ctx.join(camera.dispose)),
  first: true,
);
```

Сессия считает любую ошибку своей камеры потерей камеры. Это её собственный
выбор, а не слова плагина: ошибка несёт только описание, а плагин шлёт в тот же
поток ошибки одной операции и ошибки, которые сам называет восстановимыми.
На Android неудачный снимок сообщает
`The camera framework failed to fulfill the image capture request.`, а CameraX
сообщает об ошибке, от которой обещает восстановиться; на iOS запись, которой
не удалось добавить выход звука, сообщает
`Unable to add Audio input/output to session capture`. Цена в том, что и один
неудачный снимок кончается `Broken`, и пользователь нажимает повтор.

`_lose` пишет сбой в состояние сразу, через `externalSetState`, а не в джобе,
которая ждала бы за идущей командой. Командам кнопок нужен `Ready`, и те, что
ждут в очереди, на потерянной камере не стартуют. `_letGo` освобождает камеру
в отдельной джобе в голове очереди: там уже может ждать `release()` уходящего
экрана, который в `Broken` камеры не находит и кончился бы раньше, чем
потерянную камеру освободили. Ошибка, которая застаёт состояние не в `Ready`,
ничего не меняет: вторая ошибка той же камеры — не второй сбой. Камера, которую
Galaxy A55 вернул бы сам, тоже освобождается: ошибка не говорит, надолго ли
потеря, а повтор откроет камеру, когда пользователь вернётся.

Сессия не слушает `onCameraClosing`. Galaxy A55 присылает событие закрытия,
когда начинается запись, при смене камеры во время записи и после стопа,
а камера всё это время остаётся открытой; отнятая камера приходит ошибкой.

`open()` ничего не делает, когда камера в `Ready`. Камера открывается
в `_initialize` — конце `open()`, который начинает следить за ней, когда она
открылась; смена камеры начинает следить заново, потому что без записи камера
получает новый `id`:

```dart
Job<void> open() => enqueue<CameraState, void>((ctx) async {
  if (ctx.state is Ready) return;
  ctx.emit(const Opening());
  final cameras = await ctx.join(availableCameras);
  if (cameras.isEmpty) {
    ctx.emit(const NoCamera());
    return;
  }
  await _initialize(ctx, cameras.first);
});

Future<void> _initialize(
  SoloContext<CameraState, CameraState> ctx,
  CameraDescription description,
) async {
  final camera = CameraController(description, ResolutionPreset.medium);
  try {
    await ctx.join(camera.initialize);
  } on CameraException catch (error) {
    ctx.emit(Broken(error));
    _letGo(camera);
    return;
  }
  _watch(camera);
  ctx.emit(
    Ready(camera: camera, flash: camera.value.flashMode, recording: false),
  );
}

Job<void> switchCamera() => enqueue<Ready, void>((ctx) async {
  final cameras = await ctx.join(availableCameras);
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  final at = cameras.indexWhere((c) => c.name == camera.description.name);
  final next = cameras[(at + 1) % cameras.length];
  if (torch && !(recording && hasTorch(next))) {
    await ctx.join(() => camera.setFlashMode(flash));
    ctx.emit(Ready(camera: camera, flash: flash, recording: recording));
  }
  try {
    await ctx.join(() => camera.setDescription(next));
  } on CameraException catch (error) {
    if (recording) rethrow;
    ctx.emit(Broken(error));
    _letGo(camera);
    return;
  }
  _watch(camera);
  if (!recording) {
    final lit = torch && hasTorch(next);
    await ctx.join(() => camera.setFlashMode(lit ? FlashMode.torch : flash));
    if (lit) {
      ctx.emit(
        Ready(camera: camera, flash: flash, recording: false, torch: true),
      );
    }
  }
});
```

Камера, которая не открылась, тоже `Broken`, и `_letGo` освобождает то, что
контроллер плагина успел создать на платформе. Смена камеры без записи — тоже
открытие: плагин освобождает камеру, прежде чем открыть следующую, поэтому
неудачная смена так же `Broken`. Камера, которую он открывает, начинает
со своего режима вспышки, а контроллер плагина хранит прежний, поэтому смена
заново ставит режим кнопки: без этого на iPhone 13 mini кнопка после смены
показывала `always`, а снимок шёл в `auto`. Горящий фонарик гаснет перед
сменой, пока его камера открыта, и снова зажигается вместо режима на камере,
у которой он есть; во время записи камера с фонариком его сохраняет. Во время
записи плагин камеру не освобождает, камера продолжает писать, а сбой остаётся
ошибкой джобы при состоянии `Ready`. Стоп, который не удался, — последний путь
к `Broken`:

```dart
Job<XFile?> stopRecording() => enqueue<Ready, XFile?>((ctx) async {
  final Ready(:camera, :flash, :recording, :torch) = ctx.state;
  if (!recording) return null;
  final XFile file;
  try {
    file = await ctx.join(camera.stopVideoRecording);
  } on CameraException catch (error) {
    ctx.emit(Broken(error));
    _letGo(camera);
    return null;
  }
  ctx.emit(
    Ready(camera: camera, flash: flash, recording: false, torch: torch),
  );
  onCaptured(file);
  return file;
});
```

Контроллер плагина снимает `isRecordingVideo` только после удачного стопа.
После неудачного он навсегда считает, что пишет: новая запись бросает
исключение, а смена камеры идёт путём записи. `stopRecording` нужен `Ready`,
и после того как она выдала `Broken`, её собственные вызовы через `ctx` сдаются
с `Cancelled`, поэтому освобождение и здесь уходит в отдельную джобу.

Экран показывает `Broken` с кнопкой, которая зовёт `open()`:

```dart
Broken(:final error) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('The camera failed: $error'),
      TextButton(
        key: const Key('retry'),
        onPressed: widget.session.open,
        child: const Text('Retry'),
      ),
    ],
  ),
),
```

Два нажатия повтора до кадра, который убирает кнопку, ставят в очередь два
открытия, и второе застаёт камеру открытой. Камеру забрали и дважды нажали
повтор, на фейковой платформе по правилам Galaxy:

```text
camera #1 error
state Broken
dispose #1 start
dispose #1 end
state Opening
create back #2
initialize #2 start
initialize #2 end
state Ready
```

`state Broken` идёт сразу за ошибкой, а освобождение — за ним. Открытие
начинается, когда потерянную камеру освободили, а второе нажатие не оставляет
строки.

## Отказ в разрешении

Пользователь не даёт приложению камеру или микрофон. Экран говорит, что из двух
разрешить. После обычного отказа кнопка повтора спрашивает снова; когда телефон
больше не спрашивает, экран говорит разрешить в Настройках, а когда это
запрещает политика устройства, экран так и говорит.

### Первая попытка

Плагин сам спрашивает разрешения, пока создаёт камеру, и `initialize` бросает
`CameraException`, код которого говорит, в чём отказано. README плагина
перечисляет шесть кодов, от `CameraAccessDenied` до `AudioAccessRestricted`,
а его пример ловит их вокруг `initialize` и на каждый показывает своё сообщение
во всплывающей полосе. Здесь сообщение остаётся на экране как `Text`, а уходя,
экран освобождает свой контроллер:

```dart
// Первая попытка: одно сообщение и ничего, что спросило бы снова.
@override
void dispose() {
  camera.dispose();
  super.dispose();
}

Future<void> open() async {
  try {
    await camera.initialize();
  } on CameraException catch (e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        show('You have denied camera access.');
      case 'CameraAccessDeniedWithoutPrompt':
        // только iOS
        show('Please go to Settings app to enable camera access.');
      case 'CameraAccessRestricted':
        // только iOS
        show('Camera access is restricted.');
      case 'AudioAccessDenied':
        show('You have denied audio access.');
      case 'AudioAccessDeniedWithoutPrompt':
        // только iOS
        show('Please go to Settings app to enable audio access.');
      case 'AudioAccessRestricted':
        // только iOS
        show('Audio access is restricted.');
      default:
        show(e);
    }
  }
}
```

README помечает коды с `WithoutPrompt` и `Restricted` как пока только для iOS.
Android-часть плагина, `camera_android_camerax`, знает для отказа
`CameraAccessDenied` и `AudioAccessDenied`, а для запроса, сделанного, пока
идёт другой, — `CameraPermissionsRequestOngoing`. Galaxy A55 во второй раз
спрашивает с выбором «запретить и больше не спрашивать»; после этого открытие
не показывает диалога и примерно за 200 мс кончается тем же
`CameraAccessDenied`. На iPhone 13 mini первый отказ — `CameraAccessDenied`,
а следующее открытие без диалога кончается `CameraAccessDeniedWithoutPrompt`.
Отказ в микрофоне на iPhone — `AudioAccessDenied`. Неудачное создание камеры —
строка `create back failed`. Экран, открытый дважды, второй раз после
«запретить и не спрашивать», на фейковой платформе по правилам Galaxy:

```text
create back failed
dispose #-1 start
dispose #-1 end
create back failed
dispose #-1 start
dispose #-1 end
```

Оба открытия говорят `You have denied camera access.`, и на экране нет ничего,
что спросило бы снова: к диалогу можно вернуться, только уйдя с экрана и открыв
его заново. После «не спрашивать» Galaxy больше не спрашивает, а сообщение
не отправляет пользователя в Настройки. На iPhone 13 mini второе открытие
говорит `Please go to Settings app to enable camera access.` Уход с экрана
освобождает контроллер, и контроллер шлёт платформе `dispose` для камеры `-1`:
камеры не создали, поэтому у контроллера остался `id`, с которого он начинает,
а его `dispose` зовёт платформу, раз `initialize` уже начался.

### Отказ, который объясняет экран

`_initialize` — конец `open()` и `resume()` — отличает отказ от сбоя по коду
исключения: шесть кодов README дают `Denied` с этим кодом, а любой другой —
`Broken`. Камеру он освобождает, только если платформа её создала. Контроллер
плагина держит `cameraId`, равный `-1`, пока `createCameraWithSettings` не даст
ему `id`, а отказ приходит именно оттуда:

```dart
Future<void> _initialize(
  SoloContext<CameraState, CameraState> ctx,
  CameraDescription description,
) async {
  final camera = CameraController(description, ResolutionPreset.medium);
  try {
    await ctx.join(camera.initialize);
  } on CameraException catch (error) {
    final code = error.code;
    ctx.emit(_denials.contains(code) ? Denied(code) : Broken(error));
    if (camera.cameraId != _noCamera) {
      _letGo(camera);
    }
    return;
  }
  _watch(camera);
  ctx.emit(
    Ready(camera: camera, flash: camera.value.flashMode, recording: false),
  );
}

const _noCamera = -1;

const _denials = {
  'CameraAccessDenied',
  'CameraAccessDeniedWithoutPrompt',
  'CameraAccessRestricted',
  'AudioAccessDenied',
  'AudioAccessDeniedWithoutPrompt',
  'AudioAccessRestricted',
};
```

Плагин называет `-1` именем `kUninitializedCameraId` и держит это имя для своих
тестов, поэтому у сессии своя константа. Контроллер, которому отказали,
не освобождается: именно его `dispose` послал бы платформе `dispose` для `-1`.
После него остаётся его слушатель ориентации устройства, который он заводит
до создания камеры, — по одному на каждое открытие с отказом.

Экран показывает `Denied` — что разрешить и где, а при обычном отказе ещё
и кнопку повтора. Повтор зовёт `open()`, как и для `Broken`, и плагин
спрашивает снова, пока создаёт камеру:

```dart
Denied(:final code) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_denial(code)),
      if (code.endsWith('Denied'))
        TextButton(
          key: const Key('retry'),
          onPressed: widget.session.open,
          child: const Text('Retry'),
        ),
    ],
  ),
),

String _denial(String code) {
  final device = code.startsWith('Audio') ? 'microphone' : 'camera';
  if (code.endsWith('WithoutPrompt')) {
    return 'Allow the app to use the $device in Settings.';
  }
  if (code.endsWith('Restricted')) {
    return 'The policy of this device does not let the app use the $device.';
  }
  return 'Allow the app to use the $device.';
}
```

Отказ, нажатие повтора, когда iPhone уже не спрашивает, и уход с экрана,
на фейковой платформе по правилам iPhone:

```text
state Opening
create back failed
state Denied
state Opening
create back failed
state Denied
state Closed
```

Первый `Denied` — это `CameraAccessDenied`: экран говорит
`Allow the app to use the camera.` и показывает повтор. Второй —
`CameraAccessDeniedWithoutPrompt`: экран говорит
`Allow the app to use the camera in Settings.`, и кнопки нет. В трассе нет
строки `dispose`: камеры не создали, и освобождение экрана её не находит.
На iPhone 13 mini переключатель в Настройках перезапускает приложение.

На Galaxy A55 повтор — это второе открытие, которое снова показывает диалог,
и отказ там — снова `CameraAccessDenied`. После «запретить и не спрашивать»
повтор ничего не спрашивает: открытие без диалога кончается тем же кодом,
и экран возвращается с тем же текстом и той же кнопкой. Другого кода для такого
отказа у Android-части плагина нет, поэтому на Android экран не отправляет
пользователя в Настройки. `CameraAccessRestricted` и `AudioAccessRestricted`
взяты из README: ни один из телефонов не ставили под политику, которая
запрещает камеру.

## Тесты приложения

Тесты приложения идут под `flutter test`, на `FakeCameraPlatform`: это
`CameraPlatform` из тестов, где вместо железа длительности. Вызов, который
на телефоне занимает время, пишет строку там, где начинается, и строку там, где
кончается, а кончается он, когда тест сдвинул часы на столько же:

```dart
/// Сколько длится открытие.
Duration openTime = const Duration(milliseconds: 100);

/// Сколько длится снимок: от 0,5 до 3,4 с на Galaxy, от 0,2 до 0,6 с
/// на iPhone.
Duration captureTime = const Duration(milliseconds: 300);

/// Сколько длится смена камеры во время записи.
Duration switchTime = const Duration(milliseconds: 150);

/// Сколько длится освобождение камеры.
Duration disposeTime = const Duration(milliseconds: 50);

/// Сколько длится старт записи: около секунды на Galaxy. iPhone
/// стартует запись за 27–183 мс в profile-сборке; в debug-сборке первая
/// запись процесса стартовала от 6 до 12,6 с, а следующие — за 25–138 мс.
Duration recordStartTime = const Duration(seconds: 1);

/// Сколько длится остановка записи.
Duration stopTime = const Duration(milliseconds: 100);

/// Сколько фонарик загорается: `setFlashMode(FlashMode.torch)`, со строками
/// `flash #N torch start` и `flash #N torch end`. Любой другой режим
/// ставится сразу, одной строкой, и гасит фонарик.
Duration torchTime = const Duration(milliseconds: 50);
```

Где два вызова встречаются, фейк делает то же, что делали телефоны, а `phone`
выбирает между правилами Galaxy и правилами iPhone. По правилам Galaxy
`dispose` под снимком теряет снимок, со строкой `capture #N failed`;
по правилам iPhone `dispose` ждёт снимка. `failOpen`, `failStop`, `failSwitch`
и `failCreate`, пока заданы, роняют такой вызов, а `failFromOutside` присылает
ошибку камеры, как это делает платформа, когда камеру забирает другое
приложение.

Тесты держат три правила
[Testing](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md):
часы двигает тест, через `pump` и длительности фейка; `done` тест читает
до `pump`, как объясняет
[Waiting for the job](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md#waiting-for-the-job);
а освобождает и закрывает контроллер в своём теле, как объясняет
[Moving the clock](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/doc/testing.md#moving-the-clock).
Каждый тест кончается вызовом `finish`:

```dart
Future<void> finish(WidgetTester tester, CameraDriver controller) async {
  final released = controller.release();
  await tester.pump(platform.disposeTime);
  await letCloseEnd(tester);
  await released;
}
```

`letCloseEnd` нужен блоку из следующего раздела, а случаи solo проходят и без
него: [Тот же экран на bloc](#тот-же-экран-на-bloc) объясняет его.

`controller` — это `CameraDriver`, интерфейс тестов с методом на каждую
команду. Для `CameraSession` его `release` читает `done` сразу, пока `finish`
ещё не вызвал `pump`:

```dart
Future<void> release() async {
  // Освобождение кончается, пока тест качает кадры, а там `expect` нельзя.
  final released = await session.release().done;
  if (released is! Done<void>) throw StateError('release: $released');
  await session.close();
}
```

Те же случаи идут и против блока из следующего раздела, через его собственный
драйвер. Дальше — по одному тесту на каждую ситуацию страницы.

Быстрые нажатия: смена камеры во время снимка ждёт снимка, по правилам Galaxy,
где `dispose` под снимком потерял бы его:

```dart
testWidgets('a switch during a shot waits for it', (tester) async {
  final controller = make(captured.add);
  controller.open();
  await tester.pump(platform.openTime);
  controller
    ..takePicture()
    ..switchCamera();
  await tester.pump(platform.captureTime);
  await tester.pump(platform.disposeTime);
  await tester.pump(platform.openTime);

  expect(
    platform.log,
    containsAllInOrder([
      'capture #1 end',
      'dispose #1 start',
      'dispose #1 end',
      'create front #2',
      'initialize #2 end',
    ]),
  );
  expect(platform.log, isNot(contains('capture #1 failed')));
  expect(captured, hasLength(1));
  await finish(tester, controller);
});
```

Смена камеры во время записи: одно видео, с обеих камер:

```dart
testWidgets('recording goes on across a switch', (tester) async {
  final controller = make(captured.add);
  controller.open();
  await tester.pump(platform.openTime);
  controller
    ..startRecording()
    ..switchCamera()
    ..stopRecording();
  await tester.pump(platform.recordStartTime);
  await tester.pump(platform.switchTime);
  await tester.pump(platform.stopTime);

  expect(
    platform.log,
    containsAllInOrder([
      'record #1 start',
      'switch #1 front end',
      'record #1 end',
    ]),
  );
  expect(captured.map((file) => file.path), ['/fake/video-1.mp4']);
  expect((controller.currentState as Ready).recording, isFalse);
  await finish(tester, controller);
});
```

Уход с экрана гоняет всё приложение через его кнопки. Экран камеры, открытый
снова, пока прежний ещё уходит, открывает камеру после освобождения:

```dart
testWidgets('a new camera screen waits for the old one', (tester) async {
  await openCamera(tester);
  await until(tester, find.byKey(const Key('shutter')));
  await tester.pageBack();
  await tester.pump();
  await tester.tap(find.byKey(const Key('open-camera')));
  await tester.pumpAndSettle();
  await tester.pump(platform.disposeTime);
  await until(tester, find.byKey(const Key('shutter')));

  expect(
    platform.log,
    containsAllInOrder(['dispose #1 end', 'create back #2']),
  );
  expect(platform.openCameras, 1);
  expect(platform.hasPicture(2), isTrue);
  await goBack(tester);
  expect(platform.openCameras, 0);
});
```

Уход в фон: приложение сообщает о своём жизненном цикле через `binding` теста,
и запись доходит до `onCaptured` раньше освобождения:

```dart
testWidgets('recording is kept when the app leaves', (tester) async {
  final controller = await openShown(tester);
  controller.startRecording();
  await tester.pump(platform.recordStartTime);
  lifecycle(tester, leave);
  await tester.pump(platform.stopTime);
  await tester.pump(platform.disposeTime);

  expect(captured, hasLength(1));
  expect(captured.single.path, '/fake/video-1.mp4');
  expect(platform.openCameras, 0);
  expect(controller.currentState, isA<Closed>());
  expect(
    platform.log,
    containsAllInOrder(['record #1 end', 'dispose #1 start']),
  );
  lifecycle(tester, back);
  await tester.pump(platform.openTime);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

Потеря камеры: ошибка приходит после кадра, в котором её прислали, поэтому
`fail` качает два кадра, и экран показывает сбой раньше, чем камеру отпускают:

```dart
testWidgets('a camera taken away shows the failure', (tester) async {
  final controller = await openShown(tester);
  // Камеру, которую забрало другое приложение, Galaxy сообщает ошибкой,
  // без события закрытия.
  await fail(tester, 1, FakeCameraPlatform.takenOnAndroid);

  expect(
    controller.currentState,
    isA<Broken>().having(
      (s) => s.error,
      'error',
      FakeCameraPlatform.takenOnAndroid,
    ),
  );
  expect(retry, findsOneWidget);
  await tester.pump(platform.disposeTime);
  expect(platform.log, contains('dispose #1 end'));
  expect(platform.openCameras, 0);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

Отказ в разрешении: отказ, повтор и отказ, о котором iPhone уже не спрашивает;
камеры не создано, и освобождать нечего:

```dart
testWidgets('retry asks again, and the next answer shows (iPhone)', (
  tester,
) async {
  platform
    ..phone = FakePhone.iphone
    ..failCreate = FakeCameraPlatform.deniedOnIphone;
  final controller = await openShown(tester);
  await tester.pump();
  platform.failCreate = FakeCameraPlatform.deniedWithoutPromptOnIphone;
  await tester.tap(retry);
  await tester.pump();
  await tester.pump();

  expect(
    controller.currentState,
    isA<Denied>().having(
      (s) => s.code,
      'code',
      'CameraAccessDeniedWithoutPrompt',
    ),
  );
  expect(find.textContaining('Settings'), findsOneWidget);
  expect(retry, findsNothing);
  expect(platform.log, ['create back failed', 'create back failed']);
  await tester.pumpWidget(const SizedBox());
  await finish(tester, controller);
});
```

## Тот же экран на bloc

`CameraBloc` — контроллер экрана камеры на bloc: те же состояния и по событию
на каждую команду `CameraSession`. Команды делят один обработчик
с `sequential()` из `bloc_concurrency`: смена камеры ждёт идущего снимка,
а стоп — смены. У сбоя, о котором сообщает платформа, свой обработчик,
с трансформером по умолчанию, и тот запускает его сразу:

```dart
CameraBloc({required this.onCaptured}) : super(const Closed()) {
  // Один обработчик на все команды: смена ждёт идущего снимка, стоп —
  // смены, а освобождение — того, что идёт.
  on<CameraCommand>(_run, transformer: sequential());
  // У сбоя свой обработчик, с параллельным трансформером: сбой виден
  // сразу, а не после идущей команды.
  on<CameraLost>(_lose);
}
```

`BlocCameraScreen` кладёт блок под `BlocProvider` и `BlocBuilder` над теми же
кнопками. Блок проходит случаи предыдущего раздела на той же фейковой
платформе, и прогон приложения через его кнопки в их числе. Код —
[`camera_bloc.dart`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/camera_example/lib/camera_bloc.dart)
в приложении. Переключатель на главном экране выбирает контроллер экрана
камеры: solo, выбранный по умолчанию, или bloc. На iPhone 13 mini экран на bloc
делает то же, что экран на solo, в разделах
[Быстрые нажатия](#быстрые-нажатия),
[Быстрые нажатия фонарика](#быстрые-нажатия-фонарика),
[Смена камеры во время записи](#смена-камеры-во-время-записи),
[Уход с экрана](#уход-с-экрана) и [Уход в фон](#уход-в-фон).

`droppable()` на собственном обработчике отбросил бы второе нажатие затвора,
но смена камеры перестала бы ждать снимка. В общем обработчике `sequential()`
читает нажатие, только когда команда перед ним кончилась, а к тому времени
второе нажатие уже в очереди. Блок отбрасывает его в `add`. Там же нажатие
фонарика получает цель — от предыдущего нажатия — и идёт дальше как `SetTorch`
с целью и номером нажатия:

```dart
/// [TakePicture] ждёт в очереди или выполняется: нажатие во время снимка
/// отбрасывается. Флаг ставится в [add], потому что `sequential()`
/// читает событие, только когда предыдущее кончилось.
bool _shooting = false;

/// Фонарик, о котором просил последний [ToggleTorch], пока его [SetTorch]
/// не выполнился, и номер последнего нажатия.
bool? _torchAsked;
int _torchTaps = 0;

@override
void add(CameraEvent event) {
  if (event is TakePicture) {
    if (_shooting) return;
    _shooting = true;
  }
  if (event is ToggleTorch) {
    final lit = switch (state) {
      Ready(:final torch) => torch,
      _ => false,
    };
    final on = !(_torchAsked ?? lit);
    _torchAsked = on;
    super.add(SetTorch(on, ++_torchTaps));
    return;
  }
  super.add(event);
}
```

`sequential()` не умеет вынуть событие из очереди, поэтому каждый `SetTorch`
доходит до обработчика. Обработчик ничего не вызывает для того, чей номер
обогнало более позднее нажатие, и для того, что застаёт фонарик там, куда
просит, а последний из них забывает цель.

Потеря меняет состояние, пока команда ждёт камеру. Команда над готовой камерой
держит состояние, с которого начала, и смотрит на него снова после каждого
`await`:

```dart
Future<void> _startRecording(Emitter<CameraState> emit) async {
  final ready = state;
  if (ready is! Ready || ready.recording) return;
  await ready.camera.startVideoRecording();
  if (state != ready) return;
  emit(
    Ready(
      camera: ready.camera,
      flash: ready.flash,
      recording: true,
      torch: ready.torch,
    ),
  );
}
```

Идущая команда может ещё пользоваться потерянной камерой, поэтому `_lose`
ставит `LetGo` в очередь после неё. `Release`, который уже ждёт там,
выполняется первым и находит камеру в `_camera`: поле держит её и тогда, когда
состояние уже нет:

```dart
/// Камера, которую платформа держит для этого блока, потерянная или нет:
/// [Release], выполненный после потери, ещё находит её, раньше [LetGo].
CameraController? _camera;

void _lose(CameraLost event, Emitter<CameraState> emit) {
  if (state is! Ready) return;
  emit(Broken(event.description));
  add(const LetGo());
}

Future<void> _letGo() async {
  final camera = _camera;
  _camera = null;
  await camera?.dispose();
}
```

Владелец ждёт освобождения через `Completer` в событии. `close()` сначала
перестаёт слушать ошибки платформы: ошибка после него добавила бы событие
в закрытый блок, а `add` там бросает. Освобождение сначала гасит горящий
фонарик, в `_putTorchOut`, как это делает `release()` сессии:

```dart
Future<void> release() {
  final release = Release(Completer());
  add(release);
  return release.done.future;
}

@override
Future<void> close() {
  unawaited(_errors?.cancel());
  return super.close();
}

case Release(:final done):
  try {
    try {
      await _putTorchOut();
    } finally {
      await _letGo();
    }
    emit(const Closed());
    done.complete();
  } catch (error, stackTrace) {
    done.completeError(error, stackTrace);
  }
```

`BlocProvider` закрывает созданный им блок без ожидания и ничего не знает
об экране перед ним. `BlocCameraScreen` владеет блоком через тот же
`AsyncDataScope`, что и `CameraScreen`, с теми же таймаутами, и отдаёт блок
вниз через `BlocProvider.value`. Он берёт `scopeKey` у `CameraScreen`, поэтому
экран камеры на любом из контроллеров ждёт освобождения экрана перед ним. Скоуп
ждёт освобождения, а затем `close()`, как и у сессии:

```dart
disposeData: (bloc) async {
  try {
    await bloc.release();
  } finally {
    await bloc.close();
  }
},
```

Под `testWidgets` этот `close()` кончается только после оборота настоящего
цикла событий. Блок ждёт отмены подписок своих обработчиков, а подписка,
которой нечего ждать, отвечает future, созданным SDK в корневой зоне. Фальшивые
часы выполняют колбэки зоны теста, а не этой, поэтому случаи проворачивают цикл
везде, где ждут освобождения:

```dart
Future<void> letCloseEnd(WidgetTester tester) => tester.runAsync(() async {});
```

Что берёт каждая ситуация на bloc и на solo:

| Ситуация | bloc | solo | Что понадобилось тестам |
| --- | --- | --- | --- |
| Быстрые нажатия | `on<CameraCommand>` с `sequential()`; `_shooting`, который ставится в `add` | очередь `Solo`; `Policy.droppable` на ключе `takePicture` | ничего сверх |
| Быстрые нажатия фонарика | цель и номер нажатия, которые ставятся в `add`; `SetTorch`, который обработчик пропускает, когда его обогнало более позднее нажатие | `Policy.keepLatest` на ключе `toggleTorch`; цель, взятая в момент нажатия; `whenFinished` | ничего сверх |
| Смена камеры во время записи | тот же обработчик | та же очередь | ничего сверх |
| Уход с экрана | `Release` с `Completer`; `AsyncDataScope` со `scopeKey`; `BlocProvider.value` | `release()`; `AsyncDataScope` со `scopeKey` | bloc: `letCloseEnd`, для `close()` |
| Уход в фон | `Suspend` и `Resume` в очереди | `suspend()` и `resume()` в очереди | для упавшего стопа, bloc: блок, созданный в `runZonedGuarded`; solo: `Solo.unansweredHandler` |
| Потеря камеры | свой `on<CameraLost>`; проверка состояния после каждого `await`; `LetGo` в очереди; `_camera`; `close()`, который отменяет `_errors` | `externalSetState`; `ctx.join` при каждом `await` команды над `Ready`; `_letGo` с `first: true`; `onClose`, который отменяет `_errors` | для упавшей смены камеры во время записи, bloc: блок, созданный в `runZonedGuarded`; solo: `Solo.unansweredHandler` |
| Отказ в разрешении | `_initialize`, который сам ждёт `dispose` | `_initialize`, с `_letGo` | ничего сверх |

Тесты блока — случаи предыдущего раздела и один свой: ошибка камеры после
`close()` ничего не меняет.
