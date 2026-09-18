> **Состояние на 2026-09-09:** ревью проведено, обе находки подтверждены
> приёмкой и закрыты; подмены, которых песочница не дала ревьюеру,
> прогнаны на приёмке.
> **Что это:** ревью волны правок 4901124..1a0dde2 — код, тесты и
> документы одного дня, сделано `codex exec` на копии дерева.
> **Связанные записи:** 2026-09-08[14]-jobs-readme-review.md.
> **Наработки:** задание, зонды, логи команд и полный дифф волны —
> `.artifacts/2026-09-09-wave-review/`, вне гита.

## Приёмка

Обе находки воспроизведены своим зондом, см. вердикты под каждой.

**Подмены ревьюер сделать не смог, и это не его вина.** Копия дерева —
git worktree, а восстановить в нём файл значит писать в
`.git/worktrees/jobs-review/index.lock` основного репозитория, который вне
песочницы: `git checkout -- <файл>` отвечает `fatal: Unable to create ...
Operation not permitted`. Ревьюер проверил это preflight'ом на
неизменённом файле **до** первой подмены, получил отказ, повторил, получил
тот же — и не стал ломать код, который не сможет вернуть. Правильное
поведение; урок в том, что для подмен нужен клон, а не worktree.

Три подмены прогнаны на приёмке, в рабочем дереве, каждая с возвратом
`git checkout --` и проверкой чистоты:

| что сломано | что покраснело |
| --- | --- |
| убран отказ `_AutoJob` в `run` | `lifecycle_test.dart`: «a job that starts itself cannot be a child» и «a job that already started itself cannot be a child either» |
| `log` снова интерполирует (`'$message'`) | `observer_test.dart`: «log without an observer is a no-op» и «the message reaches the observer as it was given» |
| ребёнок, отвергнутый правилом, оставлен живым | `children_test.dart`: «a child a throwing rule turned away never runs» |

Каждый переписанный волной тест краснеет ровно на том, ради чего написан.

**Проверки `flutter_solo` не прошли не из-за волны.** В копии
`dart analyze` дал 122 ошибки вида `Target of URI doesn't exist:
'package:flutter/material.dart'` — в `packages/flutter_solo/example/` не
делали `flutter pub get`. В рабочем дереве анализ чист, восемь тестов
зелёные.

**Сверх находок, при приёмке.** В `JobContext.run` остался комментарий
волны: он объяснял, почему отвергнутого ребёнка заканчивают, тем, что
«a job like that, left alive, would start itself on its own microtask».
После того как `run` стал отказывать `_AutoJob` до этого места,
самозапускающийся ребёнок сюда не доходит, и причина теперь другая —
такой ребёнок остался бы усыновлённым наполовину: с родителем и уровнем,
никем не запущенный и никем не ожидаемый. Комментарий поправлен.

## ПРОГОН

Проверялось дерево на `1a0dde23935952e74a47f0966f11b45674ed1190`.
`git log 4901124..1a0dde2` дал десять коммитов; полный diff сохранён
в [14-wave-diff.log](14-wave-diff.log). Начальный и заключительный
`git status --short` пусты. Файлы исходного дерева не подменялись;
коммитов, reset, stash и clean не было.

Ниже указаны фактически исполненные команды, рабочие каталоги, коды
завершения и точные последние строки объединённого stdout/stderr.
Проверки запускала внешняя обвязка [audit.py](audit.py), через
`rtk proxy python3`; строки команд она передавала `/bin/zsh` с
указанным рабочим каталогом. Вывод сохранялся до сокращения ответа
инструмента. Завершающий перевод строки не считается отдельной строкой;
пустая строка перед ним отмечена отдельно.

### Проверки из задания

#### 01-jobs-format

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/jobs`.

~~~~sh
dart format --output=none --set-exit-if-changed lib test
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
Formatted 24 files (0 changed) in 0.03 seconds.
~~~~

Полный вывод: [01-jobs-format.log](01-jobs-format.log).

#### 02-jobs-analyze

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/jobs`.

~~~~sh
dart analyze
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
No issues found!
~~~~

Полный вывод: [02-jobs-analyze.log](02-jobs-analyze.log).

#### 03-jobs-test

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/jobs`.

~~~~sh
dart test
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
00:00 +237: All tests passed!
~~~~

Полный вывод: [03-jobs-test.log](03-jobs-test.log).

#### 04-jobs-doc

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/jobs`.

~~~~sh
dart doc --dry-run
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
Found 0 warnings and 0 errors.
~~~~

Полный вывод: [04-jobs-doc.log](04-jobs-doc.log).

#### 05-solo-checks

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/solo`.

~~~~sh
dart analyze && dart test
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
00:00 +266: All tests passed!
~~~~

Полный вывод: [05-solo-checks.log](05-solo-checks.log).

#### 06-example-checks

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/solo/example`.

~~~~sh
dart analyze && dart test
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
00:00 +7: All tests passed!
~~~~

Полный вывод: [06-example-checks.log](06-example-checks.log).

#### 07-flutter-checks

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/flutter_solo`.

~~~~sh
dart analyze && fvm flutter test
~~~~

Код завершения: `3`. Последняя строка:

~~~~text
122 issues found.
~~~~

Полный вывод: [07-flutter-checks.log](07-flutter-checks.log).

#### 08-translations

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
python3 tool/check_translations.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
no differences
~~~~

Полный вывод: [08-translations.log](08-translations.log).

#### 09-line-width

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
python3 tool/check_line_width.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
no Markdown line over 79 columns
~~~~

Полный вывод: [09-line-width.log](09-line-width.log).

В `05-solo-checks` и `06-example-checks` анализатор также напечатал
`No issues found!` перед запуском тестов.

Команда `07-flutter-checks` завершилась на `dart analyze`:
`122 issues found.`; `fvm flutter test` после `&&` **не исполнялся**.
В копии отсутствует `packages/flutter_solo/.dart_tool`, анализатор не
разрешает импорты Flutter, flutter_solo и зависимостей тестов. Первая
диагностика:

~~~~text
  error - example/lib/main.dart:3:8 - Target of URI doesn't exist: 'package:flutter/material.dart'. Try creating the file referenced by the URI, or try using a URI for a file that does exist. - uri_does_not_exist
~~~~

Это ограничение подготовки копии, не находка о волне. Восстановление
зависимостей с созданием файлов в дереве не выполнялось. Результат
«8 тестов зелёные» не установлен.

### Отказ песочницы и невыполненные подмены

До первой подмены проверил единственный разрешённый способ восстановления
на неизменённом файле. Он получил отказ; повторил один раз и получил
тот же отказ. Оба вызова:

#### 10-restore-preflight

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review checkout -- packages/jobs/lib/src/job_context.dart
~~~~

Код завершения: `128`. Последняя строка:

~~~~text
fatal: Unable to create '/Users/user/development/my/solo/.git/worktrees/jobs-review/index.lock': Operation not permitted
~~~~

Полный вывод: [10-restore-preflight.log](10-restore-preflight.log).

#### 11-restore-preflight-retry

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review checkout -- packages/jobs/lib/src/job_context.dart
~~~~

Код завершения: `128`. Последняя строка:

~~~~text
fatal: Unable to create '/Users/user/development/my/solo/.git/worktrees/jobs-review/index.lock': Operation not permitted
~~~~

Полный вывод: [11-restore-preflight-retry.log](11-restore-preflight-retry.log).

#### 12-clean-after-preflight

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review status --short
~~~~

Код завершения: `0`. Вывод пуст; последней строки нет.

Полный вывод: [12-clean-after-preflight.log](12-clean-after-preflight.log).

Дословный текст отказа в обеих попытках:

~~~~text
fatal: Unable to create '/Users/user/development/my/solo/.git/worktrees/jobs-review/index.lock': Operation not permitted
~~~~

Обходов, эскалации разрешений и другого способа восстановления не
применял. Поскольку вернуть подменённый файл через `git checkout --`
невозможно, подмены не начинались — ни в дереве, ни в дополнительной
копии реализации. Ничего не покраснело на подмене: такого прогона не было.

Невыполненные проверки, поимённо:

| Тест | Намеченная подмена | Фактический результат |
| --- | --- | --- |
| `lifecycle_test.dart`: `a job that starts itself cannot be a child` | Убрать отказ по `child is _AutoJob` из `JobContextBase.run`. | Не выполнена; чувствительность теста не установлена. |
| `lifecycle_test.dart`: `a job that already started itself cannot be a child either` | Перенести отказ автозадаче ниже проверки статуса. | Не выполнена; чувствительность теста не установлена. |
| `children_test.dart`: `a child a throwing rule turned away never runs` | Убрать завершение ребёнка через `finish(Failed(error, stackTrace))` из catch в `run`. | Не выполнена; чувствительность теста не установлена. |
| `observer_test.dart`: `log without an observer is a no-op` | Вернуть интерполяцию в `log` перед передачей сообщения. | Не выполнена; чувствительность теста не установлена. |
| `observer_test.dart`: `the message reaches the observer as it was given` | Превратить сообщение в строку перед вызовом наблюдателя. | Не выполнена; чувствительность теста не установлена. |

Эти тесты исполнены в обычном прогоне всех 237 тестов ядра. Чтение их
проверок и зелёный исход без подмен не заменяют требуемую проверку
чувствительности.

### Зонды на неизменённом коде

[probes.dart](probes.dart) импортирует `solo` и через него `jobs` из
проверяемой копии. Пути проверены в существующем package_config:
`jobs` у `solo` разрешается через `../../jobs`, сам `solo` — через
`../`. Исходники библиотек во внешний стенд не копировались.

17 сценариев: пять состояний автозадачи; отложенный ребёнок при живом
и отменённом родителе; ребёнок Solo; сообщение-объект и null; бросающий
`toString` у слушателя с раздельными зонами создания и выполнения;
передача объекта через глобальный и экземплярный хуки Solo; два сценария
курсора; два сценария интерполяции сообщения. `require` в зондах
проверяет наблюдаемое поведение, включая контрпримеры из находок.

#### 13-contract-probes

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/2026-09-09-wave-review`.

~~~~sh
dart --packages=/Users/user/development/my/solo/.artifacts/jobs-review/packages/solo/.dart_tool/package_config.json /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/probes.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
All 17 probe scenarios passed.
~~~~

Полный вывод: [13-contract-probes.log](13-contract-probes.log).

Полный вывод зондов:

~~~~text
run auto/created: ArgumentError, child=root, parent=Done
run auto/running: ArgumentError, child=root, parent=Done
run auto/done: ArgumentError, child=root, parent=Done
run auto/failed: ArgumentError, child=root, parent=Done
run auto/cancelled: ArgumentError, child=root, parent=Done
run deferred/parentCancelled=false: child=Done, error=Null
run deferred/parentCancelled=true: child=Cancelled, error=Cancelled
run solo: child=Done, level=1, parent=Done
log observer=false: outcome=Done, conversions=0, identity/null=preserved
log observer=true: outcome=Done, conversions=0, identity/null=preserved
log converting observer: outcome=Done, onError=0, creationZone=0, executionZone=1
log solo/convert=false: global=original, local=original, outcome=Done, zone=0
log solo/convert=true: global=original, local=original, outcome=Done, zone=2
README cursor/cancel=false: closeCalls=1, outcome=Done, onError=0
README cursor/cancel=true: closeCalls=2, outcome=Cancelled, onError=1
README interpolated log/throws=false: observer=none, conversions=1, outcome=Done
README interpolated log/throws=true: observer=none, conversions=1, outcome=Failed
All 17 probe scenarios passed.
~~~~

Тест из раздела `Testing` извлечён в
[readme_testing_test.dart](readme_testing_test.dart) без изменения тела;
добавлены импорты и `main`. `Database` импортируется из настоящего
`packages/jobs/example/example.dart`. Это обычный запуск, без подмены
ветки уборки.

#### 17-extract-readme-test

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/2026-09-09-wave-review`.

~~~~sh
python3 /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/readme_test.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
Testing snippet extracted verbatim; Database imported from repository example.
~~~~

Полный вывод: [17-extract-readme-test.log](17-extract-readme-test.log).

#### 18-readme-test

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review/packages/jobs`.

~~~~sh
dart test /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/readme_testing_test.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
00:00 +1: All tests passed!
~~~~

Полный вывод: [18-readme-test.log](18-readme-test.log).

### Команды определения ревизии, архивирования и контроля дерева

#### 14-wave-diff

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review diff 4901124..1a0dde2
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
   @override
~~~~

Полный вывод: [14-wave-diff.log](14-wave-diff.log).

#### 15-revision

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review rev-parse HEAD
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
1a0dde23935952e74a47f0966f11b45674ed1190
~~~~

Полный вывод: [15-revision.log](15-revision.log).

#### 16-wave-log

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review log --oneline 4901124..1a0dde2
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
014c19e docs(jobs): a stop that is asynchronous itself, and a list at odds with its own rule
~~~~

Полный вывод: [16-wave-log.log](16-wave-log.log).

#### 19-capture-reads

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
python3 /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/capture_reads.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
34 read commands archived; no mutations.
~~~~

Полный вывод: [19-capture-reads.log](19-capture-reads.log).

#### 20-final-status

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git -C /Users/user/development/my/solo/.artifacts/jobs-review status --short
~~~~

Код завершения: `0`. Вывод пуст; последней строки нет.

Полный вывод: [20-final-status.log](20-final-status.log).

### Подготовка отчёта и заключительная проверка

Первый запуск следующей команды завершился с кодом `1` из-за ошибки
регулярного выражения в самом проверяющем скрипте:

~~~~sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/verify_report.py
~~~~

Точная последняя строка:

~~~~text
AssertionError
~~~~

Это ошибка внешнего скрипта, не отказ песочницы. Выражение исправлено;
успешный повтор записан ниже.

~~~~sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/write_report.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
report.md written: 2 findings (Medium, Low).
~~~~

~~~~sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review/verify_report.py
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
Report verified; git status --short is empty.
~~~~

Проверена точная шапка, наличие двух находок и совпадение последних строк
с сохранёнными журналами. Проверяющий скрипт повторно выполнил:

~~~~sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/jobs-review status --short
~~~~

Код завершения: `0`. Вывод пуст; последней строки нет.

Два непосредственных чтения перед записью отчёта:

~~~~sh
rtk proxy sed -n '330,383p' packages/jobs/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
});
~~~~

~~~~sh
rtk proxy sed -n '40,110p' packages/jobs/test/lifecycle_test.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
      async.flushMicrotasks();
~~~~

### Команды чтения

Длинные ответы инструмента местами были усечены. Для полного журнала
34 команды чтения повторены скриптом [capture_reads.py](capture_reads.py).
Одинаковые команды приведены один раз с последней строкой сохранённого
повторного вызова; этот повтор не был тестом или подменой.
Дополнительные чтения `read01`–`read13` сохранены при первом запуске
обвязкой. Чтения курсора и lifecycle также делались непосредственно
через `rtk proxy sed`; их последние строки совпадают с
`read12` и `read13`.

<details>
<summary>Команды и точные последние строки чтений</summary>

#### archive01

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
pwd
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
/Users/user/development/my/solo/.artifacts/jobs-review
~~~~

Полный вывод: [archive01.log](archive01.log).

#### archive02

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
cat /Users/user/.codex/RTK.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
```
~~~~

Полный вывод: [archive02.log](archive02.log).

#### archive03

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
cat /Users/user/.agents/skills/code-critic/SKILL.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
Then briefly state what was reviewed and any important limitations, such as unavailable tests, missing call sites, incomplete platform implementations, inability to execute the code, or unresolved external API behavior.
~~~~

Полный вывод: [archive03.log](archive03.log).

#### archive04

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
cat AGENTS.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
номера версии.
~~~~

Полный вывод: [archive04.log](archive04.log).

#### archive05

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat docs/handoff.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  движке очередь устроена иначе, решение не перенесено.
~~~~

Полный вывод: [archive05.log](archive05.log).

#### archive06

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat docs/architecture.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  `onCancel` и ожидание одного `Completer`, а не `await for`.
~~~~

Полный вывод: [archive06.log](archive06.log).

#### archive07

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat docs/conventions.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
- Публикация на pub.dev — только по правилам из `AGENTS.md`.
~~~~

Полный вывод: [archive07.log](archive07.log).

#### archive08

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat docs/backlog.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  `// ignore:`, чтобы так сделать.
~~~~

Полный вывод: [archive08.log](archive08.log).

#### archive09

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy git status --short
~~~~

Код завершения: `0`. Вывод пуст; последней строки нет.

Полный вывод: [archive09.log](archive09.log).

#### archive10

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy git log --oneline 4901124..1a0dde2
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
014c19e docs(jobs): a stop that is asynchronous itself, and a list at odds with its own rule
~~~~

Полный вывод: [archive10.log](archive10.log).

#### archive11

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy git diff --stat 4901124..1a0dde2
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
 18 files changed, 1467 insertions(+), 170 deletions(-)
~~~~

Полный вывод: [archive11.log](archive11.log).

#### archive12

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '280,620p' docs/handoff.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
2730 сценариев, все последовательности до пяти событий из данных, ошибки,
~~~~

Полный вывод: [archive12.log](archive12.log).

#### archive13

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '621,1060p' docs/handoff.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  движке очередь устроена иначе, решение не перенесено.
~~~~

Полный вывод: [archive13.log](archive13.log).

#### archive14

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy git diff 4901124..1a0dde2 -- packages
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
   @override
~~~~

Полный вывод: [archive14.log](archive14.log).

#### archive15

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy rg --files -g AGENTS.md -g package_config.json -g .gitignore -g .fvmrc --hidden
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
.gitignore
~~~~

Полный вывод: [archive15.log](archive15.log).

#### archive16

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy ls -la packages/jobs/.dart_tool packages/solo/.dart_tool packages/flutter_solo/.dart_tool packages/solo/example/.dart_tool
~~~~

Код завершения: `1`. Последняя строка:

~~~~text
drwxr-xr-x@  3 user  staff    96 Sep  8 15:03 test
~~~~

Полный вывод: [archive16.log](archive16.log).

#### archive17

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '1,290p' docs/handoff.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
стрипе `run` выигрывал гонку у собственного микротаска `_AutoJob` и
~~~~

Полный вывод: [archive17.log](archive17.log).

#### archive18

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy git diff 4901124..1a0dde2 -- packages/jobs/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
 ```
~~~~

Полный вывод: [archive18.log](archive18.log).

#### archive19

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '730,950p' packages/jobs/lib/src/job_context.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
    if (identical(error, _owner._pendingCancel) ||
~~~~

Полный вывод: [archive19.log](archive19.log).

#### archive20

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '450,555p' packages/jobs/test/children_test.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
    expect(
~~~~

Полный вывод: [archive20.log](archive20.log).

#### archive21

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat packages/jobs/.dart_tool/package_config.json
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
}
~~~~

Полный вывод: [archive21.log](archive21.log).

#### archive22

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat packages/flutter_solo/pubspec.yaml .gitignore
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
.artifacts/
~~~~

Полный вывод: [archive22.log](archive22.log).

#### archive23

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '1,265p' 'docs/records/2026-09-08[14]-jobs-readme-review.md'
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
rtk proxy sed -n '1,290p' packages/jobs/lib/src/job_base.dart
~~~~

Полный вывод: [archive23.log](archive23.log).

#### archive24

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat packages/jobs/test/observer_test.dart packages/solo/lib/src/job.dart packages/solo/lib/src/job_context.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
}
~~~~

Полный вывод: [archive24.log](archive24.log).

#### archive25

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy rg -n '^##|^###|Вердикт' 'docs/records/2026-09-08[14]-jobs-readme-review.md'
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
1023:## Остальные разрезы
~~~~

Полный вывод: [archive25.log](archive25.log).

#### archive26

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '803,1035p' 'docs/records/2026-09-08[14]-jobs-readme-review.md'
~~~~

Код завершения: `0`. Последняя строка пустая.

Полный вывод: [archive26.log](archive26.log).

#### archive27

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '1,215p' packages/jobs/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  for it.
~~~~

Полный вывод: [archive27.log](archive27.log).

#### archive28

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy cat packages/jobs/README.ru.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
[flutter_solo](https://pub.dev/packages/flutter_solo).
~~~~

Полный вывод: [archive28.log](archive28.log).

#### archive29

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '640,975p' packages/jobs/lib/src/job_base.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  /// finished job does not run.
~~~~

Полный вывод: [archive29.log](archive29.log).

#### archive30

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy rg -n 'onLog|_notify\(|_callHook|_own\(|run\(|onDispose|onDiscard|disown|drop.*Failed|onError' packages/solo/lib/src/solo_base.dart packages/jobs/lib/src/job_context.dart packages/jobs/test/debug_test.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
packages/solo/lib/src/solo_base.dart:573:    SoloBase._callHook(() => _solo.onLog(job, message));
~~~~

Полный вывод: [archive30.log](archive30.log).

#### archive31

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '154,210p' packages/jobs/lib/src/job_context.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  /// // before the job ends and the next one starts.
~~~~

Полный вывод: [archive31.log](archive31.log).

#### archive32

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '299,493p' packages/jobs/README.ru.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  // `start` защищён: движок открывает к нему свою дверь.
~~~~

Полный вывод: [archive32.log](archive32.log).

#### archive33

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '390,448p' packages/jobs/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
clock — the suite of this package is built that way:
~~~~

Полный вывод: [archive33.log](archive33.log).

#### archive34

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy sed -n '1,175p' packages/solo/lib/src/solo_base.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
        }
~~~~

Полный вывод: [archive34.log](archive34.log).

#### read01-handoff-diff

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git diff 4901124..1a0dde2 -- docs/handoff.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
 ```
~~~~

Полный вывод: [read01-handoff-diff.log](read01-handoff-diff.log).

#### read02-ru-diff

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git diff 4901124..1a0dde2 -- packages/jobs/README.ru.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
 ```
~~~~

Полный вывод: [read02-ru-diff.log](read02-ru-diff.log).

#### read03-context-contracts

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
sed -n '395,735p' packages/jobs/lib/src/job_context.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
    }
~~~~

Полный вывод: [read03-context-contracts.log](read03-context-contracts.log).

#### read04-example

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
cat packages/jobs/example/example.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
}
~~~~

Полный вывод: [read04-example.log](read04-example.log).

#### read05-hook-uses

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rg -n 'onLog\(|void _notify|_observed =|beforeChildStart|ThrowingRules' packages/jobs/lib packages/solo/lib packages/jobs/test/support/probe_job.dart packages/solo/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
packages/solo/lib/src/job_context.dart:103:  Cancelled? beforeChildStart(JobBase<Object?> child) {
~~~~

Полный вывод: [read05-hook-uses.log](read05-hook-uses.log).

#### read06-flutter-cause

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/2026-09-09-wave-review`.

~~~~sh
head -n 14 07-flutter-checks.log
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
  error - example/lib/main.dart:55:30 - No associated named super constructor parameter. Try changing the name to the name of an existing named super constructor parameter, or creating such named parameter. - super_formal_parameter_without_associated_named
~~~~

Полный вывод: [read06-flutter-cause.log](read06-flutter-cause.log).

#### read07-base-contract

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
git show 4901124:packages/jobs/lib/src/job_context.dart | sed -n '790,885p'
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
    // around us when there is one, so nesting does not walk the address
~~~~

Полный вывод: [read07-base-contract.log](read07-base-contract.log).

#### read08-remaining-mechanics

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
sed -n '335,390p' packages/jobs/lib/src/job_base.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
        ),
~~~~

Полный вывод: [read08-remaining-mechanics.log](read08-remaining-mechanics.log).

#### read09-test-rule

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
sed -n '150,178p' packages/jobs/test/support/probe_job.dart
~~~~

Код завершения: `0`. Последняя строка пустая.

Полный вывод: [read09-test-rule.log](read09-test-rule.log).

#### read10-stream

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rg -n -C 5 'cancel\(|onCancel|onDispose|onData\(|await result|await.*handler|abandon|handler' packages/jobs/lib/src/job_stream.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
259-          },
~~~~

Полный вывод: [read10-stream.log](read10-stream.log).

#### read11-package-resolution

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rg -n -A 4 '"name": "(jobs|solo|example)"' packages/solo/.dart_tool/package_config.json packages/solo/example/.dart_tool/package_config.json
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
packages/solo/example/.dart_tool/package_config.json-207-    },
~~~~

Полный вывод: [read11-package-resolution.log](read11-package-resolution.log).

#### read12-cursor-anchor

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
sed -n '330,383p' packages/jobs/README.md
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
});
~~~~

Полный вывод: [read12-cursor-anchor.log](read12-cursor-anchor.log).

#### read13-lifecycle-tests

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
sed -n '40,110p' packages/jobs/test/lifecycle_test.dart
~~~~

Код завершения: `0`. Последняя строка:

~~~~text
      async.flushMicrotasks();
~~~~

Полный вывод: [read13-lifecycle-tests.log](read13-lifecycle-tests.log).

#### Первоначальное чтение каталога артефактов

Рабочий каталог: `/Users/user/development/my/solo/.artifacts/jobs-review`.

~~~~sh
rtk proxy ls -la /Users/user/development/my/solo/.artifacts/2026-09-09-wave-review
~~~~

Код завершения: `0`. Последняя строка первоначального вывода:

~~~~text
-rw-r--r--@ 1 user  staff       0 Sep  9 08:52 run.log
~~~~

Вызовы `ls` отсутствующего `packages/flutter_solo/.dart_tool` дали
`No such file or directory`; это ошибка чтения отсутствующего каталога,
а не отказ песочницы.

</details>

## Находки

### 1. Новый пример снятия регистрации закрывает курсор дважды при отмене

**Тяжесть:** Medium.

**Координата:** `packages/jobs/README.md`, раздел `Cleanup`,
пример функции снятия; тот же пример в `packages/jobs/README.ru.md`,
раздел «Уборка». Цитата-якорь:

```dart
final remove = ctx.onDispose(cursor.close);
await ctx.join(cursor.readAll); // closes it at the end
remove();
```

**В чём дело.** По комментарию `readAll` сам закрывает курсор.
Если отмена приходит во время чтения, `join` дожидается этого закрытия,
а затем его повторный `check()` бросает `Cancelled`. До `remove()`
тело не доходит. Регистрация остаётся на стеке, и завершение задачи
снова вызывает `cursor.close`. Для ресурса с неидемпотентным закрытием
это повторное освобождение; в зонде второй вызов бросает ошибку,
которую получает `onError`. Идемпотентность функции снятия здесь не
помогает: её вообще не вызвали. Условие об идемпотентном `cursor.close`
в новом примере отсутствует.

Это дефект добавленного в волну рецепта: реализация `join` выполняет
свой контракт, бросая отмену после ожидания действия.

**Чем подтверждено.** `cursorSnippet()` в [probes.dart](probes.dart)
исполняет эти три строки на неизменённом ядре: `readAll` ждёт 20 мс
и закрывает ресурс; отмена запрашивается на 10-й мс. Без отмены
`closeCalls=1, outcome=Done, onError=0`; с отменой
`closeCalls=2, outcome=Cancelled, onError=1`.
Прочитаны `JobContextBase.join` с `check()` после
`await action()`, `addCleanup` с возвращаемой функцией снятия и
раскрутка стека в `JobBase._execute`.

**Предложение:** выполнить `readAll` и следующий за ним `remove()`
внутри одного action, переданного `join`, чтобы проверка отмены
происходила после снятия регистрации.

**Вердикт:** подтверждена своим зондом: тот же рецепт на неизменённом
ядре даёт `closes=2` при отмене на 10-й мс и `closes=1` без отмены;
`remove()`, перенесённый внутрь действия `join`, даёт `closes=1` на обоих
путях. Взято владельцем и закрыто: в обоих README снятие переехало внутрь
действия, а рядом сказано, почему место решает — отмена, пришедшая по
ходу вызова, бросается после него, и до строки ниже тело не доходит.

### 2. Обещание бесплатного логирования неверно для показанных строк с интерполяцией

**Тяжесть:** Low.

**Координата:** `packages/jobs/README.md`, раздел `Observer`;
`packages/jobs/README.ru.md`, раздел «Наблюдатель». Цитата-якорь:

> `ctx.log` of the fragments above costs nothing until somebody listens.

Один из фрагментов, на которые ссылается утверждение:

```dart
ctx.log('migration failed: $error');
```

**В чём дело.** Новый проход `Object?` устраняет преобразование сообщения
внутри ядра, но интерполяция в аргументе выполняется до входа в `log`.
Поэтому именно показанные вызовы преобразуют `error` в строку даже без
наблюдателя. Если его `toString` бросает, ошибка возникает в теле и
задача заканчивается `Failed`; изоляция хука `onLog` тут не участвует.
В переводе повторено то же неверное обещание: «`ctx.log` во фрагментах
выше ничего не стоит, пока никто не слушает».

**Чем подтверждено.** `eagerMessage()` в [probes.dart](probes.dart)
исполняет точную строку фрагмента с объектом-счётчиком:
без наблюдателя получено `conversions=1, outcome=Done`;
с бросающим преобразованием — `conversions=1, outcome=Failed`.
Для сравнения, `ctx.log(message)` с тем же бросающим объектом даёт
`conversions=0, outcome=Done`. В `JobContextBase.log` сообщение
передаётся как есть; преобразование в контрпримере находится у вызывающего.

**Предложение:** ограничить обещание отсутствием преобразования внутри
ядра и оговорить, что интерполяция аргументов в примерах вычисляется
независимо от наличия слушателя.

**Вердикт:** подтверждена своим зондом: `ctx.log('migration failed:
${Counted()}')` без наблюдателя даёт `conversions=1`. Обещание было моё и
неверное: ядро строки не делает, а вызывающий в показанных фрагментах
делает. Взято владельцем и закрыто: в обоих README обещание сужено до
ядра, а про строку, собранную на месте вызова, сказано прямо — с советом
отдавать объект.

Регрессий реализации `run` и `onLog` в проверенных сценариях не найдено.

Расхождений русского перевода с оригиналом по существу изменённых
фрагментов не найдено; обе находки выше одинаково присутствуют в обоих
языках.
