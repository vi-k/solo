# Бэклог владельца

Это список владельца. Агент читает записи на старте сессии, предлагает взять их
в работу и удаляет выполненное после себя. Писать сюда агент может, но каждую
запись — только спросив владельца.

<!-- Записи ниже. Одна запись — один пункт списка. -->
- **solo: `SoloObserver.onError` без `JobErrorAnswer`.** Записал агент по слову
  владельца 2026-10-27, из HisBible. С 0.4.0 `JobObserver.onError` получает
  `answer`, а `SoloObserver.onError` нет (`solo.dart:1391`, пункт 109
  `docs/settled.md` оставлял проброс до появления потребителя). Потребитель
  есть: журнал HisBible пишется через `Solo.observer`. Отмену снаружи отличить
  можно
  (`error is Cancelled || (job.isCancelled && Job.isCancellationError(error))`),
  уже обработанную ошибку (`never`) — нельзя. Набросок:
  `{required JobErrorAnswer answer}` у `SoloObserver.onError`, как в ядре.
- **solo: рецепт отложенного старта задания.** Записал агент по слову владельца
  2026-10-27, из HisBible. Повтор решения 56 `docs/settled.md`. Задание
  начинается по сигналу или через время, не держит очередь и снимается при
  `close` и `cancelAll`. Рецепт «Pausing the queue» держит очередь, а таймер
  из «Retrying from the caller» переживает `close`. Обход без нового API:
  ожидание вне очереди, которое снимают `onClose()` контроллера
  и переопределённый `cancelAll` с вызовом `super`. Решение владельца: рецепт
  в документации `solo`, а не `enqueue(..., startAfter:)`.
- **async_job: рецепт задания в изоляте, которое убивает отмена.** Записал
  агент по слову владельца 2026-10-27, из HisBible. `Isolate.run` не отдаёт
  ни изолят, ни порт: отменой его не убить, хода из него не получить. Обход
  в HisBible — 135 строк (`isolate_progress.dart`): `Isolate.spawn` со своим
  портом, `onExit` и `onError`, `kill` в `ctx.onCancel`, `ctx.join` до смерти
  изолята, затем `ctx.check()`, чтобы убитый изолят стал `Cancelled`,
  а не сбоем. Решение владельца: рецепт в `doc/cancellation.md` без хода
  и пересылки стека, а не библиотека `package:async_job/isolate.dart`.
