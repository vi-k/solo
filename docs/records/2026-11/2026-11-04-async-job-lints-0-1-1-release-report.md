> **Состояние на 2026-11-04:** `async_job_lints` 0.1.1 опубликован на pub.dev;
> релизный коммит `0e60e2b3` и аннотированный тег отправлены в origin.
> **Что это:** подготовка патча `async_job_lints` 0.1.1 с новой подсказкой
> `bare_await`.
> **Связанные записи:** `2026-11-04-async-job-lints-release-report.md`,
> `2026-11-04-solo-lints-release-report.md`,
> `2026-10-29-bare-await-design.md`.

# Выпуск async_job_lints 0.1.1

По слову владельца 2026-11-04 «давай патч». Слово понято как подготовка:
разрешение на связку приходит отдельным запросом, состоящим только из просьбы
опубликовать, как «опубликуй async_job_lints 0.1.0» у прошлого выпуска.

## Что в патче

Коммит `e711df7b` «fix: say what join is for in the bare_await message».
Подсказка `bare_await` ставила `ctx.join` в один ряд с `ctx.abandonable`
и `ctx.pause`, а «steps that must all run» отдавала одному `ctx.uncancellable`:

```text
Wait through 'ctx.join', 'ctx.abandonable' or 'ctx.pause', or put the steps
that must all run in 'ctx.uncancellable'.
```

Так читалось, будто `join` обрывается отменой. На деле он ждёт вызов целиком
и бросает `Cancelled` только после него, и агент, поверивший подсказке,
поставил `// ignore:` с ложным обоснованием там, где нужен был `join`. Новая
подсказка называет назначение каждого члена:

```text
Wait through 'ctx.join' for a call that must finish, 'ctx.abandonable' for
one the job may leave in flight or 'ctx.pause' for a delay, or put the steps
that must not hear a cancellation until they end in 'ctx.uncancellable'.
```

Раздел `bare_await` README и его перевод объясняют разницу `join`
и `abandonable` и ссылаются на таблицу «The context at a glance» README ядра.
Цитата старой подсказки в `2026-10-29-bare-await-design.md` оставлена: запись
хранится как написана.

## Подготовка

- `version: 0.1.1`;
- README, перевод и `example/example.md` просят `^0.1.1` — сторож
  `test/readme_version_test.dart` требует версию пакета в README;
- раздел «Unreleased» `packages/async_job_lints/CHANGELOG.md` стал `## 0.1.1`;
  перевод — тем же коммитом.

`solo_lints` не меняется и не выпускается: `bare_await` он регистрирует
из `async_job_lints` через `plugin_api.dart`, своей копии подсказки у него нет,
а `async_job_lints: ^0.1.0` его `pubspec.yaml` пускает 0.1.1 — патч дойдёт
до его пользователей сам. README ядра просит `async_job_lints: ^0.1.0` и тоже
пускает 0.1.1.

## Чем проверено

- `packages/async_job_lints`: формат — 24 файла, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +114, All tests
  passed; пример — `dart analyze --fatal-infos`, No issues found;
- сверка переводов, `reflow.py --check`, `check_line_width.py`,
  `check_links.py` — чисто;
- `dart pub publish --dry-run` на чистом дереве коммита подготовки — 0
  предупреждений.

Пол на том же чистом дереве: `tool/archive_floor.py stage` прошёл по всем пяти
пакетам — шаг краснеет на предупреждении dry-run, а их не было.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 7 roots». `async_job_lints` опускает `analysis_server_plugin`,
`analyzer` и `analyzer_plugin` до нижних границ, его набор из архива — +114;
`solo_lints` идёт против опубликованного `async_job_lints` 0.1.0, +71.

## Связка

Владелец разрешил публикацию отдельным запросом «опубликуй async_job_lints
0.1.1», состоящим только из просьбы опубликовать. Перед связкой: `git fetch`
выполнен, `main` впереди `origin/main` на пять коммитов — запись о выпуске
`solo_lints` 0.1.5, отложенный патч ядра в handoff, правка подсказки,
подготовка и эта запись; они уходят в origin вместе с релизным. Тега
`async_job_lints-v0.1.1` нет ни локально, ни в origin; на pub.dev
`latest: 0.1.0`.

Связка: релизный коммит `0e60e2b3` «Release async_job_lints 0.1.1»,
аннотированный тег `async_job_lints-v0.1.1` на нём, `git push --follow-tags`
отправил `main` (`a089dd04..0e60e2b3`) и тег. `dart pub publish` из чистого
дерева: «Successfully uploaded https://pub.dev/packages/async_job_lints version
0.1.1». API pub.dev отдаёт версию 0.1.1 с датой 2026-11-04T12:02:00Z, издатель
пакета — `yet-another.dev`.
