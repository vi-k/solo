> **Состояние на 2026-11-02:** `flutter_solo` 1.0.0 подготовлен коммитом
> `235bb05f`; выполняется связка его выпуска по слову владельца, итог
> допишется отдельным коммитом после публикации.
> **Что это:** снятие оверрайдов `flutter_solo` и подготовка его выпуска
> 1.0.0 после выхода scopo под ядро 1.0.
> **Связанные записи:** `2026-11-01-solo-release-report.md`,
> `2026-11-01-async-job-release-report.md`,
> `2026-11-01-solo-lints-release-report.md`,
> `2026-10-28-flutter-solo-release-report.md`.

# Выпуск flutter_solo 1.0.0

По слову владельца 2026-11-02 «scopo обновился». На pub.dev scopo 1.0.0,
опубликован 2026-11-02, требует `async_job: '>=1.0.0 <1.1.0'`; `async_job`
и `solo` 1.0.0 вышли 2026-11-01. У `flutter_solo` сейчас `latest: 0.6.0`. Это
последний пакет выпуска 1.0.

## Подготовка

Коммит `235bb05f`:

- `scopo: ^1.0.0` в dev-зависимостях `flutter_solo` вместо `^0.21.0`, и так же
  в pubspec стенда `tool/flutter_snippets.py`: scopo 0.21.x держит `async_job`
  ^0.6.0 и с ядром 1.0 не разрешается;
- удалены `packages/flutter_solo/pubspec_overrides.yaml`
  и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление в индексе
  и в коммите. Оба вели `solo` и `async_job` на дерево. Оверрайдов в дереве
  больше нет ни у одного пакета; стенды `tool/doc_snippets.py`,
  `tool/accumulation_snippets.py` и `tool/flutter_snippets.py` по-прежнему
  ведут `async_job` и `solo` на дерево, а оно совпадает с тегами `solo-v1.0.0`
  и `async_job-v1.0.0`, кроме тестов ядра коммита `0e2ac9b1`.

Версия 1.0.0, граница `solo: ^1.0.0` и заголовок `## 1.0.0` списка изменений
и его перевода поставлены при общей подготовке,
`2026-10-30-one-zero-report.md`.

## Чем проверено

Задание `flutter` из `gate.yml`, повторённое локально. В `pubspec.lock` пакета
`async_job` 1.0.0 (sha256 `30c0a627…a915`), `solo` 1.0.0 (`a067958a…146f`)
и scopo 1.0.0 (`368da861…adca`), все с pub.dev.

- `packages/flutter_solo`: формат — 36 файлов, 0 изменений;
  `flutter analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `flutter test` — +255, All tests passed,
  `readme_scopo_test.dart` отдельно — +8;
- `packages/flutter_solo/example`: формат — 2 файла, 0 изменений; анализ
  чистый; `flutter test` — +6;
- стенд `tool/flutter_snippets.py` на scopo 1.0.0: анализ чистый,
  `flutter test --concurrency=1` — +51; `check_traces.py` — 6 цитированных
  трасс, все напечатаны;
- `flutter pub publish --dry-run` на `235bb05f` — 0 предупреждений, подсказок
  об оверрайдах больше нет.

Пол на отсоединённой копии `235bb05f`: `tool/archive_floor.py stage` —
`async_job` 120, `solo` 194, `solo_lints` 33 и `flutter_solo` 45 файлов, все
четыре по 0 предупреждений и без подсказок. `tool/archive_floor.py run`
на 3.38.1 — «every archive passes its gate on the floor: 6 roots»: `async_job`
+1891, `solo` +2218 при 11 пропущенных, его пример +112, `solo_lints` +167,
`flutter_solo` +255, его пример +6. `flutter pub downgrade solo` довёл
`flutter_solo` до нижней границы `^1.0.0`. Оверрайдов в раскладке нет, так что
ограничения между пакетами пол на этот раз доказывает.

## Связка

Владелец разрешил публикацию 2026-11-02 отдельным запросом «публикуй
flutter_solo 1.0.0», состоящим только из просьбы опубликовать.

Перед связкой: `origin/main` на `14af6348`, локальный `main` впереди
на `235bb05f` и `e6cf5a82`; тега `flutter_solo-v1.0.0` нет ни локально,
ни в `origin`; на pub.dev `latest` у `flutter_solo` — 0.6.0;
`pubspec_overrides.yaml` у пакета и примера нет.

Коммит `Release flutter_solo 1.0.0`, аннотированный тег `flutter_solo-v1.0.0`,
push и `flutter pub publish` — подряд; итог ниже.
