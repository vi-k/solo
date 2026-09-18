> **Состояние на 2026-09-08:** ревью проведено, все восемь находок
> подтверждены приёмкой — пять своим зондом, три чтением, — взяты
> владельцем и закрыты в `6e2fe9f`. Семь были про текст, восьмая про код.
> **Что это:** независимое ревью README пакета `jobs` свежим взглядом,
> сделано `codex exec` на копии дерева `.artifacts/jobs-review` (`e97d611`).
> **Связанные записи:** 2026-09-03[2]-readme-review.md,
> 2026-09-06[4]-jobs-docs-review.md.
> **Наработки:** задание, стенд, зонды, мутации и журнал команд —
> `.artifacts/2026-09-08-jobs-readme-review/`, вне гита. Ссылки на файлы
> внутри отчёта ведут туда.

## ПРОГОН

Отказов песочницы не было.

Все команды ниже выполнены из
`/Users/user/development/my/solo/.artifacts/jobs-review`, кроме явно отмеченных
запусков из внешнего стенда. Приведены команды дословно, коды завершения и
точные последние строки полученного вывода; пробелы сохранены.
У команды с пустым выводом последней строки нет. Полный полученный от
инструмента вывод сохранён в [command-output.json](command-output.json);
усечение больших ответов инструментом там не восстановлено.

Стенд — [stand/](stand/). Он содержит отдельную копию всех шести файлов
`packages/jobs/lib/`, исходного `pubspec.yaml` и
`example/example.dart`; их соответствие исходникам проверено по байтам,
README и `lib/` также проверены по SHA-256. Исходное дерево не менялось:
начальный и заключительный `git status --short` дали пустой вывод.

Проверки выполнены на Dart 3.13.0. Из README извлечены все 14 блоков Dart.
В [stand/snippets/](stand/snippets/) добавлены импорты, внешние типы и
обёртки функций; тела фрагментов сохранены. `Database` и `CancelToken`
взяты из примера, на который ссылается README; остальные внешние имена
объявлены в обвязке. Подавлены только диагностики неиспользуемых импортов
и локальных переменных. Анализатор нашёл три ошибки типов (находка 2) и
пять предупреждений `unused_shown_name` из обвязки; предупреждения не
включены в находки.

Исполнены скопированный пример, тест из «Testing» и шесть отдельных
зондов. Совместный запуск теста README и зондов завершился
`00:00 +7: All tests passed!`: зонды проверяют наличие описанных ниже
контрпримеров. Остальные фрагменты отдельно не исполнялись; полный набор
тестов пакета не запускался.

Для находки 8 сделана одна подмена исключительно во внешней копии:
из ветки отмены `JobContextBase.join` убран вызов уборщика. Неизменённый
тест README остался зелёным. Подмена снята, соответствие копии оригиналу
проверено. Скрипты подготовки, подмены и проверки сохранены рядом с
отчётом.

Ошибки чтения отсутствующего `.fvmrc` и разбора регулярного выражения
ниже — ошибки команд, а не отказы песочницы.

### Команда 1

````sh
cat /Users/user/.codex/RTK.md
````

Код завершения: `0`. Последняя строка вывода:

````text
```
````

### Команда 2

````sh
rtk proxy cat AGENTS.md
````

Код завершения: `0`. Последняя строка вывода:

````text
номера версии.
````

### Команда 3

````sh
rtk proxy cat /Users/user/.agents/skills/code-critic/SKILL.md
````

Код завершения: `0`. Последняя строка вывода:

````text
Then briefly state what was reviewed and any important limitations, such as unavailable tests, missing call sites, incomplete platform implementations, inability to execute the code, or unresolved external API behavior.
````

### Команда 4

````sh
rtk git status --short
````

Код завершения: `0`. Вывод пуст; последней строки нет.

### Команда 5

````sh
rtk proxy cat docs/handoff.md
````

Код завершения: `0`. Последняя строка вывода:

````text
  движке очередь устроена иначе, решение не перенесено.
````

### Команда 6

````sh
rtk proxy cat docs/architecture.md
````

Код завершения: `0`. Последняя строка вывода:

````text
  `onCancel` и ожидание одного `Completer`, а не `await for`.
````

### Команда 7

````sh
rtk proxy cat docs/conventions.md
````

Код завершения: `0`. Последняя строка вывода:

````text
- Публикация на pub.dev — только по правилам из `AGENTS.md`.
````

### Команда 8

````sh
rtk proxy cat docs/backlog.md
````

Код завершения: `0`. Последняя строка вывода:

````text
  `// ignore:`, чтобы так сделать.
````

### Команда 9

````sh
rtk proxy sed -n '180,420p' docs/handoff.md
````

Код завершения: `0`. Последняя строка вывода пустая.

### Команда 10

````sh
rtk proxy sed -n '421,660p' docs/handoff.md
````

Код завершения: `0`. Последняя строка вывода:

````text
настоящий дефект: README был заготовкой на 55 строк и ставил `^0.1.0`,
````

### Команда 11

````sh
rtk proxy cat docs/architecture.md
````

Код завершения: `0`. Последняя строка вывода:

````text
  `onCancel` и ожидание одного `Completer`, а не `await for`.
````

### Команда 12

````sh
rtk proxy cat packages/jobs/README.md
````

Код завершения: `0`. Последняя строка вывода:

````text
layer of `solo` is [flutter_solo](https://pub.dev/packages/flutter_solo).
````

### Команда 13

````sh
rtk proxy rg --files packages/jobs/lib packages/jobs/test
````

Код завершения: `0`. Последняя строка вывода:

````text
packages/jobs/test/support/journal.dart
````

### Команда 14

````sh
rtk proxy cat packages/jobs/pubspec.yaml packages/jobs/lib/jobs.dart packages/jobs/lib/src/observer.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 15

````sh
rtk proxy sed -n '1,300p' packages/jobs/lib/src/job_context.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
  /// created in when there is none. Written any other way, such a failure
````

### Команда 16

````sh
rtk proxy sed -n '300,700p' packages/jobs/lib/src/job_context.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
    FutureOr<void> Function(T value)? discard,
````

### Команда 17

````sh
rtk proxy sed -n '700,1060p' packages/jobs/lib/src/job_context.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 18

````sh
rtk proxy cat packages/jobs/lib/src/outcome.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 19

````sh
rtk proxy sed -n '1,290p' packages/jobs/lib/src/job_base.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
  var _uncancellableDepth = 0;
````

### Команда 20

````sh
rtk proxy sed -n '290,640p' packages/jobs/lib/src/job_base.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
      _reportUnobserved(outcome);
````

### Команда 21

````sh
rtk proxy sed -n '641,1020p' packages/jobs/lib/src/job_base.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
final class _DeferredJob<T> extends _Job<T> implements DeferredJob<T> {
````

### Команда 22

````sh
rtk proxy cat packages/jobs/lib/src/job_stream.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 23

````sh
rtk proxy cat packages/jobs/example/example.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 24

````sh
rtk proxy rg -n 'retry|timeout|pool|onCancel|log\(|discard|flushTimers|observ' packages/solo/README.md packages/jobs/test/observer_test.dart packages/jobs/test/cleanup_test.dart packages/jobs/test/cancel_test.dart packages/jobs/test/zone_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
packages/jobs/test/zone_test.dart:561:          async.flushTimers();
````

### Команда 25

````sh
rtk proxy ls -la /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review
````

Код завершения: `0`. Последняя строка вывода:

````text
-rw-r--r--@ 1 user  staff       0 Sep  8 18:44 run.log
````

### Команда 26

````sh
rtk proxy which dart
````

Код завершения: `0`. Последняя строка вывода:

````text
/Users/user/fvm/default/bin/dart
````

### Команда 27

````sh
rtk proxy cat packages/jobs/test/observer_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 28

````sh
rtk proxy sed -n '1,215p' packages/jobs/test/cleanup_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
      async.elapse(const Duration(milliseconds: 10));
````

### Команда 29

````sh
rtk proxy sed -n '1,180p' packages/jobs/test/each_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
  test('a stream that cancels the job while it is being listened to', () {
````

### Команда 30

````sh
rtk proxy rg --files packages/solo/lib
````

Код завершения: `0`. Последняя строка вывода:

````text
packages/solo/lib/solo.dart
````

### Команда 31

````sh
rtk proxy sed -n '20,50p' packages/solo/README.md
````

Код завершения: `0`. Последняя строка вывода:

````text
`jobs` README, not here.
````

### Команда 32

````sh
rtk proxy cat .fvmrc packages/jobs/analysis_options.yaml
````

Код завершения: `1`. Последняя строка вывода:

````text
    sort_pub_dependencies: true
````

### Команда 33

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/prepare_stand.py
````

Код завершения: `0`. Последняя строка вывода:

````text
Prepared 14 Dart snippets; copied lib files match source SHA-256 manifest.
````

### Команда 34

````sh
rtk proxy dart --version
````

Код завершения: `0`. Последняя строка вывода:

````text
Dart SDK version: 3.13.0 (stable) (Wed Aug 5 00:28:05 2026 -0700) on "macos_arm64"
````

### Команда 35

````sh
rtk proxy dart pub get --offline
````

Каталог: `/Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/stand`.

Код завершения: `0`. Последняя строка вывода:

````text
Changed 50 dependencies!
````

### Команда 36

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/build_snippets.py
````

Код завершения: `0`. Последняя строка вывода:

````text
Prepared 14 wrapped snippets; README bodies unchanged except moving the first import.
````

### Команда 37

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/build_snippets.py
````

Код завершения: `0`. Последняя строка вывода:

````text
Prepared 14 wrapped snippets; README bodies unchanged except moving the first import.
````

### Команда 38

````sh
rtk proxy dart analyze snippets
````

Каталог: `/Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/stand`.

Код завершения: `3`. Последняя строка вывода:

````text
8 issues found.
````

### Команда 39

````sh
rtk proxy dart test --reporter expanded probes_test.dart snippets/snippet_13.dart
````

Каталог: `/Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/stand`.

Код завершения: `0`. Последняя строка вывода:

````text
00:00 +7: All tests passed!
````

### Команда 40

````sh
rtk proxy dart run example.dart
````

Каталог: `/Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/stand`.

Код завершения: `0`. Последняя строка вывода:

````text
Cancelled(manual)
````

### Команда 41

````sh
rtk proxy rg -n '^(abstract |final |sealed |base |class |enum |extension |  (static |Future|void |[A-Z][A-Za-z0-9_<>, ?]* (get |[A-Za-z0-9_]+\())))|retry|timeout|pool' packages/solo/lib
````

Код завершения: `2`. Последняя строка вывода:

````text
error: unopened group
````

### Команда 42

````sh
rtk proxy rg -n 'cleanup|onData|cancel future|handler.*(wait|run)|onCancel' packages/jobs/test/each_test.dart packages/jobs/test/cancel_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
packages/jobs/test/each_test.dart:1313:          onData!(event);
````

### Команда 43

````sh
rtk proxy sed -n '1,220p' 'docs/records/2026-09-06[4]-jobs-docs-review.md'
````

Код завершения: `0`. Последняя строка вывода:

````text
к фрагменту дословно — тогда стенд наконец совпадёт с текстом.
````

### Команда 44

````sh
rtk proxy sed -n '1,180p' 'docs/records/2026-09-03[2]-readme-review.md'
````

Код завершения: `0`. Последняя строка вывода:

````text
   happens if I only call `close()`? (Answer, from `solo_base.dart:204-241`: you
````

### Команда 45

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/mutate_join.py apply
````

Код завершения: `0`. Последняя строка вывода:

````text
Applied external mutant: join throws Cancelled without invoking its disposer.
````

### Команда 46

````sh
rtk proxy dart test --reporter expanded snippets/snippet_13.dart
````

Каталог: `/Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/stand`.

Код завершения: `0`. Последняя строка вывода:

````text
00:00 +1: All tests passed!
````

### Команда 47

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/mutate_join.py restore
````

Код завершения: `0`. Последняя строка вывода:

````text
Restored external snapshot byte for byte.
````

### Команда 48

````sh
rtk proxy rg -n -e 'retry|timeout|pool' -e '^abstract.*class|^final.*class|^class|^enum' packages/solo/lib
````

Код завершения: `0`. Последняя строка вывода:

````text
packages/solo/lib/src/solo_base.dart:545:final class _SoloJobObserver<S extends Object> implements JobObserver {
````

### Команда 49

````sh
rtk proxy sed -n '275,321p' packages/jobs/test/each_test.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
  test('an event after an error of the stream never reaches onData', () {
````

### Команда 50

````sh
rtk proxy sed -n '1,180p' packages/solo/lib/src/policy.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 51

````sh
rtk proxy sed -n '1,100p' packages/solo/lib/src/solo.dart
````

Код завершения: `0`. Последняя строка вывода:

````text
}
````

### Команда 52

````sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-08-jobs-readme-review/verify_sources.py
````

Код завершения: `0`. Последняя строка вывода:

````text
Verified: README and all 6 lib files unchanged; external core snapshot and example match source.
````

### Команда 53

````sh
rtk proxy git status --short
````

Код завершения: `0`. Вывод пуст; последней строки нет.


## Находки

### 1. Ожидание асинхронного обработчика `each` обещано без исключения для отмены

**Тяжесть:** Medium.

**Координата:** «Cancellation», пункт `ctx.each`:

> An `onData` that returns a future is waited for, and delivery is
> held meanwhile: the events keep their order.

**В чём дело.** При отмене задачи уже работающий асинхронный обработчик
не дожидаются ни `each`, ни сама задача. Она заканчивает тело, выполняет
уборку и завершает `done`, пока обработчик продолжает работу. В частности,
`await ctx.join(write)` внутри `onData` этого не исправляет: он удерживает
обработчик, но внешний `each` уже отпустил тело задачи. Читатель,
полагающийся на приведённую гарантию ожидания и регистрирующий освобождение
ресурса через `onDispose`, может закрыть ресурс до окончания записи в него.

**Чем подтверждено.** В `packages/jobs/lib/src/job_stream.dart`,
`JobStream.each`, метод `deliver` передаёт future обработчика в
`sub.pause`, а завершение самого `each` определяется
`wait(() => done.future)`. Отмена прерывает этот `wait`.
Dartdoc `each` прямо оговаривает, что текущий обработчик продолжает
работу и задача его не ждёт. Зонд
`each ends the job and cleanup while onData still awaits join`
в [stand/probes_test.dart](stand/probes_test.dart) дал:

```text
each: handler started -> database closed -> job finished -> handler finished
```

**Предложение:** рядом с обещанием последовательной доставки указать,
что при отмене текущий асинхронный обработчик остаётся работать и уборка
задачи его не ждёт.

**Вердикт:** подтверждена своим зондом: `cleanup ran -> job finished:
Cancelled(manual) -> handler finished`. Уборка задачи отработала раньше,
чем кончился обработчик, — то есть `dispose`, закрывающий ресурс, закроет
его под пишущим обработчиком. Дартдок `each` эту оговорку держит, README —
нет. Взято владельцем и закрыто в `6e2fe9f`: оговорка стоит в буллете
`ctx.each` обоих README — ждёт доставка, а не задача, и уборка может
закрыть под обработчиком то, во что он ещё пишет.

### 2. Три фрагмента несовместимы с `Database` из Quick start

**Тяжесть:** Medium.

**Координата:** «Cancellation», оба примера `catch`, и «Cleanup»,
первый пример:

> await ctx.join(database.migrate);

**В чём дело.** Quick start вводит миграцию как
`database.migrate(stop)` и отсылает к готовому примеру с фальшивой
`Database`. В следующих фрагментах та же миграция передаётся как
tear-off без токена; смена интерфейса базы нигде не оговорена.
Читатель, продолжающий примеры на предоставленной базе, получает ошибку
типа: метод с обязательным аргументом не является действием без аргументов
для `join`.

**Чем подтверждено.** `JobContext.join<T>` в
`packages/jobs/lib/src/job_context.dart` принимает
`FutureOr<T> Function() action`.
В `packages/jobs/example/example.dart`, на который прямо ссылается
Quick start, объявлен `Future<void> migrate(CancelToken stop)`.
Все три фрагмента проверены именно с этой `Database`, без изменения её
сигнатуры. `dart analyze snippets` сообщил в
`snippet_04.dart`, `snippet_05.dart` и `snippet_07.dart`:

```text
The argument type 'Future<void> Function(CancelToken)' can't be assigned to the parameter type 'FutureOr<dynamic> Function()'.
```

Это несовместимость при продолжении на типах из Quick start; с отдельно
придуманной базой, у которой `migrate()` не принимает аргументов, эти
строки были бы допустимы.

**Предложение:** сохранить в трёх фрагментах вызов через
`() => database.migrate(stop)` с тем же токеном отмены.

**Вердикт:** подтверждена чтением: `example/example.dart:18` объявляет
`Future<void> migrate(CancelToken stop)`, а `README.md:171`, `:183` и
`:304` передают `database.migrate` как tear-off без аргумента. Quick start
на той же базе пишет `() => database.migrate(stop)` (`:59`) и объясняет
зачем (`:93`). Взято владельцем и закрыто в `6e2fe9f`: все три фрагмента
приведены к той же форме вызова, что и Quick start.

### 3. `ctx.log` выполняет пользовательский код даже без наблюдателя

**Тяжесть:** Medium.

**Координата:** «Observer»:

> and does nothing when the job has no observer, so the `ctx.log` of
> the fragments above costs nothing until somebody listens.

**В чём дело.** Вызов `ctx.log(message)` всегда преобразует объект в
строку, даже если наблюдателя нет. Это не только работа вопреки обещанию:
пользовательский `toString`, бросивший исключение, прерывает тело и
превращает задачу в `Failed`. Проверка наличия наблюдателя и защита
вызова его хука происходят уже после преобразования. Это дефект
реализации относительно обещания README и собственного dartdoc
`JobContext.log`; одной правкой формулировки он не устраняется.

**Чем подтверждено.** `JobContextBase.log` в
`packages/jobs/lib/src/job_context.dart` реализован как
`_owner._notifyLog('$message')`; `JobBase._notifyLog` только затем
вызывает `_observer?.onLog` под защитой `_notify`.
Существующий тест `log without an observer is a no-op` передаёт готовую
строку и не проверяет этот случай. Зонд
`log evaluates toString without an observer and can fail the body`
проверил обычное и бросающее преобразования:

```text
log: conversions=1, throwing=Failed(Bad state: message conversion)
```

**Предложение:** отдельной правкой реализации обеспечить проверку
наличия наблюдателя до преобразования сообщения в строку.

**Вердикт:** подтверждена своим зондом: без наблюдателя `conversions=1`, а
бросающий `toString` даёт `Failed(Bad state: message conversion)`.
Единственная находка про код, а не про текст: обещание «no-op without an
observer» стоит и в дартдоке `JobContext.log`, и — с 2026-09-08 — в README.
Лечится проверкой наблюдателя до интерполяции. Взято владельцем и закрыто в
`6e2fe9f` правкой кода: `log` проверяет наблюдателя первым, дартдок
переписан, а тест `log without an observer is a no-op` теперь считает
превращения в строку и кормит `log` объектом, чей `toString` бросает.
2026-09-09 владелец пересмотрел решение: не проверка наблюдателя, а
сквозной проход — `JobObserver.onLog` принимает `Object?`, и строки из
сообщения ядро не делает вовсе.

### 4. Уборка описана как безусловный LIFO, хотя поздняя отмена меняет порядок

**Тяжесть:** Low.

**Координата:** «Cleanup», «How it runs»:

> The engine unwinds the stack in one pass, last
> registration first, after the children and before the outcome

**В чём дело.** Если тело вернуло значение, верхняя регистрация
`discard` сначала пропускается. Пока нижний асинхронный `dispose`
исполняется, задача может быть отменена; тогда пропущенный `discard`
исполнится вторым проходом, уже после нижнего `dispose`.
Следовательно, ни один проход, ни общий обратный порядок регистраций
не гарантированы. При зависимых ресурсах нельзя на основании этого
абзаца заключить, что поздно зарегистрированное значение всегда будет
освобождено раньше своего ранее зарегистрированного окружения.

**Чем подтверждено.** `JobBase._execute` в
`packages/jobs/lib/src/job_base.dart` переносит условные регистрации
в `_skipped` при исходе `Done`, а после первого прохода отдельно
исполняет их, если исход изменился. Существующий тест
`a cancellation arriving during the cleanup still discards`
закрепляет этот порядок. Зонд
`cleanup is not global LIFO when cancellation arrives during dispose`
дал:

```text
cleanup: outer dispose started -> outer dispose ended -> inner discard
```

**Предложение:** оговорить второй проход по пропущенным `discard`
при отмене во время уборки и соответствующее исключение из LIFO.

**Вердикт:** подтверждена своим зондом: `outer dispose start -> outer
dispose end -> inner discard`. Позже зарегистрированный `discard` отработал
после раньше зарегистрированного `dispose`, то есть общего LIFO нет. Взято
владельцем и закрыто в `6e2fe9f`: «How it runs» оговаривает второй проход.

### 5. Указатель на `solo` обещает также retry, timeout и pool

**Тяжесть:** Low.

**Координата:** «Why»:

> There is no state here, no queue, no rules, no retry, no timeout, no
> pool. If you want any of those, take `solo`

**В чём дело.** `any of those` относится ко всему списку из шести
возможностей, хотя `solo` добавляет состояние, очередь и правила.
Разработчик, пришедший за retry, timeout или pool, получает указатель
на пакет, у которого эти возможности также отсутствуют.
Это противоречит и последнему разделу данного README, где добавления
`solo` перечислены без этих трёх пунктов.

**Чем подтверждено.** Прочитаны публичные экспорты
`packages/jobs/lib/jobs.dart`, классы ядра и дополнительная поверхность
`Solo` и `Policy` в `packages/solo/lib/src/`; поиск по `solo/lib`
не нашёл `retry`, `timeout` или `pool`.
`packages/solo/README.md`, «Why», прямо говорит:
`no retry, no timeout, no pool`.
В данном README раздел «solo» называет только
`a state, a queue and rules`.

**Предложение:** ограничить рекомендацию `solo` состоянием, очередью
и правилами.

**Вердикт:** подтверждена чтением: `packages/solo/README.md:40` сам говорит
«no retry, no timeout, no pool», а раздел «solo» этого README обещает от
него «a state, a queue and rules». Взято владельцем и закрыто в `6e2fe9f`:
за первыми тремя теперь зовут к `solo`, а про повторы, таймауты и пул
сказано, что их нет и у него.

### 6. «Наблюдать исход» — ключевое условие, для которого не дано определения

**Тяжесть:** Low.

**Координата:** «Why»:

> And a `Failed` outcome nobody observed goes to the zone
> that created the job

Связанный пример — «Observer»:

> void onFinish(Job<Object?> job) => print('$job: ${job.outcome}');

**В чём дело.** README многократно связывает доставку ошибки в зону с
тем, наблюдал ли кто-нибудь исход, но не задаёт точный критерий.
Чтение `job.outcome`, показанное в собственном примере наблюдателя,
не считается наблюдением; вызов `onError` тоже не считается.
Читатель может уже прочитать и записать `Failed` из `onFinish`,
а затем всё равно получить ту же ошибку как необработанную.
Слова про `job.ignore()` не объясняют, чем чтение `outcome`
отличается от обращения к `done` и `value`, и когда ещё можно
предотвратить доставку в зону.

**Чем подтверждено.** В `JobBase`,
`packages/jobs/lib/src/job_base.dart`, флаг `_observed` устанавливают
только getter `done`, getter `value` и `ignore()`.
Getter `outcome` просто возвращает поле, `cancel()` ждёт через
`whenDone`; `_reportUnobserved` проверяет флаг следующей микротаской
после завершения. Dartdoc `Job` перечисляет критерий явно.
Зонд `reading outcome at onFinish does not observe a failure`
с прочитавшим исход наблюдателем дал:

```text
outcome: read=Failed(Bad state: body failure), zone=Bad state: body failure
```

**Предложение:** в «Outcomes» перечислить `done`, `value` и
`ignore()` как наблюдение и уточнить, что `outcome`, хуки и ожидание
`cancel()` его не заменяют, с указанием срока до следующей микротаски.

**Вердикт:** подтверждена своим зондом: наблюдатель прочитал `Failed(Bad
state: boom)` в `onFinish`, и та же ошибка ушла в зону. README опирается на
«observed» дважды (`:19` и `:410`) и нигде не говорит, что им считается;
дартдок `Job` говорит. Взято владельцем и закрыто в `6e2fe9f`: «Outcomes»
называет `done`, `value` и `ignore()` и говорит, что `outcome`, `onFinish`
и ожидание `cancel()` не наблюдают ничего.

### 7. Гарантия для `unattended` дана раньше обязательного условия о наблюдателе

**Тяжесть:** Low.

**Координата:** «Cancellation», пункт `ctx.unattended`:

> reaches `onError` instead of the process.

**В чём дело.** На этом месте ещё не объяснён `JobObserver`, и
единственная полностью показанная конфигурация задачи — без него.
В такой конфигурации ошибка `unattended` поступает в зону создания
задачи; в обычной корневой зоне она остаётся необработанной.
Поэтому безусловное `instead of the process` неверно для настройки
по умолчанию. Ниже, после разделов «Children» и «Cleanup», «Observer»
даёт правильное условие: при отсутствии наблюдателя ошибка идёт прямо
в зону. До этого места рецепт
`ctx.onCancel(() => ctx.unattended(device.stop))` и объяснение его
гарантии оставляют это условие скрытым.

**Чем подтверждено.** `JobContextBase._unattendedError` вызывает
`notifyError`; `JobBase.notifyError` при `observer == null`
передаёт обычную ошибку в `_toZone`, а тот вызывает
`_zone.handleUncaughtError`.
Зонд `unattended without observer routes errors to the zone`
исполнен в перехватывающей зоне, поэтому процесс стенда не завершался:

```text
unattended: outcome=Done(null), zone=Bad state: background failure
```

**Предложение:** уже в пункте `ctx.unattended` назвать наблюдателя
условием перехвата ошибки и указать маршрут в зону при его отсутствии.

**Вердикт:** подтверждена своим зондом: без наблюдателя провал `unattended`
пришёл в зону. Буллет обещает `onError` безусловно, а условие «or straight
to the zone when there is none» стоит на сто восемьдесят строк ниже. Взято
владельцем и закрыто в `6e2fe9f`: буллет называет наблюдателя и зону прямо
на месте.

### 8. Тест из «Testing» не проверяет обещанное закрытие базы

**Тяжесть:** Low.

**Координата:** «Testing»:

> test('a cancelled open still closes what it opened', () {

Единственная проверка результата:

> expect(job.outcome, isA<Cancelled>());

**В чём дело.** Тест проверяет отмену задачи, но не проверяет ни факт,
ни количество закрытий базы. Он остаётся зелёным при утечке открытого
значения, хотя его название обещает проверку именно уборки. Для читателя
это первый образец тестирования главной гарантии `discard`, и
показанная проверка не различает работающую уборку и её отсутствие.

**Чем подтверждено.** В `JobContextBase.join`,
`packages/jobs/lib/src/job_context.dart`, при отмене после получения
значения вызывается `await _dispose(disposer, result)`, затем
перебрасывается `Cancelled`. Во внешней копии удалён только этот
вызов; исходное дерево и сам тест README не менялись.
`dart test --reporter expanded snippets/snippet_13.dart` с подменой
завершился:

```text
00:00 +1: All tests passed!
```

В исходном запуске база печатала `database closed`; при подмене
этой строки не было. Скрипт [mutate_join.py](mutate_join.py) сохраняет
точную подмену; после опыта копия восстановлена побайтно.

**Предложение:** добавить в пример теста проверку, что полученный
экземпляр базы закрыт ровно один раз.

**Вердикт:** подтверждена чтением: единственная проверка теста —
`expect(job.outcome, isA<Cancelled>())`; закрытие базы не проверяется, хотя
имя теста обещает именно его. Взято владельцем и закрыто в `6e2fe9f`: в
примере появился счётчик закрытий и `expect(closed, 1)`.

## Остальные разрезы

Отдельных находок по осиротевшим примерам, повторам и внутренним отсылкам
в отсутствующие разделы не найдено.

`packages/jobs/README.ru.md` не проверялся.

