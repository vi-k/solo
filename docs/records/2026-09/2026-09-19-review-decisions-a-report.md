# Решения по ревью, волна A: ядро и `solo`

> **Состояние на 2026-09-19:** сделано, правки в `main`.
> **Что это:** отчёт о первой из четырёх волн по решениям владельца на остаток
> ревью — вынос протокола движка, удержанная отмена, фазы `SoloPending`, трасса
> изменения, мелкие удаления и два Low.
> **Связанные записи:** `2026-09-19-solo-project-review.md` (раздел «Решения
> владельца»), `2026-09-19-medium-findings-report-3.md`.

Владелец ответил на вопросы по остатку ревью, я предложил делать решения
четырьмя волнами снизу вверх, владелец ответил «ок» на волну A. В неё вошло
всё, что лежит в ядре и в `solo`, кроме защищённых `job`, `add`, `run`,
`collect` и `accumulate` — это волна C. Каждая правка закрыта сторожем, каждый
сторож проверен мутацией.

| Решение | Где | Сторожа |
| --- | --- | --- |
| протокол движка в `engine.dart` | `async_job` | 2 |
| удержанная отмена, M18 | `JobBase.heldCancel`, `SoloPending` | 3 |
| M1, без `unknown` | `SoloPhase`, три места прозы | 2 |
| M5, трасса под флагом | `Solo.traceStateChanges` | 4 |
| L7, причина массовой отмены | `cancelAll`, `SoloQueue` | 3 |
| L6, что видит политика | `Policy`, `doc/jobs.md` | 1 |
| `lastWhere`, `isExternal`, `outcome_test.dart` | `solo` | — |

## Протокол движка

`async_job.dart` экспортирует `src/job_base.dart` без `JobBase`,
`JobContextBase` и `JobStatus`; новый `engine.dart` экспортирует основной
импорт и эти три. Библиотека `solo` импортирует `engine.dart`, её барель
по-прежнему реэкспортирует основной — поэтому приложение, импортирующее `solo`
или `flutter_solo`, протокола больше не видит. Сломались на этом только те
файлы, которые строят свою задачу на `JobBase`: шесть тестовых файлов ядра,
`foreign_job.dart` и `hooks_test.dart` в `solo`. Всем им хватило смены или
добавления импорта.

`doc/extending.md` и перевод говорят, где живут три класса, фрагмент
открывается строкой импорта, ссылка на справку ведёт в библиотеку `engine`.
Сторож — `engine_import_test.dart`: какой импорт что несёт — факт директив
`export`, и прочитать его можно только из исходника, как уже делает сторож
`@protected` у `SoloListenable`.

## Удержанная отмена и M18

Ядро помнило отмену, пришедшую в секцию `ctx.uncancellable`, в приватном
`_heldCancel`, а `SoloPending` выводил «держит отмену» из одной глубины секций.
Теперь у `JobBase` есть защищённый `heldCancel`, у снимка — поле
`heldCancellation`, и `cancellationPending` стоит на нём. `toString` пишет
`holding Cancelled(manual) back`, когда отмена удержана,
и `in an uncancellable section`, когда секция просто открыта. Правка ядра вошла
в тот же пункт changelog, что и `inUncancellableSection`: оба не выпущены.

```text
heldCancel always null -> 1 caught
heldCancel is the marked cancellation -> 1 caught
cancellationPending from the section again -> 1 caught
    an open section nobody asked to leave is only an open section
the snapshot not given the held one -> 1 caught
    a held cancellation is named without being a guess
```

## M1: фаза без `unknown`

`SoloPhase.unknown` убран. Окно после тела, когда детей нет, — это теперь
`cleanup`: там задача разбирает стек уборки, если он есть, и доходит до исхода.
Окно шире, чем записано в ревью: оно длится не одну микрозадачу, а до самого
исхода и захватывает обработчики состояния — в `onError` задачи `pending`
раньше называл `unknown`, теперь называет `cleanup`. Проза исправлена в dartdoc
`SoloPhase` и `Solo.pending`, в `doc/errors.md` с переводом и в пункте
changelog о `Solo.pending`. Тест, названный по старой прозе, переименован:
голый `await` — это `body`.

```text
the window read as body -> 1 caught
    a job past its body and children reads as its cleanup
```

## M5: трасса изменения

`Solo.traceStateChanges` по умолчанию истинен там, где включены `assert`,
и ложен в release и profile; приложение может выставить его в любую сторону.
Три места, где изменение снимало `StackTrace.current`, теперь снимают его под
флагом.

По дороге выяснилось, что выключенный флаг теряет меньше, чем казалось, когда я
задавал вопрос. Проверка правил у работающих задач идёт синхронно изнутри
самого изменения, поэтому трасса, снятая в месте отмены, уже содержит того, кто
изменил состояние, — только с несколькими кадрами движка сверху. Поэтому без
записи отмена по правилам берёт `StackTrace.current` там, где её решили,
а контрольная точка, которая сама нашла нарушенное правило, — свою. Без записи
теряется одно: у задачи, которая нашла правило нарушенным в своей точке, трасса
ведёт в эту точку, а не к последнему изменению.

```text
the default off -> 1 caught
    the record is on where assertions are
no trace where the rules cancel -> 1 caught
no trace at the checkpoint -> 1 caught
    a rule broken with no change is traced to the checkpoint
the record taken whatever the flag -> 1 caught
```

## L7 и L6

`cancelAll`, `SoloQueue.remove`, `removeWhere` и `clear` получили `reason`
с `ManualCancelReason` по умолчанию. Вызовы не ломаются, ломается только
собственная реализация `SoloQueue`, и это сказано в changelog.

Обещание политик исправлено, а не код: `Policy` и `doc/jobs.md` с переводом
говорят, что политика смотрит на очередь и работающую корневую задачу,
а ребёнка с тем же ключом не видит — он работает внутри другой задачи и через
очередь не проходил. Сторож держит это поведение: корневая `droppable` с ключом
работающего ребёнка не получает ребёнка.

```text
cancelAll drops the reason for the current job -> 1 caught
remove drops the reason -> 2 caught
droppable looks at running children -> 1 caught
```

## Удаления

`SoloQueue.lastWhere` убран, его тест оставил только `lastJobWhere`,
из `doc/jobs.md` с переводом метод ушёл, а на его месте сказано, где искать.
`SoloTransition.isExternal` убран вместе с двумя строками тестов.
Из `outcome_test.dart` пять тестов проверяли типы ядра, проверенные в ядре;
шестой, о порядке значений `Policy`, переехал в `policy_test.dart`, а файл
удалён.

## Что прошло целиком

| Проверка | Результат |
| --- | --- |
| `async_job`: `dart analyze`, `dart test`, `dart doc --dry-run` | чисто, 472 зелёных, 0 предупреждений |
| `solo`: то же | чисто, 688 зелёных, 0 предупреждений |
| `packages/solo/example` | чисто, 9 зелёных |
| `flutter_solo`: `flutter analyze`, `flutter test`, `dart doc --dry-run` | чисто, 102 зелёных, 0 предупреждений |
| пример `flutter_solo` | чисто, 4 зелёных |
| стенды `vs-bloc.md` и `accumulation.md` | три пакета чисто, все драйверы доходят, трассы на месте |
| стенд Flutter | 20 зелёных, трассы на месте |
| пять документных проверок и сторож `reflow` | зелёные |

## Чего эта работа не трогала

Волна B — `flutter_solo`: `changed:`, `SoloSelection.from`, один `SoloSelector`
над `Solo`, реэкспорт `ValueListenable`, переезд `doc/flutter.md`. Волна C —
защищённые `job`, `add`, `run`, `collect`, `accumulate`. Волна D — Low без
решений, пробел модели Usage в README `flutter_solo` и предложения сверх
находок.
