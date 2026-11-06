> **Состояние на 2026-11-06:** подготовлено коммитом «chore: prepare async_job
> 1.0.2 and solo 1.0.1»; публикация ждёт отдельного запроса владельца.
> **Что это:** подготовка патчей `async_job` 1.0.2 и `solo` 1.0.1 —
> документация после 1.0.1 и 1.0.0.
> **Связанные записи:** `2026-11-06-async-job-1-0-1-release-report.md`,
> `2026-11-06-async-job-1-0-1-docs-review.md`,
> `2026-11-06-riverpod-3-5-report.md`, `2026-11-01-solo-release-report.md`.

# Выпуск async_job 1.0.2 и solo 1.0.1

По слову владельца 2026-11-06 «готовь патчи async_job и solo». Слово понято как
подготовка: разрешение на связку приходит отдельным запросом, состоящим только
из просьбы опубликовать, по одному на пакет или одним на оба.

## Что в патчах

Код `lib/` не менялся ни у одного: `git diff async_job-v1.0.1`
и `git diff solo-v1.0.0` по `lib/` пусты. Оба патча — документация, примеры
и тесты.

`async_job` 1.0.2 — исправления ревью документации 1.0.1
(`2026-11-06-async-job-1-0-1-docs-review.md`) и страница «With riverpod and
bloc» под riverpod 3.5 (`2026-11-06-riverpod-3-5-report.md`). Главное для
читателя pub.dev: README говорит, что простой `await` в теле контрольной точкой
не служит, и показывает yaml, который включает оба линта `async_job_lints`.

`solo` 1.0.1 — две новые страницы, `doc/riverpod.md` и `doc/bloc.md`, ссылка
`documentation:` в `pubspec.yaml` на сайт, справочник, отправляющий за таблицей
контекста к ядру, и поправка README и `doc/jobs.md` о типе `ctx.state`
у `enqueue` без аргументов типа.

## Подготовка

- `version: 1.0.2` у `async_job`, `version: 1.0.1` у `solo`;
- раздел «Unreleased» каждого `CHANGELOG.md` стал разделом выпуска, переводы —
  тем же коммитом;
- у `solo` пункт «`doc/riverpod.md` runs against riverpod 3.5» слит с пунктом
  о новой странице `doc/riverpod.md`: в 1.0.0 страницы не было, и читателю
  списка менять на ней нечего. Пункт о новой странице называет riverpod 3.5.

Версию README не называют. `solo` держит ядро в `>=1.0.0 <1.1.0` и патч получит
сам; `flutter_solo` держит `solo` как `^1.0.0`. scopo держит ядро одной
минорной версией, и патч ему не мешает. Оверрайдов в дереве нет.

## Чем проверено

- `packages/async_job`: формат — 100 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test -j 2` — +1902;
- `packages/solo`: формат — 171 файл, 0 изменений; анализ чистый;
  `dart test -j 2` — +2231;
- `packages/solo/example`: формат и анализ чистые, `dart test` — +112,
  `bin/main.dart` и `bin/quick_start.dart` запускаются;
- сверка переводов, `reflow.py --check`, `check_line_width.py` — чисто;
- `dart pub publish --dry-run` на чистом дереве коммита подготовки — 0
  предупреждений у обоих.

Пол на том же дереве: `tool/archive_floor.py stage` по всем пяти пакетам без
предупреждений, `tool/archive_floor.py run` на 3.38.1 — «every archive passes
its gate on the floor: 7 roots». `async_job` как зависимость прогоняет три
примера, его набор из архива — +1902; набор `solo` из архива — +2220, 11
пропущено.

## Связка

Порядок — снизу вверх: сначала `async_job` 1.0.2, потом `solo` 1.0.1. Каждая
связка — релизный коммит «Release <пакет> X.Y.Z», аннотированный тег
`<пакет>-vX.Y.Z`, `git push --follow-tags` и `dart pub publish` из чистого
дерева пакета.
