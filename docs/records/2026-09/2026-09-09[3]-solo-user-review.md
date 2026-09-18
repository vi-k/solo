> **Состояние на 2026-09-09:** ревью проведено, все одиннадцать находок
> подтверждены приёмкой и закрыты: четвёртая — в `e6e850a` вместе с
> находкой 6 ревью кода, остальные — в `3049d98`.
> **Что это:** ревью пакета `solo` глазами его пользователя перед первой
> публикацией.
> **Связанные записи:** 2026-09-06[5]-solo-docs-review.md,
> 2026-09-08[14]-jobs-readme-review.md,
> 2026-09-09[2]-solo-project-review.md.
> **Наработки:** задание, логи и извлечённые фрагменты —
> `.artifacts/2026-09-09-solo-user-review/`, вне гита.

## Приёмка

Ревьюер вынул все 58 Dart-фрагментов, но не скомпилировал ни одного:
песочница не пустила `dart` — бинарь в PATH из FVM, а я не дал
`--add-dir ~/fvm`. Все находки получены чтением, и все одиннадцать
проверены мной: четыре поведенческих — зондом (платёж под `close`,
`loading` после провала, поздняя ошибка без наблюдателя, отмена
непрерываемой задачи в очереди), остальные — чтением кода по именам.
Ни одна не отпала.

Отдельно измерено то, чего в находке 1 не было: с `cancellable: false`
задача действительно возвращает `Done(receipt)` и состояние доходит до
`Paid` — то есть обещание документа исполнимо, но не той конструкцией,
которая в нём стояла.

## ПРОГОН

**Компиляционная часть не выполнена:** обе попытки запустить `dart --version` завершились отказом записи во Flutter SDK. Повтор сделан ровно один раз. Другой исполняемый файл SDK, перенос SDK, изменение переменных окружения и повышение прав для обхода не использовались. После второго отказа команды Dart/Flutter больше не запускались. Это ограничение проверки, а не дефект пакета.

Вынуты **все 27 блоков README** и **все 19 блоков vs-bloc**, а также блоки README примера и dartdoc публичной поверхности, включая реэкспорт ядра:

| Источник | Всего блоков | Dart | Успешно скомпилировано |
| --- | ---: | ---: | ---: |
| `packages/solo/README.md` | 27 | 24 | 0 — не запускалось |
| `packages/solo/doc/vs-bloc.md` | 19 | 19 | 0 — не запускалось |
| `packages/solo/example/README.md` | 2 | 0 | неприменимо |
| Dartdoc `packages/solo/lib/` | 2 | 2 | 0 — не запускалось |
| Реэкспортируемый dartdoc `packages/async_job/lib/` | 13 | 13 | 0 — не запускалось |
| **Итого** | **63** | **58** | **0 из 58; попыток собственно компиляции — 0** |

Остальные пять блоков — четыре shell-фрагмента и образец текстового вывода. Они сохранены, но как инструкции установки/запуска не исполнялись.

[snippets.json](snippets.json) содержит перечень, исходный документ, порядковый номер блока, путь и SHA-256 извлечённого текста. Сам текст лежит в [snippets/](snippets/); у dartdoc снят только префикс `///`. [extract.py](extract.py) воспроизводит извлечение. Проверка [check_artifacts.py](check_artifacts.py) выполнена: хеши 63 файлов совпали, каждая исходная строка всех 58 Dart-блоков присутствует в 50 подготовленных файлах стендов. **Эта Python-проверка не проверяет Dart-синтаксис, типы или поведение.**

[build_stands.py](build_stands.py) подготовил обвязку README и dartdoc в [stand/](stand/), двух Flutter-блоков в [flutter_stand/](flutter_stand/). Для сравнения использован существующий `tool/doc_snippets.py`: он подготовил 16 файлов для 19 блоков в [vs_bloc_stand/](vs_bloc_stand/). Добавлены импорты, `main`, контекст класса/тела и явно отсутствующие предметные типы (`ProfileApi`, `Screen`, `Database` и другие); их заглушки видны в генераторе. Смешанный блок с `Journal` и вызовом `test` разделён границей `main`, импорт debounce помещён среди импортов, тела примеров сохранены. Заявления «собралось» из наличия этих файлов не следует.

Все зависимости стендов на `solo` и `async_job` направлены к исходникам данного клона; это подготовка к проверке по указанному источнику правды, не проверка размещённого hosted-архива. [example_copy/](example_copy/) содержит копию примера с внешним pubspec для стенда. [stand/probes.dart](stand/probes.dart) содержит девять отдельных зондов; их имена приведены у находок. **Они также не компилировались и не выполнялись; ожидаемые следствия ниже выведены из кода, а не сняты с их вывода.**

Прочитаны README, сравнение, пример, публичные объявления и реализация `solo` и реэкспортированного ядра; кандидаты сверены с относящимися к ним существующими тестами. Версия `solo` в pubspec — `0.2.0`, описание называет последовательные задачи, владение состоянием, правила и отмену, topics — `state-management`, `async`, `cancellation`, `concurrency`. CHANGELOG обозначает её первым публичным релизом и явно говорит, что `0.1.0` не публиковалась. Эти сведения взяты из файлов. Вид живой страницы pub.dev, работоспособность внешних URL, реальные трассы bloc, установка зависимостей, тесты пакета и примера, сборка Flutter, генерация dartdoc и публикационный dry-run в этой сессии **не проверены**. Версия установленного SDK также не получена.

### Отказы песочницы — дословно

Первая попытка `rtk proxy dart --version`, exit code 1:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.56303: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

Единственный повтор той же команды, exit code 1:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.56946: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

### Выполненные команды

Ниже записана каждая выполненная shell-команда дословно, с кодом завершения и последней строкой возвращённого вывода. Порядок внутри пакетов параллельных чтений — порядок их перечисления при запуске. Рабочий каталог всех команд: `/Users/user/development/my/solo/.artifacts/solo-review-user`. У пустого вывода последней строки нет. Первое чтение сделано до получения инструкции о префиксе RTK; далее использован `rtk proxy`, сохраняющий вывод команды. Некоторые большие чтения были усечены инструментом по объёму; нужные участки дополнительно прочитаны адресно. Записи прошлых ревью и их отчёты о тестах не засчитаны как результаты этой сессии.

Файлы стендов, зондов и отчёта созданы инструментом `apply_patch` и приведёнными ниже Python-скриптами только внутри разрешённого каталога артефактов. Документы и код клона не редактировались; git-команды из запретного списка не выполнялись.

<details>
<summary>1. Команда; exit code 0</summary>

```sh
cat /Users/user/.codex/RTK.md /Users/user/.agents/skills/code-critic/SKILL.md
```

Последняя строка:

```text
Then briefly state what was reviewed and any important limitations, such as unavailable tests, missing call sites, incomplete platform implementations, inability to execute the code, or unresolved external API behavior.
```

</details>

<details>
<summary>2. Команда; exit code 0</summary>

```sh
rtk proxy cat AGENTS.md
```

Последняя строка:

```text
номера версии.
```

</details>

<details>
<summary>3. Команда; exit code 0</summary>

```sh
rtk proxy cat docs/handoff.md
```

Последняя строка:

```text
  движке очередь устроена иначе, решение не перенесено.
```

</details>

<details>
<summary>4. Команда; exit code 0</summary>

```sh
rtk proxy cat docs/architecture.md
```

Последняя строка:

```text
  `onCancel` и ожидание одного `Completer`, а не `await for`.
```

</details>

<details>
<summary>5. Команда; exit code 0</summary>

```sh
rtk proxy cat docs/conventions.md
```

Последняя строка:

```text
- Публикация на pub.dev — только по правилам из `AGENTS.md`.
```

</details>

<details>
<summary>6. Команда; exit code 0</summary>

```sh
rtk proxy cat docs/backlog.md
```

Последняя строка:

```text
  `// ignore:`, чтобы так сделать.
```

</details>

<details>
<summary>7. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '1,240p' docs/handoff.md
```

Последняя строка:

```text
  `ctx.onCancel`, и на нём видно, чем `join` отличается от `uncancellable`
```

</details>

<details>
<summary>8. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '241,480p' docs/handoff.md
```

Последняя строка:

```text
имени `unattended`. Она прошла независимое ревью двумя ревьюерами
```

</details>

<details>
<summary>9. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '481,720p' docs/handoff.md
```

Последняя строка:

```text
задачу не смотрят, потому что стеречь нечего, а терять есть что.
```

</details>

<details>
<summary>10. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '721,940p' docs/handoff.md
```

Последняя строка:

```text
пакетах — `sdk: ^3.6.0`.
```

</details>

<details>
<summary>11. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '941,1160p' docs/handoff.md
```

Последняя строка:

```text
  движке очередь устроена иначе, решение не перенесено.
```

</details>

<details>
<summary>12. Команда; exit code 0</summary>

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-user status --short
```

Вывод пуст; последней строки нет.

</details>

<details>
<summary>13. Команда; exit code 0</summary>

```sh
rtk proxy rg --files -g AGENTS.md -g '*.dart' -g '*pub*' -g '*CHANGELOG*' -g '*README*' packages/solo packages/async_job tool
```

Последняя строка:

```text
packages/solo/test/support/test_solo.dart
```

</details>

<details>
<summary>14. Команда; exit code 0</summary>

```sh
rtk proxy cat 'docs/records/2026-09-06[5]-solo-docs-review.md' 'docs/records/2026-09-08[14]-jobs-readme-review.md'
```

Последняя строка:

```text

```

</details>

<details>
<summary>15. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/README.md
```

Последняя строка:

```text
```
```

</details>

<details>
<summary>16. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/pubspec.yaml packages/solo/CHANGELOG.md packages/solo/.pubignore packages/solo/example/README.md packages/solo/example/pubspec.yaml packages/solo/lib/solo.dart packages/async_job/lib/async_job.dart
```

Последняя строка:

```text
export 'src/observer.dart';
```

</details>

<details>
<summary>17. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/lib/src/solo.dart packages/solo/lib/src/job.dart packages/solo/lib/src/job_context.dart packages/solo/lib/src/queue.dart packages/solo/lib/src/policy.dart packages/solo/lib/src/observer.dart packages/solo/lib/src/solo_cancel_reason.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>18. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/lib/src/solo_base.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>19. Команда; exit code 0</summary>

```sh
rtk proxy cat tool/doc_snippets.py
```

Последняя строка:

```text
print('wrote', len(FILES), 'files under', ROOT)
```

</details>

<details>
<summary>20. Команда; exit code 1</summary>

```sh
rtk proxy dart --version
```

Последняя строка:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

</details>

<details>
<summary>21. Команда; exit code 0</summary>

```sh
rtk proxy ls -la /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review
```

Последняя строка:

```text
-rw-r--r--@  1 user  staff       0 Sep  9 09:46 run.log
```

</details>

<details>
<summary>22. Команда; exit code 1</summary>

```sh
rtk proxy dart --version
```

Последняя строка:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

</details>

<details>
<summary>23. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/async_job/lib/src/job_context.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>24. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/async_job/lib/src/job_base.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>25. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/async_job/lib/src/job_stream.dart packages/async_job/lib/src/outcome.dart packages/async_job/lib/src/observer.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>26. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/example/lib/src/camera_controller.dart packages/solo/example/lib/src/camera_state.dart packages/solo/example/lib/src/fake_camera_hardware.dart packages/solo/example/bin/main.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>27. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/doc/vs-bloc.md
```

Последняя строка:

```text
the sample.
```

</details>

<details>
<summary>28. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '400,500p' packages/solo/README.md
```

Последняя строка:

```text

```

</details>

<details>
<summary>29. Команда; exit code 0</summary>

```sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/extract.py
```

Последняя строка:

```text
EXTRACTED 63 fenced blocks; 58 Dart blocks; compiled=0 (Dart preflight blocked)
```

</details>

<details>
<summary>30. Команда; exit code 0</summary>

```sh
rtk proxy python3 tool/doc_snippets.py /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/vs_bloc_stand
```

Последняя строка:

```text
wrote 16 files under /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/vs_bloc_stand
```

</details>

<details>
<summary>31. Команда; exit code 0</summary>

```sh
rtk proxy rg -n 'late|homeless|onError|rule|uncancellable|not cancellable|queued' packages/solo/test/unobserved_failure_test.dart packages/solo/test/unattended_test.dart packages/solo/test/cancellable_test.dart packages/solo/test/policy_test.dart packages/solo/test/each_test.dart packages/solo/test/disposal_test.dart packages/solo/example/test/camera_controller_test.dart
```

Последняя строка:

```text
packages/solo/test/cancellable_test.dart:162:      expect(queued.outcome, isA<Done<void>>());
```

</details>

<details>
<summary>32. Команда; exit code 0</summary>

```sh
rtk proxy rg -n 'discard|second pass|during the cleanup|cancelled.*cleanup|handler.*running|unwatched' packages/async_job/test/cleanup_test.dart packages/async_job/test/each_test.dart
```

Последняя строка:

```text
packages/async_job/test/cleanup_test.dart:832:        return ctx.wait(() => resource, discard: (value) {});
```

</details>

<details>
<summary>33. Команда; exit code 0</summary>

```sh
rtk proxy cat /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/snippets.json
```

Последняя строка:

```text
]
```

</details>

<details>
<summary>34. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/test/cancellable_test.dart packages/solo/example/test/camera_controller_test.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>35. Команда; exit code 0</summary>

```sh
rtk proxy rg -n 'zone|late|observer|throw|rule' packages/solo/test/zone_test.dart packages/solo/test/unobserved_failure_test.dart packages/solo/test/on_cancel_test.dart
```

Последняя строка:

```text
packages/solo/test/zone_test.dart:283:          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
```

</details>

<details>
<summary>36. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '160,205p' packages/async_job/test/cleanup_test.dart
```

Последняя строка:

```text
        try {
```

</details>

<details>
<summary>37. Команда; exit code 0</summary>

```sh
rtk proxy rg -n 'cancel|handler|finish|wait' packages/async_job/test/each_test.dart
```

Последняя строка:

```text
1308:    bool? cancelOnError,
```

</details>

<details>
<summary>38. Команда; exit code 0</summary>

```sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/build_stands.py
```

Последняя строка:

```text
PREPARED 58 Dart fragments in contextual stands; none compiled or executed
```

</details>

<details>
<summary>39. Команда; exit code 0</summary>

```sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/check_artifacts.py
```

Последняя строка:

```text
ARTIFACT CHECK: 63 extracted hashes match; all lines of 58 Dart blocks occur in 50 prepared files; Dart compilation NOT performed
```

</details>

<details>
<summary>40. Команда; exit code 0</summary>

```sh
rtk proxy cat packages/solo/test/zone_test.dart
```

Последняя строка:

```text
}
```

</details>

<details>
<summary>41. Команда; exit code 0</summary>

```sh
rtk proxy sed -n '500,550p' packages/async_job/test/each_test.dart
```

Последняя строка:

```text
      controller = StreamController<int>.broadcast(
```

</details>

<details>
<summary>42. Команда; exit code 0</summary>

```sh
rtk proxy rg -n 'ProfileApi|FakeProfileApi|import|onDispose|onDiscard|ctx.log|uncancellable|Always await' packages/solo/README.md
```

Последняя строка:

```text
1023:          ctx.log('captured $photo');
```

</details>

<details>
<summary>43. Команда; exit code 0</summary>

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-user status --short
```

Вывод пуст; последней строки нет.

</details>

<details>
<summary>44. Команда; exit code 0</summary>

```sh
rtk proxy python3 /Users/user/development/my/solo/.artifacts/2026-09-09-solo-user-review/check_report.py
```

Последняя строка:

```text
REPORT CHECK: exact header; 11 findings (7 Medium, 4 Low); one verdict each; sandbox refusals and unexecuted compilation explicit
```

</details>

<details>
<summary>45. Команда; exit code 0</summary>

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-user status --short
```

Вывод пуст; последней строки нет.

</details>

Начальная проверка `git status --short` вернула пустой вывод. Окончательная проверка приведена в конце журнала команд; её результат — пустой вывод, exit code 0.

## Находки

Все выводы ниже получены чтением текущего кода. Ссылки на существующие тесты означают, что прочитан их сценарий и ожидаемый результат, **а не что тест прошёл в этой сессии**. Девять новых зондов находятся в `stand/probes.dart`; ни один не скомпилирован и не запущен.

### 1. Рецепт платежа сообщает «не оплачено» после состоявшегося списания

**Тяжесть:** Medium.

**Координата:** `packages/solo/doc/vs-bloc.md`, «5. You cannot await your own event», пояснение после `handlePayRequest`:

> `cancel` and `close` are refused while
> it runs and `close` waits, so the job comes back `Done(receipt)` for a
> payment that really happened

Код-якорь:

```dart
final receipt = await ctx.uncancellable(() => _api.pay(order));
ctx.emit(Paid(receipt));
return receipt;
```

**Механика.** Вызвать `close()` после начала `_api.pay`, но до получения квитанции. Отмена удерживается до выхода из секции, затем применяется. Первый следующий `ctx.emit` бросает `Cancelled(closed)`: `Paid` не записывается, квитанция не возвращается, состояние остаётся `Paying`. Показанный `handlePayRequest` отвечает `{'paid': false, 'cancelled': 'closed'}`, хотя API уже завершил списание. Обещание основано на прежней семантике окончательного отказа от отмены. Перенос одного `emit` внутрь секции сам по себе не обеспечит обещанный `Done`: удержанная отмена всё равно определит исход задачи.

**Чем подтверждено.** `JobContextBase.uncancellable` вызывает `leaveUncancellable` в `finally`; `JobBase.leaveUncancellable` передаёт удержанную отмену в `cancelWith`; `_SoloContext.emit` проверяет её до записи; `JobBase._execute` выбирает `_pendingCancel ?? outcome`. Тесты `an uncancellable step holds the cancel until the step ends` и `close waits for an uncancellable step and lands after it` в `packages/solo/test/cancellable_test.dart` закрепляют именно отмену после секции. Подготовлен зонд `payment_close`, использующий оба исходных фрагмента раздела без изменения тела.

**Предложение:** для обещанного `Done(receipt)` сделать платёж задачей с `cancellable: false` и прямо оговорить, что в `solo` это защищает её от ручной отмены ещё в очереди.

**Вердикт ревьюера:** подтверждается реализацией и содержимым тестов; исполняемый зонд не запускался.

**Вердикт:** подтверждена зондом: `close()` по ходу списания даёт
`Cancelled(closed)`, состояние остаётся прежним, чек потерян. Заодно
измерено, чего в находке не было: с `cancellable: false` та же задача
даёт `Done(receipt)` и состояние доходит до `Paid`. Закрыто в `3049d98`:
`cancellable: false` в рецепте, и оба абзаца переписаны — секция
придерживает отмену, а не отказывает в ней.

### 2. README обещает ожидание обработчика `each`, не называя исключение при отмене

**Тяжесть:** Medium.

**Координата:** `packages/solo/README.md`, Concepts → «Following a stream»:

> A callback that returns a future is waited for,
> and delivery is held meanwhile

Связанный фрагмент, Concepts → «Rules»:

```dart
(ctx) => ctx.each(camera.frames, store),
```

**Механика.** Если `store` ещё пишет очередной кадр, а `keepWhile` отменяет запись, ожидание `each` заканчивается сразу. Тело задачи завершается, её уборщики могут закрыть ресурс и очередь может запустить следующую задачу, пока прежний `store` продолжает работу. Это влияет именно на показанный сценарий записи: последовательная доставка кадров не означает ожидания текущей записи при отмене. Оговорка, что сама операция не останавливается, есть выше для `wait`, но здесь README вновь даёт безусловное обещание ожидания callback.

**Чем подтверждено.** `JobStream.each` при отмене вызывает `letGoOfStream`, а ожидает `wait(() => done.future)`. Future обработчика используется для `sub.pause`, в список детей задачи она не попадает. Dartdoc этого же реэкспортированного `each` прямо говорит: `neither this call nor the job waits for it`. Тест `a cancellation stops the playback of the early events` в `packages/async_job/test/each_test.dart` оставляет работающий обработчик до его конца. Подготовлен зонд `each_cleanup`, фиксирующий порядок обработчика, уборки и исхода.

**Предложение:** оговорить непосредственно в «Following a stream», что отмена не ждёт текущий асинхронный callback и уборка задачи может освободить используемый им ресурс.

**Вердикт ревьюера:** README не передаёт существенное ограничение, уже записанное в dartdoc; зонд не запускался.

**Вердикт:** подтверждена — механика та же, что вчера замерена в ядре
(`2026-09-08[14]-jobs-readme-review.md`, находка 1). Закрыто в `3049d98`:
в «Following a stream» обоих языков сказано, что ждёт доставка, а не
задача.

### 3. Первый контроллер оставляет `loading: true` после ошибки, а экран лишается кнопки повтора

**Тяжесть:** Medium.

**Координата:** `packages/solo/README.md`, Quick start → `ProfileController.load`:

```dart
ctx.emit(ctx.state.copyWith(loading: true));
final name = await ctx.wait(api.fetchName);
ctx.emit(Profile(name: name));
```

Связанный раздел Flutter → `_ProfileScreenState.build`:

```dart
builder: (context, state, _) => state.loading
    ? const CircularProgressIndicator()
    : ElevatedButton(
```

**Механика.** Первый `fetchName` завершается ошибкой. Последний `emit` не выполняется, `Profile.loading` остаётся `true`. Показанный экран получает `Failed`, выводит SnackBar и продолжает показывать индикатор вместо единственной кнопки. Восстановить загрузку из этого интерфейса нельзя. При отмене уже начавшейся загрузки флаг остаётся таким же; фрагмент ручной отмены в Quick start этого не показывает, поскольку отменяет задачу до первого микротаска.

**Чем подтверждено.** В исходном `ProfileController.load` нет обработки ошибки или хука, сбрасывающего флаг; `JobContextBase.wait` передаёт ошибку действия в тело, `JobBase._execute` формирует `Failed`, а `SoloBase.onFinish` по умолчанию пуст. README прямо предлагает в Flutter сохранить те же задачи, заменив базовый класс. Подготовлен зонд `profile_failure` с исходными `Profile` и `ProfileController` и API, бросающим исключение.

**Предложение:** дополнить первый контроллер восстановлением флага загрузки на неуспешном завершении, включая отмену, и использовать эту же версию в примере экрана.

**Вердикт ревьюера:** дефект показанного примера, а не механизма исходов; зонд не запускался.

**Вердикт:** подтверждена зондом: после провала действия состояние
осталось с поднятым флагом. Закрыто в `3049d98`: флаг снимается в
`onFinish`, и сказано, почему не в теле — провал пропустит строки ниже, а
после отмены `emit` бросит.

### 4. Камера объявляет успешное освобождение после ошибки дочернего закрытия

**Тяжесть:** Medium.

**Координата:** `packages/solo/README.md`, Example → `CameraController.dispose`; `packages/solo/example/lib/src/camera_controller.dart`, `dispose` и `reopen`:

```dart
await ctx.run(_closeCameraJob()).done;
```

Обещание README, «`dispose()` is a job; `close()` is the end of the controller»:

> `dispose()` puts the hardware back

**Механика.** После успешного `init` установить у предоставленного `FakeCameraHardware` значение `failures['close']`. Дочернее закрытие закончится `Failed`, однако `done` вернёт этот исход обычным значением, которое родитель проигнорирует. `dispose` запишет `Disposed` и сам завершится `Done`. Показанный внешний `switch` попадёт в ветку `disposed`, а не `failed`. В `reopen` то же игнорирование разрешает `open` после неудачного `close`. Хук ошибки ребёнка вызывается, но он не исправляет исход и состояние родителя; чтение `done` также снимает маршрут ненаблюдённого отказа в зону.

**Чем подтверждено.** `FakeCameraHardware._operation` действительно поддерживает ошибку операции `close`; `JobBase.done` возвращает `Future<Outcome<T>>`, а `_execute` ждёт детей без переноса их `Failed` в родителя. В обоих методах примера исход ребёнка не проверяется. Тест `a failure while reopening leaves the camera broken` проверяет ошибку `open`, не ошибку дочернего `close`. Подготовлен зонд `camera_close_failure` против копии исходного примера.

**Предложение:** проверять исход дочернего закрытия или ожидать его `value`, прежде чем объявлять `Disposed` либо начинать повторное открытие.

**Вердикт ревьюера:** дефект кода пользовательского примера при поддерживаемом фейком отказе; зонд не запускался.

**Вердикт:** подтверждена прогоном на примере, вместе с находкой 6 ревью
кода; закрыто в `e6e850a`.

### 5. Несколько разделов обещают остановить ошибку в `onError`, хотя стандартный маршрут ведёт в зону

**Тяжесть:** Medium.

**Координата:** `packages/solo/README.md`, Errors, последний абзац:

> an action that `wait` stopped waiting for
> and that fails later is reported to `onError` and stops there.

Тот же смысл в «Rules that are not visible in signatures», абзац о бросившем правиле:

> `onError` in a controller is the end of the line.

И Concepts → «Cancellation», о `unattended`:

> reaches `onError` instead of the process.

**Механика.** В обычном `Solo`, без глобального observer и без переопределения хука, отменить задачу в `ctx.wait`, затем завершить оставленную операцию ошибкой. Отмена задачи не скрывает позднюю ошибку: она идёт в зону создания задачи, даже если её исход прочитан через `done`. Такой же маршрут у ошибки `keepWhile` при внешнем изменении состояния и у `unattended`. Это не тот случай, когда само тело бросает ошибку после пометки отмены: у ошибки тела действительно другой маршрут. В README уже есть правильное условие для `unattended` в Errors и для уборщиков в Concepts, но процитированные обещания ему противоречат.

**Чем подтверждено.** `JobContextBase._race.forward` при позднем отказе вызывает `notifyError`; `_SoloJob.notifyError` устанавливает `_homeless`; стандартный `SoloBase.onError` при `observer == null` вызывает `_reportToZone`; `JobBase._toZone` исключает только объект `Cancelled`, а не все ошибки отменённой задачи. `SoloBase._reevaluate` использует тот же маршрут. В `packages/solo/test/zone_test.dart` прочитаны тесты `a homeless error with no observer reaches the zone`, `a global observer switches the default route off` и `a rule that throws reaches the zone`. Зонд `homeless_errors` подготовлен именно для позднего отказа `wait`.

**Предложение:** во всех этих местах указать условие перехвата observer/переопределённым хуком и сохранить различие между ошибкой тела после отмены и поздним отказом оставленного действия.

**Вердикт ревьюера:** устаревшие обещания противоречат действующему стандартному обработчику; зонд не запускался.

**Вердикт:** подтверждена зондом: без наблюдателя поздний провал ушёл в
зону. Закрыто в `3049d98` вместе с находкой 8 ревью кода: оба обещания
получили условие.

### 6. Рецепт аналога `BlocListener` занимает очередь экрана на весь срок подписки

**Тяжесть:** Medium.

**Координата:** `packages/solo/README.md`, Recipes → «Following another controller»:

> The answer to `BlocListener` for a
> controller rather than a screen: a long-lived job over the other one's
> stream.

Код-якорь:

```dart
Job<void> follow() => run<Screen, void>(
      key: 'follow',
      (ctx) => ctx.each(
        session.stream,
```

**Механика.** Запустить `screen.follow()`, затем поставить обычную задачу этого же `ScreenController`. Пока сессия существует и её stream открыт, `each` не завершается, даже если новых событий нет. Следующая задача остаётся в очереди. У рецепта нет отдельного механизма завершения слежения, а очередной вызов `follow` без политики лишь добавляет ещё одну долгую задачу. Отмена полученного handle освобождает очередь, но одновременно прекращает нужное слежение. Это существенная цена рецепта, предлагаемого как обычная связь между контроллерами.

**Чем подтверждено.** `SoloBase.run` ставит корневую задачу в очередь; `SoloBase._pump` сразу возвращается при `_current != null`; `_onJobFinished` освобождает это место лишь после конца задачи. `JobStream.each` ждёт конец stream или отмену. В показанном контроллере нет иной ветви, освобождающей очередь. Подготовлен зонд `follow_queue_initial` с исходным `ScreenController` и второй задачей, добавленной через его публичный `run`.

**Предложение:** явно ограничить рецепт контроллером, посвящённым слежению, либо показать подписку, которая ставит короткие задачи на каждое событие и снимается при закрытии.

**Вердикт ревьюера:** ограничение вытекает из самого рецепта и очереди, но в рецепте не названо; зонд не запускался.

**Вердикт:** подтверждена чтением: задача живёт столько, сколько
подписка, и всё это время занимает очередь. Закрыто в `3049d98`: рецепт
ограничен контроллером, чья работа — слежение, с указанием, что иначе
нужна задача на событие.

### 7. Dartdoc `Job.cancel` обещает отмену до старта, которой у queued `SoloJob` может не быть

**Тяжесть:** Medium.

**Координата:** `packages/async_job/lib/src/job_base.dart`, реэкспортированный `Job.cancel`:

> before that there is no body to protect, and a job cancelled
> then is dropped like any other.

**Механика.** Получить от `solo.run(..., cancellable: false)` ещё стоящую в очереди задачу и вызвать `cancel()`. Она не удаляется и не помечается; возвращённая future ждёт её обычного выполнения. Если перед ней долгая задача, отмена ждёт и её. У ещё не поставленного в очередь handle, созданного через `solo.job`, такого отказа нет: поведение меняется именно от принадлежности очереди. Это видно пользователю, чьи методы по всему README возвращают статический `Job<T>` и ведут в справку данного метода.

**Чем подтверждено.** `_SoloJob.cancelWith` до вызова ядра проверяет нахождение в очереди и возвращается при `!cancellable && rejectable`. `JobBase.cancel` затем возвращает `whenDone`. Тест `cancel of a queued job that is not cancellable is refused` в `packages/solo/test/cancellable_test.dart` ожидает сохранение `isQueued`, отсутствие исхода и последующий `Done`. README «Rules that are not visible in signatures» описывает защиту очереди верно; ошибается справка реэкспортированного метода. Подготовлен зонд `queued_uncancellable`.

**Предложение:** уточнить в справке `Job.cancel` исключение для очередей надстроек и явно документировать отказ queued `SoloJob` при `cancellable: false`.

**Вердикт ревьюера:** расхождение справки ядра с публичным поведением `solo`; зонд не запускался.

**Вердикт:** подтверждена зондом: `cancel()` у задачи с
`cancellable: false`, стоящей в очереди, не помешал ей дождаться очереди
и закончиться `Done`. Закрыто в `3049d98`: дартдок `Job.cancel` называет
исключение очереди надстройки.

### 8. Обещание обратного порядка уборки не учитывает отложенный `discard`

**Тяжесть:** Low.

**Координата:** `packages/solo/README.md`, Concepts → «Taking ownership»:

> the stack scales to several resources, unwinds in reverse

Связанная справка: `packages/async_job/lib/src/job_context.dart`, `JobContext.onDispose`:

> The engine unwinds the stack after the children and before the
> outcome, last registration first

**Механика.** Зарегистрировать сначала медленный `onDispose` внешнего ресурса, затем `onDiscard` зависимого значения и успешно вернуть значение из тела. Условный верхний уборщик пропускается. Если отмена приходит во время нижнего `onDispose`, верхний `onDiscard` исполняется только после него, вторым проходом. Поэтому нельзя опираться на общий LIFO для освобождения зависимых ресурсов: условный уборщик может обратиться к уже закрытому окружению. Для обычных безусловных уборщиков обратный порядок сохраняется.

**Чем подтверждено.** Два цикла `JobBase._execute` сначала работают с `_cleanups`, затем с `_skipped`. Тест `a cancellation arriving during the cleanup still discards` в `packages/async_job/test/cleanup_test.dart` явно ожидает `['slow starts', 'slow ends', 'discarded']`. В связанном прежнем ревью ядра аналогичное обещание уже исправлялось в README ядра; в поверхности `solo` и этой справке оговорки нет. Подготовлен зонд `cleanup_order`.

**Предложение:** оговорить второй проход по пропущенным `discard` и отсутствие общего обратного порядка между ними и уже выполненными `dispose`.

**Вердикт ревьюера:** обещание шире фактического порядка, показанного реализацией и тестом; зонд не запускался.

**Вердикт:** подтверждена — тот же второй проход, что замерен вчера в
ядре. Закрыто в `3049d98`: оговорка в «Taking ownership» обоих языков.

### 9. Слежение за сессией не переносит её текущее состояние

**Тяжесть:** Low.

**Координата:** `packages/solo/README.md`, Recipes → «Following another controller»:

```dart
ScreenController(this.session) : super(const Screen());
```

и

```dart
session.stream,
(next) => ctx.emit(ctx.state.copyWith(signedIn: next.signedIn)),
```

**Механика.** Открыть экран, когда у сессии уже `signedIn == true`, а начальное `Screen()` — состояние неавторизованного экрана. Ни конструктор, ни `follow` не читают `session.state`; они слушают только будущие изменения. Пока сессия не излучит что-то ещё, экран остаётся с неверным флагом. Аналогичное окно есть, если состояние изменилось между конструированием экрана и началом queued `follow`. Рецепт не определяет `Screen`, поэтому это конкретный допустимый начальный случай, а не утверждение о несуществующем классе из пакета.

**Чем подтверждено.** `Solo` использует `StreamController.broadcast`, и `Solo.stream` возвращает stream без добавления начального `state`; `publish` добавляет только новые изменения. В исходном фрагменте нет начальной синхронизации. Зонд `follow_queue_initial` задаёт сессию с `true` и простой `Screen` с `false`; это обвязка неопределённых документом типов, исходный контроллер сохранён.

**Предложение:** явно синхронизировать начальное состояние с `session.state` и описать запуск подписки без окна потери изменений.

**Вердикт ревьюера:** неполный рецепт для уже существующей сессии; зонд не запускался.

**Вердикт:** подтверждена чтением: стрим несёт только последующие
изменения. Закрыто в `3049d98`: рецепт сначала берёт `session.state`, и в
прозе сказано зачем.

### 10. Enum ключей не передаёт проверку типа результата компилятору

**Тяжесть:** Low.

**Координата:** `packages/solo/README.md`, Concepts → «Queue and policies»:

> an enum of keys, as in
> `example/`, hands that to the compiler.

**Механика.** Использование одного enum-значения как ключа у задач `String` и `int` ничем не ограничено в API. В `Policy.droppable` несовместимость обнаруживается при приведении найденной задачи к `SoloJob<T>` во время второго вызова. Enum устраняет опечатки в строковых ключах, но не связывает свой элемент с параметром результата. Предупреждение перед этой фразой о несовместимых результатах верно; неверно обещание статического контроля.

**Чем подтверждено.** У `SoloBase.job` и `SoloBase.run` параметр имеет тип `Object? key`, независимый от `T`; `SoloBase.add` делает `existing as SoloJob<T>`. Сам `CameraKey` также не несёт параметра результата. Подготовлен зонд `enum_key` с одним enum-ключом и двумя заведомо несовместимыми типами; результат анализатора или компилятора здесь не заявляется.

**Предложение:** заменить обещание проверки компилятором правилом, что каждому результатному типу разработчик сам выделяет отдельный ключ.

**Вердикт ревьюера:** связь типов отсутствует в сигнатуре; компиляционный зонд не запускался.

**Вердикт:** подтверждена чтением: приведение по ключу происходит во
время работы, `TypeError` из `add`, и enum ключей компилятору ничего не
передаёт. Закрыто в `3049d98`: обещание заменено правилом «у типа
результата свой ключ».

### 11. Первый публичный CHANGELOG приписывает состояние не тому контексту

**Тяжесть:** Low.

**Координата:** `packages/solo/CHANGELOG.md`, «0.2.0», список API:

> `JobContext`: `state`, `stateAs`, `emit`, `check`, `wait`, `join`,

**Механика.** Читатель видит имя реального публичного типа `JobContext` и ищет в его справке или автодополнении перечисленные члены состояния. У этого типа их нет. Тип `SoloContext<S, W>` добавляет их поверх `JobContext`. Подраздел «Since 0.1.0» в этом же файле объясняет переименование правильно, поэтому шапка первой публикуемой версии противоречит собственной истории.

**Чем подтверждено.** Прочитаны объявления `JobContext` в `packages/async_job/lib/src/job_context.dart` и `SoloContext` в `packages/solo/lib/src/job_context.dart`, а также оба экспорта. Члены `state`, `stateAs` и `emit` объявлены только у второго; фактическую ошибку компилятора не получал.

**Предложение:** назвать в списке API `SoloContext<S, W>` и отделить добавленные им члены состояния от унаследованных членов ядра.

**Вердикт ревьюера:** подтверждено сопоставлением публичных объявлений, прогона не требует.

**Вердикт:** подтверждена чтением: `state`, `stateAs` и `emit` — члены
`SoloContext`, а не `JobContext` ядра. Закрыто в `3049d98`: список API в
CHANGELOG разделён на два.

## Первые пятнадцать минут

1. Пользователь начинает с `dart pub add solo`, создаёт `Profile`, затем копирует `ProfileController`. В Quick start нет объявления `ProfileApi`: ему нужно самому написать как минимум `Future<String> fetchName()`, если он хочет увидеть обещанную Ada Lovelace. Имя единственного импорта есть в прозе Why; готовой строки `import 'package:solo/solo.dart';` рядом с первым контроллером нет. Внешние операторы он помещает в собственный `async main`. Это конкретная недостающая обвязка; ошибки компиляции этих шагов в этой сессии не получены.

2. Для своего контроллера он видит порядок параметров `run<Profile, String>`, `ctx.emit`, `ctx.wait`, получение результата через `job.value`, чтение `state`, подписку и `close`. Следующий блок ручной отмены нужно пробовать на открытом экземпляре: предыдущий блок уже завершился `await profile.close()`. Если продолжить с тем же закрытым `profile`, новая `load()` сразу имеет `Cancelled(closed)`, а не показанное `Cancelled(manual)`.

3. При первой ошибке реального API он получает `Failed` или исключение через `value`, но `loading` остаётся `true` — находка 3. До объяснения восстановления состояния при отмене нужно дочитать Concepts → «The state on the way out»: там назван `onFinish` с `externalSetState`, но первый контроллер и последующий экран такого восстановления не показывают. Экран из Flutter после ошибки оставляет индикатор и убирает кнопку.

4. Если вместо простого профиля он начинает с устройства, различие `wait` и `join` объясняется в Concepts → «The action is not stopped», где ему также приходится предоставить собственный `CancelToken` и API устройства. Для подписки README вводит `each`; если обработчик сам асинхронен, на этом месте недостаёт границы ожидания при отмене — находка 2.

5. Если он связывает экран с уже работающей сессией по Recipes → «Following another controller», начальное состояние не переносится, а другие задачи экрана ждут конца слежения — находки 6 и 9. Сам рецепт не показывает ни первоначального чтения, ни одновременной работы обычного метода экрана.

6. Перейдя к Testing, пользователь должен сам предоставить `FakeProfileApi` и импорты `test` и `fake_async`; отдельного определения фейка README не даёт. Внешний стенд этой проверки задаёт ответ через задержку 10 мс, чтобы проверить показанный сценарий с `elapse(20 ms)`, но этот выбор обвязки не выдается за содержимое README или выполненный тест.

7. За полностью предоставленным кодом он идёт в `example/`: там есть состояние, контроллер, фейковое устройство, точка входа и семь тестов. `example/README.md` называет команды запуска и точные файлы. В его `pubspec.yaml` зависимость `solo: path: ../` ведёт к содержащему пакет каталогу; оверрайда на несуществующего соседа в этом файле нет. Однако при проверке ошибки `close`, которую штатный фейк умеет выдавать, он столкнётся с успешным исходом `dispose` — находка 4. Выполнение примера и установка его зависимостей в этой сессии недоступны.
