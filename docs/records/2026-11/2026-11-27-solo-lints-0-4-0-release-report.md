> **Состояние на 2026-11-28:** выпущен по слову владельца «опубликуй
> solo_lints 0.4.0»: релизный коммит «Release solo_lints 0.4.0», аннотированный
> тег `solo_lints-v0.4.0`, `git push --follow-tags`, `dart pub publish`.
> Следом — подъём `solo_lints: ^0.4.0` в README и примерах `solo`
> и `flutter_solo`.
> **Что это:** подготовка минора `solo_lints` 0.4.0 — пять правил узнают пулы
> `SoloLanes`.
> **Связанные записи:** `2026-11-27-async-job-lints-0-2-4-release-report.md`,
> `2026-11-27-solo-2-1-0-release-report.md`,
> `2026-11-27-solo-pool-report.md`,
> `2026-11-19-solo-lints-0-3-1-release-report.md`,
> `2026-11-18-solo-lints-0-3-0-release-report.md`,
> `2026-11-27-pool-releases-prep-review-report.md`.

# Выпуск solo_lints 0.4.0

По слову владельца 2026-11-27 «готовь выпуск async_job_lints, solo 2.1.0
и solo_lints». Слово понято как подготовка: разрешение на связку приходит
отдельным запросом, состоящим только из просьбы опубликовать.

## Что в выпуске

Раздел «0.4.0» `CHANGELOG.md` — задача 7 плана пула:

- `lane_outside_constructor` сообщает о `pool(...)` вне тела конструктора своим
  сообщением;
- `await_own_queue` сообщает о теле, поставленном в пул, которое ждёт задачу
  того же пула, при любом ключе, своим сообщением;
- `stale_emit` принимает тело, отданное пулу, как тело, отданное линии;
- `key_per_request` и `ignore_failure_hides_bugs` принимают члены пула как
  члены линии — это приходит из `async_job_lints` 0.2.4 и достаётся под ним
  и 0.3.1;
- README описывает пулы в разделах трёх правил;
- требует `async_job_lints` 0.2.4.

## Почему минор

`lane_outside_constructor` — предупреждение и включено, как только плагин
назван. На коде с `pool(...)` вне тела конструктора, который с 0.3.1 проходил,
`dart analyze` с 0.4.0 падает: 0.3.1 о `pool(...)` молчит и под
`async_job_lints` 0.2.4. `await_own_queue` минора не держит: под 0.2.4 уже
0.3.1 сообщает об ожидании своего пула, сообщением о линии, а 0.4.0 меняет
только текст. Так и сказано в разделе «0.4.0», как в «0.3.0». Ревью
подготовки — `2026-11-27-pool-releases-prep-review-report.md`, В1. У кого
в `analysis_options.yaml` стоит `^0.3.1`, тот 0.4.0 не получит, пока сам
не поднимет версию: минор 0.x так и доходит.

## Зависимости и порядок

Во время работы `solo_lints` зависит от `async_job_lints: ^0.2.4`, тесты идут
против `solo` 2.1.0 (`dev_dependencies`: `solo: ^2.1.0`). До выхода обоих
`packages/solo_lints/pubspec_overrides.yaml` вёл на `async_job_lints` и `solo`
из дерева. После выхода `solo` 2.1.0 коммит «chore: drop the overrides on solo»
оставил в нём один `async_job_lints`, первая строка — «Until async_job_lints
0.2.4 is published.». После выхода `async_job_lints` 0.2.4 коммит «chore: drop
the override on async_job_lints» удалил его. Выпуск последний из трёх.

README `solo` и `flutter_solo`, их переводы и примеры просят
`solo_lints: ^0.3.0`, и 0.4.0 это ограничение не пускает. Сторож
`readme_rakes_test.dart` обоих пакетов требует, чтобы README называл ту версию,
с которой анализируется пример, а пример на `^0.4.0` до публикации
не разрешился бы. Строки поднимаются отдельной правкой после выхода и дойдут
до pub.dev со следующими выпусками `solo` и `flutter_solo` — как после 0.3.0.

Подготовка живёт в ветке `pool-lints-release`, а не в `main`: README и пример
просят `^0.4.0`, и пуш связки `solo` или `async_job_lints` показал бы эту
версию на сайте раньше pub.dev. Держит ветка только версии и заголовок раздела:
тексты о пуле в README и списке изменений уже в `main` и выйдут на сайт с пушем
связки `solo`, решение 173 `docs/settled.md`.

## Подготовка

Коммит «chore: prepare solo_lints 0.4.0», вместе с этой записью:

- `version: 0.4.0`, `async_job_lints: ^0.2.4` и `solo: ^2.1.0`
  в `dev_dependencies` `packages/solo_lints/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал «0.4.0»: «Requires the next patch of
  `async_job_lints`» стало «Requires `async_job_lints` 0.2.4», добавлены фраза
  о том, что 0.3.1 уже видит под 0.2.4, и фраза о миноре; перевод тоже, линтер
  `humanizer--ru` — 0 ошибок;
- README, перевод и `example/example.md` просят `^0.4.0`: этого требуют сторожа
  `readme_version_test.dart` и `example_page_test.dart`.

## Чем проверено

На дереве подготовки, до выхода `solo` 2.1.0, против `async_job_lints` 0.2.4
и `solo` 2.1.0 из дерева: формат — «0 changed», `dart analyze --fatal-infos` —
«No issues found!», `dart doc --dry-run` — «Found 0 warnings and 0 errors.»,
`dart test` — +174; `tool/plugin_probe.py` — «ok» на всех четырёх наборах.
`check_translations.py` — «no differences», `check_links.py`,
`check_line_width.py` и `reflow.py --check` чистые.

## После выхода async_job_lints 0.2.4

`async_job_lints` 0.2.4 вышел 2026-11-27. Коммит «chore: drop the override on
async_job_lints» удалил `packages/solo_lints/pubspec_overrides.yaml` и снял его
с индекса, за ним на `main` встал коммит этой подготовки, и ветка
`pool-lints-release` больше не нужна.

Против опубликованных — в `pubspec.lock` `async_job_lints` «0.2.4» и `solo`
«2.1.0», оба «source: hosted»: формат — «0 changed»,
`dart analyze --fatal-infos` — «No issues found!», `dart doc --dry-run` —
«Found 0 warnings and 0 errors.», `dart test` — +174; `tool/plugin_probe.py` —
«ok» на всех четырёх наборах; раскладка архивов и прогон на полу Flutter
3.38.1 — «every archive passes its gate on the floor: 7 roots»;
`dart pub publish --dry-run` — «Package has 0 warnings.». Сайт покажет 0.4.0
с пушем связки.

После связки — отдельной правкой подъём `solo_lints: ^0.4.0` в README
и примерах `solo` и `flutter_solo`.

На 2026-11-27: на pub.dev `solo_lints` 0.3.1; тега `solo_lints-v0.4.0` нет
ни локально, ни в origin.

## Связка

Владелец разрешил публикацию 2026-11-28 отдельным запросом «опубликуй
solo_lints 0.4.0», следующим сообщением после доклада о выходе
`async_job_lints` 0.2.4. Перед связкой на pub.dev стоял `solo_lints` 0.3.1,
тега `solo_lints-v0.4.0` не было ни локально, ни в origin, `main` был впереди
`origin/main` на три коммита — снятие оверрайда на `async_job_lints`, эту
подготовку и заметку о CI после выхода `async_job_lints` — и не отставал
от него. Пробная публикация на `17cac687` против опубликованных
`async_job_lints` 0.2.4 и `solo` 2.1.0 — «Package has 0 warnings.».

Связка: релизный коммит «Release solo_lints 0.4.0», аннотированный тег
`solo_lints-v0.4.0`, `git push --follow-tags` и `dart pub publish --force`
из чистого дерева `packages/solo_lints`. Выпуск последний из трёх: пул вышел
в `solo` 2.1.0, `async_job_lints` 0.2.4 и `solo_lints` 0.4.0.

pub.dev показал `solo_lints` 0.4.0 через пару минут после загрузки. Пуш
запустил `gate` и `site` CI на `281d2c9a`, оба зелёные.
