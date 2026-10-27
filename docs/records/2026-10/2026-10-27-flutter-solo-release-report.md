> **Состояние на 2026-10-27:** `flutter_solo` 0.5.0 опубликован на pub.dev;
> релизный коммит `160578a5` и аннотированный тег отправлены в origin. Выпуск
> 0.5.0 завершён: все три пакета на pub.dev.
> **Что это:** снятие оверрайдов `flutter_solo` и подготовка его выпуска 0.5.0.
> **Связанные записи:** `2026-10-27-solo-release-report.md`,
> `2026-10-27-async-job-release-report.md`,
> `2026-10-27-release-prep-report.md`, `2026-10-25-flutter-solo-release-report.md`.

# Выпуск flutter_solo 0.5.0

По слову владельца 2026-10-27 «готовь flutter_solo». На pub.dev сейчас
`latest: 0.4.0`; `async_job` 0.5.0 и `solo` 0.5.0 вышли тем же днём, scopo
0.20.0 под новое ядро — тоже. Это последний из трёх пакетов выпуска.

## Подготовка

Коммит `9edcb0e8`:

- `scopo: ^0.20.0` в dev-зависимостях `flutter_solo` вместо `^0.19.0`, и так же
  в pubspec стенда `tool/flutter_snippets.py`: scopo 0.19 держит `async_job`
  ^0.4.0 и с ядром 0.5.0 не разрешается. Публичный API scopo 0.20.0 не менялся,
  сменилась только граница ядра;
- удалены `packages/flutter_solo/pubspec_overrides.yaml`
  и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление в индексе
  и в коммите. Оба вели `solo` и `async_job` на дерево. Других
  `pubspec_overrides.yaml` в дереве не осталось; стенды `tool/doc_snippets.py`,
  `tool/accumulation_snippets.py` и `tool/flutter_snippets.py` по-прежнему
  ведут `async_job` на дерево, а дерево `solo` и ядра совпадает с тегами
  `solo-v0.5.0` и `async_job-v0.5.0`.

Версия 0.5.0, граница `solo: ^0.5.0` и заголовок `## 0.5.0` списка изменений
и его перевода поставлены раньше, при общей подготовке,
`2026-10-27-release-prep-report.md`.

## Чем проверено

Задание `flutter` из `gate.yml`, повторённое локально на Flutter stable.
В `pubspec.lock` пакета `solo` 0.5.0 (sha256 `2ae4936d…c71b`), `async_job`
0.5.0 (`ff612a2b…3692`) и scopo 0.20.0 (`09368bb0…0f12`), все с pub.dev.

- `packages/flutter_solo`: формат — 36 файлов, 0 изменений;
  `flutter analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `flutter test` — +249, All tests passed,
  `readme_scopo_test.dart` загружается и проходит;
- `packages/flutter_solo/example`: анализ чистый; `flutter test` — +6;
- стенд `tool/flutter_snippets.py`: анализ чистый,
  `flutter test --concurrency=1` — +50; `check_traces.py` — 6 цитированных
  трасс, все напечатаны;
- `flutter pub publish --dry-run` на `9edcb0e8` — 0 предупреждений, подсказок
  об оверрайдах больше нет.

Пол на копии `9edcb0e8`, отсоединённой: `tool/archive_floor.py stage` — три
архива по 0 предупреждений; `tool/archive_floor.py run` на 3.27.0 — «every
archive passes its gate on the floor: 5 roots»: `async_job` +1885, `solo` +2122
при 11 пропущенных, его пример +112, `flutter_solo` +249, его пример +6.
`flutter pub downgrade solo` довёл `flutter_solo` до нижней границы `^0.5.0`.

## Связка

Владелец разрешил публикацию отдельным запросом «публикуй flutter_solo»,
состоящим только из просьбы опубликовать. Перед связкой: `git fetch` выполнен,
`origin/main` не ушёл вперёд от `main` на `e1e625fa`, тега
`flutter_solo-v0.5.0` нет ни локально, ни в origin, оверрайдов у пакета
и примера нет, `flutter pub publish --dry-run` — 0 предупреждений; на pub.dev
`latest: 0.4.0`. Коммиты подготовки `9edcb0e8` и `e1e625fa` до связки
не пушились: они уходят в origin вместе с релизным, и CI на них идёт уже после
push.

Связка выполнена подряд:

- `9edcb0e8` — снятие оверрайдов, `160578a5` — Release flutter_solo 0.5.0;
- аннотированный тег `flutter_solo-v0.5.0` указывает на `160578a5`;
- `origin/main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/flutter_solo-v0.5.0^{}` дают `160578a5`;
- `flutter pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/flutter_solo version 0.5.0»;
- API pub.dev вернул `latest: 0.5.0`;
- CI `gate` на `160578a5`: `dart`, `flutter`, `floor`, `snippets` и `docs`
  зелёные.

Пакет: https://pub.dev/packages/flutter_solo/versions/0.5.0

Выпуск 0.5.0 завершён: все три пакета на pub.dev.
