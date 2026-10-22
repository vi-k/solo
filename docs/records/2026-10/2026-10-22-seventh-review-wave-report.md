> **Состояние на 2026-10-22:** сделано и смержено в `main`, коммит `25ef4349`;
> ревью сделанного на Opus и его правки — в этом отчёте.
> **Что это:** отчёт о волне по седьмому ревью: что сделано по каждой находке,
> где разошлось с планом и что из ревью плана на Opus принято.
> **Связанные записи:** `2026-10-22-seventh-review-wave-plan.md`,
> `2026-10-22-async-job-project-review.md`,
> `2026-10-22-solo-project-review.md`.

# Волна по седьмому ревью: отчёт

## Что сделано

**Ядро, L1 и вопрос 1.** `Job.then` и `Job.shared` принимают `key`
и `describe`, `JobContext.each` — тоже, и защищённая фабрика
`JobContextBase.createEachJob(body, {key, describe})` получает их от `each`.
Умолчание `describe` подставляет ядро: `then`, `shared`, `each`, поэтому
прежние имена в трассах страниц остались — `Job(then)`, `Job(shared)`,
`Job(each)`, а с одним `key` выходит `Job(load: then)`. В dartdoc трёх членов
одна фраза со ссылкой на «A job's name» `observing.md`; на странице абзац
о том же. Тест — `continuation_names_test.dart`: четыре формы имени у каждого
из трёх и `key`, дошедший до наблюдателя в `onError` продолжения (сценарий R16
ревьюера). `EachContext` в `extending_test.dart` принимает новую сигнатуру
и проверяет, что `key` и умолчание `describe` дошли до фабрики.

**`solo`, часть 2.1.** `_SoloContext.createEachJob` передаёт `key` и `describe`
в `_solo.job`, `SoloContext.each` их принимает. Dartdoc говорит, что это только
имя: политики очереди правят корневыми задачами. Тест — первый
в `each_child_test.dart`. Фразы `children.md` и `streams.md` `solo` о том, что
имя даёт сам `then` и сам `ctx.each`, дописаны «unless the call gives it a
`key` or a `describe`», и `_says` в двух тестах страниц вместе с ними.

**`solo`, L1 и вопрос 1.** `SoloQueue.jobs` — `Iterable<SoloJob<Object?>>`,
`Solo.current` — `SoloJob<Object?>?`, предикаты `removeWhere` и `lastJobWhere`
принимают `bool Function(SoloJob<Object?>)`. `OpenSolo`
в `test/support/test_solo.dart` переопределяет оба защищённых члена и получил
новые типы. Тест в `queue_test.dart` читает `isQueued` у элемента очереди,
у `current` и в обоих предикатах без приведения, поэтому на старых типах
не компилируется. Вводная фраза раздела `SoloJob` в `reference.md` называет
`queue.jobs`, `current` и `lastJobWhere`.

**Ядро, L2.** «observe», «answer for» и «the zone» при первом употреблении
в прозе ведут на «A failure nobody waits for» `outcomes.md`, «Answering for
errors» и «Where errors go» `errors.md`. Страницы находки — `chains.md`,
`children.md`, `streams.md`, `testing.md`, `extending.md`, `observing.md`;
по ревью плана ещё `cancellation.md`, `groups.md` и `cleanup.md`, где «the
zone» стояло без ссылки. `time.md` уже вела на `outcomes.md`. Переводы —
на русские якоря тех же разделов.

**Ядро, L3 и L4.** Dartdoc `JobObserver.onError`, `JobAnswerer.onUnanswered`,
`Failed`, `Job.whenCancelled` и `JobContext.each` — в форме решения 103.
Перечень источников `onUnanswered` и `onError` ушёл: его держат таблицы «Where
each error goes» и «Rare routes». Разбор порядка вызовов `whenCancelled` ушёл
в «Listening for the cancellation» `outcomes.md`, где он уже был. Чего
на страницах не было, переехало туда:

- в «Cancelling a chain» `chains.md` — что продолжение и ручка `shared`
  регистрируются в `whenCancelled` источника при создании, и слушатель,
  зарегистрированный раньше них, застаёт их неотменёнными;
- в «A child that owns the subscription» `streams.md` — что отложенная задача,
  которую вернул колбэк, кончает ребёнка `ArgumentError`. Что future отмены
  подписки не ждут, страница уже говорила в «Waiting for the source to close»,
  и абзац ведёт туда.

Отказ через `finish` задачи, которая уже кончилась, из `onError` ушёл без
переезда: его говорит dartdoc самого `JobBase.finish`.

**Ядро, L5.** Таблица «The context at a glance» осталась одна, с теми же
колонками; ячейки — по два-шесть слов, оговорки — списком под таблицей.
`readme_recipe_test.dart` держит новые ячейки и их перевод, а фразу об ошибках
`ctx.unattended`, которая ушла из ячейки, — уже в тексте под таблицей.

**Ядро, L6.** Фраза в dartdoc `Job.each` у `cancellable` и, по ревью плана,
тест в `each_root_test.dart`: `cancel()` не возвращается секунду на открытом
потоке и возвращается после `close`.

**Ядро, L7.** Таблица «`0.2.0` | `0.3.0`» в начале «Breaking changes»: шесть
строк, с `JobBase.debug` и с `ctx.wait`, хотя тот в «Deprecated»; вводная фраза
та же, что у `solo`, «each has its entry below». Записи о `key` и `describe`:
«Added» — одна, «Breaking changes» — фразой в пункте о реализациях `Job`
и `JobContext` и фразой в пункте о защищённой поверхности.

**`solo`, M1.** `example/README.md` стал `example/example.md`; тест примера
`camera_rakes_test.dart` читает новый файл, имя теста поправлено.

**`solo`, L2 и вопрос 2.** На `accumulation.md` сказано, что событие при
дренаже в ждущую группу не вливается, в отличие от дубликата `droppable`, и что
последний пакет пишут до `close`. Dartdoc `add` это уже говорил и не тронут.
Решение 104 в `docs/settled.md` с доводом о debounce.

**`solo`, L3 и L4.** Фраза в dartdoc `SoloSelector` о выборе, который вернулся
до кадра; dartdoc `Solo.pending` открывается договором, строка `reference.md` —
тем же смыслом.

**Записи о таблице и об имени.** Решение 75 дописано: таблица переименований —
не «Migrating». Решение 81 дописано: продолжение, ручку и ребёнка `ctx.each`
теперь называет вызывающий.

## Ревью плана на Opus

Отчёт — `.artifacts/2026-10-22-wave7-review/plan-review-opus.md`: High 0,
Medium 5, Low 15. Что с каждой находкой:

- 1, коммит частями: код ядра и `solo` с документами идут одним коммитом,
  записи — следующим.
- 2, тест примера: поправлен; ссылку `camera.md` на каталог `example/` оставил
  сознательно — она ведёт на код примера, а не на его страницу.
- 3, фразы `solo` об имени: сделано, с `_says`.
- 4, тест таблицы README: поправлен вместе с ячейками; таблица одна.
- 5, проверка вкладки Example: шаг «после публикации открыть вкладку Example
  `solo` 0.3.0» записан в `docs/handoff.md`.
- 6, `CHANGELOG.md`: отдельный пункт о `createEachJob` сложен в два
  существующих.
- 7, `JobBase.debug` в таблице: был с самого начала.
- 8, ещё страницы и «accept a cancellation»: три страницы добавлены; у «accept
  a cancellation» ссылки нет — в вердикте его нет.
- 9, dartdoc `add`: не тронут.
- 10, линт на аннотации типа: тест читает `isQueued` без аннотации.
- 11, тест защищённой поверхности и `reference.md`: тест не тронут, фраза
  в разделе `SoloJob` добавлена.
- 12, что остаётся `Job`: `remove(Job)`, `SoloPending*`, `SoloTransition`
  и хуки — названо в итоге L1 `solo`; расширение на предикаты — там же.
- 13, умолчание `each` в ядре: оставлено, dartdoc `createEachJob` говорит, что
  `describe` приходит уже с умолчанием; тест `EachContext` проверяет и `key`,
  и умолчание.
- 14, `Job(load: then)` в абзаце: есть.
- 15, dartdoc `then` и `shared`: одна фраза, остальное не тронуто;
  `SoloContext.each` — фраза без ссылки на страницы ядра.
- 16, `docs/settled.md`: решение 104 с доводом; 75 и 81 дописаны; 50 не задето.
- 17, ответы владельца: были записаны в обеих записях до волны.
- 18, `dart doc` и пол: `dart doc --dry-run` трёх пакетов — в гейте; `floor`
  на 3.27.0 — после коммита в копии, потому что пробный `publish` падает
  на грязном дереве.
- 19, тест L6: сделан.
- 20, handoff: обновлён в коммите волны.

## Ревью сделанного на Opus

Отчёт — `.artifacts/2026-10-22-wave7-review/work-review-opus.md`: High 0,
Medium 3, Low 6, в коде ошибок нет. Каждую находку я проверил по дереву своей
командой. Что с каждой:

- M1, фраза L6 в dartdoc `Job.each`: «only when the stream ends» неверно —
  с `cancellable: false` бросивший колбэк тоже кончает задачу. Фраза теперь
  говорит, что `cancel()` вернётся, когда задача кончится сама: поток кончится
  или упадёт или бросит колбэк.
- M2, повтор на `streams.md`: вторая половина нового абзаца повторяла «Waiting
  for the source to close» той же страницы. Она заменена ссылкой на тот раздел,
  в переводе тоже; итог L4 и этот отчёт поправлены.
- M3, `docs/handoff.md` писал волну влитой до коммита: состояние дерева
  и строку о `floor` handoff получает в коммите записей, после `floor`.
- L1, dartdoc `whenCancelled`: вернулось, что брошенный колбэком `Cancelled`
  в зону не идёт; «once the call has begun» стало «once the pass over the
  callbacks has begun», как на странице.
- L2, dartdoc `SoloSelector`: сравнение с `ValueListenableBuilder` стоит теперь
  у поведения, а не у противопоставления.
- L3, `CHANGELOG.md`: у ядра `key` и `describe` названы и для переопределения,
  у `solo` — для `each` класса, который сам реализует `SoloContext`. Переводы
  тем же коммитом.
- L4, род future в переводе `streams.md`: фраза ушла вместе с повтором M2.
- L5, итог L1 `solo` назвал, почему `SoloPending*` и `SoloTransition` остаются
  на `Job`: это значения с открытыми `const`-конструкторами, тесты
  пользователей собирают их из обычного `Job`.
- L6, README: под таблицу вернулись два факта прежних ячеек — `ctx.check()` для
  места, где нечего обернуть, и `ctx.each` по одному событию. Их держит новый
  тест `readme_recipe_test.dart`.

## Проверки

Гейт после правок ревью сделанного, на дереве `25ef4349`: формат и анализ пяти
корней чистые; тесты — ядро +1797, `solo` +2067, его пример +112,
`flutter_solo` +241, его пример +6, `flutter_check` +47; стенды и сверка трасс
3, 13 и 6 из 0 непечатанных; документные проверки, сборка сайта
и `dart doc --dry-run` трёх пакетов — зелёные. Линтер `humanizer--ru`
на изменённых абзацах переводов — 0 `ERROR`.

`floor` на 3.27.0 — после коммита, в отсоединённой копии `25ef4349`: пробный
`dart pub publish` трёх пакетов без предупреждений, подсказки только
об оверрайдах; все пять корней проходят на полу. `example/example.md` в архиве
`solo` есть. Покажет ли его вкладка Example, проверит только сама вкладка после
публикации — шаг в `docs/handoff.md`.
