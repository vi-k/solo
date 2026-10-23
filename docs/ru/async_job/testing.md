# Тестирование

Задача идёт на таймерах и микротасках, поэтому тест может прогнать её
во времени под своим управлением и ничего не ждать в реальном времени. Такое
время тесту даёт `package:fake_async`.

## Отменённое открытие

Тест проверяет, что при отмене во время открытия база всё равно закрывается,
когда открытие завершится. `discard` закрывает значение, которое пришло после
отмены, как в разделе
[«Значение, которое приходит поздно»](cleanup-rules.md#значение-которое-приходит-поздно).

### Первая попытка

`cancel()` возвращает future, которая завершается, когда задача кончилась,
поэтому тест её ждёт:

```dart
// Первая попытка: ни один expect не выполняется.
test('a cancelled open still closes what it opened', () {
  fakeAsync((async) async {
    var closed = 0;
    final job = Job<Database>(
      (ctx) => ctx.join(
        Database.open,
        discard: (db) {
          closed++;
          return db.close();
        },
      ),
    );

    async.elapse(const Duration(milliseconds: 10));
    await job.cancel();

    expect(job.outcome, isA<Cancelled>());
    expect(closed, 1);
  });
});
```

Тест проходит, и с `expect(closed, 0)` прошёл бы точно так же: ни один `expect`
не выполняется. Вот что происходит:

1. Под `fakeAsync` время движется, только когда его двигает тест.
2. Колбэк возвращается на первом `await`, и `fakeAsync` возвращается вместе
   с ним.
3. Время больше никто не двигает, так что future из `cancel()` не завершается
   никогда, и код после неё не выполняется.

Если написать `() => fakeAsync(...)`, тест будет ждать эту future и упадёт
по таймауту.

### Тест двигает время

```dart
test('a cancelled open still closes what it opened', () {
  fakeAsync((async) {
    var closed = 0;
    final job = Job<Database>(
      (ctx) => ctx.join(
        Database.open,
        discard: (db) {
          closed++;
          return db.close();
        },
      ),
    );

    async.elapse(const Duration(milliseconds: 10));
    job.cancel().ignore(); // внутри `fakeAsync` никто ничего не ждёт
    async.flushTimers();

    expect(job.outcome, isA<Cancelled>());
    expect(closed, 1); // ради чего тест и назван
  });
});
```

Внутри `fakeAsync` никто ничего не ждёт. Future из `cancel()` проигнорирована,
`flushTimers()` доводит открытие до конца, и проверки видят то, что произошло.
Чем двигать время, зависит от того, чего тест ждёт:

| Тест ждёт | Он вызывает |
| --- | --- |
| Запуска задачи, чьё тело начинается в микротаске | `flushMicrotasks()` |
| Работы, запланированной через `Future(...)` или `Future.delayed(...)`, которые используют таймеры | `flushTimers()` или `elapse(...)` |
| Паузы `ctx.pause(duration)`, которая ждёт на таймере | `elapse(duration)` или `flushTimers()` |
| Срока из `timeout: limit`, который ядро держит на таймере | `elapse(limit)` или `flushTimers()` |

## Провал, которого тест ждёт

Тест проверяет, что открытие запертой базы падает.

### Первая попытка

```dart
// Первая попытка: проверка проходит, а тест падает.
test('a locked database fails the open', () {
  fakeAsync((async) {
    final job = Job<Database>((ctx) => ctx.join(Database.open));
    async.flushTimers();

    expect(job.outcome, isA<Failed>());
  });
});
```

```text
Bad state: database locked
```

`expect` проходит, а тест падает с той самой ошибкой, которую проверяет. Чтение
`outcome` провал не [наблюдает](outcomes.md#ошибка-которую-никто-не-ждёт):
никто не прочитал `done` или `value` и не вызвал `ignoreFailure()`, поэтому
провал уходит в [зону](errors.md#куда-уходят-ошибки), где задачу создали. Это
зона теста, а `package:test` роняет тест, до зоны которого дошла ошибка.
Ошибки, которых не несёт ни один исход, например ошибки уборки или
`ctx.unattended`, попадают туда же, если за них
не [отвечает](errors.md#ответ-за-ошибки) наблюдатель: см.
[«Куда идёт каждая ошибка»](error-rules.md#куда-идёт-каждая-ошибка).

### Провал читает тест

```dart
test('a locked database fails the open', () {
  fakeAsync((async) {
    final job = Job<Database>((ctx) => ctx.join(Database.open))
      ..ignoreFailure(); // провал тест читает из исхода
    async.flushTimers();

    expect(job.outcome, isA<Failed>());
  });
});
```

`ignoreFailure()` говорит, что о провале кто-то позаботится, и здесь это тест.
Тест, который читает `job.done` или `job.value`, тоже его наблюдает.

## Сравнение исходов

Тест проверяет значение задачи через её исход.

### Первая попытка

```dart
// Первая попытка: два исхода, которые печатаются одинаково, не равны.
test('the job loads three', () {
  fakeAsync((async) {
    final job = Job<int>((ctx) => ctx.join(load));
    async.flushTimers();

    expect(job.outcome, const Done(3));
  });
});
```

```text
Expected: Done<int>:<Done(3)>
  Actual: Done<int>:<Done(3)>
```

Своего `==` у исхода нет, поэтому два исхода равны, только когда это один
объект, а исход задачи никогда не тот, который строит тест.

### По типу и значению

```dart
test('the job loads three', () {
  fakeAsync((async) {
    final job = Job<int>((ctx) => ctx.join(load));
    async.flushTimers();

    expect(
      job.outcome,
      isA<Done<int>>().having((done) => done.value, 'value', 3),
    );
  });
});
```

С остальными так же: `isA<Cancelled>()` с `having` по `reason`
и `isA<Failed>()` с `having` по `error`.

## Настройки между тестами

```dart
setUp(() {
  final previous = Job.isCancellationError;
  Job.isCancellationError = (error) => error is DatabaseStopped;
  addTearDown(() => Job.isCancellationError = previous);
});
```

`Job.isCancellationError` и `Job.debug` статические. Тест, который задаёт одно
из них, задаёт его и для каждого теста после себя в том же файле: оставленный
фильтр не пускает названные им ошибки в зону этих тестов. `addTearDown`
возвращает то, что было.
