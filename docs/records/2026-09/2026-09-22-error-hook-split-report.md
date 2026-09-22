# Разделение хука ошибки: сделано

> **Состояние на 2026-09-22:** сделано и влито в `main` (`eb94a2a`).
> **Что это:** отчёт о правке по плану `2026-09-22-error-hook-split-plan.md`:
> `Solo.onError` стал чистым оповещением, ответ за ошибку переехал в новый хук
> `Solo.onUnanswered`, маркер `_homeless` ушёл из ядра.
> **Связанные записи:** `2026-09-22-error-hook-split-plan.md` (план),
> `2026-09-20-errors-rakes-report.md` (вычитка страницы, откуда пришёл вопрос).

## Что стало

`Solo.onError` — оповещение с пустым телом. Ему рассказывают о каждой ошибке
контроллера, один раз, и его переопределение не двигает ни одну ошибку никуда.
Маршрут, который он держал раньше, — `Solo.errorHandler`, а без него зона
создания задачи, — живёт теперь в `Solo.onUnanswered`. Его спрашивают только
о тех ошибках, которых не несёт ни один исход.

Из ядра ушло поле `_solo._homeless` вместе с сохранением-восстановлением вокруг
вызова хуков и оговоркой про синхронную реентрантность: место вызова знает,
какая это ошибка, и теперь просто зовёт нужный хук. `_SoloJob.notifyError`
после оповещения зовёт `onUnanswered`, `_SoloJob.handleUnanswered` зовёт только
его — второго оповещения там нет по устройству ядра.

## Карта путей

Снята зондом до правки и повторена после: в поведении по умолчанию
не изменилось ничего. «хук» — `onError` контроллера, «набл.» — `SoloObserver`,
«обр.» — `Solo.errorHandler`, «зона» — зона создания задачи.

| Путь ошибки | хук | набл. | обр. | зона |
| --- | --- | --- | --- | --- |
| провал тела, исход не наблюдали | 1 | 1 | — | да |
| провал тела, `ignore()` | 1 | 1 | — | — |
| бросает `onDispose` | 1 | 1 | да | — |
| бросает колбэк `onCancel` | 1 | 1 | да | — |
| брошенная `wait` падает позже | 1 | 1 | да | — |
| бросает `canStart` | 1 | 1 | — | да |
| бросает `keepWhile` | 1 | 1 | — | — |
| ветка группы, отказавшаяся остановиться | 1 | 1 | да | — |

Первые пять строк — зонд от 2026-09-22 из `2026-09-20-errors-rakes-report.md`,
остальные сняты здесь. Каждую ошибку хук слышит ровно один раз: обещание «one
error is announced once» держится не только для наблюдателя.

## Дыры нет

План открывал зондом 2 подозрение: группа с двумя падающими детьми не доводила
вторую ошибку ни до обработчика, ни до зоны. Причина оказалась в самом зонде.
Когда первая ветка падает, группа останавливает остальные, и вторая
заканчивается `Cancelled(sibling)` — её `Failed` не доживает до разбора группы,
а отвечать за отмену не надо:

```text
outcomes=[a=Failed(Bad state: a) b=Cancelled(sibling)]
```

Настоящий случай строится так, как его строит `extending_test.dart` в ядре:
вторая ветка с `cancellable: false` отказывается остановиться и падает сама.
Тогда её провал и правда доходит до `handleUnanswered`, а оттуда —
до `onUnanswered`. Это и стало сторожем
`a failure a group did not throw is answered for`.

## Миграция

Правка тихая: код компилируется, а ошибки, которые глушило переопределение
`onError` без `super`, снова идут дальше. В пакете это показали восемь красных
тестов в пяти файлах.

| Контроллер | Файл | Что сделано |
| --- | --- | --- |
| `_Controller` | `state_handlers_test.dart` | пустой `onUnanswered`: тест читает `errors` |
| `_Recorder`, `_Watched` | `unattended_test.dart` | то же |
| `Uploader` | `cancellation_rakes_test.dart` | то же |
| `_Quiet` | `zone_test.dart` | молчит нарочно — переехал на `onUnanswered` |
| `Silent` | `errors_rakes_test.dart` | то же: контроллер, отвечающий за свои ошибки сам |
| `Cam` | `errors_rakes_test.dart` | `super.onError` убран, добавлена запись `onUnanswered` |

Вне тестов переопределений `Solo.onError` в дереве не было: ни в примерах,
ни в `flutter_solo`.

## Сторожа

Ушёл сторож на первую попытку раздела `Reporting an error`: ловушки больше нет,
и ошибаться в этом разделе не на чем. Пришли четыре:

- `a hook that reports and returns keeps the route` — обработчика спрашивают,
  хотя хук переопределён;
- `an override of onError alone leaves the route in place` (`zone_test.dart`) —
  то же на пути `unattended`, до самой зоны;
- `an override of onUnanswered answers for the error` — ни обработчика,
  ни зоны;
- `a failure a group did not throw is answered for` — путь `handleUnanswered`.

Плюс два прежних сторожа научились говорить о втором хуке: `Cam` теперь пишет
и `onUnanswered`, так что «провал тела никого не просит отвечать» и «ошибку
уборки просят» проверяются прямо.

## Мутации

Семь, все пойманы.

```text
onUnanswered answers for nothing -> 12 caught
the handler branch is inverted -> 49 caught
a Cancelled is let into the zone -> 5 caught
notifyError does not ask for an answer -> 19 caught
handleUnanswered does not ask for an answer -> 2 caught
the error is announced twice -> 27 caught
the reporting hook answers as well -> 22 caught
```

Последняя — проверка на то, что разделение не половинчатое: если оповещение
снова начнёт отвечать, ответ случится дважды, и это видно.

## Документы

- `packages/solo/doc/errors.md` и `docs/ru/solo/errors.md`: раздел
  `Reporting an error` потерял первую попытку и открывается ответом; ответ
  вынесен в `### Answering for an error`. Обещание вступления — пять разделов
  вместо шести. Поправлены ещё два места, где маршрут назывался старым именем.
- `docs/architecture.md`: пункт про то, кто отвечает за ошибку, и список хуков.
- `packages/flutter_solo/README.md` и `README.ru.md`: абзац про
  `ctx.unattended`.
- `packages/solo/CHANGELOG.md` — запись **Breaking** с миграцией;
  `packages/flutter_solo/CHANGELOG.md` — унаследованная.

## Проверки

| Проверка | Результат |
| --- | --- |
| `solo`: формат, анализ, тесты | чисто, 734 зелёных |
| пример `solo` | чисто, 9 зелёных |
| `flutter_solo`: анализ, тесты | чисто, 83 зелёных |
| пример `flutter_solo` | чисто, 4 зелёных |
| `async_job`: анализ, тесты | чисто, 472 зелёных |
| пять документных проверок | зелёные |
| сайт: `tool/build_site.py` | 42 страницы |
| `jargon.py`, `bare_names.py` | чисто; шесть прежних `Dart`/`future` |

## Что осталось

Имя хука взято из плана: `onUnanswered`. Чтение владельцем `errors.md`
продолжается с того места, где встало, — раздел `Reporting an error` теперь
другой, и читать его надо заново.
