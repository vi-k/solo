# Переделка страницы «async_job in a bloc app»: дизайн

> **Состояние на 2026-11-04:** брошено. Ревью дизайна показало, что сильнейший
> ответ одного bloc — стрим с `onCancel` в `emit.forEach` — даёт ту же
> остановку работы без задачи, и владелец решил страницу ядра о bloc снять,
> а не переделывать: «да, убираем». Сделано тем же коммитом, что эта шапка.
> **Что это:** новый состав страницы ядра о bloc после ревью простоты: три
> прежних раздела уходят в таблицу, их место занимают сценарии, где задача
> несёт отмену bloc до самой работы, и каждый сравнивается с сильнейшим
> ответом одного bloc.
> **Связанные записи:** `2026-11-04-bloc-pages-simplicity-report.md`,
> `2026-11-03-bloc-pages-design.md`, `2026-11-04-bloc-pages-plan.md`,
> `2026-11-04-bloc-pages-report.md`.

## Зачем

Ревью простоты, `2026-11-04-bloc-pages-simplicity-report.md`, ответило
на вопрос владельца «проще ли такие решения для пользователя» о странице ядра
`packages/async_job/doc/bloc.md` словом «нет»: в каждом из трёх разделов
сильный ответ одного bloc — ранний `isClosed`, блокировка `synchronized`
с одной проверкой, `try`/`finally` — даёт ту же трассу с меньшим числом
понятий. Находки C1, C2 и I2. Слово владельца 2026-11-04 — «Переделать»: три
раздела уходят в таблицу «Where bloc keeps its answer» с ответом bloc,
а страница строится вокруг того, где задача сильнее.

Рамка прежнего дизайна, `2026-11-03-bloc-pages-design.md`, остаётся: читатель
живёт на bloc и bloc не бросит, страница показывает, ради чего ему взять ядро
вместе с bloc, без призыва переходить (решение 133 `docs/settled.md`). Меняется
одно: разделы больше не берутся из сценариев `vs-bloc.md`. Ни один из них
задаче в обработчике не достался, и все они стоят в таблице.

## Что показывает страница

Одна мысль на всю страницу. Отмена bloc — замена обработчика у `restartable()`,
`close()` — перестаёт слушать обработчик, но работу не останавливает:
обработчик — это `Future`, и запрос, начатый в нём, идёт до конца. Задача несёт
эту отмену дальше, до самой работы: мост `watch` отменяет задачу, когда bloc
отменяет подписку, а задача — свой запрос через `ctx.onCancel`, своих детей
и свой срок. Каждый раздел — требование, где работу надо остановить,
а не просто перестать ждать.

Один bloc умеет то же сам, и это показано: токен клиента в поле, отменённый
в начале обработчика и в `close()`. Разделы сравнивают задачу с этим ответом,
а не с первой попыткой, и называют, что уходит и что приходит.

## Критерий отбора

Раздел стоит на странице, если при той же трассе, что у сильнейшего ответа
одного bloc, задача снимает с кода приложения поле, правило или шаг, который
можно забыть без следа, — и цена задачи названа в том же разделе. Сильнейший
ответ одного bloc ищется зондом, и ревью дизайна просят найти ответ сильнее.
Сценарий, где задача не снимает ничего, уходит в таблицу.

Прежний критерий, «Критерий отбора» `2026-11-03-bloc-pages-design.md`,
сравнивал ступень с ответом bloc из `vs-bloc.md`. Ревью простоты показало, что
эти ответы не сильнейшие, и этой разницей ступени и держались.

## Зонды

Прогнаны 2026-11-04 в пакете стенда `tool/bloc_snippets.py` (bloc 9.2.1,
`bloc_concurrency` 0.3.0, `async_job` из дерева), три версии на сценарий:
первая попытка, сильнейший ответ одного bloc, задача в обработчике. Сервер
фейковый: отвечает за заданное время, токен в форме `CancelToken` dio
останавливает его с `Aborted`. Строки — непустые строки класса bloc, без общих
`watch` и фейков. Код версий — в приложении «Код зондов».

**A. Поиск под `restartable()`.** «a» в 0 мс, «ab» в 10 мс, `close()` в 30 мс,
сервер отвечает за 50 мс.

```text
naive: [server: a started, server: ab started, closed, state "", server: a answered, server: ab answered], the zone []
token: [server: a started, server: ab started, server: a aborted, server: ab aborted, closed, state ""], the zone []
job, no filter: [server: a started, server: ab started, server: a aborted, server: ab aborted, closed, state ""], the zone [Aborted, Aborted]
job: [server: a started, server: ab started, server: a aborted, server: ab aborted, closed, state ""], the zone []
```

Строк: 7, 19, 12. Токен и задача дают одну трассу. У задачи нет поля
и переопределённого `close()`; её цена — мост `watch` и строка
`Job.isCancellationError = (error) => error is Aborted;` в `main`: без неё
прерванный запрос уходит в зону (`job, no filter`).

**B. Три части экрана грузятся разом.** Профиль за 30 мс, лента за 60 мс,
уведомления падают на 20 мс; провал одной части останавливает остальные,
перезапуск и `close()` останавливают все.

```text
naive, alerts fail: [server: profile 1 started, server: feed 1 started, server: alerts 1 started, server: alerts 1 failed, server: profile 1 answered, server: feed 1 answered, state "failed: Bad state: alerts 1"], the zone []
token, alerts fail: [server: profile 1 started, server: feed 1 started, server: alerts 1 started, server: alerts 1 failed, server: profile 1 aborted, server: feed 1 aborted, state "failed: Bad state: alerts 1"], the zone []
job, alerts fail: [server: profile 1 started, server: feed 1 started, server: alerts 1 started, server: alerts 1 failed, server: profile 1 aborted, server: feed 1 aborted, state "failed: Bad state: alerts 1"], the zone []
```

Перезапуск в 5 мс и `close()` в 15 мс: у первой попытки все шесть запросов
отвечают после `closed`, у токенов и у задачи все шесть прерваны до `closed`.
Строк: 13, 25, 16. Сильнейший ответ одного bloc — один токен на все три
запроса, как позволяет dio: `eagerError: true`, отмена токена в `catch`, ветка
`on Aborted` перед общим `catch`, поле и `close()`. Версия с токеном на каждую
часть и списком в поле даёт ту же трассу в 33 строках и в сравнение не идёт.
У задачи — `ctx.runAll`, который сам отменяет остальные ветки при первом
провале, и токен в каждой ветке; поля и `close()` нет.

**C. Срок, после которого экспорт останавливается.** Экспорту 100 мс, сервер
отвечает за 300 мс; по истечении срока экспорт прерывается на сервере,
а состояние говорит «timed out», чего не должно быть при перезапуске.

```text
naive, past the limit: [server: export 1 started, state "timed out", server: export 1 answered], the zone []
token, past the limit: [server: export 1 started, server: export 1 aborted, state "timed out"], the zone []
job, past the limit: [server: export 1 started, server: export 1 aborted, state "timed out"], the zone []
```

Перезапуск в 50 мс и `close()` в 70 мс: у первой попытки оба экспорта отвечают
после `closed`, у токенов и у задачи оба прерваны до него, «timed out»
не появляется. Строк: 11, 26, 15. У одного bloc — токен, `Timer`, флаг
`timedOut`, `finally` с `timer.cancel()`, поле и `close()`. У задачи —
`timeout:` задачи и `onError:` моста, который отличает `Cancelled` срока
от провала: замена и `close()` отменяют подписку, и `onError:` их не видит.

Вывод. B и C проходят критерий: при той же трассе уходят поле, `close()`
и шаги, забытый из которых не виден в трассе первой попытки, — `eagerError`
и отмена соседей в B, таймер, флаг и его сброс в C. A проходит узко: уходят
поле и `close()`, а приходят `watch` и фильтр, но без A токен через
`ctx.onCancel` пришлось бы объяснять внутри B. Поэтому A — короткий первый
раздел, который ставит механику токена, а B — главный.

Чего зонды не проверяли и что в состав не берётся: несколько ресурсов подряд
в одном обработчике. На одном ресурсе ревью простоты выигрыша не нашло (I2),
а на нескольких форма та же — вложенный `try`/`finally` против `dispose`
у каждого `ctx.join`, — и довода, которого нет у B и C, этот сценарий
не добавляет.

## Состав

Заголовок остаётся «async_job in a bloc app», путь —
`packages/async_job/doc/bloc.md`, перевод — `docs/ru/async_job/bloc.md`.

1. **Вступление.** Что страница показывает — мысль из раздела «Что показывает
   страница» — и для кого. Обещание «leaves the code less to do» уходит; на его
   месте — что каждый раздел ставит задачу рядом с ответом одного bloc
   на токенах и называет, что уходит и что приходит. Строка о том, что код идёт
   на bloc 9.2.1 с `bloc_concurrency` в чистом Dart, и о том, что состояния
   и трассы под кодом — его вывод, остаётся.
2. **«The bridge».** Остаётся как есть: `watch`, что `close()` делает под
   каждым трансформером, `sequential()` и `done` против `value`. Добавляется
   фраза I3 ревью простоты: прочитанный `done` с `Failed`, который обработчик
   не бросил дальше, не дойдёт ни до `onError` bloc, ни до зоны.
3. **«A request that stops with its handler»** — сценарий A. Первая попытка —
   `restartable()` один: запросы отвечают после `close()`. Ответ одного bloc —
   токен в поле. Задача — токен через `ctx.onCancel` в теле, поле и `close()`
   уходят. Цена названа: `watch` и строка `Job.isCancellationError` в `main`,
   без которой прерванный запрос уходит в зону. Механику токена и фильтра
   раздел не разбирает, а ведёт к «A request to abort» страницы
   `riverpod-and-bloc.md`; с dio строки те же, что там.
4. **«Parts that stop together»** — сценарий B. Первая попытка — `Future.wait`.
   Ответ одного bloc — общий токен, `eagerError`, отмена токена в `catch`, поле
   и `close()`. Задача — `ctx.runAll` с токеном в каждой ветке. Раздел ведёт
   к «When one failure makes the rest pointless» страницы `groups.md` за тем,
   что `runAll` бросает и чем отличается от `Future.wait`.
5. **«A deadline that stops the work»** — сценарий C. Первая попытка —
   `Future.timeout`: экспорт отвечает после «timed out». Ответ одного bloc —
   токен, таймер, флаг и `finally`. Задача — `timeout:` и `onError:` моста.
   Раздел ведёт к «A deadline of the job» страницы `time.md`.
6. **«Where bloc keeps its answer».** Вступление таблицы говорит, что в этих
   сценариях `vs-bloc.md` задача в обработчике ничего не снимает, и ведёт
   к «solo under bloc» там, где ответ — очередь. В таблицу встают три прежних
   раздела, ответом — сильнейший ответ одного bloc из ревью простоты:
   - закрытие с вызовом в полёте — `isClosed` до и после `await`, а если
     `close()` не должен ждать вызова, — `Completer`, который `close()`
     завершает и с которым вызов гонится;
   - запись, которая заканчивается до перезапуска, — блокировка `synchronized`
     с одной проверкой `emit.isDone` внутри;
   - ресурс, вернувшийся после отмены, — `try`/`finally`.

   Строка о внешнем изменении говорит прямо: задача даёт ту же трассу
   и не меньше кода, ответ — проверка (M2 ревью простоты).

Каждый раздел 3–5 построен как прежние: требование с конкретной историей,
`### The first attempt`, `### With bloc alone`,
`### With a job in the handler`, трассы под кодом и строка «What stays with
bloc». Первая попытка — версия, к которой ведёт словарь bloc: `restartable()`,
`Future.wait`, `Future.timeout`. В строке «What stays with bloc» названо и то,
что задача приносит: `watch`, фильтр, исходы.

## Что меняется вокруг

- **Стенд.** `tool/bloc_snippets.py` теряет драйверы шести блоков, которые
  уходят: `core_closing_*`, `core_write_*`, `core_resource_*`, и получает
  по три драйвера на сценарий — первая попытка, один bloc, задача —
  со сторожами: прерван ли каждый запрос до `closed`, пуста ли зона, какое
  состояние. Фейки страницы — сервер и токен из зондов. Драйверы мостов
  и таблицы остаются.
- **Вход из ядра.** Строка таблицы README `async_job` «In a bloc app», запись
  «Unreleased» в `packages/async_job/CHANGELOG.md` и фраза в конце «A handler
  that restarts» страницы `riverpod-and-bloc.md`, которая перечисляет разделы
  страницы о bloc, — новым составом. Переводы — тем же коммитом.
- **Страница `solo`.** Её таблица ведёт строкой «Releasing a resource…»
  на раздел ядра, которого не станет; строка ведёт на раздел `vs-bloc.md`,
  а ответ в ней — `try`/`finally` одного bloc, как в таблице ядра. Ссылка
  на «The bridge» остаётся. Остальные правки страницы `solo` — по ревью
  простоты, отдельной работой.
- **`docs/settled.md`.** Новое решение 146: раздел страниц о bloc сравнивает
  ступень с сильнейшим ответом одного bloc, найденным зондом, и называет цену
  ступени; сценарий, где ступень ничего не снимает, стоит в таблице. Без него
  следующее ревью снова примет ответ `vs-bloc.md` за базу. Решение 133 остаётся
  верным как есть.

## Чего не будет

- Сравнения с `solo`: страница ядра закончена без него, `solo` упоминается
  только во вступлении таблицы (раздел «Ставка — ядро» `AGENTS.md`).
- Механики токена, фильтра, `runAll` и срока сверх нужного разделу: она
  разобрана на `riverpod-and-bloc.md`, `cancellation.md`, `groups.md`
  и `time.md`, и разделы ведут туда.
- Настоящего dio в стенде: фейковый токен держит страницу в чистом Dart
  и в одном стенде с остальными фейками; с dio строки те же, и это показывает
  `riverpod-and-bloc.md`. Это моё решение.

## Порядок работ

План — отдельной записью после одобрения дизайна. Порядок такой: драйверы трёх
сценариев в стенде по коду зондов, страница ядра с переводом, таблица, входы
и строка таблицы `solo`, решение 146, полная проверка, ревью готовой работы,
вливание. Правки страницы `solo` по ревью простоты — отдельной работой до или
после, они этой не касаются, кроме одной строки таблицы.

## Код зондов

Общие фейки: сервер `Api.load(name, ms, {token, fail})` печатает `started`,
`answered`, `failed` или `aborted`; `CancelToken` — завершитель с `cancel()`
и `whenCancel`; `watch` — тот же, что на странице. Ниже — версии одного bloc
и задачи каждого сценария, как они прогонялись.

A, один bloc и задача:

```dart
class TokenBloc extends Bloc<Searched, String> {
  TokenBloc() : super('') {
    on<Searched>((e, emit) async {
      _token?.cancel();
      final token = _token = CancelToken();
      try {
        emit(await api.load(e.query, 50, token: token));
      } on Aborted {
        return;
      }
    }, transformer: restartable());
  }

  CancelToken? _token;

  @override
  Future<void> close() {
    _token?.cancel();
    return super.close();
  }
}

class JobBloc extends Bloc<Searched, String> {
  JobBloc() : super('') {
    on<Searched>((e, emit) => emit.forEach(
          watch(Job((ctx) {
            final token = CancelToken();
            ctx.onCancel(token.cancel);
            return ctx.join(() => api.load(e.query, 50, token: token));
          })),
          onData: (rows) => rows,
        ), transformer: restartable());
  }
}
```

B, один bloc и задача:

```dart
class OneTokenBloc extends Bloc<Opened, String> {
  OneTokenBloc() : super('') {
    on<Opened>((e, emit) async {
      _token?.cancel();
      final token = _token = CancelToken();
      try {
        final values = await Future.wait([
          for (final name in parts) part(name, e.round, token: token),
        ], eagerError: true);
        emit(values.join(', '));
      } on Aborted {
        return;
      } catch (error) {
        token.cancel();
        emit('failed: $error');
      }
    }, transformer: restartable());
  }

  CancelToken? _token;

  @override
  Future<void> close() {
    _token?.cancel();
    return super.close();
  }
}

class JobBloc extends Bloc<Opened, String> {
  JobBloc() : super('') {
    on<Opened>((e, emit) => emit.forEach(
          watch(Job((ctx) => ctx.runAll([
                for (final name in parts)
                  Job.deferred((ctx) {
                    final token = CancelToken();
                    ctx.onCancel(token.cancel);
                    return ctx.join(() => part(name, e.round, token: token));
                  }),
              ]))),
          onData: (values) => values.join(', '),
          onError: (error, _) => 'failed: $error',
        ), transformer: restartable());
  }
}
```

C, один bloc и задача:

```dart
class TokenBloc extends Bloc<Exported, String> {
  TokenBloc() : super('') {
    on<Exported>((e, emit) async {
      _token?.cancel();
      final token = _token = CancelToken();
      var timedOut = false;
      final timer = Timer(limit, () {
        timedOut = true;
        token.cancel();
      });
      try {
        emit(await api.load('export ${e.round}', 300, token: token));
      } on Aborted {
        if (timedOut) emit('timed out');
      } finally {
        timer.cancel();
      }
    }, transformer: restartable());
  }

  CancelToken? _token;

  @override
  Future<void> close() {
    _token?.cancel();
    return super.close();
  }
}

class JobBloc extends Bloc<Exported, String> {
  JobBloc() : super('') {
    on<Exported>((e, emit) => emit.forEach(
          watch(Job(timeout: limit, (ctx) {
            final token = CancelToken();
            ctx.onCancel(token.cancel);
            return ctx.join(
                () => api.load('export ${e.round}', 300, token: token));
          })),
          onData: (rows) => rows,
          onError: (error, _) =>
              error is Cancelled ? 'timed out' : 'failed: $error',
        ), transformer: restartable());
  }
}
```

## Ревью дизайна

Ревьюер на Opus читал копию на `d468ec8e` и гонял зонды на копии стенда. Его
текст — ниже, без путей временного стенда; вердикт и итог — в конце каждой
находки.


Коротко: дизайн повторяет ошибку прежней страницы, только на шаг дальше.
Механизм, на котором стоят A, B и C, принадлежит самому bloc: эмиттер отменяет
подписку своего `forEach`. Ядро здесь ни при чём. Любой стрим, у которого
`onCancel` отменяет токен, даёт ту же трассу без задачи. Таких стримов два:
`CancelableOperation(...).asStream()` из `package:async` или хелпер на всё
приложение размером с `watch`. Поля и `close()` при этом нет, и фильтр
`Job.isCancellationError` не нужен. «Сильнейший ответ одного bloc» в дизайне
(токен в поле плюс `close()`) сильнейшим не является.

Стенд: `python3 tool/bloc_snippets.py` в отдельный каталог, в `pubspec.yaml`
добавлен `async: ^2.13.0`, зонды автора скопированы в `bin/probe/`, свои лежат
рядом. Запуск: `dart run --enable-asserts bin/probe/<файл>.dart`. Зонды автора
на этой копии печатают ровно то, что процитировано в дизайне.

Общий хелпер моих зондов (`rv_helper.dart`, 14 непустых строк, как `watch`):

```dart
Stream<T> stoppable<T>(Future<T> Function(CancelToken token) work) {
  final token = CancelToken();
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      work(token).then(controller.add, onError: (Object e, StackTrace s) {
        token.cancel();
        controller.addError(e, s);
      }).whenComplete(controller.close);
    },
    onCancel: token.cancel,
  );
  return controller.stream;
}
```

#### C1. «Сильнейший ответ одного bloc» в A, B и C не сильнейший: bloc сам доносит отмену до стрима

**Где.** Разделы «Что показывает страница» (абзацы 1–2), «Зонды» (A, B, C),
«Вывод».

**В чём дело.** Дизайн утверждает, что «задача несёт эту отмену дальше,
до самой работы: мост `watch` отменяет задачу, когда bloc отменяет подписку».
Но подписку отменяет bloc, и до работы отмену доносит `onCancel` стрима,
а не задача. Страница `riverpod-and-bloc.md` (строки 269–271) говорит это
прямо: «An `Emitter` has no callback for its cancellation, but it cancels the
subscriptions of its `forEach` and `onEach` at once». Значит, один bloc
обходится без поля и без `close()` в каждом из трёх сценариев. Ошибка
`Aborted`, пришедшая в отменённый контроллер, тихо отбрасывается, поэтому
фильтр в `main` не нужен.

**Чем подтверждено.** `rv_a.dart`, тот же `run` из `a_search.dart`, фильтр
не задан:

```dart
on<Searched>((e, emit) {
  final token = CancelToken();
  return emit.forEach(
    CancelableOperation.fromFuture(
      api.load(e.query, 50, token: token),
      onCancel: token.cancel,
    ).asStream(),
    onData: (rows) => rows,
  );
}, transformer: restartable());
// второй вариант: emit.forEach(stoppable((token) => api.load(e.query, 50, token: token)), onData: ...)
```
```text
CancelableOperation, no filter: [server: a started, server: ab started, server: a aborted, server: ab aborted, closed, state ""], the zone []
stoppable, no filter: [server: a started, server: ab started, server: a aborted, server: ab aborted, closed, state ""], the zone []
```
Это трасса `job` из дизайна. У задачи без фильтра:
`the zone [Aborted, Aborted]`.

`rv_b.dart`, B с одним токеном. Суть:
`CancelableOperation.fromFuture(Future.wait([...],
eagerError: true).whenComplete(token.cancel),
onCancel: token.cancel).asStream()`, `onError: 'failed: $error'`:
```text
CancelableOperation, alerts fail: [... server: alerts 1 failed, server: profile 1 aborted, server: feed 1 aborted, state "failed: Bad state: alerts 1"], the zone []
CancelableOperation, restart and close: [... все шесть aborted ..., closed], the zone []
stoppable, alerts fail / restart and close: то же, the zone []
```

`rv_c.dart`, C. Суть:
`api.load(..., token: token).timeout(limit).whenComplete(token.cancel)` внутри
`CancelableOperation`,
`onError: error is TimeoutException ? 'timed out' : ...`. Вариант с хелпером:
`stoppable((token) => api.load(...).timeout(limit))`.
```text
CancelableOperation, past the limit: [server: export 1 started, server: export 1 aborted, state "timed out"], the zone []
CancelableOperation, restart and close: [server: export 1 started, server: export 2 started, server: export 1 aborted, server: export 2 aborted, closed, state ""], the zone []
stoppable: те же две строки
```

Непустые строки класса bloc (тот же подсчёт, что в дизайне):

| | токен в поле (дизайн) | `CancelableOperation` | хелпер | задача |
|---|---|---|---|---|
| A | 19 | 14 | 8 | 12 |
| B | 25 | 17 | 11 | 16 |
| C | 26 | 19 | 11 | 15 |

У хелпера и у задачи по одной обвязке на приложение (14 и 12 строк). В C ответ
одного bloc — та же первая попытка `Future.timeout`, к которой добавлены
`whenComplete(token.cancel)` и стрим.

**Что предложить.** Взять базой каждого раздела стрим, чья отмена останавливает
работу: `CancelableOperation(...).asStream()` с `onCancel`, а если заводить
хелпер, то рядом с `watch` на тех же правах. Затем пересчитать критерий.
По моим зондам A не проходит, B проходит узко, C не проходит (вердикты
в конце). Разделы, где ответ одного bloc — стрим с `onCancel`, уходят в таблицу
«Where bloc keeps its answer», и этот ответ стоит в строке. Опору страницы
искать там, где `CancelableOperation` не помогает. Это то, что README ядра
(строки 108–135) само называет вкладом задачи: проверка на каждом `join`,
уборка там, где ресурс открыт, дети. Кандидаты — в I1.

Вердикт: принята, все зонды прогнаны заново (ниже). Итог: по слову владельца
«да, убираем» страница ядра о bloc снята, а не переделана; факт находки встал
фразой в «A handler that restarts»
`packages/async_job/doc/riverpod-and-bloc.md`, решение 133 `docs/settled.md`
пересмотрено тем же коммитом.

#### I1. Сценарий «несколько ресурсов» отброшен без зонда, хотя его назвали владелец и вердикт I2, и по зонду он сильнее A–C

**Где.** «Зонды», последний абзац («Чего зонды не проверяли и что в состав
не берётся…»).

**В чём дело.** Слово владельца в `2026-11-04-bloc-pages-simplicity-report.md`
прямое: страница строится вокруг того, где задача «останавливает саму работу,
убирает несколько ресурсов, — с новыми зондами». Вердикт I2 там же: «Встанет ли
он, решает дизайн переделки по зонду». Дизайн решил без зонда, на доводе «форма
та же». Но именно здесь у одного bloc нет короткого пути. Ресурсы прервать
нельзя, поэтому `CancelableOperation` ничего не даёт, и это говорит сам README.

**Чем подтверждено.** `rv_e_two.dart`: база и файл экспорта открываются по 10
мс, две страницы читаются по 20 мс, «ab» в 25 мс, `close()` в 50 мс. Один
bloc — вложенные `try`/`finally` и `if (emit.isDone) return;` после открытия
файла и в цикле. Задача:

```dart
watch(Job((ctx) async {
  final db = await ctx.join(() => Res.open('db ${e.query}'),
      dispose: (db) => db.close());
  final file = await ctx.join(() => Res.open('file ${e.query}'),
      dispose: (file) => file.close());
  for (var page = 1; page <= 2; page++) {
    await ctx.join(() async => file.write(await db.read(page)));
  }
  return 'exported ${e.query}';
}))
```
```text
nested try, restart and close: [db a: opened, file a: opened, file a: closed, db a: closed, db ab: opened, file ab: opened, closed, state "", db ab: page 1, file ab: wrote 1, file ab: closed, db ab: closed], the zone []
job, restart and close: [та же трасса], the zone []
nested try, to the end / job, to the end: [... file a: closed, db a: closed, state "exported a"], the zone []
```
Строк: 22 против 17. Задача снимает два `try`/`finally` и проверки
`emit.isDone`. Забытая проверка состояние не меняет: работа просто идёт дальше.
Токена и фильтра здесь нет.

`rv_d_pages.dart`, один ресурс и три чтения:
```text
check: [a: opened, a: page 1, a: closed, ab: opened, closed, state "", ab: page 1, ab: closed]
check forgotten: [a: opened, a: page 1, ab: opened, a: page 2, closed, state "", ab: page 1, a: page 3, a: closed, ab: page 2, ab: page 3, ab: closed]
job: [та же трасса, что у check]
```
Забытая проверка дочитывает всё у обеих загрузок, а состояние то же `""`. Здесь
выигрыш узкий (17 против 18 строк), и этот случай близок к «A handler that
restarts» на `riverpod-and-bloc.md`.

**Что предложить.** Взять E кандидатом главного раздела и прогнать его
сторожами стенда. Сказать, что проверка нужна на каждом `await`, а при
`restartable()` бесплатный флаг bloc — `emit.isDone`, поэтому сравнивать надо
с ним.

Вердикт: принята. Сценарий с несколькими ресурсами и есть место, где задача
сильнее одного bloc. Итог: раздел новой страницы из него не встал, потому что
страницы нет; довод ушёл одним абзацем в «A handler that restarts»
`packages/async_job/doc/riverpod-and-bloc.md`, на примере `readRows`, который
там уже стоит: одна база и три страницы, форма D. Разошлось с предложенным:
ни раздела, ни сторожей стенда — абзац держит прозу, а не новый код.

#### I2. A почти целиком повторяет `riverpod-and-bloc.md`

**Где.** «Состав», п. 3.

**В чём дело.** «A handler that restarts» уже показывает `restartable()`,
`close()` и `watch`, которые останавливают работу. «A request to abort»
показывает токен через `ctx.onCancel` и фильтр в `main`. A складывает эти два
раздела, а вместо механики отсылает к ним же. Вместе с C1 у A не остаётся
ни довода, ни нового материала. Довод дизайна «без A токен пришлось бы
объяснять внутри B» снимается ссылкой из B на «A request to abort», которую
дизайн и так ставит.

**Что предложить.** A — в таблицу, ответ «`CancelableOperation(...).asStream()`
с `onCancel: token.cancel`». Либо одна фраза в «The bridge»: эмиттер отменяет
подписку, и для одного запроса с токеном этого хватает и без задачи.

Вердикт: принята. Итог: A ушёл вместе со страницей; его довод — второй вариант
предложенного — встал фразой в «A handler that restarts»
`riverpod-and-bloc.md`: одному вызову хватает стрима с `onCancel`, со ссылкой
на «A request to abort» за токеном.

#### I3. Фильтр — цена задачи в B и C тоже, а дизайн называет его только в A

**Где.** «Зонды» B и C, «Состав», п. 4–5. В зондах `b_dashboard.dart`,
`b2_one_token.dart` и `c_deadline.dart` фильтр молча задан в `main`.

**Чем подтверждено.** `rv_b.dart` и `rv_c.dart` гоняют задачу автора без
фильтра:
```text
job, no filter, alerts fail: [...], the zone [Aborted, Aborted]
job, no filter, restart and close: [...], the zone [Aborted, Aborted, Aborted, Aborted, Aborted, Aborted]
job, no filter, past the limit: [...], the zone [Aborted]
job, no filter, restart and close (C): [...], the zone [Aborted, Aborted]
```
Ответу одного bloc через стрим фильтр не нужен (выше везде `the zone []`). Это
настройка на всё приложение, и до сих пор она числилась только за задачей.

**Что предложить.** Назвать фильтр в цене каждого раздела с токеном или один
раз в «The bridge» со ссылкой из разделов: читатель приходит с одним сценарием
(M4 ревью простоты). В «What stays with bloc» сказать прямо: у стрима
с `onCancel` фильтра нет.

Вердикт: принята как цена задачи с токеном. Итог: страницы, где её назвать,
нет; на `riverpod-and-bloc.md` фильтр назван в «A request to abort», где задача
с токеном и стоит, а новый абзац задачу с токеном не предлагает.

#### I4. B: `runAll` сообщает о провале только после последней ветки, а ветка без сигнала остановки его задерживает

**Где.** «Зонды» B, «Состав», п. 4 («`ctx.runAll`, который сам отменяет
остальные ветки при первом провале»).

**В чём дело.** В `groups.md`, таблица «When one failure makes the rest
pointless», о `runAll` сказано: «The body wakes: after the last branch ends».
Если у одной части клиент без токена, экран у задачи узнаёт о провале, когда
эта часть доотвечает. Один bloc с `eagerError: true` узнаёт сразу.

**Чем подтверждено.** `rv_b_deaf.dart`: лента идёт без токена, 60 мс;
уведомления падают на 20 мс; `onError` пишет время.
```text
CancelableOperation, a deaf feed: [... alerts 1 failed, profile 1 aborted, feed 1 answered, state "failed at 20ms"], the zone []
job, a deaf feed: [... alerts 1 failed, profile 1 aborted, feed 1 answered, state "failed at 70ms"], the zone []
```

**Что предложить.** Назвать это ценой B одной фразой со ссылкой на `groups.md`.
Либо показать `ctx.abandonable` для ветки без сигнала.

Вердикт: принята. Итог: B не пишется, назвать цену негде. Числа зонда идут
на реальном времени и плавают: в моих трёх прогонах `failed at 20ms` у стрима
и `failed at 90ms` у задачи, в прежнем — 30 и 80; стабилен порядок: задача
узнаёт о провале после ответа ленты без токена.

#### I5. Неверная ссылка на решение 141

**Где.** «Зачем», абзац 2 («без призыва переходить (решение 141
`docs/settled.md`)»), и «Что меняется вокруг» («Решение 141 остаётся верным как
есть»).

**В чём дело.** Решение 141 — «Советы ревью перед 1.0 о документах агента
ждут». Рамку «bloc остаётся, призыва переходить нет» держит решение 133 (строки
1054–1075, с дополнением 2026-11-04 о двух страницах о bloc). Та же ошибка
стоит в вердикте M3 `2026-11-04-bloc-pages-simplicity-report.md`. Номер 146
свободен: последнее решение — 145.

**Что предложить.** Заменить на решение 133 в обоих местах дизайна,
а в вердикте M3 ревью простоты — тем же коммитом.

Вердикт: принята. Итог: номер исправлен на 133 в обоих местах этого дизайна
и в вердикте M3 `2026-11-04-bloc-pages-simplicity-report.md` тем же коммитом.
Решение 146 не заведено: страница снята правкой решения 133.

#### I6. «С dio строки те же» неверно для двух строк, которые читатель скопирует

**Где.** «Состав», п. 3; «Чего не будет», п. 3.

**В чём дело.** Фейк бросает `Aborted`, поэтому на странице встанут
`on Aborted` в ответе одного bloc
и `Job.isCancellationError = (error) => error is Aborted;`. Под dio это
`DioException` с `type == DioExceptionType.cancel`, как в «A request to abort».
Эти строки отличаются. dio-код на `riverpod-and-bloc.md` стендом не собирается:
`DioExceptionType` нет ни в одном `tool/*`. Ещё одно: в стенде
`tool/bloc_snippets.py` уже есть свой `CancelToken` (строка 999, токен SDK
устройства для страницы `solo`) с другой формой: `cancelled` вместо
`isCancelled` и `whenCancel`. Плану надо развести имена.

**Что предложить.** Назвать на странице, какие две строки под dio другие, или
назвать фейковое исключение так, чтобы было видно, что это заглушка. В плане
записать, как фейк новой страницы уживается с `CancelToken` стенда.

Вердикт: принята. Итог: страница не пишется, и спор имён не возникает: драйверы
ядра ушли из `tool/bloc_snippets.py`, `CancelToken` стенда остался один,
страницы `solo`.

#### M1. C: `error is Cancelled` шире, чем срок

**Где.** Код зонда C, `JobBloc`, `onError:`.

**В чём дело.** В `onError:` придёт любой `Cancelled`, который вынесет
`job.value`, в том числе чужой `Cancelled` из тела (`BodyCancelReason`, «A
`Cancelled` that is not the job's» в `cancellation.md`). Точнее —
`error case Cancelled(reason: TimeoutCancelReason())`. У одного bloc
`TimeoutException` такой двусмысленности не даёт.

Вердикт: принята. Итог: C не пишется.

#### M2. Стенд теряет восемь драйверов, а не шесть

**Где.** «Что меняется вокруг», «Стенд».

**В чём дело.** Уходят `core_closing_bloc`, `core_closing_job`,
`core_closing_bloc_failed`, `core_closing_job_failed`, `core_write_bloc`,
`core_write_job`, `core_resource_bloc`, `core_resource_job`
(`tool/bloc_snippets.py`, строки 427–741). Шесть — это число блоков
на странице.

Вердикт: принята, восемь драйверов разделов. Итог: со страницей ушли все
одиннадцать драйверов ядра — эти восемь и три драйвера моста.

#### M3. Перевод страницы `solo` не назван, вопрос C1 ревью простоты не закрыт

**Где.** «Что меняется вокруг», «Страница `solo`»; «Состав».

**В чём дело.**
- Строка таблицы `packages/solo/doc/bloc.md:983` меняется,
  но `docs/ru/solo/bloc.md` в дизайне не упомянут. Фраза «Переводы — тем же
  коммитом» стоит только в пункте о входах ядра.
- Вердикт C1 ревью простоты поручил дизайну решить, нужна ли фраза о том, что
  `abandonable` вызов не прерывает. Дизайн молчит. В новом составе
  `abandonable` нет, так что ответ «не нужна», но его надо записать.

Вердикт: принята. Итог: строка таблицы и ссылка на мост на странице `solo`
поправлены в оригинале и в `docs/ru/solo/bloc.md` тем же коммитом; фраза
об `abandonable` не нужна — раздела, где она стояла бы, нет.

#### M4. Шапка дизайна не ссылается на решение 142

Решение 142 откладывает перестройку страниц до 1.0. Здесь его снимает прямое
слово владельца «Переделать», так что находки нет, но одна фраза об этом
избавит следующее ревью от вопроса.

Вердикт: принята. Итог: не нужна — переделки нет, решению 142 перечить нечему.

### Ответы на вопросы брифа

1. **Сильнейший ли ответ.** Нет, ни в одном сценарии (C1). Сильнее везде ответ
   «`emit.forEach` + стрим с `onCancel`», через `package:async` или через
   хелпер. Проверено зондами `rv_a`, `rv_b`, `rv_c`.
2. **Критерий.** A не проходит. B проходит узко: задача снимает
   `eagerError: true` и `whenComplete(token.cancel)`, а забытый `eagerError`
   даёт `profile 1 answered, feed 1 answered` при том же состоянии (`rv_b`,
   `stoppable, no eagerError`). При этом приходят фильтр и ожидание глухой
   ветки. C не проходит относительно хелпера и проходит узко относительно
   `package:async`: снимается один `whenComplete(token.cancel)`.
3. **Цена.** Не названы фильтр в B и C (I3), ожидание глухой ветки в `runAll`
   (I4) и то, что строки dio другие (I6). Проверены и верны: `onError:` в C
   обязателен; без `Job.deferred` код не соберётся, потому что `runAll`
   принимает `Iterable<ChildJob<T>>`. Тихой поломки здесь нет.
4. **Сценарий сильнее.** Несколько ресурсов без сигнала остановки (I1, E):
   та же трасса, 22 против 17 строк, без токена и без фильтра. Слабее —
   несколько `await` на одном ресурсе (D). Вложенную отмену
   и `ctx.uncancellable` я не зондировал. У одного bloc работа и так
   не прерывается, пока её не прервал токен, поэтому выигрыша `uncancellable` я
   там не жду, но это не проверено.
5. **Согласованность.** «Ставка — ядро» и решение 144 соблюдены: `solo` стоит
   только во вступлении таблицы, `LEADS_UP` в `tool/check_links.py` это
   разрешает. Повтор `riverpod-and-bloc.md` в A (I2). Неверное решение 141
   (I5). Утверждения о соседях верны (см. ниже).
6. **Хватит ли для плана.** Нет. Не решены база сравнения (C1), а значит
   и состав; входит ли E; где страница вводит фильтр; имена фейков. Это решения
   владельца или новой версии дизайна, а не плана.

### Вердикты по сценариям

- **A:** не проходит. `CancelableOperation` даёт ту же трассу в 14 строках
  против 12, без поля, `close()` и фильтра; хелпер — в 8.
- **B:** проходит узко. Снимаются `eagerError: true` и отмена токена при
  провале; приходят фильтр, `runAll`, токен в каждой ветке и задержка провала
  из-за глухой ветки.
- **C:** не проходит. Против хелпера разница 11 строк против 15, плюс фильтр.
  Против `package:async` проходит узко: снимается один
  `whenComplete(token.cancel)`.

### Проверено и верно

- Трассы и подсчёты строк дизайна для A (7, 19, 12), B (13, 25, 16 и 33) и C
  (11, 26, 15) воспроизводятся на этой копии слово в слово.
- `Bloc.close()` в bloc 9.2.1 (`bloc.dart:313–321`) зовёт `emitter.cancel()`,
  а `_Emitter.onEach` кладёт `subscription.cancel` в `_disposables`. Поэтому
  `close()` и `restartable()` доходят до `onCancel` стрима. На это опираются
  и `watch`, и ответ одного bloc.
- `CancelableOperation.asStream()` в `async` 2.13.0
  (`cancelable_operation.dart:116–128`) отменяет операцию при отмене подписки.
- Якоря, на которые ведут разделы, существуют: `riverpod-and-bloc.md` «A
  request to abort», `groups.md` «When one failure makes the rest pointless»,
  `time.md` «A deadline of the job».
- Строка «What else…» в конце «A handler that restarts»
  (`riverpod-and-bloc.md:338–340`) действительно перечисляет старые разделы.
  Строка README `async_job:316` и запись «Unreleased»
  в `packages/async_job/CHANGELOG.md:7–11` тоже на старом составе.
- На раздел ядра «Releasing a resource…» ведёт только
  `packages/solo/doc/bloc.md:983`; одноимённый раздел есть в `vs-bloc.md:1864`.
  Три старых раздела ядра есть в `vs-bloc.md` (474, 1702, 1864), так что строки
  таблицы ядра могут вести туда.
- `docs/ru/async_job/bloc.md` и `docs/ru/solo/bloc.md` существуют,
  и `tool/check_translations.py` их сверяет.

Файлы в копии я не правил. Ключевой код зондов и их вывод приведены выше.
Фоновых процессов я не запускал, все прогоны `dart run` завершились.

## Проверка находок

Все зонды ревьюера прогнаны заново той же командой, и каждая находка
подтвердилась. Зонды идут на реальном времени: порядок строк в трассах
`rv_e_two` и `rv_d_pages` и числа `rv_b_deaf` от прогона к прогону сдвигаются.
Стабильно три вещи. Каждый открытый ресурс закрыт, и в зоне пусто у обеих
версий. Пропущенная проверка `emit.isDone` дочитывает всё. Задача узнаёт
о провале ветки только после того, как ответит ветка без токена.

Один bloc в зонде E, против которого задача снимает два `try`/`finally`
и проверки:

```dart
class NestedBloc extends Bloc<Searched, String> {
  NestedBloc() : super('') {
    on<Searched>((e, emit) async {
      final db = await Res.open('db ${e.query}');
      try {
        if (emit.isDone) return;
        final file = await Res.open('file ${e.query}');
        try {
          for (var page = 1; page <= 2; page++) {
            if (emit.isDone) return;
            await file.write(await db.read(page));
          }
          emit('exported ${e.query}');
        } finally {
          await file.close();
        }
      } finally {
        await db.close();
      }
    }, transformer: restartable());
  }
}
```

Вывод моего прогона, `rv_e_two` и `rv_d_pages`:

```text
nested try, restart and close: [db a: opened, file a: opened, file a: closed, db a: closed, db ab: opened, file ab: opened, closed, state "", db ab: page 1, file ab: wrote 1, file ab: closed, db ab: closed], the zone []
job, restart and close: [db a: opened, db a: closed, db ab: opened, closed, state "", file ab: opened, file ab: closed, db ab: closed], the zone []
check forgotten: [a: opened, a: page 1, ab: opened, a: page 2, closed, state "", ab: page 1, a: page 3, a: closed, ab: page 2, ab: page 3, ab: closed], the zone []
```

## Слово владельца

2026-11-04, по итогам ревью дизайна. На вопрос, что делать со страницей ядра:
«давай определим: нужна тогда страница, или нам не нужно пытаться навязать себя
bloc?». Я ответил, что не нужна: в bloc специфичного не осталось, а где задача
сильнее — в шагах по ресурсам, — bloc ни при чём, и мост с таким примером
у ядра уже есть на `riverpod-and-bloc.md`. Владелец: «да, убираем, делай
по четырём пунктам» — снять страницу со всеми входами, дописать абзац в «A
handler that restarts», поправить решение 133, закрыть этот дизайн с ревью. И:
«про solo надо также решить»; на вопрос о странице `solo` — «Узкая страница»:
мосты с ценой слоя, разделы Restarting, Removing и Finishing, а Ordering,
Closing и Reacting — в таблицу с ответом одного bloc.
