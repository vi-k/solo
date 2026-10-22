# Тестирование

Контроллер тестируется через его задачи: вызов ставит `Job` в очередь и её же
возвращает, а состояние, которое она публикует, приходит позже. Каждый
из восьми разделов ниже сводится к одному правилу. Четыре правила — для теста,
который ждёт свою задачу или `close` контроллера:

- [«Ожидание задачи»](#ожидание-задачи): вызов только ставит задачу в очередь,
  поэтому тест ждёт её `done` или `value` и только потом читает состояние. Тест
  без этого ожидания падает с состоянием `Initial`.
- [«Закрытие контроллера»](#закрытие-контроллера): обычный `close()` отменяет
  загрузку, и тест видит `Initial`; тест, который не держит `Job`, ждёт через
  `SoloCloseMode.drain`.
- [«Ошибка, которую никто не прочитал»](#ошибка-которую-никто-не-прочитал):
  провал, который никто не прочитал, делает тест красным с ошибкой, которую
  не бросала ни одна его проверка, или приходит, когда тест уже прошёл, поэтому
  задача, которую тест не ждёт, получает `ignoreFailure()`.
- [«Проверки внутри зоны»](#проверки-внутри-зоны): задача создаётся внутри
  `runZonedGuarded`, зона собирает её ошибки, а тест проверяет снаружи. Тест,
  который проверяет внутри, проходит, ничего не проверив, или висит до своего
  таймаута.

Другие четыре — для теста под `fakeAsync`, который не ждёт ничего:

- [«Порядок событий»](#порядок-событий): порядок записывает наблюдатель,
  а `flushMicrotasks()` между двумя вызовами даёт первой задаче стартовать. Без
  этого `flushMicrotasks()` тест падает на порядке, которого не ждал.
- [«Ожидание внутри fakeAsync»](#ожидание-внутри-fakeasync): часы двигает
  `async.elapse`, тест читает `job.outcome` там, где ждал бы `done`,
  а `ignoreFailure()` помечает задачу. Тест, который ждёт внутри `fakeAsync`,
  висит до своего таймаута или проходит раньше, чем выполнятся его проверки.
- [«Что один тест оставляет следующему»](#что-один-тест-оставляет-следующему):
  наблюдатель — статическое поле, и таких полей ещё четыре; тест, который
  ставит такое поле, возвращает его в `addTearDown`, а не своей последней
  строкой: упавший тест эту строку пропускает и оставляет свой наблюдатель
  следующему.
- [«Таймауты»](#таймауты): `Future.timeout` прекращает ожидание, а не вызов;
  вызову, который должен остановиться, нужны `timeout` задачи и `ctx.onCancel`,
  а `Job.isCancellationError` называет ошибку его остановки, иначе она делает
  тест красным.

Тесты страницы импортируют `dart:async`, `package:fake_async/fake_async.dart`,
`package:solo/solo.dart` и `package:test/test.dart`;
`dart pub add dev:test dev:fake_async` добавляет `package:test` и `fake_async`
в dev-зависимости.

Из примеров ниже все, кроме последнего, гоняют `load` контроллера из раздела
[«Быстрый старт»](https://github.com/vi-k/solo/blob/main/packages/solo/README.ru.md#быстрый-старт)
README пакета:

```dart
final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue<ProfileState, String>(
        key: 'load',
        policy: Policy.droppable,
        ifFailed: (state, error, stackTrace) => Failure(error),
        ifCancelled: (state, cancelled) => const Initial(),
        (ctx) async {
          ctx.emit(const Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));
          return name;
        },
      );
}
```

`ifFailed` и `ifCancelled` у `load` служат обработчиками состояния: первый
превращает провал в `Failure`, второй возвращает состояние в `Initial`.
`key: 'load'` вместе с `Policy.droppable` заставляют второй вызов
присоединиться к уже идущей загрузке. Тесты ниже читают все три. API, которое
зовёт контроллер, фейковое: через двадцать миллисекунд после вызова оно
отвечает именем или бросает ошибку, которую ему дали.

```dart
class FakeProfileApi implements ProfileApi {
  final String name;
  final Object? error;

  FakeProfileApi({this.name = 'Ada Lovelace', this.error});

  @override
  Future<String> fetchName() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final error = this.error;
    if (error != null) throw error;
    return name;
  }
}
```

Тестов на странице два вида. Один держит `Job` и ждёт её: ему хватает исхода,
а двадцать миллисекунд фейка он честно выжидает. Другому нужно смотреть между
событиями (в каком порядке легли два вызова, что будет со сроком в пять
секунд), и ждать он не может ничего вовсе. Такой тест идёт под
`package:fake_async`, где часы двигает сам тест. Первые четыре раздела ниже
ждут; `fakeAsync` начинается с пятого.

## Ожидание задачи

Самый простой тест контроллера зовёт метод и смотрит на состояние: после
`load()` профиль должен быть `Loaded`, с именем, которое вернуло API.

### Первая попытка

```dart
// Первая попытка: проверка выполняется раньше загрузки.
test('load fills in the name', () {
  final profile = ProfileController(FakeProfileApi());

  profile.load();

  expect(profile.currentState, isA<Loaded>());
});
```

Тест падает и печатает состояние `Initial`, даже не `Loading`, которое тело
публикует первой строкой. `load()` ставит задачу в очередь и возвращает
управление; тело стартует позже, микротаской, а фейк отвечает через двадцать
миллисекунд после неё. К моменту проверки от загрузки не случилось ничего,
и сообщение читается так, будто контроллер пропустил вызов мимо ушей.

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
завершению отработали и обработчики состояния, так что тест читает
окончательное состояние.

`value` даёт вторую половину: значение, которое вернуло тело, или ошибку,
которую оно бросило:

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

Отмена тоже исход, и тест про неё спрашивает `done`:

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

`cancel()` завершается, когда задача закончилась, поэтому исход уже
на следующей строке. `done` отдаёт его как любой другой, а `value` бросил бы,
и тест, ожидающий отмену, вычитывал бы её из `throwsA`. `started: false`
объясняет, почему состояние не тронуто: задача стояла в очереди, тело
не выполнялось вовсе, и её обработчик `ifCancelled` не звали ни разу. Загрузка,
отменённая на ходу, тоже кончится `Cancelled`, уже со `started: true`,
а состояние у неё будет то, которое опубликовал её обработчик `ifCancelled`.

## Закрытие контроллера

`close()` возвращает future, которая завершается, когда контроллер закрылся.
Она читается как способ дождаться загрузки, не держа её `Job`: дождаться
`close`, а потом посмотреть на состояние.

### Первая попытка

```dart
// Первая попытка: close() отменяет загрузку раньше.
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  profile.load();
  await profile.close();

  expect(profile.currentState, isA<Loaded>());
});
```

`close()` отменяет, и проверка видит `Initial`. Здесь задача даже не вышла
из очереди: обе строки идут в одном такте, поэтому `close` отбрасывает её
с `Cancelled(closed)` до старта тела. Состояние остаётся тем, с которым
контроллер создан. Успевшая стартовать загрузка кончилась бы так же, отменой
там, где она ждала, и её обработчик `ifCancelled` опубликовал бы `Initial`
поверх `Loading`, который успело опубликовать тело.

### Дать работе закончиться

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Loaded>());
});
```

`SoloCloseMode.drain` выполняет то, что уже стоит в очереди, а не отбрасывает,
поэтому такой `close` годится, чтобы подождать. Он нужен тесту, у которого
`Job` в руках нет: контроллер сам ставит работу, очередь наполняет виджет.
Тест, который `Job` держит, ждёт её `done`, как в разделе выше, а `close`
у него остаётся концом теста.

Дренаж выполняет очередь, но не обещает, что работа удастся. Задача под
дренажем всё ещё может упасть, и чего это стоит тесту, сказано в следующем
разделе.

## Ошибка, которую никто не прочитал

Следующий тест о загрузке, которая падает: API бросает, и состояние должно быть
`Failure`. Сама `Job` тесту не нужна, поэтому ждать он поручает дренажу.

### Первая попытка

```dart
// Первая попытка: непрочитанный сбой роняет тест.
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  profile.load();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});
```

Проверка проходит, а тест всё равно красный. Исход задачи никто не прочитал,
а `Solo.unansweredHandler` не задан, поэтому движок отправляет ошибку в зону,
в которой `Job` была создана, здесь это зона самого теста, и тест падает
с `Bad state: no network`. Трасса под сообщением называет строку фейка, которая
бросила, и кадр движка, а строк теста в ней нет. Тест, который задачу не ждёт
вовсе, платит больше: ошибка приходит после его конца. В отчёте так и сказано —
`This test failed after it had already completed` — под именем теста, который
уже прошёл, а выполняется в этот момент следующий. Если же к этому времени
не выполняется ни один тест, прогон кончается раньше, чем приходит ошибка:
о ней не говорит никто, и прогон зелёный.

### ignoreFailure

```dart
test('a failed load shows the failure', () async {
  final profile = ProfileController(
    FakeProfileApi(error: StateError('no network')),
  );

  profile.load().ignoreFailure();
  await profile.close(mode: SoloCloseMode.drain);

  expect(profile.currentState, isA<Failure>());
});
```

`ignoreFailure()` помечает `Job` наблюдённой, не дожидаясь её, и наблюдённый
провал становится делом теста, а не зоны. Чтение `done` или `value` помечает её
так же, поэтому тесту, который ждёт исход, как в первом разделе, больше ничего
не нужно. Пометить нужно до микрозадачи после конца задачи. О провале, которым
никто не интересовался, движок сообщает на этой микрозадаче, поэтому тест,
который держит `Job`, закрывает контроллер с дренажем и читает `done` уже
после, всё равно красный. Чтение `job.outcome` не помечает ничего: это взгляд
в поле, а поле остаётся `null`, пока задача не закончилась.

Одна ошибка не достаётся ни одному из трёх: ошибка вызова, от которого задача
ушла. Отмените загрузку, пока фейк ещё отвечает, или закройте на ней
контроллер, и `ctx.abandonable` отпускает вызов. Задача кончается `Cancelled`;
вызов падает через двадцать миллисекунд, и его ошибка не принадлежит ни одному
исходу. Она уходит в зону, в которой задача создана, снова в зону теста, а тест
к этому времени уже закончился. Тест, который такую ошибку ждёт, ставит
`Solo.unansweredHandler`, и ошибка приходит ему вместо зоны: об этом раздел
[«Ответ за ошибку»](errors.md#ответ-за-ошибку) страницы об ошибках.

## Проверки внутри зоны

То, что непрочитанный провал доходит до зоны, когда `Solo.unansweredHandler`
не задан, обещает движок. Тесту этого обещания нужна своя зона, чтобы провал
в ней поймать: в зоне самого теста он и делает тест красным.

### Первая попытка

```dart
// Первая попытка: тест ничего не доказывает о зоне.
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

Тест проходит, и прошёл бы, даже если бы до зоны не дошло ни одной ошибки.
Проверка в обработчике сама по себе не спасает: его зовут, только когда ошибка
пришла. Не пришло ни одной, и он не выполнится ни разу, тест зелёный, а о зоне
не сказано ничего.

Проверке в теле не лучше. `Job` отправляет ошибку в зону, в которой создана,
поэтому `load()`, вызов, который её создаёт, приходится делать внутри
`runZonedGuarded`, а вместе с ним внутрь уезжает и проверка состояния. Там она
перестаёт быть проверкой: о провале `expect` сообщает броском `TestFailure`,
а бросок изнутри зоны достаётся её обработчику, как любая другая ошибка. Будь
состояние не `Failure`, обработчик получил бы этот `TestFailure`, сравнил его
со `StateError`, не нашёл совпадения и написал об этом со строкой обработчика,
а не той, на которой стояла проверка. А `await` не вернулся бы никогда, потому
что ошибка тела ушла в зону, а не в его future, и тест кончился бы таймаутом.

### Собрать в зоне, проверить снаружи

```dart
test('a failure nobody read reaches the zone', () async {
  final zoneErrors = <Object>[];
  late final ProfileController profile;

  await runZonedGuarded(
    () async {
      profile = ProfileController(
        FakeProfileApi(error: StateError('no network')),
      )..load();
      await profile.close(mode: SoloCloseMode.drain);
    },
    (error, stackTrace) => zoneErrors.add(error),
  );

  expect(profile.currentState, isA<Failure>());
  expect(zoneErrors, [isA<StateError>()]);
});
```

Зона собирает, а тест проверяет после неё, на своих строках: и состояние,
и ошибки. Для этого `profile` объявлен снаружи зоны, а присвоен внутри, где
и должна быть создана `Job`. Эти строки делает безопасными дренаж: к возврату
из `close` задача закончилась и её провал отправлен.

## Порядок событий

`Policy.droppable` нужна, чтобы второй `load()`, сделанный, пока идёт первый,
ничего своего не запускал. По состоянию этого не увидеть: оно кончается
`Loaded` в обоих случаях. Тесту нужно видеть порядок событий. Разделы о времени
и порядке идут под `fakeAsync`: этот,
[«Ожидание внутри fakeAsync»](#ожидание-внутри-fakeasync)
и [«Таймауты»](#таймауты). Там тест сам двигает часы и сам выполняет
микротаски, поэтому может остановиться между двумя вызовами. А что именно
произошло, собирает наблюдатель, один на все контроллеры процесса.

### Первая попытка

```dart
// Первая попытка: тест назван по случаю, которого не создаёт.
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
      'load Cancelled(duplicate)',
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
load Cancelled(duplicate)
load started
state: Loading
state: Loaded
load Done(Ada Lovelace)
```

Оба вызова сделаны в одном такте, и очередь между ними не работала. `droppable`
находит первую задачу всё ещё ждущей, и второй вызов отбрасывает ту `Job`,
которую только что создал: внутри самого вызова, до того как хоть что-то
стартовало. Тест прав в том, что дубликат отброшен, и неправ насчёт случая,
который назван в его имени: ничего не выполнялось.

Первую строку пишет `onFinish` отброшенной задачи, и другой строки ей
не достаётся. Тело не выполнялось, поэтому `onStart` для неё не было, а её
обработчик `ifCancelled` не звали, потому рядом и нет её собственного
состояния. Ключ в строке тот самый, по которому сработала политика, тот же
`load`, что и у второй задачи, так что различает их только исход. В исходе
`duplicate` стоит на месте причины, это `DuplicateCancelReason`: её
`Policy.droppable` даёт той задаче, которую отбрасывает, а `cancel()` снаружи
пишет там `manual`.

### Дать первой задаче стартовать

```dart
final first = profile.load();
async.flushMicrotasks();
final second = profile.load();
```

Вся разница между этими двумя случаями в одном `flushMicrotasks()`. С ним
первая задача выходит из очереди и публикует `Loading`, а второй вызов застаёт
загрузку выполняющейся:

```text
load started
state: Loading
load Cancelled(duplicate)
state: Loaded
load Done(Ada Lovelace)
```

Строку с отменой даёт та же отброшенная задача, что и выше, только теперь там,
где её ждал тест; оба вызова вернули первую `Job`, и это проверяет `identical`.
Наблюдатель хранится в статическом поле на весь процесс, поэтому тест его
сбрасывает, и сбрасывает через `addTearDown`, а не строкой в конце. Почему,
сказано в разделе
[«Что один тест оставляет следующему»](#что-один-тест-оставляет-следующему).

## Ожидание внутри fakeAsync

Тесту под `fakeAsync` нужно то же, что было у тестов первых разделов: исход
загрузки, а потом состояние. Привычка из тех разделов подсказывает дождаться
`done`.

### Первая попытка

```dart
// Первая попытка: никто не двигает поддельные часы.
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
и возвращает future. `fakeAsync` отдаёт эту future наружу и разворачивается,
а двигать фейковые часы и даже выполнять их микротаски больше некому: загрузка
так и не стартует, и ни один таймер внутри не сработает. Проверка
не выполняется вовсе, и остаётся от этого один след: таймаут, который читается
как взаимная блокировка в контроллере. Без `await` перед `fakeAsync` нет и его:
тест кончается сразу и зелёным, а ни одна из двух строк под первым `await`
не выполнилась.

### Проматывать вместо ожидания

```dart
test('load fills in the name', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignoreFailure();
    async.elapse(const Duration(milliseconds: 20));

    expect(job.outcome, isA<Done<String>>());
    expect(profile.currentState, isA<Loaded>());

    profile.close();
    async.flushTimers();
  });
});
```

Колбэк остаётся синхронным и читает `job.outcome` там, где тест выше ждал
`done`. `ignoreFailure()` заменяет собой это чтение: внутри `fakeAsync`
дождаться нельзя ничего, и провал ушёл бы в зону ненаблюдённым. Двадцать
миллисекунд фейка сделаны через `Future.delayed`, то есть таймером,
и перешагивает его `elapse`: один `flushMicrotasks()` оставляет задачу вовсе
без исхода, а состояние на `Loading`. `close()` и последний `flushTimers()`
заканчивают тест с пустыми часами; контроллер, оставленный с работой в полёте,
так и останется, а про таймер, который никто не тронул, `fakeAsync` не скажет
ничего. Этот же `flushTimers()` доводит до конца то, что оставила в полёте
отменённая загрузка, поэтому вызов, который падает поздно, падает внутри теста,
который его сделал.

Часы двигать не нужно только отмене:

```dart
final job = profile.load();
async.flushMicrotasks();

job.cancel();
expect(job.outcome, isNull);

async.flushMicrotasks();
expect('${job.outcome}', 'Cancelled(manual)');
```

Задача принимает отмену внутри самого вызова, а до исхода остаётся ещё
несколько микротасок: тело должно выйти из своего вызова `abandonable`,
а обработчик `ifCancelled` должен отработать. Строкой под вызовом исход ещё
`null`, и до `Cancelled` его доводит один `flushMicrotasks()`. Первый
`flushMicrotasks()` тот же, что в разделе выше. Он выпускает загрузку
из очереди, так что отменяется уже работающая загрузка; ту, что ещё стоит
в очереди, вызов отбрасывает сам, и её исход есть уже на следующей строке.

`elapse` двигает вместе с таймерами и `clock.now()`, поэтому здесь же
тестируется и рецепт, который отмечает время: наблюдатель из раздела
[«Отметка отмены»](diagnostics.md#отметка-отмены) страницы о диагностике. Ждать
ради этого тесту не приходится.

## Что один тест оставляет следующему

`Solo.observer` хранится в статическом поле, поэтому журнал теста выше всё ещё
установлен, когда начинается следующий тест, если его никто не убрал.

### Первая попытка

```dart
// Первая попытка: упавший expect пропускает сброс.
test('a second load while the first one runs is dropped', () {
  final journal = Journal();
  Solo.observer = journal;

  // ...сам тест...

  Solo.observer = null;
});
```

Сброс выполняется, только когда тест проходит. `expect` сообщает о провале
броском `TestFailure`, поэтому первая же не прошедшая проверка пропускает все
строки под собой. Тогда журнал закончившегося теста остаётся установленным для
следующего: собирает строки, которые никто не читает, и рассказывает
о контроллерах, которых в глаза не видел.

### addTearDown

```dart
Solo.observer = journal;
addTearDown(() => Solo.observer = null);
```

`addTearDown` выполняется и после провала, и после успеха. Процессу,
а не контроллеру, принадлежат пять статических полей. Каждое из них переживает
тест одинаково: `Solo.observer`, `Solo.unansweredHandler`, `Solo.debug`
с `Job.debug` ядра, который ставят рядом с ним, и `Job.isCancellationError`
ядра. Все пять начинают с `null`, его и возвращает сброс выше.

## Таймауты

Вызов, который не отвечает никогда, занял бы очередь насовсем, поэтому задача,
которая его делает, получает срок. Тест этого срока должен показать две вещи:
что задача кончается вовремя и что к этому моменту стало с вызовом.

### Первая попытка

Срок встаёт в `load` на место его строки
`final name = await ctx.abandonable(api.fetchName);`:

```dart
// Первая попытка: срок обрывает ожидание, а не вызов.
final name = await ctx.abandonable(
  () => api.fetchName().timeout(const Duration(milliseconds: 5)),
);
```

`Future.timeout` ограничивает ожидание, но не работу за ним. На пятой
миллисекунде задача заканчивается `Failed` с `TimeoutException`, очередь идёт
дальше, а вызов всё ещё в полёте и закончится позже и в никуда. Тест видит обе
половины:

```dart
test('the deadline ends the job, not the call', () {
  fakeAsync((async) {
    final profile = ProfileController(FakeProfileApi());

    final job = profile.load()..ignoreFailure();
    async.elapse(const Duration(milliseconds: 5));

    expect(job.outcome, isA<Failed>());
    expect(async.pendingTimers, hasLength(1));

    async.elapse(const Duration(milliseconds: 15));
    expect(async.pendingTimers, isEmpty);

    profile.close();
    async.flushTimers();
  });
});
```

Таймер, который остался на часах, когда задача кончилась, принадлежит самому
фейку: фейк вызван и не вернулся. Вернётся он на своей двадцатой миллисекунде,
через пятнадцать после конца задачи, и ждать его уже некому. Срок здесь пять
миллисекунд только потому, что фейк отвечает через двадцать: срок в секундах
против этого фейка не сработает никогда, и задача кончится `Done`. Для
результата, который можно отбросить, этим история и исчерпывается, и одного
`Future.timeout` достаточно.

### Срок самой задачи

Если операция устройства должна остановиться до следующей задачи, дайте задаче
срок через `timeout` и передайте механизм отмены устройства в `ctx.onCancel`.
Пример взят с контроллера камеры, а не профиля. Устройство контроллер держит
в `hw`; `CancelToken` принадлежит API устройства, а не этому пакету, а `Idle`
и `Connected` служат состояниями:

```dart
final class CameraController extends Solo<CameraState> {
  final Camera hw;

  CameraController(this.hw) : super(const Idle());

  Job<void> connect() => enqueue<Idle, void>(
        key: 'connect',
        timeout: const Duration(seconds: 5),
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => hw.open(cancelToken: token));
          ctx.emit(const Connected());
        },
      );
}
```

Через пять секунд после старта тела задача отменяется так же, как её отменяет
`cancel()`: `ctx.onCancel` отменяет токен, а `join` ждёт, пока устройство
остановится, поэтому следующая задача стартует после этого. Отмена, пришедшая
снаружи, идёт тем же путём, так что отменённая задача тоже останавливает
устройство. Действительно ли устройство остановится, зависит от его API. API
устройства завершается `OpenCancelled` при отмене токена, и `join` бросает эту
ошибку, но задача к тому времени уже отменена: она кончается
`Cancelled(timeout)`, а не `Failed`. Ошибка не становится ничьим исходом,
и задача отвечает за неё, как за любой провал своего тела: если её не трогать,
она доходит до зоны теста, и тест краснеет. Приложение один раз, в `main`,
называет остановку своего устройства полем `Job.isCancellationError` ядра,
а тест называет её так же и возвращает поле на место. Тогда до зоны ничего
не доходит, и `ignoreFailure()` тесту не нужен. Поле разобрано в разделе
[«Ошибки отмены»](../async_job/errors.md#ошибки-отмены) страницы об ошибках
пакета `async_job`.

Тесту эти пять секунд не стоят ничего: его `FakeCamera` — устройство, которое
само не отвечает никогда, `Camera`, чей `open` ждёт, пока тест не велит ему
ответить. Отменённый токен роняет ждущий вызов с `OpenCancelled` и засчитывает
его в `refused`. Фейк целиком лежит
в [`test/support/testing_camera.dart`](../../../packages/solo/test/support/testing_camera.dart),
вместе с заменами `CancelToken` и `OpenCancelled` из API устройства. Тест
смотрит за миллисекунду до срока и в сам срок:

```dart
test('connect gives up after five seconds', () {
  Job.isCancellationError = (error) => error is OpenCancelled;
  addTearDown(() => Job.isCancellationError = null);

  fakeAsync((async) {
    final hw = FakeCamera();
    final camera = CameraController(hw);

    final job = camera.connect();
    async.elapse(const Duration(milliseconds: 4999));
    expect(job.outcome, isNull);

    async.elapse(const Duration(milliseconds: 1));
    expect('${job.outcome}', 'Cancelled(timeout)');
    expect(hw.refused, 1);
    expect(camera.currentState, isA<Idle>());

    camera.close();
    async.flushTimers();
  });
});
```

За миллисекунду до срока у задачи нет исхода, а устройство ещё ждёт; в срок
токен отменяется, и `refused` засчитывает вызов, который устройство отпустило.
`connect()` не даёт `enqueue` обработчиков состояния, поэтому состояние
остаётся `Idle`. У `enqueue` с `ifCancelled` срок попадает туда,
а не в `ifFailed`. Таймер, который ядро держит для него, исчезает, как только
задача кончилась: после пяти секунд `async.pendingTimers` пуст. Как в этом
обработчике отличить срок от других отмен, показывает раздел
[«Срок задачи»](cancellation.md#срок-задачи) на странице об отмене.
