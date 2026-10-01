> **Состояние на 2026-10-01:** сделано в `main` одним коммитом, не отправлено;
> независимое ревью на Opus — в разделе «Ревью».
> **Что это:** отчёт о том, как тело, которое сдаётся само, стало отменять
> задачу тем же путём, что и отмена снаружи: колбэки `onCancel` вызываются,
> а `whenCancelled` срабатывает в момент броска.
> **Связанные записи:** `2026-09-25-observing-rakes-report.md`,
> `2026-09-09[11]-when-cancelled-report.md`, `2026-09-25-cancellation-rakes-report.md`.

# Самоотмена тела идёт путём отмены снаружи

## Что было

Тело, которое сдаётся само, бросая `Cancelled` или выпуская наружу отмену
дочерней задачи, с 93c7ad3 (2026-09-15) помечало задачу в момент броска
и передавало отмену детям. Но колбэки `ctx.onCancel` не вызывались вовсе,
а слушатели `whenCancelled` слышали отмену только после конца детей, перед
уборкой. Владелец спросил при чтении `observing.md`, почему так, и можно ли это
починить; ответ — пункт 12 в «По чтению владельца»
`2026-09-25-observing-rakes-report.md`.

Записанных причин было три, одна в документации и две в комментарии ядра.
В документации: «nobody asked the job to stop, so no token it gave to
`onCancel` is cancelled». В комментарии: те же колбэки завершают отменой
ожидания, от которых тело ушло, и `unawaited` такое ожидание унесло бы отмену
в зону; а `_notifyCancelled` ждёт детей, «because `solo` pins the order».
Первая не держится: `onCancel` нужен, чтобы остановить начатое, когда оно
больше не нужно, а после самоотмены оно не нужно так же; цену было видно
на самой `extending.md`, где вторая попытка правила кончала задачу `Cancelled`,
а соединение никто не закрывал. Вторая решается одной строкой. Третья неверна
для самоотмены: прототип с уведомлением в момент броска оставил `solo` (822)
и `flutter_solo` (85) зелёными.

Решение владельца 2026-10-01 — «делай» на предложение чинить оба правила одной
правкой.

## Что сделано

Ядро, `packages/async_job/lib/src/job_base.dart`, `_execute`: после пометки
и каскада на детей самоотмена вызывает `_markCancelled`, как `cancelWith`:
в `finally` вокруг каскада, пропуская его, если движок закончил задачу руками
посреди каскада. Ошибка каскада или колбэка, зарегистрированного без защиты,
уходит в `notifyError`: бросить её из `_execute` значило бы оставить задачу
идущей навсегда. Позднее `_notifyCancelled` после ожидания детей убрано:
к этому месту оба пути уже всё объявили, и `assert` о пометке остался.

`packages/async_job/lib/src/job_context.dart`, `_race`: колбэк отмены, если
тело уже кончилось, гасит копию отмены через `completer.future.ignore()`. Так
ведёт себя и ветка ошибки в `forward`. Без этого брошенный телом `ctx.wait` при
самоотмене отдавал бы отмену в зону. Заодно это чинит отмену снаружи, пришедшую
после конца тела: таблица `observing.md` всегда говорила, что `wait` идёт
в зону только до конца тела, а отмена туда шла.

Ветка `fromFork && pendingCancel != null` в `forward` осталась. Тесты её больше
не задевали, и зонд показал, зачем она: движок заканчивает задачу руками
посреди каскада, `finish` сбрасывает колбэки, и работа из `unattended` без
ветки получает `StateError` «has already finished, cannot take the value of a
call it made» вместо отмены — и при самоотмене, и при отмене снаружи.
Комментарий переписан под эту причину, сторож — два теста
`wait, the job ended by hand in the cascade, …` в `late_value_test.dart`.

Комментарий о `solo` в `cancelWith` проверен мутацией: уведомление до каскада
красит в `solo` `cancelling the parent marks children before itself`
и `accepting a cancellation happens inside cancel(),
and the body no longer decides`. Там он верен и остался; ложный был только
в пути самоотмены, и он снят.

Dartdoc: `whenCancelled` и `JobContext.onCancel`.

## Документы

- `observing.md`: оговорка «`whenCancelled` срабатывает только когда кончились
  дети» и пример с миниатюрой, добавленный в тот же день по пункту 11, ушли.
  Абзац о засечке говорит, что `whenCancelled` срабатывает, когда задача
  принимает отмену, и что у сдавшегося тела счёт идёт от броска.
- `extending.md`, раздел «A rule of your own»: вторая попытка теперь сама
  закрывает соединение, и третья, `cancelOwnJob` с `throw pendingCancel`, стала
  лишней. Раздел — первая попытка и ответ «A cancellation of the engine's own»
  с двумя цитатами. Абзац о `cancelOwnJob` ушёл, абзац о `finish` остался
  и называет `cancelWith` и `cancelOwnJob` как способ закончить идущую задачу.
  Из вступления страницы ушла фраза о второй попытке. Тесты правила прогнаны
  с ответом без `cancelOwnJob`: отличие одно — внутри `uncancellable` шаг
  слышит отмену раньше, чем вызываются колбэки.
- `cancellation.md`, `outcomes.md` и `packages/solo/doc/cancellation.md` —
  абзацы о самоотмене и о моменте `whenCancelled`.
- Переводы всех пяти; изменённые абзацы прошли `humanizer-ru`, сканер дал 90
  из 100 без запретов и тире, правок не понадобилось.
- `## Unreleased`: у `async_job` новая ломающая запись и запись в «Fixed»
  о брошенном `wait`, совет миграции у `check` переписан; у `solo`
  и `flutter_solo` — в унаследованных записях.

## Тесты

Прототип красил 8 тестов, и все закрепляли прежнее правило. Они переписаны:
`a body that gives itself up runs its onCancel, after the children`
(cancellation_rakes),
`self cancellation notifies at the throw, as one from outside does`
(when_cancelled), два теста засечки в observing_rakes, тесты правила
в extending_rakes. Ушли: два теста примера с миниатюрой, два теста второй
попытки, `super.check() goes first` с `LateSuperContext` и `CleaningJob`,
`after the job has ended, the rule throws a cancellation of its own` — их
утверждения на странице больше нет — и библиотека
`support/extending_second_attempt.dart`. Новые сторожа: брошенный `wait`
(`a wait left behind, the job's cancellation after the body: nobody`) и ветка
`forward` (два теста выше).

Мутации, откат копией со сверкой хэша:

- без `_markCancelled` в пути самоотмены — 10 красных: cancellation_rakes,
  cleanup `whenCancelled notifies before cleanup starts`, пять
  в extending_rakes, два в observing_rakes, when_cancelled;
- без `.ignore()` в `_race` — 2: новый сторож observing_rakes и cleanup
  `a wait the body walked away from gets no error of its own`;
- без ветки `fromFork` — 2 новых теста `late_value_test.dart`.

Прогоны: `async_job` 929 (с тестами по ревью), `solo` 822, `flutter_solo` 85;
`dart format`, `dart analyze`, питоновские проверки документации и сборка сайта
чистые.

## Ревью

Независимый ревьюер на Opus работал по копии дерева, с зондами и мутациями
в ней. Блокеров не нашёл: порядок совпадает с `cancelWith`, каждый путь
объявляет отмену ровно один раз, `ignore()` только помечает копию отмены
обработанной, а мутации сходятся с перечисленными выше. Находки — ниже, каждая
проверена своим зондом.

1. Брошенная секция `uncancellable` не держит самоотмену. Тело открыло секцию
   без `await` и сдалось: на старом ядре шаг секции доходил до конца, на новом
   колбэки `onCancel` вызываются, пока секция открыта, и `wait` в ней бросает.
   Нигде не было сказано: ни в dartdoc `uncancellable`, ни в абзаце «Always
   await» `cancellation.md`, ни в `CHANGELOG`.

   Вердикт: принято, это поведение верное. Сдавшееся тело приняло отмену само,
   а отмену, от которой задача отказаться не может, секция и так не держит
   (`cancelOwnJob`). Зонд на старом и новом ядре дал `step done`
   и `onCancel, step interrupted`. Итог: дописано в dartdoc `uncancellable`
   («Always await this call»), в абзац «Always await» `cancellation.md`
   с переводом и в ломающую запись `CHANGELOG`; сторож —
   `a section the body walked away from does not hold its give-up`
   в `cleanup_test.dart`, красный без `_markCancelled` в пути самоотмены.

2. Совет о своём правиле разошёлся между файлами. Dartdoc `JobContextBase` всё
   ещё велел `cancelOwnJob` с `throw pendingCancel` и объяснял `StateError` при
   уборке тем, что правило иначе отменило бы задачу, вернувшую значение.
   Ни одна страница не говорила, что теряет правило, которое только бросает:
   задача принимает отмену, лишь когда бросок выходит из тела. Фраза
   `extending.md` «Every cancellation of a job arrives at `cancelWith`»
   называла правило через `cancelOwnJob`, которого на странице больше нет,
   а самоотмена через `cancelWith` не идёт вовсе.

   Вердикт: принято. Итог: dartdoc `JobContextBase` переписан под бросок
   с причиной движка, с оговоркой о пойманной отмене и `cancelOwnJob` для
   отмены вопреки телу. В `extending.md` и переводе: фраза о `cancelWith`
   говорит об отмене, о которой просят задачу, и о том, что самоотмена туда
   не приходит, а задача к тому времени уже вне очереди; абзац о правиле
   получил фразу о теле, которое поймало отмену и пошло дальше. Сторожа —
   `a body that catches the rule and goes on is not cancelled`
   и `a body that gives itself up does not come through cancelWith`
   в `extending_rakes_test.dart`.

3. Комментарий к ветке `fromFork && pendingCancel != null` называл один путь
   туда, а их больше: колбэк, зарегистрированный сырым через
   `addCancelCallback` и бросивший, обрывает проход по колбэкам, и гонка `wait`
   его не слышит.

   Вердикт: принято. Свой зонд с мутацией: с веткой работа из `unattended`
   получает `cancelled`, без неё — `got the value`. Итог: комментарий называет
   оба пути; сторож —
   `wait, a raw callback before it threw, the body gave itself up`
   в `late_value_test.dart`, для него в `ProbeContext` добавлен `onCancelRaw`.
   Без ветки краснеют три теста этого файла.

4. Сырой колбэк, бросивший при самоотмене: задача кончается `Cancelled`, ошибка
   идёт в `onError` и `onUnanswered`, колбэки после него не вызываются,
   а `whenCancelled` срабатывает только в `finish`, после уборки.

   Вердикт: не дефект. Так же ведёт себя `cancelWith`, и dartdoc
   `addCancelCallback` это и обещает. Правок нет.

5. Заголовочный комментарий `extending_rakes_test.dart` залит с огрызком
   строки.

   Вердикт: принято. Итог: комментарий перезалит.

6. В диффе нет `docs/handoff.md` и отчёта в `docs/records/`.

   Вердикт: не подтверждено. Оба в дереве: `docs/handoff.md` изменён, отчёт —
   этот файл, ещё не под гитом и потому вне `git diff`. Идут тем же коммитом.
