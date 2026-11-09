> **Состояние на 2026-11-09:** связка выпуска `async_job_lints` 0.2.0 идёт
> по слову владельца «публикуй»: релизный коммит этой записи, тег, push
> и `dart pub publish`. Итог связки дописан следующим коммитом.
> **Что это:** подготовка и связка минорного выпуска `async_job_lints` 0.2.0
> с правилами `discarded_outcome` и `outcome_after_await`.
> **Связанные записи:** `2026-11-09-done-lints-design.md`,
> `2026-11-09-done-lints-report.md`,
> `2026-11-04-async-job-lints-0-1-1-release-report.md`.

# Выпуск async_job_lints 0.2.0

По слову владельца 2026-11-09 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Им закрыт выпуск `async_job_lints` 0.2.0, который
handoff и прошлое сообщение владельцу называли первым; `solo_lints` 0.2.0 —
отдельная связка и ждёт своего слова.

## Что в выпуске

Два новых предупреждения о результате задачи, включённые, как только плагин
назван: `discarded_outcome` и `outcome_after_await` — дизайн
`2026-11-09-done-lints-design.md`, работа, замер, ревью работы и три узких
ревью правок — `2026-11-09-done-lints-report.md`. `dart analyze` падает
на коде, который раньше проходил, поэтому выпуск минорный. README отправляет
за таблицей контекста в справочник `async_job`.

## Подготовка

Коммит `0516e1c6` «chore: prepare async_job_lints 0.2.0»:

- `version: 0.2.0`;
- README, перевод и `example/example.md` просят `^0.2.0` — сторож
  `test/readme_version_test.dart` требует версию пакета в README;
- раздел «Unreleased» `packages/async_job_lints/CHANGELOG.md` стал `## 0.2.0`,
  «the next release is a minor one» — «the release is a minor one»; перевод —
  тем же коммитом.

`solo_lints` не меняется: его `async_job_lints: ^0.1.0` минор 0.2.0 не пускает,
новые правила дойдут до его пользователей выпуском `solo_lints` 0.2.0. До него
оверрайд `packages/solo_lints` на `async_job_lints` из дерева остаётся.

## Чем проверено

- `packages/async_job_lints`: формат — 28 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +203, All tests
  passed; пример — `dart analyze --fatal-infos`, No issues found;
- сверка переводов, `reflow.py`, `check_line_width.py` — чисто;
- `dart pub publish --dry-run` на чистом дереве коммита подготовки — 0
  предупреждений, архив 46 KB.

Пол на том же чистом дереве: `tool/archive_floor.py stage` прошёл по всем пяти
пакетам без предупреждений; у `solo_lints` одна подсказка, его пакет
раскладывается с оверрайдами дерева. `tool/archive_floor.py run` на 3.38.1 —
«every archive passes its gate on the floor: 7 roots», набор `async_job_lints`
из архива — +203. CI `gate` и сборка сайта зелёные на `d805e4a7`, последнем
коммите кода перед подготовкой.

## Связка

Перед связкой: тега `async_job_lints-v0.2.0` нет ни локально, ни в origin;
на pub.dev `latest: 0.1.1`. Связка: релизный коммит «Release async_job_lints
0.2.0» с этой записью и handoff, аннотированный тег `async_job_lints-v0.2.0`
на нём, `git push --follow-tags`, `dart pub publish` из чистого дерева.
