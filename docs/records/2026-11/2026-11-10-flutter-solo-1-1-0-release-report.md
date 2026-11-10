> **Состояние на 2026-11-10:** подготовлено, не опубликовано: остаток ветки
> `solo-listener` влит в `main` (голова `312a5130`), коммит подготовки
> `0e218671`, полный гейт и пробная публикация на нём чистые. Связка ждёт
> отдельного запроса владельца, состоящего только из просьбы опубликовать.
> **Что это:** подготовка минорного выпуска `flutter_solo` 1.1.0 —
> `SoloListener` и его документация.
> **Связанные записи:** `2026-11-10-solo-1-1-0-release-report.md`,
> `2026-11-10-solo-listener-report.md`, `2026-11-09-solo-listener-plan.md`,
> `2026-11-02-flutter-solo-release-report.md`.

# Выпуск flutter_solo 1.1.0

По слову владельца 2026-11-10 «готовь выпуск flutter_solo 1.1.0». Слово понято
как подготовка: разрешение на связку приходит отдельным запросом, состоящим
только из просьбы опубликовать.

## Что в выпуске

Новый виджет `SoloListener` и перечисление `SoloListenerMode`: реакция экрана,
задача ядра, на каждое изменение контроллера, которое пропускает `listenWhen`,
с пятью режимами на случай, когда прежняя реакция ещё идёт. Поэтому выпуск
минорный. `flutter_solo` теперь требует `solo: ^1.1.0` ради
`Solo.addChangeListener`. Кроме того — документация из «Unreleased»: README
просит `solo_lints: ^0.2.0`, `pubspec.yaml` называет сайт документации.

`solo` 1.1.0 вышел 2026-11-10 (`2026-11-10-solo-1-1-0-release-report.md`)
и держит ядро в `>=1.0.0 <1.1.0`; scopo 1.0.0 на pub.dev держит то же ядро.
Нового ядра выпуск не требует, и ждать scopo не нужно.

## Как остаток ветки вошёл в `main`

Шаг 3 раздела «Как ветка входит в `main`» плана
`2026-11-09-solo-listener-plan.md`. Ветка `solo-listener` перебазирована
на `main` `d59d63a2` — третий раз: после выпуска `solo` 1.1.0 в `main` легла
запись о нём, — затем `main` перемотан до её головы. Конфликтов не было,
содержимое пакетов от прошлого перебазирования не изменилось.

| Было | Стало | Коммит |
| --- | --- | --- |
| `77981709` | `7e7be822` | feat(flutter_solo): add SoloListener |
| `287ead02` | `876eff74` | feat(flutter_solo): cancel SoloListener reactions… |
| `f85c7698` | `6fb33c73` | docs(flutter_solo): add the SoloListener section… |
| `530f10a7` | `554b1667` | docs(flutter_solo): say what a reaction that outlives… |
| `5bf3ae03` | `2e3a980b` | docs: name SoloListener next to BlocListener… |
| `bd8b61a7` | `f29c7d82` | fix(flutter_solo): say where an abandoned load fails… |
| `83824298` | `312a5130` | test(flutter_solo): hold every mode to the next reaction… |

Прежние соответствия — в `2026-11-10-solo-1-1-0-release-report.md`.

## Подготовка

Коммит `0e218671` «chore: prepare flutter_solo 1.1.0»:

- `version: 1.1.0` в `packages/flutter_solo/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «1.1.0», в переводе
  `docs/ru/flutter_solo/CHANGELOG.md` — «Не выпущено» тоже;
  `check_translations.py` — «no differences»;
- удалены `packages/flutter_solo/pubspec_overrides.yaml`
  и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление в индексе
  и в коммите. Оба вели `solo` на дерево, пока 1.1.0 не вышел. Оверрайдов
  в дереве больше нет ни у одного пакета;
- из `docs/backlog.md` удалена запись «`SoloListener` во Flutter»: она
  выполнена.

README версию не называет: таблица версионирования говорит о 1.0.0 как о начале
семантического версионирования.

## Чем проверено

Полный гейт, пять заданий CI, на чистом дереве `0e218671`, статус 0:

- `dart`: формат и `dart analyze --fatal-infos` чистые, `dart doc --dry-run`
  без предупреждений; `async_job` +1905, `solo` +2260, пример `solo` +112,
  `async_job_lints` +203, `solo_lints` +96; оба плагина через сервер анализа;
- `flutter`: `flutter_solo` +337, теперь на `solo` 1.1.0 с pub.dev, его пример
  +6, стенд `flutter_solo` +56, трассы `mixins.md` — 6, 0 не напечатано;
  раскладка архивов — 0 предупреждений;
- `floor` на Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots». В раскладке `flutter_solo` и его примера `solo` 1.1.0 с pub.dev:
  оверрайдов больше нет, и ограничение `solo: ^1.1.0` пол на этот раз
  доказывает;
- `snippets`: шесть пакетов стендов, анализ чистый, все драйверы, трассы шести
  страниц сходятся;
- `docs`: все питоновские проверки, их сторожа и сборка сайта, 96 страниц;
  дерево после прогона не сдвинулось.

`flutter pub publish --dry-run` в `packages/flutter_solo` на том же чистом
дереве — «Publishing flutter_solo 1.1.0», «Package has 0 warnings».

На 2026-11-10: на pub.dev `flutter_solo` 1.0.0, `solo` 1.1.0, scopo 1.0.0; тега
`flutter_solo-v1.1.0` нет ни локально, ни в origin.

## Связка

Не запускалась: слово владельца — подготовка. Связка `flutter_solo` 1.1.0 —
релизный коммит «Release flutter_solo 1.1.0», аннотированный тег
`flutter_solo-v1.1.0`, `git push --follow-tags` и `flutter pub publish`
из чистого дерева `packages/flutter_solo` — идёт по отдельному запросу
владельца, состоящему только из просьбы опубликовать.

## После выпуска

В «Unreleased» `solo` лежит запись задачи 7: dartdoc `SoloCancelReason`
и `ReplacedCancelReason`, `doc/reference.md`, `doc/cancellation.md`
и `doc/vs-bloc.md` называют `SoloListener`. На pub.dev она уйдёт с патчем
`solo` 1.1.1, который разумно выпустить после `flutter_solo` 1.1.0, чтобы имя
вело на опубликованный виджет. Решает владелец.
