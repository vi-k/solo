> **Состояние на 2026-10-03:** сделано и закоммичено в `main`, не отправлено:
> член, тесты, страницы и записи в `CHANGELOG.md`. Дизайн и код прошли
> независимое ревью, `2026-10-03-ctx-pause-design-review-report.md`: девять
> находок приняты и внесены.
> **Что это:** `ctx.pause(duration)` — пауза, которую отмена кончает сразу
> и вместе с таймером.
> **Связанные записи:** `2026-10-03-ctx-pause-design-review-report.md`,
> `2026-10-03-job-each-design.md` (пример, с которого
> начался вопрос), `2026-09-04[4]-join-design.md` (`wait`, `join` и правило про
> голый `await`).

# Пауза в теле задачи: ctx.pause

## Зачем

Владелец 2026-10-03, по примеру `watchTicks` на странице `children.md`:

```dart
await ctx.wait(
  () => Future<void>.delayed(const Duration(milliseconds: 2500)),
);
```

До такой записи трудно додуматься, и разработчик напишет `Future.delayed` без
`wait`. Решения владельца того же дня: имя `pause`, член `JobContext`,
документы поправить.

У обеих записей с `Future.delayed` свой дефект:

- голый `await Future.delayed(d)` контрольной точкой не служит: отменённая
  задача досиживает паузу целиком, прежде чем заметит отмену;
- `ctx.wait(() => Future.delayed(d))` уходит из ожидания сразу, но таймер
  остаётся: `Future.delayed` отменить нельзя. Тест
  `the same wait written with Future.delayed leaves its timer`
  в `packages/async_job/test/pause_test.dart`: после отмены на полпути
  у `FakeAsync` один незавершённый таймер.

## API

Член `JobContext`, рядом с `uncancellable`:

```dart
Future<void> pause([Duration duration = Duration.zero]);
```

Имя и форма параметра — как у `Future.pause` из Dart 3.13; пол пакета 3.6,
и сам `Future.pause` не используется. В `solo` слово «пауза» есть у рецепта
паузы очереди в `jobs.md`; это другой класс, и имена не сталкиваются.

## Поведение

`pause` — это `wait` вокруг своего таймера, и всё, что `wait` обещает
о контрольной точке, верно и для неё:

- на входе спрашивается `check()`: уже отменённая задача или нарушенное правило
  домена бросают сразу, и таймер не создаётся;
- отмена во время паузы кончает её тем же `Cancelled`, и таймер снимается;
- без `duration` пауза возвращается следующим оборотом цикла событий — таймером
  нулевой длины, как `Future.delayed(Duration.zero)`, а не микротаской;
  отрицательная длительность считается нулевой;
- внутри `uncancellable` отмена придержана до конца секции, и пауза идёт
  целиком;
- во время уборки бросает `StateError`, как `wait`: disposer, которому надо
  подождать, ждёт голый `Future.delayed`;
- из работы `unattended` работает как `wait` оттуда же.

После паузы правило домена не переспрашивается — как после `wait`.

Раньше срока паузу кончает только отмена. Пауза, от которой тело ушло, —
`unawaited`, проигравшая сторона `Future.any`, работа `unattended` после конца
тела — идёт до конца вместе с таймером, если задача кончилась иначе: так ведёт
себя любой вызов, который тело не ждёт. В колбэке `onCancel` задача уже
отменена, и пауза бросает сразу.

## Реализация

`JobContextBase` в `packages/async_job/lib/src/job_context.dart`:

```dart
@override
Future<void> pause([Duration duration = Duration.zero]) async {
  Timer? timer;
  try {
    await wait<void>(() {
      final elapsed = Completer<void>();
      timer = Timer(duration, elapsed.complete);
      return elapsed.future;
    });
  } finally {
    timer?.cancel();
  }
}
```

Регистрации `onCancel` нет: `wait` кончается на отмене сам, и `finally` снимает
таймер несколькими микротасками позже пометки. Движок, чей контекст наследует
`JobContextBase`, получает член даром; `solo` так и получает. Рукописный
`implements JobContext` перестаёт собираться — ломающая правка для фейков,
запись в «Breaking changes».

## Документы

- dartdoc члена;
- `packages/async_job/doc/cancellation.md`: раздел «Letting time pass» в конце
  страницы — первая попытка с голым `await Future.delayed` в теле, вторая
  с `ctx.wait` вокруг него, у которой остаётся таймер, и `ctx.pause`
  с таблицей; строка `ctx.pause` в таблице методов наверху; перевод;
- `watchTicks` в `children.md` и перевод — на `ctx.pause`;
- таблица «how the body waits» в `packages/solo/doc/errors.md` — строка
  `ctx.pause`, со сторожем в `cancel_delay_recipe_test.dart`;
- перечисления членов, которые ждут: шапка `JobContext` и `JobContextBase`
  в dartdoc, `packages/async_job/doc/cleanup.md`,
  `packages/async_job/doc/extending.md`, `packages/solo/doc/cancellation.md`,
  строка таблицы в `packages/solo/README.md` — и их переводы;
- `CHANGELOG.md` у `async_job`: «Added» и запись о фейках в «Breaking changes»;
  у `solo` — «Added».

`Future.delayed` вне тела задачи — в коде, который задачу создаёт и ждёт,
и в заглушках API — остаётся как есть. В `packages/async_job/doc/outcomes.md`
голая задержка в теле неотменяемого ребёнка изображает работу шага и тоже
оставлена.

## Приёмка

`packages/async_job/test/pause_test.dart`, под `FakeAsync`:

1. пауза без помех: тело идёт дальше ровно через `duration`, таймеров
   не осталось;
2. отмена на полпути: `Cancelled` сразу, таймеров не осталось;
3. та же пауза через `wait` и `Future.delayed`: таймер остался — сторож
   утверждения, ради которого член существует;
4. пауза в уже отменённой задаче: `Cancelled`, таймер не создан — счёт таймеров
   сразу после вызова, до `await`;
5. без `duration`: не микротаска, а таймер нулевой длины;
6. отмена во время паузы внутри `uncancellable`: пауза идёт целиком;
7. отмена после паузы, которая кончилась сама: в зону ничего не уходит;
8. пауза в disposer: `StateError` со словами `cannot pause`;
9. пауза в работе `unattended`, отмена: `Cancelled`, таймеров не осталось;
10. пауза, от которой тело ушло, в задаче с исходом `Done`: таймер остался;
11. отрицательная длительность: как нулевая;
12. пауза в колбэке `onCancel`: `Cancelled` сразу, таймера нет.

Мутации: таймер не снимается — 2; `Future.delayed` на месте таймера — 2; `join`
на месте `wait` — 2; `uncancellable` на месте `wait` — 2 и 9; микротаска при
нулевой длине — 5; таймер до контрольной точки — 2, 4 и 10; без
`throwIfFinished('pause')` — 8; таймер снимается в конце задачи — 10.

В `solo`, `packages/solo/test/cancel_delay_recipe_test.dart`: `ctx.pause`
у `SoloContext` кончается на отмене без таймера; правило `keepWhile`,
нарушенное во время паузы, спрошено один раз, на входе.

Страницу держат сторожа группы «Letting time pass»
в `packages/async_job/test/cancellation_rakes_test.dart`: числа таблицы сверены
с прогоном каждой из трёх версий.
