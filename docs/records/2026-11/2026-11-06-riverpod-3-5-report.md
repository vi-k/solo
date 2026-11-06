> **Состояние на 2026-11-06:** сделано коммитом «docs: follow riverpod 3.5 on
> the riverpod pages» по слову владельца «перепиши», находки ревью — коммитом
> «docs: tighten the riverpod 3.5 pages after review»; на pub.dev правка
> придёт со следующими выпусками `async_job` и `solo`.
> **Что это:** riverpod 3.5.0 перестал сообщать наблюдателю о провайдере,
> упавшем после освобождения; две страницы о riverpod переписаны под это,
> стенды требуют 3.5.
> **Связанные записи:** `2026-11-06-async-job-1-0-1-docs-review.md`.

# riverpod 3.5: наблюдатель не слышит освобождённый провайдер

## Что случилось

Push коммита `f48f967d` дал красное задание `snippets`: драйвер
`provider_answer` стенда `tool/adapter_snippets.py` упал на стороже «without
the filter the observer hears Cancelled(manual): []». Сама правка коммита была
прозой и к стенду не относилась. riverpod 3.5.0 вышел 2026-11-06 в 12:45 UTC,
после прошлого зелёного прогона, а стенды требуют `riverpod: ^3.0.0` и берут
свежий. Список изменений 3.5.0:

> `ProviderObserver`s are no longer notified when a provider's future
> completes after the provider was disposed. This stops `providerDidFail` from
> reporting disposal errors, such as when an `autoDispose` provider awaiting
> another provider's `.future` is disposed mid-load (#4706).

Локальный прогон обоих стендов на 3.5.0 уронил два драйвера, каждый раз:
`provider_answer` ядра и `camera_naive` страницы `solo` о riverpod («the late
onDispose reaches the observer: ()»). На 3.4.3 оба проходят. Остальные драйверы
обоих стендов на 3.5.0 зелёные.

## Что утверждали страницы

- `packages/async_job/doc/riverpod-and-bloc.md`, «Cancelling on disposal»:
  `providerDidFail` получает `Cancelled(manual)` освобождённого провайдера,
  и наблюдатель отчётов пропускает его блоком `CrashReports`
  с `if (error is Cancelled) return;`.
- `packages/solo/doc/riverpod.md`, первая попытка «A camera closed when the
  screen goes»: `UnmountedRefException` поздней регистрации `onDispose` видит
  `ProviderObserver`, трасса кончалась строкой
  `observer: UnmountedRefException`.

## Что сделано

Владелец выбрал переписать страницы под 3.5, а не прибивать стенды к 3.4.

- Ядро: блок `CrashReports` снят, абзац говорит, что отмена не доходит
  ни до зоны, ни до `ProviderObserver`, и что до 3.5.0 наблюдатель получал этот
  `Cancelled(manual)`. Фильтр по `Cancelled` на 3.5 вредил бы: `Cancelled`,
  которым задача кончилась сама, по своему сроку, при живом провайдере —
  настоящий сбой, и фильтр прятал бы его.
- `solo`: трасса первой попытки кончается `observer: nothing`, проза говорит,
  что об открытом устройстве не сообщает никто, а до 3.5.0 сообщал
  `providerDidFail`.
- Вступления обеих страниц называют riverpod 3.5, стенды требуют
  `riverpod: ^3.5.0`, `docs/conventions.md` — «не ниже 3.5».
- Драйвер `provider_answer` ставит наблюдателя, который записывает каждый сбой,
  и требует, чтобы после ухода экрана список был пуст; `camera_naive` печатает
  `observer: nothing` и требует того же. На 3.4.3 оба сторожа краснеют: «the
  observer hears nothing of the disposed provider: [Cancelled(manual)]» и «the
  late onDispose reaches no observer: (UnmountedRefException)».
- Переводы и записи в «Unreleased» списков изменений `async_job` и `solo`.

## Проверки

Оба стенда на 3.5.0: анализ без замечаний, все 22 драйвера прошли,
`check_traces.py` — по 10 трасс на страницу, все напечатаны. Переводы, заливка,
ширина, ссылки, форма попыток — чисто; линтер `humanizer--ru` на переводах — 0
ERROR, кроме старой строки 443 перевода списка изменений `solo`, которая была
и до правки.

## Ревью

Независимый ревьюер на Opus прочёл коммит «docs: follow riverpod 3.5 on the
riverpod pages» и прогнал оба стенда на 3.5.0 и на 3.4.3: вливать можно, три
находки Low, все приняты и исправлены коммитом «docs: tighten the riverpod 3.5
pages after review».

R1. Оговорка «before 3.5.0» стояла в прошедшем времени, а для читателя
на riverpod 3.0–3.4 это настоящее. Теперь «On riverpod before 3.5.0 it does
receive this `Cancelled(manual)`», в настоящем.

R2. На странице `solo` «nothing reports the open device; before 3.5.0
`providerDidFail` received the exception» читалось так, будто до 3.5.0
об устройстве сообщали. Дописано «and names no device either».

R3. Абзац ядра о `Cancelled`, которым задача кончилась сама, держался словами
«as well» за снятое утверждение, что наблюдатель слышит отмену освобождения;
«as well» снято. Ревьюер предлагал ещё сказать, что наблюдатель слышит такой
`Cancelled`, когда повторы кончились: его зонд показал это без повторов и после
одного исчерпанного, но при повторах по умолчанию за три секунды отчётов
не было, и механику повторов он не разобрал. Фраза о наблюдателе не добавлена;
в этой записи утверждение «наблюдатель слышит» заменено на «настоящий сбой».
