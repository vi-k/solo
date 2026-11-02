> **Состояние на 2026-11-02:** собрано. Владелец выбрал рамку «что
> `async_job` и `solo` добавляют к riverpod»; страница спроектирована
> в `2026-11-02-riverpod-page-design.md` и написана:
> `packages/solo/doc/riverpod.md`.
> **Что это:** жалобы, известные дефекты и ловушки riverpod 3 по заявкам
> GitHub, документации, changelog и обсуждениям, сгруппированные по темам.
> **Связанные записи:** `2026-10-30-pub-dev-landscape-review.md`,
> `2026-10-30-riverpod-and-bloc-design.md`, `2026-10-30-prospects-review.md`.

# Проблемные места riverpod

Задание владельца 2026-11-02: найти проблемные места riverpod — жалобы,
известные дефекты, ловушки — и потом посмотреть, что на них могут ответить
`solo` и `async_job`. Это материал для страницы сравнения `solo` с riverpod
(остаток Opus F2 из `2026-10-30-pub-dev-landscape-review.md`). Решение 133
`docs/settled.md` задаёт тон: `solo` не подаётся как замена riverpod.

Версия — riverpod 3.4.3 (2026-09-03). Номера, состояние, реакции «+1»
и комментарии заявок сняты `gh api` 2026-11-02 своей командой; ответы
мейнтейнера — оттуда же. Строки changelog и исходников —
из `~/.pub-cache/hosted/pub.dev/riverpod-3.4.3/`.

Оговорка о весе. Заявки — не опрос: много закрыто как «ожидаемое поведение»,
часть исправлена. Ниже это помечено у каждой. Обсуждения на Reddit найдены
через зеркала поиска, их немного, и в цифры они не идут.

## 1. Отмена, асинхронный разрыв и запись после удаления

Это ядро темы: здесь работает `async_job`.

**`Ref` после `await` бросает.** В 3.0 провайдер удаляется или перестраивается,
пока тело ждёт, и любое обращение к `ref` или `state` после `await` бросает
`UnmountedRefException`: «Cannot use the Ref of … after it has been disposed …
You should therefore either use `ref.onDispose` to cancel pending work, or
check `ref.mounted` after async gaps» (текст
из [#4096](https://github.com/rrousselGit/riverpod/issues/4096), закрыта, 35
комментариев). Мейнтейнер: «That's the expected behaviour. You're supposed to
check for disposal after async gaps».
В [#4325](https://github.com/rrousselGit/riverpod/issues/4325) (закрыта)
`FutureProvider` с `await` и `ref.read` после него падает; автор: «If
intentional it is a huge gotcha that I believe will bite a lot of folks».
Ответ: «Not a bug … Generally the best solution is to have the future you're
awaiting throw when the provider gets disposed. This naturally will happen if
you cancel the network request on dispose» — и пример с `CancelToken` dio.
[#4336](https://github.com/rrousselGit/riverpod/issues/4336) (закрыта, +24):
в гайде миграции на 3.0 об этой перемене не сказали.

Итог группы: отмена в riverpod — забота пользователя. Ожидание само
не прерывается; его прерывают закрытием клиента в `onDispose` или проверкой
`ref.mounted` после каждого `await`.

**`ref.mounted` сам был ненадёжен.** Changelog 3.2.0 (2026-01-17): «Fixed
`ref.mounted` returning `true` for stale refs after provider rebuild, causing
race conditions in async providers». И после правки он не отвечает на вопрос
«моё ли ещё состояние»: после `ref.invalidate` нотифайер тот же, и `mounted`
снова `true`. `packages/async_job/doc/riverpod-and-bloc.md`, раздел «A notifier
that starts again», поэтому сверяет поле с текущей задачей, а не `mounted`.

**Шаблон ради `mounted`.**
[#1926](https://github.com/rrousselGit/riverpod/issues/1926) (2022, закрыта;
в 3.0 есть `ref.mounted`) — четыре строки в каждом `AsyncNotifier`, чтобы
не писать состояние после удаления.

**Устаревший ответ побеждает в методе нотифайера.** Зонд
А `2026-10-30-pub-dev-landscape-review.md`: `AsyncNotifier.search(q)`
с `state = AsyncData(await api(q))` без проверки оставляет ответ на старый
запрос (`[a-1, a-2]`). Провайдер на запрос (`FutureProvider` смотрит провайдер
запроса) решает задачу правильно, но шлёт лишний вызов API на пустой запрос.

**Запись состояния после удаления.**
[#2506](https://github.com/rrousselGit/riverpod/issues/2506) (2023, закрыта):
`state = AsyncLoading()`, `await`, `state = AsyncData(0)` у автоудаляемого
нотифайера без слушателя падали «Bad state: Future already completed».
Мейнтейнер: «Your provider got disposed, so it shouldn't be calling `state=`
anymore … You should handle the fact that the provider was canceled within the
operation and act accordingly»; теперь `state=` на удалённом нотифайере
бросает.

**Рецепт debounce — бросок после удаления.** Официальная страница
[how_to/cancel](https://riverpod.dev/docs/how_to/cancel): флаг в `onDispose`,
задержка 500 мс, `throw Exception('Cancelled')`; «It is safe to throw inside
providers after the provider has been disposed», «To abort requests, a common
practice is to voluntarily throw». Отмена без debounce, признаёт страница, всё
равно шлёт запросы: «We are still sending multiple requests». Вокруг рецепта
три заявки:

- [#4760](https://github.com/rrousselGit/riverpod/issues/4760) (2026-05,
  открыта): `ProviderObserver.providerDidFail` получает это исключение, хотя
  документация называет бросок безопасным. Мейнтейнер: «We probably want to add
  some form of `CancelException` that's not reported as an uncaught error».
  Отдельного типа отмены в riverpod пока нет.
- [#3651](https://github.com/rrousselGit/riverpod/issues/3651) (2024, открыта):
  пример debounce зависает, если уйти со страницы, пока идёт задержка, —
  страница больше не открывается.
- [#2144](https://github.com/rrousselGit/riverpod/issues/2144) (2023, закрыта):
  пример pub с общим `cancelToken` бросает «cancelled» при быстром наборе,
  а при медленном не отменяет ничего.

**Удалён без значения — `StateError` по строке.**
[#4168](https://github.com/rrousselGit/riverpod/issues/4168) (открыта):
провайдер, удалённый в загрузке, бросает общий `StateError` «missing last
value». Чтобы не слать его в отчёты о падениях, его ловят сравнением текста
сообщения: «which is not solid because we have to do string matching».

**Ресурс, захваченный до `onDispose`, течёт молча.** Зонд Б
`2026-10-30-pub-dev-landscape-review.md`: `FutureProvider.autoDispose`, где
`ref.onDispose(close)` стоит после `await openCamera()`, при уходе во время
открытия оставляет камеру открытой (`alive={1}`), и в зону ничего не приходит.
Регистрация уборки и захват разнесены, и порядок держит пользователь.

**Мутации не ограничивают параллельные вызовы.** Исходник
`lib/src/core/mutations.dart:282`: «Currently, mutations do not restrict
concurrent calls in any capacity». Вторую отправку формы riverpod сам
не остановит. [#4772](https://github.com/rrousselGit/riverpod/issues/4772):
`Mutation.reset()` не отменял идущий `run`, и тот писал результат поверх
сброса; исправлено в 3.3.2 (2026-06-10). Там же исправлен `StateError`
«subscription was closed» у `Mutation.run`, если контейнер удалили во время
работы.

## 2. Жизненный цикл и автоудаление

- [#3354](https://github.com/rrousselGit/riverpod/issues/3354) (закрыта, +82):
  «Cannot use ref functions after the dependency of a provider changed but
  before the provider rebuilt, when chaining providers» — та же ошибка `Ref`,
  но без `await`.
- [#4271](https://github.com/rrousselGit/riverpod/issues/4271) (открыта): после
  асинхронного разрыва `FutureProvider` ставит автоудаляемую зависимость
  на паузу, как обещает «What's new» 3.0, а `AsyncNotifierProvider` её удаляет.
  Changelog 3.3.2: «Fix `AsyncNotifierProvider`/ `StreamNotifierProvider`
  disposing dependencies watched after an asynchronous gap during rebuild»;
  заявка при этом открыта.
- [#4358](https://github.com/rrousselGit/riverpod/issues/4358) (открыта):
  провайдер с `keepAlive` и таймером не удаляется при уходе с экрана, а при
  возврате удаляется.
- [#3522](https://github.com/rrousselGit/riverpod/issues/3522) (2024, закрыта):
  `ref.watch` после `await` в уже брошенном провайдере добавляет слушателя,
  которого никто не снимет, — утечка.
- [#2576](https://github.com/rrousselGit/riverpod/issues/2576) (закрыта, +93):
  разные типы у автоудаляемых и обычных провайдеров; в 3.0 их свели.
- 3.0 по умолчанию ставит на паузу провайдеры вне экрана и повторяет упавшие
  провайдеры (гайд [3.0_migration](https://riverpod.dev/docs/3.0_migration)).
  Для отмены второе важно: `Cancelled`, которым задача кончается сама, riverpod
  считает ошибкой и повторяет; это уже сказано в `riverpod-and-bloc.md`.
  Changelog 3.2.1: «resuming a paused provider could cause it to never notify
  its listener ever again» — исправлено.

## 3. Планировщик и кадр Flutter

- [#4808](https://github.com/rrousselGit/riverpod/issues/4808) (2026-07,
  открыта): исключение внутри `ProviderScheduler._performRefresh` навсегда
  клинит планировщик: «a permanent, app-wide freeze of provider updates».
- [#4812](https://github.com/rrousselGit/riverpod/issues/4812) (закрыта): то же
  через «setState() or markNeedsBuild() called during build» при повторной
  подписке на устаревший граф `keepAlive`.
- [#4285](https://github.com/rrousselGit/riverpod/issues/4285) (закрыта, +13):
  `ref.watch` на мутацию в виджете даёт ту же ошибку `markNeedsBuild`.
- [#3889](https://github.com/rrousselGit/riverpod/issues/3889) (закрыта, 41
  комментарий): `ref.watch` возвращает не то, что `ref.read`.

К `solo` эта группа отношения не имеет: это устройство графа и его связь
с кадром.

## 4. `AsyncValue`

- [#67](https://github.com/rrousselGit/riverpod/issues/67) (с 2020, открыта, 80
  комментариев): нет способа слить несколько `AsyncValue`.
- [#4172](https://github.com/rrousselGit/riverpod/issues/4172) (открыта, +38):
  переделать `AsyncValue` под сопоставление с образцом.
- [#4145](https://github.com/rrousselGit/riverpod/issues/4145) (открыта):
  просят, чтобы `AsyncError` очищал прежние данные: сейчас они остаются рядом
  с ошибкой.
- [#4009](https://github.com/rrousselGit/riverpod/issues/4009) (закрыта, +28,
  73 комментария): лишний промежуток `isLoading` при сочетании провайдеров.
- В 3.0 `AsyncValue.value` возвращает `null` при ошибке, `valueOrNull` убран
  (гайд миграции). Шаблон с проверкой `value` на `null` не совпадает, когда
  настоящее значение — `null` (статья DCM, правило
  `avoid-nullable-async-value-pattern`).

`solo` здесь отвечает исходом вызова (`Done`, `Failed`, `Cancelled`)
и состоянием, которое тип выбирает сам, но это не ответ на слияние и показ
данных, а другая модель.

## 5. Синтаксис, кодогенерация и смена API

- [#4008](https://github.com/rrousselGit/riverpod/issues/4008) (2025-03,
  открыта, +153, 202 комментария): RFC единого синтаксиса провайдеров без
  кодогенерации. [#4752](https://github.com/rrousselGit/riverpod/issues/4752)
  (2026-04, открыта, +48, 148 комментариев): ещё один вариант. Мейнтейнер
  в #4096: «there are active discussions about straight up removing Notifiers
  for a more general approach (cf the pinned issues)».
- Changelog 3.2.0 обещает в 4.0 переименование `overrideWith2`
  в `overrideWith`. В 3.0 `StateProvider` и `StateNotifierProvider` ушли
  в `legacy.dart`, `ProviderObserver` получил один объект контекста вместо
  параметров.
- Кодогенерация: на Reddit (r/FlutterDev, 2024–2026) жалуются
  на сгенерированные файлы, которые трудно читать, и на переход к определению,
  который ведёт в `.g.dart`; один комментатор переписывает провайдеры обратно
  руками. Защитники отвечают, что генерация ловит ошибки. Ветка «Am I doing
  something wrong or Riverpod sucks?» (2025-03): теряется состояние, ответ —
  ранние опыты с `autoDispose`.

## 6. Кеш и данные

- [#1664](https://github.com/rrousselGit/riverpod/issues/1664) (с 2022,
  открыта): `cacheTime` и `staleTime`.
- [#3781](https://github.com/rrousselGit/riverpod/issues/3781) (открыта, 46
  комментариев): синхронизация провайдеров одной сущности.
- [#1032](https://github.com/rrousselGit/riverpod/issues/1032) (закрыта,
  +139) — офлайн-хранение
  и [#1660](https://github.com/rrousselGit/riverpod/issues/1660) (закрыта,
  +46) — мутации: в 3.x вышли как экспериментальные
  `package:riverpod/experimental/persist.dart` и `mutation.dart`.

Это сильная сторона и территория riverpod; `solo` туда не идёт.

## 7. Кривая обучения

Статья DCM
([Inside Riverpod source code](https://dcm.dev/blog/2026/03/25/inside-riverpod-source-code-guide-dcm-rules/),
2026-03) насчитывает 13 ловушек и под каждую правило линта: `ref.read`
в `build`, `ref.watch` вне `build`, `ref`/`state` после асинхронного разрыва
в нотифайере и `ref.read` после разрыва в виджете, логика в конструкторе
нотифайера, публичные поля нотифайера, нотифайер в переменной («This reference
can become stale!»), `ref` в `dispose`, не освобождённые экземпляры («Memory
leak! dispose() is never called»), шаблон `AsyncValue` с `null`, аргументы
семейства без равенства, вызовы нотифайера в `build`, лишний `ConsumerWidget`.
Пять из тринадцати — про время жизни и асинхронный разрыв.

## Предварительно: где говорят `solo` и `async_job`

Это моя первая раскладка для разговора с владельцем, не решение.

Отвечают по существу только на группу 1, и `riverpod-and-bloc.md` ядра уже
показывает, как задача встаёт под провайдер и нотифайер:

- отмена доходит до ожидания (`abandonable`, клиентский токен в `onCancel`),
  а не держится на броске после удаления и флаге;
- отмена — свой тип `Cancelled`, а не строка в `StateError` (#4168)
  и не исключение без типа в наблюдателе (#4760):
  `if (error is Cancelled) return`;
- уборка записана в месте захвата (`join(..., dispose:)`), а не отдельной
  регистрацией, порядок которой держит пользователь (зонд Б);
- `solo`: очередь с политикой (`restart`, `drop`) против параллельных мутаций
  (`mutations.dart:282`) и исход у каждого вызова;
- `solo`: `emit` отменённой задачи не доходит до состояния, поэтому устаревший
  ответ не побеждает (зонд А) и проверка `mounted` после каждого `await`
  не нужна (#1926, #4096).

Группы 2–7 — граф, кадр, `AsyncValue`, синтаксис, кеш — вне `solo`
и `async_job`. Обещать там что-то значит спорить с решением 133.

## Источники

- Заявки — по ссылкам выше, `gh api repos/rrousselGit/riverpod/issues/<N>`
  и `…/comments`, 2026-11-02.
- [riverpod.dev/docs/how_to/cancel](https://riverpod.dev/docs/how_to/cancel),
  [riverpod.dev/docs/3.0_migration](https://riverpod.dev/docs/3.0_migration).
- `riverpod-3.4.3/CHANGELOG.md`, `lib/src/core/mutations.dart`,
  `lib/experimental/`.
- [Статья DCM, 2026-03-25](https://dcm.dev/blog/2026/03/25/inside-riverpod-source-code-guide-dcm-rules/).
- Reddit r/FlutterDev через зеркала:
  [codegen, 2024-12](https://reddit.birdcat.cafe/r/FlutterDev/comments/1hbs90i/riverpod_the_best_tool_for_resumedriven/m1j8hwb/?context=3),
  [codegen, 2026-04](https://reddit.sentinel-team.org/posts/1sw3d2i/snapshots/2026-04-29T00%3A44%3A38.739645Z),
  [«Am I doing something wrong or Riverpod sucks?», 2025-03](https://redlib.hbubli.cc/r/FlutterDev/comments/1j37ln7/am_i_doing_something_wrong_or_riverpod_sucks).
- Сторонние блоги о `ref.mounted` (startdebugging.net) приписывали правку
  «stale refs» версии 3.4.0; по changelog она в 3.2.0. Им здесь не верю.
