> **Состояние на 2026-09-15:** разобрано, вердикты проставлены. Находки 1–5
> закрыты коммитами `4ba09fd` и `6ca88db`; по находке 2 решение владельца
> принято отдельно.
> **Что это:** полное ревью реализации `ctx.runAll` Codex
> (`gpt-6-astra:xhigh`), первый круг. Проза ревьюера не тронута, вердикт
> по каждой находке добавлен отдельным абзацем.
> **Связанные записи:** спека
> `2026-09-14[10]-eager-parallel-run-design.md`, план
> `2026-09-15[1]-eager-parallel-run-plan.md`, отчёт о проходе
> `2026-09-15[2]-eager-parallel-run-report.md`, второе ревью того же круга —
> `2026-09-15[7]-eager-parallel-run-work-review-2.md`.

# Ревью реализации `ctx.runAll`

Проверяемые коммиты: `8cb6597`, `4def576`, `5b1dd15`. Контракт: десятая
редакция `docs/records/2026-09-14[10]-eager-parallel-run-design.md`. Работа
ведётся в изолированном клоне `/private/tmp/k7q2m9/wt`.

Ревью завершено. Ниже только подтверждённые находки.

## 1. Отказ повторного приёма снимает удержание действующей ветки

**Блокирующая.**

`packages/async_job/lib/src/job_context.dart:1269`: новая группа присваивает
`child._hold` до `startChild`, а при отказе сбрасывает его в `null`. Если
передать уже работающую ветку другой группы, ожидаемый `StateError`
сопровождается порчей первой группы. Ветка заканчивается до решения группы,
теряет `discard`, и поздний отказ соседа оставляет ресурс открытым. Нарушены
критерии 11 и 15 и правило удержания. Это воспроизводится через публичный API,
без доменных переопределений.

Чем доказано: из `packages/async_job` выполнено
`rtk proxy dart run .probe/admission_and_filter.dart`.

```text
ADMISSION retry=false refused=Null holderFinishedBeforeFailure=false
ADMISSION retry=false caughtOriginal=true closed=1 holder=Cancelled parentFinished=true
ADMISSION retry=true refused=StateError holderFinishedBeforeFailure=true
ADMISSION retry=true caughtOriginal=true closed=0 holder=Done<Object> parentFinished=true
```

Зонд запускает группу `[holder, bad]`, затем повторно передаёт `holder`
в другую группу и ловит отказ. После этого разрешает соседу упасть. Контрольный
прогон без повторного приёма закрывает ресурс ровно один раз.

Что сделать: устанавливать удержание только для принимаемого нового ребёнка;
при отказе сохранять прежнее удержание. Добавить тест на повторный приём
работающей ветки до входа в первый барьер.

Вердикт: исправить до принятия реализации.


**Вердикт: принята, исправлена до отчёта ревьюера.** Тот же вход я нашёл сам,
пока ревью шло, и починил коммитом `4ba09fd`: удержание вешается только после
приёма. Замер совпал с приведённым — `Done(db)` и ноль закрытий до правки,
`Cancelled(sibling)` и одно после. Тест на повторный приём работающей ветки
добавлен в `packages/async_job/test/run_all_test.dart`, обратная мутация его
краснит. Совпадение независимой находки с моей — сильнее любого из двух
по отдельности.

## 2. Фильтр собственных остановок не покрывает проигравшую отмену

**Блокирующая.**

`packages/async_job/lib/src/job_context.dart:1357` и `:1559`: координатор
запоминает созданный им объект `Cancelled`, а выбор сравнивает итог ветки
только с ним. По контракту исключается итоговая отмена ветки, которую этот
вызов просил остановить, включая случай, когда просьба проиграла чужой отмене.
При удержанной внешней отмене внутри `ctx.uncancellable` итоговый объект
отличается от запроса группы и ошибочно побеждает отмену источника.

Чем доказано: той же командой
`rtk proxy dart run .probe/admission_and_filter.dart`.

```text
FILTER targetFinishedFirst=true
FILTER selectedSource=false selectedRequestedBranch=true targetReason=manual
```

Зонд удерживает внешнюю отмену второй ветки в `uncancellable`. Затем первая
ветка бросает отмену и запускает остановку соседей, но её уборка задержана.
Вторая заканчивается первой с ранее удержанной внешней отменой. Именно её
группа ошибочно возвращает. Спека прямо называет такой широкий фильтр в разделе
«Что не считается ошибкой группы»; критерий 9 проверяет выбор при более раннем
завершении остановленного соседа.

Что сделать: учитывать факт просьбы остановить ветку и исключать её итоговый
`Cancelled`, сохраняя настоящие `Failed`. Добавить расписание с чужой отменой,
удержанной до групповой остановки.

Вердикт: исправить до принятия реализации.


**Вердикт: принята, и это оказалось решением владельца, а не только правкой.**
Замер воспроизвёл: ветка `a` сдалась сама и запустила остановку, ветка `b`
кончилась ранее удержанной чужой `Cancelled(manual)` — наружу вышла отмена `b`.
Спека в разделе «Что не считается ошибкой группы» читается двояко: фраза «По
тождеству исхода, а не по типу причины» говорит за прежний код, а абзац «Фильтр
шире причинности: попытка `cancel` могла быть отвергнута или проиграть чужой
отмене» — за находку. Вопрос вынесен владельцу, решение 2026-09-15: **фильтр
по ветке**. Реализовано в `6ca88db`: у ветки хранится `askedToStop` вместо
объекта, `Failed` не фильтруется никогда, а ветка, сменившая исход на барьере,
называется источником — иначе фильтр съел бы тот самый исход, который группа
обязана отдать. Тест на проигравшую просьбу добавлен, мутация «исключать только
созданное группой» его краснит.

## 3. Невыбранный отказ доменного `finish` теряется при наблюдателе

**Блокирующая.**

`packages/async_job/lib/src/job_base.dart:868`
и `packages/async_job/lib/src/job_context.dart:1536`: `handleUnanswered`
считает наличие наблюдателя доказательством уже доставленного отказа. Но домен
вправе закончить ветку через `finish(Failed(...))` на барьере. Этот путь
не вызывает `notifyObserver`; группа уже наблюдает `done`, поэтому обычного
сообщения о ненаблюдённом отказе тоже не будет. При двух таких отказах первый
получает вызывающий, второй исчезает.

Чем доказано: из `packages/async_job` выполнено
`rtk proxy dart run .probe/commit_and_sink.dart`.

```text
SINK observer=false selectedFirst=true otherInObserver=0 otherInZone=1
SINK observer=true selectedFirst=true otherInObserver=0 otherInZone=0
```

Зонд использует существующие `CheckingJob` и `ProbeJob` из тестового окружения.
В доменном `check()` обе стоящие на втором барьере ветки заканчиваются через
`drop(Failed(...))`. Без наблюдателя второй объект достигает зоны,
с наблюдателем его не получает никто. Ручное завершение на барьерах явно
разрешено разделом спеки «Где живёт»; обещание сохранения полученного
невыбранного отказа нарушено.

Что сделать: различать наличие наблюдателя и фактическую доставку конкретного
отказа. Для полученного, но ещё не объявленного `Failed` сохранить маршрут
диагностики, не удваивая сообщения об обычных отказах тела. Добавить этот вход
к критерию 10.

Вердикт: исправить до принятия реализации.


**Вердикт: принята, исправлена.** Зонд подтвердил и показал больше: при
наблюдателе отказ терялся и у наблюдателя, и в зоне — ноль и ноль. Причина
названа верно: проверка наличия наблюдателя считает доказанной доставку,
которой не было. Правка в `6ca88db` различает два случая по тому, тот ли это
объект, что произвёл исход тела: объявленный идёт в `handleUnanswered`,
необъявленный — в `notifyError`, то есть наблюдателю, а без него в зону.
Добавлен тест на обе половины с двумя прогонами; мутация «один маршрут на всех»
его краснит.

## 4. Приёмка пропускает нарушения контракта фиксации и фильтра

**Блокирующая.**

`packages/async_job/test/run_all_test.dart:1319`
и `packages/solo/test/run_all_test.dart`: отсутствует различающий вход критерия
21 с поздним асинхронным `onDispose`, зарегистрированным именно на втором
барьере. Мутация `wait_success_tails` заменяет успешный возврат ожиданием всех
`branch.job.done`. Она нарушает разрешённый ранний возврат успеха, но оба
полных набора остаются зелёными.

Чем доказано:
`rtk proxy python3 /private/tmp/k7q2m9/out/mutations.py wait_success_tails`.
Скрипт сохраняет исходник через `cp`, вносит одну мутацию, запускает
`dart test` в обоих пакетах и возвращает исходник копией.

```text
wait_success_tails async_job exit=0
00:00 +367: All tests passed!
wait_success_tails solo exit=0
00:00 +563: All tests passed!
```

Свой зонд `.probe/commit_and_sink.dart` отличает версии:

```text
исходник: TAIL valuesReady=true quickFinished=false parentFinished=false
мутант:   TAIL valuesReady=false quickFinished=false parentFinished=false
```

Дополнительно подтверждена мутация `clear_before_reread`: координатор
запоминает предварительный успех, выполняет `check()`, снимает `_skipped`
и лишь затем перечитывает ветки. Бросивший `check()` обработан правильно,
но успешно вернувшийся `check()`, отменивший ветку, приводит к утечке. Штатный
тест `:785` проверяет только отсутствие значения и тип отмены, ресурса в этом
входе нет. Команда:
`rtk proxy python3 /private/tmp/k7q2m9/out/mutations.py clear_before_reread`.

```text
clear_before_reread async_job exit=0
00:00 +367: All tests passed!
clear_before_reread solo exit=0
00:00 +563: All tests passed!
исходник: COMMIT_CHECK closed=1 caught=Cancelled
мутант:   COMMIT_CHECK closed=0 caught=Cancelled
```

Третья выжившая мутация — `filter_by_reason`: сравнение по тождеству заменено
проверкой `outcome.reason is SiblingCancelReason`. Внешний код может передать
такую публичную причину сам, и её нельзя считать своей остановкой. Штатный тест
`:513` такого входа не содержит. Команда:
`rtk proxy python3 /private/tmp/k7q2m9/out/mutations.py filter_by_reason`.

```text
filter_by_reason async_job exit=0
00:00 +367: All tests passed!
filter_by_reason solo exit=0
00:00 +563: All tests passed!
исходник: FOREIGN_REASON selectedSource=true caught=Cancelled
мутант:   FOREIGN_REASON selectedSource=false caught=StateError
```

Есть и пропуск внутри уже написанного входа критерия 10 (`:598–623`): проверка
содержимого зоны находится внутри `runZonedGuarded`. Если `expect` падает,
обработчик зоны добавляет сам `TestFailure` в список, после чего список больше
не проверяется. Поэтому целевое утверждение про сохранение невыбранного отказа
проходит при полностью удалённом вызове `handleUnanswered`. Команда:
`rtk proxy python3 /private/tmp/k7q2m9/out/one_test_mutation.py`.

```text
criterion_10_mutation exit=0
00:00 +0: loading test/run_all_test.dart
00:00 +0: a failure the group received and did not throw is not lost
00:00 +1: All tests passed!
```

Полный набор эту мутацию ловит другим тестом — об отказе приёма; это не делает
исправным утверждение критерия 10.

Что сделать: добавить тест с регистрацией долгого хвоста на втором барьере
и проверкой, что список уже получен, пока хвост и родитель ещё не закончены.
В реентрантный вход `check()` добавить ресурс и проверять его закрытие.
Проверить отдельно внешнюю отмену с публичной `SiblingCancelReason`.
Утверждение о содержимом зоны вынести за `runZonedGuarded`.

Вердикт: дополнить приёмку до принятия реализации.


**Вердикт: принята целиком, все четыре пробела закрыты.** `wait_success_tails`
— добавлен тест с долгим `onDispose`, зарегистрированным на втором барьере:
список приходит, пока хвост ещё идёт; мутация «дождаться всех `done`» краснеет.
`clear_before_reread` — в реентрантный вход добавлен ресурс, проверяются два
закрытия; мутация краснеет двумя тестами. `filter_by_reason` — тест добавлен
(его же нашёл второй ревьюер). Утверждение о зоне вынесено за `runZonedGuarded`
во всех четырёх местах, где оно стояло внутри; проверено мутацией «сток
выкинут» — тест краснеет в одиночном прогоне, чего раньше не было. Замечание
точное и стоило дороже остальных: проглоченное утверждение снаружи неотличимо
от работающего.

## 5. Публичные документы обещают закрытие вне границ гарантии

**Не блокирующая.**

`packages/async_job/doc/children.md:93` обещает, что при любом неуспехе группы
ветка закроет ресурс и к моменту `catch` открытого не останется. Та же
безусловная гарантия дана у `onDiscard`
в `packages/async_job/lib/src/job_context.dart:258`. Однако неотменяемая ветка
сохраняет `Done` и не исполняет `discard`. Упоминание отказа от остановки ниже
в документе не объясняет эту цену для ресурса. Спека прямо называет её
границей: «Неотменяемая ветка уносит свой ресурс».

Чем доказано: из `packages/async_job` выполнено
`rtk proxy dart run .probe/coordinator_edges.dart`.

```text
RESOURCE refuses=false caught=StateError closed=1 holder=Cancelled
RESOURCE refuses=true caught=StateError closed=0 holder=Done<Object>
```

Это ожидаемое поведение реализации; неверно обещание документации.

Что сделать: ограничить гарантию веткой, которая сама зарегистрировала ресурс
и приняла отмену. Назвать сохранение ресурса у `cancellable: false` и отдельно
обозначенную спекой границу делегирования своему ребёнку. Согласовать dartdoc
и русский перевод с этой формулировкой.

Вердикт: исправить формулировки вместе с остальными правками.


**Вердикт: принята.** `doc/children.md`, его перевод и dartdoc `onDiscard`
переписаны в `6ca88db`: обещание ограничено веткой, принявшей остановку,
и прямо названы две вещи, которые остаются открытыми, — ветка
с `cancellable: false`, отдающая значение через свой `value`, и ветка,
получившая ресурс от собственного ребёнка (дыра ядра, отложенная работа
`2026-09-14[17]-discard-follows-the-value-design.md`).

## Проверка четырёх утверждений исполнителя

1. Перенос приёмки в отдельные `run_all_test.dart` сам по себе допустим. Старые
   тесты в проверяемом диффе не переписаны: изменения добавочные. Однако
   покрытие конкретных критериев неполно — находка 4.
2. Проверка наблюдателя в ядре соответствует критерию 10 для обычного отказа
   тела: наблюдатель получает его один раз, зона молчит. В `solo`
   переопределение действительно сохраняет отдельный маршрут `errorHandler`;
   собственный зонд проверил все четыре сочетания наличия наблюдателя
   и обработчика. Но обобщение на любой полученный `Failed` неверно — находка
   3.
3. Обработка броска `cancelWith` обоснованна. Собственный зонд проверил бросок
   до и после `super.cancelWith`, ожидание асинхронного `discard` соседней
   ветки и синхронное завершение из `whenCancelled`. Соседи отпускаются, группа
   ждёт уборку, ошибка движка возвращается вызывающему. Ветка
   с переопределением, бросившим до `super`, не принимает отмену: её
   собственный ресурс остаётся открытым. Зонд не выдаёт это за гарантию
   закрытия неисправного домена.
4. Объяснение зелёной мутации со снятием `_skipped` после отпускания
   подтверждается в узком смысле: вердикт успеха действительно не даёт
   выполнить `discard`, даже если группа ещё не очистила список. Мутация
   `clear_after_async_release` оставила оба полных набора зелёными. Но это
   не подтверждает полноту приёмки синхронной фиксации: другие перестановки
   и ожидание хвостов меняют результат и также зелёные (находка 4).
   Дополнительный `await` меняет планирование, поэтому зелёный прогон
   не доказывает буквальный порядок пяти шагов спеки.

## Контроль неизменности и границы проверки

Хвост `_execute` сопоставлен с версией `8cb6597` до добавления группы. При
`_hold == null` новые ожидания и повторное чтение стека не выполняются,
а условие `valueHandedOver()` сводится к прежнему
`(_pendingCancel ?? outcome) is Done<T>`. Все 342 теста вне нового файла
`run_all_test.dart` выполнены на обеих версиях. Они зелёные в обоих случаях;
снятие ребёнка по тождеству в этой контрольной базе уже исправлено. Разбор
конверта и `_isOwnCancellation` в проверяемом диффе не изменены.

На штатных путях первый и второй барьеры отпускаются. Проверены ручное
завершение на обоих барьерах со сбросом `isDisposing`, реентрантная отмена
из настоящего `SoloContext.check()`, завершение из `whenCancelled`, отмена
из `onFinish` и ожидание асинхронных уборок на неуспехе. Зависания на этих
входах не обнаружены. Непрерываемые действия без разрешения их барьера
по контракту могут удерживать группу бессрочно; таймаут это ревью
не приписывает реализации.

Исходники реализации восстановлены после каждой мутации через `cp` из `.orig`,
затем проверен `git status --short`. `git checkout` не использовался. Остались
только заметка в `docs/handoff.md` и собственные зонды в `.probe/`; исправления
реализации не вносились.

## Итог

Не годится.

## Что я выполнил

Команды ниже запускались через `rtk proxy`. Все логи и скрипты находятся рядом
с этим отчётом. Гейт выполнялся по дереву клона с локальными оверрайдами
зависимостей; мутация ядра, уронившая доменный тест, отдельно подтвердила, что
`solo` видит именно это ядро.

### Обязательный гейт

У всех команд код выхода 0. Для Dart приведена последняя строка, для FVM —
последние три строки, включая служебный хвост самого FVM.

`packages/async_job` → `dart analyze` ([лог](packages_async_job_analyze.log)):

```text
No issues found!
```

`packages/async_job` → `dart test` ([лог](packages_async_job_test.log)):

```text
00:00 +367: All tests passed!
```

`packages/solo` → `dart analyze` ([лог](packages_solo_analyze.log)):

```text
No issues found!
```

`packages/solo` → `dart test` ([лог](packages_solo_test.log)):

```text
00:00 +563: All tests passed!
```

`packages/solo/example` → `dart analyze`
([лог](packages_solo_example_analyze.log)):

```text
No issues found!
```

`packages/solo/example` → `dart test` ([лог](packages_solo_example_test.log)):

```text
00:00 +9: All tests passed!
```

`packages/flutter_solo` → `fvm flutter analyze`
([лог](packages_flutter_solo_analyze.log)):

```text
No issues found! (ran in 4.2s)
IO  : Writing 6358 characters to text file /Users/user/.pub-cache/log/pub_log.txt.
MSG : Logs written to /Users/user/.pub-cache/log/pub_log.txt.
```

`packages/flutter_solo` → `fvm flutter test`
([лог](packages_flutter_solo_test.log)):

```text
00:00 +87: All tests passed!
IO  : Writing 6355 characters to text file /Users/user/.pub-cache/log/pub_log.txt.
MSG : Logs written to /Users/user/.pub-cache/log/pub_log.txt.
```

`packages/flutter_solo/example` → `fvm flutter analyze`
([лог](packages_flutter_solo_example_analyze.log)):

```text
No issues found! (ran in 2.5s)
IO  : Writing 6117 characters to text file /Users/user/.pub-cache/log/pub_log.txt.
MSG : Logs written to /Users/user/.pub-cache/log/pub_log.txt.
```

### Мутации

Запуск: `rtk proxy python3 /private/tmp/k7q2m9/out/mutations.py <имя>`. Каждая
мутация по отдельности, затем полные `dart test` в `async_job` и `solo`. Точные
изменения сохранены в одноимённых `.diff`, выводы — в `<имя>_async_job.log`
и `<имя>_solo.log`.

| Имя | async_job | solo | Что проверяет |
| --- | --- | --- | --- |
| `outcome_by_input_order` | exit 1 | exit 0 | Выбор отказа по позиции входа |
| `filter_by_reason` | exit 0 | exit 0 | Фильтр по типу причины |
| `wait_success_tails` | exit 0 | exit 0 | Ожидание хвостов на успехе |
| `clear_before_parent_check` | exit 1 | exit 0 | Снятие записей до проверки родителя |
| `clear_before_reread` | exit 0 | exit 0 | Снятие записей до перечитывания веток |
| `clear_after_async_release` | exit 0 | exit 0 | Мутация из отчёта исполнителя |
| `drop_unanswered` | exit 1 | exit 1 | Удаление стока невыбранного отказа |

Последние строки каждого из этих прогонов:

`outcome_by_input_order`:

```text
async_job: For example, 'dart test --chain-stack-traces'.
solo: 00:00 +563: All tests passed!
```

`filter_by_reason`:

```text
async_job: 00:00 +367: All tests passed!
solo: 00:00 +563: All tests passed!
```

`wait_success_tails`:

```text
async_job: 00:00 +367: All tests passed!
solo: 00:00 +563: All tests passed!
```

`clear_before_parent_check`:

```text
async_job: For example, 'dart test --chain-stack-traces'.
solo: 00:00 +563: All tests passed!
```

`clear_before_reread`:

```text
async_job: 00:00 +367: All tests passed!
solo: 00:00 +563: All tests passed!
```

`clear_after_async_release`:

```text
async_job: 00:00 +367: All tests passed!
solo: 00:00 +563: All tests passed!
```

`drop_unanswered`:

```text
async_job: For example, 'dart test --chain-stack-traces'.
solo: For example, 'dart test --chain-stack-traces'.
```

Отдельно выполнен целевой тест критерия 10 с удалённым стоком:
`rtk proxy python3 /private/tmp/k7q2m9/out/one_test_mutation.py`. Последняя
строка самого `dart test`:

```text
00:00 +1: All tests passed!
```

### Сравнение до и после

`rtk proxy python3 /private/tmp/k7q2m9/out/compare_before.py` — все тестовые
файлы ядра, кроме нового `test/run_all_test.dart`. Точные команды записаны
в `non_group_after_command.txt` и `non_group_before_command.txt`. Последние
строки двух прогонов:

```text
после: 00:00 +342: All tests passed!
до:    00:00 +342: All tests passed!
```

### Собственные зонды

Каждый запускался через `dart run` из папки своего пакета, код выхода 0. Копии
`.dart` и полные логи лежат рядом с отчётом. Копии используют тестовые
помощники пакета; для повторного запуска оставлены исходные файлы в `.probe/`.

- `packages/async_job/.probe/admission_and_filter.dart` — Повторный приём живой
  ветки и проигравший запрос отмены.

Из `packages/async_job`: `dart run .probe/admission_and_filter.dart`.

Последняя строка ([полный вывод](admission_and_filter.log)):

```text
FILTER selectedSource=false selectedRequestedBranch=true targetReason=manual
```

- `packages/async_job/.probe/commit_and_sink.dart` — Ресурс при реентрантном
  check, поздний хвост, ручное завершение на обоих барьерах, сток ручного
  Failed и внешняя SiblingCancelReason.

Из `packages/async_job`: `dart run .probe/commit_and_sink.dart`.

Последняя строка ([полный вывод](commit_and_sink.log)):

```text
SINK observer=true selectedFirst=true otherInObserver=0 otherInZone=0
```

- `packages/async_job/.probe/coordinator_edges.dart` — Бросок cancelWith
  до и после super, ожидание discard, синхронное завершение из whenCancelled
  и граница cancellable: false.

Из `packages/async_job`: `dart run .probe/coordinator_edges.dart`.

Последняя строка ([полный вывод](coordinator_edges.log)):

```text
RESOURCE refuses=true caught=StateError closed=0 holder=Done<Object>
```

- `packages/solo/.probe/domain_routes.dart` — Реентрантный keepWhile настоящего
  solo и четыре сочетания observer/errorHandler.

Из `packages/solo`: `dart run .probe/domain_routes.dart`.

Последняя строка ([полный вывод](domain_routes.log)):

```text
SOLO_SINK observer=true handler=true selected=true observed=1 handled=1 zone=0
```

### Дополнительные проверки

`dart format --output=none --set-exit-if-changed` выполнен для восьми
изменённых Dart-файлов проверяемой работы, без изменений форматирования.
Проверки документации запускались из корня. Последние строки:

`dart format --output=none --set-exit-if-changed` — exit 0:

```text
Formatted 8 files (0 changed) in 0.05 seconds.
```

`python3 tool/check_line_width.py` — exit 0:

```text
no Markdown line over 79 columns
```

`python3 tool/check_translations.py` — exit 0:

```text
headings: 2 in the same order, levels [1, 2]
code blocks: 2 in both files
no differences
```

`python3 tool/check_doc_shape.py` — exit 0:

```text
every section opens with code or a table
```

`python3 tool/build_site.py` — exit 0:

```text
wrote 42 pages under site/src/content/docs
```

`python3 tool/reflow.py --check` — exit 0:

```text
every paragraph is filled to 79 columns
```

Отдельная проверка того же скрипта для этого отчёта — exit 0, та же последняя
строка. `rtk proxy git diff --check` — exit 0, вывода нет. Все 11 файлов
проверяемого диффа побайтно совпадают с `HEAD` после возврата мутаций; файлов
`.orig` не осталось.

Последний `rtk proxy git status --short`:

```text
 M docs/handoff.md
?? packages/async_job/.probe/
?? packages/solo/.probe/
```


## Вердикт по итогу ревью

«Не годится» принято. Пять находок из пяти признаны верными: четыре блокирующие
закрыты коммитами `4ba09fd` и `6ca88db`, пятая — правкой документов там же.
Ни одна находка не отвергнута.

Разбор четырёх утверждений исполнителя тоже принят. Пункт 4 — про зелёную
мутацию со снятием отложенных записей после отпускания — уточняет мой отчёт
верно: односторонний вердикт действительно закрывает окно, но из этого
не следует, что приёмка синхронной фиксации полна; недостающие входы названы
в находке 4 и добавлены.
