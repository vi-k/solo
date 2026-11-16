> **Состояние на 2026-11-16:** сделано и влито в `main` коммитом
> `docs: close the device app work`; все задачи, с 13b–13j сверх исходного
> плана, исполнены субагентами с ревью каждой; финальное ревью ветки —
> `2026-11-16-device-app-final-review-report.md`. Владелец 2026-11-13 одобрил
> план («План одобряю, исполняй субагентами с ревью каждой задачи», «Тест
> страницы вместо генератора — согласен») и перенёс вариант bloc в приложение —
> задача 13b.
> **Что это:** план работ по странице `packages/flutter_solo/doc/device-app.md`
> и приложению `packages/flutter_solo/camera_example/`: задачи, имена, тесты,
> проверки, порядок.
> **Связанные записи:** `2026-11-13-device-app-design.md`,
> `2026-11-07-bloc-vs-solo-debate-report.md`.

# Приложение устройства во flutter_solo — план

> **Исполнителю-агенту:** обязательный скилл —
> `superpowers:subagent-driven-development` или `superpowers:executing-plans`,
> задача за задачей. Шаги отмечены `- [ ]`.

**Цель:** страница `doc/device-app.md` пакета `flutter_solo` с переводом
и приложение `camera_example/` на плагине `camera`, код которого страница
показывает, с тестами на подставной платформе и ценой того же на bloc.

**Устройство:** приложение — отдельный пакет Flutter рядом с `example/`,
исключённый из архива `flutter_solo`. Контроллер `CameraSession` на `Solo`
владеет `CameraController` плагина; экран камеры живёт в scope scopo
с `scopeKey`. Страницу держит тест страницы внутри приложения: каждый блок кода
стоит в файлах приложения или его тестов, каждая процитированная трасса —
в журнале подставной платформы, как у `packages/solo/doc/camera.md`.

**Стек:** Flutter 3.38.1 и новее, `camera` от 0.12.0+2, `flutter_solo` и `solo`
из дерева, `scopo` ^1.0.0, `flutter_bloc` ^9.1.1 и `bloc_concurrency` ^0.3.0 —
только в тестах, `integration_test` — только на телефоне.

**Дизайн:** `2026-11-13-device-app-design.md`. План спорит от него; при
расхождении прав дизайн, исполнитель читает оба.

## Общие ограничения

- Пол: Dart 3.10.0, Flutter 3.38.1; `environment` приложения — `sdk: ^3.10.0`,
  `flutter: '>=3.38.1'`, как у `example/`.
- Рантайм-зависимости не выше пинов Flutter на полу, dev — свежие.
- Нижняя граница `camera` — `^0.12.0+2`. На стабильном SDK разрешается выпуск
  новее (на Flutter 3.47 — 0.12.2), на полу — 0.12.0+2; вывод о плагине,
  который различается между ними, на страницу идёт с версией или не идёт.
- Новых членов API в `async_job`, `solo`, `flutter_solo` нет (решение 131).
  Ответ раздела требует члена, которого нет, — стоп, вопрос владельцу.
- Код `yx_camera` не попадает никуда, и сам проект в публичных файлах,
  в коммитах и в записях для публики не называется.
- Первая попытка — то, к чему ведёт плагин: его README, его API, его пример.
  Раздел, где зонд поломки не показал, открывается ответом.
- Вариант bloc — сильнейший, какой удастся найти; мера цены — механизмы,
  а не строки.
- Утверждение о плагине на странице — только то, что есть в его исходнике или
  в прогоне, а о телефоне — только то, что сошлось на телефоне.
- Импорт `material.dart` — с комментарием и `// ignore: deprecated_member_use`,
  как в `packages/flutter_solo/test/testing_rakes_test.dart`.
- Код, комментарии, страница, `CHANGELOG.md`, коммиты — по-английски; перевод —
  по-русски, через линтер `humanizer--ru`, только `ERROR`.
- Markdown — ширина 79, `python3 tool/reflow.py`; правила `docs/conventions.md`
  и скилла `doc-reader`.
- Коммиты — Conventional Commits, в конце
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `docs/handoff.md` обновляется после каждой задачи, а не только в конце.
- Публикация — только отдельной просьбой владельца; пуш — по его слову.

## На что смотреть ревьюеру

Пять случаев, о которых дизайн молчит и которые первыми ударят по человеку
с телефоном. Тест каждого стоит в задаче, которая владеет кодом.

1. **Камер нет** — `availableCameras()` вернул пустой список (симулятор iOS,
   планшет без камеры): экран говорит «нет камеры», а не падает на `first`.
   Задача 3.
2. **Нажатие, пока камера открывается** — снимок, вспышка или смена камеры
   до конца `initialize()`: команда ждёт открытия, а не ловит `CameraException`
   «Uninitialized CameraController». Задача 4.
3. **Экран закрыт, пока камера открывается** — закрытие посреди `open()`:
   камера на платформе освобождается ровно один раз, и после `release()`
   `CameraController` плагина никто не трогает. Задача 6.
4. **«Повторить» дважды подряд** — две команды открытия после сбоя:
   на платформе открыта одна камера, а не две. Задача 8.
5. **Событие платформы после закрытия** — `CameraErrorEvent` или
   `CameraClosingEvent` приходит, когда контроллер уже закрыт: ни состояния,
   ни исключения. Задача 8.

---

## Решения плана

Дизайн оставил их строителю; здесь они приняты, и исполнитель их не меняет без
записи `Ruling:` в журнале.

- **Стенд — тест страницы, а не генератор.** Ответы страницы — код самого
  приложения, и проще держать страницу внутри приложения, чем собирать
  приложение заново из markdown. Так уже устроена `packages/solo/doc/camera.md`
  с `packages/solo/example/test/camera_rakes_test.dart`. Тест страницы
  `camera_example/test/device_app_page_test.dart`: `codeMissingFrom` держит
  каждый блок `dart` страницы в файлах приложения и тестов, трассы из блоков
  `text` сверяются с журналом подставной платформы, фразы прозы — через
  `_says`. `tool/check_traces.py` и генератор не нужны; цели дизайна — блок
  собирается, попытки и ответы идут, трассы сверены — выполняет этот тест.
  Дизайн дал выбор между расширением `tool/flutter_snippets.py` и своим
  генератором; тест страницы — третий путь, и он вынесен владельцу при
  одобрении плана. Тест строится по `camera_rakes_test.dart`: блоки ответа
  держатся `under:` своего заголовка, блоки попытки — в файле попыток, трассы —
  в общем журнале прогона (`test/support/journal.dart`): строки платформы,
  смены состояния и пойманные исключения.
- **Прежние версии ответов** — `test/support/device_app_steps.dart`. Задача,
  которая меняет метод, уже процитированный страницей, переносит его прежнюю
  версию туда тем же коммитом, и раздел, цитирующий прежнюю, держится этим
  файлом. Так тест страницы не краснеет в чужой задаче.
- **Пятая копия `page_code.dart`** — в `camera_example/test/support/`: тест
  страницы не может жить в `packages/flutter_solo/test/`, потому что `floor`
  гоняет тесты пакета из архива, а приложения в архиве нет.
  `tool/check_page_code.py` получает пятую копию, шапки четырёх старых копий
  называют её.
- **Подставная платформа одна** —
  `camera_example/test/support/fake_camera_platform.dart`, и для тестов
  приложения, и для вариантов bloc.
- **Вариант bloc** — код теста: `camera_example/test/support/bloc_camera.dart`;
  `flutter_bloc` и `bloc_concurrency` — dev-зависимости приложения.
- **Пол `camera`** проверяется шагом задания `floor`: на Flutter 3.38.1
  `flutter pub downgrade` и `flutter test` приложения, затем проверка, что
  в `pubspec.lock` стоит `camera` 0.12.0+2. Пробный прогон — уже в конце задачи
  1, шаг в CI — задача 12. Если `downgrade` на полу не разрешается, шаг
  не заводится, а отказ записывается в `docs/settled.md`.
- **Подпись iOS** — файл `ios/Flutter/Signing.xcconfig` с `DEVELOPMENT_TEAM`
  вне гита (`.gitignore` приложения), подключённый через `#include?`
  из `Debug.xcconfig` и `Release.xcconfig`. Команду разработчика исполнитель
  спрашивает у владельца, в репозиторий она не идёт.
- **Зонды на телефонах — до кода разделов**, задача 2, вместе с ручным списком
  владельцу: правила подставной платформы для разделов 4–6 иначе были бы
  выдуманы. Финальная проверка на телефонах остаётся последним этапом, задача
  13, и перепроверяет ответы.
- **Освобождение камеры — своя команда `release()`.** `close()` у `Solo`
  не ждёт ничего, что запущено в `onClose` (dartdoc `onClose`
  в `packages/solo/lib/src/solo.dart`), а переопределять `close()` dartdoc
  запрещает. Поэтому ветвь закрытия экрана ждёт `release().done`, потом зовёт
  `close()`, как раздел «Awaiting the disposal» страницы
  `packages/solo/doc/camera.md`. Это член приложения, а не API.
- **Уход в фон — по `hidden`, а не по `inactive`.** На iOS `inactive` приходит
  и от системного диалога разрешения, и от шторки; README плагина освобождает
  камеру на `inactive`, и это кандидат в первую попытку раздела 4. Что выбрать,
  подтверждает iPhone в задаче 2.
- **Требования разделов**, которые дизайн отдал разделам:
  - 1: вспышка — каждое нажатие применяется по порядку, итог — последнее;
    снимок во время снимка — нажатие пропадает; смена камеры во время снимка —
    ждёт конца снимка.
  - 2: запись идёт дальше с другой камеры, файл один; «стоп» во время смены
    ждёт её конца.
  - 3: снимок, начатый до ухода с экрана, доходит до главного экрана; новый
    экран камеры открывает камеру только после того, как старый её отпустил.
  - 4: запись, прерванная уходом в фон, сохраняется и доходит до главного
    экрана; камера освобождается; при возврате открывается снова, и только
    после освобождения.
  - 5: камера, отнятая извне или упавшая, переводит экран в сбой с кнопкой
    «повторить»; повтор открывает камеру заново.
  - 6: отказ в разрешении — экран с объяснением, что разрешить: камеру или
    микрофон. Обычный отказ — кнопка «повторить», которая спросит снова; отказ
    без вопроса (`…WithoutPrompt`) — «разрешите в Settings»; ограничение
    (`…Restricted`) — «запрещено политикой устройства».

## Имена

Пути в задачах — от `packages/flutter_solo/camera_example/`, кроме тех, что
начинаются с `packages/`, `docs/`, `tool/`, `site/` или `.github/`: те —
от корня. Имена ниже — общие для всех задач; задача, которая их вводит,
указана.

- `flutter_solo_camera_example` — имя пакета приложения, задача 1.
- `FakeCameraPlatform` — подставная `CameraPlatform`,
  `test/support/fake_camera_platform.dart`, задача 1.
- Первые попытки — код, к которому ведёт плагин,
  `test/support/device_app_attempts.dart`, задача 2.
- `CameraState` и подклассы — `lib/camera_state.dart`, задача 3.
- `CameraSession` — контроллер на `Solo<CameraState>`,
  `lib/camera_session.dart`, задача 3.
- `CameraScreen`, `CameraView` — экран камеры, `lib/camera_screen.dart`, задача
  3.
- `CameraApp`, `HomeScreen` — приложение и главный экран,
  `lib/camera_app.dart`, задача 3.
- `Journal` — общий журнал прогона, `test/support/journal.dart`, задача 3.
- Прежние версии ответов — `test/support/device_app_steps.dart`, с задачи 4.
- `CameraBloc`, `BlocCameraScreen` — вариант bloc,
  `test/support/bloc_camera.dart`, задача 10.

Состояние, `lib/camera_state.dart`:

```dart
sealed class CameraState { const CameraState(); }
final class Closed extends CameraState { const Closed(); }
final class Opening extends CameraState { const Opening(); }
final class NoCamera extends CameraState { const NoCamera(); }
final class Ready extends CameraState {
  const Ready({
    required this.camera,
    required this.flash,
    required this.recording,
  });
  final CameraController camera;
  final FlashMode flash;
  final bool recording;
}
final class Broken extends CameraState {
  const Broken(this.error);
  final Object error;
}
final class Denied extends CameraState {
  const Denied(this.code);
  final String code;
}
```

Не `Failed`: это имя исхода `async_job`, его реэкспортируют `solo`,
`flutter_solo` и scopo, и импорт стал бы неоднозначным.

Контроллер, `lib/camera_session.dart`:

```dart
final class CameraSession extends Solo<CameraState> {
  CameraSession({required void Function(XFile file) onCaptured});
  Job<void> open();
  Job<XFile?> takePicture();
  Job<void> cycleFlash(); // off -> auto -> always -> off
  Job<void> switchCamera(); // to the next of availableCameras()
  Job<void> startRecording();
  Job<XFile?> stopRecording();
  Job<void> suspend(); // the app leaves the foreground
  Job<void> resume(); // the app comes back
  Job<void> release(); // frees the camera on the platform, awaited
}
```

Тела, ключи, политики — дело задач 3–8; страница показывает, что вышло.
`close()` — свой у `Solo`, перед ним владелец ждёт `release().done`. Состояние
читается через `currentState` (у `Solo` нет `state`). Снимок и видео уходят
наверх через `onCaptured`: главный экран держит последний файл и сам живёт
дольше экрана камеры.

Журнал подставной платформы — строки `FakeCameraPlatform.log`, по одной
на начало и конец каждого вызова, который на телефоне занимает время:

```text
create back #1
initialize #1 start
initialize #1 end
capture #1 start
capture #1 end
flash #1 auto
switch #1 front start
switch #1 front end
record #1 start
stop #1 start
record #1 end
dispose #1 start
dispose #1 end
```

`Journal` теста добавляет к ним строки `state Ready`, `state Broken`
и `error CameraException(…)`. Трассы на странице — отрезки журнала. Порядок
в тестах сверяется `containsAllInOrder`, а не `indexOf`: строка, которой нет,
даёт `-1` и прошла бы любое «раньше». Длительности по умолчанию — поля
`FakeCameraPlatform`: открытие 100 мс, снимок 300 мс, смена камеры 150 мс,
освобождение 50 мс, остановка записи 100 мс; тесты идут на фальшивых часах
`testWidgets`.

---

### Задача 1: каркас приложения, подставная платформа, CI

**Файлы:**
- Создать: `packages/flutter_solo/camera_example/` — `flutter create
  --platforms android,ios --org dev.yet_another --project-name
  flutter_solo_camera_example`; затем `pubspec.yaml`, `pubspec_overrides.yaml`,
  `analysis_options.yaml` (копия из `example/`), `lib/main.dart`,
  `test/support/fake_camera_platform.dart`,
  `test/fake_camera_platform_test.dart`, `.gitignore`.
- Изменить: `packages/flutter_solo/.pubignore`, `.github/workflows/gate.yml`
  (задание `flutter`, ключи кэша трёх заданий), `AGENTS.md` (разделы «Проверки»
  и «Оверрайды разработки»), `ios/Runner/Info.plist`,
  `android/app/build.gradle.kts`.
- Удалить: `README.md` приложения,
  `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md`,
  `test/widget_test.dart`. В `camera_example/` не остаётся ни одного `.md`:
  проверки `docs` обходят `packages/**/*.md`.

**Интерфейсы:**
- Производит: `FakeCameraPlatform extends CameraPlatform`. Переопределяет то,
  что зовёт `CameraController`: `availableCameras`, `createCameraWithSettings`,
  `initializeCamera`, `onCameraInitialized` (событие с размером превью — без
  него `initialize()` не кончается), `onCameraError`, `onCameraClosing`,
  `onDeviceOrientationChanged`, `takePicture`, `setFlashMode`,
  `setDescriptionWhileRecording`, `startVideoCapturing`, `stopVideoRecording`,
  `dispose`, `buildPreview` (базовый бросает `UnimplementedError`). Поля
  `List<CameraDescription> cameras` (задняя `back`, передняя `front`),
  `Duration openTime`, `captureTime`, `switchTime`, `disposeTime`, `stopTime`,
  `PlatformException? failOpen`, `List<String> log`, методами
  `void closeFromOutside(int cameraId)` (шлёт `CameraClosingEvent`)
  и `void failFromOutside(int cameraId, String description)` (шлёт
  `CameraErrorEvent`); `int get openCameras` — сколько камер создано и ещё
  не освобождено.

- [ ] **Шаг 1: тест подставной платформы**

```dart
testWidgets('the fake logs an opening and a shot', (tester) async {
  final platform = FakeCameraPlatform();
  CameraPlatform.instance = platform;
  final cameras = await availableCameras();
  final camera = CameraController(cameras.first, ResolutionPreset.low);
  final opened = camera.initialize();
  await tester.pump(platform.openTime);
  await opened;
  final shot = camera.takePicture();
  await tester.pump(platform.captureTime);
  await shot;
  final closed = camera.dispose();
  await tester.pump(platform.disposeTime);
  await closed;
  expect(platform.log, [
    'create back #1', 'initialize #1 start', 'initialize #1 end',
    'capture #1 start', 'capture #1 end',
    'dispose #1 start', 'dispose #1 end',
  ]);
  expect(platform.openCameras, 0);
});
```

- [ ] **Шаг 2:** `cd packages/flutter_solo/camera_example && flutter test` —
  ожидается: не компилируется, `FakeCameraPlatform` не определён.
- [ ] **Шаг 3:** `FakeCameraPlatform` по интерфейсу выше; события
  инициализации — через `StreamController.broadcast` на камеру.
- [ ] **Шаг 4:** `flutter test` — зелёный.
- [ ] **Шаг 5: платформенные проекты.** `Info.plist`:
  `NSCameraUsageDescription` и `NSMicrophoneUsageDescription` с английской
  фразой о том, зачем; `minSdk` — не ниже того, что требует
  `camera_android_camerax` выбранной версии. `Signing.xcconfig` — по разделу
  «Решения плана».
- [ ] **Шаг 6: зависимости.** `pubspec.yaml`: `camera: ^0.12.0+2`,
  `camera_platform_interface` с той нижней границей, что требует `camera`
  0.12.0+2 (`CameraPlatform` и события плагин наружу не отдаёт,
  а `depend_on_referenced_packages` требует прямой зависимости),
  `flutter_solo: {path: ../}`, `scopo: ^1.0.0`; dev — `flutter_test`,
  `integration_test` (оба `sdk: flutter`), `flutter_lints: ^6.0.0`,
  `flutter_bloc: ^9.1.1`, `bloc_concurrency: ^0.3.0`.
  `pubspec_overrides.yaml` — как у `example/`, путь `../../solo`.
- [ ] **Шаг 7: архив.** В `.pubignore` `flutter_solo` — строка
  `camera_example/` с комментарием. Проверка:
  `cd packages/flutter_solo && dart pub publish --dry-run` — в списке файлов
  нет `camera_example`.
- [ ] **Шаг 8: CI.** Задание `flutter`: `flutter pub get` приложения
  в «Dependencies» — до анализа пакета, потому что `flutter analyze`
  `flutter_solo` обходит и `camera_example/`; формат
  `lib test integration_test`; `flutter analyze` и `dart analyze --fatal-infos`
  приложения (`analysis_options.yaml` из `example/` называет плагин
  `solo_lints`, а `flutter analyze` с 3.44 его диагностик не показывает);
  `flutter test` приложения. Ключи кэша —
  с `packages/flutter_solo/camera_example/pubspec.yaml`. Шапка `gate.yml`
  называет приложение одной фразой.
- [ ] **Шаг 9: `AGENTS.md`.** «Проверки» — задание `flutter` проверяет ещё
  и `camera_example`, а локальный `flutter analyze` пакета требует сперва
  `flutter pub get` в `camera_example`; пол поднимается и в `pubspec.yaml`
  приложения; приложение зависит от scopo во время работы. «Оверрайды
  разработки» — седьмой файл.
- [ ] **Шаг 10: проверки.** Из `camera_example`:
  `dart format --output=none --set-exit-if-changed lib test integration_test`,
  `flutter analyze`, `flutter test`; из `packages/flutter_solo`:
  `flutter analyze`; из корня — шаги задания `docs` из `gate.yml`, все зелёные.
  Пробный пол: `PATH=~/fvm/versions/3.38.1/bin:$PATH`, в копии дерева
  `flutter pub downgrade` и `flutter test` приложения, строка `camera`
  в `pubspec.lock` — `0.12.0+2`. Не разрешается — стоп, ограничения задачи
  пересматриваются до задачи 2.
- [ ] **Шаг 11: коммит**
  `build(camera_example): scaffold the camera app with a fake platform`.

### Задача 2: зонды первых попыток — подставная платформа и телефоны

Что ломает версия, к которой ведёт плагин, решает, с чего начинается каждый
раздел. Подставная платформа говорит то, что в неё вложили, поэтому сперва
телефон, потом правила подставной платформы под то, что он показал.

**Файлы:**
- Создать: `test/support/device_app_attempts.dart` — экран на голом
  `CameraController`, такой, к какому ведут README плагина и его пример:
  нажатия зовут методы контроллера без очереди; смена камеры —
  `setDescription`; уход с экрана — `dispose()` в `State.dispose`; жизненный
  цикл — по разделу «Handling Lifecycle states» README плагина; ошибки —
  `value.errorDescription`.
- Создать: `integration_test/attempts_test.dart` — те же попытки на настоящей
  камере, печать того, что произошло.
- Прочитать: исходник `camera` 0.12.0+2 и последнего выпуска — что различается
  в `takePicture`, `dispose`, `setDescription`, обработке ошибок.
- Создать: `test/attempts_test.dart` — те же попытки на подставной платформе.
- Создать: `docs/records/2026-11/<дата>-device-app-probes-report.md`.

**Интерфейсы:**
- Потребляет: `FakeCameraPlatform` задачи 1.
- Производит: виджеты попыток, по одному на раздел, с именами `FirstAttempt<N>`
  или по сути (`EagerShutter`), — исполнитель выбирает, страница цитирует их
  как есть; правила подставной платформы, подогнанные под телефоны.

- [ ] **Шаг 1:** попытки 1–6 в `device_app_attempts.dart`.
- [ ] **Шаг 2: телефоны.** Скилл `device-lease`: `take_device` перед каждым
  телефоном, `drop_device` после. Galaxy A55 (`RZCXC0LYZ8Y`) и iPhone
  (`00008110-001600DE0E0B801E`):
  `flutter test integration_test/attempts_test.dart -d <id>`. Разрешения
  до прогона: на Android —
  `adb shell pm grant <пакет> android.permission.CAMERA`
  и `android.permission.RECORD_AUDIO` после первой установки; на iOS владелец
  один раз нажимает «Разрешить» — это ожидание владельца, и агент просит о нём
  заранее.
- [ ] **Шаг 2а: список владельцу** — короткий, по шагам, проходится один раз
  здесь: диалог разрешения на iOS и что приходит в жизненный цикл во время
  него; отказ и повторный запуск (`…WithoutPrompt`); другое приложение забирает
  камеру — что приходит, `CameraClosingEvent` или `CameraErrorEvent`, и с каким
  текстом; уход в фон посреди записи на iPhone — что стало с файлом. Ответы —
  в отчёт.
- [ ] **Шаг 3: отчёт.** Для каждой попытки на каждом телефоне — что произошло:
  исключение с текстом, потерянный файл, зависший экран, сбой открытия второй
  камеры, ничего; версии `camera` и его платформенных пакетов, на которых это
  снято.
- [ ] **Шаг 4: правила подставной платформы** — ровно то, что показали
  телефоны: например, открытие второй камеры до освобождения первой бросает
  `PlatformException` с тем кодом, что на телефоне. Каждое правило —
  с комментарием, на каком телефоне оно увидено.
- [ ] **Шаг 5:** `test/attempts_test.dart` — тест на каждую попытку, которая
  ломается, с ожиданием того, что увидено на телефоне. Прогон — на стабильном
  SDK и на полу (`~/fvm/versions/3.38.1`, после `flutter pub downgrade`);
  поломка, которая есть только на одной из версий `camera`, в отчёте так
  и названа.
- [ ] **Шаг 6: решение по разделам** — в отчёт и в журнал исполнителя: раздел
  открывается первой попыткой, если она на телефоне делает то, что требование
  раздела запрещает; иначе — ответом. Поломка в Dart-коде плагина
  (`ChangeNotifier` после `dispose`, исключение `CameraController`) видна
  и на подставной платформе и считается.
- [ ] **Шаг 7:** `flutter test` — зелёный; коммит
  `test(camera_example): probe the first attempts on the phones`.

### Задача 3: контроллер, экраны, тест страницы

**Файлы:**
- Создать: `lib/camera_state.dart`, `lib/camera_session.dart`,
  `lib/camera_screen.dart`, `lib/camera_app.dart`.
- Создать: `test/camera_session_test.dart`, `test/camera_screen_test.dart`,
  `test/device_app_page_test.dart`, `test/support/page_code.dart` (пятая
  копия), `test/support/journal.dart`.
- Создать: `packages/flutter_solo/doc/device-app.md` — только вступление;
  разделы добавляют задачи 4–10, пустых заголовков нет.
- Изменить: `tool/check_page_code.py` (`COPIES` и docstring), шапки четырёх
  копий `page_code.dart`, комментарий о копиях в `gate.yml`,
  `docs/conventions.md` («четыре копии» — «пять копий»).

**Интерфейсы:**
- Потребляет: `FakeCameraPlatform` задачи 1.
- Производит: `CameraState`, `CameraSession`, `CameraScreen`, `CameraApp`
  из раздела «Имена». `CameraScreen` — scope scopo (как его собирает
  `packages/flutter_solo/test/support/readme_scopo.dart`); `scopeKey`
  и `AsyncScopeCoordinator` над `Navigator` в `CameraApp` вводит задача 6 —
  по dartdoc scopo 1.0.0, образца с `scopeKey` в дереве нет.

- [ ] **Шаг 1: тесты.** Каждый тест ставит `CameraPlatform.instance = platform`
  и создаёт `CameraSession(onCaptured: captured.add)`, где `captured` —
  `<XFile>[]` теста; так же и в задачах 4–9.

```dart
testWidgets('open shows the preview', (tester) async { /* … */
  expect(session.currentState, isA<Ready>());
  expect(platform.log.take(3),
      ['create back #1', 'initialize #1 start', 'initialize #1 end']);
});
testWidgets('no camera on the device', (tester) async {
  platform.cameras.clear();
  // open(), pump
  expect(session.currentState, isA<NoCamera>());
  expect(platform.openCameras, 0);
});
testWidgets('the home screen shows the last shot', (tester) async {
  // pump CameraApp, open the camera screen, tap the shutter, go back
  expect(find.byKey(const Key('last-shot')), findsOneWidget);
});
testWidgets('release waits for the platform', (tester) async {
  // open, pump; final done = session.release().done; pump disposeTime;
  // await done, then session.close()
  expect(platform.log,
      containsAllInOrder(['dispose #1 start', 'dispose #1 end']));
  expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
  expect(platform.openCameras, 0);
});
```

- [ ] **Шаг 2:** `flutter test` — не компилируется.
- [ ] **Шаг 3:** `CameraSession.open()`, `release()`, `takePicture()` без защит
  раздела 1, экраны; ветвь закрытия экрана — `release().done`, потом `close()`.
  Кнопки — с ключами `shutter`, `flash`, `switch`, `record`, `retry`.
- [ ] **Шаг 4:** `flutter test` — зелёный.
- [ ] **Шаг 5: страница.** Вступление по дизайну: что за приложение, где лежит
  код (ссылка на `camera_example/` адресом на GitHub, потому что pub.dev
  не показывает файлы вне архива), как запустить (`flutter run` в блоке `sh`),
  одно обещание о коде и трассах.
- [ ] **Шаг 6: тест страницы.**

```dart
test('every block of the page stands in the app or its tests', () {
  expect(codeMissingFrom(_doc, 'lib/camera_session.dart', alsoIn: _files),
      isEmpty);
});
test('no stray fences', () => expect(strayFences(_doc), ['```sh']));
```

  `_doc` — `'../doc/device-app.md'`, `_files` — все `lib/*.dart`,
  `test/*_test.dart` и `test/support/*.dart`, кроме `page_code.dart`. Задачи
  4–10 добавляют проверку на свой раздел: ответ —
  `codeMissingFrom(_doc, …, under: '## …')` против `lib/`
  и `device_app_steps.dart`, попытка — против `device_app_attempts.dart`.
  Сверка трасс — функция `_traceUnder(String heading)`: блок `text` под
  заголовком, строки которого обязаны стоять подряд в `Journal` прогона.
- [ ] **Шаг 7: проверки** задачи 1 шаг 10 и `python3 tool/check_page_code.py`;
  коммит `feat(camera_example): open the camera through a Solo`.

### Задача 4: раздел 1 — быстрые нажатия

**Файлы:** `lib/camera_session.dart`, `lib/camera_screen.dart`,
`test/camera_session_test.dart`, `test/attempts_test.dart`,
`test/device_app_page_test.dart`, `doc/device-app.md`.

- [ ] **Шаг 1: тесты.**

```dart
testWidgets('flash taps apply in order', (tester) async {
  // three cycleFlash() without waiting, pump
  expect(platform.log.where((l) => l.startsWith('flash')),
      ['flash #1 auto', 'flash #1 always', 'flash #1 off']);
});
testWidgets('a shot during a shot is dropped', (tester) async {
  // takePicture() twice, pump captureTime
  expect(platform.log.where((l) => l == 'capture #1 start'), hasLength(1));
  expect(captured, hasLength(1));
});
testWidgets('a switch during a shot waits for it', (tester) async {
  // takePicture(), switchCamera(), pump
  expect(platform.log,
      containsAllInOrder(['capture #1 end', 'dispose #1 start']));
});
testWidgets('a tap while the camera opens waits for it', (tester) async {
  // open(), takePicture() at once, pump
  expect(platform.log,
      containsAllInOrder(['initialize #1 end', 'capture #1 start']));
});
```

- [ ] **Шаг 2:** `flutter test` — файл не компилируется: нет `cycleFlash`
  и `switchCamera`. С заглушками, которые бросают `UnimplementedError`, красные
  первые три; четвёртый может быть зелёным уже с задачи 3 — очередь там есть, —
  и остаётся сторожем.
- [ ] **Шаг 3:** ключи и политики очереди `Solo`, по докам
  `packages/solo/doc/jobs.md`; смена камеры — через `setDescription` плагина.
- [ ] **Шаг 4:** зелёный.
- [ ] **Шаг 5: раздел страницы** по образцу
  `packages/flutter_solo/doc/mixins.md`: требование, `### The first attempt`
  (если задача 2 так решила) с пометкой `// The first attempt: …`, что она
  делает — трасса из прогона, ответ, последний фрагмент — код
  `lib/camera_session.dart`. Тест страницы сверяет трассу.
- [ ] **Шаг 6:** проверки, коммит
  `feat(camera_example): keep rapid taps in order`.

### Задача 5: раздел 2 — смена камеры во время записи

**Файлы:** как у задачи 4.

- [ ] **Шаг 1: тесты.**

```dart
testWidgets('recording goes on across a switch', (tester) async {
  // startRecording(), switchCamera(), stopRecording(), pump
  expect(platform.log, containsAllInOrder(
      ['record #1 start', 'switch #1 front end', 'record #1 end']));
  expect(captured, hasLength(1));
  expect((session.currentState as Ready).recording, isFalse);
});
testWidgets('stop during a switch waits for it', (tester) async {
  // startRecording(), pump; switchCamera(), stopRecording() at once, pump
  expect(platform.log,
      containsAllInOrder(['switch #1 front end', 'stop #1 start']));
});
```

- [ ] **Шаг 2–4:** красный, код, зелёный.
- [ ] **Шаг 5:** раздел. Если задача 2 не нашла поломки (дизайн:
  у `startVideoRecording` `enablePersistentRecording` по умолчанию `true`),
  раздел открывается ответом.
- [ ] **Шаг 6:** коммит
  `feat(camera_example): switch the camera while recording`.

### Задача 6: раздел 3 — уход с экрана, пока снимок не готов

**Файлы:** `lib/camera_screen.dart`, `lib/camera_session.dart`,
`test/camera_screen_test.dart`, `test/attempts_test.dart`,
`test/device_app_page_test.dart`, `doc/device-app.md`.

- [ ] **Шаг 1: тесты.**

```dart
testWidgets('a shot started before leaving reaches home', (tester) async {
  // tap shutter, pop the camera screen at once, pump
  expect(find.byKey(const Key('last-shot')), findsOneWidget);
  expect(platform.log,
      containsAllInOrder(['capture #1 end', 'dispose #1 start']));
});
testWidgets('a new camera screen waits for the old one', (tester) async {
  // pop, push again before dispose ends, pump
  expect(platform.log,
      containsAllInOrder(['dispose #1 end', 'create back #2']));
  expect(platform.openCameras, 1);
});
testWidgets('leaving while the camera opens', (tester) async {
  // push, pop before openTime, pump
  expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
  expect(platform.openCameras, 0);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Шаг 2–4:** красный; ветвь закрытия scope ждёт `release().done`, потом
  `close()`; `scopeKey` с `AsyncScopeCoordinator` над `Navigator` держит новый
  экран до конца; таймаут ожидания `scopeKey` (по умолчанию 3 с) — больше
  самого долгого освобождения; зелёный.
- [ ] **Шаг 5:** раздел; коммит
  `feat(camera_example): let the camera go before the next screen takes it`.

### Задача 7: раздел 4 — приложение уходит в фон посреди записи

**Файлы:** `lib/camera_screen.dart`, `lib/camera_session.dart`, тесты,
страница.

- [ ] **Шаг 1: тесты** — через `tester.binding.handleAppLifecycleStateChanged`.

```dart
testWidgets('recording is kept when the app leaves', (tester) async {
  // startRecording(), lifecycle inactive -> hidden, pump
  expect(captured, hasLength(1));
  expect(platform.openCameras, 0);
});
testWidgets('coming back opens after the release', (tester) async {
  // hidden, then resumed at once, pump
  expect(platform.log,
      containsAllInOrder(['dispose #1 end', 'create back #2']));
  expect(platform.openCameras, 1);
  expect(session.currentState, isA<Ready>());
});
testWidgets('a permission dialog during open releases nothing',
    (tester) async {
  // open(), inactive -> resumed before openTime, pump
  expect(platform.log.where((l) => l.startsWith('dispose')), isEmpty);
  expect(session.currentState, isA<Ready>());
});
```

- [ ] **Шаг 2–4:** красный; `suspend()` и `resume()`, `AppLifecycleListener`
  в экране — состояние, на котором освобождать, по задаче 2; зелёный.
- [ ] **Шаг 5:** раздел; коммит
  `feat(camera_example): release the camera in the background`.

### Задача 8: раздел 5 — потеря камеры

**Файлы:** `lib/camera_session.dart`, `lib/camera_screen.dart`, тесты,
страница.

- [ ] **Шаг 1: тесты.**

```dart
testWidgets('a camera taken away shows the failure', (tester) async {
  platform.closeFromOutside(1);
  await tester.pump();
  expect(session.currentState, isA<Broken>());
  expect(find.byKey(const Key('retry')), findsOneWidget);
});
testWidgets('a platform error shows the failure', (tester) async {
  platform.failFromOutside(1, 'camera error');
  // pump
  expect(session.currentState, isA<Broken>());
});
testWidgets('an error of the camera after a switch shows', (tester) async {
  // switchCamera() without recording, pump; the id is now 2
  platform.failFromOutside(2, 'camera error');
  // pump
  expect(session.currentState, isA<Broken>());
});
testWidgets('retry opens again', (tester) async { /* … */
  expect(session.currentState, isA<Ready>());
});
testWidgets('retry twice opens one camera', (tester) async {
  // two taps on retry, pump
  expect(platform.openCameras, 1);
});
testWidgets('an event after close changes nothing', (tester) async {
  // close, pump, failFromOutside(1, …), pump
  expect(session.currentState, isA<Closed>());
  expect(tester.takeException(), isNull);
});
```

- [ ] **Шаг 2–4:** красный; подписка — поле контроллера, а не `ctx.each`
  в джобе: та держала бы очередь, пока поток не кончится
  (`packages/solo/doc/streams.md`). `cameraId` меняется при каждом открытии
  и при смене камеры без записи, поэтому джоба открытия снимает прежнюю
  подписку и оформляет новую, `onClose` снимает последнюю; событие пишется
  в состояние через `externalSetState` или короткую джобу; зелёный.
- [ ] **Шаг 5:** раздел; коммит `feat(camera_example): recover a lost camera`.

### Задача 9: раздел 6 — нет разрешения

**Файлы:** `lib/camera_session.dart`, `lib/camera_screen.dart`, тесты,
страница.

- [ ] **Шаг 1: тесты** — по одному на код: `CameraAccessDenied`,
  `CameraAccessDeniedWithoutPrompt`, `CameraAccessRestricted`,
  `AudioAccessDenied`, `AudioAccessDeniedWithoutPrompt`,
  `AudioAccessRestricted`.

```dart
for (final code in _deniedCodes) {
  testWidgets('$code explains what to allow', (tester) async {
    platform.failOpen = PlatformException(code: code);
    // open, pump
    expect(session.currentState, isA<Denied>());
    expect(find.textContaining(code.startsWith('Audio') ? 'microphone'
        : 'camera'), findsOneWidget);
    expect(find.textContaining('Settings'),
        code.endsWith('WithoutPrompt') ? findsOneWidget : findsNothing);
    expect(find.byKey(const Key('retry')),
        code.endsWith('Denied') ? findsOneWidget : findsNothing);
    expect(platform.openCameras, 0);
  });
}
```

- [ ] **Шаг 2–4:** красный; разбор кодов в `open()`, текст экрана —
  по требованию раздела 6 в «Решениях плана»; зелёный.
- [ ] **Шаг 5:** раздел; коммит
  `feat(camera_example): explain a denied permission`.

### Задача 10: раздел 7 — тесты и раздел 8 — тот же экран на bloc

**Файлы:**
- Изменить: `doc/device-app.md`, `test/device_app_page_test.dart`.
- Создать: `test/support/bloc_camera.dart`, `test/bloc_camera_test.dart`.

**Интерфейсы:**
- Потребляет: `FakeCameraPlatform`, `CameraState`, тесты задач 3–9.
- Производит: `CameraBloc extends Bloc<CameraEvent, CameraState>` — те же
  состояния; события по командам `CameraSession`; `BlocCameraScreen`
  с `BlocProvider` и `BlocBuilder` — тот же экран, те же ключи кнопок, чтобы
  виджетные ожидания задач 6, 7 и 9 шли и против bloc.

- [ ] **Шаг 1: раздел 7.** Блоки — подставная платформа и по одному тесту
  на ситуацию 1–6 из файлов тестов приложения; правила `doc/testing.md` (часы
  двигает тест, `done` читается до `pump`, закрытие в теле) названы ссылкой
  на тот раздел, а не пересказаны.
- [ ] **Шаг 2: тесты bloc** — те же ожидания задач 4–9 против `CameraBloc`
  и `BlocCameraScreen`, в `test/bloc_camera_test.dart`, на той же платформе.
- [ ] **Шаг 3:** красный.
- [ ] **Шаг 4: `CameraBloc`** — сильнейшие средства: трансформеры
  `bloc_concurrency` (`sequential`, `droppable`), `close()`, `BlocProvider`,
  scopo для порядка владельцев, если иначе нельзя. Каждый механизм —
  с комментарием, какую ситуацию он закрывает.
- [ ] **Шаг 5:** зелёный.
- [ ] **Шаг 6: раздел 8** — блоки bloc, таблица: ситуация, механизмы на bloc,
  механизмы на solo, что понадобилось тестам каждого. Числа и названия
  в таблице — из кода; тест страницы держит каждую строку таблицы фразой
  `_says`.
- [ ] **Шаг 7:** проверки; коммит
  `docs(flutter_solo): test the camera app and price it on bloc`.

### Задача 11: перевод, ссылки, сайт, список изменений

**Файлы:**
- Создать: `docs/ru/flutter_solo/device-app.md`.
- Изменить: `tool/check_translations.py` (`PAIRS`), `site/astro.config.mjs`
  (`page('flutter_solo/device-app', 'A device app', 'Приложение устройства')`
  после `testing`), `packages/flutter_solo/README.md` и `README.ru.md` (ссылка
  на страницу рядом с `doc/testing.md`), `packages/flutter_solo/CHANGELOG.md`
  и `docs/ru/flutter_solo/CHANGELOG.md` («Unreleased», «Documentation», одна
  фраза), `docs/settled.md` (решения раздела «Решения плана», которые ревьюер
  поднял бы снова: тест страницы вместо генератора, приложение вне архива,
  проверка пола `camera`, телефоны вне CI).

- [ ] **Шаг 1:** перевод; изменённые абзацы — через линтер `humanizer--ru`,
  только `ERROR`, шаг «Голос» пропущен.
- [ ] **Шаг 2:** `python3 tool/check_translations.py` — зелёный;
  `python3 ~/.claude/skills/doc-reader/jargon.py` и `bare_names.py` по странице
  и переводу — подозреваемые разобраны.
- [ ] **Шаг 3:** шаги задания `docs` из `gate.yml` — зелёные.
- [ ] **Шаг 4:** коммит
  `docs(flutter_solo): translate and link the device app page`.

### Задача 12: пол `camera`

**Файлы:** `.github/workflows/gate.yml` (задание `floor`) или
`docs/settled.md`.

- [ ] **Шаг 1:** повтор пробы задачи 1 на законченном приложении, локально,
  в копии дерева: `PATH=~/fvm/versions/3.38.1/bin:$PATH` — в `camera_example`
  `flutter pub downgrade`, `flutter test`, затем строка `camera`
  в `pubspec.lock`. Ожидается `version: "0.12.0+2"` и зелёные тесты.
- [ ] **Шаг 2:** сошлось — шаг «The camera app on the floor» в задании `floor`,
  те же три команды, проверка версии через `grep -A3` по `pubspec.lock`.
  Не сошлось — запись в `docs/settled.md` с причиной.
- [ ] **Шаг 3:** коммит `ci: run the camera app on the floor` или
  `docs: settle the floor of the camera app`.

### Задача 13: проверка на телефонах

**Файлы:** `integration_test/app_test.dart`, отчёт
`docs/records/2026-11/<дата>-device-app-phones-report.md`, страница и перевод —
если вывод не сошёлся.

- [ ] **Шаг 1:** `integration_test/app_test.dart` — ситуации 1–4 на настоящей
  камере через `CameraApp`: быстрые нажатия, смена во время записи, уход
  с экрана во время снимка, уход в фон во время записи. Каждая проверка — то,
  что утверждает страница.
- [ ] **Шаг 2:** оба телефона через `device-lease`,
  `flutter test integration_test/app_test.dart -d <id>`; фон на Android — ещё
  и `adb shell input keyevent KEYCODE_HOME` во время записи.
- [ ] **Шаг 3: перепроверка владельцем** — список задачи 2, но уже против
  ответов: диалог разрешения на iOS, отказ без вопроса, другое приложение
  забирает камеру, уход в фон на iPhone посреди записи. Ответы — в отчёт.
- [ ] **Шаг 4:** вывод, который не сошёлся, уходит со страницы или
  переписывается под телефон, в обоих языках; тест страницы и тесты
  приложения — под новое.
- [ ] **Шаг 5:** коммит `test(camera_example): check the page on the phones`.

### Задача 14: вливание

- [ ] **Шаг 1:** из `docs/backlog.md` снимается запись «Страница приложения
  устройства в `flutter_solo`»; `docs/handoff.md` — что сделано и что ждёт
  выпуска; шапки дизайна, плана и отчётов — «сделано» с коммитом.
- [ ] **Шаг 2:** полный прогон: проверки задания `flutter` из дерева
  на стабильном SDK, `flutter test` приложения, задание `docs`,
  `python3 tool/archive_floor.py stage` во временный каталог и `run` по нему
  на полу — `.pubignore` правился.
- [ ] **Шаг 3:** ревью всей ветки на Opus; находки — по правилам `AGENTS.md`
  о ревью.
- [ ] **Шаг 4:** коммит `docs: close the device app work`; вливание `--ff-only`
  в `main` по правилу CLAUDE.md. Пуш — по слову владельца.

## Ревью плана

Ревьюер на Opus 2026-11-13, по копии дерева на коммите `5ba76606`, с зондом
`flutter create` и `pub get` вне дерева. Вердикт: исполнять после правок.
Находки сверены по исходникам и приняты в текст выше тем же коммитом, что этот
раздел.

- К1. `close()` у `Solo` не ждёт освобождения камеры — команда `release()`,
  «Решения плана», задачи 3 и 6.
- В1. Имя `Failed` занято исходом `async_job` — состояние `Broken`.
- В2. `CameraPlatform` и события плагин не экспортирует — зависимость
  `camera_platform_interface`, задача 1.
- В3. Плагин прочитан с 0.12.0+1, а граница с 0.12.0+2 и на стабильном SDK
  разрешается 0.12.2 — общие ограничения, задача 2: обе версии, версии
  в отчёте.
- В4. Ответы ранних разделов перестанут стоять в коде —
  `device_app_steps.dart`.
- В5. Тесты порядка на `indexOf` не краснеют без строки — `containsAllInOrder`,
  журнал с началом и концом смены и остановки.
- В6. Указатель на `streams.md` вёл к подписке в джобе — форма подписки
  названа, тест ошибки после смены камеры.
- В7. У bloc не было экрана — `BlocCameraScreen`.
- В8. Тест страницы вместо генератора — отход от буквы дизайна, вынесен
  владельцу; тест усилен `under:` и общим журналом.
- В9. Попытки на телефонах не запустятся без разрешений — `pm grant`
  на Android, «Разрешить» владельцем на iOS.
- В10. Правила подставной платформы для разделов 5–6 выдумывались бы — ручной
  список владельцу перенесён в задачу 2.
- В11. `inactive` на iOS приходит от диалога разрешения — освобождение
  по `hidden`, тест диалога во время открытия.
- М1–М11. Блок `sh` в `strayFences`, тесты в `_files`, `currentState` вместо
  `state`, красный шаг задачи 4, полный интерфейс подставной платформы,
  `AsyncScopeCoordinator`, `dart analyze` приложения в CI, хвосты «четырёх
  копий» и пола, проба пола в задаче 1 и `run` на полу в задаче 14,
  `docs/handoff.md` после каждой задачи, тексты отказа по кодам — каждая
  в своей задаче.

## Приложение: решения исполнения и отложенные мелочи

Строки журнала исполнителя плана как есть, по-английски, в порядке записи:
каждое решение, принятое по ходу без владельца, с ценой ошибки, и каждая
находка ревью, отложенная как мелкая. Часть отложенного закрыта волной правок
финального ревью — `2026-11-16-device-app-final-review-report.md`, находки
М3–М8.

```text
Ruling: task 1 formats and analyzes `lib test` only; task 13, which creates `integration_test/`, adds it to the format step of CI and AGENTS.md — `dart format` on a missing path fails — cost if wrong: one CI line.
Ruling: task 1 adds the `#include?` lines and the `.gitignore` entry only; the local `Signing.xcconfig` with the team ID is created in task 2, when the first iPhone build needs it, and the ID is asked from the owner then — the ID is not in any repo file — cost if wrong: none, file is local.
Ruling: the floor trial of task 1 runs in a temporary copy outside the repo (pubspec.lock is gitignored, the downgrade would leave the worktree on old versions) — cost if wrong: none.
Task 1: Ruling: fix round 1 also takes the reviewer's minors that later tasks build on — fake streams for unknown/disposed id, _recording reset in dispose, doc comment of the fake, second test for flash/switch/record/failOpen — and the cheap doc minors (gate.yml width 84 and «second run», AGENTS.md «Без них», «тогда как», publication paragraph, .gitignore «owner's») — tasks 2+ consume the fake verbatim — cost if wrong: a few lines.
Task 1: minor (deferred): minSdk = 24 hardcoded instead of flutter.minSdkVersion (commented).
Task 1: Ruling: remove DEVELOPMENT_TEAM by amending 843e7e8c, not by a commit on top — branch not pushed (no remote contains it), the ID must not stay in history — cost if wrong: none.
Task 2: Ruling: `integration_test` joins the CI format step in task 2, which first creates the dir (was task 13) — cost if wrong: none.
Task 2: Ruling: section 5 opens with its first attempt (Galaxy recovers by itself but the screen keeps a stale error and has no retry — the requirement asks for failure with retry and a working retry) — implementer asked to confirm — cost if wrong: section 5 opens with the answer instead, one rewrite in task 8.
Task 2: Ruling: fix round 1 also takes minors 8 (`record #N started` line), 9 (openedOverAnother cascade), 10 (createCameraWithSettings naming), 11 (tautological tests/names) — later tasks consume the fake and the record — cost if wrong: a few lines.
Task 2: Ruling: handoff stays the controller's job (updated after each task by the controller) — the reviewer's handoff finding is closed by the controller's commit, not the implementer.
Task 3: Ruling: the Russian translation docs/ru/flutter_solo/device-app.md, its PAIRS entry and the site page() line move from task 11 into task 3; every later task that edits the page edits the translation in the same commit — AGENTS.md requires a translation edit with every edit of the original, and build_site_test.py fails without the mirror — cost if wrong: none, task 11 keeps README links, CHANGELOG, settled.md.
Task 3: Ruling: fix round 1 also takes minors 1 (release dartdoc «awaits it»), 2 (intro «a call on the camera is a line»), 3 (check_page_code.py docstring «page tests»), 4 (guard: every ```text block of the page is checked by _traceUnder), 5 (/// comment sticking to _doc) — cheap and tasks 4–10 build on the page test — cost if wrong: a few lines.
Task 3: minor (deferred): the trace guard of device_app_page_test.dart relies on test declaration order (red when run alone by a name filter) — re-review: acceptable, the gate runs the whole file.
Task 4: Ruling: the brief's flash strings (auto, always, off) are replaced by what the fake's start value and the cycle give — the test keeps its meaning (three taps reach the platform in order) — cost if wrong: three strings.
Task 4: Ruling: fix round 1 takes minors 1+2 (the flash part of the first attempt shown under «The first attempt» with cycleFlash in the block; phrase about the iPhone said as what the code does), 4 (intro «the code on this page is the app's code» false since first attempts from test/support), 5 (test that the second shot tap gets the first tap's job), 7 (widget test of flash/switch buttons) — the page form «attempt → what it does → answer» is what tasks 5–9 copy, and a page claim must be held by a test — cost if wrong: a few lines.
Task 4: Ruling: minor 3 (Ready.flash vs the new camera after switchCamera — setDescription does not re-apply flash) is not fixed by inventing a fake rule; it goes into task 13 phone criteria and the handoff — the phones were not filmed on it — cost if wrong: a stale flash icon after a switch until task 13.
Task 4: minor (deferred): shutter → switch → shutter during the first shot gives the third tap the first shot's job (no shot on the new camera); page says «queued or running», requirement allows it.
Task 5: Ruling: besides the brief's two tests, one test on FakePhone.iphone — switch at once after startRecording waits for «record #1 started» and takes the while-recording path — it is the test that the answer fixes the iPhone break; first-attempt trace from FakePhone.iphone (android path throws UnsupportedError by design) — cost if wrong: one test.
Task 5: Ruling: fix round 1 takes minors 2 (a sentence reading the answer's trace, as section 1 does) and 4 (screen test checks the icon is back to videocam after stop) — tasks 6–9 copy the section form — cost if wrong: a few lines.
Task 5: minor (deferred): while the recording starts (iPhone up to 2.5 s) the record button shows videocam and a second tap silently does nothing.
Task 6: Ruling: fix round 1 takes minors 1 (translation lost its final newline), 2 (page: what happens when the 10 s expire and why 10 s), 3 (name the Galaxy rules before the first attempt's trace), 4 (80-char marker line in a code block) — page text the reader sees — cost if wrong: a few lines.
Task 6: minor (deferred): untilShutter in the page test duplicates `until` of camera_screen_test.dart; the phrase «a release that comes while the camera opens waits…» is held by a screen test, not by _says.
Task 8: Ruling: a CameraClosingEvent alone does not make Broken — the Galaxy sends it at record start, at a switch and after a stop while the camera stays open (probes record, fake rules lines ~271/287/317); a camera taken away on the Galaxy came as an error event («The camera was already in use…», FakeCameraPlatform.takenOnAndroid), no closing. The brief's first test «a camera taken away shows the failure» uses failFromOutside(1, takenOnAndroid); a new test pins that the Galaxy's closing events during record/switch/stop leave Ready — cost if wrong: a real close-from-outside without an error is not shown (not seen on the phones).
Task 8: Ruling: task 8 also takes the carried failures, as «failure with retry» is its subject — a failed initialize emits Broken and disposes the half-open controller (no leak); a failed stop emits Broken instead of leaving recording true; suspend() releases the camera even if its stop fails (try/finally) — cost if wrong: a few lines and tests.
Task 7: Ruling: I1 is settled by a Galaxy probe in the fix round (controller holds the Galaxy lease, adb home key, no owner needed) before the page keeps its claim; if the stop on hidden fails on the Galaxy, the implementer stops with NEEDS_CONTEXT and the owner decides (stop on inactive means a notification shade stops the recording too) — cost if wrong: section 4's answer redone.
Task 7: Ruling: I2 fixed now (moved from the task 8 carry): suspend() releases the camera and emits a state that does not lie even if the stop throws — cost if wrong: none.
Task 7: Ruling: fix round 1 also takes minors 3 (say what Closed means in suspend vs release), 4 (answer trace on both phones' rules or name why one), 6 (requirement vs trace: home screen vs another app), 7 (answer test checks the video file reached home) — cost if wrong: a few lines.
Task 7: minor (deferred): permission-dialog test duplicated in session and page tests; page names _suspended/_initialize the reader does not see. Owner lease: Galaxy RZCXC0LYZ8Y (adb 192.168.15.157:5555) taken by controller 18:33 until 20:32 for the task 7 probe.
Task 7: minor (deferred): if dispose in suspend()'s finally also throws, its error replaces the stop's error.
Task 8: Ruling: I1 — keep "any error is a lost camera" in code (the event carries only a description string; filtering by plugin text is brittle), but the page says it as the session's choice, not the plugin's, and names its cost: a recoverable error (a failed shot on Galaxy) also ends in Broken and Retry — cost if wrong: one Retry tap after a recoverable error; task 13 checks on phones how often it happens
Task 8: minor (deferred): dispose(-1) after a failed create; page phrase "_letGo releases what the controller has created" — goes to task 9 with Denied
Task 8: minor (deferred): an error during a recording loses the video (never reaches onCaptured) — name it on the page or in task 13
Task 8: minor (deferred): fake writes "camera #N error" for failFromOutside but not for the Galaxy shot-release rule; page defines the line wider
Task 8: minor (deferred): prose — device-app.md:653 "leaves no mark" -> "on the screen"; :703-705 ambiguous "which" (and _initialize serves resume()); ru :637 mixed sentence/list
Task 8: minor (deferred): camerax onCameraError maps every error to every subscribed id — resubscribe-on-id argument holds for iOS and the fake only; task 13
Task 9: minor (deferred): device-app.md:921-923 (+ru) "second time after deny and don't ask again" — by the probes that choice is in the second dialog; the opening after it is the third
Task 9: minor (deferred): device-app.md:862-865 requirement promises Settings when the phone no longer asks; Android cannot — narrow to "when the plugin reports…"
Task 9: minor (deferred): test name 'retry on the Galaxy after "don't ask again" asks nothing' promises more than the fake checks — rename "…comes back the same"
Task 9: minor (deferred): device-app.md:986-990 gives no reason why dispose(-1) is bad (camerax unbindAll ignores id; avfoundation passes -1 to host)
Task 10: minor (deferred): device-app.md:1074 "Every test ends with finish" — app-run cases end with goBack
Task 10: minor (deferred): device-app.md:1300-1302, bloc_camera.dart:110 "A transformer sees a tap only when…" true for sequential(), not any EventTransformer
Task 10: minor (deferred): HomeScreen.camera seam in lib; bloc test rebuilds CameraApp by hand — pass it through CameraApp instead
Task 10: minor (deferred): section 7 does not name the fake's closing events (design item 7 "closing from outside")
Task 10: minor (deferred): test/support/camera_cases.dart 1050 lines; controllerCases/appCases split naturally
Task 10: minor (deferred): section 7 shows `await letCloseEnd(tester);` in finish before the bloc section explains it — one phrase or a forward link
Task 10: minor (deferred): `until` in appCases calls letCloseEnd every frame for solo too; its comment does not say the reason is bloc's
Task 10: minor (deferred): mutant await-close in the mutation script of task 10 is stale (now the code)
Task 10: Ruling: check_doc_shape.py (a step of the docs job) is red on device-app.md:1274 «The same screen on bloc» opens with prose only — a task 10 regression the review missed (the dispatch did not list the check); reopen task 10 with fix round 2 by its implementer, which also takes the parked minors of the same sections (letCloseEnd shown in section 7 before it is explained; «A transformer sees a tap…» said of sequential()) — cost if wrong: one extra round
Task 11: Ruling: fix round 1 also takes minor 1 (settled 160 and 161 name plan tasks — «задаче 12 плана», «последней задаче плана» — episodes that go stale; say them as rules; task 12 corrects 160 if the step is refused) — cost if wrong: none
Task 11: minor (deferred): settled 158 does not say the app runs in the flutter job's checks
Task 12: minor (deferred): settled 160 says «145 тестов зелёные» — a run result that goes stale; «проба на законченном приложении сошлась»
Task 12: minor (deferred): gate.yml:333 «What it proves is the plugin» — the step proves every third-party floor of the app
Task 12: minor (deferred): gate.yml:344-345 two grep -A7 in a row (the first only for the log); -A7 fragile vs block shape — awk on the camera block's version line
Task 13: Ruling: the iPhone findings are fixed now, in one round with the part-1 review findings — (a) after a switch without a recording the session re-applies `ready.flash` with `setFlashMode` (the plugin's new camera starts at auto); during a recording left as is until a phone shows it; (b) «up to 2.5 s» leaves the page, the fake's dartdoc and `releaseTimeout`'s dartdoc for the measured numbers with the build named (profile ~180 ms, debug first start up to 12.6 s); (c) both scope timeouts go from 10 s to 20 s, since the debug first start alone (12.6 s) exceeds 10 s and a longer wait costs only when a release hangs — cost if wrong: a hung release keeps the next screen waiting 10 s longer
Task 13: Ruling: review Important 2 — the :242-244 claim is fixed in the same round as (b): name the build (first recording of a debug process), the fake platform's delay described against that — why: same false-for-profile number as «up to 2.5 s» — cost if wrong: one more sentence to reword
Task 13: minor (deferred): app_test fails only on platform « threw »; session `error …` lines and `state Broken` do not fail it
Task 13: minor (deferred): «back at once (simulated)» feeds all six lifecycle states synchronously, so hidden-before-stop is trivial there
Task 13: minor (deferred): phones-report run table counts 12/14 «green» while the file has 12 cases (runner counts setUpAll/tearDownAll?)
Task 13: minor (deferred): phones-report says simulation in «runs 3–6» at :179 and «runs 2–7» at :298
Task 13: minor (deferred): app_test dartdoc does not give the ready command line for the real background (log file + answer_actions.py ios UDID LOG)
Task 13: minor (deferred): «moves the recording to the other camera» rests on the journal and file length, no frames looked at
Task 13: minor (deferred): two black shots of run 2 (8 KB) pass expectShot (size > 0) — keep open for Galaxy/owner
Task 13: Ruling: implementer concern 3 (the page's bloc does not re-apply the flash after a switch, so it now differs from the session) — the bloc variant gets the same fix in this round, with the shared case in camera_cases.dart covering both — why: section 8 presents the two as the same behaviour — cost if wrong: one handler line in the bloc
Task 13: Ruling: implementer concern 4 (a camera without a flash may fail the re-apply after a switch) — carried to the Galaxy run on Monday as item 10 of the list carried to the Galaxy; no change now — why: the flash button already makes the same call on the same camera, the iPhone front camera accepts it — cost if wrong: a switch to a flashless camera with flash on ends in Broken until fixed
Task 13: minor (deferred): setFlashMode after a switch on a camera without a flash may throw (carried item 10, Galaxy Monday); the page does not mention it
Task 13: minor (deferred): ffmpeg warned once about non-monotonic audio dts in a video recorded across a switch (run 10); both tracks intact
Task 13b: Ruling: the move is task 13b, before the Galaxy part of 13 — why: the Galaxy run on Monday then covers both controllers in one go — cost if wrong: none beyond ordering
Task 13c: Ruling: the torch is task 13c, dispatched after task 13b's review is clean — why: both touch the session, the bloc and app_test — cost if wrong: none beyond ordering
Task 13b: minor (deferred): iPhone run 11 hung after the first «tap controller-solo» (VM service silent); the next four runs passed unchanged — cause unknown
Task 13b: minor (deferred): the floor step's `flutter pub get` on macOS rewrites tracked ios/Flutter/*.xcconfig and creates ios/Podfile (reverted by hand); CI floor runs on Linux
Task 13b: minor (deferred): solo, debug: the first flash tap of the process took ~2 s once
Task 13b: minor (deferred): the flash-taps case's comment promises all three taps before the first answer; on the first case of a debug process the answer came before the second tap (~2 s call) — the case then checks less than it says
Task 13b: minor (deferred): the page does not say the bloc screen shares the `scopeKey` of `CameraScreen` (device-app.md:1397 «with its `scopeKey`»)
Task 13b: minor (deferred): controller_switch_test.dart copies `until` from appCases and nearly repeats «a new camera screen waits for the old one»
Task 13b: minor (deferred): phones report, solo-in-debug paragraph: «3» and «мс» on different lines
Task 13b: Ruling: two small doc items ride with task 13c — the design record's header «ничего не построено» is stale next to the bloc sentence, and section 8 gets the sentence that the bloc held the iPhone runs (Galaxy after Monday) — why: 13c edits section 8 and the records anyway — cost if wrong: two sentences
Task 13c: Ruling: implementer concern 3 (camerax `torchEnabled` not reset on a switch: back → back with the torch on may skip the call) — carried to the Galaxy as item 11 — cost if wrong: a torch that stays dark after a switch on Android
Task 13c: Ruling: M3 (translation makes the bloc the subject of the torch-tap sentence) and M4 (bloc-on-iPhone sentence reads as if the torch ran on the phone) re-graded Important — why: AGENTS.md's translation rule and a reader misled about an unrun check — cost if wrong: two sentences
Task 13c: Ruling: I1 fixed now (put the torch out on the platform before release/suspend/switch to a camera without a torch; the fake models camerax's flag under FakePhone.android; the page says a lost camera is not covered) — supersedes carried item 11 partly; the Galaxy still checks it — cost if wrong: one more round
Task 13c: Ruling: the torch's first attempt (FlippingTorch) is probed on the iPhone in this round (plan Global Constraint: a first attempt not shown on a phone → the section opens with the answer) — cost if wrong: one probe run
Task 13c: minor (deferred): M1 failed relight on back → back switch keeps torch: true; M2 missing edge cases (four taps, failed torch call, leaving with a pending tap, switch during a recording with the torch lit); M5 two unreflowed comment lines
Task 13c: fix round 1 implementer done (commit 51d9803c, 181 green also on the floor, 10 new cases failed first, 10 mutants caught); Ruling: accept its widening — the torch goes out before every switch without a recording, not only to a camera without a torch — why: camerax's flag would leave a back → back switch dark too; closes M1 — cost if wrong: one extra platform call per switch with the torch lit
Task 13c: minor (deferred): the torch tap window has a few ms of margin on the iPhone — a slow frame may turn «off and on while the torch lights» red
Task 13c: minor (deferred): the torch going out before a release was not exercised on the iPhone (the cases put it out with the button first); the Galaxy and a switch with the torch lit are ahead
Ruling: the controller made the two doc fixes itself — the handoff is the controller's file and the record fix is a one-word reference — cost if wrong: a re-read
Task 13c: minor (deferred): the page's "7 ms"/"1 ms" after the first-attempt trace come from the debug probe, not named there
Task 13g: Ruling: M1 (lamp described as seen going dark), M2 («one of three runs» hides the selection of runs) and M3 (denied-permission group not skipped off Android, would turn an iPhone run red; torch-across-a-switch group not run on the iPhone) re-graded Important — why: page claims must be what the phones showed, and a test that reds on the other phone breaks the next iPhone run — cost if wrong: three small edits
Task 13g: Ruling: I1 — prefer (a) teach the fake under FakePhone.android to fail the running shot at the second camera's create, page trace/test/translation follow; fall back to (b) relabel the trace as the fake's, simpler than the phone, only if (a) changes what the section teaches — why: the page calls the fake «on the Galaxy's rules» and run 4 is the Galaxy's rule — cost if wrong: one more fake mode
Task 13g: minor (deferred): M4 record says «code before this task» for the screen-off-during-a-shot loss; the behaviour is the same on the current code, the test now wakes the screen; leaving to the background during a shot is not on the page
Task 13g: minor (deferred): M5 the 3.9 s shot comes from run 2, where stray ACTIONs of run 1 interfered; the record should say whether that shot met one
Task 13g: minor (deferred): M6 owner question 2 names only the technical cost; the user-visible side is 8–15 s of microphone with the Android 12+ indicator lit after Broken — controller carries it into the owner question
Task 13g: minor (deferred): M7 first person in the record («мои other-camera»)
Task 13g: minor (deferred): translation «погасили его за 0,41 с, когда он загорелся» may read as the moment of putting out; «как только он загорелся» is closer to «once it had lit»
Task 13h: Ruling: M1+M3 re-graded Important — why: the task's constraint «a failing or hanging stop must not prevent the release» and the page's listing is the code readers copy; one `finally` fixes both — cost if wrong: one small round
Task 13h: Ruling: M2 re-graded Important and fixed in code, not by scoping the page — why: the owner's decision covers a recording under way, and a recording being stopped is still under way; the page sentence must hold — prefer handing the file of the in-flight stop to `onCaptured` in both controllers; fall back to scoping the sentence only if the code change is out of proportion — cost if wrong: one round
Task 13h: Ruling: M4 re-graded Important — why: a test script must not force-stop a system package on someone's phone; one guard — cost if wrong: one line
Task 13h: minor (deferred): M5 the stop-lost branch is repeated in camera_session.dart and camera_bloc.dart
Task 13h: minor (deferred): M6 «either of the two» / «любой из двух» on the page — name `Release` and `LetGo`
Task 13h: minor (deferred): the session's `suspend` joins the stop without `discard`; if it were ever cancelled during the stop the file would be lost (no path does that today)
Task 13h: minor (deferred): if `dispose` in the `finally` throws too, its error hides the stop's error
Ruling: 13i (leaving the screen) goes before 13j (flash channel) — why: 13i is small and the same shape as 13h, 13j touches the torch code and needs both phones; sequential because both touch the controllers — cost if wrong: none Task 13i (stop a recording when leaving the screen): BASE 8b82c125; brief task-13i-brief.md; Galaxy lease retaken until 17:14; implementer (opus) dispatched
Task 13i: Ruling: the containsAllInOrder deviation, M1, M2, M3, M5 re-graded Important; also the session's `suspend` (stop unbounded, no discard; a release queued behind it waits past the 3 s bound) taken into this round — why: the global constraint on order checks; the record must not merge broken; the bound exists so the release always comes; the page sentence misleads — cost if wrong: one round
Task 13i: Ruling: M4 (handoff name) fixed by the controller with the next handoff update — the handoff is the controller's file — cost if wrong: none
Task 13i: Ruling: close() during the stop of the session's suspend leaves the camera unreleased — real but unreachable in the app (close comes only after release, queued behind suspend); the sound fix (emit Closed before one join) moves Closed ahead of the stop and changes the background order — deferred as a known gap for the final review — cost if wrong: a copied pattern with a theoretical leak
Task 13i: fix round 2/5 (2 addressed, 0 open — run 16 in the Galaxy table, number and unit together; commit d97705d7); Ruling: the controller checked this doc-only 10-line diff itself (row now in the Galaxy table, 5 cells under the 5-column header) instead of dispatching a re-review — cost if wrong: a misplaced table row
Task 13j: Ruling: keep the iPhone channel answer and run 20 in the record until the owner says otherwise; the iPhone branch «torch lit on the next camera» (5 → 0) stays open — cost if wrong: one section to remove
Task 13j: Ruling: ⚠️ resolved by the controller from file times — iPhone run 20 ended 14:38:21, the owner's ban came 14:39:05; the later attempt stopped at the Xcode build; the data stays until the owner rules — cost if wrong: one section to remove
Task 13j: Ruling: M1–M4 re-graded Important and sent as fix round 1 — why: M1 a false promise on the page; M2 a trap in the fake and a part of the brief left undone; M3 the page talks hardware the code no longer touches; M4 the global constraint on order checks — cost if wrong: one round
Final: Ruling: the fix wave takes В1, М1 (cancellable suspend + Ready check), М2 (earlier versions marked on the page) and the one-line falsehoods М3–М8 with «either of the two» — they are false statements on a page people copy from; the rest of the deferred minors stay deferred — cost if wrong: a longer wave
```
