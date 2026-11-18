> **Состояние на 2026-11-18:** зонд сделан, его код в `main` не идёт:
> приложение остаётся на своей форме. Приём записан на странице времени ядра
> коммитом `docs(async_job): a bounded wait for a call that may not return`,
> решения 10 и 112 `docs/settled.md` дополнены.
> **Что это:** зонд, можно ли выразить границы платформы приложения камеры
> на примитивах `async_job`: три попытки, вердикт по каждому правилу и решение
> владельца.
> **Связанные записи:** `2026-11-13-device-app-design.md`,
> `2026-11-13-device-app-phones-report.md`,
> `2026-11-13-device-app-probes-report.md`, `2026-10-27-ctx-child-design.md`,
> `2026-10-06-job-timeout-design.md`.

# Зонд: границы платформы камеры на примитивах ядра

## Вопрос

Приложение `packages/flutter_solo/camera_example` переживает глючный плагин
кодом, написанным руками, а не примитивами ядра. Вопрос зонда: может ли ядро
(`packages/async_job`) выразить этот код чисто, а если нет — чего именно ему
не хватает. Решение владельца 2026-11-17: «Делай зонд на примитивах ядра».

Код зонда жил в приложении, на отдельной ветке; `lib` ядра, `solo`
и `flutter_solo` не менялись, новых членов API не было. Проверка —
`flutter test` приложения на Flutter 3.50: 291 тест, общие случаи
`test/support/camera_cases.dart` гоняются на обоих контроллерах, `solo` и bloc.
Тесты не правились: тест, который пришлось бы поменять, был бы находкой.

## Три правила

Правила, которые приложение держит руками:

1. **Граница на каждом вызове платформы, который может зависнуть.**
   `stopInTime` — `Future.timeout(stopTimeout)`, 3 с; по таймауту бросает
   `CameraException('stopTimeout', …)`, и экран уходит в `Broken`.
   `stopBeforeRelease` — `releaseStopTimeout`, 3 с. Освобождение целиком —
   `releaseTimeout`, 20 с.
2. **Позднему ответу не верят.** Стоп, от которого отказались, может
   завершиться позже: он не должен вернуть экран в `Ready` или отдать видео
   дважды.
3. **Сдавшийся ресурс помечается.** `_stopGaveUp` — `Expando<bool>`
   на контроллере камеры, его ставит `stopInTime` по таймауту.
   `stopBeforeRelease` по нему не шлёт второй стоп этой камере.

Четвёртое место, где приложение ждёт руками, — «`Ready` ещё не устоялся»: ждёт
только тест, одну секунду. Зонд его не трогал: ядро не даёт для него ничего
естественного.

Исходная форма, `camera_state.dart`:

```dart
const releaseStopTimeout = Duration(seconds: 3);
const stopTimeout = Duration(seconds: 3);
final _stopGaveUp = Expando<bool>();

Future<XFile> stopInTime(CameraController camera) =>
    camera.stopVideoRecording().timeout(
      stopTimeout,
      onTimeout: () {
        _stopGaveUp[camera] = true;
        throw CameraException(
          'stopTimeout',
          'The recording did not stop in ${stopTimeout.inSeconds} s.',
        );
      },
    );

Future<bool> stopBeforeRelease(
  CameraController camera,
  void Function(XFile file) onCaptured,
) async {
  if (_stopGaveUp[camera] ?? false) return false;
  final XFile file;
  try {
    file = await camera.stopVideoRecording().timeout(releaseStopTimeout);
  } on CameraException {
    return true;
  } on TimeoutException {
    return false;
  }
  onCaptured(file);
  return true;
}
```

`CameraSession.stopRecording` ждёт стоп целиком:
`file = await ctx.join(() => stopInTime(camera), discard: onCaptured);`,
и на `CameraException` ставит `Broken` и отпускает камеру. Потеря камеры
(`_lose`) ставит `Broken` и запускает задачу `_letGo(camera, lost: true)`
с `first: true`; если камера ещё пишет, задача зовёт `stopBeforeRelease`, потом
`dispose`. Bloc-контроллер зовёт `stopInTime` в `_stopRecording`
и `stopBeforeRelease` в `_letGo` и `_suspend`.

## Попытка A: ребёнок со сроком

Словарь ядра ведёт к сроку шага: шаг со сроком — ребёнок со сроком (решение 10
`docs/settled.md`). `stopRecording`:

```dart
try {
  file = await ctx.run(
    ctx.child(
      (ctx) => ctx.abandonable(camera.stopVideoRecording),
      key: 'stop',
      timeout: stopTimeout,
    ),
    discard: onCaptured,
  );
} on Cancelled catch (cancelled) {
  if (cancelled.reason is! TimeoutCancelReason) rethrow;
  markStopGaveUp(camera);
  ctx.check();
  ctx.emit(Broken(stopTimeoutError()));
  _letGo(camera);
  return null;
}
```

`flutter test`: `+283 -8`. Падения:

- три варианта «a loss during a stop that hangs: no second stop»: журнал
  `['stop #1 start', 'camera #1 error', 'stop #1 start']` вместо `dispose`
  после ошибки камеры;
- «a camera lost while a stop runs: the stop of the record button hands its
  video on»: два `stop #1 start`;
- «a stop that ends after the bound hands nothing on»:
  `A CameraController was used after being disposed.`
  из `CameraController.stopVideoRecording` через `JobContextBase._race`, ошибка
  дошла до зоны;
- четыре теста страницы `device-app.md`, которая цитирует код `CameraSession`.

Механизм. `SoloContext.child` наследует правила родителя: `W` и `keepWhile`.
Задача стопа идёт под правилом `Ready`. Потеря камеры ставит `Broken`, правила
переоцениваются у идущих задач, и отмена по правилу доходит до ребёнка сразу.
Ребёнок ждёт стоп через `abandonable` и бросает его на полпути, задача
кончается, и `_letGo(lost: true)` видит камеру всё ещё пишущей и шлёт второй
стоп. Отметка не ставится: срока не было, была отмена по правилу. С `join`
в ребёнке вместо `abandonable` срок ребёнка тоже ждал бы стоп, и зависший стоп
держал бы его без границы.

## Попытка A2: ребёнок со сроком в `uncancellable`

Решение 112 `docs/settled.md` давало рецепт шага со сроком, который отмена
родителя не прерывает: `ctx.uncancellable` вокруг `ctx.run(ctx.child(...))`.
Ребёнок здесь сделан `job(...)` движка, а не `ctx.child`, и обёрнут секцией:

```dart
file = await ctx.uncancellable(
  () => ctx.run(
    job<CameraState, XFile>(
      (ctx) => ctx.abandonable(camera.stopVideoRecording),
      key: 'stop',
      timeout: stopTimeout,
    ),
    discard: onCaptured,
  ),
);
```

Тот же `+283 -8`, те же падения. Механизм: правила `solo` неотклоняемы (решение
50). Секция `uncancellable` придерживает только отклоняемую отмену (решение 5):
неотклоняемая отмена задачи стопа принимается сразу, каскадом уходит к ребёнку,
и ребёнок бросает стоп так же, как в попытке A. Простой `cancel()` в ядре
секция держит; правило движка — нет.

## Попытка B: корневой `Job` вне дерева

Отмену по правилу не пережить ни одному ребёнку. Остаётся корневая задача,
которую дерево `solo` не видит. Код — в `camera_state.dart`, `CameraSession`
и `CameraBloc` не менялись, а в `pubspec.yaml` приложения встала прямая
зависимость `async_job: ^1.0.3`:

```dart
Future<XFile> stopInTime(CameraController camera) async {
  try {
    return await _stop(camera, stopTimeout);
  } on Cancelled {
    _stopGaveUp[camera] = true;
    throw CameraException(
      'stopTimeout',
      'The recording did not stop in ${stopTimeout.inSeconds} s.',
    );
  }
}

// stopBeforeRelease: file = await _stop(camera, releaseStopTimeout);
// ... on Cancelled { return false; }

Future<XFile> _stop(CameraController camera, Duration bound) => Job<XFile>(
  (ctx) => ctx.abandonable(camera.stopVideoRecording),
  timeout: bound,
  observer: _lateIgnored,
).value;

final _lateIgnored = _LateIgnored();

final class _LateIgnored extends JobObserver with JobAnswerer {
  @override
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {}
}
```

`flutter test`: `+287 -4`. Падают только четыре теста страницы, где страница
цитирует прежний код: «every block…», «leaving the screen the release waits for
the shot…», «losing the camera the failure is the state…» и «every trace…» как
их следствие. Пробный прогон с пропуском двух цитат дал `+291`. Кода
в `camera_state.dart` стало 74 строки вместо 64, во всех трёх файлах — 146
вместо 128.

Без наблюдателя `_LateIgnored` — `+210 -2`: «a stop that ends after the bound
hands nothing on» в обоих контроллерах, ошибка
`A CameraController was used after being disposed.` уходит в зону и роняет
тест.

Отличия B от исходной формы, мелкие:

- вызов платформы уходит на микрозадачу позже: `Job` стартует на следующей
  микрозадаче;
- файл доходит на несколько микрозадач позже;
- внутри ловится `Cancelled`, а не `TimeoutException`;
- зависший стоп держит замыкание `_race` ядра, пока не вернётся.

## Поздняя ошибка

`Future.timeout` отбрасывает молча всё, что пришло после границы: и значение,
и ошибку. `ctx.abandonable` значение отдаёт в `dispose` или `discard`, а ошибку
передаёт дальше: `onError` наблюдателя, `onUnanswered` у `JobAnswerer`, иначе
зона. Поэтому в попытках A и B проявилась ошибка, которую исходная форма
прятала.

Это `A CameraController was used after being disposed.`: стоп, который вернулся
после `dispose` камеры, пишет `value` контроллера,
а `ChangeNotifier.notifyListeners` проверяет, не освобождён ли он, внутри
`assert`. Бросок есть только в debug; в release поздний стоп проходит молча.
Исходная форма этот бросок прятала, а `abandonable` вынес его на свет, и чтобы
повторить поведение исходной формы, понадобился глушащий наблюдатель.

## Вердикт по правилам

1. **Граница.** На примитивах ядра выражается только корневым `Job` вне дерева
   (B), и читается это хуже `.timeout`: функция, наблюдатель и перевод
   `Cancelled` в `CameraException` вместо одного вызова. Внутри контекста
   `solo` граница вызова, который должен пережить отмену по правилу, ребёнком
   не выражается: правило неотклоняемо и доходит до ребёнка каскадом.
   Освобождение целиком (20 с) — это ожидание scopo (`scopeKeyTimeout`,
   `disposeScopeTimeout` у `AsyncDataScope`), а не ядра; срок ядра считался бы
   от старта тела и `join` не прервал бы.
2. **Поздний ответ.** Позднее значение ядро отводит нативно, в `dispose`.
   Позднюю ошибку — только через наблюдателя, который её глушит.
3. **Отметка.** Остаётся на `Expando`: у ядра нет ничего о состоянии чужого
   ресурса.

## Bloc

Bloc-контроллер не идёт на `solo`, и вопрос был, держит ли ядро само по себе
те же границы внутри обработчика. Держит: форма B живёт в общем
`camera_state.dart`, и bloc-контроллер прошёл тот же набор без изменений. Цена
та же, что у `solo`: корневой `Job`, наблюдатель, перевод исключений.

## Вывод

Форма, которая уже есть в приложении, — `ctx.join` вокруг `Future.timeout`, —
правильная. `join` ждёт вызов целиком сквозь любую отмену, в том числе
неотклоняемую, а `Future.timeout` ограничивает это ожидание и отбрасывает
позднее значение и позднюю ошибку сам, без наблюдателя. Ребёнок со сроком даёт
границу, но бросает вызов при отмене задачи, а это то, ради чего выбран `join`.
Приём не завязан на `solo`: в чистом ядре простой `cancel()` каскадом доходит
до ребёнка так же.

## Решение владельца

2026-11-18: «Не делаем join(timeout:). Запиши зонд и опиши приём на странице
ядра».

Нового члена API нет. Приложение остаётся на своей форме. Страница
`packages/async_job/doc/time.md` получила раздел «A call that may not come
back» с переводом: `ctx.join(device.stop)` висит и после `cancel()`, ребёнок
со сроком даёт границу, но отмена задачи бросает стоп на полпути, и ответ —
`ctx.join(() => device.stop().timeout(...))`, где `TimeoutException` — ошибка
Dart, а не `TimeoutCancelReason` ядра. Код и трассы раздела держат
`packages/async_job/test/time_rakes_test.dart` и `test/support/time_page.dart`.
Решения 10 и 112 `docs/settled.md` указывают на этот приём.
