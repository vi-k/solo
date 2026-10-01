> **Состояние на 2026-10-01:** сделано в `main` одним коммитом вместе
> с правками по независимому ревью на Opus, не отправлено; ревью и вердикты —
> в разделе «Ревью».
> **Что это:** отчёт о том, как сделаны `JobObserver.all`, `JobAnswerer`
> и `SoloObserver.all` по второй редакции дизайна.
> **Связанные записи:** `2026-10-01-multi-observer-design.md`,
> `2026-09-25-observing-rakes-report.md`.

# Несколько наблюдателей: отчёт

## Что сделано

Ядро, `packages/async_job/lib/src/observer.dart`. `JobObserver` оставил четыре
хука и получил явный `JobObserver();` и фабрику `JobObserver.all`.
`onUnanswered` с прежним телом по умолчанию переехал
в `mixin JobAnswerer on JobObserver`. Фабрика обходит список один раз, копирует
его, проверяет повторы по `identical` с заходом во вложенные составные
и считает отвечающих по типу: ни одного — приватный `_AllObservers`, который
`JobAnswerer` не является; один — `_AllObserversAnswering`, наследник
с `JobAnswerer`, который отдаёт `onUnanswered` ему; больше — `ArgumentError`.
Каждый вызов хука изолирован `JobBase._notify`.

`job_base.dart`, `_handleUnanswered`: ядро спрашивает наблюдателя, только если
он `JobAnswerer`; иначе ошибка уходит в зону создания, как без наблюдателя.
Dartdoc ядра переписан под `JobAnswerer` в `job_base.dart`, `job_context.dart`,
`outcome.dart` и комментарий `job_stream.dart`; совет «override `onUnanswered`
in the child's observer» стал «give the child an observer that is a
`JobAnswerer`».

`solo`. Тело `_callHook` переехало в `callHook` нового
`lib/src/call_hook.dart`, который пакет не экспортирует; `Solo._callHook` зовёт
его. `SoloObserver` получил явный `SoloObserver();` и фабрику
`SoloObserver.all` с приватным `_AllSoloObservers`, который раздаёт семь хуков
через тот же `callHook`. `_SoloJobObserver` стал
`implements JobObserver, JobAnswerer` и отвечает, как прежде, через
`Solo.onUnanswered`.

## Документы

- `packages/async_job/doc/observing.md` и перевод: вступление объясняет строку
  `onUnanswered:`; раздел «Observer» — четыре хука и `JobAnswerer`; «Where
  errors go» — ответ даёт наблюдатель, который `JobAnswerer`, пример стал
  классом `Answering`; абзац о `ctx.unattended`. Новый раздел «Several
  observers» перед «Testing»: требование с `Crashes`, первая попытка `Both`,
  которая раздаёт хуки списку и печатает строки одного `Reporter`, второй
  самодельный исход прозой, ответ `JobObserver.all([Reporter(), Crashes()])`
  и абзац правил.
- `children.md`, `extending.md` и переводы: путь ответа через `JobAnswerer`.
- `packages/solo/doc/errors.md` и перевод: `SoloObserver.all` с четырьмя
  наблюдателями страницы в конце «A cancellation that never lands».
- README `async_job` и перевод: строка оглавления называет `JobAnswerer`.
- `CHANGELOG.md`: первая ломающая запись `async_job` переписана под
  `JobAnswerer`, фраза о `implements JobObserver` ушла, «Changes you will see
  on upgrade» говорит о `JobAnswerer`; «Added» — `JobObserver.all`
  у `async_job`, `SoloObserver.all` у `solo`, оба у `flutter_solo`; у `solo`
  и `flutter_solo` поправлены унаследованные записи.
- Изменённые русские абзацы прошли сканер `humanizer-ru`: 100 из 100, тире нет,
  правок не понадобилось. Новых голых имён из кода нет.

## Тесты

- `packages/async_job/test/observer_all_test.dart`, 14 тестов: порядок и ответ
  после всех `onError`; изоляция и `Cancelled` никуда; без отвечающего — зона
  один раз и зона создания при двух зонах; составной без отвечающего
  не `JobAnswerer`; отвечающий на любом месте; вложенный отвечающий отвечает,
  вложенный без отвечающего не мешает; два отвечающих и вложенный второй —
  `ArgumentError`; повторы, вложенные тоже; два наблюдателя, равные по `==`,
  остаются двумя; составной называет свой список в `toString`; ленивый
  `Iterable` обходится раз, список копируется; пустой список; ребёнок наследует
  составного.
- `unanswered_test.dart`: тест двух зон гоняется для наблюдателя, который
  не отвечает (путь ядра), и для `PlainAnswer` (тело `JobAnswerer`).
  Одиннадцать тестовых наблюдателей с `onUnanswered` получили
  `with JobAnswerer`, `Plain` разделился на `Plain` и `PlainAnswer`;
  `Forwarding` проверяет `inner is JobAnswerer`.
- `observing_rakes_test.dart`: `Crashes`, `Both`, `BothAnswering`, две новые
  цитаты и шесть тестов раздела; 59 тестов.
- `packages/solo/test/observer_all_test.dart`, 6 тестов: семь хуков по порядку,
  изоляция и `Cancelled` в зону, как у одиночного, повторы, равные по `==`,
  `toString`, ленивый `Iterable` и копия. `errors_rakes_test.dart`: три рецепта
  страницы, `Hangs`, `SlowCancellations` и `StuckCancellations`, работают под
  одним `SoloObserver.all`.

Прогоны после правок по ревью: `async_job` 950, `solo` 829, пример `solo` 47,
`flutter_solo` 85, его пример 4; `dart format` и анализ чисты везде; стенды
`doc_snippets` и `accumulation_snippets` с `check_traces`; питоновские проверки
документации.

Мутации, откат копией со сверкой хэша, красные по меткам `[E]`:

- `async_job`, без изоляции в составном — 1; составной всегда `JobAnswerer` —
  2; ядро для наблюдателя без `JobAnswerer` отдаёт ошибку никуда — 106,
  в `Zone.current` вместо зоны создания — 11; два отвечающих разрешены — 2; без
  проверки повторов — 2; без захода во вложенные — 1; без копии списка — 1;
  составной хранит переданный `Iterable` как есть — 1. Первая попытка «lazy
  kept» — `map` поверх уже скопированного списка — оказалась равносильной
  исходнику и заменена этой. После ревью: повтор по `==` вместо тождества — 1,
  `toString` составного от `Object` — 1.
- `solo`, без изоляции — 1; правило ядра вместо `callHook` (`Cancelled`
  глушится) — 1; без проверки повторов — 1; без копии — 1; повтор по `==` — 1;
  `toString` от `Object` — 1.

## Ревью

Независимый ревьюер на Opus, 2026-10-01. Работал по копии дерева на `8c57192`
с несделанной работой поверх: 30 изменённых и 4 новых файла, все проверки идут
по ней. После мутаций копия восстановлена, хэши пяти мутированных файлов `lib`
совпали с исходными, `git status` тот же: 30 M и 4 ??.

**Что подтвердилось.**

- **Гейты.** Прогон на свежей копии без `.dart_tool` дал `format rc=1` (46
  файлов) и 9726 замечаний анализатора: `package_config` ещё не было, и формат
  с анализом шли на языке 3.13. Повторный прогон после `pub get` чистый.
  Результаты:
  - `dart format` чист в пяти пакетах;
  - `dart analyze` и `flutter analyze`: «No issues found» везде;
  - тесты: `async_job` 948, `solo` 827, пример `solo` 47, `flutter_solo` 85,
    его пример 4;
  - из корня зелёные `reflow.py --check`, `check_line_width.py`,
    `check_translations.py`, `check_links.py`, `check_doc_shape.py`
    и `build_site.py` (42 страницы);
  - отчёт и `handoff.md` укладываются в 79 символов и залиты.
- **Пол и стенды.** На закоммиченной копии пол 3.27.0 (`archive_floor.py stage`
  и `run`) зелёный по всем пяти корням: 948, 827, 47, 85, 4. Стенды
  `doc_snippets` и `accumulation_snippets` анализируются чисто, `check_traces`
  отвечает «every quoted trace is what the bench prints».
- **Числа отчёта.** Сходятся: 12 тестов
  в `async_job/test/observer_all_test.dart`, 4
  в `solo/test/observer_all_test.dart`, 59 в `observing_rakes_test.dart`, 11
  наблюдателей с `with JobAnswerer`. В изменённых русских строках нет ни одного
  тире.
- **Мутации из отчёта** воспроизведены с теми же счётами `[E]`:
  - составной всегда `JobAnswerer` — 2;
  - ядро для наблюдателя без `JobAnswerer` отдаёт ошибку никуда — 106;
  - два отвечающих разрешены — 2;
  - без проверки повтора — 2;
  - без захода во вложенные — 1;
  - без копии — 1;
  - без изоляции — 1;
  - в `solo` без изоляции, правило ядра вместо `callHook`, без повтора и без
    копии — по 1.

  Мутация «`Zone.current` вместо `_toZone`» в варианте, который сохраняет
  фильтр отмен, убита четырьмя тестами (в отчёте 11 — видимо, вариант без
  фильтра). Среди этих четырёх есть оба новых теста двух зон.
- **Мои мутации, все убиты.** Счёт `[E]` по каждой:
  - составной теряет `onFinish` — 3, теряет `onLog` — 2;
  - обратный порядок — 3 в `async_job`, 2 в `solo`;
  - `Cancelled` из хука члена идёт в зону — 1;
  - отвечающий составной отвечает телом по умолчанию — 6;
  - вложенные отвечающие считаются вдвойне — 2;
  - отвечающего спрашивают дважды — 4;
  - тело `JobAnswerer` по умолчанию идёт в `Zone.current` — 1;
  - пустой список отвечает — 2;
  - `solo` теряет `onCreate` — 1, `onClose` — 2;
  - `solo` без вложенного обхода — 1;
  - `_SoloJobObserver` без `JobAnswerer` — 32.
- **Зонды.** Всё, о чём просили, работает по дизайну:
  - `then(observer: JobObserver.all([a, b-отвечающий]))` и движок на `JobBase`
    (`ProbeJob` с `unattended`) дают одинаковый журнал: все `onStart`, все
    `onError`, `b onUnanswered`, все `onFinish`;
  - `drop(Failed)` на закончившейся задаче с составным без отвечающего даёт оба
    `onError` и одну строку `zone:`;
  - класс `implements JobObserver` в списке слышит хуки;
  - `implements JobObserver, JobAnswerer` считается отвечающим: составной
    `is JobAnswerer`, а вместе со вторым отвечающим получается `ArgumentError`;
  - `onUnanswered` без `JobAnswerer` в составном не зовётся, ошибка уходит
    в зону. Анализатор предупреждает только при `@override`
    (`override_on_non_overriding_member`), без аннотации молчит — фраза
    `CHANGELOG` верна;
  - ленивое сообщение `onLog` строится по разу на наблюдателя: 2 из 2;
  - бросивший `onUnanswered` отвечающего уходит в текущую зону;
  - `Cancelled` из disposer отвечающий с телом по умолчанию отбрасывает;
  - `toString` даёт `JobObserver.all([Instance of 'Rec', ...])`,
    а `ArgumentError` на ленивом `Iterable` не обходит его повторно.
- **Двойной вызов в `_AllObserversAnswering` невозможен.** Отвечающий берётся
  только из верхнего списка (`observer.dart:67`). `onError` он получает один
  раз через `_each`, `onUnanswered` — один раз через `_answerer`. Тот же
  отвечающий напрямую и внутри вложенного составного — это повтор,
  `ArgumentError` (`observer_all_test.dart:245-249`).
- **`solo` и `flutter_solo`.** Ни в `lib`, ни в примерах, ни в тестах больше
  нет ничего, что держалось бы за `JobObserver.onUnanswered`. `JobObserver`
  встречается только в `solo.dart` и `observer.dart`, экспорт `JobAnswerer`
  доходит через `export 'package:async_job/async_job.dart'`. 0.2.0 объявлял
  `abstract class JobObserver` и `abstract class SoloObserver` без
  `const`-конструктора, поэтому «compiles unchanged» в `CHANGELOG` верно.

Блокеров нет.

1. **Нужно исправить.** Таблица раздела «Where errors go» не переписана:
   `packages/async_job/doc/observing.md:204, 206, 207, 208`, перевод —
   `docs/ru/async_job/observing.md:208, 210, 211, 212`. В колонке «With an
   observer» по-прежнему стоит «`onError`, then `onUnanswered`: the zone by
   default». Наблюдатель этой колонки — `Reporter` (`observing.md:175`),
   а у него `onUnanswered` нет, и ядро его не спрашивает
   (`job_base.dart:1298`). Раздел «Документы» дизайна требует: «таблица и проза
   говорят „`onUnanswered`, если наблюдатель отвечает, иначе зона“». Отчёт
   об этом пункте молчит. Абзац ниже ссылается на таблицу как на источник: «the
   two failures of a body the table sends to `onUnanswered`»
   (`observing.md:271`).

   Вердикт: принято, проверено чтением раздела. Четыре ячейки в обоих языках
   говорят теперь «`onError`, then `onUnanswered` if the observer answers, the
   zone otherwise» (у строки `Cancelled` — «nobody otherwise»), в переводе —
   «если наблюдатель отвечает, иначе зона». Ссылка абзаца на таблицу остаётся
   верной: таблица ведёт эти провалы в `onUnanswered`, когда есть кому
   ответить.

2. **Нужно исправить.** Английский и русский абзацы о двух путях в зону
   разошлись.
   - EN, `observing.md:266-267`, не тронут: «when nobody observed the outcome,
     or when `onUnanswered` sends it on». Но у наблюдателя без `JobAnswerer`
     ошибку в зону отправляет ядро, а не `onUnanswered`.
   - RU, `docs/ru/async_job/observing.md:271-272`, переписан: «если ответа нет
     либо `onUnanswered` отправил ошибку дальше».

   `check_translations.py` сверяет только заголовки и блоки кода, поэтому
   расхождение прошло.

   Вердикт: принято. Английский догнал перевод: «or when nobody answers or
   `onUnanswered` sends it on», абзац перезалит.

3. **Нужно исправить.** Новые приватные классы в `lib` объявляют конструктор
   выше полей, вопреки `docs/conventions.md:45-47`:
   - `packages/async_job/lib/src/observer.dart:194` (`_AllObservers`);
   - `:227` (`_AllObserversAnswering`);
   - `packages/solo/lib/src/observer.dart:118` (`_AllSoloObservers`).

   В `packages/*/lib` на `HEAD` такого класса нет ни одного — проверено
   скриптом. То же в новых тестах: `observing_rakes_test.dart:150`
   (`BothAnswering`), `async_job/test/observer_all_test.dart:12`
   и `solo/test/observer_all_test.dart:15` (`Recording`). В тестах на `HEAD`
   таких классов уже 21.

   Вердикт: принято, правило в `docs/conventions.md` сверено. Поля поднял над
   конструктором во всех шести классах, три в `lib` и три в новых тестах.
   Старые тестовые классы не тронуты: это не эта работа.

4. **Нужно исправить.** Фраза `packages/solo/doc/errors.md:344` «this page has
   made three by now» неверна. До этого места страница собрала четыре рабочих
   наблюдателя: `LoggingObserver` (`:90`), `Hangs` (`:183`),
   `SlowCancellations` (`:259`) и `StuckCancellations` (`:314`), плюс первую
   попытку `SlowJobs` (`:231`). Список из трёх в коде под этой фразой обходит
   `Hangs` без объяснения. Перевод `docs/ru/solo/errors.md:346` повторяет
   «три», а порядок слов «эта страница их уже собрала три» читается с запинкой.

   Вердикт: принято, `Hangs` на странице есть. Фраза говорит «four», список
   в обоих языках получил `Hangs()` вторым, перевод — «а на этой странице их
   уже четыре». Тест `errors_rakes_test.dart` переименован
   в `SoloObserver.all keeps the recipes at work under one observer` и держит
   теперь три рецепта: строку `Hangs` о задаче, которая всё ещё идёт, тоже.

5. **Мелочь.** Во всех трёх `CHANGELOG.md` после новой записи «Added» стоят три
   пустые строки подряд: `async_job/CHANGELOG.md:238-241`,
   `solo/CHANGELOG.md:276-279`, `flutter_solo/CHANGELOG.md:109-112`. На `HEAD`
   в `solo/CHANGELOG.md` нет ни одного места с двумя пустыми строками подряд.
   `reflow.py --check` этого не замечает.

   Вердикт: принято, подтверждено поиском: по одному такому месту в каждом
   из трёх. Свёрнуты в одну пустую строку.

6. **Мелочь.** Публичный dartdoc `JobContext` по-прежнему называет путь ошибки
   «`onError` and `onUnanswered`» без оговорки об отвечающем наблюдателе:
   - `job_context.dart:47` (`wait`), `:73`;
   - `:142` и `:145` (`join`);
   - `:257` (`onCancel`);
   - `:596` (`unattended`);
   - приватный `job_base.dart:524`.

   У наблюдателя без `JobAnswerer` второго хука нет. Соседние места работа
   переписала на «on to its answer» (`job_context.dart:536`,
   `job_base.dart:1100`), а эти остались. В дизайне их нет, ревью второй
   редакции назвало только `:578` и `:790`.

   Вердикт: принято. Все семь мест говорят «to `onError` and on to the job's
   answer», абзацы перезалиты. Что такое ответ задачи, объясняет dartdoc
   `JobObserver`: отвечающий наблюдатель, без него зона.

7. **Мелочь.** В переписанном dartdoc остались оборванные переносы: следующее
   слово влезло бы в предыдущую строку в пределах 80 символов. Это
   `job_base.dart:1286` («[notifyError] ends here, and so do two», 44 символа),
   `job_base.dart:1643` («answers, otherwise in the zone.», 37)
   и `job_context.dart:537`. `dart format` комментарии не перезаливает.

   Вердикт: принято. Три абзаца перезалиты жадно до 80, вместе с абзацами
   находки 6.

8. **Мелочь.** Две мутации переживают оба набора.
   - Проверка повтора на `HashSet()` вместо `HashSet.identity()`: `async_job`
     948 из 948 и `solo` 827 из 827 зелёные. Разница появляется только
     у наблюдателя с переопределённым `==`: два равных, но разных объекта
     стали бы `ArgumentError`, хотя dartdoc обещает повтор по тождеству.
   - `toString` составного (`observer.dart:221`,
     `solo/lib/src/observer.dart:160`) заменён на `super.toString()`: оба
     набора зелёные. При этом строка `JobObserver.all([...])` видна в сообщении
     `ArgumentError` о вложенном повторе.

   Вердикт: принято. В оба `observer_all_test.dart` добавлены тесты
   `two observers equal by == are two observers` (наблюдатель `Alike`, равный
   любому другому `Alike`) и `it names its observers`. Все четыре мутации
   повторены: каждую убивает один тест.

9. **Мелочь.** Dartdoc `JobObserver.all` (`observer.dart:44-46`) говорит «the
   same observer comes twice, counting those inside» и не уточняет, внутри
   чего. Обход заходит только в составные `JobObserver.all`
   (`observer.dart:57-59`), поэтому повтор внутри самодельного пересыльщика
   вроде `Both` со страницы проходит молча, и наблюдатель слышит `onError`
   дважды. У `SoloObserver.all` формулировка точная: «inside one made by
   [SoloObserver.all]» (`solo/lib/src/observer.dart:33-34`).

   Вердикт: принято. Формулировка та же, что у `SoloObserver.all`: «counting
   those inside one made by [JobObserver.all]».

10. **Мелочь.** Шапка отчёта (`2026-10-01-multi-observer-report.md:1`) говорит
    «сделано в `main` одним коммитом», а работа не закоммичена: `git status`
    показывает 30 изменённых и 4 новых файла, и `docs/handoff.md` пишет «потом
    коммит». Шапка станет верной только вместе с коммитом.

    Вердикт: принято как замечание о порядке. Шапка была написана на коммит
    заранее. Отчёт уходит тем же коммитом, что и работа, и в нём шапка верна.
