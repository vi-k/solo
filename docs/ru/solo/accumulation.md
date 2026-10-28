# Накопление событий до запуска задачи

Несколько событий могут разделять одну задачу в очереди. `collect` сохраняет
каждое событие в списке, `accumulate` объединяет его с одним накопленным
значением.

С чего начать, по тому, что нужно контроллеру; три последние строки ведут
на страницу [«Правила накопления»](accumulation-rules.md):

| Контроллеру нужно | Читать |
| --- | --- |
| Один из четырёх частых случаев: поле поиска, настройки, сохраняемые на каждом щелчке, строки журнала, отправляемые пачками, команды, где важна только последняя | [«Рецепты»](#рецепты): их таблица называет, что доходит до работы и какой накопитель у каждого |
| Группа, которая начинается после паузы в событиях, с ограниченной частотой или сразу | [«Выбор момента готовности группы»](accumulation-rules.md#выбор-момента-готовности-группы): `timing` |
| Событие, которое присоединяется к группе в очереди или начинает свою группу за другой задачей | [«Выбор места присоединения событий»](accumulation-rules.md#выбор-места-присоединения-событий): `AccumulationPolicy` |
| Один хэндл у всех, кто добавлял в группу, и как её задача начинается, отменяется, падает и заканчивается на `close()` | [«Запуск, отмена и ошибки»](accumulation-rules.md#запуск-отмена-и-ошибки) |

## Рецепты

Четыре контроллера, и у каждого событий приходит больше, чем есть работы,
которую стоит делать. Разница в том, что остаётся: последнее значение, слияние
всех или каждое событие в списке.

| Рецепт | Что доходит до работы | Накопитель |
| --- | --- | --- |
| [«Поиск, который стреляет на каждый символ»](#поиск-который-стреляет-на-каждый-символ) | Последний запрос, после паузы в наборе | `accumulate`, `merge`, который оставляет `incoming`, `debounce` |
| [«Настройки, сохраняемые на каждом щелчке»](#настройки-сохраняемые-на-каждом-щелчке) | Один патч, слитый из всех щелчков | `accumulate`, `merge`, который объединяет патчи, `debounce` |
| [«Один запрос на строку журнала»](#один-запрос-на-строку-журнала) | Каждая строка, не чаще одного запроса в секунду | `collect`, `throttle` с `startAtOnce: false` |
| [«Команды, где важна только последняя»](#команды-где-важна-только-последняя) | Последняя из команд, нажатых подряд | `accumulate`, `merge`, который оставляет `incoming`, `policy: adjacent` |

Под каждой версией контроллера стоит то, к чему приводит сценарий над ней: что
доходит до сервера или устройства и каким остаётся состояние контроллера.

У `collect` и `accumulate` три аргумента типа, `<W, E, T>`: рабочий тип `W`,
как у `enqueue`, тип события `E` и тип результата `T`, а возвращают обе
накопитель, `SoloAccumulator<E, T>`. Создайте его один раз в контроллере, затем
вызывайте `add(event)` из публичных методов контроллера.

Накопитель владеет входными данными ожидающей задачи. Добавление события
не запускает обработчик и не меняет состояние контроллера. События, которые
разделяют одну задачу, составляют группу. Группа принимает события, пока
не запечатана: её запечатывает истечение окна debounce, а при throttle или
вовсе без `timing` тот момент, когда очередь берёт задачу на выполнение.
Обработчик получает этот вход и обычный `SoloContext<S, W>`; состояние он
меняет через `ctx.emit`.

Каждый `add`, попавший в одну группу, возвращает одну и ту же задачу, поэтому
обычный `then` на ней бросает `StateError`; вызывающий продолжает её через
`shared()`. `merge` у `accumulate` выполняется внутри `add` и должна быть
синхронной и чистой. Оба правила действуют в каждом рецепте ниже; они —
в разделе
[«Запуск, отмена и ошибки»](accumulation-rules.md#запуск-отмена-и-ошибки)
страницы о правилах накопления, вместе с тем, что бывает при их нарушении.

### Поиск, который стреляет на каждый символ

Строка поиска спрашивает сервер, пока пользователь печатает. Каждое нажатие
становится событием, и запроса стоит только последнее.

```dart
import 'package:solo/solo.dart';

class SearchState {
  final List<String> results;

  const SearchState.idle() : results = const [];

  const SearchState.results(this.results);
}

abstract interface class SearchApi {
  Future<List<String>> search(String text);
}
```

#### Первая попытка

Словарь контроллера говорит `enqueue`, значит, на каждое нажатие заводится
задача:

```dart
// Первая попытка: каждое нажатие ждёт предыдущего.
final class QueuedSearch extends Solo<SearchState> {
  final SearchApi api;

  QueuedSearch(this.api) : super(const SearchState.idle());

  Job<void> query(String text) =>
      enqueue<SearchState, void>(key: 'query', (ctx) async {
        final results = await ctx.abandonable(() => api.search(text));
        ctx.emit(SearchState.results(results));
      });
}
```

Набирается `solo`, по символу каждые 50 мс, сервер отвечает за 100 мс:

```text
the server was asked 4 times: [s, so, sol, solo]
at 100 ms the screen shows [hits for s]
at 200 ms the screen shows [hits for so]
at 300 ms the screen shows [hits for sol]
at 400 ms the screen shows [hits for solo]
```

Очередь делает ровно то, что обещала, и в этом беда. Каждый запрос ждёт
предыдущего, поэтому ответ на `solo` приходит через 400 мс после первого
нажатия: четыре обращения вместо одного. А по дороге экран отвечает на три
слова, которые пользователь уже дописал.

#### Вторая попытка

`Policy.restart` отменяет работающую задачу, когда приходит следующая; политики
самой очереди описаны в разделе
[«Очередь и политики»](jobs.md#очередь-и-политики) страницы о задачах. Меняется
только метод:

```dart
// Вторая попытка: к серверу всё равно четыре запроса.
Job<void> query(String text) => enqueue<SearchState, void>(
  key: 'query',
  policy: Policy.restart,
  (ctx) async {
    final results = await ctx.abandonable(() => api.search(text));
    ctx.emit(SearchState.results(results));
  },
);
```

```text
the server was asked 4 times: [s, so, sol, solo]
at 250 ms the screen shows [hits for solo]
```

Устаревшее до экрана больше не доходит, и ответ приходит раньше: запросы теперь
идут внахлёст, а не в очередь. Сервер при этом спросили те же четыре раза:
отмена задачи не отзывает то, что она уже отправила. `ctx.join` вместо
`ctx.abandonable` их тоже не отзовёт. Он держит единственный слот выполнения
контроллера до ответа, и сколько запросов уйдёт, зависит от того, насколько
сервер быстрее набора.

#### Накопитель

```dart
final class Search extends Solo<SearchState> {
  final SearchApi api;
  late final _queries = accumulate<SearchState, String, void>(
    (ctx, text) async {
      final results = await ctx.abandonable(() => api.search(text));
      ctx.emit(SearchState.results(results));
    },
    merge: (accumulated, incoming) => incoming,
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 300)),
    policy: AccumulationPolicy.join,
    key: 'query',
  );

  Search(this.api) : super(const SearchState.idle());

  Job<void> query(String text) => _queries.add(text);
}
```

```text
the server was asked 1 time: [solo]
at 550 ms the screen shows [hits for solo]
```

Один запрос. `merge` берёт пришедший текст и выбрасывает прежний, поэтому
группа несёт последний запрос; debounce держит группу, пока набор не замрёт
на 300 мс. Эта пауза и есть цена: ответ приходит позже, чем у обеих попыток
выше, и он единственный отправленный. `policy` выписывает умолчание, `join`;
что решает политика, сказано в разделе
[«Выбор места присоединения событий»](accumulation-rules.md#выбор-места-присоединения-событий).

Уже начавшаяся группа завершается до старта следующей, а возвращённая `Job`
предоставляет исход и отмену, как и другие `Job`. Завершается при этом задача:
отмена кончает ожидание, а не запрос, который задача уже отправила, поэтому тот
может быть ещё в пути, когда стартует следующая группа.

### Настройки, сохраняемые на каждом щелчке

На экране настроек есть переключатель, выбор темы и выбор языка. Каждое
изменение становится событием, а серверу нужна одна запись, а не три.

`SettingsPatch` описывает, какие настройки изменить. Новое значение поля
заменяет прежнее; поля, которых в новом патче нет, сохраняются. В этом примере
сами настройки не могут быть `null`, поэтому `null` в поле патча означает «это
не трогать». Для nullable-настройки, которую можно очистить, понадобится
отдельно выражать, есть ли в патче значение.

```dart
import 'package:solo/solo.dart';

class Settings {
  final bool notifications;
  final String theme;
  final String language;

  const Settings({
    required this.notifications,
    required this.theme,
    required this.language,
  });
}

class SettingsPatch {
  final bool? notifications;
  final String? theme;
  final String? language;

  const SettingsPatch({this.notifications, this.theme, this.language});

  SettingsPatch merge(SettingsPatch incoming) => SettingsPatch(
    notifications: incoming.notifications ?? notifications,
    theme: incoming.theme ?? theme,
    language: incoming.language ?? language,
  );

  Settings apply(Settings current) => Settings(
    notifications: notifications ?? current.notifications,
    theme: theme ?? current.theme,
    language: language ?? current.language,
  );
}

abstract interface class SettingsApi {
  Future<void> save(Settings settings);

  Future<Settings> load();
}
```

#### Первая попытка

Каждое изменение становится задачей, и задача пишет:

```dart
// Первая попытка: каждое изменение пишется отдельно.
final class EagerSettingsController extends Solo<Settings> {
  final SettingsApi _api;

  EagerSettingsController(this._api, Settings initial) : super(initial);

  Job<void> update(SettingsPatch patch) =>
      enqueue<Settings, void>(key: 'settings', (ctx) async {
        final next = patch.apply(ctx.state);
        await ctx.join(() => _api.save(next));
        ctx.emit(next);
      });
}
```

Переключатель, потом тема, потом язык, с промежутком в 20 мс, сервер пишет 100
мс:

```text
the server was written to 3 times:
  notifications: true, theme: light, language: en
  notifications: true, theme: dark, language: en
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

К концу экран прав, а платит за это сеть: три обращения за один заход
в настройки. Первые два публикуют настройки, от которых пользователь уже ушёл.
Другое устройство, прочитавшее между ними, найдёт светлую тему, хотя хозяин уже
выбрал тёмную.

#### Вторая попытка

`Policy.restart` убирает из очереди ожидающие записи с тем же ключом и просит
остановиться ту, что идёт. Меняется только метод:

```dart
// Вторая попытка: перезапуск затирает изменение, которое заменил.
Job<void> update(SettingsPatch patch) => enqueue<Settings, void>(
  key: 'settings',
  policy: Policy.restart,
  (ctx) async {
    final next = patch.apply(ctx.state);
    await ctx.join(() => _api.save(next));
    ctx.emit(next);
  },
);
```

```text
the server was written to 2 times:
  notifications: true, theme: light, language: en
  notifications: false, theme: light, language: ru
the screen ends up with notifications: false, theme: light, language: ru
```

Переключатель вернулся в положение «выключено», а тема снова светлая. Каждая
задача читает состояние, с которым стартовала, и пишет целый `Settings`.
Поэтому задача, заменившая другую, не наследует того, что та собиралась
изменить: она переписывает это из состояния, где того изменения не было. Первая
из двух записей и есть та, которую `restart` просил остановиться, и она всё
равно ушла. `ctx.join` ждёт вызов, который сам же сделал, а `_api.save` запроса
на отмену не слышит. Два пользовательских изменения из трёх исчезли,
и с сервера, и с экрана, и при этом ничего не упало.

#### Накопитель

```dart
final class SettingsController extends Solo<Settings> {
  final SettingsApi _api;
  late final _updates = accumulate<Settings, SettingsPatch, void>(
    (ctx, patch) async {
      final next = patch.apply(ctx.state);
      await ctx.join(() => _api.save(next));
      ctx.emit(next);
    },
    merge: (accumulated, incoming) => accumulated.merge(incoming),
    key: 'settings',
    timing: AccumulationTiming.debounce(const Duration(milliseconds: 200)),
  );

  SettingsController(this._api, Settings initial) : super(initial);

  Job<void> update(SettingsPatch patch) => _updates.add(patch);

  Job<void> reload() => enqueue<Settings, void>(
    key: 'reload',
    (ctx) async => ctx.emit(await ctx.abandonable(_api.load)),
  );
}
```

```text
the server was written to 1 time:
  notifications: true, theme: dark, language: ru
the screen ends up with notifications: true, theme: dark, language: ru
```

`merge` объединяет патчи, а не выбирает между ними, поэтому ничего
из сделанного пользователем не пропадает, а группа несёт все три изменения
в одну запись.

Экран ещё и читает настройки с сервера, и `reload` здесь обычная задача,
а не накопленная. Этот накопитель берёт политику по умолчанию, `join`, поэтому
`reload`, вставший в очередь между двумя щелчками, границей не становится:
щелчки остаются одной группой и одной записью, чем бы очередь ни была занята.
Когда вместо неё брать `adjacent`, сказано в разделе
[«Выбор места присоединения событий»](accumulation-rules.md#выбор-места-присоединения-событий).

Первое событие становится накопленным значением без вызова `merge`; каждое
следующее синхронно вызывает `merge(accumulated, incoming)` из `add`, до старта
обработчика.

Три вызова возвращают одну задачу, и дождаться её один раз значит дождаться
всех трёх:

```dart
Future<void> changeSettings(SettingsApi api, Settings initial) async {
  final controller = SettingsController(api, initial);
  try {
    final first = controller.update(const SettingsPatch(notifications: true));
    final second = controller.update(const SettingsPatch(theme: 'dark'));
    final third = controller.update(const SettingsPatch(language: 'ru'));

    print(identical(first, second) && identical(second, third));
    print(await first.done);
  } finally {
    await controller.close();
  }
}
```

```text
true
Done(null)
```

После 200 мс без новых изменений обработчик сохраняет один снимок со всеми
тремя, а когда запись закончилась, отдаёт его в состояние. До запуска
обработчика состояние остаётся исходным, и за время паузы могут выполниться
другие готовые `Job`. `.done` не бросает: его ожидание возвращает `Outcome`,
будь то `Done`, `Failed` или `Cancelled`.

Если сохранение падает, состояние не меняется, а группа завершается провалом.
Повторять ли неудавшиеся изменения, решает вызывающий; более поздний
независимый патч не включает их автоматически. Пример предполагает одного
писателя и future API, которая завершается при фактическом окончании записи.
Что с этим делают клиентский таймаут и `timeout` накопителя — в разделе
[«Запуск, отмена и ошибки»](accumulation-rules.md#запуск-отмена-и-ошибки)
страницы о правилах накопления.

### Один запрос на строку журнала

Приложение пишет записи журнала по одной, а сервер принимает их пачками. Дойти
должна каждая, и в том порядке, в каком её написали.

```dart
import 'package:solo/solo.dart';

class LogEntry {
  final String message;

  const LogEntry(this.message);
}

abstract interface class LogApi {
  Future<void> send(List<LogEntry> entries);
}
```

#### Первая попытка

Каждая строка становится задачей, и задача отправляет:

```dart
// Первая попытка: каждая строка стоит отдельного запроса.
final class EagerLogController extends Solo<int> {
  final LogApi _api;

  EagerLogController(this._api) : super(0);

  Job<void> logEvent(LogEntry entry) =>
      enqueue<int, void>(key: 'logs', (ctx) async {
        await ctx.join(() => _api.send([entry]));
        ctx.emit(ctx.state + 1);
      });
}
```

Три строки, написанные подряд кодом, который обрабатывает переход между
экранами, и ещё одна через две секунды; сервер тратит на запрос 100 мс:

```text
the server got 4 requests:
  [opened] at 0 ms
  [loaded] at 100 ms
  [shown] at 200 ms
  [tapped] at 2000 ms
the three lines of the transition cost 3 of them
the counter says 4
```

Четыре строки, четыре запроса. Порядок держит очередь, и она же заставляет их
ждать: каждая отправка начинается, только когда закончилась предыдущая. Так
всплеск логирования превращается в цепочку обращений, которая переживёт
породившее её событие.

#### Накопитель

`collect` дописывает события в приватный список и отдаёт обработчику
неизменяемый снимок, снятый в момент запечатывания группы: каждое событие,
в том порядке, в каком его написали. Снимок копирует список, но не сами
события, поэтому событие, изменённое после `add`, уйдёт изменённым. Берите
неизменяемые объекты.

```dart
final class LogController extends Solo<int> {
  final LogApi _api;
  late final _logs = collect<int, LogEntry, void>(
    (ctx, entries) async {
      await ctx.join(() => _api.send(entries));
      ctx.emit(ctx.state + entries.length);
    },
    key: 'logs',
    policy: AccumulationPolicy.join,
    timing: AccumulationTiming.throttle(
      const Duration(seconds: 1),
      startAtOnce: false,
    ),
  );

  LogController(this._api) : super(0);

  Job<void> logEvent(LogEntry entry) => _logs.add(entry);
}
```

```text
the server got 2 requests:
  [opened, loaded, shown] at 1000 ms
  [tapped] at 3000 ms
the three lines of the transition cost 1 of them
the counter says 4
```

Три строки перехода едут вместе. С `startAtOnce: false` интервал начинается
с первой из них, и группа его выжидает, так что строки, записанные за эту
секунду, остаются вместе, сколько бы проходов код ни потратил на их запись.
С умолчанием (`startAtOnce: true`) первая строка ушла бы сразу, а остаток
перехода, записанного больше чем за один проход, ушёл бы секундой позже.
Четвёртая строка написана, когда никакой интервал не идёт, поэтому она заводит
свой и выжидает его: строка, записанная в одиночку, доходит до сервера
на секунду позже.

Буфер, который вы держите сами, тоже собрал бы их в пачку. `collect` добавляет
к этому то, что буфер и есть вход задачи:

- события запечатываются в группу, которую берёт очередь;
- вызывающий получает ту же `Job`, что и все добавлявшие в эту группу;
- `close()` сбрасывает группу вместо того, чтобы оставить после себя список
  и таймер.

Состояние этого контроллера считает записи, отправка которых завершилась,
а обработчик дошёл до `emit`. Рабочий тип `int` и есть всё это состояние,
поэтому обработчик стартует при любом счёте и читает его как `ctx.state`.
Раздел
[«Выбор места присоединения событий»](accumulation-rules.md#выбор-места-присоединения-событий)
объясняет, почему умолчанием выбрана политика `join`, которую этот пример
выписывает явно. Раздел
[«Выбор момента готовности группы»](accumulation-rules.md#выбор-момента-готовности-группы)
говорит, от чего отсчитывается интервал throttle в каждом из двух режимов
и чего стоит каждый.

Сбор записей не гарантирует доставку. Неудачная отправка, отмена группы или
обычный `close()` могут оставить их неотправленными; `close()`
с `SoloCloseMode.drain` отправляет то, что уже стоит в очереди. Надёжное
хранение и повторы требуют протокола приложения сверх этого накопителя.

### Команды, где важна только последняя

Плеер вешает воспроизведение и паузу на одну кнопку, а пользователь жмёт её
быстрее, чем отвечает устройство.

```dart
import 'package:solo/solo.dart';

enum Command { resume, pause }

sealed class Playback {
  const Playback();
}

final class Playing extends Playback {
  const Playing();
}

final class Paused extends Playback {
  const Paused();
}

abstract interface class PlayerDevice {
  Future<void> resume();

  Future<void> pause();
}
```

#### Первая попытка

Каждая команда идёт отдельной задачей:

```dart
// Первая попытка: каждое нажатие доходит до устройства.
final class QueuedPlayer extends Solo<Playback> {
  final PlayerDevice device;

  QueuedPlayer(this.device) : super(const Paused());

  Job<void> resume() =>
      enqueue<Playback, void>(key: Command.resume, (ctx) async {
        await ctx.join(device.resume);
        ctx.emit(const Playing());
      });

  Job<void> pause() => enqueue<Playback, void>(key: Command.pause, (ctx) async {
    await ctx.join(device.pause);
    ctx.emit(const Paused());
  });
}
```

Три нажатия подряд, воспроизведение, пауза и снова воспроизведение,
на устройстве, которому нужно 100 мс на исполнение:

```text
the device heard 3 commands:
  resume at 0 ms
  pause at 100 ms
  resume at 200 ms
the button gave back a job for every tap
the player settles Playing at 300 ms
```

Плеер оказывается там, куда просило последнее нажатие, но приходит туда длинной
дорогой: играет, останавливается и играет снова, а эту остановку посередине
пользователь слышит. Три обращения к устройству и 300 мс до того, как всё
уляжется.

#### Накопитель

Очередь, в которой лежат `resume`, а за ним `pause`, вот-вот сделает две
взаимно уничтожающие вещи. Пришедший сейчас `resume` делает бессмысленной всю
пару: её итог тот же, к которому пришёл бы один `resume`. `merge` берёт
пришедшую команду и выбрасывает ту, что была:

```dart
final class Player extends Solo<Playback> {
  final PlayerDevice device;

  late final _transport = accumulate<Playback, Command, void>(
    key: 'transport',
    policy: AccumulationPolicy.adjacent,
    merge: (accumulated, incoming) => incoming,
    (ctx, command) async {
      switch (command) {
        case Command.resume:
          await ctx.join(device.resume);
          ctx.emit(const Playing());
        case Command.pause:
          await ctx.join(device.pause);
          ctx.emit(const Paused());
      }
    },
  );

  Player(this.device) : super(const Paused());

  Job<void> resume() => _transport.add(Command.resume);

  Job<void> pause() => _transport.add(Command.pause);
}
```

```text
the device heard 1 command:
  resume at 0 ms
the button gave back one job
the player settles Playing at 100 ms
```

Три вызова подряд оставляют в очереди одну задачу, и все три возвращают один
и тот же хэндл. Устройству сказано включить воспроизведение один раз. Ничего
не ставилось в очередь и не отменялось по дороге.

Это работает потому, что команды абсолютны: каждая говорит, каким должно стать
итоговое состояние, поэтому ответом служит последняя. Команды, которые
надстраиваются друг над другом («ещё десять секунд вперёд»), сливаются
сложением, а не заменой.

`adjacent` пристраивает событие к группе только в хвосте очереди, поэтому
задача другого рода, добавленная между двумя командами, становится границей,
и слияние на ней прекращается. У трёх нажатий подряд такой задачи между ними
нет, и `join`, политика по умолчанию, слил бы их так же. Расходятся они, когда
у плеера в очереди есть другая работа. Если между `resume` и `pause` стоит
задача другого рода, `join` вливает `pause` в группу перед этой задачей.
Поэтому устройство не слышит `resume` и встаёт на паузу раньше, чем задача
выполнится. `adjacent` посылает `resume`, даёт задаче выполниться и потом
посылает `pause`, в порядке вызовов, и потому рецепт называет политику,
а не берёт умолчание.

#### Когда это всё-таки разные задачи

Там, где `resume` и `pause` правда разные операции, а не одна команда
со значением, они обычные задачи со своими ключами. `Policy.replace`
не поможет: она убирает задачи с тем же ключом, а общего ключа у этих двух нет.
Убирает их собственная очередь контроллера:

```dart
Job<void> resume() {
  queue.removeWhere(
    (job) => job.key == Command.resume || job.key == Command.pause,
  );

  return enqueue<Playback, void>(key: Command.resume, (ctx) async {
    await ctx.join(device.resume);
    ctx.emit(const Playing());
  });
}
```

Удалить и добавить значит повторить форму `AccumulationPolicy.replace`: команда
оказывается в хвосте, за всем, что встало между. Разница в хэндле: этим путём
приходится строить новую задачу, а накопитель переносит ту, что у него уже
есть. Очередь умеет удалить задачу и добавить задачу, но не умеет изменить то,
что сделает уже стоящая. Поэтому место, которое сохраняет
`AccumulationPolicy.join`, этим путём не получить. Для него команду надо
держать вне задачи, там, откуда задача прочтёт её при старте, и именно это
накопитель делает для своей задачи.

Работающую задачу очередь не трогает никогда: уже начавшийся `pause` доработает
до конца, что бы за ним ни убрали. Чтобы отменить и работающую задачу, нужен
`cancelAll()`, который чистит всю очередь и отменяет текущую задачу, или общий
ключ на обе команды с `Policy.restart`. `removeWhere` пропускает задачи,
созданные с `cancellable: false`, пока не передан `force: true`.
