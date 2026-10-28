> **Состояние на 2026-10-28:** `flutter_solo` 0.6.0 опубликован на pub.dev;
> релизный коммит `da1525d9` и аннотированный тег отправлены в origin. Выпуск
> 0.6.0 завершён: все три пакета на pub.dev.
> **Что это:** снятие оверрайдов `flutter_solo` и подготовка его выпуска 0.6.0.
> **Связанные записи:** `2026-10-28-solo-release-report.md`,
> `2026-10-28-async-job-release-report.md`,
> `2026-10-28-release-prep-report.md`,
> `2026-10-27-flutter-solo-release-report.md`.

# Выпуск flutter_solo 0.6.0

По слову владельца 2026-10-28 «scopo опубликован. готовь flutter_solo».
На pub.dev сейчас `latest: 0.5.0`; `async_job` 0.6.0 и `solo` 0.6.0 вышли
тем же днём, scopo 0.21.0 под новое ядро (`async_job: ^0.6.0`) — тоже. Это
последний из трёх пакетов выпуска.

## Подготовка

Коммит `c0e22559`:

- `scopo: ^0.21.0` в dev-зависимостях `flutter_solo` вместо `^0.20.0`, и так же
  в pubspec стенда `tool/flutter_snippets.py`: scopo 0.20.0 держит `async_job`
  ^0.5.0 и с ядром 0.6.0 не разрешается;
- удалены `packages/flutter_solo/pubspec_overrides.yaml`
  и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление в индексе
  и в коммите. Оба вели `solo` и `async_job` на дерево. В дереве остались
  оверрайды одного `packages/solo_lints`; стенды `tool/doc_snippets.py`,
  `tool/accumulation_snippets.py` и `tool/flutter_snippets.py` по-прежнему
  ведут `async_job` и `solo` на дерево, а дерево `solo` и ядра совпадает
  с тегами `solo-v0.6.0` и `async_job-v0.6.0`.

Версия 0.6.0, граница `solo: ^0.6.0` и заголовок `## 0.6.0` списка изменений
и его перевода поставлены раньше, при общей подготовке,
`2026-10-28-release-prep-report.md`.

## Чем проверено

Задание `flutter` из `gate.yml`, повторённое локально на Flutter 3.47.0 stable.
В `pubspec.lock` пакета `solo` 0.6.0 (sha256 `8dfc849e…d5de`), `async_job`
0.6.0 (`317e8d8a…d464`) и scopo 0.21.0 (`0a2fcf3d…9160`), все с pub.dev.

- `packages/flutter_solo`: формат — 36 файлов, 0 изменений;
  `flutter analyze --fatal-infos` — No issues found; `dart doc --dry-run` — 0
  предупреждений и 0 ошибок; `flutter test` — +254, All tests passed,
  `readme_scopo_test.dart` отдельно — +8;
- `packages/flutter_solo/example`: анализ чистый; `flutter test` — +6;
- стенд `tool/flutter_snippets.py`: анализ чистый,
  `flutter test --concurrency=1` — +51; `check_traces.py` — 6 цитированных
  трасс, все напечатаны;
- `flutter pub publish --dry-run` на `c0e22559` — 0 предупреждений, подсказок
  об оверрайдах больше нет.

Пол на копии `c0e22559`, отсоединённой: `tool/archive_floor.py stage` —
`async_job` 119, `solo` 189 и `flutter_solo` 45 файлов, по 0 предупреждений без
подсказок; `solo_lints` 30 файлов, 0 предупреждений, с оверрайдами дерева.
`tool/archive_floor.py run` на 3.38.1 — «every archive passes its gate on the
floor: 6 roots»: `async_job` +1885, `solo` +2198 при 11 пропущенных, его пример
+112, `solo_lints` +122, `flutter_solo` +254, его пример +6.
`flutter pub downgrade solo` довёл `flutter_solo` до нижней границы `^0.6.0`.

## Связка

Владелец разрешил публикацию отдельным запросом «публикуй flutter_solo 0.6.0»,
состоящим только из просьбы опубликовать. Перед связкой: `git fetch` выполнен,
`origin/main` на `87eef859` и вперёд от `main` не ушёл; коммиты `c0e22559`,
`30e89ca0` и `f13423b1` не пушились и уходят в origin вместе с релизным, CI
на них идёт уже после push. Тега `flutter_solo-v0.6.0` нет ни локально,
ни в origin, оверрайдов у пакета и примера нет,
`flutter pub publish --dry-run` — 0 предупреждений; на pub.dev `latest: 0.5.0`.

Связка выполнена подряд:

- `da1525d9` — Release flutter_solo 0.6.0;
- аннотированный тег `flutter_solo-v0.6.0` указывает на `da1525d9`;
- `origin/main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/flutter_solo-v0.6.0^{}` дают `da1525d9`;
- `flutter pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/flutter_solo version 0.6.0»;
- API pub.dev вернул `latest: 0.6.0`;
- CI `gate` на `da1525d9`: `dart`, `flutter`, `snippets` и `docs` зелёные,
  `floor` отменён — группа конкурентности `gate.yml` сняла его, когда пришёл
  push `84ddb054` выпуска `solo_lints`. `gate` на `84ddb054`, где то же дерево
  `flutter_solo`, зелёный во всех пяти заданиях.

Пакет: https://pub.dev/packages/flutter_solo/versions/0.6.0

Выпуск 0.6.0 завершён: все три пакета на pub.dev.
