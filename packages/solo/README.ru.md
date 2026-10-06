# solo

`solo` управляет состоянием и асинхронной работой в Dart. Контроллер хранит
текущее состояние и выполняет задачи по одной. Каждая задача может объявить,
в каких состояниях ей разрешено запускаться и продолжать работу. Вызывающий код
может дождаться её результата или запросить отмену.

Пакет подходит для экранов, сессий и устройств, операции которых работают
с общим состоянием и должны выполняться в определённом порядке. Зависимости
от Flutter нет. [`flutter_solo`](https://pub.dev/packages/flutter_solo)
добавляет `SoloListenable` — миксин, который даёт контроллеру интерфейс
`ValueListenable` для виджетов Flutter.

## Установка

```sh
dart pub add solo
```

Для Flutter установите `flutter_solo`. Он реэкспортирует `solo`:

```sh
flutter pub add flutter_solo
```

`solo` реэкспортирует [async_job](https://pub.dev/packages/async_job), который
предоставляет задачи, отмену и освобождение ресурсов. Импорт
`package:solo/solo.dart` открывает оба API. Чтобы пользоваться примерами ниже,
предварительно изучать пакет `async_job` не нужно.

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

API в примере возвращает имя после небольшой задержки. Замените его клиентом
API вашего приложения:

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
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`run<ProfileState, String>` создаёт `Job` и ставит её в очередь. `ProfileState`
задаёт рабочий тип `W`: состояния, с которыми работает тело `Job`. Это может
быть и подтип `S`, типа состояния контроллера. `String` задаёт тип результата.
Тело получает контекст `ctx` для изменения состояния и ожидания с учётом
отмены:

- `ctx.emit` обновляет состояние контроллера.
- `ctx.abandonable` ждёт ответ API или бросает `Cancelled`, если во время
  ожидания `Job` принимает отмену.

Два параметра `run` задают состояние для публикации, если `Job` не завершилась
успехом:

- `onError` возвращает состояние для публикации при ошибке `Job`.
- `onCancel` возвращает состояние для публикации при отмене начатой `Job`.

Обработчики состояния вызываются после тела и освобождения его ресурсов. В этом
примере состояние становится `Loaded` при успехе, `Failure` при ошибке или
`Initial` при отмене. Исходом `Job` остаётся `Failed` или `Cancelled`, даже
когда обработчик обновляет состояние.

`Policy.droppable` с `key: 'load'` позволяет повторным вызовам использовать
ту же загрузку, пока она стоит в очереди или выполняется. Второй вызов
возвращает существующую `Job`. После её завершения следующий вызов может начать
новую загрузку.

Вызывающий код ждёт именно эту загрузку через возвращённую `Job<String>`:

```dart
Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  void onChange() => print(profile.currentState);
  profile.addListener(onChange);
  try {
    final job = profile.load();
    profile.load(); // возвращается существующая Job

    print(await job.value);
    if (profile.currentState case Loaded(:final name)) {
      print(name);
    }
  } finally {
    profile.removeListener(onChange);
    await profile.close();
  }
}
```

`profile.currentState` доступен синхронно, и `addListener` тоже зовёт колбэк
синхронно, внутри самого изменения. `job.value` возвращает загруженное имя или
бросает ошибку `Job` либо `Cancelled`. Блок `finally` снимает слушателя
и закрывает контроллер даже при ошибке загрузки.

Чтобы получать изменения ещё и через broadcast-стрим `stream`, события которого
приходят на следующей микротаске, подмешайте `SoloStream`:

```dart
final class ProfileController extends Solo<ProfileState> with SoloStream {
  // ...то же, что и выше...
}
```

Полную картину доставки, включая `SoloListenable` из `flutter_solo`, см.
в разделе
[«Наблюдение за состоянием»](../../docs/ru/solo/state.md#наблюдение-за-состоянием)
страницы о состоянии.

Для отмены используется тот же объект `Job`. Этот отдельный пример запрашивает
отмену сразу, поэтому `Job` ещё стоит в очереди:

```dart
Future<void> cancelLoading() async {
  final profile = ProfileController(ProfileApi());
  final job = profile.load();

  await job.cancel();
  print(job.outcome); // Cancelled(manual)
  await profile.close();
}
```

`cancel()` ждёт завершения `Job`, включая освобождение ресурсов, если она
успела начаться. При отмене до запуска тела `onCancel` не вызывается. `Job`
может запускать дочерние `Job` как часть своей работы; запустившая их `Job`
является родителем и ждёт их перед собственным завершением. Следующая `Job`
из очереди запускается только после завершения тела, дочерних `Job`,
освобождения ресурсов и обработчика состояния предыдущей.

Страницы ниже подробнее объясняют результаты, политики очереди и отмену.
В частности, отмена `Job` сама по себе не останавливает запрос к API, который
уже был отправлен.

## Почему `currentState`, а не `state`

Допустим, `ProfileController` хранит ещё и `session`, другой контроллер, а API
профиля принимает пользователя: `fetchName(user)`. Метод, который загружает имя
заново, когда профиль уже загружен:

```dart
Job<String> reload() => run<Loaded, String>(
      (ctx) async {
        // Снимок чужого контроллера: обычное чтение, и имя об этом
        // говорит.
        final user = session.currentState.user;
        final name = await ctx.abandonable(() => api.fetchName(user));
        // Собственное состояние этой Job: контрольная точка, которая
        // бросит `Cancelled`, если Job отменена или состояние уже
        // не `Loaded`.
        if (ctx.state.name != name) {
          ctx.emit(Loaded(name));
        }
        return name;
      },
    );
```

Тело `Job` пишется замыканием внутри метода контроллера, поэтому в теле видны
все члены контроллера. `ctx.state` служит контрольной точкой. Перед чтением он
проверяет, что `Job` не отменена и её правила по-прежнему выполняются: рабочий
тип, здесь `Loaded`, и правило `keepWhile`, если оно у `Job` есть, как у `play`
ниже. Обычное чтение, названное `state`, выглядело бы в точности как
`ctx.state`, и тело, набравшее его по привычке, читало бы состояние после
отмены, которую обязано было соблюсти: ни `Cancelled`, ни проверки правил,
и весь `S` вместо `W`, а у `S` нет `name`. Собственное чтение контроллера
называется `currentState`: голое `state` в теле не компилируется,
а `currentState` никто не наберёт по привычке там, где нужна контрольная точка.

Снаружи `Job` состояние читают через `currentState`. Внутри это чтение остаётся
верным для другого контроллера: `session.currentState` выше берёт чужой снимок,
и правила этой `Job` о нём ничего не говорят.

## Дюжина вызовов

Всё, чем пользуются каждый день, в одном контроллере. `PlayerState` с его
состояниями, `Track`, `Download`, `Api` и `Device` принадлежат приложению,
остальное принадлежит пакету.

```dart
enum _Op { play }

final class Player extends Solo<PlayerState> {
  final Api api;
  final Device device;

  Player(this.api, this.device) : super(const Idle()) {
    // Факт извне очереди: он публикуется сразу, и о нём спрашивают
    // правило работающей Job.
    device.onDisconnect = () => externalSetState(const Disconnected());
  }

  /// Job в очереди контроллера. Корневые Job выполняются по одной, и эта
  /// заканчивается, когда трек начинает играть: дальше его играет само
  /// устройство.
  Job<Track> play(String id) => run<PlayerState, Track>(
        // Ключом может быть любой объект. Этот ключ называет операцию,
        // а не трек.
        key: _Op.play,
        // Новый запуск отменяет работающий с тем же ключом.
        policy: Policy.restart,
        // Правило: его спрашивают перед стартом и при каждой смене
        // состояния, пока работает тело, кроме сделанной самим телом
        // через `ctx.emit`.
        keepWhile: (state) => state is! Disconnected,
        // Состояние для публикации, если Job упала или её отменили. Отмена
        // правилом ничего не публикует, и `Disconnected` остаётся.
        onError: (state, error, stackTrace) => const Idle(),
        onCancel: (state, cancelled) => const Idle(),
        (ctx) async {
          // Так тело меняет состояние. Сеттера снаружи нет.
          ctx.emit(const Loading());
          // Этого дожидаются в любом случае: трек, который играет сейчас,
          // останавливается раньше, чем загрузится следующий.
          await ctx.join(device.stop);
          // Отмена прекращает это ожидание сразу; запрос может идти дальше.
          final track = await ctx.abandonable(() => api.fetch(id));
          // Этого тоже дожидаются. `dispose` закрывает скачивание, когда
          // Job заканчивается, или сразу после возврата вызова, если Job
          // за это время отменили.
          final download = await ctx.join(
            () => api.download(track),
            dispose: (download) => download.close(),
          );
          // Дочерняя Job: устройство читает скачанное, и стрим кончается,
          // когда трек начинает играть. `value` этого ждёт.
          await ctx.each(device.load(download), (childCtx, percent) {
            childCtx.emit(Buffering(track, percent));
          }).value;
          ctx.emit(Playing(track));
          return track;
        },
      );

  /// События, делящие одну Job в очереди: важна только последняя громкость.
  late final _volume = accumulate<PlayerState, double, void>(
    (ctx, value) => ctx.join(() => device.setVolume(value)),
    merge: (previous, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 50)),
  );

  Job<void> setVolume(double value) => _volume.add(value);

  // Колбэк снимается раньше, чем состояние станет окончательным: после
  // этого `externalSetState` бросил бы.
  @override
  void onClose() => device.onDisconnect = null;
}
```

На стороне вызова `Job` служит хэндлом: можно дождаться её исхода или отменить
её, как в быстром старте.

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
// Сразу перестать принимать работу, выполнить то, что уже в очереди,
// и закрыться.
await player.close(mode: SoloCloseMode.drain);
```

## Страницы

Они же на [сайте документации](https://docs.yet-another.dev/ru/solo/),
с поиском.

| Страница | О чём |
| --- | --- |
| [Задачи и очередь](../../docs/ru/solo/jobs.md) | Постановка работы, исходы, ключи, политики очереди |
| [Состояние](../../docs/ru/solo/state.md) | Публикация, правила, наблюдение, внешние изменения, состояние после ошибки |
| [Отмена](../../docs/ru/solo/cancellation.md) | `abandonable`, `join`, `pause`, `uncancellable`, `timeout`, остановка операции, закрытие |
| [Ресурсы и освобождение](../../docs/ru/solo/resources.md) | `onDispose`, `dispose` и `discard`, передача, порядок |
| [Дочерние задачи и стримы](../../docs/ru/solo/children.md) | Дочерние `Job`, цепочки, шаги подряд |
| [Стримы](../../docs/ru/solo/streams.md) | `ctx.each` в контроллере, слежение за другим контроллером |
| [Накопление событий](../../docs/ru/solo/accumulation.md) | `collect`, `accumulate`, debounce и throttle |
| [Ошибки и наблюдение](../../docs/ru/solo/errors.md) | `SoloObserver`, `errorHandler`, `pending`, логи |
| [Тестирование](../../docs/ru/solo/testing.md) | Ожидание исходов, фейковое время, таймауты |
| [Flutter](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md) | Пакет `flutter_solo`: `SoloListenable`, владение контроллером, перестроение экрана |
| [Пример камеры](../../docs/ru/solo/camera.md) | Один контроллер с правилами, освобождением ресурсов и устройством |
| [solo и bloc рядом](../../docs/ru/solo/vs-bloc.md) | Одиннадцать сценариев на обоих пакетах |

## Рецепты

Ситуации, которые встречаются, и чем их брать. Каждая разобрана в разделе,
на который ведёт ссылка рядом.

| Ситуация | Чем брать | Где |
| --- | --- | --- |
| Из пачки команд важна только последняя | `accumulate` с `merge`, берущим пришедшую | [Команды, где важна только последняя](../../docs/ru/solo/accumulation.md#команды-где-важна-только-последняя) |
| Ввод в поле поиска | `accumulate` с `AccumulationTiming.debounce` | [Поиск, который стреляет на каждый символ](../../docs/ru/solo/accumulation.md#поиск-который-стреляет-на-каждый-символ) |
| Поздний запрос не должен быть отброшен как дубликат раннего | ключ-запись, `(_Op.load, id)` | [Ключ на каждый запрос](../../docs/ru/solo/jobs.md#ключ-на-каждый-запрос) |
| Ожидающую работу обесценило только что пришедшее | `queue.removeWhere` перед постановкой или `cancelAll()`, если она может уже работать | [Когда это всё-таки разные задачи](../../docs/ru/solo/accumulation.md#когда-это-всё-таки-разные-задачи) |
| Последняя пачка должна уйти до того, как экран исчезнет | `close(mode: SoloCloseMode.drain)` | [Отмена работы и закрытие контроллера](../../docs/ru/solo/cancellation.md#отмена-работы-и-закрытие-контроллера) |
| `close()` не возвращается | `controller.pending` | [Что удерживает контроллер](../../docs/ru/solo/errors.md#что-удерживает-контроллер) |
| Журналу нужно сказать, какая операция изменила состояние | `SoloTransition` в `onChange` | [Наблюдение за всеми контроллерами](../../docs/ru/solo/errors.md#наблюдение-за-всеми-контроллерами) |
| Вызов должен закончиться до того, как очередь пойдёт дальше | `ctx.join` | [Отмена](../../docs/ru/solo/cancellation.md) |
| Шаг из нескольких вызовов нельзя прервать на половине | `ctx.uncancellable` | [Защита шага или всей задачи](../../docs/ru/solo/cancellation.md#защита-шага-или-всей-задачи) |
| Ресурс, открытый вызовом, которого никто не дождался, всё равно надо закрыть | `dispose` или `discard` у `ctx.abandonable` и `ctx.join` | [Получение ресурса вызовом](../../docs/ru/solo/resources.md#получение-ресурса-вызовом) |
| Виджет перестраивается из-за состояния, которым не пользуется | `SoloSelector` из `flutter_solo` | [Выбор одного значения](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#выбор-одного-значения) |
| Очередь нужно на время остановить | `Job`, которая ждёт `Completer` в голове очереди | [Пауза очереди](../../docs/ru/solo/jobs.md#пауза-очереди) |
| Событие стрима приходит микротаской позже, и это поздно | `addListener`, который зовёт колбэк внутри изменения | [Наблюдение за состоянием](../../docs/ru/solo/state.md#наблюдение-за-состоянием) |

## Переход с bloc

Вызывающий код обращается к методам контроллера и получает `Job` для каждой
операции. Политика очереди выбирается при каждом вызове, а все корневые `Job`
используют одну очередь. [solo и bloc рядом](../../docs/ru/solo/vs-bloc.md)
содержит соответствия API и сравнивает одиннадцать прикладных сценариев
с реализациями на обоих пакетах.

Пакет не включает политики повторов, пулы исполнителей, внедрение зависимостей,
сохранение состояния или фильтрацию равных состояний. Если работе нужны отмена
и освобождение ресурсов, но не правила состояния и очередь контроллера, можно
использовать [async_job](https://pub.dev/packages/async_job) напрямую. Для
значения без асинхронного жизненного цикла может хватить `ValueNotifier`.
