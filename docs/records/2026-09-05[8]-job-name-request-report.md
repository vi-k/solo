> **Состояние на 2026-09-06:** письмо отправлено владельцем, ответа нет.
> Ждать его решено не дальше публикации: 2026-09-06 владелец решил
> публиковать ядро как `jobs`, потому что без опубликованного ядра не
> выложить ни `solo`, ни `scopo`. Если `job` освободится позже — тот же
> код выходит как `job` 0.1.0, а `jobs` помечается discontinued с
> указанием замены.
> **Что это:** проверка имён на pub.dev для выносимого ядра и запрос
> держателю занятого имени `job` о передаче.
> **Связанные записи:** `2026-09-05[4]-jobs-design.md`,
> `2026-09-03[3]-stream-future-report.md`.

# Имя для пакета ядра и запрос на передачу `job`

Ядру, которое выносится из `solo` (`2026-09-05[4]-jobs-design.md`), нужно
имя на pub.dev. Естественное — `job`: пакет экспортирует `Job<T>`. Оно
занято.

## Чем занято `job`

Проверено 2026-09-05 через API pub.dev и архив пакета:

- паблишер `efa.dev`, контакт `info@efa.dev`, сайт `https://efa.dev/` —
  Flutter-разработчик Haşim. Паблишер живой: второй его пакет
  `app_strings` обновлялся 2026-03-22;
- у `job` единственная версия 1.0.0 от 2024-01-24, зависимостей нет,
  `description: "Place holder project for job"`;
- в архиве лежит нетронутый шаблон `dart create --template=package`:
  `class Awesome { bool get isAwesome => true; }`, в README — «Placeholder
  for now»;
- 0 лайков, 5 загрузок за 30 дней.

Это ровно то, что политика pub.dev называет name squatting: пакет
опубликован только чтобы зарезервировать имя, и его код «не имеет
объективно и по-настоящему полезного назначения»
(`https://pub.dev/policy#name-squatting`).

## Что свободно

Проверка одного имени:
`curl -s -o /dev/null -w "%{http_code}" https://pub.dev/api/packages/<имя>`,
404 — имя свободно. На 2026-09-05:

- свободны `jobs`, `job_core`, `job_engine`, `job_runner`, `job_kit`,
  `jobkit`, `async_job`, `cancellable_job`, `solo_core`, `solo_job`,
  `gig`, `stint`, `errand`, `deed`, `toil`, `opus`, `etude`, `coda`,
  `baton`, `mission`, `quest`, `venture`, `strand`, `spool`, `graft`, а
  также сами `solo` и `flutter_solo`;
- заняты `job`, `task`, `tasks`, `chore`, `duty`, `worker`, `runner`,
  `agenda`, `tempo`, `encore`, `maestro`, `ensemble`, `sprint`, `fiber`,
  `shift`, `endeavor`, `outcome`.

Рабочим взято `jobs`: главный тип остаётся `Job<T>`, переименований в
`solo`, в его документах и в записях не требуется, а в поиске по «job»
пакет встаёт рядом с пустышкой без содержимого.

Рассмотрены и отклонены:

- `gig` — короткое, как `solo`, и из того же музыкального ряда, но цена
  либо расхождение имени пакета с главным типом, либо переименование
  `Job` во всём API `solo` и во всех документах;
- `job_core` — суффикс `_core` намекает на фасадный пакет `job`, которого
  у владельца нет и не будет;
- `solo_core`, `solo_job` — называют самостоятельное ядро именем его
  первого потребителя, хотя ядро задумано отдельным (замена
  `stream_future`).

## Запрос на передачу

Процедура из политики: письмо держателю с копией на `support@pub.dev` с
просьбой либо объяснить назначение пакета, либо передать имя; в письме
называются пакет и аккаунт просителя на pub.dev. Если держатель молчит три
недели, тред пересылается на `support@pub.dev`, и дальше решает модератор.

Отправлено 2026-09-05 на `info@efa.dev`, копия `support@pub.dev`. Текст:

```
Subject: pub.dev package `job` — still in use, or open to a transfer?

Hi Haşim,

I'm writing about the `job` package published under your efa.dev publisher
on pub.dev: https://pub.dev/packages/job

From the outside it looks like a reserved name rather than a released
library: a single version 1.0.0 from January 2024, described as "Place
holder project for job", and the archive still contains the untouched
`dart create` template — `class Awesome`, "Placeholder for now" in the
README.

I'm preparing an open-source Dart package for which `job` is the exact
word: the execution core of solo (https://github.com/vi-k/solo), a
`Job<T>` handle over a unit of async work, with cooperative cancellation,
child jobs and explicit outcomes — done, failed, or cancelled with a
reason.

So my question is simply this: do you still plan to build something under
that name? If you do, that is completely fine — I'll pick another name and
won't bother you again. If you don't, would you be willing to transfer the
package to me? My pub.dev account is victor.dunaev@gmail.com.

I've copied pub.dev support, as the naming policy suggests
(https://pub.dev/policy#name-squatting); they can advise on the mechanics
of a transfer.

Thank you for your time.

Best regards,
Victor Dunaev
https://github.com/vi-k
```

## Что дальше

- Ждать ответа до 2026-09-26. Молчание — повод переслать тред на
  `support@pub.dev`.
- На публикацию `solo` 0.1.0 запрос не влияет: имя нужно только к первой
  публикации самого ядра, а ядро ещё не написано.
- Любой исход безопасен. Пакет остаётся `jobs`; переезд на `job`
  бесплатен, пока ядро не опубликовано, и становится ломающим после.
