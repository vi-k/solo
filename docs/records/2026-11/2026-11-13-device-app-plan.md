> **Состояние на 2026-11-13:** план написан, ждёт ревью и одобрения
> владельца; ничего не построено.
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
- Нижняя граница `camera` — `^0.12.0+2`.
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
   камера на платформе освобождается ровно один раз, и после закрытия
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
  в `pubspec.lock` стоит `camera` 0.12.0+2. Если `downgrade` на полу
  не разрешается, шаг не заводится, а отказ записывается в `docs/settled.md`.
- **Подпись iOS** — файл `ios/Flutter/Signing.xcconfig` с `DEVELOPMENT_TEAM`
  вне гита (`.gitignore` приложения), подключённый через `#include?`
  из `Debug.xcconfig` и `Release.xcconfig`. Команду разработчика исполнитель
  спрашивает у владельца, в репозиторий она не идёт.
- **Зонды на телефонах — до кода разделов**, задача 2. Финальная проверка
  на телефонах остаётся последним этапом, задача 13.
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
  - 6: отказ в разрешении — экран с объяснением, что разрешить и где; повтор
    доступен.

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
- `CameraBloc` — вариант bloc, `test/support/bloc_camera.dart`, задача 10.

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
final class Failed extends CameraState {
  const Failed(this.error);
  final Object error;
}
final class Denied extends CameraState {
  const Denied(this.code);
  final String code;
}
```

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
}
```

Тела, ключи, политики — дело задач 3–8; страница показывает, что вышло.
`close()` — свой у `Solo`. Снимок и видео уходят наверх через `onCaptured`:
главный экран держит последний файл и сам живёт дольше экрана камеры.

Журнал подставной платформы — строки `FakeCameraPlatform.log`, по одной
на начало и конец каждого вызова, который на телефоне занимает время:

```text
create back #1
initialize #1 start
initialize #1 end
capture #1 start
capture #1 end
flash #1 auto
switch #1 front
record #1 start
record #1 end
dispose #1 start
dispose #1 end
```

Трассы на странице — отрезки этого журнала. Длительности по умолчанию — поля
`FakeCameraPlatform`: открытие 100 мс, снимок 300 мс, смена камеры 150 мс,
освобождение 50 мс; тесты идут на фальшивых часах `testWidgets`.

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
- Производит: `FakeCameraPlatform extends CameraPlatform` с полями
  `List<CameraDescription> cameras` (задняя `back`, передняя `front`),
  `Duration openTime`, `captureTime`, `switchTime`, `disposeTime`,
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
  `lib test integration_test`; `flutter analyze` приложения; `flutter test`
  приложения. Ключи кэша —
  с `packages/flutter_solo/camera_example/pubspec.yaml`. Шапка `gate.yml`
  называет приложение одной фразой.
- [ ] **Шаг 9: `AGENTS.md`.** «Проверки» — задание `flutter` проверяет ещё
  и `camera_example`; «Оверрайды разработки» — седьмой файл.
- [ ] **Шаг 10: проверки.** Из `camera_example`:
  `dart format --output=none --set-exit-if-changed lib test integration_test`,
  `flutter analyze`, `flutter test`; из `packages/flutter_solo`:
  `flutter analyze`; из корня — шаги задания `docs` из `gate.yml`, все зелёные.
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
  `flutter test integration_test/attempts_test.dart -d <id>`. Что требует руки
  человека — разрешение на iOS, другое приложение с камерой, — в этот шаг
  не входит, а записывается в отчёт как «ждёт владельца».
- [ ] **Шаг 3: отчёт.** Для каждой попытки на каждом телефоне — что произошло:
  исключение с текстом, потерянный файл, зависший экран, сбой открытия второй
  камеры, ничего.
- [ ] **Шаг 4: правила подставной платформы** — ровно то, что показали
  телефоны: например, открытие второй камеры до освобождения первой бросает
  `PlatformException` с тем кодом, что на телефоне. Каждое правило —
  с комментарием, на каком телефоне оно увидено.
- [ ] **Шаг 5:** `test/attempts_test.dart` — тест на каждую попытку, которая
  ломается, с ожиданием того, что увидено на телефоне.
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
  копия).
- Создать: `packages/flutter_solo/doc/device-app.md` — только вступление;
  разделы добавляют задачи 4–10, пустых заголовков нет.
- Изменить: `tool/check_page_code.py` (`COPIES`), шапки четырёх копий
  `page_code.dart`, `docs/conventions.md` («четыре копии» — «пять копий»).

**Интерфейсы:**
- Потребляет: `FakeCameraPlatform` задачи 1.
- Производит: `CameraState`, `CameraSession`, `CameraScreen`, `CameraApp`
  из раздела «Имена». `CameraScreen` — scope scopo с `scopeKey`, как
  в `packages/flutter_solo/test/support/readme_scopo.dart`; в этой задаче без
  ожидания освобождения — его вводит задача 6.

- [ ] **Шаг 1: тесты.** Каждый тест ставит `CameraPlatform.instance = platform`
  и создаёт `CameraSession(onCaptured: captured.add)`, где `captured` —
  `<XFile>[]` теста; так же и в задачах 4–9.

```dart
testWidgets('open shows the preview', (tester) async { /* … */
  expect(session.state, isA<Ready>());
  expect(platform.log.take(3),
      ['create back #1', 'initialize #1 start', 'initialize #1 end']);
});
testWidgets('no camera on the device', (tester) async {
  platform.cameras.clear();
  // open(), pump
  expect(session.state, isA<NoCamera>());
  expect(platform.openCameras, 0);
});
testWidgets('the home screen shows the last shot', (tester) async {
  // pump CameraApp, open the camera screen, tap the shutter, go back
  expect(find.byKey(const Key('last-shot')), findsOneWidget);
});
testWidgets('close releases the camera once', (tester) async {
  // open, close, pump disposeTime
  expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
});
```

- [ ] **Шаг 2:** `flutter test` — не компилируется.
- [ ] **Шаг 3:** `CameraSession.open()` и `close()`, `takePicture()` без защит
  раздела 1, экраны. Кнопки — с ключами `shutter`, `flash`, `switch`, `record`,
  `retry`.
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
test('no stray fences', () => expect(strayFences(_doc), isEmpty));
```

  `_doc` — `'../doc/device-app.md'`, `_files` — все `lib/*.dart`
  и `test/support/*.dart`, кроме `page_code.dart`. Сверка трасс — функция
  `_traceUnder(String heading)`: блок `text` под заголовком, строки которого
  обязаны стоять подряд в `platform.log` прогона.
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
  expect(platform.log.indexOf('capture #1 end'),
      lessThan(platform.log.indexOf('dispose #1 start')));
});
testWidgets('a tap while the camera opens waits for it', (tester) async {
  // open(), takePicture() at once, pump
  expect(platform.log.indexOf('initialize #1 end'),
      lessThan(platform.log.indexOf('capture #1 start')));
});
```

- [ ] **Шаг 2:** `flutter test` — первые три красные: нет `cycleFlash`
  и `switchCamera`, второй снимок не отброшен. Четвёртый может быть зелёным уже
  с задачи 3 — очередь там есть; тогда он остаётся сторожем.
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
      ['record #1 start', 'switch #1 front', 'record #1 end']));
  expect(captured, hasLength(1));
  expect((session.state as Ready).recording, isFalse);
});
testWidgets('stop during a switch waits for it', (tester) async {
  expect(platform.log.indexOf('switch #1 front'),
      lessThan(platform.log.indexOf('record #1 end')));
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
  expect(platform.log.indexOf('capture #1 end'),
      lessThan(platform.log.indexOf('dispose #1 start')));
});
testWidgets('a new camera screen waits for the old one', (tester) async {
  // pop, push again before dispose ends, pump
  expect(platform.log.indexOf('dispose #1 end'),
      lessThan(platform.log.indexOf('create back #2')));
});
testWidgets('leaving while the camera opens', (tester) async {
  // push, pop before openTime, pump
  expect(platform.log.where((l) => l == 'dispose #1 start'), hasLength(1));
  expect(platform.openCameras, 0);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Шаг 2–4:** красный; ожидаемое закрытие — ветвь закрытия scope ждёт
  `session.close()`, `scopeKey` держит новый экран до конца; зелёный.
- [ ] **Шаг 5:** раздел; коммит
  `feat(camera_example): let the camera go before the next screen takes it`.

### Задача 7: раздел 4 — приложение уходит в фон посреди записи

**Файлы:** `lib/camera_screen.dart`, `lib/camera_session.dart`, тесты,
страница.

- [ ] **Шаг 1: тесты** — через `tester.binding.handleAppLifecycleStateChanged`.

```dart
testWidgets('recording is kept when the app leaves', (tester) async {
  // startRecording(), lifecycle inactive, pump
  expect(captured, hasLength(1));
  expect(platform.openCameras, 0);
});
testWidgets('coming back opens after the release', (tester) async {
  // inactive, resumed at once, pump
  expect(platform.log.indexOf('dispose #1 end'),
      lessThan(platform.log.indexOf('create back #2')));
  expect(session.state, isA<Ready>());
});
```

- [ ] **Шаг 2–4:** красный; `suspend()` и `resume()`, слушатель жизненного
  цикла — в экране; зелёный.
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
  expect(session.state, isA<Failed>());
  expect(find.byKey(const Key('retry')), findsOneWidget);
});
testWidgets('a platform error shows the failure', (tester) async {
  platform.failFromOutside(1, 'camera error');
  // pump
  expect(session.state, isA<Failed>());
});
testWidgets('retry opens again', (tester) async { /* … */
  expect(session.state, isA<Ready>());
});
testWidgets('retry twice opens one camera', (tester) async {
  // two taps on retry, pump
  expect(platform.openCameras, 1);
});
testWidgets('an event after close changes nothing', (tester) async {
  // close, pump, failFromOutside(1, …), pump
  expect(session.state, isA<Closed>());
  expect(tester.takeException(), isNull);
});
```

- [ ] **Шаг 2–4:** красный; подписка на `onCameraClosing` и `onCameraError`
  платформы — так, как подписки держит `solo` (`packages/solo/doc/streams.md`),
  чтобы закрытие снимало их; зелёный.
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
    expect(session.state, isA<Denied>());
    expect(find.textContaining('Settings'), findsOneWidget);
    expect(platform.openCameras, 0);
  });
}
```

- [ ] **Шаг 2–4:** красный; разбор кодов в `open()`, текст экрана — что
  разрешить (камеру или микрофон) и что `WithoutPrompt` значит «только
  в настройках»; зелёный.
- [ ] **Шаг 5:** раздел; коммит
  `feat(camera_example): explain a denied permission`.

### Задача 10: раздел 7 — тесты и раздел 8 — тот же экран на bloc

**Файлы:**
- Изменить: `doc/device-app.md`, `test/device_app_page_test.dart`.
- Создать: `test/support/bloc_camera.dart`, `test/bloc_camera_test.dart`.

**Интерфейсы:**
- Потребляет: `FakeCameraPlatform`, `CameraState`, тесты задач 3–9.
- Производит: `CameraBloc extends Bloc<CameraEvent, CameraState>` — те же
  состояния; события по командам `CameraSession`.

- [ ] **Шаг 1: раздел 7.** Блоки — подставная платформа и по одному тесту
  на ситуацию 1–6 из файлов тестов приложения; правила `doc/testing.md` (часы
  двигает тест, `done` читается до `pump`, закрытие в теле) названы ссылкой
  на тот раздел, а не пересказаны.
- [ ] **Шаг 2: тесты bloc** — те же ожидания задач 4–9 против `CameraBloc`,
  в `test/bloc_camera_test.dart`, на той же платформе.
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

- [ ] **Шаг 1:** локально, в копии дерева:
  `PATH=~/fvm/versions/3.38.1/bin:$PATH` — в `camera_example`
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
- [ ] **Шаг 3: список владельцу** — короткий, по шагам: диалог разрешения
  на iOS, отказ и повторный запуск, другое приложение забирает камеру, то же
  на Android, если `adb` этого не делает. Владелец проходит его один раз;
  ответы — в отчёт.
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
  `python3 tool/archive_floor.py stage` во временный каталог.
- [ ] **Шаг 3:** ревью всей ветки на Opus; находки — по правилам `AGENTS.md`
  о ревью.
- [ ] **Шаг 4:** коммит `docs: close the device app work`; вливание `--ff-only`
  в `main` по правилу CLAUDE.md. Пуш — по слову владельца.
