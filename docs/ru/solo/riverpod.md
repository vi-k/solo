# solo под riverpod

Приложение на riverpod остаётся на riverpod: граф провайдеров, кеш,
`AsyncValue`, по которому ветвится экран. Эта страница о том, что встаёт под
провайдер, когда у работы в нём есть порядок, который надо держать, и ресурс,
который надо закрыть. Контроллер `solo` живёт в провайдере: провайдер его
создаёт, экран читает через провайдер его состояние, а освобождение провайдера
контроллер закрывает. Код идёт на riverpod 3.5, на чистом Dart:
`flutter_riverpod` даёт тот же `Ref`.

Там, где riverpod оставляет работу приложению, её разбирают эта страница и её
соседи:

| Ловушка в riverpod | Что на неё отвечает | Где |
| --- | --- | --- |
| `Ref` после `await` в методе нотифаера, поле, которое сверяют с текущим вызовом | Метод контроллера не держит `Ref`, а `emit` отменённой задачи до состояния не доходит | [Нотифаер, который начинает заново](../async_job/riverpod-and-bloc.md#нотифаер-который-начинает-заново) |
| Провайдер освобождён, пока идёт его работа | `ref.onDispose(job.cancel)` | [Провайдер, которого больше нет](../async_job/riverpod-and-bloc.md#провайдер-которого-больше-нет) |
| Флаг и бросок после освобождения в debounce | `ctx.pause` в задаче под провайдером; в `solo` — `accumulate` с `debounce` | [Пауза самой задачи](../async_job/time.md#пауза-самой-задачи), [Поиск, который стреляет на каждый символ](accumulation.md#поиск-который-стреляет-на-каждый-символ) |
| Состояние контроллера на экране | `ref.notifyListeners` и `select` | [Контроллер под провайдером](#контроллер-под-провайдером) |
| Ресурс взят раньше, чем зарегистрирована его уборка | `discard` там, где ресурс берётся, `onClose` для того, что держит контроллер | [Камера, которую закрывают при уходе экрана](#камера-которую-закрывают-при-уходе-экрана) |
| Форма, отправленная дважды | `Policy.droppable` | [Форма, которую отправляют один раз](#форма-которую-отправляют-один-раз) |

Рецепт debounce из [руководства](https://riverpod.dev/docs/how_to/cancel)
riverpod после освобождения бросает `Exception('Cancelled')`. Приложение,
которое хочет отличать эту отмену от сбоя по типу, бросает свой класс;
`async_job` уже даёт этот тип всему коду: `Cancelled`.

Каждый раздел открывается версией, к которой ведёт API самого riverpod,
и показывает, что этот код делает. Состояния и трассы под фрагментами — то, что
код печатает при запуске.

## Контроллер под провайдером

Контроллер — камера. `open()` публикует `Opening`, открывает устройство
и публикует `Ready` с ним:

```dart
sealed class CameraState {
  const CameraState();
}

final class Closed extends CameraState {
  const Closed();
}

final class Opening extends CameraState {
  const Opening();
}

final class Ready extends CameraState {
  const Ready(this.device);

  final Device device;
}
```

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Closed());

  Job<void> open() => enqueue<CameraState, void>(
    key: #camera,
    policy: Policy.restart,
    ifCancelled: (state, cancelled) => const Closed(),
    (ctx) async {
      ctx.emit(const Opening());
      final device = await ctx.join(
        Device.open,
        discard: (device) => device.close(),
      );
      ctx.emit(Ready(device));
    },
  );
}
```

`Device` изображает камеру платформы: открытие занимает 50 мс, а `close()` её
освобождает. `ctx.join` ждёт открытия, даже если задачу тем временем отменили,
а его `discard` закрывает устройство, которое пришло к задаче, не закончившейся
`Done`. `ifCancelled` возвращает камеру в `Closed`, когда задачу отменяют, —
следующим `open()` при `Policy.restart` или `close()` контроллера. В трассах
устройство названо номером: `Ready(1)` держит первое открытое.

Провайдер создаёт контроллер и закрывает его при освобождении. Экрану нужно
и состояние, а контроллер зовёт своих слушателей при каждом изменении.
`ref.notifyListeners` — то, что riverpod даёт провайдеру, чей объект меняется
на месте, поэтому слушателем контроллера становится этот вызов.

### Первая попытка

```dart
// Первая попытка: контроллер зовёт уже освобождённый Ref.
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() => unawaited(controller.close()));
  return controller;
});
```

Экран открывает камеру и уходит через 10 мс, пока устройство ещё открывается.
`outcome` — исход задачи, которую вернул `open()`, `states` — состояния,
которые видел экран, а `device` — то, что стало с устройством:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
zone: Cannot use the Ref of Provider<Camera> after it has been disposed.
```

Экран был последним слушателем провайдера, поэтому riverpod освобождает
провайдер, а `onDispose` закрывает контроллер. `close()` отменяет открытие,
и его `ifCancelled` публикует `Closed`. Слушатель контроллера — всё ещё
`ref.notifyListeners` у `Ref`, освобождённого мгновением раньше; вызов бросает,
а ошибку слушателя контроллер отдаёт зоне.

### Снятие слушателя

```dart
final camera = Provider.autoDispose<Camera>((ref) {
  final controller = Camera()..addListener(ref.notifyListeners);
  ref.onDispose(() {
    controller.removeListener(ref.notifyListeners);
    unawaited(controller.close());
  });
  return controller;
});

// Экран: ref.watch(camera.select((camera) => camera.currentState))
```

Тот же экран уходит через 10 мс:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
zone: nothing
```

Слушатель уходит раньше, чем закрывается контроллер, и `Closed` отмены
не доходит ни до кого: экран ушёл вместе с провайдером. `removeListener`
сравнивает через `==`, а два отрыва метода `ref.notifyListeners` равны, поэтому
второе упоминание метода снимает то, что добавила первая строка.

Экран читает состояние через `select`: сам провайдер ничего не меняет, а только
оповещает, и `select` отдаёт экрану каждый новый `currentState`.
`StreamProvider` над потоком `SoloStream` не подошёл бы: поток несёт изменения,
а не состояние, в котором камера находится, когда экран подписывается.
Во Flutter экран может и взять контроллер через
`ref.watch(camera.select((camera) => camera))`, и строить по нему `SoloBuilder`
из [`flutter_solo`](https://pub.dev/packages/flutter_solo). `select` здесь
нужен: мост оповещает слушателей `camera` при каждой смене состояния, и виджет
с `ref.watch(camera)` перестраивался бы на каждую.

## Камера, которую закрывают при уходе экрана

Экран открывает камеру, когда появляется, и закрывает её, когда уходит,
в какой бы момент это ни случилось: пока устройство ещё открывается или после
того, как оно открылось. Без контроллера riverpod держит устройство
в собственном провайдере и закрывает его в `onDispose`.

### Первая попытка

```dart
// Первая попытка: уборка регистрируется после await.
final camera = FutureProvider.autoDispose<Device>((ref) async {
  final device = await Device.open();
  ref.onDispose(device.close);
  return device;
});
```

Экран уходит через 10 мс, пока устройство открывается; наблюдатель контейнера
печатает то, что падает:

```text
screen left at 10 ms
device: open 1 start, open 1 done
observer: nothing
```

Устройство остаётся открытым. riverpod освобождает провайдер, когда экран
уходит, а `onDispose`, который закрыл бы устройство, ещё не зарегистрирован:
строка, которая его регистрирует, ждёт за `await`. Когда открытие кончается,
провайдера уже нет, и эта строка бросает `UnmountedRefException`. С riverpod
3.5.0 `ProviderObserver` не слышит провайдер, который упал после освобождения,
и об открытом устройстве не сообщает никто; до 3.5.0 `providerDidFail` получает
это исключение как `Ref`, использованный после освобождения, и устройства тоже
не называет.

### Флаг до await

Руководство riverpod по [отмене](https://riverpod.dev/docs/how_to/cancel) велит
провайдеру отметить своё освобождение до первого `await` и проверить отметку
после него:

```dart
final camera = FutureProvider.autoDispose<Device>((ref) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final device = await Device.open();
  if (disposed) {
    await device.close();
    throw StateError('the screen left while the camera opened');
  }
  ref.onDispose(device.close);
  return device;
});
```

Экран уходит через 10 мс, а затем, со свежим провайдером, через 80 мс:

```text
screen left at 10 ms
device: open 1 start, open 1 done, close 1
screen left at 80 ms
device: open 1 start, open 1 done, close 1
```

Это работает: устройство закрывается по обе стороны открытия. Уборка живёт
в двух местах, в проверке после `await` и в `onDispose` следом за ней,
а порядок держит автор: флаг регистрируется до `await`.

### Уход после открытия камеры

Под контроллером из первого раздела уход во время открытия устройство
закрывает: `discard` забирает устройство, которое пришло к отменённой задаче.
Тот же экран уходит через 80 мс, после открытия:

```text
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done
```

Устройство остаётся открытым. `close()` отменяет задачи контроллера, а открытие
к этому времени кончилось `Done`: отменять уже нечего. Устройство в `Ready`
теперь принадлежит контроллеру, а не задаче, и `close()` его не закрывает.

### onClose

```dart
final class Camera extends Solo<CameraState> {
  Camera() : super(const Closed());

  Job<void> open() => enqueue<CameraState, void>(
    key: #camera,
    policy: Policy.restart,
    ifCancelled: (state, cancelled) => const Closed(),
    (ctx) async {
      ctx.emit(const Opening());
      final device = await ctx.join(
        Device.open,
        discard: (device) => device.close(),
      );
      ctx.emit(Ready(device));
    },
  );

  @override
  void onClose() {
    if (currentState case Ready(:final device)) {
      unawaited(device.close());
    }
  }
}
```

Экран уходит через 10 мс, а затем, со свежим провайдером, через 80 мс:

```text
screen left at 10 ms
outcome: Cancelled(closed)
states: Closed, Opening
device: open 1 start, open 1 done, close 1
screen left at 80 ms
outcome: Done(null)
states: Closed, Opening, Ready(1)
device: open 1 start, open 1 done, close 1
```

`onClose` выполняется один раз, когда все задачи контроллера закончились,
и закрывает устройство, которое держит состояние. Уход во время открытия идёт
как раньше: задача кончается `Cancelled`, `ifCancelled` публикует `Closed`,
а `discard` закрывает устройство. Ни флаг, ни порядок регистраций автору
держать не нужно: гонку ухода с открытием держит `discard` в месте, где
устройство берётся, а то, что контроллер держит после этого, — `onClose`.
Контроллер, у которого закрытие — отдельная задача, ждущая оборудование,
разобран в разделе [Освобождение камеры](camera.md#освобождение-камеры).

## Форма, которую отправляют один раз

Форма отправляет сообщение на сервер, и второе нажатие, пока сообщение в пути,
не должно отправить его снова. `send` изображает API: он отвечает через 30 мс
квитанцией с номером своего вызова.

### Первая попытка

Для отправки формы в riverpod 3 есть мутации, пока экспериментальные,
в `package:riverpod/experimental/mutation.dart`. Их документация на время
`MutationPending` заменяет кнопку индикатором загрузки. Вызывающий, который
идёт не через эту кнопку, читает то же состояние перед тем, как запустить
мутацию:

```dart
// Первая попытка: каждый вызывающий проверяет мутацию перед запуском.
final sendMessage = Mutation<String>();

Future<String?> submit(ProviderContainer container, String text) async {
  if (container.read(sendMessage) is MutationPending) return null;
  return sendMessage.run(container, (_) => send(text));
}
```

Во Flutter те же строки берут `WidgetRef` экрана. Экран отправляет `'hi'`,
а затем `'bye'`, пока `'hi'` в пути:

```text
right after the first: MutationPending<String>()
first: sent hi #1
second: null
calls: 1
```

Охрана работает: `run` переводит мутацию в `MutationPending` до того, как
вернуть управление, и второй вызов застаёт её там. Отличие от ответа ниже
узкое. Второй вызывающий получает `null`, а не квитанцию ушедшего сообщения.
И охрана живёт в каждом вызывающем, а не в мутации. Её документация говорит,
что пока мутации никак не ограничивают параллельные вызовы. Вызывающий без
проверки отправит сообщение второй раз.

### Policy.droppable

Форма — контроллер под провайдером, так же как камера в первом разделе:

```dart
sealed class MessageState {
  const MessageState();
}

final class Editing extends MessageState {
  const Editing();
}

final class Sent extends MessageState {
  const Sent(this.receipt);

  final String receipt;
}
```

```dart
final class MessageForm extends Solo<MessageState> {
  MessageForm() : super(const Editing());

  Job<String> submit(String text) => enqueue<MessageState, String>(
    key: #submit,
    policy: Policy.droppable,
    (ctx) async {
      final receipt = await ctx.join(() => send(text));
      ctx.emit(Sent(receipt));
      return receipt;
    },
  );
}
```

Те же `'hi'` и `'bye'`, и каждый вызывающий ждёт `value` той задачи, которую
вернул его `submit`:

```text
same job: true
first: sent hi #1
second: sent hi #1
calls: 1
state: Sent(sent hi #1)
```

Вызов, пришедший, пока идёт задача его ключа, получает при `Policy.droppable`
эту же задачу, и API вызывается один раз. Оба вызывающих ждут `value` одной
задачи и получают квитанцию. Вызывающий, который продолжает через `then`, берёт
задачу через `shared()`, как объясняет раздел
[Очередь и политики](jobs.md#очередь-и-политики). Отправка идёт через
`ctx.join`: сообщение — работа, которая должна закончиться, прежде чем очередь
двинется дальше. Под `ctx.abandonable` отменённая отправка шла бы и после конца
своей задачи, а следующий `submit` начал бы вторую, пока первая ещё в пути.

Цена `droppable` — оборотная сторона того же правила: второй вызов с другими
аргументами тоже получает первую задачу. `'bye'`, набранное, пока `'hi'` было
в пути, так и не уходит, а его вызывающий получает квитанцию `'hi'`.

## Что вы берёте на себя

Контроллер добавляет слой. Провайдер держит контроллер, контроллер держит
состояние, и это состояние — тип контроллера, а не `AsyncValue`. Мост
из первого раздела — код приложения, по одному на контроллер,
и `removeListener` в его `onDispose` обязателен.

Сколько живёт контроллер, решает провайдер. `ref.read`
у `autoDispose`-провайдера без слушателя создаёт контроллер и сразу его
освобождает, а задача, о которой его попросили, кончается `Cancelled`:

```text
read without a listener
outcome: Cancelled(closed)
device: open 1 start, open 1 done, close 1
```

Перестройка провайдера закрывает контроллер и отменяет его задачи:
`ref.invalidate` или изменение провайдера, который мост читает через
`ref.watch`.  Здесь экран остаётся, пока камера открыта, а провайдер
инвалидируют; экран получает новый контроллер, в `Closed`:

```text
camera invalidated
states: Closed, Opening, Ready(1), Closed
device: open 1 start, open 1 done, close 1
the first controller finished: true
```

Упавшую задачу контроллера riverpod не повторяет: его повтор — для провайдера,
который не смог построиться, а провайдер контроллера не падает. Повтор пишется
в теле задачи, как показывает раздел
[Повтор упавшего вызова](errors.md#повтор-упавшего-вызова).

`Policy.droppable` теряет аргументы второго вызова, как показывает форма.
А `solo` — ещё одна зависимость со своей моделью: очередь, ключи, политики,
правила состояния.

`solo` не нужен для одной операции под провайдером: это задача `async_job`, как
показывает страница [С riverpod и bloc](../async_job/riverpod-and-bloc.md).
Не нужен он и для запроса, который riverpod держит на каждый аргумент через
семейство провайдеров: с этим справляется сам riverpod.
