# solo и bloc рядом

Перевод
[packages/solo/doc/vs-bloc.md](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md).
Источник правды — оригинал.

Часть пакета [solo](https://pub.dev/packages/solo).

bloc хорошо ложится на обычный экран: пришло событие, обработчик ответил
состоянием. Восемь пунктов ниже — про контроллеры с жизненным циклом:
железо, устройства, плееры, фоновая синхронизация, — где с одним состоянием
происходит сразу несколько вещей и порядок важен.

Каждый пункт называет предметную область, потом показывает, что пишет для
неё опытная команда на bloc и чего этот код стоит, а потом то же самое на
`solo`. Где у bloc есть рабочий ответ, он здесь и работает; где ответа нет,
об этом сказано прямо. Ни одна из ловушек не баг: они следуют из устройства
bloc — трансформер на обработчик, `emit` действителен только внутри своего
обработчика, `add` возвращает `void`, — и там, где вопрос обсуждался в
трекере, стоит ссылка на issue.

Документ опирается на [раздел «Понятия»][concepts] из README: `Job` и
`Outcome`, `Policy`, рабочий тип `W` в `run<W, T>`, `ctx.guard` и очередь.

[concepts]: https://github.com/vi-k/solo/blob/main/packages/solo/README.ru.md#понятия

Каждый фрагмент кода ниже компилировался и запускался — фрагменты на bloc
против bloc 9.2.1 с bloc_concurrency 0.3.0, фрагменты на `solo` против
`solo` 1.0.0, — и все приведённые трассы взяты из этих запусков.

В том же пакете есть `Cubit`: ни событий, ни трансформеров, только методы,
которые излучают состояние. Пункты 5 и 6 он закрывает прямо — метод кубита
принимает типизированные аргументы и возвращает значение, которого можно
дождаться, — и felangel указывает на него в самом
[#1556](https://github.com/felangel/bloc/issues/1556). Для остального он не
даёт ничего: управлять нечем — очереди нет (1), трансформеров нет вовсе
(2, 3), отмены нет (4), а `emit` после `close` бросает `Bad state: Cannot
emit new states after calling close` (пункт 7 ниже).

## 1. Очередью нельзя управлять

Экран BLE-устройства. Пользователь открывает его — подключение, — жмёт
«прочитать заряд» и «прочитать уровень сигнала», переименовывает устройство
и закрывает окно: отключение. Оба чтения делались для экрана, которого
больше нет, и должны быть выброшены; переименование пользователь попросил
сам, и оно обязано уцелеть.

**На bloc.** Чтобы очередь вообще появилась, все команды сводят в один
`on<DeviceEvent>` с `sequential()`; пять отдельных `on<E>` дали бы пять
очередей, работающих бок о бок, а это следующий пункт. Очередь настоящая,
но непрозрачная — API, чтобы перечислить ожидающее или убрать его оттуда,
нет, — поэтому чтения отсекаются флагом, выставленным в `onEvent`, который
`add` зовёт синхронно, то есть раньше, чем очередь до них дойдёт.

```dart
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final Ble _ble;
  bool _leaving = false;

  DeviceBloc(this._ble) : super(const DeviceState()) {
    // Один обработчик на весь тип, чтобы `sequential()` делал одну очередь.
    on<DeviceEvent>((e, emit) async {
      // Чтения нужны были только экрану, который пользователь уже закрыл.
      if (_leaving && (e is ReadBattery || e is ReadSignal)) return;
      switch (e) {
        case Connect():
          await _ble.connect();
          emit(state.copyWith(online: true));
        case ReadBattery():
          emit(state.copyWith(battery: await _ble.battery()));
        case ReadSignal():
          emit(state.copyWith(signal: await _ble.signal()));
        case Rename(:final name):
          await _ble.rename(name);
        case Disconnect():
          await _ble.disconnect();
          emit(const DeviceState());
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(DeviceEvent event) {
    // `add` зовёт это синхронно, поэтому к моменту, когда очередь дойдёт
    // до двух чтений за `Disconnect`, флаг уже выставлен.
    if (event is Disconnect) _leaving = true;
    super.onEvent(event);
  }
}
```

Это работает: железо видит `[connect, rename kitchen, disconnect]`, а два
чтения не выполняются вовсе. Цена в том, что правило теперь живёт в поле
блока, а не в том месте вызова, которое знает, что экрана больше нет, и что
это условие, а не удаление: события всё так же идут по очереди и всё так же
доходят до обработчика, каждая команда, способная устареть, добавляет в это
условие слагаемое, а флаг надо где-то сбрасывать. Забудьте сброс — и заново
открытый экран молча проглотит собственные чтения: `[connect, disconnect,
connect]`, и ни одного чтения заряда.

И сказать тому, кто просил заряд, что запрос выброшен, нечем. `add`
возвращает `void`; это пункт 5.

**На solo.** Очередь — объект, которым владеет контроллер, а у задач в ней
есть ключи.

```dart
enum DeviceKey { connect, readBattery, readSignal, rename, disconnect }

final class DeviceController extends Solo<DeviceState> {
  final Ble _ble;

  DeviceController(this._ble) : super(const Offline());

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

Трасса железа та же самая. Разница в том, что правило — выражение в месте
вызова, вычисленное один раз, и сбрасывать нечего, и дополнять по мере
появления новых команд нечего; и в том, что оба чтения завершаются исходом
`Cancelled(manual)` и завершают свой `done`, так что вызывающие узнают, что
произошло. Переименование остаётся — пользователь его попросил и не
отменял, — а отключение идёт следом, потому что очередь последовательна, а
отключение добавлено последним. `removeWhere` трогает только очередь: уже
начавшийся `connect` сначала доработает.

## 2. Один restartable среди sequential

Медиаплеер. `play`, `pause` и `seek` говорят с одним нативным плеером,
поэтому выполняться должны по одному; но `seek`, выпущенный, пока
пользователь тянет ползунок, не должен вставать в очередь за более ранними
шагами того же движения — важна только последняя позиция, — а два
переключателя обязаны выполняться в том порядке, в каком их нажали.

**На bloc.** Трансформер — аргумент `on<E>` (или, глобально,
`Bloc.transformer`), и упорядочивает он только события этого одного
обработчика. Если дать `seek` собственный `on<Seek>` с `restartable()`,
эмиттер и правда начнёт перезапускаться, но обработчик пойдёт рядом с
`play` и `pause`, а не в одну линию с ними. Поэтому все три сводят в одну
воронку с `sequential()`, а движение ползунка прореживают полем с самым
свежим seek: одно поле, одно переопределение `onEvent` и один ранний
выход, и никакого собственного `EventTransformer` писать не надо.

```dart
class PlayerBloc extends Bloc<PlayerCommand, PlayerState> {
  final Player _player;
  Duration? _newestSeek;

  PlayerBloc(this._player) : super(const PlayerState()) {
    on<PlayerCommand>((command, emit) async {
      switch (command) {
        case Play():
          await _player.play();
        case Pause():
          await _player.pause();
        case Seek(:final position):
          // Все шаги движения, кроме самого свежего, отсекаются здесь.
          if (position != _newestSeek) return;
          await _player.seek(position);
          emit(PlayerState(position: position));
      }
    }, transformer: sequential());
  }

  @override
  void onEvent(PlayerCommand event) {
    if (event is Seek) _newestSeek = event.position;
    super.onEvent(event);
  }
}
```

Он делает то, что просили: `[play start, play end, seek 3 start, seek 3
end, pause start, pause end]` — один нативный seek на всё движение,
переключатели по-прежнему в порядке нажатий.

Чего он не может — остановить seek, который уже начался. Сделайте один шаг,
дождитесь, пока он дойдёт до плеера, сделайте второй — и трасса будет
`[seek 1 start, seek 1 end, seek 2 start, seek 2 end]`: устаревший шаг
договорит с устройством до конца, а более новый будет ждать за ним. Это
`Policy.replace`, а не `Policy.restart` — отбрасывание bloc получить может,
отмену нет; вторая половина — пункт 4. И правило написано руками для каждой
команды, которую надо прореживать.

**На solo.** Очередь последовательна по построению, а политика принадлежит
задаче, а не очереди.

```dart
enum PlayerKey { play, pause, seek }

final class PlayerController extends Solo<PlayerState> {
  final Player _player;

  PlayerController(this._player) : super(Ready());

  // play() и pause() выполняются в порядке нажатий.
  Job<void> pause() => run<Ready, void>(
        key: PlayerKey.pause,
        (ctx) async {
          await ctx.guard(_player.pause);
          ctx.emit(ctx.state.copyWith(playing: false));
        },
      );

  Job<void> seek(Duration position) => run<Ready, void>(
        key: PlayerKey.seek,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _player.seek(position));
          ctx.emit(ctx.state.copyWith(position: position));
        },
      );
}
```

`Policy.restart` выбрасывает стоящие в очереди seek и отменяет
выполняющийся — всё по ключу `seek`; у `play()` и `pause()` политики нет,
поэтому они остаются в той же единственной очереди и выполняются в том
порядке, в каком их нажали. Перезапуск достаёт до seek и ни до чего больше,
а политика — именованный аргумент, а не поле и ветка.

Нативный `seek`, который уже в пути, прервать нельзя — ни одну футуру в Dart
нельзя, — и трасса это показывает: `[seek 1 start, seek 2 start, seek 1 end,
seek 2 end]`. Меняется то, что его задача отменяется сразу, поэтому более
новый seek стартует, не дожидаясь её, а устаревший `emit` отклоняется.
Слушатели видят `[Ready(2ms)]` там, где bloc выше публиковал
`[PlayerState(1ms), PlayerState(2ms)]`, — ползунок не прыгает назад в позицию,
которую пользователь уже покинул, — а хэндл устаревшей задачи несёт
`Cancelled(manual)`.

## 3. Параллельные обработчики пишут в одно состояние

Заметки с синхронизацией. `UploadNote` и `RefreshList` меняют один и тот же
объект состояния, а с bloc 7.2 трансформер по умолчанию — конкурентный:
если трансформер не указан, оба обработчика работают одновременно.
`RefreshList` спрашивает сервер прежде, чем загрузка дойдёт, а отвечает уже
после неё, поэтому список, который старше заметки, записывается поверх
более нового. Чтение свежего `state` после каждого `await`, как это делают
оба обработчика ниже, лечит устаревший снимок, но не чередование: никакого
снимка тут нет, два обработчика просто ходят по очереди по одному объекту.

**На bloc.** Лекарство — форма из пункта 1, применённая ко всему
контроллеру: один обработчик на тип события с `sequential()`, чтобы между
`await` и `emit` всегда было не больше одного тела.

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Api _api;

  // Один обработчик на весь тип, поэтому все записи в состояние
  // сериализованы — та самая форма, к которой принуждал пункт 1.
  NotesBloc(this._api) : super(const NotesState()) {
    on<NotesEvent>((e, emit) async {
      switch (e) {
        case UploadNote(:final note):
          emit(state.copyWith(uploading: true));
          await _api.upload(note);
          emit(
            state.copyWith(notes: [...state.notes, note], uploading: false),
          );
        case RefreshList():
          emit(state.copyWith(notes: await _api.list()));
      }
    }, transformer: sequential());
  }
}
```

Это работает — итоговое состояние `NotesState([n0, n1], uploading: false)`,
заметка на месте, — и стоит формы. Один обработчик на тип означает один
трансформер на все команды внутри него, поэтому политика на команду из
пункта 2 закрыта навсегда, а весь контроллер — один `switch`.

Глубже лежит другая цена: гарантия здесь — соглашение, а не правило.
Трансформер на обработчик её не даёт: с `sequential()` на каждом из двух
отдельных `on<E>` заметка всё равно теряется —
`NotesState([n0], uploading: true)`, — потому что два обработчика это две
очереди. И в тот день, когда кто-нибудь зарегистрирует третий `on<E>` под
новый тип события, у состояния снова окажется два писателя, молча, и ни
одна сигнатура при этом не изменится.

**На solo.** Очередь одна и корневая задача выполняется одна, поэтому
чередоваться не с чем.

```dart
final class NotesController extends Solo<NotesState> {
  final Api _api;

  NotesController(this._api) : super(const NotesState());

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
никакая другая корневая задача этого контроллера состояние не пишет.
Внутрь ведут два пути: собственные дети, запущенные `ctx.run` в том же
теле, и `externalSetState` снаружи — оба осознанные, оба видны. Это
гарантия владения, а не дисциплина, которую два тела должны соблюдать, и
десятый метод её под угрозу не ставит.

## 4. После отмены обработчик продолжает работать

Обновление прошивки по BLE, кусок за куском. Перезапущенная прошивка должна
перестать писать в устройство; `restartable()` закрывает эмиттер, и это
всё, что он делает: цикл продолжает писать.

**На bloc.** Ответ здесь — от самого мейнтейнера, в
[felangel/bloc#3349](https://github.com/felangel/bloc/issues/3349):

> This is because Futures aren't truly cancelable. To get the behavior
> you're describing you can simply check if `emit.isDone` is true before
> performing any expensive computations:

(«Дело в том, что Future по-настоящему неотменяемы. Чтобы получить
описанное вами поведение, можно просто проверять, истинно ли
`emit.isDone`, перед любыми дорогими вычислениями».)

```dart
class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final Ble _ble;

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
}
```

В своих пределах это работает. Со строкой прошивка, перезапущенная на
середине файла, пишет `[0, 1, 100, 101, …]` и на этом останавливается. Без
неё две прошивки чередуются до конца: `[0, 1, 2, 100, 3, 101, 4, 102, 5,
103, 104, 105]` — два образа идут в одно устройство разом.

Строку надо повторять после каждого `await` в каждом цикле, трогающем
железо, и никто не проверит, что она там есть. А досягаемость её кончается
на эмиттере. Занесите отказ как состояние, а не как перезапуск — событие
`HardwareFailed`, излучающее `Broken`, поддерживаемый путь из пункта 8, — и
`emit.isDone` не станет истинным никогда: прошивка запишет
`[0, 1, 2, 3, 4, 5]` в сломанное железо, а потом перезапишет `Broken` на
`Flashing`. Зеркальный случай — футура, запущенная внутри обработчика и
оставленная без `await`: ничего, что пережило бы обработчик, тут не
устроено, поэтому её ловит только `assert` в debug
([#2961](https://github.com/felangel/bloc/issues/2961)) — см. пункт 7.

**На solo.** Отмена тоже кооперативная, но ожидание заканчивается само.

```dart
final class FirmwareController extends Solo<FirmwareState> {
  final Ble _ble;

  FirmwareController(this._ble) : super(const Idle());

  Job<void> flash(List<Chunk> chunks) => run<NotBroken, void>(
        key: 'flash',
        policy: Policy.restart,
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

Перезапуск пишет те же `[0, 1, 100, 101, …]`: `ctx.guard` возвращает
управление, как только пришла отмена, поэтому следующая запись не
начинается. Отличаются досягаемость и отчётность.

Тот же `guard` завершает задачу и тогда, когда состояние перестало
подходить рабочему типу, поэтому `Broken`, записанный слушателем железа,
останавливает прошивку на `[0, 1, 2]` с
`Cancelled(rules: is not NotBroken)`, а не даёт ей дописать файл, — случай,
которого `emit.isDone` не видит. Хэндл отменённого вызова несёт
`Cancelled(manual)` там, где `add` не нёс ничего. А работа, которая иначе
была бы запущена и брошена, идёт через `ctx.run(child)` — дочернюю задачу,
которую родитель дожидается.

## 5. Нельзя дождаться своего события

Оформление заказа. После нажатия «Оплатить» экран должен знать, что успешно
прошёл *именно этот* платёж, и только потом переходить дальше. `add`
возвращает `void`, а стрим состояний говорит лишь то, что состояние
изменилось. Так задумано, а не недосмотрено, — felangel в
[felangel/bloc#1556](https://github.com/felangel/bloc/issues/1556):

> … a single add can result in multiple state changes so you would never
> know when the event was actually "done" being processed.

(«…один add может привести к нескольким изменениям состояния, так что
узнать, когда событие на самом деле «обработано», вы не сможете».)

**На bloc.** Ответ — `Completer` внутри события и метод на блоке, отдающий его
футуру экрану.

```dart
class Pay extends CheckoutEvent {
  final Order order;
  final Completer<Receipt> result;

  Pay(this.order) : result = Completer<Receipt>();
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final Api _api;
  final _inFlight = <String, Completer<Receipt>>{};

  CheckoutBloc(this._api) : super(Cart()) {
    on<Pay>((e, emit) async {
      emit(Paying());
      try {
        final receipt = await _api.pay(e.order);
        emit(Paid(receipt));
        e.result.complete(receipt);
      } on Object catch (error, stackTrace) {
        emit(PaymentFailed(error));
        e.result.completeError(error, stackTrace);
      } finally {
        _inFlight.remove(e.order.id);
      }
      // `droppable()` отпадает: он выбросил бы дубль, не заходя в этот
      // обработчик, и его completer не завершился бы никогда.
    }, transformer: sequential());
  }

  /// То, чем место вызова пользуется вместо `add`.
  Future<Receipt> pay(Order order) {
    final running = _inFlight[order.id];
    if (running != null) return running.future;
    final event = Pay(order);
    _inFlight[order.id] = event.result;
    add(event);
    return event.result.future;
  }
}
```

и экран после этого — `navigateToReceipt(await bloc.pay(order))`, ровно то,
чего просил пункт: два нажатия по одному заказу ведут к одному чеку, а
второй заказ получает свой.

Цена — форма. Раз этот метод появился, он и есть то, чем `add` отказался
быть, а класс события — обвязка вокруг него, это пункт 6. Completer надо
завершить на каждом пути выхода, включая ошибку, иначе экран будет ждать
вечно; отсев дублей нельзя поручить `droppable()`, потому что выброшенное
событие в обработчик не заходит и его completer не завершается никогда, —
поэтому карта `_inFlight` написана руками. А выходы, которыми владеет сам
bloc, completer как раз и не видит: после `close()` вызов `pay()` бросает
`Bad state: Cannot add new events after calling close`, и это пункт 7.

**На solo.** Метод возвращает хэндл задачи, которую он создал.

```dart
final class CheckoutController extends Solo<CheckoutState> {
  final Api _api;

  CheckoutController(this._api) : super(const Cart());

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        // Ключ называет заказ, поэтому двойное нажатие — дубль, а другой
        // заказ — другая задача.
        key: ('pay', order.id),
        policy: Policy.droppable,
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
изменение состояния перед ним. Поскольку ключ называет заказ, а не метод,
`Policy.droppable` считает двойное нажатие тем дублем, каким оно и
является, — оба нажатия получают один хэндл и один чек, — а другой заказ
остаётся другой задачей. Три нажатия по двум заказам доходят до API дважды,
ровно как у написанной руками карты `_inFlight` выше, только карту писать
не надо. Отменённый и упавший пути приходят исходами, а не футурой, которая
никогда не завершится, а после `close` вызов возвращает задачу, уже
завершённую с `Cancelled(closed)`, вместо того чтобы бросить.

Дальше в том же обсуждении felangel указывает на `Cubit`: его методы —
обычные `async`-методы, которых можно дождаться, — ответ на этот пункт
ценой очереди событий и трансформеров из пунктов 1–4.

## 6. Метод, а не событие

Карта. `moveTo`, `setZoom`, `follow` — три действия на одном виджете, и
движение пальца выпускает `moveTo` на каждом кадре. В bloc с событиями
каждое действие — класс, регистрация и `add`: типы аргументов живут в
событии, работа живёт в обработчике где-то ещё, а место вызова говорит
`add`, а не то, чего оно хочет.

**На bloc.** `Cubit` закрывает это прямо: кубит и есть методы, — что
другими словами означает: вся эта обвязка принадлежит событиям, а не
пакету.

```dart
class MapCubit extends Cubit<MapState> {
  final MapApi _map;

  MapCubit(this._map) : super(const MapState());

  Future<void> moveTo(Point<double> point) async {
    await _map.moveTo(point);
    emit(state.copyWith(center: point));
  }

  Future<void> setZoom(double value) async {
    await _map.setZoom(value);
    emit(state.copyWith(zoom: value));
  }

  Future<void> follow(Track track) => _map.follow(track);
}
```

Обвязки нет, аргументы типизированы. Вместе с ней исчезла очередь: у кубита
её нет. Кадры движения идут все разом к одной нативной карте, и состояние
пишет тот вызов, который вернулся последним, а не тот, на котором палец
остановился. Дайте нативным вызовам разную длительность — и трасса будет
`[moveTo 1 start, moveTo 2 start, moveTo 3 start, moveTo 3 end, moveTo 2
end, moveTo 1 end]`: карта осядет на первом кадре движения, `MapState(1)`.

Чтобы вернуть порядок, футуры сцепляют в поле; чтобы отбросить устаревшие
кадры, рядом заводят поле с самой свежей точкой. Это пункты 1 и 2,
пересобранные руками, а `close()` у кубита цепочку к тому же не
дожидается.

**На solo.** Это три метода, а у движения есть политика.

```dart
enum MapKey { moveTo, setZoom, follow }

final class MapController extends Solo<MapState> {
  final MapApi _map;

  MapController(this._map) : super(const MapState());

  // Движение пальца выпускает это на каждом кадре; важна только самая
  // свежая точка.
  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _map.moveTo(point));
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          await ctx.guard(() => _map.setZoom(value));
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );

  Job<void> follow(Track track) => run<MapState, void>(
        key: MapKey.follow,
        (ctx) => ctx.guard(() => _map.follow(track)),
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);
```

Сигнатура несёт аргументы и результат, место вызова читается как вызов, а
возвращённый `Job<void>` есть на случай, если вызывающий захочет его
дождаться, — вызов без `await` не поднимает линтов, потому что хэндл не
`Future`. Движение прореживает та же `Policy.restart`, что и seek из пункта
2. На тех же неравномерных нативных вызовах трасса будет `[moveTo 1 start,
moveTo 3 start, moveTo 3 end, moveTo 1 end]`: средний кадр не стартует
вовсе, а задача первого отменена, поэтому её запоздавший возврат ничего не
пишет. Карта останавливается на `MapState(3)` — там же, где палец.

## 7. Закрытие, пока работа ещё идёт

Экран чата или ленты. Пользователь отправляет сообщение, уходит назад, и
ответ приходит в контроллер, который уже закрыт. Что будет дальше, зависит
от трансформера. С `sequential()` `close()` дожидается работающего
обработчика, и запоздавший `emit` доходит: состояние меняется после
`close`, и слушатели стрима его получают. С трансформером по умолчанию, с
`concurrent()`, `droppable()` или `restartable()`, `close()` возвращается
сразу, эмиттер отменён, и запоздавший `emit` выбрасывается молча. И в том,
и в другом случае тело продолжает работать.

**На bloc.** Обычный обходной путь — проверка `isClosed` после каждого
`await`.

```dart
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final Api _api;

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
}
```

Это работает: `close()` возвращается только после того, как вернулось тело,
сколько бы оно ни шло, и состояние остаётся нетронутым.

Одна пропущенная строка — и под `sequential()` состояние меняется после
`close`, и слушатели это видят; под любым другим трансформером та же
пропущенная строка молчит. `add` после `close` бросает `Bad state: Cannot
add new events after calling close`
([#52](https://github.com/felangel/bloc/issues/52),
[#120](https://github.com/felangel/bloc/issues/120) — оба из эпохи
`mapEventToState`, за несколько мажорных версий до `on<Event>`; отменяемые
операции всё ещё в статусе предложения,
[#3069](https://github.com/felangel/bloc/issues/3069)), поэтому каждому
месту вызова, которое может сработать после закрытия, нужна ещё и
собственная проверка.

Случай тяжелее — футура, пережившая свой обработчик. `emit` из неё роняет
`assert` в debug ([#2961](https://github.com/felangel/bloc/issues/2961)), а
с выключенными ассертами просто пишет состояние: один и тот же запуск
оставляет `ChatState(null)` под `dart run --enable-asserts` и
`ChatState(reply to hi)` без него — обработчик, вернувшийся давным-давно,
всё ещё двигает экран под пользователем.

**На solo.** Закрытие — часть той же дисциплины очереди.

```dart
final class ChatController extends Solo<ChatState> {
  final Api _api;

  ChatController(this._api) : super(const ChatState());

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

Разница не в ожидании: `sequential()` у bloc тоже дожидается тела, и тело
solo, которое пользуется голым `await` вместо `ctx.guard`, заставит
`close()` ждать ровно столько же. Разница в том, что устаревшая запись
отклоняется, а не принимается и не проглатывается молча, — и что
отклоняется она в release тоже.

`ctx.emit` отменённой задачи бросает её `Cancelled`; `emit` из футуры,
пережившей задачу, бросает `Bad state: Job(send) has already finished,
cannot emit` — именно `throw`, а не `assert`, поэтому с выключенными
ассертами он никуда не пропадает. Задачи из очереди завершаются с
`Cancelled(closed)` и завершают свой `done`, а `send` после `close`
возвращает задачу, уже завершённую с тем же исходом, вместо того чтобы
бросить, — так что месту вызова проверка `isClosed` не нужна.

## 8. Состояние меняется извне

Камера или BLE-датчик. Железо сообщает об отказе через листенер, пока
обработчик калибровки на середине пути, и всё, что идёт после этой точки,
говорит со сломанным железом.

**На bloc.** Собственный `emit` у bloc помечен `@visibleForTesting` и
описан как внутренний — «only for internal use and should never be called
directly outside of tests» («только для внутреннего использования, звать
его напрямую вне тестов нельзя»), — поэтому поддерживаемый путь внутрь из
листенера — `add(HardwareFailed(error))`. Этому событию нужен свой
обработчик, вне очереди калибровки, чтобы он мог работать рядом с ней, а не
за ней; а калибровка повторяет своё предусловие после каждого `await`.

```dart
class SensorBloc extends Bloc<SensorEvent, SensorState> {
  final Sensor _hw;

  SensorBloc(this._hw) : super(Ready()) {
    // Поддерживаемый путь внутрь — событие. У него свой обработчик, чтобы
    // он мог работать *рядом* с калибровкой, а не за ней.
    _hw.onError = (error) => add(HardwareFailed(error));
    on<HardwareFailed>((e, emit) => emit(Broken(e.error)));
    on<Calibrate>((e, emit) async {
      if (state is! Ready) return;
      await _hw.zero();
      // Broken мог прийти во время await; этот обработчик никто не отменил,
      // поэтому предусловие повторяется руками после каждого шага.
      if (state is! Ready) return;
      await _hw.sample();
      if (state is! Ready) return;
      emit(Calibrated());
    }, transformer: sequential());
  }
}
```

Это работает: состояние заканчивается на `Broken(cable unplugged)`, а
`Calibrated` не появляется вовсе.

Стоит это строки на каждый `await`, в каждом обработчике, всегда.
Предусловие невидимо в сигнатуре, поэтому новое состояние или новый `await`
означают повторный обход всех тел; пропустите одно — и калибровка запишет
`Calibrated` поверх `Broken`: экран датчика отрапортует об успехе на
отключённом железе.

И само разделение — не выбор. Примените лекарство из пункта 3 и заведите
отказ в ту же воронку — он встанет в очередь за калибровкой: `[Calibrated,
Broken(cable unplugged)]`, причём `Calibrated` по дороге опубликуется
слушателям. Сериализованные записи в состояние или отказ, способный
вклиниться, — трансформеры дают одно или другое, но не оба сразу.

**На solo.** Состояние пишет сам листенер, а правила остаются в
объявлении.

```dart
final class SensorController extends Solo<SensorState> {
  final Sensor _hw;

  SensorController(this._hw) : super(const Ready()) {
    // Листенер сам пишет состояние. Каждая работающая задача, которая
    // перестала подходить состоянию по рабочему типу или keepWhile,
    // отменяется сразу.
    _hw.onError = (error) => externalSetState(Broken(error));
  }

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
задачу и отменяет те, чей рабочий тип или `keepWhile` больше не держится:
калибровка завершается исходом `Cancelled(rules: is not Ready)`, и
вызывающий может это прочитать. Предусловие живёт в `run<Ready, void>`, где
движок проверяет его перед стартом, при каждом изменении состояния и при
каждом чтении, — в одном месте, и новый `await` в теле его наследует.

Уже начавшийся `sample()` всё равно доработает — и там, и там; прервать
футуру в Dart не может ни одна библиотека. Останавливается всё, что идёт
после неё.
