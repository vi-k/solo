# Тестирование

Дождитесь исхода Job, чтобы синхронизировать тест перед проверкой
состояния. Следующий пример использует `package:test`; `FakeProfileApi`
является тестовой реализацией, возвращающей `'Ada Lovelace'`:

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

Для проверки результата используйте `job.value`, для проверки ошибки:
`await expectLater(profile.load().value, throwsA(...))`.

Для проверки времени и порядка используйте `package:fake_async`.
В следующем тесте фейковое API отвечает через 20 мс. Наблюдатель записывает
изменения состояния и завершения Job в один упорядоченный список:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, SoloTransition<Object> transition) =>
      lines.add('state: ${transition.current.runtimeType}');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    addTearDown(() => SoloBase.observer = null);
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    async.flushMicrotasks();
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

Отменённый дубликат в журнале является новой Job, которую отбросил
`droppable`. Оба вызова метода вернули исходную Job. Сбрасывайте
глобальный наблюдатель через `addTearDown`, чтобы неудачный тест
не оставил его установленным для следующих тестов.

Внутри `fakeAsync` запрашивайте отмену через `job.cancel().ignore()`
и продвигайте ожидающую работу перед проверкой. `flushMicrotasks()`
выполняет микротаски; `Future(...)` и `Future.delayed(...)` используют
таймеры и требуют `elapse(...)` или `flushTimers()`. Используйте
`emitsInOrder`, когда важен сам стрим; для итогового состояния обычно
достаточно прочитать `currentState` после `job.done`.

## Таймауты

`Future.timeout` ограничивает ожидание future; он не останавливает саму
операцию. Для запроса, результат которого можно отбросить, может хватить
`ctx.wait(() => api.fetch().timeout(...))`.

Если операция устройства должна остановиться до следующей Job,
свяжите таймер с механизмом отмены устройства и дождитесь операции
через `join`. В этом примере API устройства завершается ошибкой при
отмене токена, поэтому таймаут приводит к ошибке Job:

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

Блок `finally` отменяет таймер при любом выходе. Действительно ли
устройство остановится и какую ошибку вернёт, зависит от его API.
