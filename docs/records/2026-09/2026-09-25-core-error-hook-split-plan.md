# Разделение хука ошибки в ядре: оповещение отдельно, ответ отдельно

> **Состояние на 2026-09-25:** план написан и прошёл круг независимого ревью
> (`2026-09-25-core-error-hook-split-plan-review.md`), все тринадцать находок
> приняты и внесены; открытые вопросы 1–4 решены, пятый — для владельца.
> Правки в коде нет.
> **Что это:** план правки `async_job`: `JobObserver.onError` становится
> чистым оповещением, ответ за ошибку, которую не несёт ни один исход,
> переезжает в новый хук наблюдателя `onUnanswered`, а движок `solo` теряет
> свои переопределения `notifyError` и `handleUnanswered`.
> **Связанные записи:** `2026-09-22-error-hook-split-plan.md` (та же правка
> в `solo`, открытый вопрос 4 которого этот план пересматривает),
> `2026-09-22-error-hook-split-report.md`,
> `2026-09-25-observing-rakes-report.md` (вычитка страницы, откуда пришёл
> вопрос), `2026-09-25-core-error-hook-split-plan-review.md` (ревью плана).

## Зачем

Владелец спросил при чтении `packages/async_job/doc/observing.md`:
«а в async_job не нужен Job.onError и onUnanswered?» 2026-09-22 план разделения
в `solo` ответил на это заранее, открытым вопросом 4: «В `async_job` править
нечего: там оповещение и ответ уже разные методы, схлопывал их `solo`». Это
верно для автора движка: у `JobBase` есть защищённые `notifyObserver`
(оповестить), `handleUnanswered` (ответить) и `notifyError` (и то и другое).
Но пользователь ядра видит только `JobObserver`, и у него одно место на обе
работы.

`JobBase.notifyError` сегодня:

```dart
final observer = _observer;
if (observer == null) {
  _toZone(error, stackTrace);
  return;
}
_notify(() => observer.onError(this, error, stackTrace));
```

Без наблюдателя ошибка вне тела уходит в зону создания задачи. С наблюдателем
она останавливается на нём, и отвечает за неё само присутствие наблюдателя,
что бы ни было в его `onError`. Dartdoc `JobObserver.onError` говорит это
прямо: «with an observer they all stop here».

**Зонд 2026-09-25.** Уборка бросает, работа `ctx.unattended` падает. Без
наблюдателя зона получает
`[Bad state: cleanup failed, Bad state: analytics offline]`. С `Log` из первого
раздела страницы — наблюдателем, который переопределяет только `onFinish`
и `onLog`, — зона получает `[]`, и никто ничего не слышит. Наблюдатель,
написанный для журнала, молча отменяет маршрут ошибок: та же ловушка, которую
`solo` снял 2026-09-22.

## Что станет с API

```dart
abstract mixin class JobObserver {
  /// Something the job did threw.
  ///
  /// Notification only: overriding it changes nothing about where the
  /// error goes. ...
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}

  /// Nobody answered for this error, and this observer is the last one
  /// holding it.
  ///
  /// The errors no outcome carries: ... Each has been through [onError]
  /// already. The default body hands the error to the zone the job was
  /// created in — where it goes when the job has no observer — all but a
  /// [Cancelled] and a `ParallelWaitError` carrying nothing but
  /// cancellations, which go nowhere. Override it to answer here instead;
  /// call `super.onUnanswered(job, error, stackTrace)` to keep the zone as
  /// well, and hand it anything the override cannot tell apart.
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    ...
  }
}
```

| Чего хочет читатель | Что он переопределяет |
| --- | --- |
| видеть ошибки задачи | `onError`, и `super` ему не нужен |
| отвечать за ошибки без исхода у этой задачи и её детей | `onUnanswered` |
| отвечать за них во всём приложении | ничего: они приходят в зону, как без наблюдателя |

Имя и форма те же, что у `Solo.onUnanswered`: одно слово на один предмет по обе
стороны границы пакетов, и переопределение без `super` значит «отвечаю сам»
в обоих. `@mustCallSuper` не ставится по той же причине, что у `Solo`.

## Маршруты до и после

Меняются две строки из пяти в таблице раздела «Where errors go», и добавляется
третья, которой там нет.

| Ошибка | Сейчас, с наблюдателем | После, с наблюдателем | Без наблюдателя, до и после |
| --- | --- | --- | --- |
| тела, задача кончается `Failed` | `onError`; зона, если исход не наблюдали | то же | зона, если исход не наблюдали |
| тела, отмена пришла, пока задача ждёт детей | `onError`; зона, если исход не наблюдали | то же | зона, если исход не наблюдали |
| тела, после принятой отмены | `onError` | то же | никто |
| вне тела | `onError` | `onError`, затем `onUnanswered`: по умолчанию зона | зона |
| `Cancelled` вне тела | `onError` | `onError`, затем `onUnanswered`: по умолчанию никто | никто |
| провал ветки `runAll`, который группа не бросила | `onError`, где тело его бросило; больше никто | `onError` там же, затем `onUnanswered`: по умолчанию зона | зона |

Не меняется ни одна ошибка тела. Провал после принятой отмены остаётся
оповещением: так решено в `fcc7409` (находка 1
`2026-09-07[8]-jobs-fixes-review.md`), иначе в зону уходила бы каждая остановка
по токену; `solo` ведёт его так же. `onUnanswered` его не получает: с ответом
по умолчанию он привёл бы его в зону.

Последняя строка — ветка `ctx.runAll`, чей провал группа не выбрала. Её тело
уже оповестило наблюдателя, где провал поймали, поэтому второго `onError` нет
и после правки. Ответ за него — `handleUnanswered`, и сегодня при наблюдателе
он молчит: это та же ловушка, только глубже.

Вторая строка для детей, чей исход смотрит `ctx.run` или группа `runAll`,
на деле значит «никогда»: исход наблюдали, а несёт он `Cancelled`, не провал.
Так было и до правки, правка этого не меняет — открытый вопрос 5.

## Что станет с ядром

- `packages/async_job/lib/src/observer.dart` становится частью `job_base.dart`
  (`part of`): тело `onUnanswered` по умолчанию должно дойти до зоны создания
  задачи, а это приватный `JobBase._zone` за приватным же `_toZone`, который
  держит правило «`Cancelled` в зону не идёт». `lib/async_job.dart` перестаёт
  экспортировать `src/observer.dart`: `JobObserver` уходит наружу вместе
  с `job_base.dart`. Сторож `test/engine_import_test.dart` сверяет список
  экспортов и меняется вместе с ним.
- Задача, чей наблюдатель зовёт `onUnanswered` по умолчанию, — всегда
  `JobBase`: ядро передаёт хуку `this`. Если хук позвали руками с чужой
  реализацией `Job`, тело по умолчанию отдаёт ошибку текущей зоне. Фильтр
  `_toZone` — `Cancelled` и чистый конверт отмен — выносится в один предикат,
  и обе ветки зовут его.
- `JobObserver` становится `abstract mixin class`. Класс, который уже наследует
  другой, подмешивает его `with JobObserver` и получает тела по умолчанию,
  в том числе маршрут `onUnanswered`. `implements JobObserver` после правки
  не компилируется, пока класс не напишет `onUnanswered` сам, а маршрут в зону
  создания он получит только делегированием в наблюдателя, который его
  наследует. Поэтому страница советует `with`, а не `implements`.
- Ответ — один путь, `_handleUnanswered`: с наблюдателем его `onUnanswered`
  через `_notify`, без наблюдателя `_toZone`. `notifyError` — это
  `notifyObserver`, затем `_handleUnanswered`, двумя отдельными вызовами
  `_notify`: бросивший `onError` не отменяет ответа. Трасса `JobBase.debug`
  меняется: у каждого ответа строка «error nobody answered for», а при
  наблюдателе ещё и строки `_toZone`.
- `JobBase.handleUnanswered` становится приватным: единственное место вызова —
  `_conclude` у `runAll`, а переопределял его только движок `solo`, которому
  после правки это не нужно. Его dartdoc сегодня велит движку переопределять
  его, иначе «the kernel takes the observer for the answer and the error stops
  there»; после правки ответ движка — это `onUnanswered` его собственного
  наблюдателя. Член не публиковался (открытый вопрос 1).
- `notifyObserver`, `notifyError` и `reportToZone` остаются в протоколе движка.
  `reportToZone` нужен `solo`: `Solo.onUnanswered` по умолчанию, без
  `Solo.errorHandler`, отдаёт ошибку туда, а `Solo` — не наблюдатель ядра.
- Хук `onUnanswered`, который бросил, ведёт себя как любой хук наблюдателя: его
  ошибка уходит в текущую зону и больше ничего не меняет.

## Что станет с `solo`

- `packages/solo/lib/src/job.dart`: переопределения `notifyError`
  и `handleUnanswered` в `_SoloJob` удаляются вместе с dartdoc.
- `packages/solo/lib/src/solo.dart`: `_SoloJobObserver` получает
  `onUnanswered`, который зовёт
  `Solo._callHook(() => _solo.onUnanswered(...))`. `SoloObserver` второго хука
  не получает: наблюдение ни за что не отвечает (вопрос 3 плана
  `2026-09-22-error-hook-split-plan.md`).
- Поведение `solo` не меняется: порядок тот же — `Solo.observer.onError`,
  `Solo.onError`, затем `Solo.onUnanswered`.

**Зонд 2026-09-25, пробная правка в копии, до ревью.** Ядро: `observer.dart`
частью `job_base.dart`, `onUnanswered` с маршрутом в `_toZone`, `notifyError`
и `handleUnanswered` зовут его при наблюдателе. `solo`: оба переопределения
сняты, `_SoloJobObserver.onUnanswered` добавлен. Итог: `solo` — 791 тест из 791
зелёные, без правки тестов. `async_job` — 43 теста красные: 40 ждут, что ошибка
с наблюдателем в зону не дойдёт, три — список экспортов, трасса `debug_test`,
`implements JobObserver` у трёх тестовых наблюдателей (`JobJournal`,
`_RecordingObserver`, `_ThrowingObserver`, до правки они не собирались и роняли
13 файлов при загрузке). Ревьюер собрал правку ровно по плану, с приватным
`handleUnanswered`: 44 красных из 566 и предупреждение анализатора
в `extending_test.dart:29`; `solo` 791 и его пример 47, `flutter_solo` 85 и его
пример 4 — зелёные.

## Миграция тестов ядра

Каждый красный тест — по смыслу, как в `solo` 2026-09-22.

- **Общие наблюдатели из `test/support` — `ErrorObserver` и `JobJournal` —
  не отвечают.** На них стоят и тесты маршрута: `zone_test.dart:107` («the same
  errors go to the observer when there is one») — на `JobJournal`,
  `parallel_wait_test.dart:501`, единственный сторож фильтра конверта, —
  на `ErrorObserver`. Отвечающий вариант — явный, с именем
  (`ErrorObserver.answering`, `JobJournal(answers: true)` или отдельный класс),
  и тест, который его берёт, говорит почему.
- **Тесты, чей предмет — маршрут**, получают новый маршрут: `onError` и зона.
  Их имена говорят «goes to the observer»: `zone_test.dart` («the same errors
  go to the observer when there is one»), `cleanup_test.dart`,
  `waiting_test.dart`, `late_value_test.dart` («an error of the disposer goes
  to the observer»), `when_cancelled_test.dart`, `unattended_test.dart` («a
  failure of unattended work reaches the observer»), два теста
  `cancellation_rakes_test.dart`, четыре `observing_rakes_test.dart`,
  `debug_test.dart` («the same error is traced when an observer takes it», его
  reason «and it stopped there» станет ложным). Имя меняется вместе
  с утверждением.
- **Тесты, чей предмет другой** — глубина каскада, порядок уборки, группа
  `runAll`, граница `unattended`, — собирают ошибки наблюдателем и не хотят их
  в зоне. Они берут отвечающий вариант.
- **`extending_test.dart`** — сторож протокола движка. Его шапка (`:3-7`)
  называет `handleUnanswered` среди пяти членов, которые держит один `solo`;
  станет четыре. `AnsweringJob` перестаёт переопределять член и ставит
  на задачу свой наблюдатель с `onUnanswered` — так движок отвечает теперь, так
  отвечает и `solo`. Тест `:110` проверяет это, тест `:147` («handleUnanswered
  not overridden goes to the zone») переименовывается.
- Три тестовых наблюдателя с `implements JobObserver` переходят на `extends`
  или `with`. `_ThrowingObserver` обещает «Throws from every hook the engine
  calls» и бросает и из `onUnanswered`.
- `engine_import_test.dart` сверяет список экспортов `lib/async_job.dart`.

## Документация

- `packages/async_job/doc/observing.md` и `docs/ru/async_job/observing.md`.
  Страница сейчас на чтении владельца, и правка идёт в неё же; чтение
  продолжается после.
  - «Observer»: хуков пять; совет `with JobObserver` вместо `implements`.
  - «Where errors go»: первая попытка и `Reporter` остаются — провал после
    принятой отмены по-прежнему слышит один `onError`. Таблица маршрутов —
    по таблице выше. Абзац о двойном слухе становится шире: вне тела ошибка
    тоже приходит и в `onError`, и в зону. Нужен абзац или подраздел об ответе:
    `onUnanswered` по умолчанию несёт ошибку в зону, переопределение отвечает
    здесь. Раздел, где ошибаться станет не на чем, открывается ответом.
  - «Work the job does not wait for»: вывод `ctx.unattended` с `Reporter`
    станет `onError:` и `zone:`. Разница с `unawaited` — не зона, а то, чья
    ошибка: при `unawaited` наблюдатель не слышит ничего, и ошибка приходит
    в зону без задачи; при `ctx.unattended` её слышит наблюдатель задачи,
    а в зону она идёт ту, где задача создана. Вступление раздела («so the app
    hears about the job's errors there») переписывается.
  - Легенда вступления, если в выводе появится строка `onUnanswered`.
- `packages/async_job/doc/outcomes.md` (абзац об ошибке слушателя
  `whenCancelled`), `doc/cleanup.md` (ошибка колбэка уборки),
  `doc/cancellation.md` (`:99-103` о том, что бросит миграция после `wait`,
  и `:166-180` о колбэке `onCancel` и `unattended`), `doc/extending.md` (абзац
  о `handleUnanswered` уходит, ответ движка — его наблюдатель; абзац
  о `reportToZone`), их переводы в `docs/ru/async_job/`.
- Страница `observing.md` прямо говорит, что `JobObserver` — место того, кто
  запускает задачу, и что продолжение `then` наблюдателя источника
  не наследует. `solo` говорит «An observer only watches» о `SoloObserver`
  и реэкспортирует `JobObserver`, который отвечает: иначе два пакета,
  прочитанные подряд, кажутся противоречащими друг другу.
- `packages/async_job/README.md` и `README.ru.md`: абзац об открытии, упавшем
  после отмены, остаётся верным; проверить абзац о наблюдателе.
- dartdoc: `JobObserver` и все его хуки, `JobBase.notifyError`,
  `notifyObserver`, `reportToZone`, `JobBase.finished`,
  `JobContextBase.notifyError`, `Failed` (`outcome.dart`), `Job.whenCancelled`,
  `JobContext.onCancel`, `JobContext.unattended`, `JobContext.wait`,
  `JobContext.join` (`job_context.dart:133-136`), комментарии `_runCleanup`
  («ends there»), `_dispose` и `_race` — всё, что говорит «goes to `onError`»,
  «or to the zone when there is none», «stops there» или «ends there». Dartdoc
  `onUnanswered` называет и `Cancelled`, и конверт из одних отмен.
- `packages/async_job/CHANGELOG.md`: запись **Breaking** в `Unreleased`. Правка
  тихая для `extends JobObserver` — код скомпилируется, и ошибки, которые
  наблюдатель глушил, пойдут в зону, — поэтому в записи сказано, что прежнее
  поведение возвращает одна строка: пустой `onUnanswered`. Громкая для
  `implements JobObserver`: не скомпилируется, и запись говорит про `with`.
  Запись о защищённом `handleUnanswered` (`:205-212`) удаляется: член
  не публиковался — тегов `async_job` два, `v0.1.0` и `v0.2.0`, а запись стоит
  в `Unreleased`, — и записи об удалении ему не нужно.
- `packages/solo/CHANGELOG.md`: запись «Breaking, inherited from `async_job`»
  (`:21`) дополняется `JobObserver.onUnanswered`, а `handleUnanswered` из неё
  уходит (`:30-33`). Второй записи не заводится. Поведение контроллеров
  не меняется.
- `packages/flutter_solo/CHANGELOG.md`: запись «Breaking, inherited from `solo`
  and `async_job`» (`:11`) дополняется: пакет реэкспортирует и ядро.
- `docs/architecture.md`: абзац о маршрутах ядра (около строки 184), строка
  «`observer.dart` — отдельная библиотека» (`:309`, станет `part`) и строка
  о `notifyError` (около строки 377).
- Шапка `2026-09-22-error-hook-split-plan.md`: его открытый вопрос 4
  пересмотрен этим планом.
- `2026-09-25-observing-rakes-report.md`: четвёртый пункт «По чтению
  владельца».

## Сторожа и мутации

Новые сторожа в `packages/async_job/test/observer_test.dart` или своём файле:

- наблюдатель без переопределений маршрут не уносит: ошибка уборки,
  `unattended`, брошенного `wait`, колбэка отмены доходит до зоны создания,
  а не до текущей: `Job.deferred` с наблюдателем создаётся под одним
  `runZonedGuarded`, `start()` зовётся под другим, и ошибку ждут в первом;
- переопределённый `onUnanswered` без `super` берёт ответ: он записал ошибку,
  а зона пуста;
- с `super` — и свой ответ, и зона;
- `onUnanswered` не зовётся для провала тела — ни для `Failed`, ни для провала
  после принятой отмены, ни для покрытого отменой, — а ошибка уборки в той же
  задаче до него доходит;
- на каждое такое событие `onError` один раз и `onUnanswered` один раз,
  `onError` первым;
- провал ветки `runAll`, который группа не бросила, приходит в `onUnanswered`,
  а в `onError` второй раз не приходит;
- `Cancelled` вне тела: `onUnanswered` его получает, тело по умолчанию в зону
  его не несёт; конверт из одних отмен — так же (`parallel_wait_test.dart:501`
  остаётся на неотвечающем наблюдателе);
- ребёнок без своего наблюдателя отвечает наблюдателем родителя;
- `onUnanswered`, который бросил: его ошибка в текущей зоне, задача кончается
  как кончилась бы, остальные хуки вызваны;
- `onError`, который бросил: `onUnanswered` всё равно спрошен, ошибка уборки
  в зоне;
- `with JobObserver` на классе, который наследует другой, получает маршрут
  по умолчанию;
- тело по умолчанию, позванное руками с чужой реализацией `Job`, держит тот же
  фильтр.

В `solo` сторожа есть с 2026-09-22 и зелены на пробной правке; новый — что
`Solo.onUnanswered` слышит одну ошибку один раз и после снятия переопределений.

Мутации: снять маршрут в теле `onUnanswered` по умолчанию; тело по умолчанию
уходит в текущую зону, а не в зону создания; тело по умолчанию без фильтра
конверта; ветка чужой задачи без фильтра; не звать `onUnanswered`
из `notifyError`; не звать его для ветки `runAll`; не звать его для
`Cancelled`; позвать его для провала после принятой отмены; позвать `onError`
второй раз для ветки `runAll`; оба хука в одном `_notify`; вернуть
в `_SoloJobObserver` пустой `onUnanswered`.

## Проверки

`dart format`, `dart analyze`, `dart test` в `packages/async_job`,
`packages/solo` и его примере; `flutter test` в `packages/flutter_solo` и его
примере — они наследуют хуки. Пять документных проверок, два стенда
(`tool/doc_snippets.py`, `tool/accumulation_snippets.py`),
`tool/build_site.py`, `jargon.py` и `bare_names.py` по обеим версиям тронутых
страниц. `pubspec_overrides.yaml` на месте у всех четырёх: правка в нижнем
пакете.

## Порядок

1. Ревью этого плана, вердикты в запись.
2. Ядро: `observer.dart`, `notifyError`, `handleUnanswered`, dartdoc. Сторожа,
   мутации.
3. Миграция тестов ядра.
4. `solo`: снять переопределения, `_SoloJobObserver.onUnanswered`, сторож.
5. Документы, переводы, `CHANGELOG` обоих пакетов, `docs/architecture.md`.
6. Батарея, отчёт, ревью сделанного, коммит.

Дерево зелёное на каждом коммите: ядро и `solo` правятся одним коммитом. Новое
ядро со старым `solo` не собирается: `_SoloJobObserver` не реализует
`onUnanswered`, а `_SoloJob` переопределяет член, которого больше нет.

## Открытые вопросы

Вопросы 1–4 решены ревью (`2026-09-25-core-error-hook-split-plan-review.md`):

1. `handleUnanswered` — приватный. Защищённый звался бы только из `_conclude`,
   а `notifyError` его обходил бы: полудверь.
2. `abstract mixin class` — делать. `mixin` на классе без конструкторов и без
   суперкласса ничего не ломает, при `sdk: ^3.6.0` собирается.
3. `onUnanswered` получает `Cancelled`, брошенный вне тела, и конверт из одних
   отмен, как `Solo.onUnanswered` получает их сегодня. Переопределение, которое
   отвечает само, видит всё, за что отвечает; решение «отмена в зону не идёт»
   принадлежит маршруту по умолчанию, и dartdoc говорит, что `super`
   отбрасывает оба.
4. Наследование: ребёнок без своего наблюдателя получает наблюдателя родителя,
   а с ним и ответ. Продолжение `then` наблюдателя источника не наследует,
   и его ответ по умолчанию уходит в его собственную зону создания.

Для владельца:

5. Провал ребёнка, покрытый отменой, не слышит ни зона, ни `onUnanswered`, если
   исход ребёнка смотрит `ctx.run` или группа `runAll`: `_reportCovered` отдаёт
   ошибку только при ненаблюдённом исходе (`job_base.dart:1347-1354`), а группа
   читает `branch.job.done`, `ctx.run` ждёт значение, и оба исход наблюдают.
   Исход — `Cancelled`, провала в нём нет. Слышит его только `onError`. Так
   было и до правки, и в этой работе это не чинится. Вариант починки: раз
   группа и `run` взяли исход на себя, покрытый провал они отдают
   в `_handleUnanswered`, как `_conclude` отдаёт невыбранный `Failed`; для
   этого задача хранит `failedFirst`.
