> **Состояние на 2026-11-19:** перепись сделана, дизайн второй фазы
> не начат и ждёт слова владельца.
> **Что это:** какие сценарии `vs-bloc.md` уже показывают страницы riverpod
> ядра и `solo`, а каких на нотифаере нет.
> **Связанные записи:** `2026-11-03-bloc-pages-design.md` (раздел «riverpod»
> предлагает вторую фазу), `2026-11-12-solo-project-review.md`.

# Вторая фаза страниц о bloc: перепись сценариев на riverpod

Дизайн `2026-11-03-bloc-pages-design.md` предложил второй фазой сценарии
`vs-bloc.md` на нотифаере riverpod, по странице у ядра и у `solo`, и велел
начать дизайн с того, что уже закрывают `riverpod-and-bloc.md` и `riverpod.md`.
Это та перепись. Сверка — по тексту страниц на `89597954`; зондов не было:
переносится ли ловушка на нотифаер, решает дизайн своими прогонами.

Страницы riverpod сейчас: у ядра `riverpod-and-bloc.md` — «A provider that is
gone», «A notifier that starts again», «A handler that restarts» (bloc), «A
request to abort»; у `solo` `riverpod.md` — «A controller under a provider», «A
camera closed when the screen goes», «A form sent once», «A price riverpod
reads and a controller saves», «What you take on».

## Шесть сценариев из списка дизайна

| Сценарий `vs-bloc.md` | Что уже есть | Чего нет |
|---|---|---|
| Ordering updates to shared state | `riverpod.md`, «A price…»: две записи одной цены доходят до сервера по порядку | загрузка и обновление списка, которые перемежаются на нотифаере, — ответ обновления затирает новую заметку |
| Closing and cancelling in-flight work | ядро: «A provider that is gone», уборка в «A notifier that starts again»; `solo`: «A camera closed when the screen goes» | по сути закрыт; работа вслед за ответом после закрытия (отметка «прочитано») отдельно не показана |
| Leaving a loading state when the work is cancelled | ядро, «A notifier that starts again»: отменённый поиск не пишет поверх нового, `Cancelled` ложится в `AsyncError` | отмена без замены — метод «отменить», после которого индикатор должен вернуться в покой |
| Awaiting a particular request | `riverpod.md`, «A form sent once»: второй вызов того же ключа получает ту же задачу и тот же ответ | разные заказы по очереди, когда каждый вызывающий ждёт ответ своего |
| Finishing an in-flight write before restarting | нет | целиком: замена загрузки ждёт текущую запись чанка |
| Releasing a resource returned after cancellation | ядро: `dispose:` в «A provider that is gone»; `solo`: `discard:` в «A controller under a provider» | по сути закрыт; перекрывающиеся декодирования без очереди не показаны |

## Вне списка дизайна

Дизайн не взял их, потому что у нотифаера нет очереди и трансформеров. Перепись
их не переоценивала, только отмечает, что на страницах riverpod их нет:

- Restarting one operation within a shared queue — `play`, `pause` и `seek`
  на нотифаере идут без очереди вовсе;
- Removing selected pending work — снимать из очереди нечего;
- Reacting to an independent external state change — на riverpod это
  `ref.listen` или `ref.watch` на провайдер сессии;
- Typed methods with queued execution — у нотифаера методы и так свои;
- An observer fails during a state update — у riverpod свой `ProviderObserver`.

## Итог

Из шести сценариев два уже закрыты, три закрыты частично, один нет совсем.
Новое — первые попытки на нотифаере для порядка обновлений, отмены без замены,
разных заказов по очереди и записи перед перезапуском. Это меньше, чем две
новые страницы: вопрос дизайна — новые страницы или разделы в двух
существующих.
