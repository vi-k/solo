> **Состояние на 2026-09-09:** решение «публиковать как `jobs`» больше не
> исполнимо: pub.dev отклонил загрузку — имя слишком похоже на занятое
> `job`. Письмо держателю отправлено 2026-09-06 владельцем, ответа нет.
> Разбор отказа — в разделе «Отказ pub.dev 2026-09-09» ниже; выбор нового
> имени или освобождение `job` за владельцем.
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

## Отказ pub.dev 2026-09-09

Владелец разрешил публикацию `jobs` 0.1.0, связка прошла до последнего
шага, и `dart pub publish` вернул:

```text
Message from server: Package name `jobs` is too similar to another active
package: `job` (https://pub.dev/packages/job).
```

Проверка `https://pub.dev/api/packages/jobs` отдавала и отдаёт 404 —
свободно. Похожесть имён сервер проверяет **только на самой загрузке**, и
`dart pub publish --dry-run`, сделанный минутой раньше, дал «0 warnings».
То есть ни один способ проверить имя заранее здесь не работает: проба
имени — это и есть публикация под ним, и если имя пройдёт, оно и станет
именем пакета.

Чем занято `job`, по данным pub.dev на 2026-09-09: версия 1.0.0, описание
«Place holder project for job», зависимостей нет, из dev-зависимостей
только `lints` и `test`. Это довод для обращения в `support@pub.dev`:
имя держит пустышка. Отдельно это же означает, что снятие `job` с
активных — discontinued или передача — снимает и запрет на `jobs`: сервер
говорит про «another **active** package».

Список свободных имён выше собран 2026-09-05 тем же способом, который
здесь и оказался недостаточным: 404 говорит только о том, что имя не
занято, но не о том, что сервер его примет. Многословные кандидаты
(`job_engine`, `job_runner`, `job_kit`, `async_job`, `cancellable_job`) на
`job` похожи меньше, чем `jobs`, но проверить это можно только загрузкой.

## Что дальше

- Ждать ответа до 2026-09-26. Молчание — повод переслать тред на
  `support@pub.dev`.
- На публикацию `solo` 0.1.0 запрос не влияет: имя нужно только к первой
  публикации самого ядра, а ядро ещё не написано.
- Любой исход безопасен. Пакет остаётся `jobs`; переезд на `job`
  бесплатен, пока ядро не опубликовано, и становится ломающим после.
