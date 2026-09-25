# Разделение хука ошибки в ядре: оповещение отдельно, ответ отдельно

> **Состояние на 2026-09-25:** план написан, ждёт независимого ревью; правки
> в коде нет.
> **Что это:** план правки `async_job`: `JobObserver.onError` становится
> чистым оповещением, ответ за ошибку, которую не несёт ни один исход,
> переезжает в новый хук наблюдателя `onUnanswered`, а движок `solo` теряет
> свои переопределения `notifyError` и `handleUnanswered`.
> **Связанные записи:** `2026-09-22-error-hook-split-plan.md` (та же правка
> в `solo`, открытый вопрос 4 которого этот план пересматривает),
> `2026-09-22-error-hook-split-report.md`,
> `2026-09-25-observing-rakes-report.md` (вычитка страницы, откуда пришёл
> вопрос).

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
  /// [Cancelled], which goes nowhere. Override it to answer here instead;
  /// call `super.onUnanswered(job, error, stackTrace)` to keep the zone as
  /// well.
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

Меняется одна строка из пяти в таблице раздела «Where errors go» и ещё одна,
которой там нет.

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
  реализацией `Job`, тело по умолчанию отдаёт ошибку текущей зоне, кроме
  `Cancelled`.
- `JobObserver` становится `abstract mixin class`. Класс, который уже наследует
  другой, подмешивает его `with JobObserver` и получает тела по умолчанию,
  в том числе маршрут `onUnanswered`. `implements JobObserver` после правки
  не компилируется, пока класс не напишет `onUnanswered` сам, а написать
  маршрут в зону создания он не может: зона закрыта. Поэтому страница советует
  `with`, а не `implements`.
- `JobBase.notifyError`: оповещение, как сейчас, затем ответ — с наблюдателем
  его `onUnanswered` через `_notify`, без наблюдателя `_toZone`. Трасса
  `JobBase.debug` остаётся прежней.
- `JobBase.handleUnanswered` становится приватным: единственное место вызова —
  `_conclude` у `runAll`, а переопределял его только движок `solo`, которому
  после правки это не нужно. Его dartdoc сегодня велит движку переопределять
  его, иначе «the kernel takes the observer for the answer and the error stops
  there»; после правки ответ движка — это `onUnanswered` его собственного
  наблюдателя. Вариант оставить его защищённым — открытый вопрос 1.
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

**Зонд 2026-09-25, пробная правка в копии.** Ядро: `observer.dart` частью
`job_base.dart`, `onUnanswered` с маршрутом в `_toZone`, `notifyError`
и `handleUnanswered` зовут его при наблюдателе. `solo`: оба переопределения
сняты, `_SoloJobObserver.onUnanswered` добавлен. Итог: `solo` — 791 тест из 791
зелёные, без правки тестов. `async_job` — 43 теста красные: 40 ждут, что ошибка
с наблюдателем в зону не дойдёт, три — список экспортов, трасса `debug_test`,
`implements JobObserver` у трёх тестовых наблюдателей (`JobJournal`,
`_RecordingObserver`, `_ThrowingObserver`, до правки они не собирались и роняли
13 файлов при загрузке).

## Миграция тестов ядра

Каждый красный тест — по смыслу, как в `solo` 2026-09-22.

- **Тесты, чей предмет — маршрут**, получают новый маршрут: `onError` и зона.
  Их имена говорят «goes to the observer»: `zone_test.dart` («the same errors
  go to the observer when there is one»), `cleanup_test.dart`,
  `waiting_test.dart`, `late_value_test.dart` («an error of the disposer goes
  to the observer»), `when_cancelled_test.dart`, `unattended_test.dart` («a
  failure of unattended work reaches the observer»), два теста
  `cancellation_rakes_test.dart`, четыре `observing_rakes_test.dart`. Имя
  меняется вместе с утверждением.
- **Тесты, чей предмет другой** — глубина каскада, порядок уборки, группа
  `runAll`, граница `unattended`, — собирают ошибки наблюдателем и не хотят их
  в зоне. Их наблюдатель отвечает сам: `onUnanswered` переопределён. Для
  `ErrorObserver` и `JobJournal` из `test/support` это одна строка
  с комментарием, почему.
- Три тестовых наблюдателя с `implements JobObserver` переходят на `extends`
  или `with`.

Список уточняется по прогону: пробная правка — не та, что будет, и трасса
`debug_test` может остаться зелёной.

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
  `doc/extending.md` (абзац о `handleUnanswered` и абзац о `reportToZone`), их
  переводы.
- `packages/async_job/README.md` и `README.ru.md`: абзац об открытии, упавшем
  после отмены, остаётся верным; проверить абзац о наблюдателе.
- dartdoc: `JobObserver` и все его хуки, `JobBase.notifyError`,
  `notifyObserver`, `reportToZone`, `JobContextBase.notifyError`, `Failed`
  (`outcome.dart`), `Job.whenCancelled`, `JobContext.onCancel`,
  `JobContext.unattended`, `JobContext.wait` — всё, что говорит «goes to
  `onError`», «or to the zone when there is none» или «stops there».
- `packages/async_job/CHANGELOG.md`: запись **Breaking** в `Unreleased`. Правка
  тихая для `extends JobObserver` — код скомпилируется, и ошибки, которые
  наблюдатель глушил, пойдут в зону, — поэтому в записи сказано, что прежнее
  поведение возвращает одна строка: пустой `onUnanswered`. Громкая для
  `implements JobObserver`: не скомпилируется, и запись говорит про `with`. Для
  протокола движка — `handleUnanswered` ушёл, ответ движка — его наблюдатель.
- `packages/solo/CHANGELOG.md`: запись «Breaking, inherited from `async_job`» —
  `solo` реэкспортирует ядро целиком, `JobObserver` вместе с ним. Поведение
  контроллеров не меняется.
- `docs/architecture.md`: абзац о маршрутах ядра (около строки 184) и строка
  о `notifyError` (около строки 377).
- `2026-09-25-observing-rakes-report.md`: четвёртый пункт «По чтению
  владельца».

## Сторожа и мутации

Новые сторожа в `packages/async_job/test/observer_test.dart` или своём файле:

- наблюдатель без переопределений маршрут не уносит: ошибка уборки,
  `unattended`, брошенного `wait`, колбэка отмены доходит до зоны;
- переопределённый `onUnanswered` без `super` берёт ответ: зона пуста;
- с `super` — и свой ответ, и зона;
- `onUnanswered` не зовётся для провала тела — ни для `Failed`, ни для провала
  после принятой отмены, ни для покрытого отменой;
- на каждое такое событие `onError` один раз и `onUnanswered` один раз,
  `onError` первым;
- провал ветки `runAll`, который группа не бросила, приходит в `onUnanswered`,
  а в `onError` второй раз не приходит;
- `Cancelled` вне тела: `onUnanswered` его получает, тело по умолчанию в зону
  его не несёт;
- ребёнок без своего наблюдателя отвечает наблюдателем родителя;
- `onUnanswered`, который бросил: его ошибка в текущей зоне, задача кончается
  как кончилась бы, остальные хуки вызваны;
- `with JobObserver` на классе, который наследует другой, получает маршрут
  по умолчанию.

В `solo` сторожа есть с 2026-09-22 и зелены на пробной правке; новый — что
`Solo.onUnanswered` слышит одну ошибку один раз и после снятия переопределений.

Мутации: снять маршрут в теле `onUnanswered` по умолчанию; не звать
`onUnanswered` из `notifyError`; не звать его для ветки `runAll`; позвать его
для провала после принятой отмены; позвать `onError` второй раз для ветки
`runAll`; вернуть в `_SoloJobObserver` пустой `onUnanswered`.

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

Дерево зелёное на каждом коммите: ядро и `solo` правятся одним коммитом, иначе
`solo` против нового ядра звал бы `onUnanswered` дважды — своим
переопределением `notifyError` и через наблюдателя.

## Открытые вопросы

1. `handleUnanswered`: приватным или оставить защищённым? Приватный убирает
   из протокола второй путь ответа, и абзац `extending.md` о нём исчезает
   целиком. Защищённый оставляет движку способ ответить мимо наблюдателя,
   которым сегодня никто не пользуется. Предложение — приватный.
2. `abstract mixin class`: цена — ещё одно изменение API; без него класс,
   который уже наследует другой, остаётся без маршрута по умолчанию.
   Предложение — делать.
3. `onUnanswered` получает `Cancelled`, брошенный вне тела, как
   `Solo.onUnanswered` его получает сегодня. Альтернатива — не звать хук для
   `Cancelled` вовсе. Предложение — звать: переопределение, которое отвечает
   само, должно видеть всё, за что отвечает, а решение «отмена в зону не идёт»
   принадлежит маршруту по умолчанию.
4. Наследование: ребёнок без своего наблюдателя получает наблюдателя родителя,
   а с ним и ответ. Отдельного правила для ответа нет — это довод за хук
   на наблюдателе, а не параметр `Job`.
