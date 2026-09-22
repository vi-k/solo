# Разделение хука ошибки: оповещение отдельно, ответ отдельно

> **Состояние на 2026-09-22:** план, к работе не приступали.
> **Что это:** план правки `Solo` к `0.3.0`: `onError` становится чистым
> оповещением, ответ за ошибку, которой некуда идти, переезжает в новый хук
> `onUnanswered`, а маркер `_homeless` уходит из ядра.
> **Связанные записи:** `2026-09-20-errors-rakes-report.md` (откуда пришёл
> вопрос), `2026-09-20-review-decisions-d-report.md` (последняя волна правок
> к `0.3.0`), `2026-09-19-solo-project-review.md`.

## Зачем

`Solo.onError` делает две работы сразу. Он оповещает контроллер об ошибке —
и он же развозит ту, за которую ответить больше некому: в `Solo.errorHandler`,
а без него в зону создания задачи. Переопределение заменяет тело целиком,
поэтому хук, написанный ради первой работы, молча отменяет вторую.

Цена видна в трёх местах.

**В ядре.** Раз хук один на две работы, ему нужно знать, какая ошибка пришла,
а из подписи это не следует. Поэтому в `packages/solo/lib/src/job.dart` живёт
поле-маркер `_solo._homeless`: оно выставляется и восстанавливается вокруг
вызова хуков в двух местах, с оговоркой про синхронную реентрантность через
`externalSetState`. Комментарий там говорит об этом прямо:

> `[Solo.onError]` takes two kinds and cannot tell them apart by itself:
> the body's failure, which has an outcome carrying it to the zone already,
> and this one, which has nothing.

Место вызова знает ответ, теряет его и протаскивает обратно через поле
контроллера.

**В наших же тестах.** Девять наследников `Solo` в `packages/solo/test`
переопределяют `onError`. `super` зовут три. Из шести остальных двое молчат
нарочно (`Silent` — первая попытка со страницы, `_Quiet` — так и назван),
четыре просто складывают ошибки в список и о маршруте не думали.

**На странице.** Раздел `Reporting an error` в `packages/solo/doc/errors.md`
открывается первой попыткой, которая существует только ради этой ловушки: хук,
отправивший отчёт и вернувшийся. Документация компенсирует острый край API.

## Что станет с API

```dart
/// Something a job did threw where there was nowhere else to put it.
/// Notification only: overriding it changes nothing about where the
/// error goes.
void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

/// Nobody answered for this error.
///
/// The default body hands it to [errorHandler], and to the job's
/// creation zone when no handler is set. Override it to answer for
/// these errors here instead.
void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
  ...
}
```

| Чего хочет читатель | Что он переопределяет |
| --- | --- |
| видеть ошибки контроллера | `onError`, и `super` ему не нужен |
| отвечать за бесприютные ошибки в этом контроллере | `onUnanswered` |
| отвечать за них во всём приложении | `Solo.errorHandler`, как и сейчас |
| смотреть за всеми контроллерами | `SoloObserver`, который не отвечает ни за что |

## Что станет с ядром

- `packages/solo/lib/src/solo.dart`: у `onError` пустое тело; новый
  `onUnanswered` с телом сегодняшнего маршрута; поле `_homeless` удаляется
  вместе с проверкой `identical`.
- `packages/solo/lib/src/job.dart`: `notifyError` больше не метит контроллер,
  а после `super.notifyError(...)` зовёт `onUnanswered` через `Solo._callHook`;
  `handleUnanswered` зовёт только `onUnanswered`. Второго оповещения там нет
  по устройству ядра — «The route is `notifyError`'s with that second
  announcement left out».
- `_SoloJobObserver.onError` не меняется: наблюдатель и хук получают
  оповещение, как сегодня.

## Зонды до правки

1. Полная карта путей: тело, уборка, колбэк отмены, операция, брошенная `wait`,
   бросившее правило, ребёнок, чью ошибку группа не бросила. Для каждого — кто
   слышит: наблюдатель, хук контроллера, обработчик, зона. Пять случаев сняты
   2026-09-22 и лежат в `2026-09-20-errors-rakes-report.md`; остались правило
   и ребёнок.
2. Непринятый провал ребёнка. Зонд 2026-09-22 на `ctx.runAll` с двумя падающими
   детьми дал `hook=[a, b] handler=[] zone=[]`: до обработчика не дошло ничего.
   Понять, гасит ли отмена сиблинга его `Failed` до `_conclude` (тогда зонд
   просто не создал нужного случая) или это дыра. Если дыра — чинить отдельно
   и до разделения.
3. Сколько раз хук контроллера слышит одну ошибку на каждом пути. Сегодняшнее
   «one error is announced once» проверено только для наблюдателя.

## Миграция внутри репозитория

После правки маршрут восстановится у всех, кто его терял, и у четырёх тестовых
контроллеров ошибки пойдут в зону: `Uploader` (`cancellation_rakes_test.dart`),
`_Hooked` (`hooks_test.dart`), `_Controller` (`state_handlers_test.dart`),
`_Recorder` и `_Watched` (`unattended_test.dart`). Каждому — по смыслу теста:
наблюдение исхода, `Solo.errorHandler` в тесте или переопределение
`onUnanswered`. `Silent` и `_Quiet` молчат нарочно и переопределяют
`onUnanswered`.

Вне тестов переопределений `Solo.onError` в дереве нет: ни в примерах,
ни в `flutter_solo`.

## Документация

- `packages/solo/doc/errors.md` и `docs/ru/solo/errors.md`: раздел
  `Reporting an error` теряет первую попытку — ошибаться станет не на чем,
  и по правилу скилла раздел начнётся с ответа. Абзац про маршрут
  переписывается на два хука. Проверить `Handled and unhandled failures`
  и `Background work and logs`: там маршрут упоминается.
- dartdoc `Solo.onError`, `Solo.errorHandler` и нового `Solo.onUnanswered`.
- `packages/solo/README.md` и `README.ru.md`: проверить, называют ли они
  `onError` местом отчётов.
- `packages/solo/CHANGELOG.md`: запись **Breaking** в `Unreleased`. Правка
  тихая — код, глушивший маршрут, скомпилируется и начнёт пускать ошибки
  дальше, — поэтому в записи должно стоять, что чинится это одной строкой:
  тем же телом в `onUnanswered`.
- `docs/architecture.md`: если маршрут ошибок описан там.

## Сторожа и мутации

Новые сторожа в `packages/solo/test/errors_rakes_test.dart`
и `hooks_test.dart`:

- переопределённый `onError` без `super` маршрут не уносит: обработчик спрошен;
- переопределённый `onUnanswered` без `super` берёт ответственность:
  ни обработчика, ни зоны;
- `onUnanswered` не зовётся для провала тела, у которого есть свой исход;
- хук слышит одну ошибку один раз на каждом пути;
- наблюдатель по-прежнему не отвечает ни за что;
- `Cancelled` не уходит в зону ни одним путём.

Мутации: снять маршрут в теле `onUnanswered`; не звать `onUnanswered`
из `notifyError`; не звать его из `handleUnanswered`; позвать `onError` дважды.
Сторож на первую попытку раздела уходит вместе с самой попыткой.

## Проверки

`dart format`, `dart analyze`, `dart test` в `packages/solo` и в его примере;
то же для `packages/flutter_solo` и его примера — он наследует хуки.
`async_job` не трогаем. Пять документных проверок, `tool/build_site.py`,
`jargon.py` и `bare_names.py` по обеим версиям страницы.

## Порядок

1. Зонды 1–3; если зонд 2 показал дыру — отдельная работа на неё.
2. Правка `solo.dart` и `job.dart`, сторожа, мутации.
3. Миграция шести тестовых контроллеров.
4. Документы, dartdoc, changelog.
5. Батарея, отчёт, коммит.

Работа берётся после слияния `worktree-doc-errors` в `main`: иначе раздел
`Reporting an error` придётся переписывать дважды. Ядро правится немного,
основная работа — в тестах и документах.

## Открытые вопросы

1. Имя хука. `onUnanswered` — по `JobBase.handleUnanswered` в ядре и по словарю
   dartdoc («watching is not answering»). Другие варианты: `answerFor`,
   `onHomeless`.
2. `@mustCallSuper` на `onUnanswered` не ставим: переопределение без `super` —
   это и есть «отвечаю сам».
3. Наблюдателю второй хук не нужен: наблюдение ни за что не отвечает.
4. В `async_job` править нечего: там оповещение и ответ уже разные методы,
   схлопывал их `solo`.
