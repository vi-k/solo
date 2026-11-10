> **Состояние на 2026-11-10:** выпущено по слову владельца «публикуй»:
> релизный коммит `4ffc087e`, аннотированный тег `solo-v1.1.0`, `solo` 1.1.0
> на pub.dev. Остаток ветки `solo-listener` после выпуска перебазирован
> на `main`, голова `83824298`; он ждёт выпуска `flutter_solo`.
> **Что это:** подготовка минорного выпуска `solo` 1.1.0 —
> `Solo.addChangeListener` и его документация.
> **Связанные записи:** `2026-11-10-solo-listener-report.md`,
> `2026-11-09-solo-listener-plan.md`,
> `2026-11-06-docs-patches-release-report.md`.

# Выпуск solo 1.1.0

По слову владельца 2026-11-10 «готовь выпуск solo 1.1.0». Слово понято как
подготовка: разрешение на связку приходит отдельным запросом, состоящим только
из просьбы опубликовать.

## Что в выпуске

Новый член API — `Solo.addChangeListener` и `removeChangeListener`: слушатель,
которому каждое изменение приходит парой, прежнее состояние и текущее. Поэтому
выпуск минорный. Кроме него — документация, накопленная в «Unreleased» после
1.0.1: `doc/state.md` об `addChangeListener`, `solo_lints: ^0.2.0` в README,
исход `done` в примере и `doc/mistakes.md`, границы гарантий в `doc/jobs.md`,
`doc/cancellation.md` и `doc/state.md`.

`solo` держит ядро в `>=1.0.0 <1.1.0` и нового ядра не требует: «Unreleased»
ядра — только документация. `flutter_solo` держит `solo` как `^1.0.0` и выпуск
получит сам; `SoloListener`, которому нужен 1.1.0, остаётся в ветке до выпуска
`flutter_solo`. Оверрайдов в дереве нет.

## Как часть `solo` вошла в `main`

По разделу «Как ветка входит в `main`» плана
`2026-11-09-solo-listener-plan.md`: ветка `solo-listener` перебазирована
на `main` `9725998f`, затем `main` перемотан до последнего коммита задачи 2.
Перебазирование сменило хеши всех девяти коммитов ветки, содержимое пакетов
не изменилось: `git diff` старой и новой головы задевает только записи `docs/`,
пришедшие из `main`.

| Было | Стало | Коммит |
| --- | --- | --- |
| `c00f5cbc` | `4f5d4370` | feat(solo): add addChangeListener… — в `main` |
| `9e44a3a0` | `5dacbae3` | docs(solo): describe addChangeListener — в `main` |
| `18ea1068` | `9c539e92` | feat(flutter_solo): add SoloListener |
| `6e8aced1` | `2aaf6885` | feat(flutter_solo): cancel SoloListener reactions… |
| `b524160d` | `9e9e1fb3` | docs(flutter_solo): add the SoloListener section… |
| `2cc24e79` | `cf157b0c` | docs(flutter_solo): say what a reaction that outlives… |
| `59cef380` | `b13b253a` | docs: name SoloListener next to BlocListener… |
| `85c0e59a` | `7b6edee9` | fix(flutter_solo): say where an abandoned load fails… |
| `fb4e6451` | `2bca4c26` | test(flutter_solo): hold every mode to the next reaction… |

Записи о `SoloListener` называют старые хеши; эта таблица — их соответствие.

## Подготовка

Коммит `ef26d17e` «chore: prepare solo 1.1.0»:

- `version: 1.1.0` в `packages/solo/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «1.1.0», в переводе
  `docs/ru/solo/CHANGELOG.md` — «Не выпущено» тоже; `check_translations.py` —
  «no differences».

README версию не называет: установка — `dart pub add solo`, а таблица
версионирования приводит `1.1.0` как пример минорного выпуска.

## Чем проверено

Полный гейт, пять заданий CI, на чистом дереве `ef26d17e`, статус 0:

- `dart`: формат и `dart analyze --fatal-infos` чистые; `async_job` +1905,
  `solo` +2260, пример `solo` +112, `async_job_lints` +203, `solo_lints` +96;
  оба плагина через сервер анализа;
- `flutter`: `flutter_solo` +255 (на опубликованном `solo`), его пример +6,
  стенд `flutter_solo` +51, трассы `mixins.md` — 6, 0 не напечатано; раскладка
  архивов — 0 предупреждений;
- `floor` на Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots»;
- `snippets`: шесть пакетов стендов, анализ чистый, все драйверы, трассы шести
  страниц сходятся;
- `docs`: все питоновские проверки, их сторожа и сборка сайта; дерево после
  прогона не сдвинулось.

`dart pub publish --dry-run` в `packages/solo` на том же чистом дереве —
«Publishing solo 1.1.0», «Package has 0 warnings».

На 2026-11-10: на pub.dev `solo` 1.0.1; тега `solo-v1.1.0` нет ни локально,
ни в origin; `main` впереди `origin/main` на 19 коммитов, считая подготовку,
и не отстаёт — они уйдут в origin вместе с релизным коммитом.

## Связка

По слову владельца 2026-11-10 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Перед связкой: `main` чистый, впереди `origin/main`
на 20 коммитов и не отстаёт, тега `solo-v1.1.0` нет ни локально, ни в origin,
на pub.dev `solo` 1.0.1. Связка — релизный коммит «Release solo 1.1.0» с этой
записью, аннотированный тег `solo-v1.1.0` на нём, `git push --follow-tags`
и `dart pub publish` из чистого дерева `packages/solo`.

Связка прошла подряд: релизный коммит `4ffc087e` «Release solo 1.1.0»,
аннотированный тег `solo-v1.1.0` на нём, `git push --follow-tags` —
`origin/main` с `b541fe82` на `4ffc087e` вместе с тегом, —
и `dart pub publish --force` из чистого дерева `packages/solo`: «Successfully
uploaded https://pub.dev/packages/solo version 1.1.0». API pub.dev отдаёт
версию 1.1.0 с датой публикации 2026-11-10.

## После выпуска

Шаг 2 раздела «Как ветка входит в `main`» плана: перебазировать остаток ветки
`solo-listener` на `main`. Запись задачи 7 в `CHANGELOG.md` `solo` и в переводе
должна лечь в новый «Unreleased», а не под «1.1.0»: проверить глазами
и `check_translations.py`.

Сделано сразу после публикации. Перебазирование прошло без конфликтов,
но запись задачи 7 легла в конец раздела «1.1.0» — и в `CHANGELOG.md`,
и в переводе. Она перенесена в новый раздел «Unreleased» («Не выпущено»
в переводе) с подразделом «Documentation» («Документация») и вклеена в сам
коммит задачи 7, так что ни один коммит ветки не пишет её под «1.1.0».
`check_translations.py` — «no differences», `reflow.py --check`,
`check_line_width.py`, `check_links.py` и сторож сборки сайта чистые;
`dart test` `solo` +2260, `flutter test` `flutter_solo` +337.

| До | После | Коммит |
| --- | --- | --- |
| `9c539e92` | `77981709` | feat(flutter_solo): add SoloListener |
| `2aaf6885` | `287ead02` | feat(flutter_solo): cancel SoloListener reactions… |
| `9e9e1fb3` | `f85c7698` | docs(flutter_solo): add the SoloListener section… |
| `cf157b0c` | `530f10a7` | docs(flutter_solo): say what a reaction that outlives… |
| `b13b253a` | `5bf3ae03` | docs: name SoloListener next to BlocListener… |
| `7b6edee9` | `bd8b61a7` | fix(flutter_solo): say where an abandoned load fails… |
| `2bca4c26` | `83824298` | test(flutter_solo): hold every mode to the next reaction… |
