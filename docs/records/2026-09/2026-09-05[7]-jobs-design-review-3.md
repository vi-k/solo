> **Состояние на 2026-09-05:** третье ревью получено, вердикт стоит у
> каждой находки. Правки по нему внесены в спеку
> `2026-09-05[4]-jobs-design.md` (четвёртая редакция) тем же днём.
> **Что это:** третье независимое ревью спеки пакета `jobs` (Fable 5.1) —
> проверка того, внесены ли поправки второго ревью, и скелет шва, собранный
> по третьей редакции.
> **Связанные записи:** `2026-09-05[4]-jobs-design.md` (спека),
> `2026-09-05[5]-jobs-design-review.md` и
> `2026-09-05[6]-jobs-design-review-2.md` (первые два ревью).

# Третье ревью спеки `jobs`: заключение Fable 5.1

Задание: проверить, внесены ли тринадцать поправок второго ревью и его
раздел «Что дописать», и не сломали ли они верного; собрать скелет по
третьей редакции и показать анализатором и прогонами, что изменённые
механизмы работают; разобрать переименование `SoloContext`; ответить, можно
ли по спеке писать план; проверить порядок работ.

Ниже текст ревью целиком. По правилу `AGENTS.md` в конец каждой находки
добавлен вердикт отдельным абзацем; проза находок не тронута.

## Вердикт ревьюера

Спека **годится как основа для плана** — после правки в два абзаца, не в
раздел. Все тринадцать поправок внесены по существу, и скелет, собранный по
нынешнему тексту, сходится на всех пробах, по которым второе ревью спеку
правило: чужой контекст ядра больше не усыновляет задачу solo, длинная форма
`handler: child …` переживает снятие ребёнка со списка, ошибки ходят двумя
путями без дублей, `covariant` при `JobBase<T>` с одним параметром чист под
линтами проекта. Две вещи в тексте всё же не дают писать код дословно:
последовательности зовут одним именем `notifyError` два разных пути ошибки —
и буквальное чтение возвращает ту самую двойную отправку в зону, которую
закрывала находка 5 второго ревью; а блок `execute(covariant SoloContext<S,
W> ctx)` с публичным интерфейсом в роли параметра не компилируется — сужать
надо приватной реализацией. Ни одна находка ниже не требует решения
владельца.

## Что закрыто

По находкам второго ревью:

1. Закрыта: контрольную точку зовут `wait`, `join` (дважды) и
   `uncancellable`; `onCancel` — невиртуальная проверка отмены; `run`, `log`,
   `job` — ничего (спека, 331-336). Стенд S1: `{wait: 1, join: 2,
   uncancellable: 1, onCancel: 0, run: 0, log: 0, job: 0, emit: 0}`.
2. Закрыта: ядро в `run` смотрит только на свой статус, «уже в очереди» —
   дело хука наследника (426-434, 486-487). S6: `Bad state: Job(q) has
   already been added or run`.
3. Закрыта: `adoptedBy(parent)` на задаче, `beforeChildStart` на контексте, с
   объяснением, почему так (430-448). S7: задача solo под чужим контекстом
   ядра не стартует.
4. Закрыта: список убывает, связь исход → ребёнок в `Expando` на родителе
   (497-510). S5a/S5b: длинная форма на месте. Но записывать надо ребёнка, а
   не ключ — находка 5.
5. Закрыта: два пути записаны прямым текстом (281-293), `log` без
   наблюдателя — пустая операция. В последовательностях оба пути названы
   одним именем — находка 1.
6. Закрыта: правило префикса снято, одноимённые причины равны осознанно
   (259-264).
7. Закрыта: в шаге 1 — `JobObserver` с адаптером и свой отладочный канал;
   шаг 2 назван «перенос плюс новый код» (592-623).
8. Закрыта: `covariant`, `JobBase<T>` с одним параметром, обоснование про
   `strict-casts` убрано (338-348). Форма блока не компилируется с публичным
   интерфейсом — находка 2.
9. Закрыта: обещание сужено до `Job.deferred` и `Job`, созданной в той же
   синхронной полосе (150-157). C3a/C3b на стенде — как во втором ревью.
10. Закрыта: `start()` без аргументов, уровень ставит `run` до вызова
    (139-140, 394, 436).
11. Закрыта: список членов контекста дополнен `throwIfCancelled` и
    `cancelOwnJob`, хозяева хуков названы (310-323, 377-384). Сеттер
    `cancellable` в блоке без геттера — находка 6.
12. Закрыта: диспозер зовётся независимо от того, ждёт ли кто-нибудь исход;
    `canReleaseAfterCancellation` — дело `scopo`; обе разницы для шага 3
    записаны (553-563).
13. Закрыта: ссылка на инвариант 2 и ленивый путь, тест через `join` в списке
    шага 1 (302-305, 610).

По разделу «Что дописать» второго ревью: имя полного конструктора —
`Cancelled.by`, `@immutable` на `CancelReason`, одна библиотека с
`part`-ами, `cancel()` «не ту же самую», шестое место в API, пять тестов
шага 1, две разницы для `scopo` — всё есть. Не дописано одно: «`JobBase`:
сигнатура конструктора, тип `children`, что делает `finish` на уже
законченной задаче, кто снимает ребёнка со списка» — из четырёх сделан
только последний пункт (509-510), а вердикт говорил «остальное дописывается
дословно». Это находка 3.

Ничего из прежде верного правки не сломали: ссылки `job.dart:104`, `:189`,
`:235`, `:240-257`, `:315-319`; `job_context.dart:48`, `:186`, `:201-216`,
`:302-304`, `:386-391`, `:423`; `outcome.dart:93-98`, `:101-103`;
`solo_base.dart:266`, `:476`; `children_test.dart:109`, `:229`;
`scope_init_context.dart:50`, `:79-82`; `async_data_scope_core.dart:116-127`;
`async_scope_core.dart:294-299`, `:927-928`; `scope_dependency_group.dart:288`
— все на месте. Неверных находок прошлых ревью, под которые спека прогнулась
бы, не нашёл; ближе всего к этому `covariant` (находка 8 второго ревью):
сама форма верна, но стенд второго ревью проверил её на классе-наследнике, а
спека применила к интерфейсу — отсюда находка 2.

**Вердикт (2026-09-05):** Принято. Разбор совпадает с моим прочтением: все
тринадцать поправок на месте, и единственное невнесённое — блок `JobBase`,
который во втором ревью стоял в «Что дописать», а не в находках. Он и стал
находкой 3.

## Находки

**1 [important] — Одно имя `notifyError` для двух путей ошибки: буквальное
чтение последовательностей возвращает двойную отправку в зону.** Раздел о
наблюдателе разводит пути верно (спека, 281-293): ошибка тела — наблюдателю,
а в зону только через необслуженный исход; три «безысходные» ошибки —
наблюдателю, а без него сразу в зону. Но последовательность выполнения тела
говорит «`on Object` — `notifyError`, затем `Failed`» (403-404) и «ошибка
диспозера уходит в `notifyError`» (406-407), а у `JobContextBase` объявлен
один `notifyError` (314), которым ходят поздняя ошибка `wait` и колбэк
`onCancel`. Ошибка диспозера и ошибка тела одним методом идти не могут:
первая без наблюдателя обязана попасть в зону сразу, вторая — нет.
Реализатор либо делает `notifyError` «наблюдатель или зона» и получает
C4 = 1, C5 = 2 из второго ревью, либо «только наблюдатель» и теряет три
безысходные ошибки без наблюдателя — то, от чего уходило первое ревью
(находка 8). Стенд с двумя методами — приватный путь тела «только
наблюдатель» и защищённый `notifyError` «наблюдатель или зона создания» —
даёт C4 = 0, C5 = 1, C6a/b/c = 1 в зоне, C6d = 0 в зоне и три записи у
наблюдателя, C8 — обработанный `Failed` при наблюдателе в зону не идёт,
необслуженный идёт один раз. Второй метод надо назвать в блоке и в шагах 2 и
4 выполнения тела.

**Вердикт (2026-09-05):** Принято. Два пути расходятся не только в прозе, но
и в именах: ошибка тела идёт `notifyObserver`, который без наблюдателя
молчит (в зону она попадёт исходом), а `notifyError` остаётся «наблюдателю,
а без него — в зону создания» и обслуживает три безысходные ошибки, включая
ошибку диспозера. Оба имени идут в блок и в шаги выполнения тела.

**2 [important] — `execute(covariant SoloContext<S, W> ctx)` с публичным
интерфейсом не компилируется; шаг 1 смешивает интерфейс и реализацию.**
`SoloContext<S, W>` по спеке — переименованный публичный интерфейс (534-538),
«поверх контекста ядра» (514-516), то есть `abstract interface class …
implements JobContext`, как велит таблица модификаторов
(`docs/conventions.md:40-43`). `covariant` требует, чтобы новый тип параметра
был в отношении подтипа с прежним, а интерфейс с `JobContextBase` в таком
отношении не состоит. Стенд `variant`: `error - lib/variant.dart:40:13 -
'SpecFormJob.execute' ('Future<T> Function(PublicContext)') isn't a valid
override of 'JobBase.execute' ('Future<T> Function(JobContextBase)') -
invalid_override`. Та же сигнатура с приватной реализацией (`covariant
PublicImpl ctx`, где `PublicImpl extends JobContextBase implements
PublicContext`) чиста, и потребитель на стенде собран так —
`execute(covariant _SoloContext<S, W, T> ctx)`, `No issues found!`;
приватный тип в сигнатуре приватного класса линт
`library_private_types_in_public_api` не трогает. Второй выход — сделать
`SoloContext` классом, наследующим `JobContextBase`, — хуже: «фейковый
`JobContext` для теста тела задачи без движка»
(`2026-09-02[1]-solo-design.md`, 3.6) получил бы в интерфейс восемь
защищённых членов основы. Отсюда правка и в шаге 1: «разделить `_JobContext`
на `JobContextBase` + `SoloContext`» (592-593) читается так, будто
`SoloContext` — половина реализации; надо: `_JobContext` → `JobContextBase`
+ `_SoloContext`, а публичный `JobContext<S, W>` → `SoloContext<S, W>`. У
`scopo` та же ситуация с `ScopeInitContext` (`abstract interface class`,
`scope_init_context.dart:28`) — сужать приватным типом.

**Вердикт (2026-09-05):** Принято, с проверенным обоснованием: `SoloContext`
и `JobContextBase` — не родственники, они оба лишь реализуют `JobContext`
ядра, поэтому сужение к интерфейсу — неверный override. Сужаем к приватной
реализации, и в шаге 1 разводятся три имени: `JobContextBase` (основа
ядра), `_SoloContext` (реализация solo), `SoloContext<S, W>` (публичный
интерфейс solo).

**3 [minor] — У `JobBase` нет блока, как у `JobContextBase`: защищённая
поверхность, конструктор и `finish` на законченной задаче остаются на
выдумку плана.** Блок (325-328) показывает два члена; остальное разбросано
по прозе без имён: «старт, завершение исходом, отмена с флагом
отклоняемости, чтение статуса, чтение `pendingCancel`, список детей,
ожидание завершения без наблюдения» (373-376), хуки `started()`/`finished()`
(395, 414), `adoptedBy` (430), безымянная «внутренняя форма» отмены, «она
виртуальная» (456-458). Это публичное API пакета — по нему пишет `scopo`, —
и имена ему нужны так же, как контексту. Чего нет совсем: сигнатуры
конструктора (у `Job(...)` она есть, у основы — нет), типа `children`, что
делает `finish` на уже законченной задаче (сегодня `_finish` без защиты,
`job.dart:274`; второй вызов упадёт в `Completer` — `StateError` случайный,
не обещанный), и одного члена в списке нужд движка — чтения `cancellable`:
`SoloQueue.remove` читает `job.cancellable` (`queue.dart:57`), и потребитель
на стенде без обёртки даёт `warning - lib/src/solo_base.dart:182:25 - The
member 'cancellable' can only be used within instance members of subclasses
of 'JobBase'`. Мелочь по порядку: шаг 2 `run` («ядро смотрит только на свой
статус») стоит раньше шага 3 («ядро проверяет, что ребёнок его типа») —
статус читать не у чего, пока тип не проверен; проверка типа идёт первой, с
`ArgumentError`.

**Вердикт (2026-09-05):** Принято целиком. У `JobBase` появляется такой же
блок, как у `JobContextBase`, с конструктором, типом `children`, именами
хуков и защищённых членов; `finish` на законченной задаче — молча ничего,
как `cancel`; чтение `cancellable` идёт в список нужд движка; проверка типа
в `run` встаёт перед чтением статуса.

**4 [minor] — Последовательность `finish` не знает про снятие ребёнка со
списка и запись в `Expando`.** Раздел «Дети» говорит «законченный ребёнок
снимается» и «запись делается при завершении ребёнка» (497-507), а
`finish(outcome)` (410-419) перечисляет шесть шагов без этого. Порядок
объявлен частью контракта (388-389), и здесь он наблюдаем: `children`
родителя в хуке `finished()` и в `onFinish` наблюдателя либо ещё содержит
ребёнка, либо уже нет. На стенде снятие и запись стоят между `whenCancelled`
и `finished()`; спеке надо назвать место.

**Вердикт (2026-09-05):** Принято, место называется: между завершением
`whenCancelled` и хуком `finished()`, как на стенде.

**5 [minor] — В `Expando` надо класть ребёнка, а не его ключ: ребёнок без
ключа теряет длинную форму.** Спека: «связь «исход → ключ ребёнка»»
(504-506). Значение `Expando`, равное `null`, — это отсутствие записи, а
ключ у задачи необязателен. Сегодня ребёнок без ключа, отклонённый
правилами, описывается как `Cancelled(handler: child null: Cancelled(rules:
is not B))` — проба `probe2/bin/nullkey.dart` на нынешнем `packages/solo`;
при записи ключа `_handlerCancel` дал бы короткую форму. На стенде
`Expando<JobBase<Object?>>`, S5c: `Cancelled(handler: child null:
Cancelled(rules: is not Working))`. Заодно правило, которого в тексте нет:
ключ `Expando` — сам экземпляр исхода, поэтому ребёнка нельзя завершать
канонизированной константой (две одинаковые `const Cancelled.by(...)` — один
объект, одна запись). Сегодня это держится само: каждый `Cancelled` движка
несёт `StackTrace` времени выполнения, а брошенный телом `const
Cancelled('why')` в `Expando` только ищется — S5d.

**Вердикт (2026-09-05):** Принято. В `Expando` кладётся ребёнок; правило про
канонизированные константы идёт в текст рядом — оно неочевидно и держится
сегодня случайно, на том, что у каждой отмены движка свой стектрейс.

**6 [minor] — `@protected set cancellable(bool value)` без геттера: линт
проекта и сам `uncancellable`.** В блоке `JobContextBase` (317) один сеттер.
`avoid_setters_without_getters` включён (`analysis_options.yaml:120`), стенд:
`info - lib/variant.dart:62:7 - Setter has no corresponding getter -
avoid_setters_without_getters`. И геттер нужен по делу: `uncancellable`
запоминает прежнее значение и восстанавливает его
(`job_context.dart:292-297`). В блок — пара.

**Вердикт (2026-09-05):** Принято, в блок идёт пара.

**7 [minor] — `adoptedBy` у solo обещает `StateError` и за чужой
контроллер, и за очередь; за чужой контроллер по соглашениям —
`ArgumentError`.** Спека: «требует, чтобы родителем был контекст того же
контроллера и чтобы задача не стояла в его очереди, иначе `StateError`»
(432-434). `docs/conventions.md:36-37`: `StateError` — нарушение жизненного
цикла, `ArgumentError` — неверный аргумент. Задача чужого контроллера —
неверный аргумент, и сегодня оба входа так и отвечают: `add` —
`throwsArgumentError` (`queue_test.dart:110-114`), `ctx.run` — через `_own`
(`job_context.dart:388`, `solo_base.dart:313-317`). Стенд: чужой контроллер
— `ArgumentError`, очередь — `StateError` (S7, S6). Одно слово в спеке,
иначе тест шага 1 «усыновление чужим контекстом — отказ» напишут на не тот
тип.

**Вердикт (2026-09-05):** Принято: чужой контроллер — `ArgumentError`,
очередь — `StateError`, как отвечают оба входа сегодня.

**8 [minor] — `Job.deferred` не может быть конструктором: он возвращает
`DeferredJob<T>`.** «Два конструктора» (127-141): фабричный конструктор
класса `Job` возвращает `Job<T>`, подтип он вернуть не может. На стенде это
`static DeferredJob<T> deferred<T>(body, {...})` — чисто под
`prefer_constructors_over_static_methods` (`analysis_options.yaml:180`),
потому что тип результата не совпадает с классом; вызов —
`Job.deferred<int>(...)` (C2, C9). Либо назвать статическим методом, либо
дать `DeferredJob` свой конструктор `DeferredJob(body, {...})`. Это форма
API, решать в спеке.

**Вердикт (2026-09-05):** Принято по существу, обоснование уточняю: фабрика
вернуть экземпляр подтипа как раз может, но статический тип выражения
останется `Job<T>`, и `start()` у вызывающего пропадёт — а нужен именно он.
Беру статический метод: `Job.deferred(...)` на месте вызова читается так же,
как конструктор, и отдаёт `DeferredJob<T>`.

**9 [minor] — Цена шага 2: `tool/doc_snippets.py` собирает корневой пакет на
`solo` по пути, и ему тоже нужен оверрайд на `jobs`; правки `docs/` не
названы.** `SOLO_PUBSPEC` в `tool/doc_snippets.py:42-56` пишет `solo: path:
…` без `dependency_overrides`; после выноса `solo_check` — корень, оверрайд
из `pubspec.yaml` solo он не применит (спека сама объясняет это для
`flutter_solo` и примера, 620-622). `docs/conventions.md:83-86` требует
гонять эти стенды после любой правки фрагментов — значит, скрипт правится в
шаге 2. Туда же: `docs/architecture.md:131-167` (раскладка и карта модулей) и
таблица модификаторов в `docs/conventions.md:40-46`, где назван `JobContext`
и где появятся `JobBase`/`JobContextBase` «без `base`»; свой оверрайд на
`jobs` у самого `solo`; записи `CHANGELOG.md` обоих пакетов и пол `solo:
^0.2.0` у `flutter_solo`.

**Вердикт (2026-09-05):** Принято, всё перечисленное идёт в «Цену шага 2».
`doc_snippets.py` — находка не бумажная: без оверрайда стенды фрагментов
`vs-bloc.md` перестанут собираться в тот же день, когда `solo` сядет на
`jobs`.

## Скелет под третью редакцию

Стенды в скретчпаде, каталог `seam3/`, отдельно от `seam/` второго ревью
(тот остался под вторую редакцию: `JobBase<T, C>`, `adopt` на контексте,
`Cancelled.of`):

- `seam3/core` — одна библиотека с `part`-ами (`jobs.dart`: `job.dart`,
  `job_context.dart`, `job_stream.dart`, `observer.dart`, `outcome.dart`).
  `JobBase<T>` с одним параметром типа и `execute(JobContextBase ctx)`;
  `adoptedBy(JobContextBase parent)` на задаче; `start()` без аргументов;
  убывающий список детей с ленивым `Expando<JobBase<Object?>>` на родителе;
  два пути ошибки; `Cancelled.by`; `@immutable CancelReason`; `Job(...)` как
  фабрика и `Job.deferred` как статический метод; `DeferredJob`; `each` на
  контексте ядра; вызовы наблюдателя изолированы, как `_callHook` у solo.
  Последовательности `start`, тела, `finish`, `run`, `cancel` — по спеке, не
  заглушки.
- `seam3/consumer` — `SoloContext<S, W>` как публичный интерфейс поверх
  `JobContext` и `_SoloContext` с переопределёнными `check()` и
  `beforeChildStart`; `_SoloJob extends JobBase<T> implements SoloJob<T>` с
  `execute(covariant _SoloContext<S, W, T> ctx)`, `adoptedBy`, веткой очереди
  в `cancelWith` и семью обёртками (`_launch`, `_drop`, `_cancelWith`,
  `_pending`, `_whenDone`, `_status`, `_cancellable`); `SoloCancelReason`,
  `SoloObserver` с адаптером; реэкспорт ядра целиком, без `hide`.
- `seam3/variant` — боковые проверки; `probe2/bin/nullkey.dart` — на нынешнем
  `packages/solo`.

`analysis_options.yaml` в каждом — копия
`packages/solo/analysis_options.yaml`. Результат:

- `core`: `No issues found!`.
- `consumer`: `No issues found!`. Первый прогон дал одно предупреждение —
  чтение `cancellable` из `SoloBase.remove` (находка 3); после обёртки чисто.
  Реэкспорт без `hide` не конфликтует.
- `variant`: спековая форма `covariant` с интерфейсом — `invalid_override`
  (находка 2); с приватной реализацией — чисто; сеттер без геттера —
  `avoid_setters_without_getters` (находка 6); прямые
  `finish`/`cancelWith`/`pendingCancel` из класса-не-наследника — три
  `invalid_use_of_protected_member`, `start()` через тип `JobBase` —
  четвёртое, через `DeferredJob` — чисто; `abstract final class` из
  статических констант — чисто.

Прогон `seam3/consumer/bin/probe.dart`:

```
S1 check() calls per member: {wait: 1, join: 2, uncancellable: 1, onCancel: 0, run: 0, log: 0, job: 0, emit: 0}
S2 rule broken by the body, found by the core join: Cancelled(rules: is not NotDisposed)
S3 onFinish sees: [a: current=null, b: current=null]
S3 listener of a.done sees: b.isRunning=true
S4a during the disposer: outcome=null closed=false; after: Cancelled(manual) closed=true
S4a journal: [[db] started, disposed DB, [db] finished Cancelled(manual)]
S4b disposer threw, onError before onFinish: [[db] started, [db] error Bad state: cannot close DB, [db] finished Cancelled(manual)]
S4c children -> disposer -> finish: [[parent] started, > [child] started, > [child] finished Cancelled(parent), disposed R, [parent] finished Cancelled(manual)]
S5a dropped at run, via the Expando: [parent] finished Cancelled(handler: child child: Cancelled(rules: is not Working))
S5b cancelled by keepWhile, via the Expando: [parent] finished Cancelled(handler: child child: Cancelled(rules: keepWhile))
S5c child without a key: [parent] finished Cancelled(handler: child null: Cancelled(rules: is not Working))
S5d const Cancelled thrown by the body: [parent] finished Cancelled(handler: why)
S6 ctx.run(queued job): Bad state: Job(q) has already been added or run
S7 solo job adopted by a core context while another solo job is current: stray=null isRunning=false, blocker still running=true, state=Initial()
S7 foreign job: Failed(Invalid argument (child): was not created by this Solo: Instance of '_SoloJob<TestState, TestState, void>')
S7 journal: [[blocker] started]
S7 the refused job, queued afterwards: Done(null)
S8 cancel() of a queued cancellable:false job: isQueued=true outcome=null
S8 remove: false, forced: true, outcome=Cancelled(manual) isQueued=false
C1 cancelled before start: Cancelled(manual), body ran: false
C2 deferred: Done(2), second start: Bad state: Job(null) has already started
C3a auto child created inside the body: Done(3)
C3b auto child created before the parent: Done(-50) (negative = StateError in the body), child: Done(3)
C4 handled Failed, no observer, zone got: 0
C5 unobserved Failed, no observer, zone got: 1
C9 deferred child adopted by run: Done(4), start() by hand afterwards: Bad state: Job(null) has already started
C6a late error of a wait-abandoned action, no observer, zone got: [FormatException: late]
C6b ifCancelled error, no observer, zone got: [Bad state: cannot close DB]
C6c onCancel callback error, no observer, zone got: [Bad state: callback]
C6d the same three with an observer: zone got 0, observer got: ([c] error Bad state: callback, [b] error Bad state: cannot close DB, [a] error FormatException: late)
C7 log without an observer: Done(null), zone got 0
C8 body errors with an observer: zone got 1 (the unobserved one), observer got: ([h] error FormatException: boom, [u] error FormatException: boom)
```

Что пробы показали против того, что во втором ревью не сходилось: S7 —
`stray` не стартовал (`outcome=null`, `isRunning=false`), `blocker` работает,
состояние `Initial()`, чужая задача кончилась `Failed(ArgumentError)`, а
отвергнутая задача потом прошла через очередь — `Done(null)`; S5a/S5b —
длинная форма при снятом со списка ребёнке, и отклонённом в `run`, и
отменённом `keepWhile`; C4/C5 и C6–C8 — два пути без дублей; S1 — точки
проверки по инварианту 2; S4a/b/c — «дети → диспозер → finish», `close()`
ждёт освобождение (`closed=false` во время диспозера), ошибка диспозера в
`onError` до `onFinish`; S8 — ветка очереди solo: очередная неотменяемая
отказывает `cancel()` и `remove`, снимается только `force`; C9 — `start()`
вручную у усыновлённой `Job.deferred` — `StateError`. Обещания порядка (S3)
держатся, как и во втором ревью.

**Вердикт (2026-09-05):** Принято как главный результат третьего захода: под
нынешним текстом шов собран заново, и все пробы, по которым правили спеку во
втором заходе, теперь сходятся. Два расхождения скелета с текстом — находки
1 и 2 — правятся в спеке, а не в скелете.

### Переименование `SoloContext`

Что задевает, по `grep` в дереве:

- `lib/`: объявление и `_JobContext` (`job_context.dart:15, 177-178`), тип
  тела в `job.dart:91` и `solo_base.dart:86, 168`, extension `JobStream`
  (`job_stream.dart:6`) — он переезжает на `JobContext` ядра. Дартдоки
  `[JobContext.wait]`, `[JobContext.log]`, `[JobContext.uncancellable]`,
  `[JobContext.run]` (`job.dart:23, 66`; `solo_base.dart:83, 294, 306`;
  `observer.dart:22, 42`; `outcome.dart:52, 70`) остаются верными: `solo`
  реэкспортирует `JobContext` ядра, и это его члены. Меняется только
  `[JobContext.stateAs]` (`outcome.dart:9`) — это `SoloContext.stateAs`, и
  строка всё равно уезжает в дартдок `SoloCancelReason.rules`.
- Тесты: шесть строк в четырёх файлах — `leaked_context_test.dart:22, 47,
  67`, `children_test.dart:414`, `on_cancel_test.dart:159`,
  `support/run_solo.dart:34` (`pause`). Тела задач имя не пишут — верно.
- `README.md:129, 150, 240` и `README.ru.md:134, 156, 247`. Строка 240 про
  `each` («an extension on `JobContext`») после выноса становится буквально
  верной, но объяснить в ней придётся, что это контекст ядра.
- `flutter_solo`: в `lib/` и тестах имени нет, только `CHANGELOG.md:5` —
  история, не правится. `packages/solo/example`, `doc/vs-bloc.md`,
  `docs/ru/`, корневые README — нет.
- `docs/architecture.md:155, 161`, `docs/conventions.md:41`, новая запись в
  `CHANGELOG.md` solo.
- Реэкспорт `jobs` без `hide`: собран на стенде
  (`seam3/consumer/lib/consumer.dart`), анализатор чист.

Мест, где спека всё ещё подразумевает старое имя, нет; единственная
двусмысленность — шаг 1 (находка 2).

**Вердикт (2026-09-05):** Принято к сведению как инвентарь для плана:
шестнадцать строк в `lib/`, шесть в тестах, шесть в README обоих языков, три
в `docs/`. Отдельно ценно, что дартдоки `[JobContext.…]` остаются верными
после реэкспорта — переименование дешевле, чем казалось.

### Порядок работ

Шаг 1 реалистичен: это рефакторинг внутренностей solo под 223 тестами,
публичное API меняется в названных шести местах. Список полон по существу,
но четыре вещи в нём подразумеваются, а не названы, и план их всё равно
выпишет: публичный `JobContext` без параметров типа внутри solo (иначе
`JobContextBase implements JobContext` не из чего собрать), само
переименование в `SoloContext` со всем инвентарём выше, перенос `each` на
этот интерфейс, три статуса у основы с `isQueued` по членству на
`SoloJob<T>`. Шаг 2 — находка 9. Шаги 3 и 4 — без замечаний; для `scopo` к
двум записанным разницам добавляется находка 2 (сужение приватным типом).

Готовность для плана: по спеке можно писать задачи и коммиты; выдумывать по
дороге пришлось бы ровно то, что перечислено в находках 1-3 и 6-8 и в «Что
дописать» ниже — имена защищённых членов `JobBase` и его конструктор, второй
метод для ошибки тела, форму отладочного канала, ответ solo на чужого
ребёнка, тип ошибки в `adoptedBy`. Каждое — абзац, ни одно не требует
решения владельца.

**Вердикт (2026-09-05):** Принято. Четыре подразумеваемые вещи выписываются
в шаг 1 явно, чтобы план не выводил их заново.

## Что дописать

- Второй метод для ошибки тела — в блок `JobBase` и в шаги 2 и 4 выполнения
  тела (находка 1).
- Блок `JobBase`: конструктор `{key, describe, cancellable, ifCancelled,
  observer}`, `status`, `pendingCancel`, `whenDone`, `children` с типом,
  `start()`, `finish(outcome)` и что он делает на законченной задаче,
  виртуальная отмена с флагом, `started()`, `finished()`,
  `adoptedBy(parent)`; чтение `cancellable` в список нужд движка (находка 3).
  Публичен ли `JobStatus` — тип защищённого `status` не спрячешь.
- `execute(covariant _SoloContext<S, W, T> ctx)` и правка шага 1: интерфейс
  отдельно от реализации (находка 2).
- Отладочный канал ядра: «свой» (587-588, 598-599) — где живёт и какой
  формы; сегодня это статик `SoloBase.debug`.
- Изоляция хуков `JobObserver`: инвариант 10 (`docs/architecture.md:124-129`)
  для ядра не записан; на стенде вызовы обёрнуты, как `_callHook`
  (`solo_base.dart:55-61`).
- Что делает solo с ребёнком, который не его: `soloCtx.run(Job(...))`
  проходит проверку типа ядра и пустой `adoptedBy` ядра, а в
  `beforeChildStart` solo падает на `_own` — стенд
  `seam3/consumer/bin/probe_s9.dart`: `Failed(ArgumentError)`. Принимать без
  правил и вне `_running` или отказывать — сказать.
- Правило для `Expando`: ключ — свежий экземпляр исхода, значение — ребёнок
  (находка 5); место снятия и записи в `finish` (находка 4).
- `Job.deferred` — статический метод или конструктор `DeferredJob` (находка
  8); тип ошибки в `adoptedBy` (находка 7); геттер `cancellable` (находка 6).
- Цена шага 2: `doc_snippets.py`, `docs/`, оверрайд у `solo`, `CHANGELOG`,
  пол `flutter_solo` (находка 9).

Чего проверить не смог: `dart doc` на скелете не гонял — дартдоки стенда
написаны ради линта, а не как документация; тесты `scopo` не запускались по
условию задания; `FakeAsync` в пробах не использовал — стенд идёт на
реальном времени с миллисекундными задержками, на порядок событий это не
влияет, но сьюта ядра по соглашениям пойдёт под `FakeAsync`, и микротаска
старта там проверяется `flushMicrotasks`, а не `flushTimers`.

**Вердикт (2026-09-05):** Список принят как оглавление четвёртой редакции.
Два решения принимаются здесь: `JobStatus` публичен (тип защищённого члена
не спрячешь, а `scopo` он понадобится), и чужой ребёнок у solo получает
отказ `ArgumentError` — принимать задачу, которой контроллер не владеет, он
не будет ни на каких условиях.
