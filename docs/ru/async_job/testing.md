# Тестирование

Задача идёт на таймерах и микротасках, поэтому тест может прогнать её
во времени под своим управлением и ничего не ждать в реальном времени. Такое
время тесту даёт `package:fake_async`.

## Отменённое открытие

Тест проверяет, что при отмене во время открытия база всё равно закрывается,
когда открытие завершится. `discard` закрывает значение, которое пришло после
отмены, как в разделе
[«Значение, которое приходит поздно»](cleanup.md#значение-которое-приходит-поздно).

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
