# solo

`solo` управляет состоянием и асинхронной работой в Dart. Контроллер хранит
текущее состояние и выполняет задачи по одной. Каждая задача может
объявить, в каких состояниях ей разрешено запускаться и продолжать
работу. Вызывающий код может дождаться её результата или запросить отмену.

Пакет подходит для экранов, сессий и устройств, операции которых работают
с общим состоянием и должны выполняться в определённом порядке.
Зависимости от Flutter нет.
[`flutter_solo`](https://pub.dev/packages/flutter_solo) добавляет
контроллер с интерфейсом `ValueListenable` для виджетов Flutter.

## Установка

```sh
dart pub add solo
```

Для Flutter установите `flutter_solo`. Он реэкспортирует `solo`:

```sh
flutter pub add flutter_solo
```

`solo` реэкспортирует [async_job](https://pub.dev/packages/async_job),
который предоставляет задачи, отмену и освобождение ресурсов. Импорт
`package:solo/solo.dart` открывает оба API. Чтобы пользоваться примерами
ниже, предварительно изучать пакет ядра не нужно.

## Быстрый старт

Контроллер предоставляет методы для операций приложения. Здесь `load()`
загружает имя профиля и сообщает о ходе работы через четыре неизменяемых
состояния:

```dart
import 'package:solo/solo.dart';

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class Failure extends ProfileState {
  final Object error;

  const Failure(this.error);
}
```

API в примере возвращает имя после небольшой задержки. Замените его
клиентом API вашего приложения:

```dart
class ProfileApi {
  Future<String> fetchName() => Future.delayed(
        const Duration(milliseconds: 20),
        () => 'Ada Lovelace',
      );
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => run<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        onError: (state, error, stackTrace) => Failure(error),
        onCancel: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`run<ProfileState, String>` создаёт `Job` и ставит её в очередь.
`ProfileState` задаёт тип состояния, с которым может работать тело;
`String` задаёт тип результата. Тело получает контекст `ctx` для
изменения состояния и ожидания с учётом отмены:

- `ctx.emit` обновляет состояние контроллера.
- `ctx.wait` ждёт ответ API или бросает `Cancelled`, если во время
  ожидания `Job` принимает отмену.
- `onError` возвращает состояние для публикации при ошибке `Job`.
- `onCancel` возвращает состояние для публикации при отмене начатой `Job`.

Обработчики состояния вызываются после тела и освобождения его ресурсов.
В этом примере состояние становится `Loaded` при успехе, `Failure` при
ошибке или `Initial` при отмене. Ошибка и отмена остаются исходом `Job`,
даже когда обработчик обновляет состояние.

`Policy.droppable` с `key: 'load'` позволяет повторным вызовам использовать
ту же загрузку, пока она стоит в очереди или выполняется. Второй вызов
возвращает существующую `Job`. После её завершения следующий вызов
может начать новую загрузку.

Вызывающий код ждёт именно эту загрузку через возвращённый `Job<String>`:

```dart
Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  final subscription = profile.stream.listen(print);
  try {
    final job = profile.load();
    profile.load(); // возвращается существующая задача

    print(await job.value);
    if (profile.currentState case Loaded(:final name)) {
      print(name);
    }
  } finally {
    await subscription.cancel();
    await profile.close();
  }
}
```

`profile.currentState` доступен синхронно. `profile.stream` асинхронно
доставляет изменения подписчикам. `job.value` возвращает загруженное имя
или бросает ошибку `Job` либо `Cancelled`. Блок `finally` снимает подписку
и закрывает контроллер даже при ошибке загрузки.

Для отмены используется тот же объект `Job`. Этот отдельный пример
запрашивает отмену сразу, поэтому `Job` может ещё находиться в очереди:

```dart
Future<void> cancelLoading() async {
  final profile = ProfileController(ProfileApi());
  final job = profile.load();

  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  await profile.close();
}
```

`cancel()` ждёт завершения `Job`, включая освобождение ресурсов, если
она успела начаться. При отмене до запуска тела `onCancel` не вызывается.
`Job` может запускать дочерние `Job` как часть своей работы; запустившая
их `Job` является родителем и ждёт их перед собственным завершением.
Следующая `Job` из очереди запускается только после завершения тела,
дочерних `Job`, освобождения ресурсов и обработчика состояния предыдущей.

Страницы ниже подробнее объясняют результаты, политики очереди
и отмену. В частности, отмена `Job` сама по себе не останавливает запрос
к API, который уже был отправлен.

## Почему `currentState`, а не `state`

Метод `ProfileController`, который вдобавок смотрит на сессию:

```dart
Job<String> reload() => run<ProfileState, String>(
      (ctx) async {
        // Снимок чужого контроллера: обычное чтение, и имя об этом
        // говорит.
        final user = session.currentState.user;
        final name = await ctx.wait(() => api.fetchName(user));
        // Собственное состояние задачи: чекпойнт, который бросит
        // `Cancelled`, если за время ожидания задача лишилась состояния.
        if (ctx.state case Loading()) {
          ctx.emit(Loaded(name));
        }
        return name;
      },
    );
```

Тело задачи — замыкание внутри метода контроллера, поэтому все члены
контроллера в теле видны. Обычное чтение, названное `state`, выглядело бы
в точности как `ctx.state`, и тело, набравшее его по привычке, читало бы
состояние после отмены, которую обязано было соблюсти: ни `Cancelled`, ни
проверки `keepWhile`, и весь `S` вместо рабочего типа задачи `W`.
`currentState` вместо чекпойнта по привычке не напишет никто — молчаливое
чтение стало ошибкой компиляции.

Снаружи задачи `currentState` — то самое чтение. Внутри оно остаётся
верным для другого контроллера: `session.currentState` выше — чужой
снимок, и правила этой задачи о нём ничего не говорят.

## Дюжина вызовов

Всё, чем пользуются каждый день, в одном контроллере. `PlayerState`,
`Api` и `Device` принадлежат приложению; остальное — пакет.

```dart
enum _Op { play }

final class Player extends Solo<PlayerState> {
  final Api api;
  final Device device;

  Player(this.api, this.device) : super(const Idle());

  /// Job в очереди контроллера. Корневые Job выполняются по одной.
  SoloJob<Track> play(String id) => run<PlayerState, Track>(
        // Ключом может быть любой объект. Запись — ключ одного запроса,
        // а не операции.
        key: (_Op.play, id),
        // Новый запуск отменяет работающий с тем же ключом.
        policy: Policy.restart,
        // Правила: проверяются перед стартом и в каждой контрольной точке.
        canStart: (state) => state is! Disconnected,
        keepWhile: (state) => state is! Disconnected,
        (ctx) async {
          // Единственный способ изменить состояние: сеттера снаружи нет.
          ctx.emit(const Loading());
          // Отмена прекращает это ожидание сразу; запрос может идти дальше.
          final track = await ctx.wait(() => api.fetch(id));
          // Этого дожидаются в любом случае, а значение освобождается,
          // если Job закончилась раньше, чем тело успело его забрать.
          final handle = await ctx.join(
            () => device.open(track),
            dispose: (handle) => handle.close(),
          );
          // Освобождение идёт в обратном порядке и при любом исходе.
          ctx.onDispose(handle.close);
          // Дочерняя Job: родитель дождётся её перед своим завершением.
          ctx.each(device.position, (childCtx, position) async {
            childCtx.emit(Playing(track, position));
          });
          return track;
        },
      );

  /// События, делящие одну Job в очереди: важна только последняя громкость.
  late final _volume = accumulate<PlayerState, double, void>(
    (ctx, value) => ctx.join(() => device.setVolume(value)),
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 50)),
  );

  SoloJob<void> setVolume(double value) => _volume.add(value);
}
```

На стороне вызова `Job` — это ручка: дождаться исхода или отменить.

```dart
final player = Player(api, device);

final job = player.play('t-1');
switch (await job.done) {
  case Done(:final value):
    print('playing $value');
  case Failed(:final error):
    print('failed: $error');
  case Cancelled(:final reason):
    print('cancelled: $reason');
}

player.setVolume(0.4);
// Выполнить то, что уже в очереди, и перестать принимать работу.
await player.close(mode: SoloCloseMode.drain);
```

## Страницы

Они же на [сайте документации](https://docs.yet-another.dev/ru/solo/), с поиском.

| Страница | О чём |
| --- | --- |
| [Задачи и очередь](../../docs/ru/solo/jobs.md) | Постановка работы, исходы, ключи, политики очереди |
| [Состояние](../../docs/ru/solo/state.md) | Публикация, правила, наблюдение, внешние изменения, состояние после ошибки |
| [Отмена](../../docs/ru/solo/cancellation.md) | `wait`, `join`, `uncancellable`, остановка операции, закрытие |
| [Ресурсы и освобождение](../../docs/ru/solo/resources.md) | `onDispose`, `dispose` и `discard`, передача, порядок |
| [Дочерние задачи и стримы](../../docs/ru/solo/children.md) | Дочерние `Job`, стримы, слежение за другим контроллером |
| [Накопление событий](../../docs/ru/solo/accumulation.md) | `collect`, `accumulate`, debounce и throttle |
| [Ошибки и наблюдение](../../docs/ru/solo/errors.md) | `SoloObserver`, `errorHandler`, `pending`, логи |
| [Тестирование](../../docs/ru/solo/testing.md) | Ожидание исходов, фейковое время, таймауты |
| [Flutter](../../docs/ru/solo/flutter.md) | `SoloListenable`, владение контроллером, перестроение экрана |
| [Пример камеры](../../docs/ru/solo/camera.md) | Один контроллер с правилами, уборкой и устройством |
| [solo и bloc рядом](../../docs/ru/solo/vs-bloc.md) | Десять сценариев на обоих пакетах |

## Рецепты

Ситуации, которые встречаются, и чем их брать. Каждая разобрана на
странице, названной рядом.

| Ситуация | Чем брать | Где |
| --- | --- | --- |
| Из пачки команд важна только последняя | `accumulate` с `merge`, берущим пришедшую | [Команды, где важна только последняя](../../docs/ru/solo/accumulation.md) |
| Ввод в поле поиска | `accumulate` с `AccumulationTiming.debounce` | [Накопление событий](../../docs/ru/solo/accumulation.md) |
| Поздний запрос не должен быть отброшен как дубликат раннего | ключ-запись, `(Op.load, id)` | [Задачи и очередь](../../docs/ru/solo/jobs.md) |
| Ожидающую работу обесценило только что пришедшее | `queue.removeWhere` перед постановкой или `cancelAll()`, если она может уже работать | [Команды, где важна только последняя](../../docs/ru/solo/accumulation.md) |
| Последняя пачка должна уйти до того, как экран исчезнет | `close(mode: SoloCloseMode.drain)` | [Отмена](../../docs/ru/solo/cancellation.md) |
| `close()` не возвращается | `SoloBase.pending` | [Ошибки и наблюдение](../../docs/ru/solo/errors.md) |
| Журналу нужно сказать, какая операция изменила состояние | `SoloTransition` в `onChange` | [Ошибки и наблюдение](../../docs/ru/solo/errors.md) |
| Шаг нельзя прервать на половине | `ctx.join` для вызова, `ctx.uncancellable` для шага | [Отмена](../../docs/ru/solo/cancellation.md) |
| Ресурс, открытый вызовом, которого никто не дождался, всё равно надо закрыть | `dispose` или `discard` у `ctx.wait` и `ctx.join` | [Ресурсы и освобождение](../../docs/ru/solo/resources.md) |
| Виджет перестраивается из-за состояния, которым не пользуется | `select` на `SoloListenable` | [Flutter](../../docs/ru/solo/flutter.md) |
| Очередь нужно на время остановить | задача, ждущая `Completer` в её голове | [Задачи и очередь](../../docs/ru/solo/jobs.md) |
| Событие стрима приходит микротаской позже, и это поздно | `publish` в наследнике `SoloBase`, уведомляющий внутри изменения | [Состояние](../../docs/ru/solo/state.md) |

## Переход с bloc

Вызывающий код обращается к методам контроллера и получает `Job`
для каждой операции. Политика очереди выбирается при каждом вызове,
а все корневые `Job` используют одну очередь.
[solo и bloc рядом](../../docs/ru/solo/vs-bloc.md) содержит соответствия
API и сравнивает десять прикладных сценариев с реализациями на обоих
пакетах.

Пакет не включает политики повторов, встроенные таймауты, пулы
исполнителей, внедрение зависимостей, сохранение состояния на диск
или фильтрацию равных состояний. Если работе нужны отмена и освобождение
ресурсов, но не правила состояния и очередь контроллера, можно
использовать [async_job](https://pub.dev/packages/async_job) напрямую.
Для значения без асинхронного жизненного цикла может хватить
`ValueNotifier`.
