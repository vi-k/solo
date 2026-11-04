# Переделка страницы «async_job in a bloc app»: дизайн

> **Состояние на 2026-11-04:** дизайн написан по слову владельца «давай, пиши
> дизайн», зонды кандидатов прогнаны; ждёт независимого ревью и одобрения
> владельца.
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
вместе с bloc, без призыва переходить (решение 141 `docs/settled.md`). Меняется
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
Строк: 13, 33, 16. У одного bloc — токен на каждую часть, `eagerError: true`,
отмена всех токенов в `catch`, ветка `on Aborted` перед общим `catch`, поле
списка, `_stop()` в начале обработчика и в `close()`. У задачи — `ctx.runAll`,
который сам отменяет остальные ветки при первом провале, и токен в каждой
ветке; поля и `close()` нет.

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
   Ответ одного bloc — токены, `eagerError`, отмена соседей в `catch`, поле
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
  следующее ревью снова примет ответ `vs-bloc.md` за базу. Решение 141 остаётся
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
class TokenBloc extends Bloc<Opened, String> {
  TokenBloc() : super('') {
    on<Opened>((e, emit) async {
      _stop();
      final tokens = _tokens = [for (final _ in parts) CancelToken()];
      try {
        final values = await Future.wait([
          for (final (i, name) in parts.indexed)
            part(name, e.round, token: tokens[i]),
        ], eagerError: true);
        emit(values.join(', '));
      } on Aborted {
        return;
      } catch (error) {
        for (final token in tokens) {
          token.cancel();
        }
        emit('failed: $error');
      }
    }, transformer: restartable());
  }

  List<CancelToken> _tokens = const [];

  void _stop() {
    for (final token in _tokens) {
      token.cancel();
    }
  }

  @override
  Future<void> close() {
    _stop();
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
