# solo

> Это перевод [`packages/solo/README.md`](packages/solo/README.md).
> Источник правды — английский оригинал, он лежит в пакете; перевод
> обновляется в том же коммите, что и оригинал.

Одна задача за раз: последовательные задачи с монопольным владением
состоянием, декларативными правилами и кооперативной отменой. Чистый Dart,
без зависимости на Flutter;
[`flutter_solo`](https://pub.dev/packages/flutter_solo) добавляет лицо
`ValueListenable`.

## Зачем

`solo` вырос из шести претензий к bloc:

1. очередью событий нельзя управлять;
2. если все события `sequential`, одно из них нельзя сделать `restartable`,
   не вынося в отдельную очередь;
3. события, работающие параллельно, пишут в одно и то же состояние;
4. после отмены обработчик продолжает работать, пока сам не проверит
   `emit.isDone`;
5. нельзя дождаться своего события: `stream` говорит, что состояние
   изменилось, а не кто его изменил;
6. снаружи хочется звать метод, а не собирать событие и делать `add`.

[Где bloc не дотягивает](#где-bloc-не-дотягивает) показывает все шесть в
коде, на восьми сценариях из разных предметных областей.

## Где bloc не дотягивает

bloc хорошо ложится на обычный экран: пришло событие, обработчик ответил
состоянием. Ловушки ниже — про контроллеры с жизненным циклом: железо,
устройства, плееры, фоновая синхронизация, — где с одним состоянием
происходит сразу несколько вещей и порядок важен. Каждый пункт называет
предметную область, показывает форму ловушки на bloc, а затем то же самое
на `solo`. Ни одна из них не баг: они следуют из устройства bloc —
трансформер на обработчик, `emit` действителен только внутри своего
обработчика, `add` возвращает `void`, — и там, где вопрос обсуждался в
трекере, стоит ссылка на issue.

В том же пакете есть `Cubit`: ни событий, ни трансформеров, только методы,
которые излучают состояние. Пункты 5 и 6 он закрывает прямо — метод кубита
принимает типизированные аргументы и возвращает значение, которого можно
дождаться, — и felangel указывает на него в самом
[#1556](https://github.com/felangel/bloc/issues/1556). Для остального он не
даёт ничего — управлять нечем: очереди нет (1), трансформеров нет вовсе
(2, 3), отмены нет (4), а `emit` после `close` бросает `Bad state: Cannot
emit new states after calling close` (пункт 7 ниже).

### 1. Очередью нельзя управлять

Экран BLE-устройства. Пользователь открывает его — подключение, — жмёт
«прочитать заряд» и «прочитать уровень сигнала», переименовывает устройство
и закрывает окно: отключение. Чтобы очередь вообще появилась, все команды
сводят в один `on<DeviceEvent>` с `sequential()`; пять отдельных `on<E>`
дали бы пять очередей, работающих бок о бок, а это следующий пункт. Теперь
очередь настоящая, и `Disconnect` дописывается за двумя чтениями и
переименованием. Оба чтения отрабатывают раньше отключения, каждое эмитит
состояние в уже закрытое окно, — и выбросить их нечем: очередь есть, но она
непрозрачна. Посмотреть на неё нечем, и убрать из неё ожидающее событие
нечем.

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc(this._ble) : super(const DeviceState()) {
    // Один обработчик на весь тип, чтобы `sequential()` делал одну очередь.
    on<DeviceEvent>((e, emit) async {
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(const DeviceState(online: true));
        case ReadBattery():
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          emit(state.copyWith(signal: await _ble.signal()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          // Оба чтения стоят в очереди перед этим и отработают первыми,
          // эмитя состояние в уже закрытое окно.
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  final Ble _ble;
}
```

В `solo` очередь — объект, которым владеет контроллер, а у задач в ней есть
ключи.

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  DeviceController(this._ble) : super(const Offline());

  final Ble _ble;

  // connect(), readBattery(), readSignal() и rename() — обычные задачи.

  Job<void> disconnect() {
    // Чтения нужны были только экрану, который пользователь уже закрыл;
    // переименование он попросил сам, поэтому остаётся в очереди.
    queue.removeWhere(
      (job) =>
          job.key == DeviceKey.readBattery || job.key == DeviceKey.readSignal,
    );
    return run<Connected, void>(
      key: DeviceKey.disconnect,
      (ctx) async {
        await ctx.guard(_ble.disconnect);
        ctx.emit(const Offline());
      },
    );
  }
}
```

`removeWhere` завершает оба чтения исходом `Cancelled(manual)` и завершает
их `done`, так что вызывающие узнают, что произошло. Переименование
остаётся — пользователь его попросил и не отменял, — выполняется, и только
затем выполняется отключение: `first: true` не нужен, потому что очередь
последовательна по построению, а отключение добавлено последним.
Выполняющуюся задачу `removeWhere` не трогает: уже начавшийся `connect`
сначала доработает; если так не надо, поставьте `current?.cancel()` перед
удалением. Очередь — объект, на который можно посмотреть и из которого можно
выбросить лишнее, поэтому «выкинуть то, что нужно было только закрытому
экрану» — это одно выражение, а не переделка.

### 2. Один restartable среди sequential

Медиаплеер. `play`, `pause`, `seek` и `setVolume` говорят с одним нативным
плеером, поэтому выполняться должны по одному; но `seek`, выпущенный, пока
пользователь тянет ползунок, должен перезапускаться, а не вставать в
очередь. В bloc трансформер — аргумент `on<E>`, и `sequential()`
упорядочивает только события этого одного типа, обработчики разных типов всё
равно накладываются. Чтобы выстроить в линию все четыре, их сводят в один
`on<PlayerCommand>`, и после этого `seek` уже не может быть `restartable()`:
у одного обработчика один трансформер. Запасной выход — написать
`EventTransformer` руками: он видит события и мог бы ветвиться по их типу, —
ценой того, что его надо написать.

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  PlayerBloc(this._player) : super(const PlayerState()) {
    // Один обработчик на все команды: трансформер применяется к своему
    // `on<E>`, поэтому четыре обработчика с `sequential()` всё равно
    // накладывались бы. Seek теперь тоже sequential — перетаскивание
    // ползунка встаёт в очередь целиком.
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          await _player.seek(position);
          emit(PlayerState(position: position));
        case SetVolume(:final value):
          await _player.setVolume(value);
      }
    }, transformer: sequential());
  }

  final Player _player;
}
```

В `solo` очередь последовательна по построению, а политика принадлежит
задаче, а не очереди.

```dart
enum PlayerKey { play, pause, seek, volume }

final class PlayerController extends Solo<PlayerState> {
  PlayerController(this._player) : super(const Stopped());

  final Player _player;

  Job<void> pause() => run<Playing, void>(
        key: PlayerKey.pause,
        policy: Policy.droppable,
        (ctx) async => ctx.guard(_player.pause),
      );

  // Единственная перезапускаемая задача здесь. Остальные остаются
  // последовательными, не говоря об этом: очередь одна, и выполняет она
  // одну задачу за раз.
  Job<void> seek(Duration position) => run<Playing, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _player.seek(position));
          ctx.emit(Playing(position: position));
        },
      );
}
```

`Policy.restart` отменяет выполняющийся seek и выбрасывает стоящие в
очереди — все по ключу `seek`; больше в контроллере ничего не меняется,
потому что политика называет ключ, а не дорожку.

### 3. Параллельные обработчики пишут в одно состояние

Заметки с синхронизацией. `UploadNote` и `RefreshList` меняют один и тот же
объект состояния, а с bloc 7.2 трансформер по умолчанию — конкурентный: если
трансформер не указан, оба обработчика работают одновременно. У версии этой
ошибки с устаревшим снимком лекарство в одну строку — читать `state` после
`await`, а не до, — и оба обработчика ниже так и делают. Чего это не лечит,
так это чередования: `RefreshList` спрашивает сервер прежде, чем загрузка
дойдёт, а отвечает уже после неё, поэтому список, который старше заметки,
только что влитой `UploadNote`, записывается поверх более нового. Никакого
снимка тут нет; два обработчика просто ходят по очереди по одному объекту.

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  // Трансформера нет: с bloc 7.2 по умолчанию конкурентный, поэтому оба
  // обработчика работают одновременно.
  NotesBloc(this._api) : super(const NotesState()) {
    on<UploadNote>((e, emit) async {
      emit(state.copyWith(uploading: true));
      await _api.upload(e.note);
      // `state` прочитан заново после await, как и следует.
      final merged = [...state.notes, e.note];
      emit(state.copyWith(notes: merged, uploading: false));
    });
    on<RefreshList>((e, emit) async {
      // Спрошено до конца загрузки, отвечено после неё: этот список
      // старше заметки, влитой выше, поэтому запись его в состояние
      // теряет ту заметку. Свежие чтения от чередования не спасают.
      final serverNotes = await _api.list();
      emit(state.copyWith(notes: serverNotes));
    });
  }

  final Api _api;
}
```

В `solo` очередь одна и корневая задача выполняется одна, поэтому
чередоваться не с чем.

```dart
final class NotesController extends Solo<NotesState> {
  NotesController(this._api) : super(const NotesState());

  final Api _api;

  Job<void> upload(Note note) => run<NotesState, void>(
        key: 'upload',
        (ctx) async {
          ctx.emit(ctx.state.copyWith(uploading: true));
          await ctx.guard(() => _api.upload(note));
          final merged = [...ctx.state.notes, note];
          ctx.emit(ctx.state.copyWith(notes: merged, uploading: false));
        },
      );

  Job<void> refresh() => run<NotesState, void>(
        key: 'refresh',
        (ctx) async {
          // Выполняется до upload или после него, но никогда поперёк.
          final serverNotes = await ctx.guard(_api.list);
          ctx.emit(ctx.state.copyWith(notes: serverNotes));
        },
      );
}
```

`ctx.state` читается в момент излучения, и пока идёт корневая задача,
никакая другая корневая задача этого контроллера состояние не пишет. Внутрь
ведут два пути: собственные дети, запущенные `ctx.run` в том же теле, и
`externalSetState` снаружи — оба осознанные, оба видны. Это гарантия
владения, а не дисциплина, которую два тела должны соблюдать.

### 4. После отмены обработчик продолжает работать

Обновление прошивки по BLE, кусок за куском. `restartable()` закрывает
эмиттер, и это всё, что он делает: цикл продолжает писать куски в
устройство. Ответ мейнтейнера в
[felangel/bloc#3349](https://github.com/felangel/bloc/issues/3349) ровно об
этом:

> This is because Futures aren't truly cancelable. To get the behavior
> you're describing you can simply check if `emit.isDone` is true before
> performing any expensive computations:

(«Дело в том, что Future по-настоящему неотменяемы. Чтобы получить
описанное вами поведение, можно просто проверять, истинно ли
`emit.isDone`, перед любыми дорогими вычислениями».)

Зеркальный случай — футура, запущенная внутри обработчика и оставленная без
`await`: излучить состояние позже она тоже не может. В debug-сборках её
ловит `assert` — `emit was called after an event handler completed normally`
([#2961](https://github.com/felangel/bloc/issues/2961)), — потому что
ничего, что пережило бы обработчик, тут не устроено.

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  FirmwareBloc(this._ble) : super(Idle()) {
    on<Flash>((e, emit) async {
      for (final chunk in e.chunks) {
        await _ble.write(chunk);
        // Без этой строки перезапущенный обработчик продолжает писать
        // куски в устройство: `restartable()` закрывает эмиттер, а не
        // останавливает тело. Она нужна каждому циклу, трогающему железо.
        if (emit.isDone) return;
        emit(Flashing(chunk.index));
      }
    }, transformer: restartable());
  }

  final Ble _ble;
}
```

В `solo` отмена тоже кооперативная, но ожидание заканчивается само.

```dart
final class FirmwareController extends Solo<FirmwareState> {
  FirmwareController(this._ble) : super(const Idle());

  final Ble _ble;

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
        canStart: (state) => state is Idle,
        (ctx) async {
          for (final chunk in chunks) {
            // guard возвращает управление, как только задача отменена,
            // поэтому следующая запись не начнётся. Отказ железа,
            // излучивший Broken снаружи, завершит задачу на том же await.
            await ctx.guard(() => _ble.write(chunk));
            ctx.emit(Flashing(chunk.index));
          }
        },
      );
}
```

`ctx.guard` возвращает управление, как только пришла отмена, поэтому
следующая запись не начинается; следующий `ctx.state` или `ctx.emit` бросает
`Cancelled` этой задачи; а работа, которая иначе была бы запущена и брошена,
идёт через `ctx.run(child)` — дочернюю задачу, которую родитель дожидается.

### 5. Нельзя дождаться своего события

Оформление заказа. После нажатия «Оплатить» экран должен знать, что успешно
прошёл *именно этот* платёж, и только потом переходить дальше. `add`
возвращает `void`, а стрим состояний говорит лишь то, что состояние
изменилось. Так задумано, а не недосмотрено, — felangel в
[felangel/bloc#1556](https://github.com/felangel/bloc/issues/1556):

> … a single add can result in multiple state changes so you would never
> know when the event was actually "done" being processed.

(«…один add может привести к нескольким изменениям состояния, так что
узнать, когда событие на самом деле «обработано», вы не сможете».)

```dart
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      try {
        emit(Paid(await _api.pay(e.order)));
      } on Object catch (error) {
        emit(PaymentFailed(error));
      }
    }, transformer: droppable());
  }

  final Api _api;
}
```

и экран:

```dart
Future<void> onPayPressed(CheckoutBloc bloc, Order order) async {
  bloc.add(Pay(order)); // возвращает void
  // Стрим говорит, что состояние изменилось, а не кто его изменил: повтор
  // с другого экрана даёт такой же Paid.
  final state = await bloc.stream.firstWhere((s) => s is! Paying);
  if (state is Paid) {
    navigateToReceipt(state.receipt);
  }
}
```

Метод `solo` возвращает хэндл задачи, которую он создал.

```dart
final class CheckoutController extends Solo<CheckoutState> {
  CheckoutController(this._api) : super(const Cart());

  final Api _api;

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        key: 'pay',
        policy: Policy.droppable,
        canStart: (state) => state is Cart,
        (ctx) async {
          ctx.emit(const Paying());
          final receipt = await ctx.guard(() => _api.pay(order));
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}
```

и экран:

```dart
Future<void> onPayPressed(CheckoutController checkout, Order order) async {
  switch (await checkout.pay(order).done) {
    case Done(:final value):
      navigateToReceipt(value);
    case Cancelled():
      showCancelled();
    case Failed(:final error):
      showError(error);
  }
}
```

`done` несёт исход именно этого вызова и никогда не бросает; `value` несёт
значение и, наоборот, бросает. Ни тому, ни другому не нужно гадать, чьё
изменение состояния перед ним. Дальше в том же обсуждении felangel
указывает на `Cubit`: его методы — обычные `async`-методы, которых можно
дождаться, — ответ на этот пункт ценой очереди событий и трансформеров из
пунктов 1–4.

### 6. Метод, а не событие

Карта. `moveTo`, `setZoom`, `follow` — три действия на одном виджете. В bloc
каждое из них — класс, регистрация и `add`: типы аргументов живут в событии,
работа живёт в обработчике где-то ещё, а место вызова говорит `add`, а не
то, чего оно хочет. `Cubit` закрывает и этот пункт — кубит и есть методы, —
что другими словами означает: вся эта обвязка принадлежит событиям, а не
пакету.

```dart
sealed class MapEvent {}

class MoveTo extends MapEvent {
  MoveTo(this.point);
  final Point<double> point;
}

class SetZoom extends MapEvent {
  SetZoom(this.value);
  final double value;
}

class Follow extends MapEvent {
  Follow(this.track);
  final Track track;
}
```

и bloc:

```dart
class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc(this._map) : super(const MapState()) {
    on<MoveTo>((e, emit) => _map.moveTo(e.point), transformer: sequential());
    on<SetZoom>((e, emit) => _map.setZoom(e.value), transformer: sequential());
    on<Follow>((e, emit) => _map.follow(e.track), transformer: sequential());
  }

  final MapApi _map;
}

void onMapDrag(MapBloc bloc, Point<double> point) => bloc.add(MoveTo(point));
```

В `solo` это три метода.

```dart
final class MapController extends Solo<MapState> {
  MapController(this._map) : super(const MapState());

  final MapApi _map;

  Job<void> moveTo(Point<double> point) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.moveTo(point)));

  Job<void> setZoom(double value) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.setZoom(value)));

  Job<void> follow(Track track) =>
      run<MapState, void>((ctx) => ctx.guard(() => _map.follow(track)));
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

Сигнатура несёт аргументы и результат, место вызова читается как вызов, а
возвращённый `Job<void>` есть на случай, если вызывающий захочет его
дождаться, — вызов без `await` не поднимает линтов, потому что хэндл не
`Future`.

### 7. Закрытие, пока работа ещё идёт

Экран чата или ленты. Пользователь отправляет сообщение, уходит назад, и
ответ приходит в контроллер, который уже закрыт. Что будет дальше, зависит
от трансформера. С `sequential()` — он ниже — `close()` дожидается
работающего обработчика, и запоздавший `emit` доходит: состояние меняется
после `close`, и слушатели стрима его получают. С трансформером по
умолчанию, с `concurrent()`, `droppable()` или `restartable()`, `close()`
возвращается сразу, эмиттер отменён, и запоздавший `emit` выбрасывается
молча. В обоих случаях тело продолжает работать, а следующий за ним `add`
бросает `Bad state: Cannot add new events after calling close`
([#52](https://github.com/felangel/bloc/issues/52),
[#120](https://github.com/felangel/bloc/issues/120); отменяемые операции
всё ещё в статусе предложения,
[#3069](https://github.com/felangel/bloc/issues/3069)). Обычный обходной
путь — проверка `isClosed` после каждого `await`.

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._api) : super(const ChatState()) {
    on<SendMessage>((e, emit) async {
      final reply = await _api.send(e.text);
      // Пользователь ушёл назад, пока запрос был в пути. Без этой строки
      // ответ всё равно дойдёт до состояния — `sequential()` заставляет
      // `close()` дождаться этого тела, — а `add` ниже бросит
      // `Bad state: Cannot add new events after calling close`.
      if (isClosed) return;
      emit(state.withReply(reply));
      add(const MarkRead());
    }, transformer: sequential());
    on<MarkRead>((e, emit) => _api.markRead(), transformer: sequential());
  }

  final Api _api;
}
```

В `solo` закрытие — часть той же дисциплины очереди.

```dart
final class ChatController extends Solo<ChatState> {
  ChatController(this._api) : super(const ChatState());

  final Api _api;

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await ctx.guard(() => _api.send(text));
          ctx.emit(ctx.state.withReply(reply));
          markRead();
        },
      );

  Job<void> markRead() =>
      run<ChatState, void>((ctx) => ctx.guard(_api.markRead));
}

Future<void> onScreenClosed(ChatController chat) async {
  // Отменяет выполняющийся send и ждёт, пока его тело остановится;
  // задачи из очереди завершаются с Cancelled(closed).
  await chat.close();
  chat.send('bye'); // задача, уже завершённая с Cancelled(closed)
}
```

`close()` отмечает выполняющуюся задачу отменённой и ждёт, пока она
действительно остановится, задачи из очереди завершаются с
`Cancelled(closed)`, а `add` после `close` возвращает задачу, уже
завершённую с тем же исходом, — так что месту вызова проверка `isClosed`
не нужна.

### 8. Состояние меняется извне

Камера или BLE-датчик. Железо сообщает об отказе через листенер, пока
обработчик калибровки на середине пути. Собственный `emit` у bloc помечен
`@visibleForTesting` и описан как внутренний — «only for internal use and
should never be called directly outside of tests» («только для внутреннего
использования, звать его напрямую вне тестов нельзя»), — поэтому
поддерживаемый путь внутрь из листенера — `add(HardwareFailed(error))`. У
этого события свой обработчик, который работает рядом с калибровочным, а тот
продолжает говорить со сломанным железом. Поэтому каждый обработчик
начинается с `if (state is! Ready) return;` и повторяет это после каждого
`await`.

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  SensorBloc(this._hw) : super(Idle()) {
    // Поддерживаемый путь внутрь — событие, а у события свой обработчик,
    // работающий рядом с тем, что уже работает.
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      // Broken мог прийти во время await; этот обработчик никто не
      // отменил, поэтому предусловие повторяется руками после каждого
      // шага, и так всегда.
      if (state is! Ready || emit.isDone) return;
      await _hw.sample();
      if (state is! Ready || emit.isDone) return;
      emit(Calibrated());
    }, transformer: sequential());
  }

  final Sensor _hw;
}
```

В `solo` состояние пишет сам листенер, а правила остаются в объявлении.

```dart
final class SensorController extends Solo<SensorState> {
  SensorController(this._hw) : super(const Idle()) {
    // Листенер сам пишет состояние. Каждая работающая задача, которая
    // перестала подходить состоянию по рабочему типу или keepWhile,
    // отменяется сразу.
    _hw.onError = (error) => externalSetState(Broken(error));
  }

  final Sensor _hw;

  // Предусловие — это сигнатура: W здесь Ready. В теле проверять нечего и
  // повторять после каждого await нечего.
  Job<void> calibrate() => run<Ready, void>(
        key: 'calibrate',
        (ctx) async {
          await ctx.guard(_hw.zero);
          await ctx.guard(_hw.sample);
          ctx.emit(const Calibrated());
        },
      );
}
```

`externalSetState` переоценивает по новому состоянию каждую работающую
задачу и отменяет те, что перестали подходить состоянию по рабочему типу
или `keepWhile`. Предусловие живёт в `run<Ready, void>`, где движок
проверяет его перед стартом, при каждом изменении состояния и при каждом
чтении.

## Установка

```sh
dart pub add solo
```

Для Flutter берите вместо него `flutter_solo` — он реэкспортирует весь
`solo`:

```sh
flutter pub add flutter_solo
```

## Быстрый старт

Контроллер камеры. Состояние — sealed-иерархия; `NotDisposed` —
объединённый интерфейс, который задачи могут объявлять своим рабочим типом:

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

Контроллер — обычный класс с обычными методами. Каждый метод создаёт задачу
и отдаёт её очереди; возвращаемый хэндл — не `Future`, поэтому вызвать метод
без `await` законно и линтов это не поднимает:

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
          await ctx.guard(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.guard(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.guard(hw.capture);
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
          await ctx.run(_closeCameraJob()).done;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

Снаружи:

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

Задачи выполняются одна за другой, в порядке очереди, и никогда не
накладываются. `setZoom`, добавленный, пока в очереди ждёт более ранний
`setZoom`, выбрасывает ожидающий из очереди и занимает его место; уже
начавшийся `setZoom` доработает — это `Policy.replace`. `takePhoto`,
добавленный, пока снимок в работе, возвращает уже выполняющийся снимок
вместо того, чтобы ставить в очередь второй, — это `Policy.droppable`.
`dispose` чистит очередь, отменяет то, что выполняется, и затем выполняется
сам как задача, которую отменить нельзя.

## Понятия

**Состояние.** Один неизменяемый объект типа `S`, обычно sealed-иерархия с
объединёнными интерфейсами (`NotDisposed`, `Initialized`), чтобы задачи
могли объявлять рабочий тип шире одного класса. `solo.state` читается кем
угодно и когда угодно; пишут только задачи.

**Контроллер.** Владелец состояния и очереди. Иерархия линейная:
`SoloBase<S>` — движок и `state`; `Solo<S>` добавляет broadcast-`stream`;
`SoloListenable<S>` в `flutter_solo` добавляет `ValueListenable`.
Различаются они только тем, как доставляется изменение.

**Задача.** Единица работы: `async`-тело `Future<T> Function(JobContext)`,
необязательный `key`, правила и хэндл `Job<T>`. `job(...)` создаёт задачу,
не ставя её в очередь, `add(job, policy: ...)` ставит её в очередь,
`run(...)` делает и то и другое одним вызовом. Одновременно выполняется не
больше одной корневой задачи, и пока она идёт, никакая другая задача этого
контроллера состояние не трогает.

**Рабочий тип `W`.** Подтип `S`, с которым задача согласна работать. Тело
видит `ctx.state` уже суженным до `W`. Тип проверяется перед стартом задачи,
при каждом изменении состояния, пока она идёт, и при каждом чтении через
контекст.

**Правила.** `canStart` проверяется один раз, когда задачу берут из очереди;
провал выбрасывает задачу с `Cancelled(rules, 'canStart')` и
`started: false`. `keepWhile` проверяется непрерывно — и перед стартом тоже,
вместе с `canStart`: задача, у которой инвариант уже нарушен, не стартует
вовсе, вместо того чтобы стартовать и умереть на первом чтении.

**Отмена.** Кооперативная: прервать чужой `await` в Dart нельзя. Отменённая
задача узнаёт об этом при следующем обращении к контексту — любой член
`JobContext`, кроме `log` и `job`, бросает `Cancelled` этой задачи, как
только она отмечена. После голого `await` зовите `ctx.check()`. Чтобы
дождаться чего-то и сразу сдаться при отмене, оберните это в
`ctx.guard(() => ...)`: guard возвращает управление, как только придёт одно
из двух: результат действия или отмена.

**Дети.** `ctx.run(child)` запускает задачу прямо сейчас, в обход очереди,
ребёнком текущей. Родитель завершается только после всех своих детей.
`ctx.run(child).done` даёт исход и никогда не бросает;
`ctx.run(child).value` даёт значение и бросает `Cancelled` ребёнка или его
ошибку в тело родителя.

**Внешнее состояние.** `externalSetState(next)` устанавливает состояние вне
всякой задачи: листенер железа, принудительный переход. Каждая работающая
задача, кроме излучившей, немедленно переоценивается по новому состоянию;
излучившая проверяется лениво, на следующем чтении.

**Исходы.** `Outcome<T>` — sealed, поэтому `switch` по трём его случаям
исчерпывающий: `Done` несёт возвращённое `value`, `Failed` несёт `error` и
`stackTrace`, `Cancelled` несёт `reason`, флаг `started`, необязательное
`description` и стектрейс самой отмены. Причина — это `CancelReason`:
`manual`, `rules`, `closed`, `parent`, `handler`. `job.done` завершается
исходом и никогда не бросает; `job.value` завершается значением или бросает;
`job.whenCancelled` завершается в момент, когда задача отмечена отменённой,
ещё до конца тела; `job.cancel()` отменяет и ждёт, пока задача действительно
завершится.

**Очередь и политики.** `queue` — объект первого класса, видимый
наследникам: `jobs`, `remove`, `removeWhere`, `clear`, `lastWhere`. Три
удаляющих метода пропускают задачи с `cancellable: false`, если не передан
`force: true`, и ни один из них не трогает выполняющуюся задачу. Политики —
сахар для типового случая одного ключа: `sequential` дописывает в конец;
`droppable` возвращает стоящую в очереди или выполняющуюся задачу с тем же
ключом, а новую выбрасывает; `replace` удаляет из очереди задачи с тем же
ключом; `restart` вдобавок отменяет выполняющуюся, не дожидаясь её.
`add(job, first: true)` ставит задачу в голову.

**Стрим.** `Solo.stream` — broadcast-стрим всех изменений состояния, по
порядку, доставляемых следующей микротаской: стрим асинхронный. Источник
правды — `state`: к моменту прихода события `state` может быть уже новее.
Равенство не проверяется; каждое изменение — одно событие. В `flutter_solo`
слушатели `SoloListenable` зовутся синхронно, в порядке подписки, пока
событие стрима ещё в пути.

## Правила, не видные из сигнатур

`cancellable: false` защищает задачу от чужой воли: ручного `cancel`,
`clear` без `force`, отмены родителя, `close`. От реальности не защищает:
если состояние перестало подходить по `W` или `keepWhile`, задача отменяется
всё равно, потому что читать ей уже нечего. Неотменяемой задаче, которая
должна пережить любое состояние, нужен базовый тип `S` и никакого
`keepWhile`.

`emit` доверяем, чтения проверяем. Излучённое состояние не проверяется
против правил излучившей задачи — иначе задача `close`, объявленная как
`run<NotClosed, void>`, отменяла бы сама себя в тот момент, когда излучит
`Closed()`.

`ctx.run(child)` возвращает хэндл, а не значение.
`await ctx.run(child).value` бросает в родителя,
`switch (await ctx.run(child).done)` — нет. Забытый `await` ничего не
ломает: родитель дожидается своих детей в любом случае.

Задача, переданная в `ctx.run`, становится ребёнком, даже если её выбросят
до старта. Сначала она регистрируется ребёнком и только потом проверяется по
правилам, поэтому родитель всегда отчитывается за каждую задачу, которую
пытался запустить.

`add` в закрытый контроллер не бросает. Он возвращает задачу, уже
завершённую с `Cancelled(closed)`, так что местам вызова проверка
`isClosed` не нужна.

Любая политика, кроме `sequential`, при `key == null` бросает
`ArgumentError`, а не `assert`: в release `null == null` истинно, и
`replace` вычистил бы из очереди все задачи без ключа.

`ctx.emit` и `ctx.run` после завершения задачи бросают `StateError`.
Контекст, утёкший из своей задачи — захваченный замыканием, которого никто
не дождался, — не должен писать состояние вне критической секции. Чтения
(`state`, `stateAs`, `check`, `guard`, `log`) после завершения задачи
законны.

`close()`, которого ждут изнутри тела текущей задачи, не завершается
никогда: он ждёт как раз это тело. То же и с `cancelAll()`. Отменяйте
изнутри выходом из тела или броском `Cancelled('why')`.

Из тела задачи видна вся поверхность наследника `Solo`, поэтому `ctx.solo`
и нет.

## Рецепты

**Таймаут.** Движок ничего не знает о таймаутах; `guard` плюс
`Future.timeout` — вот и весь рецепт. На таймауте тело бросает, и задача
заканчивается исходом `Failed`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        await ctx.guard(
          () => hw.open().timeout(const Duration(seconds: 5)),
        );
        ctx.emit(const Connected());
      },
    );
```

**Debounce.** Тоже вне движка: держите `Timer` в контроллере и запускайте
задачу, когда он сработает. Совмещайте это с `Policy.restart`, чтобы задачу,
всё ещё работающую с предыдущим вводом, отменяли, а не дожидались:

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  Timer? _debounce;

  Search() : super(const SearchState.idle());

  void query(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        describe: () => text,
        (ctx) async {
          final results = await ctx.guard(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
```

**Хуки.** Контроллер может переопределить `onStart`, `onFinish`, `onError`,
`onLog` и `onChange`, чтобы реагировать на собственные задачи:

```dart
final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...задачи из примера выше...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

**Observer.** `SoloObserver` — сквозная версия тех же пяти хуков плюс
`onCreate` и `onClose`: аналитика, отправка ошибок, единый лог на все
контроллеры процесса. Движок зовёт observer перед собственным хуком
контроллера и независимо от него — наследник, забывший `super`, observer не
выключает:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

Чтобы трассировать сам движок, а не задачи, поставьте
`SoloBase.debug = print`.

## Flutter

`flutter_solo` добавляет `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>` и реэкспортирует весь `solo`. В контроллере меняется
только базовый класс — задачи выше остаются ровно такими, какие они есть, —
и дальше контроллер идёт прямо в `ValueListenableBuilder`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class CameraController extends SoloListenable<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  // ...задачи из примера выше...
}

class CameraView extends StatelessWidget {
  const CameraView({super.key, required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<CameraState>(
        valueListenable: camera,
        builder: (context, state, _) => switch (state) {
          Ready(:final zoom) => Text('zoom $zoom'),
          _ => const CircularProgressIndicator(),
        },
      );
}
```

`value` и `state` — один и тот же объект. Сеттера нет намеренно: лицо
`ValueNotifier` было бы дырой в гарантии владения.

## Пример

[`packages/solo/example/`](packages/solo/example) — работающий пакет:
фейковая камера, железо которой отвечает с задержкой и может сломаться
само, полный контроллер из примера выше, четыре теста по упорядоченному
журналу и `bin/main.dart`, печатающий тот же журнал в реальном времени.

```sh
cd packages/solo/example
dart run bin/main.dart
dart test
```
