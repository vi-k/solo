# Тестирование

Контроллер тестируется через его `Job`: вызов ставит одну в очередь и её же
возвращает, а состояние, которое она публикует, приходит позже. Все примеры
ниже используют `package:test`, контроллер из быстрого старта и фейковое API,
которое отвечает через двадцать миллисекунд или падает:

```dart
class FakeProfileApi implements ProfileApi {
  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

  final String name;
  final Object? error;

  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final error = this.error;
    if (error != null) throw error;
    return name;
  }
}
```

Тестов на странице два вида. Один держит `Job` и ждёт её: исход — весь сигнал,
который ему нужен, а двадцать миллисекунд фейка он честно выжидает. Другому
нужно смотреть между событиями — в каком порядке легли два вызова, что будет
через пять секунд, — и ждать он не может ничего вовсе: такой тест идёт под
`package:fake_async`, где часы двигает сам тест. Три раздела ниже ждут;
`fakeAsync` начинается с четвёртого.

Семь разделов ниже открываются тестом, к которому ведёт словарь этого API
и `package:test`: проверка сразу после вызова, `close`, который должен дать
работе закончиться, `await` внутри `fakeAsync`, проверка внутри зоны. И под
каждым сказано, что этот тест делает вместо того, ради чего он написан.
Работающая версия идёт следом, под своим заголовком.

## Ожидание Job

### Первая попытка

```dart
test('load fills in the name', () {
  final profile = ProfileController(FakeProfileApi());

  profile.load();

  expect(profile.currentState, isA<Loaded>());
});
```

Тест падает, и состояние, которое он печатает, — `Initial`, даже не `Loading`,
которое тело публикует первой строкой. `load()` ставит `Job` в очередь
и возвращает управление; тело стартует следующей микротаской, а фейк отвечает
через двадцать миллисекунд после неё. К моменту проверки от загрузки
не случилось ничего, и сообщение читается так, будто контроллер пропустил вызов
мимо ушей.

### Ожидание исхода

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(
    profile.currentState,
    isA<Loaded>().having((state) => state.name, 'name', 'Ada Lovelace'),
  );

  await profile.close();
});
```

`done` завершается исходом и не бросает никогда, поэтому одна и та же строка
годится и для успешной загрузки, и для упавшей, и для отменённой. К её
завершению отработали и обработчики состояния, так что состояние, которое
читает тест, — окончательное.

`value` — вторая половина: значение, которое вернуло тело, или ошибка, которую
оно бросило:

```dart
test('a failed load carries the error to the caller', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  await expectLater(profile.load().value, throwsA(isA<StateError>()));
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});
```

Отмена — тоже исход, и тест про неё спрашивает `done`:

```dart
test('a cancelled load ends Cancelled', () async {
  final profile = ProfileController(FakeProfileApi());
  final job = profile.load();

  await job.cancel();

  expect(
    await job.done,
    isA<Cancelled>().having((outcome) => outcome.started, 'started', isFalse),
  );
  expect(profile.currentState, isA<Initial>());

  await profile.close();
});
```

`cancel()` завершается, когда `Job` закончилась, поэтому исход уже на следующей
строке. `done` отдаёт его как любой другой, а `value` бросил бы — и тест,
ожидающий отмену, вычитывал бы её из `throwsA`. `started: false` объясняет,
почему состояние не тронуто: `Job` стояла в очереди, тело не выполнялось вовсе,
и `onCancel` не звали ни разу. Отменённая на ходу загрузка кончится тем же
`Cancelled`, а состояние у неё будет то, которое опубликовал её `onCancel`.

## Закрытие контроллера

### Первая попытка

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  profile.load();
  await profile.close();

  expect(profile.currentState, isA<Loaded>());
});
```

`close()` отменяет, и проверка видит `Initial`. Здесь `Job` даже не вышла
из очереди: обе строки идут в одном такте, поэтому `close` отбрасывает её
с `Cancelled(closed)` до старта тела, и состояние остаётся тем, с которым
контроллер создан. Успевшая стартовать загрузка кончилась бы так же — отменой
там, где она ждала, и `onCancel` опубликовал бы `Initial` поверх своего
`Loading`.

### Дать работе закончиться

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;
  await profile.close();

  expect(outcome, isA<Done<String>>());
  expect(profile.currentState, isA<Loaded>());
});
```

Сначала дождались `Job`, и только потом `close` — как конец теста, а не как
способ подождать. Там, где у теста `Job` в руках нет — контроллер сам ставит
работу, очередь наполняет виджет, — `close` может выполнить то, что в ней уже
стоит:

```dart
await profile.close(mode: SoloCloseMode.drain);
```

Дренаж выполняет очередь, но не обещает, что работа удастся. Дренированная
`Job` всё ещё может упасть, и чего это стоит тесту — в следующем разделе.

## Ошибка, которую никто не прочитал

### Первая попытка

```dart
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});
```

Проверка проходит, а тест всё равно красный. Исход `Job` никто не прочитал,
поэтому движок отправляет ошибку в зону, в которой `Job` была создана, — здесь
это зона самого теста, — и тест падает с `Bad state: no network` и трассой,
которая идёт через `JobContext` и не называет ни одной строки теста. Тест,
который `Job` не ждёт вовсе, платит больше: ошибка приходит после его конца,
и об этом так и сказано — `This test failed after it had already completed`,
под именем теста, который уже прошёл, а выполняется в этот момент следующий.

### Чтение исхода

```dart
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  final outcome = await profile.load().done;

  expect(outcome, isA<Failed>());
  expect(profile.currentState, isA<Failure>());

  await profile.close();
});
```

Чтение `done` или `value` помечает `Job` наблюдённой, и наблюдённая ошибка —
дело теста, а не зоны. `Job`, которую тест запускает и сознательно бросает,
говорит об этом через `job.ignore()`: пометить наблюдённой, не дожидаясь.
Чтение `job.outcome` не помечает ничего — это взгляд в поле, а поле остаётся
`null`, пока `Job` не закончилась.

## Порядок событий

### Первая попытка

Время и порядок тестируются через `package:fake_async`, а что именно произошло,
собирает наблюдатель — один на все контроллеры процесса:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(Solo<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(Solo<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    Solo.observer = journal;
    addTearDown(() => Solo.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load started',
      'state: Loading',
      'load Cancelled(manual: duplicate)',
      'state: Loaded',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
  });
});
```

Журнал выходит в другом порядке:

```text
load Cancelled(manual: duplicate)
load started
state: Loading
state: Loaded
load Done(Ada Lovelace)
```

Оба вызова сделаны в одном такте, и очередь между ними не работала. `droppable`
находит первую `Job` всё ещё ждущей, и второй вызов отбрасывает ту, которую
только что создал, — внутри самого вызова, до того как хоть что-то стартовало.
Тест прав в том, что дубликат отброшен, и неправ насчёт случая, который назван
в его имени: ничего не выполнялось.

### Дать первой Job стартовать

```dart
final first = profile.load();
async.flushMicrotasks();
final second = profile.load();
```

Один `flushMicrotasks()` — вся разница между этими двумя случаями. С ним первая
`Job` выходит из очереди и публикует `Loading`, а второй вызов застаёт загрузку
выполняющейся:

```text
load started
state: Loading
load Cancelled(manual: duplicate)
state: Loaded
load Done(Ada Lovelace)
```

Отменённый дубликат в журнале — это новая `Job`, которую отбросил `droppable`;
оба вызова вернули первую, и это проверяет `identical`. Наблюдатель —
статическое поле на весь процесс, поэтому тест его сбрасывает, и сбрасывает
через `addTearDown`, а не строкой в конце — почему, в разделе
[Что один тест оставляет следующему](#что-один-тест-оставляет-следующему).

## Ожидание внутри fakeAsync

### Первая попытка

```dart
test('load fills in the name', () async {
  await fakeAsync((async) async {
    final profile = ProfileController(FakeProfileApi());

    final outcome = await profile.load().done;

    expect(outcome, isA<Done<String>>());
    await profile.close();
  });
});
```

Тест висит, пока его не убьёт таймаут теста. Колбэк засыпает на первом `await`
и возвращает future; `fakeAsync` отдаёт эту future наружу и разворачивается,
а промотать фейковые часы больше некому — ни один таймер внутри них
не сработает никогда. Проверка не выполняется вовсе, и единственный след
этого — таймаут, который читается как взаимная блокировка в контроллере.

### Проматывать вместо ожидания

```dart
test('load fills in the name', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignore();
    async.elapse(const Duration(milliseconds: 20));

    expect(job.outcome, isA<Done<String>>());
    expect(profile.currentState, isA<Loaded>());

    profile.close();
    async.flushTimers();
  });
});
```

Колбэк остаётся синхронным и читает `job.outcome` там, где тест выше ждал
`done`, а `ignore()` заменяет собой это чтение: внутри `fakeAsync` дождаться
нельзя ничего, и ошибка ушла бы в зону ненаблюдённой. `flushMicrotasks()`
выполняет микротаски; `Future(...)` и `Future.delayed(...)` работают
на таймерах и требуют `elapse(...)` или `flushTimers()`. Отмена запрашивается
так же: `job.cancel().ignore()` — этот `ignore()` уже `Future.ignore`, на той
future, которую вернул вызов, — и вступает в силу следующей микротаской.
`close()` и последний `flushTimers()` заканчивают тест с пустыми часами;
контроллер, оставленный с работой в полёте, так и останется, а про таймер,
который никто не тронул, `fakeAsync` не скажет ничего.

`elapse` двигает вместе с таймерами и `clock.now()`, поэтому рецепт, который
штампует время, — наблюдатель
из [Почему отмена была долгой](errors.md#почему-отмена-была-долгой) —
тестируется здесь же, и ждать ради этого тесту не приходится.

## Что один тест оставляет следующему

### Первая попытка

```dart
test('a second load while the first one runs is dropped', () {
  final journal = Journal();
  Solo.observer = journal;

  // ...сам тест...

  Solo.observer = null;
});
```

Сброс выполняется, когда тест проходит, то есть когда он и не нужен. `expect`
сообщает о провале броском `TestFailure`, поэтому первая же не прошедшая
проверка пропускает все строки под собой, и журнал закончившегося теста
остаётся установленным для следующего: собирает строки, которые никто
не читает, и рассказывает о контроллерах, которых в глаза не видел.

### addTearDown

```dart
Solo.observer = journal;
addTearDown(() => Solo.observer = null);
```

`addTearDown` выполняется и после провала, и после успеха. Процессу,
а не контроллеру, принадлежат четыре статических поля, и каждое переживает тест
одинаково: `Solo.observer`, `Solo.errorHandler`, `Solo.traceStateChanges`
и `Solo.debug`. У двух последних умолчание не `null` — `traceStateChanges`
включён везде, где работают `assert`, — поэтому тест, который их меняет,
возвращает найденное значение, а не константу.

## Проверки внутри зоны

### Первая попытка

```dart
test('a failure nobody read reaches the zone', () async {
  await runZonedGuarded(
    () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);

      expect(profile.currentState, isA<Failure>());
    },
    (error, stackTrace) => expect(error, isA<StateError>()),
  );
});
```

Тест зелёный, что бы зона ни поймала. `Job` отправляет ошибку в зону, в которой
создана, поэтому контроллер приходится создавать внутри `runZonedGuarded` —
а следом туда переезжают и проверки, где `expect` бросает `TestFailure`,
и обработчик собирает этот бросок, как любую другую ошибку. Проверка в самом
обработчике не лучше: о случае, когда ошибка не пришла вовсе, она не говорит
ничего.

### Собрать в зоне, проверить снаружи

```dart
test('a failure nobody read reaches the zone', () async {
  final zoneErrors = <Object>[];

  await runZonedGuarded(
    () async {
      final profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    },
    (error, stackTrace) => zoneErrors.add(error),
  );

  expect(zoneErrors, [isA<StateError>()]);
});
```

Зона собирает, тест проверяет после неё. Строку ниже безопасной делает дренаж:
к возврату из `close` `Job` закончилась и её ошибка отправлена.

## Таймауты

### Первая попытка

```dart
final name = await ctx.wait(
  () => api.fetchName().timeout(const Duration(seconds: 5)),
);
```

`Future.timeout` ограничивает ожидание, но не работу за ним. Через пять секунд
`Job` заканчивается `Failed(TimeoutException)`, очередь идёт дальше, а запрос
всё ещё в полёте и закончится позже и в никуда. Тест видит обе половины:
в момент конца `Job` фейк вызван и не вернулся; через несколько миллисекунд он
возвращается, и ждать его уже некому. Для результата, который можно отбросить,
этим история и исчерпывается, и строки выше достаточно.

### Таймер, связанный с устройством

Если операция устройства должна остановиться до следующей `Job`, свяжите таймер
с механизмом отмены устройства и дождитесь операции через `join`. В этом
примере API устройства завершается ошибкой при отмене токена, поэтому таймаут
приводит к ошибке `Job`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        final token = CancelToken();
        final timer = Timer(const Duration(seconds: 5), token.cancel);
        ctx.onCancel(token.cancel);
        try {
          await ctx.join(() => hw.open(cancelToken: token));
        } finally {
          timer.cancel();
        }
        ctx.emit(const Connected());
      },
    );
```

Блок `finally` отменяет таймер при любом выходе, а `ctx.onCancel` отдаёт тот же
токен отмене, пришедшей снаружи, так что отменённая `Job` тоже останавливает
устройство. Действительно ли устройство остановится и какую ошибку вернёт,
зависит от его API. Тесту эти пять секунд не стоят ничего:

```dart
test('connect gives up after five seconds', () {
  fakeAsync((async) {
    final camera = CameraController(FakeCamera());

    final job = camera.connect()..ignore();
    async.elapse(const Duration(seconds: 5));

    expect(job.outcome, isA<Failed>());
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
```
