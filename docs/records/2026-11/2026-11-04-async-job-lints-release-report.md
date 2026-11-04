> **Состояние на 2026-11-04:** `async_job_lints` 0.1.0 опубликован на pub.dev
> под издателем `yet-another.dev`; релизный коммит `d74c0bf2` и аннотированный
> тег отправлены в origin.
> **Что это:** первый выпуск `async_job_lints` 0.1.0 — пять правил ядра,
> вынесенных из `solo_lints`.
> **Связанные записи:** `2026-11-03-lints-split-report.md`,
> `2026-11-03-lints-split-design.md`,
> `2026-11-01-solo-lints-release-report.md`.

# Выпуск async_job_lints 0.1.0

По слову владельца 2026-11-04 «опубликуй async_job_lints 0.1.0» — отдельный
запрос, состоящий только из просьбы опубликовать. Первый шаг порядка выпусков
из `docs/handoff.md`: за ним `solo_lints` 0.1.5 без оверрайда, патч `async_job`
и зонд по версии, каждый — отдельной связкой.

## Подготовка

Отдельного коммита подготовки нет: пакет собран под выпуск ещё разделом линтов,
`2026-11-03-lints-split-report.md`. В дереве `version: 0.1.0`, раздел
`## 0.1.0` в `packages/async_job_lints/CHANGELOG.md` и переводе, README
и перевод просят `async_job_lints: ^0.1.0` — сторож
`test/readme_version_test.dart`. Оверрайда у пакета нет: его тесты идут против
опубликованных `async_job` и `solo` 1.0.0, в `pubspec.lock` у обоих источник
`hosted`. `README.ru.md` исключён `.pubignore`.

## Чем проверено

На `7d516c7b`, Dart 3.13.0:

- `packages/async_job_lints`: формат — 24 файла, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +114, All tests
  passed;
- `dart pub publish --dry-run` на чистом дереве — 0 предупреждений; в архиве
  `lib/`, `test/`, `example/example.md`, README, CHANGELOG, LICENSE,
  `analysis_options.yaml` и `pubspec.yaml`, сжатый он весит 34 KB;
- зонд `tool/plugin_probe.py` на 3.13.0 и на полу 3.10.0 — все четыре набора
  `ok`, прогон 2026-11-03 на `66b5167c`, после которого правился только
  `docs/handoff.md`.

Пол на чистом дереве того же коммита: `tool/archive_floor.py stage` —
`async_job_lints` 30 файлов, 0 предупреждений; `async_job` 120, `solo` 195
и `flutter_solo` 45 файлов тоже без предупреждений; `solo_lints` 22 файла
с оверрайдом дерева на `async_job_lints`, 0 предупреждений и одна подсказка.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 7 roots». `async_job_lints` опускает `analysis_server_plugin`,
`analyzer` и `analyzer_plugin` до нижних границ: `analyze lib` как
у зависимости чист, его набор из архива — +114 против опубликованных
`async_job` и `solo` 1.0.0.

## Связка

Перед связкой: `git fetch` выполнен, `origin/main` на `5512381e` — префикс
раздела линтов, который владелец отправил 2026-11-03. `main` впереди на пять
коммитов: задача 7 `aef32b50`, которая называет `async_job_lints: ^0.1.0`
в README ядра и на сайте, отчёт и ревью раздела, закрытие отложенных находок
и запись о push. Они уходят в origin вместе с релизным коммитом: окно, которое
держал `docs/handoff.md`, закрывается этим выпуском. Тега
`async_job_lints-v0.1.0` нет ни локально, ни в origin; на pub.dev пакета нет,
API отвечает 404.

Сборка сайта на `5512381e` красная: `npm ci` — «Missing:
@astrojs/markdown-satteri@0.3.8 from lock file». `site/package-lock.json`
разошёлся с `package.json` в `a13a4ade`, где сайт разделён на темы,
а не в разделе линтов; `gate` на том же коммите зелёный. Выпуска это
не касается, на сайте остаётся прежняя сборка, и в связку правка не входит.

Связка выполнена подряд:

- `d74c0bf2` — Release async_job_lints 0.1.0;
- аннотированный тег `async_job_lints-v0.1.0` указывает на `d74c0bf2`;
- `main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/async_job_lints-v0.1.0^{}` дают `d74c0bf2`;
- `dart pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/async_job_lints version
  0.1.0»;
- API pub.dev вернул `latest: 0.1.0`;
- CI `gate` на `d74c0bf2` зелёный; сборка сайта на нём красная по той же
  причине, что и на `5512381e`.

Пакет вышел без издателя. Владелец перенёс его к `yet-another.dev` сам
на странице администрирования pub.dev, API вернул
`publisherId: yet-another.dev`.

Сборку сайта чинит коммит «build: build the site on Node 26» по слову владельца
«первый, подними Node»; в origin он уйдёт по слову владельца. npm 10 из Node 22
не принимает lock-файл, который записал более новый npm: `npm ci` просит
запись, которую тот выбросил. Ни один выпуск Node не несёт npm 12, на котором
lock-файл записан локально; Node 26 несёт npm 11.20, и с ним локально проходят
`npm ci` и сборка сайта, 91 страница.

Пакет: https://pub.dev/packages/async_job_lints/versions/0.1.0

Выпуск завершён.
