# Ревью сделанного: провал ребёнка, покрытый отменой

> **Состояние на 2026-09-25:** вердикты записаны: все девять находок
> приняты, находка 2 — без ограничения второй строки таблицы, находка 7 —
> как решение, без смены правила. Правки — в `main`, коммитом следом
> за `38db07d`; не отправлено.
> **Что это:** независимое ревью коммита `38db07d` (база `a791829`) по плану
> `2026-09-25-covered-child-failure-plan.md` — на Opus, по копии дерева,
> с зондами и мутациями в скретч-каталоге.
> **Связанные записи:** `2026-09-25-covered-child-failure-report.md`,
> `2026-09-25-covered-child-failure-plan.md`,
> `2026-09-25-covered-child-failure-plan-review.md`,
> `2026-09-25-observing-rakes-report.md`.

## Итог

Главное сделано верно. Покрытый провал ребёнка `ctx.run` и ветки `ctx.runAll`
теперь отвечается ровно один раз на всех путях, которые я прогнал: провал тела,
провал, поданный движком поверх отметки, у ребёнка и у ветки, две ветки,
упавшие в одном синхронном шаге, свой наблюдатель ребёнка, без наблюдателя
вовсе. Двойного ответа нет: у покрытого провала исход `Cancelled`,
и `_conclude` группы его не видит, а при флаге микрозадача прежнего пути
не ставится. Разделение `announced` верно: `_execute` зовёт `notifyObserver`
в том же `catch`, где собирает `Failed`, а `finish` получает провал, который
не шёл через тело. Порядок хуков ребёнка — `onError`, `onFinish`,
`onUnanswered`, и только потом тело родителя получает отмену. `solo` кода
не менял и получает ответ в `Solo.onUnanswered`, дальше `Solo.errorHandler` или
зона.

Числа отчёта, которые я проверял, — тесты пакетов до и после правки, пример
`solo`, `flutter_solo`, — сошлись с моими прогонами, и утверждение «на исходном
ядре красны …» тоже; не сошлась только таблица мутаций (находка 9). Формат,
анализ, `dart doc --dry-run`, тесты и пять проверок документов зелёные.

Но починка признака `_failedBeforeMark` неполна, и этой работой её дыра
переехала из корня в детей: провал, брошенный после неотменяемой отметки,
секция называет первым, если до этого придерживала отменяемую отмену. В `solo`
это воспроизводится на обычном ребёнке: родителя отменили, пока ребёнок
в `uncancellable`, потом состояние ушло из рабочего типа, и шаг, оборванный
отметкой, уходит в `Solo.onUnanswered` и зону, хотя до правки его слышал один
`Solo.onError` (находка 1). Починка — одно условие, набор на ней зелёный. Абзац
под таблицей `observing.md`, который владелец читает построчно, делит ошибки
на пересекающиеся виды и теряет условие «покрытый отменой» (находка 2).
Собственная запись `CHANGELOG` `solo` о `Solo.onUnanswered` теперь говорит
неправду (находка 3).

Работа годна после находок 1–3; остальное — мелкие поправки текста, два
неохраняемых решения и числа.

## Находки

1. **Medium. Секция называет первым провал после неотменяемой отметки, если
   придерживала отменяемую отмену: у ребёнка это теперь `onUnanswered`
   и зона.**

   Суть. Условие записи признака — `_owner._heldCancel != null`
   (`job_context.dart:850`). Отмена, которую нельзя отклонить
   (`rejectable: false`, так отменяют правила домена: `cancelOwnJob`,
   `keepWhile` в `solo`), метит задачу сразу, даже внутри секции,
   и придержанную раньше отменяемую не снимает. Шаг, оборванный этой отметкой
   (колбэк `onCancel` рвёт операцию), падает уже после неё, но `_heldCancel`
   всё ещё не `null`: секция записывает ошибку, `_execute` видит тождество
   и считает провал первым. Собственный довод комментария в секции — «without
   one nothing lands on the way out, and there is no order to put right» —
   годится и сюда: при уже поставленной отметке придержанная отмена на выходе
   тоже ничего не ставит (`cancelWith` возвращается
   на `_pendingCancel != null`). До правки у ребёнка такой провал слышал один
   `onError`, потому что исход смотрел родитель; теперь флаг `_takenByParent`
   ведёт его в `onUnanswered` и зону. У корня так было и до правки: старый
   признак ставился на любом провале секции.

   Свидетельство. Зонд A (`zz_wr_probe_test.dart`): ребёнок `ctx.run` —
   `RulesJob`, шаг в `uncancellable` ждёт 20 мс и бросает, если задача
   помечена; родителя отменяют на 5 мс (отмена придержана), на 10 мс
   `breakRule`. Без придержанной отмены (A0) — один `onError`. Зонд S3 в `solo`
   (`zz_wr_solo_probe_test.dart`): ребёнок `solo.job<Initial, int>`
   регистрирует `ctx.onCancel`, который рвёт ожидание шага ошибкой, и ждёт
   в `uncancellable`; на 5 мс отменяют родителя, на 10 мс
   `externalSetState(const Preparing())`.

```text
S3, a791829:
  Solo.onError child: Bad state: aborted by the mark
S3, 38db07d:
  Solo.onError child: Bad state: aborted by the mark
  Solo.onUnanswered child: Bad state: aborted by the mark
  zone: Bad state: aborted by the mark
```

   Пробная починка:

```dart
if (_owner._heldCancel != null && _owner._pendingCancel == null) {
  _owner._failedBeforeMark = error;
}
```

   С ней A и S3 дают один `onError`, корень A без наблюдателя молчит, как
   обещает строка таблицы «The body's, after the job accepted a cancellation»;
   P9 и вложенные секции C1 и C3 по-прежнему отвечаются. `async_job` — 613
   из 613 (600 своих и 13 зондов), `solo` — 797 из 797 (794 и 3). Весь набор
   проходит и без условия, и с ним: сейчас эти два варианта не различает
   ни один тест.

   Предложение. Добавить условие, сторож в группу «a failure after the child
   accepted a cancellation is only told» — `RulesJob` под `ctx.run`,
   придержанная отмена, затем `breakRule`, — и дописать запись `Fix` о секции
   в `CHANGELOG` ядра: «only when it held a cancellation» → «only when it held
   a cancellation and nothing had marked the job yet».

   Вердикт: принята. Зонды ревьюера на `38db07d` дали то же: A у ребёнка —
   `onError`, `onUnanswered`, зона; A у корня — зона; S3 в `solo` —
   `Solo.onError`, `Solo.onUnanswered`, зона. Условие стало
   `_owner._heldCancel != null && _owner._pendingCancel == null`, комментарий
   секции называет отметку, которую ставит правило домена. Сторожа: «a step a
   rule stopped while the section held a stop» в группе «only told»
   `unanswered_test.dart`, «a step a rule stopped while the section held a stop
   is not first» в `zone_test.dart` ядра, у корня, и «a step the state stopped
   while a section held a stop is only told» в `zone_test.dart` `solo`,
   сценарий S3; на прежнем условии красны все три. Запись `Fix` о секции
   в `CHANGELOG` ядра кончается на «only when it held a cancellation and
   nothing had marked the job yet», `docs/architecture.md` говорит то же.

2. **Medium. Абзац под таблицей `observing.md` делит ошибки на пересекающиеся
   виды и теряет условие «покрытый отменой».**

   Суть. Новая первая фраза: «An error can reach `onError` and the zone both: a
   failure the body throws, when nobody observed the outcome, and an error no
   outcome carries, when `onUnanswered` sends it on». Прежняя «a failure the
   job ends with» была точна для первой строки таблицы; новая «a failure the
   body throws» накрывает и четвёртую — «The body's, after the job accepted a
   cancellation | `onError` | Nobody»: этот провал бросило тело, исход никто
   не смотрел, а до зоны он не доходит. Она же накрывает покрытый провал
   ребёнка, и тогда «Observing the outcome keeps the first kind out of the
   zone» для него неверно — родитель исход смотрит, а провал идёт в зону.
   Последняя фраза пытается вынести его во второй вид, но называет его «the
   failure of a child or a branch whose parent took the outcome», без отмены.
   Читатель поймёт: любой провал ребёнка `ctx.run` идёт в `onUnanswered`.
   А непокрытый туда не идёт никогда: «A child's error or cancellation is
   thrown through the returned future», — говорит страница `children.md`.

   Слова «took the outcome» и «passes on» на странице без предмета: примера
   с ребёнком для этой строки нет, а «took the outcome» в публичных документах
   стоит только здесь и в записи `CHANGELOG` (`grep` по `packages/*/doc`,
   README, `CHANGELOG` и `docs/ru`). Это имя флага `_takenByParent`,
   пересказанное словами. Строка таблицы выше называет то же самое тем, что
   читатель пишет сам: «a child of `ctx.run` or a branch of `ctx.runAll`».

   И сама таблица: вторая строка («The body's, and a cancellation arrives while
   the job waits for its children | `onError`, and the zone if nobody observed
   the outcome») не ограничена, и читатель, открывший её одну, выведет для
   ребёнка `ctx.run` «родитель смотрит — зоны нет». Новая строка «The same, in
   a child …» поправляет её только тому, кто дочитал до следующей.

   Предложение. Первый вид назвать точно — провал тела, брошенный раньше всякой
   отмены, — а покрытый провал ребёнка назвать тем же, что в таблице: «a
   failure of a child of `ctx.run` or a branch of `ctx.runAll` that a
   cancellation covered is one of the second kind: `ctx.run` hands the parent's
   body the cancellation, and the failure is not in it». Вторую строку таблицы
   ограничить: «… in a job no `ctx.run` or group waits for». Перевод — вместе.
   Правка идёт пунктом в `2026-09-25-observing-rakes-report.md`, как шла
   и правка этой работы.

   Вердикт: принята, кроме ограничения второй строки таблицы. Абзац под
   таблицей больше не заводит видов: путь каждой ошибки в зону называет
   таблица — «when nobody observed the outcome» или «when `onUnanswered` sends
   it on», — первый путь закрывает наблюдение исхода, второй — переопределение
   `onUnanswered`. Слов «took the outcome» и «passes on» на странице
   не осталось. Вторую строку не ограничивал: строка «The same, in a child of
   `ctx.run` or a branch of `ctx.runAll`» стоит прямо под ней и её уточняет,
   а таблица так устроена и без неё — первая строка тоже общая, и строка ветки
   `ctx.runAll` ниже её уточняет. Перевод правлен вместе, правка записана
   абзацем пункта 5 в `2026-09-25-observing-rakes-report.md`.

3. **Medium. Собственная запись `CHANGELOG` `solo` о `Solo.onUnanswered` теперь
   неверна: отступление от плана оправдано наполовину.**

   Суть. Довод отчёта верен для унаследованной записи: она несёт ломающие
   изменения ядра, исправлений там не было, а у `flutter_solo` запись вовсе
   не перечисляет, что спрашивают у `onUnanswered`, — с ней согласен. Но первая
   запись `Breaking` в `Unreleased` у `solo` — своя, и она перечисляет:
   «`Solo.onUnanswered`, asked only about the errors no outcome carries: an
   operation abandoned by `wait` failing later, a disposer, an `onCancel`
   callback, work handed to `ctx.unattended`. A failure of a body is not one of
   them and never was: it becomes `Failed` …». Покрытый провал ребёнка — провал
   тела, и его спрашивают у `Solo.onUnanswered`: это держит сторож `solo`
   «reaches onUnanswered of the controller». Невыбранная ветка `runAll` тоже
   провал тела и тоже не названа — это осталось от прошлой работы, но «never
   was» теперь неверно дважды. `Solo.onUnanswered` в этом выпуске новый,
   и пользователь `solo` узнаёт, за что он отвечает, из этой записи,
   а не из записи ядра.

   Предложение. Отдельной записи `Fix` в `solo` не нужно; нужен точный перечень
   в его записи `Breaking`: добавить ветку `ctx.runAll`, которую группа
   не бросила, и провал ребёнка `ctx.run` или ветки, после которого пришла
   отмена, а «never was» заменить оговоркой, что остальной провал тела сюда
   не приходит.

   Вердикт: принята. Перечень записи `Breaking` о `Solo.onUnanswered` дополнен
   веткой `ctx.runAll`, которую группа не бросила, и провалом тела ребёнка
   `ctx.run` или ветки `ctx.runAll`, после которого пришла отмена; «never was»
   заменено на «Any other failure of a body is not one of them». Отдельной
   записи `Fix` в `solo` нет; отступление в отчёте переписано.

4. **Low. `errors.md` `solo` и перевод называют шире, чем правда: «провал тела
   дочерней задачи».**

   Суть. Новый пункт перечня — «the failure of a child's body when a
   cancellation reaches the child afterwards, while it still waits for children
   of its own». Ребёнок `ctx.each` — тоже ребёнок, и на той же странице
   `children.md` у `solo` его `value` ждут
   (`await ctx.each(session.stream, take).value`). Его покрытый провал
   у `Solo.onUnanswered` не бывает — правило корня, вопрос 4 плана. В dartdoc
   `Solo.onUnanswered` сказано точно: «in a child of [JobContext.run] or a
   branch».

   Свидетельство. Зонды S1 и S2 в `solo`: колбэк `each` запускает внука
   и бросает, родителя отменяют на 10 мс. S1, родитель ждёт `.value`: один
   `Solo.onError`. S2, `value` никто не читает: `Solo.onError` и зона, мимо
   `Solo.errorHandler`. На `a791829` то же самое.

   Предложение. «the failure of the body of a child of `ctx.run` or a branch of
   `ctx.runAll` …» — в оригинале и в переводе.

   Вердикт: принята. Зонды S1 и S2 дали то же: родитель ждёт `.value` — один
   `Solo.onError`; `value` никто не читает — `Solo.onError` и зона.
   В `errors.md` `solo` и в переводе теперь «the failure of the body of a child
   of `ctx.run` or a branch of `ctx.runAll`».

5. **Low. Окно, в котором отмена покрывает провал, описано уже, чем в коде.**

   Суть. `_execute` считает провал покрытым, если к `finish` задача помечена:
   отмена может прийти и пока задача ждёт детей, и пока она раскручивает стек
   уборки. Новые тексты называют только первое: «while it still waited for
   children of its own» в `children.md` обоих пакетов, «while it still waits
   for children of its own» в `errors.md` `solo` и в записи `Fix` `CHANGELOG`
   ядра, «while the job still waits for its children» в dartdoc `Failed`,
   «задача ждала детей» в `docs/architecture.md`, и переводы. Dartdoc
   `onError`, `onUnanswered`, `JobContext.run` и `Solo.onUnanswered` говорят
   «covered afterwards» и верны. Вторая строка таблицы `observing.md` той же
   узости стояла и до правки.

   Свидетельство. Зонд B: ребёнок `ctx.run` без внуков,
   `ctx.onDispose(() => delay(20))`, тело бросает на 5 мс, родителя отменяют
   на 10 мс. `38db07d`: `onError`, `onFinish`, `onUnanswered`, зона; `a791829`:
   один `onError`. Ребёнок с асинхронной уборкой идёт этой дорогой, хотя своих
   детей у него нет.

   Предложение. «a cancellation reached the child before it finished — while it
   waited for children of its own or ran its cleanup», или короче, как
   в dartdoc: «a cancellation that came afterwards».

   Вердикт: принята. Зонд B дал то же: ребёнок без внуков с асинхронной
   уборкой — `onError`, `onFinish`, `onUnanswered`, зона. Окно названо целиком,
   «while it still waits for children of its own or runs its cleanup», —
   в `children.md` обоих пакетов, `errors.md` `solo`, записях `CHANGELOG` ядра
   и `solo`, dartdoc `Failed`, `docs/architecture.md`, во второй строке таблицы
   `observing.md` и в переводах. Сторожа: «a child of run cancelled while its
   cleanup runs» в группе ответа `unanswered_test.dart` и «a cancellation while
   the cleanup runs: the same as the failure» в `observing_rakes_test.dart`,
   у корня.

6. **Low. Три решения работы не держит ни один тест.**

   - Синхронный ответ. Мутация «ответ с флагом — в микрозадаче» проходит весь
     набор (0 красных); «ответ по таймеру» краснит один сторож страницы. План
     и отчёт выводят из синхронности порядок: ответ раньше, чем тело родителя
     получит отмену. Зонд G этот порядок показывает, тест — нет.
   - Фильтр отмены на новом пути. `docs/architecture.md` и dartdoc `_toZone`
     обещают: `Failed`, собранный вокруг `Cancelled` и поданный поверх отметки
     ребёнку, чей исход взял родитель, в зону не идёт. Мутация «без
     наблюдателя — прямо в зону, мимо фильтра» проходит весь набор. Зонд R:
     с наблюдателем `onError` и `onUnanswered`, зоны нет; без наблюдателя
     пусто; корень — `zone: Cancelled(manual: built on purpose)`.
   - Точное условие секции — находка 1.

   Мутация «ответ за провал, поданный через `finish`, до `onFinish`» тоже
   проходит, но порядок там нигде не обещан.

   Предложение. В тест «a child of run whose parent was cancelled» добавить
   запись из тела родителя, когда оно ловит отмену, и сверять порядок; тест
   на `Failed(Cancelled(...))`, поданный поверх отметки ребёнка, с наблюдателем
   и без.

   Вердикт: принята. Тест «the answer comes before the parent hears the
   cancellation» сверяет порядок: `onError`, `onUnanswered`, тело родителя.
   Тест «a cancellation an engine handed in as a failure is dropped» держит
   фильтр с наблюдателем и без. Мутация «ответ в микрозадаче» теперь краснит
   одного сторожа порядка, «без наблюдателя — прямо в зону» — одного сторожа
   фильтра. Порядок ответа за поданный провал относительно `onFinish` нигде
   не обещан, и сторожа на него нет.

7. **Low. Обёрнутая ошибка секции теряет диагноз: у корня была зона, стал один
   `onError`.**

   Суть. Сверка тождества различает «тело поймало ошибку секции и пошло дальше»
   и «тело бросило её снова», но не отличает от первого обёртку, брошенную
   прямо в `catch`: `on DbException catch (e) { throw PaymentFailed(e); }`.
   Такая обёртка — следствие первого провала, а ядро считает её провалом после
   отметки. Запись `CHANGELOG` говорит это прямо («only for its own error»),
   и сторож «another failure after a step that failed under a held stop» держит
   именно это поведение, так что это решение, а не промах. Но у корня оно
   меняет маршрут, и читатель страниц об этом не узнает.

   Свидетельство. Зонд D: корень, шаг в `uncancellable` падает на 20 мс при
   придержанной с 10 мс отмене, тело оборачивает ошибку в `FormatException`.
   `a791829`: `onError`, `onFinish`, зона. `38db07d`: `onError`, `onFinish`.
   Зонд D2, тот же шаг, `rethrow`: зона в обоих.

   Предложение. Решить владельцу: оставить и сказать в dartdoc
   `JobContext.uncancellable`, что диагноз сохраняется за той ошибкой, которую
   бросил шаг, или искать другое правило. Я за первое: иного признака у ядра
   нет.

   Вердикт: принята как решение, правило не меняется. Строка таблицы и так
   относит обёртку к провалам после принятой отмены: секция отпустила отмену
   на выходе, и обёртку тело бросило уже после. Dartdoc
   `JobContext.uncancellable` говорит теперь прямо: первой названа только
   ошибка шага, и тело сохраняет это, пропустив её или бросив снова, а новая
   ошибка на её месте, обёртка тоже, приходит после отмены, и её слышит один
   `onError`. Сторож — прежний «another failure after a step that failed under
   a held stop». Владельцу вынесено в отчёте как принятое решение.

8. **Low. Формулировки dartdoc и страниц.**

   - `Job.ignore`: «A child whose failures nobody should answer for is given an
     observer of its own that answers for nothing». «whose failures» шире
     правды: непокрытый провал `ctx.run` бросает в тело родителя при любом
     наблюдателе. «answers for nothing» читается как «не отвечает», то есть
     тело по умолчанию, а оно шлёт в зону. Точнее: «whose `onUnanswered` does
     nothing», и речь о провале, покрытом отменой.
   - `JobObserver.onError`: «a failure of the body the parent took and cannot
     pass on» читается как «тело, которое взял родитель».
   - `children.md` обоих пакетов и переводы: «whichever `ignore` was called» /
     «какой бы `ignore` ни был вызван» предполагает, что какой-то вызван;
     точнее «whether `child.ignore()`, `ctx.run(child).ignore()` or neither was
     called». «One failure of the child is not in that future» читается как
     «один из провалов»; речь о виде провала.

   Вердикт: принята. `Job.ignore`: «To answer for it differently, give the
   child an observer of its own that overrides [JobObserver.onUnanswered]».
   `JobObserver.onError`: «and so do two failures of the body that a parent
   cannot pass on». `children.md` обоих пакетов и переводы: абзац начинается
   с «That future does not carry a failure of the child's body if …», а вместо
   «whichever `ignore` was called» стоит «whether or not `child.ignore()` or
   `ctx.run(child).ignore()` was called».

9. **Low. Числа отчёта и `docs/handoff.md`.**

   - Таблица мутаций отчёта в четырёх строках на единицу меньше моего прогона
     по всему набору `async_job`: «`_awaitChild` не ставит флаг» — 6, а не 5;
     «с флагом всегда `notifyError`» — 8, а не 7; «с флагом ответа нет» — 9,
     а не 8; «`_execute` передаёт `announced: false`» — 8, а не 7. Лишний везде
     один и тот же — сторож страницы «the same in a child of run: onError, then
     the zone»: похоже, мутации гоняли до того, как он появился. Остальные
     девять строк сошлись, и вывод «ответа нет — краснеют одни новые сторожа»
     верен.
   - `docs/handoff.md`: «Сторож —
     `packages/async_job/test/observing_rakes_test.dart`, 34 теста» — в файле
     36 (35 после пункта 4 вычитки, 36 после этой работы). В том же абзаце
     перенос «даёт наблюдателю 0» / «мс» рвёт число и единицу.

   Вердикт: принята. Лог моих мутаций подтвердил догадку: в нём нет сторожа
   страницы, прогон шёл до него. Мутации прогнаны заново по всему набору
   `async_job` после всех правок, таблица отчёта заменена. В `docs/handoff.md`
   число тестов сторожа исправлено, а фраза с «0 мс» переписана так, что число
   и единица не рвутся.

## Как проверено

Копия дерева: `git checkout --detach 38db07d`; база `a791829` выгружена
`git archive` в скретч-каталог. Зонды лежали
в `packages/async_job/test/zz_wr_probe_test.dart`
и `packages/solo/test/zz_wr_solo_probe_test.dart`, запускались изнутри пакета,
на `38db07d` и на базе; утверждений в них нет, только печать журнала из-за
пределов `runZonedGuarded`. Убраны, дерево на `38db07d` чистое.

- Проверки пакетов. `async_job`:
  `dart format --output=none --set-exit-if-changed lib test` — 0 изменённых,
  `dart analyze` — чисто, `dart test` — 600, `dart doc --dry-run` — 0
  предупреждений. `solo`: то же, 794. Пример `solo` — 47, `flutter_solo` — 85.
  База: `async_job` 585, `solo` 791.
- Новые тесты на базе: красны восемь тестов группы «a failure a cancellation
  covered, when a parent took the outcome», сторож `zone_test.dart` ядра,
  сторож страницы в `observing_rakes_test.dart` и три сторожа `solo`; группы
  «only told» и границы зелёные — как в отчёте.
- Зонды ядра: A, A0 (находка 1), B (находка 5), C1–C3 — вложенные секции:
  внутренняя падает при придержанной отмене, внешняя бросает дальше, глотает
  или оборачивает; D, D2 (находка 7), G — порядок хуков, I — провал, поданный
  поверх отметки ветке `runAll`: один `onError`, один `onUnanswered`, одна
  зона; P — две ветки падают синхронно при живых внуках: группа бросает первую,
  вторая отвечается; Q — без наблюдателей: одна зона; R (находка 6). Зонды
  `solo`: S1, S2 (находка 4), S3 (находка 1).
- Мутации — двадцать, скриптом, откат копией файла со сверкой хэша, счёт
  по меткам `[E]` во всём наборе `async_job`: тринадцать из отчёта и семь
  своих. Не пойманы: `then` с `announced: false` (эквивалентная), ответ
  в микрозадаче, обход фильтра без наблюдателя, точное условие секции, ответ
  за поданный провал до `onFinish`, запись признака только внешней секцией
  (почти эквивалентная: ошибка внутренней проходит через внешнюю). Пойманы:
  ответ по таймеру (1), флаг после чтения `value` (6).
- Документы: `check_translations.py`, `reflow.py --check`,
  `check_line_width.py`, `check_links.py`, `check_doc_shape.py` — чисто; ширина
  и заливка изменённых записей — чисто. Каждую новую фразу страниц и dartdoc
  сверял с кодом и зондами; переводы сверены по смыслу с оригиналами.
