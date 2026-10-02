> **Состояние на 2026-10-02:** вычитка сделана в `main`, находки независимого
> ревью закрыты тем же коммитом; владелец читает страницу с 2026-10-02, правки
> по его вопросам — в разделе «По чтению владельца».
> **Что это:** отчёт о вычитке `packages/async_job/doc/extending.md` и её
> перевода — двенадцать мест по чтению, двенадцать находок ревью, одиннадцать
> новых сторожей, двадцать одна мутация.
> **Связанные записи:** `2026-10-02-extending-rakes-review-report.md`,
> `2026-09-28-extending-page-report.md`,
> `2026-10-01-self-give-up-callbacks-report.md`,
> `2026-09-25-observing-rakes-report.md`,
> `2026-09-11[16]-docs-structure-design.md`.

# Вычитка extending.md

## Что было

Страницу перестроили 2026-09-28 по находкам ревью `async_job`
(`2026-09-28-extending-page-report.md`): четыре раздела, два из них с первой
попыткой, сторож `packages/async_job/test/extending_rakes_test.dart`.
2026-10-01 из раздела о правиле ушли вторая попытка и ответ через
`cancelOwnJob` (`2026-10-01-self-give-up-callbacks-report.md`), а в абзац
о наблюдателе встал `JobAnswerer`. Перестраивать её заново было незачем.
Вычитка — чтение страницы глазами читателя, который видит её впервые, и сверка
каждой фразы с ядром: 313 строк, девять заголовков, шестнадцать блоков, из них
шесть — строки вывода.

## Что нашлось

Двенадцать мест по моему чтению; что к ним добавило независимое ревью —
в разделе «Независимое ревью» ниже, и цитаты страницы в этом разделе стоят
такими, какими были до него. Заголовков по-прежнему девять, блоков стало
семнадцать, строк 345, в переводе 352.

**Слово «engine» ничего не называло.** Вступление говорило «ваша библиотека»,
а следующий абзац — «An engine imports that library», и дальше слово стоит
на странице два десятка раз. Теперь вступление говорит, что движком страница
зовёт библиотеку, которая строит своё поверх ядра.

**Два слова для одного предмета и предмет, которого нет.** `_launch`
и `_whenDone` звались то «doors», то «wrappers», очередь запускала задачи
«through the door of `MyJob`», а движок обращался к задаче «from its queue,
from its controller» — контроллера на странице нет. Слово осталось одно,
«wrappers», как в dartdoc `JobBase`; очередь запускает задачи через `_launch`;
контроллер ушёл. «`@protected` holds inside a subclass» читалось двояко —
теперь «A `@protected` member is for the subclass alone».

**Поле стояло ниже конструктора.** `docs/conventions.md` требует обратного
и в коде, и во фрагментах документации; остальные страницы `async_job` так
и написаны. Исправлено на странице, в переводе и в трёх библиотеках сторожа,
заодно у вспомогательных классов сторожа.

**Фраза о наблюдателе начиналась с конца.** «To give an error nobody answered
for an answer of your own» читается с третьего раза. Теперь она открывается
целью и берёт слова страницы о наблюдении: «For the engine to answer for the
errors no outcome carries». «When the answer of your engine ends with nobody»
стало «When that `onUnanswered` has nobody to hand an error to», и там же
сказано, что `reportToZone` защищён и до него добираются через обёртку, как
до `start`.

**Легенда вступления.** «`cancel` and `sign out` are the moments the user does
so» — у «does so» нет глагола, на который оно ссылается. Теперь «the user
cancels the job or signs out».

**У очереди не было задачи за отменённой.** Требование раздела — «the ones
behind it still have to run», разбор первой попытки кончался словами «every job
behind the second one waits for good», а в примере задач две, и за второй
никого. В примере теперь третья задача, которая печатает `third runs`: первая
попытка до неё не доходит, ответ печатает её строку перед `the queue is empty`.

**`cancelWith` — не единственный член, который наследник дополняет.** Страница
и dartdoc говорили «the one member of the lifecycle a subclass extends rather
than replaces». `@mustCallSuper` стоит ещё на `finish`, на `startChild`
и на `check()`, и сама страница ниже требует `super.check()`. Теперь «An
override adds to it rather than replacing it»; dartdoc `cancelWith` поправлен
так же. Заодно ушло «It» через предложение от своего слова.

**Фраза о сдавшемся теле стояла не в своём разделе.** «A body that gives itself
up does not come through it, and its job has left the queue by then» —
в разделе об очереди, где тело ещё не работало и сдаваться некому; само понятие
страница вводит разделом ниже. Фраза переехала в раздел о правиле, к тому телу,
которое сдаётся: «Nobody asked the job for this cancellation, so it does not
come through `cancelWith`».

**Почему `cancelWith`, а не `finished()`.** Абзацем выше страница говорит, что
`finished()` зовётся и у задачи, снятой до старта, — и читатель спросит, почему
из очереди уходят не там. Зонд: с уходом в `finished()` очередь печатает то же.
Страница теперь говорит это прямо и называет, что даёт `cancelWith`: движок
распоряжается самой отменой. Совет «do it in `cancelWith`, before `super`» стал
«return from `cancelWith` before the call to `super` when `rejectable` is
`true`», и параметр `rejectable`, который стоял в сигнатуре без объяснения,
получил его.

**Цитаты ответа о правиле шли без подписей и в другом порядке.** Под первой
попыткой — отмена, потом выход, каждая с подписью; под ответом — выход, потом
отмена, без подписей, а проза под ними снова начинала с отмены. Теперь порядок
и подписи те же, что у первой попытки.

**Правило ленивое, и страница не говорила, что с этим делать.** «The rule is
asked where `check()` is asked and nowhere else» — верно, а зонд показал цену:
`wait` спрашивает `check()` только до действия, и задача, у которой
пользователь вышел во время `wait`, кончается `Done`, если тело больше ничего
не спросит. Страница теперь называет `wait` рядом с `join`. Следующий абзац
начинался с «An engine ends a job that is still running by cancelling it»
и к правилу привязан не был; теперь он отвечает на вопрос, который оставляет
предыдущий: движок, который не может ждать контрольной точки или должен
остановить задачу, что бы ни поймало тело, отменяет её сам. «Through
`cancelWith`, or through `cancelOwnJob` of its context, a cancellation the job
cannot refuse» относило «cannot refuse» к обоим, а `cancelWith` по умолчанию
отказать позволяет; теперь названо `rejectable: false`. Контракт `finish`
остался на месте целиком.

**Отладочный канал не был назван.** «Only the debug channel says how many
cleanups were left behind» — что это за канал, говорит только `cleanup.md`.
Теперь «switched on with `Job.debug = print;`», теми же словами.

## Зонды

`.artifacts/2026-10-02-extending-rakes/probe_extending_test.dart`; запускался
из `packages/async_job/.probe/`, каталог снят.

| Сценарий | Что вышло |
| --- | --- |
| очередь из трёх, первая попытка | `second: Cancelled(manual)`, `the queue stopped: Bad state: Job(second) has already finished` |
| очередь из трёх, уход в `cancelWith` | `second: Cancelled(manual)`, `third runs`, `the queue is empty` |
| очередь из трёх, уход в `finished()` | то же |
| ждущая задача с `cancellable: false`, возврат из `cancelWith` до `super` | остаётся в очереди, стартует в свой черёд, `Done` |
| та же задача, `rejectable: false` | `Cancelled(signed out)`, из очереди ушла |
| та же задача без ветки отказа | `Cancelled(manual)`: ядро кончает не стартовавшую |
| движок отменяет идущую задачу через `cancelWith` с `rejectable: false`, внутри `uncancellable`, тело ловит отмену | `onCancel` на 10-й мс, исход `Cancelled(signed out)`; с `cancellable: false` то же |
| то же через `cancelOwnJob` | то же |
| правило в `check()`, выход на 10-й мс, тело в `join` | `onCancel` на 20-й мс, когда `join` вернулся |
| правило в `check()`, выход во время `wait` | тело дошло до конца, `Done` |
| `finish` у идущей задачи с одной уборкой | `Job() finished with 1 cleanups pending` в `Job.debug` |

## Независимое ревью

Ревьюер на Opus работал в своей копии дерева с незакоммиченной вычиткой: десять
зондов, 34 мутации ядра и 13 мутаций страниц. Его текст целиком и вердикт
по каждой находке — в `2026-10-02-extending-rakes-review-report.md`. Находок
двенадцать, четыре Medium; дефектов ядра нет. Зонды ревьюера я повторил
в рабочем дереве. Принято всё, кроме трёх мест: сторож не обязан замечать
выброшенный со страницы кусок и переставленные подводки, а фраза о придержанной
отмене, которая приходит в `cancelWith` дважды, встала в dartdoc,
а не на страницу.

Что это изменило на странице сверх двенадцати мест выше:

- **`reportToZone` через обёртку терял ошибку чужого ребёнка.** Ловушку
  поставила сама вычитка: `onUnanswered` получает `Job<Object?>`, обёртка есть
  только у `MyJob`, а ребёнок, принятый без наблюдателя, может быть обычной
  `Job.deferred`. Абзац теперь первым называет
  `super.onUnanswered(job, error, stackTrace)`.
- **Отказ ждущей задачи, написанный по тексту, оставлял её ждать вечно.**
  «Return before the call to `super`» читается и как «после ухода из очереди».
  Страница теперь показывает саму строку —
  `if (status == JobStatus.created && !cancellable && rejectable) return;` —
  и говорит, что она стоит первой; конструктор `MyJob` принимает
  `super.cancellable`. Так на странице появился и `JobStatus`, обещанный
  вступлением.
- **Поданный в `finish` `Cancelled` остаётся исходом.** Фраза «ends with that
  cancellation whatever `finish` is handed» стояла и до вычитки; теперь
  названо, что уступают `Done` и `Failed`.
- **`finish` не останавливает детей и не зовёт `onCancel`.** Пример страницы
  закрывает соединение именно в `onCancel`, а абзац говорил только о стеке
  уборки.
- Перечень путей в `cancelWith` открывается словами «among them»; цитата ответа
  очереди получила подводку; «turn down» стало «refuse», как
  на `cancellation.md`; четыре местоимения с двумя хозяевами развязаны; три
  ссылки названы заголовком раздела и страницей, как требует
  `docs/conventions.md`; шапка dartdoc `JobBase` говорит теми же словами, что
  страница.

Общий помощник `test/support/page_code.dart` закрыт с трёх сторон: `under:`
бросает `StateError`, когда под заголовком нет кода, — раньше переименованный
заголовок оставлял тест зелёным и пустым; `strayFences` находит блок под
забором, которого проверки не читают; хвост первой строки куска принимается,
только когда перед ним в строке теста стоит `=>`, `=` или `return`.

## Сторож

`packages/async_job/test/extending_rakes_test.dart`: было 29 тестов, стало 40.
Новые по чтению:

- `taking the job out in finished() lets the queue go on as well` — через
  `MyQueue` первой попытки дословно;
- `mustCallSuper holds an override of cancelWith to super`;
- `a sign-out during a wait is noticed only at the next call that asks`;
- `the engine stops a running job itself`, два теста — через `cancelWith`
  и через `cancelOwnJob`: `onCancel` в момент отмены, тело ловит отмену, секция
  открыта, задача создана с `cancellable: false`.

Новые по ревью:

- `a job that refuses first of all waits on in the queue` — `PatientJob`
  со строкой страницы в `MyQueue` страницы;
- `the cascade and cancelOwnJob arrive at cancelWith as well`;
- `super.onUnanswered sends on the error of a child of another kind`;
- `reportToZone hands the error to the zone the job was created in`;
- `finish by hand stops no child and runs no onCancel`;
- `the page has no fence the checks do not read`.

Тест продолжения `then` создаёт задачу в одной зоне и зовёт `then` в другой;
`HookJob.started` записывает статус задачи. Число уборок в отладочном канале
держит `debug_test.dart`, как и раньше.

## Мутации

В копии пакета; после каждой файл возвращён копией и сверен с исходным, прогон
после возврата зелёный. Свои —
`.artifacts/2026-10-02-extending-rakes/mutate.py`, тринадцать, красные считаны
в стороже страницы:

| Мутация | Красных |
| --- | --- |
| `finished()` только у задачи, чьё тело работало | 2 |
| задача отклоняет и `rejectable: false` | 2 |
| секция держит и `rejectable: false` | 2 |
| `wait` спрашивает `check()` после действия | 1 |
| с `cancelWith` снят `@mustCallSuper` | 1 |
| цитаты ответа правила переставлены обратно | 1 |
| из цитаты ответа очереди выпала `third runs` | 1 |
| конструктор на странице выше поля | 1 |
| из примера страницы выпала третья задача | 2 |
| строка отказа на странице ждёт `running` | 2 |
| `PatientJob` отказывает после ухода из очереди | 1 |
| ответ в стороже не уходит из очереди | 5 |

Восемь мутаций ревьюера, которые до правок не красили ничего, — его скриптом
`reviewer/mutate_reviewer.py`, прогон всего пакета, после правок каждая краснит
один тест сторожа страницы:

| Мутация | Кто краснеет |
| --- | --- |
| c10 `reportToZone` шлёт в текущую зону | `reportToZone hands the error to the zone…` |
| c14 `started()` раньше статуса `running` | `a started that throws is told…` |
| c21a каскад идёт мимо переопределения | `the cascade and cancelOwnJob arrive…` |
| c21b `cancelOwnJob` идёт мимо переопределения | тот же |
| c27 `finish` руками останавливает детей | `finish by hand stops no child…` |
| p01 блок под голым забором | `the page has no fence the checks do not read` |
| p03 первая строка куска обрезана слева | `every piece of code on the page…` |
| p05 заголовок ответа переписан | `the code under "### Leaving the queue…"` |

## Перевод

`docs/ru/async_job/extending.md` поправлен вслед за оригиналом, фраза
за фразой, и по девяти замечаниям ревьюера к самому переводу: «отклоняет
отмену» вместо двух управлений слова «отказать», «переданный исход» вместо
«поданного», заголовок «Собственная отмена движка». Изменённые абзацы прошли
`humanizer-ru`: сканер дал 90 из 100 до и после, запретов и тире нет;
единственное замечание — заголовки `##`, это структура страницы.

## Проверки

`packages/async_job`: формат, анализ и `dart doc --dry-run` чистые, `dart test`
зелёный, 1053 теста. Из корня: `reflow.py --check`, `check_line_width.py`,
`check_links.py`, `check_translations.py` и `check_doc_shape.py` зелёные;
`jargon.py` и `bare_names.py` скилла `doc-reader` на странице и переводе
молчат. `solo` и `flutter_solo` не затронуты: в `lib/` изменены два комментария
dartdoc.

## По чтению владельца

Чтение идёт с 2026-10-02.

1. «Сначала ты говоришь о библиотеке пользователя, а потом пишешь „такую
   библиотеку называют движком“» — о вступлении. Первая фраза обращалась
   к читателю, «If your library needs its own state…», и советовала строить
   поверх ядра, а имя приходило третьей фразой и уже не о его библиотеке: «This
   page calls such a library an engine». «Такая» после «вашей» читается как
   другая библиотека. Фразу с именем дописала сама вычитка — первый пункт
   раздела «Что нашлось» — и поставила её после совета, а не перед ним. Теперь
   вступление открывается именем: «An engine, on this page, is a library with
   its own state, queue or scheduling rules. Build yours on the core…»,
   и наследники добавляют «the engine's behavior», а не «the library's». Рядом
   слово «library» называло второй предмет, библиотеку Dart: «An engine imports
   that library» через абзац после «your library» — стало «that file», а «the
   engine lives in the library of `MyJob`» — «the Dart library of `MyJob`».
   Перевод поправлен в тех же четырёх местах. Новых утверждений правка
   не добавила, код страницы не тронут; сторож зелёный, 40 тестов.

2. «Эта мысль читается так: API ведёт вот к этим примерам, а правильно
   по-другому. Но зачем тогда нужно такое API, которое ведёт не туда?» —
   о фразе вступления «Two parts of the page below open with the version the
   protected API leads to». Фраза снята с остальных страниц, где первую попытку
   подсказывает имя: `value` — за значением, `wait` — подождать. Здесь имён,
   которые подсказывают не то, нет. Первая очередь запускает задачи по порядку
   и не думает о задаче, отменённой в ожидании; первое правило записано
   в `check()` без `super.check()` и бросает ошибку вместо отмены. Это просто
   первая версия, а фраза делала из неё упрёк API. Теперь вступление называет
   её тем, чем она является: «the version you would write first — a queue that
   starts its jobs in turn, a rule written into `check()`», в переводе —
   «версией, которую пишут первой». Остальные страницы не тронуты: там сказано
   «the names lead to» или «the vocabulary leads to» и названо, какое имя
   к чему подталкивает. Новых утверждений правка не добавила, код страницы
   не тронут.
