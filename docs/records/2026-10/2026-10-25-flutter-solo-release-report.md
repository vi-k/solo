> **Состояние на 2026-10-25:** подготовка `flutter_solo` 0.4.0 сделана
> и в `main`, коммит `37da782f`. Публикация не начиналась: связка ждёт
> отдельного слова владельца.
> **Что это:** снятие оверрайдов `flutter_solo` и подготовка его выпуска 0.4.0.
> **Связанные записи:** `2026-10-25-solo-release-report.md`,
> `2026-10-25-async-job-release-report.md`,
> `2026-10-25-release-prep-report.md`, `2026-10-23-flutter-solo-release-report.md`.

# Выпуск flutter_solo 0.4.0

По слову владельца 2026-10-25 «готовь выпуск flutter_solo». На pub.dev сейчас
`latest: 0.3.0`; `async_job` 0.4.0 и `solo` 0.4.0 вышли тем же днём, scopo
0.19.0 под новое ядро — тоже. Это последний из трёх пакетов выпуска.

## Подготовка

Коммит `37da782f`:

- `scopo: ^0.19.0` в dev-зависимостях `flutter_solo` вместо `^0.18.0`, и так же
  в pubspec стенда `tool/flutter_snippets.py`: scopo 0.18 держит `async_job`
  ^0.3.0 и с ядром 0.4.0 не разрешается, а под оверрайдами переопределял
  `onError` ядра по-старому, отчего `readme_scopo_test.dart` не загружался;
- удалены `packages/flutter_solo/pubspec_overrides.yaml`
  и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление в индексе
  и в коммите. Оба вели `solo` и `async_job` на дерево. Других
  `pubspec_overrides.yaml` в дереве не осталось; стенды `tool/doc_snippets.py`,
  `tool/accumulation_snippets.py` и `tool/flutter_snippets.py` по-прежнему
  ведут `async_job` на дерево, а оно совпадает с тегом `async_job-v0.4.0`.

Версия 0.4.0, граница `solo: ^0.4.0` и заголовок `## 0.4.0` списка изменений
и его перевода поставлены раньше, при общей подготовке,
`2026-10-25-release-prep-report.md`.

## Чем проверено

Задание `flutter` из `gate.yml`, повторённое локально на Flutter 3.47.0 stable.
В `pubspec.lock` пакета `solo` 0.4.0 (sha256 `2f33de96…37d4`), `async_job`
0.4.0 (`a71e876e…950d`) и scopo 0.19.0 (`4298f8f1…73f9`), все с pub.dev.

- `packages/flutter_solo`: формат — 36 файлов, 0 изменений;
  `flutter analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `flutter test` — +249, All tests passed,
  `readme_scopo_test.dart` загружается и проходит;
- `packages/flutter_solo/example`: анализ чистый; `flutter test` — +6;
- стенд `tool/flutter_snippets.py`: анализ чистый,
  `flutter test --concurrency=1` — +50; `check_traces.py` — 6 цитированных
  трасс, все напечатаны;
- `flutter pub publish --dry-run` на `37da782f` — 0 предупреждений, подсказок
  об оверрайдах больше нет.

Пол на копии `37da782f`, `git worktree add --detach`:
`tool/archive_floor.py stage` — три архива по 0 предупреждений;
`tool/archive_floor.py run` на 3.27.0 — «every archive passes its gate on the
floor: 5 roots»: `async_job` +1858, `solo` +2059 при 11 пропущенных, его пример
+112, `flutter_solo` +249, его пример +6. `flutter pub downgrade solo` довёл
`flutter_solo` до нижней границы `^0.4.0`.

CI `gate` на `37da782f` (прогон 40179110802) зелёный во всех пяти заданиях:
`dart`, `snippets`, `docs`, `flutter` и `floor` — впервые с начала цикла 0.4.0,
где `flutter` краснел одним `readme_scopo_test.dart`.

Связка — коммит `Release flutter_solo 0.4.0`, аннотированный тег
`flutter_solo-v0.4.0`, push, `flutter pub publish` — по отдельному запросу
владельца.
