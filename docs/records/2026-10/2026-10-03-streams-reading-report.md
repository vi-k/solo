> **Состояние на 2026-10-03:** владелец читает страницу; правки по его
> вопросам идут в `main` по одной.
> **Что это:** вопросы владельца по `packages/async_job/doc/streams.md`
> и что по каждому сделано.
> **Связанные записи:** `2026-10-02-children-reread-report.md` (пункты 32–36:
> те же разделы, пока они жили в `children.md`, и вынос на свою страницу),
> `2026-10-03-job-each-design.md`.

# Чтение streams.md владельцем

Страница вынесена из `children.md` 2026-10-03, пункт 36
в `2026-10-02-children-reread-report.md`. Каждый вопрос правится в самой
странице: оригинал, перевод `docs/ru/async_job/streams.md`, сторож
`packages/async_job/test/streams_rakes_test.dart` и пункт здесь.

1. Владелец 2026-10-03, «The second attempt»: «а если добавить `onError`
   в `listen`?» Зонд: `onError` подписки получает ошибки, которые отправил
   стрим, а бросок колбэка, синхронный или из `async`, мимо него уходит в зону;
   `asFuture` из той же попытки к тому же заменяет `onError` своим. В абзац
   об ошибке колбэка добавлена фраза: `onError` у `listen` этого не меняет.
   Сторож — `the onError of listen hears the stream, not the callback`.
