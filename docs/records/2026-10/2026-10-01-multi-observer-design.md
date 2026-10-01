> **Состояние на 2026-10-01:** вторая редакция по решениям владельца прошла
> независимое ревью, находки приняты и внесены; кода нет. Ревью обеих
> редакций — в конце записи.
> **Что это:** несколько наблюдателей у одной задачи и у `Solo.observer`:
> `JobObserver.all` и `SoloObserver.all`, а ответ за ошибку — отдельный
> интерфейс `JobAnswerer`.
> **Связанные записи:** `2026-09-25-observing-rakes-report.md`.

# Несколько наблюдателей

## Зачем

Задача получает одного наблюдателя, `Solo.observer` — тоже один. Приложению
обычно нужно несколько: лог, аналитика, отчёт о падениях, а в `solo` ещё
и наблюдатели со страницы `errors.md` (`SlowCancellations`,
`StuckCancellations`). Сейчас их сводят в один класс руками, и он смешивает
разную работу в одном месте.

## Решения владельца

2026-10-01, по ходу разговора о первой редакции:

- составной наблюдатель делается для обоих пакетов;
- наблюдение и ответ за ошибку — разные интерфейсы: `JobObserver` наблюдает,
  `JobAnswerer` отвечает, конкретный класс может смешать оба;
- составной получает один список, без отдельного `answer:`; отвечающих больше
  одного — `ArgumentError`;
- имена: `JobObserver.all` и `JobAnswerer`. `SoloObserver.all` — по той же
  схеме.

## Ловушка, ради которой это не рецепт

Сейчас у `JobObserver` хуки двух видов. `onStart`, `onFinish`, `onError`
и `onLog` только сообщают. `onUnanswered` отвечает за ошибку, которую не несёт
ни один исход, и тело по умолчанию отдаёт её в зону, где задача создана. Класс,
который раздаёт списку все пять, отдаёт ошибку в зону столько раз, сколько
в списке наблюдателей без своего ответа, и ответ одного её не останавливает.
Зонд 2026-10-01 на `f36d03d`, два логгера и один отвечающий, работа
из `ctx.unattended` бросает:

```text
без отвечающего: [a onError, b onError] [zone: late, zone: late]
с отвечающим:    [a onError, b onError, sentry answered] [zone: late, zone: late]
```

Узнать, переопределил ли наблюдатель `onUnanswered`, во время выполнения
нельзя, поэтому составной не может сам решить, кого спросить. Разделение
интерфейсов делает это видимым по типу.

## `async_job`

```dart
abstract mixin class JobObserver {
  JobObserver();

  factory JobObserver.all(Iterable<JobObserver> observers);

  void onStart(Job<Object?> job) {}
  void onFinish(Job<Object?> job) {}
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {}
  void onLog(Job<Object?> job, Object? message) {}
}

mixin JobAnswerer on JobObserver {
  void onUnanswered(Job<Object?> job, Object error, StackTrace stackTrace) {
    // the body JobObserver.onUnanswered has today
  }
}
```

```dart
final class Crashes with JobObserver, JobAnswerer { ... }

Job<void>(observer: JobObserver.all([Log(), Analytics(), Crashes()]), body);
```

Правила:

1. `onUnanswered` переезжает из `JobObserver` в `JobAnswerer` вместе с телом
   по умолчанию: зона, где задача создана, отмены отбрасываются. Ядро,
   `_handleUnanswered` (`job_base.dart:1294`), спрашивает наблюдателя, только
   если он `JobAnswerer`; иначе, как и без наблюдателя, ошибка уходит в зону.
   `super.onUnanswered` в переопределении работает, как сейчас.
2. `JobObserver();` объявлен явно. Фабрика без него отнимает конструктор
   по умолчанию у каждого `extends JobObserver`; зонд на 3.6.0 и 3.13.0: «The
   superclass … has no unnamed constructor that takes no arguments».
   `abstract mixin class` принимает только тривиальный генеративный
   конструктор, и `with JobObserver` с ним собирается.
3. `JobObserver.all` обходит `observers` один раз и копирует. `onStart`,
   `onFinish`, `onError` и `onLog` идут каждому по порядку списка, каждый вызов
   изолирован `JobBase._notify`: ошибка — в текущую зону, `Cancelled` никуда,
   следующий вызывается. Порядок задаёт пользователь, отвечающий наблюдает
   на своём месте.
4. Отвечающий в списке — тот, кто `is JobAnswerer`. Ни одного — фабрика
   возвращает составной, который сам `JobAnswerer` не является, и ядро отдаёт
   ошибку в зону один раз. Один — составной, который `JobAnswerer` и передаёт
   `onUnanswered` ему; ядро зовёт его после всех `onError`, так что крошки
   любого наблюдателя ложатся до ответа. Больше одного — `ArgumentError`.
5. Вложенность следует из типа. Составной с отвечающим сам `JobAnswerer`
   и считается отвечающим внешнего; без отвечающего — не считается. Отдельного
   правила не нужно: зонд, `[Log(), JobObserver.all([Crashes()])]` отвечает
   через `Crashes`, а `[Crashes(), JobObserver.all([Log(), Crashes()])]` —
   `ArgumentError`.
6. Один и тот же наблюдатель дважды (`identical`), считая вложенные
   составные, — `ArgumentError`: иначе он слышит каждое событие дважды,
   и молча.
7. Ленивое сообщение `onLog` строит каждый наблюдатель, который следует
   соглашению `Log` со страницы: столько раз, сколько их. Это говорит dartdoc.
8. Реализация — два приватных `final` класса в `observer.dart`, части
   `job_base.dart`: наблюдающий и наследник с `JobAnswerer`. Публичных геттеров
   нет.

Что остаётся как было: дети без своего наблюдателя наследуют составного целиком
(`job_context.dart:1424`); продолжение `then` берёт только переданного ему;
ядро о составном не знает. `Job.ignore` по-прежнему не пускает две ошибки тела
к ответу.

Что ломается, и почему это дёшево. `onUnanswered` нет в выпущенной 0.2.0: он
пришёл в `## Unreleased`, и опубликованный пользователь ничего не теряет. Код
на дереве, который его переопределяет, получает `with JobAnswerer`. Ловушка
остаётся одна: класс с `onUnanswered`, но без `JobAnswerer`, молча не отвечает.
Анализатор предупреждает `override_on_non_overriding_member`, только если
у метода уже стоит `@override`: в перенесённом коде и в коде, скопированном
со страницы. Новый код без аннотации молчит: `annotate_overrides` требует её
лишь на том, что переопределяет. Это говорят dartdoc `JobAnswerer` и запись
`CHANGELOG`.

`solo`: `_SoloJobObserver` (`solo.dart:1240`) получает `implements JobAnswerer`
и отвечает, как сейчас, через `Solo.onUnanswered`. Сам `Solo.onUnanswered` —
метод контроллера, его разделение не трогает.

## `solo`

```dart
abstract class SoloObserver {
  SoloObserver();

  factory SoloObserver.all(Iterable<SoloObserver> observers);
  ...
}
```

```dart
Solo.observer = SoloObserver.all([
  LoggingObserver(),
  SlowCancellations(),
  StuckCancellations(),
]);
```

Все семь хуков (`onCreate`, `onStart`, `onFinish`, `onError`, `onChange`,
`onLog`, `onClose`) идут каждому по порядку. Изоляция — правило
`Solo._callHook`: ошибка в текущую зону, включая `Cancelled`, следующий
вызывается; обёртка не меняет, куда идёт ошибка одиночного наблюдателя. Чтобы
правило было одно, тело `_callHook` переезжает в функцию `callHook` в новом
`lib/src/call_hook.dart`, который `lib/solo.dart` не экспортирует; её зовут
и `Solo`, и составной в `observer.dart`. Вердикт 4 первой редакции предлагал
класс в `solo.dart` с прямым вызовом `Solo._callHook`; фабрика в `SoloObserver`
из библиотеки `observer.dart` приватного класса `solo.dart` не видит, поэтому
общей стала функция. Фабрика стоит в `SoloObserver`, а приватный класс — рядом
с ним, в той же библиотеке. Повтор (`identical`, считая вложенные) —
`ArgumentError`. Отвечать нечем и некому: за ошибки отвечают
`Solo.onUnanswered` и `Solo.errorHandler`.

`flutter_solo` своего наблюдателя не имеет и получает всё реэкспортом.

## Документы

- `packages/async_job/doc/observing.md` и перевод.
  - Раздел «Observer»: четыре хука `JobObserver`, `onUnanswered` —
    у `JobAnswerer`, класс примешивает его, чтобы отвечать.
  - Раздел «Where errors go», «An observer»: пример переопределения
    `onUnanswered` становится классом `with JobAnswerer`; таблица и проза
    говорят «`onUnanswered`, если наблюдатель отвечает, иначе зона».
  - Новый раздел «Several observers» после «Work the job does not wait for»,
    перед «Testing». Требование: у задачи `Reporter` со страницы и `Crashes`,
    `JobAnswerer`, чей `onUnanswered` печатает `onUnanswered: $error`; отправка
    аналитики из раздела выше падает. Первая попытка — то, к чему ведёт
    словарь: `observer:` принимает `JobObserver`, и класс раздаёт списку его
    хуки. Он не `JobAnswerer`, ядро его не спрашивает, ответ `Crashes`
    пропадает, и ошибка уходит в зону: цитата `outcome:`, `onError:`, `zone:` —
    дословно цитата раздела выше, и проза говорит, что с `Crashes` в списке
    вышло то же, что без него. Ответ:
    `JobObserver.all([Reporter(), Crashes()])`, цитата `outcome:`, `onError:`,
    `onUnanswered:`. Абзац правил: порядок, один отвечающий, вложенность,
    повтор; и второй самодельный исход — пересыльщик `with JobAnswerer`,
    который раздаёт `onUnanswered` отвечающим списка: без отвечающего ошибка
    пропадает, с двумя отвечают оба.
  - Вступление: фраза о строке `onUnanswered:`.
  - README: строка оглавления называет `JobAnswerer`.
- `packages/solo/doc/errors.md` и перевод: абзац и код с `SoloObserver.all`
  в конце «A cancellation that never lands», после `StuckCancellations`. Первой
  попытки нет: ловушки нет. На страницах `solo` и `flutter_solo` речь идёт
  о `Solo.onUnanswered`, разделение их не трогает.
- Остальные страницы `async_job` и переводы, где путь ответа назван через
  наблюдателя: `children.md` («override `onUnanswered` in the child's
  observer», и ещё одно место ниже), рецепт движка в `extending.md` («put an
  observer of your own on every job and override its `onUnanswered`»),
  `observing.md` — строка о `with JobObserver`, абзац «An override of
  `onUnanswered` closes the second», абзац о `ctx.unattended` («its
  `onUnanswered` sends them on»). Пример переопределения на `observing.md`
  становится классом по образцу `Answering` из сторожа.
- Dartdoc ядра: ссылки `[JobObserver.onUnanswered]` и `[onUnanswered]`
  в `job_base.dart`, `job_context.dart`, `observer.dart`, `outcome.dart`
  и проза о пути «`onError` and `onUnanswered`, or the zone»
  в `job_context.dart` и `job_stream.dart` — под `JobAnswerer`; совет «override
  [JobObserver.onUnanswered] in the child's observer» — сделать наблюдателя
  `JobAnswerer`. Dartdoc `JobAnswerer` показывает оба написания:
  `extends JobObserver with JobAnswerer` и `with JobObserver, JobAnswerer`;
  голое `with JobAnswerer` анализатор советует чинить через
  `extends JobAnswerer`, а это ошибка.
- `CHANGELOG.md`, `## Unreleased`: запись `async_job` о новом `onUnanswered`
  переписывается под `JobAnswerer`; «Added» — `JobObserver.all`. У `solo` —
  `SoloObserver.all` и унаследованное; у `flutter_solo` — унаследованное.
  Фразы, которые разделение делает ложными: у `async_job` «A class that
  implements `JobObserver` stops compiling until it has an `onUnanswered`»
  (по исходникам 0.2.0 больше не ломается ничего, меняется поведение), «an
  override of `onUnanswered` with an empty body keeps the old behaviour»,
  последний абзац «Changes you will see on upgrade»; у `solo` — «a class that
  implements `JobObserver` needs an `onUnanswered`»; у `flutter_solo` — «the
  new `JobObserver.onUnanswered`». Нижняя граница `async_job`
  в `packages/solo/pubspec.yaml` поднимается при выпуске вместе с остальным
  невыпущенным ядром.

## Тесты

- `packages/async_job/test/observer_all_test.dart`: порядок; изоляция
  (бросивший не выключает следующего, ошибка в зоне, `Cancelled` никуда);
  ни одного отвечающего — два наблюдателя, задача создана в одной зоне, ошибка
  рождается в другой, и приходит в зону создания ровно один раз, а брошенная
  отмена — никуда (путь целиком в ядре: составной без отвечающего
  не `JobAnswerer`); один отвечающий получает `onUnanswered` после всех
  `onError`, на любом месте списка; два — `ArgumentError`, и вложенный тоже;
  вложенный составной с отвечающим отвечает; повтор и вложенный повтор —
  `ArgumentError`; ленивый `Iterable` обходится один раз; правка исходного
  списка ничего не меняет; пустой список ведёт себя как наблюдатель без хуков;
  ребёнок наследует составного (сторож обещания страницы).
- Ядро: наблюдатель без `JobAnswerer` — ошибка в зону создания; с ним —
  `onUnanswered`. Существующие тестовые наблюдатели с `onUnanswered` получают
  `with JobAnswerer`; анализатор назовёт каждого: восемь ошибкой, четыре
  предупреждением, и эти четыре без правки краснят шесть тестов. `Forwarding`
  в `unanswered_test.dart` пересылает `onUnanswered` полю `inner` и получает
  проверку `inner is JobAnswerer`; `Plain` зовёт `onUnanswered` руками.
- Ядро, две зоны: одиночный наблюдатель без `JobAnswerer`, задача создана
  в одной зоне, ошибка рождается в другой, приходит в зону создания.
- Составной без отвечающего — не `JobAnswerer`:
  `JobObserver.all([Log()]) is! JobAnswerer`,
  и `[Crashes(), JobObserver.all([Log()])]` принимается и отвечает через
  `Crashes`.
- `observing_rakes_test.dart`: код новых и изменённых фрагментов, две новые
  цитаты.
- `packages/solo/test/observer_all_test.dart`: семь хуков по порядку, изоляция,
  `Cancelled` в зону, как у одиночного, повтор, копия списка.
  `errors_rakes_test.dart`: строка с составным рядом с кодом «Why cancellation
  was slow».
- Мутации: без изоляции в обоих; составной всегда `JobAnswerer`; ядро
  спрашивает любого наблюдателя; `Zone.current` вместо тела по умолчанию; без
  проверки двух отвечающих; без проверки повтора; `Iterable` без копии;
  `SoloObserver.all` с правилом ядра вместо `callHook`; ядро для наблюдателя
  без `JobAnswerer` — `Zone.current` вместо `_toZone` и «никуда».
- `errors_rakes_test.dart`: копии наблюдателей там берут `lines`,
  а `LoggingObserver` нет, поэтому строку страницы с тремя наблюдателями сторож
  дословно не держит; тест показывает, что составной из копий работает.
  `observer_all_test.dart` у `solo` проверяет и ленивый `Iterable`, и вложенный
  повтор.

## Вопросы ревьюеру

1. `mixin JobAnswerer on JobObserver` против независимого интерфейса: что
   теряет класс, который только отвечает, и нужен ли такой вообще?
2. Ловушка «`onUnanswered` без `JobAnswerer`»: хватит ли предупреждения
   анализатора, или ядру есть чем её поймать?
3. Не ломает ли разделение что-то в `solo` и `flutter_solo` сверх
   `_SoloJobObserver`: тесты, примеры, документы.
4. Порядок разделов и первая попытка в `observing.md` после разделения.

## Ревью первой редакции

Первая редакция: `MultiJobObserver(observers, answer: ...)`
и `MultiSoloObserver(observers)`. Независимый ревьюер на Opus, 2026-10-01,
по копии дерева на `f36d03d`. Номера правил в вердиктах — первой редакции: её
правило 4 стало правилом 6, правило 5 — правилом 3, правило 6 — правилом 8.
Ревьюер: скелет обоих классов по правилам дизайна, зонды тестами внутри пакетов
на Dart 3.13 и на полу 3.6.0. Ниже его отчёт, к каждой находке — вердикт.

Что подтвердилось: на 3.6.0 `dart analyze lib` обоих пакетов чист, зонды
`async_job` 19 из 19, `solo` 3 из 3; языка новее 3.6 дизайн не требует.
Порядок: список по порядку, `answer` последним, его `onUnanswered` после всех
`onError`. Без `answer` при двух наблюдателях с телом по умолчанию строка
`zone:` одна; пустой список ведёт себя как задача без наблюдателя. Изоляция:
бросивший `onStart` не выключает следующих, `Cancelled` из `onLog` никуда
не уходит. Бросивший `onUnanswered` у `answer` изолирует обёртка ядра `_notify`
(`job_base.dart:1301`). `ArgumentError` на `answer` в списке срабатывает,
правка исходного списка ничего не меняет, ребёнок наследует составного
(`job_context.dart:1424`). `MultiSoloObserver`: семь хуков по порядку,
бросивший не выключает второго. Блокеров нет.

1. Нужно исправить. Составной с `answer`, положенный в список другого
   составного, молча теряет свой ответ: правило 2 обходит `onUnanswered`
   каждого из списка. Зонд
   `MultiJobObserver([MultiJobObserver([a], answer: inner)])` с ошибкой
   из `ctx.unattended` печатает
   `a onError, inner onError, zone: Bad state: late`. Сценарий естественный:
   модуль отдаёт готового наблюдателя с `answer`, экран добавляет к нему лог
   списком. Обратный случай работает: составной в роли `answer` спрашивает
   свой. Решение — `ArgumentError` с советом передать такой составной как
   `answer` или поднять вложенный ответ наверх; тест и мутация нужны при любом.

   Вердикт: принято, `ArgumentError` с советом — правило 4. Подъём ответа
   наверх молча выбирал бы, кто отвечает, когда ответов два. Во второй редакции
   закрыто иначе: составной с отвечающим сам `JobAnswerer`, считается
   отвечающим внешнего и отвечает (правило 5); два отвечающих —
   `ArgumentError`.

2. Нужно исправить. Тест «без `answer` — зона один раз» не отличает зону
   создания от текущей: тело по умолчанию идёт в `_toZone`
   (`observer.dart:88-89`, `job_base.dart:1329-1336`), а замена
   `Zone.current.handleUncaughtError` отправила бы ошибку в зону вызывающего,
   и в харнессе сторожа это одна зона. Зонд: задача создана в зоне `creation`,
   её `whenCancelled` бросает, `cancel()` зовётся из `canceller`; `answer`
   видит текущей `canceller`, а ошибка приходит в `creation`. Нужен тест
   с двумя зонами и с двумя наблюдателями с телом по умолчанию, мутация
   в списке; `whenCancelled((c) => throw c)` закрывает тем же тестом «отмена
   не идёт».

   Вердикт: принято, раздел «Тесты» и мутация `Zone.current`.

3. Нужно исправить. Пример `MultiSoloObserver` и «Зачем» берут `SlowJobs`,
   а на странице это первая попытка (`errors.md:228-252`). Раздел «Watching
   every controller» стоит до «Why cancellation was slow», и второго
   наблюдателя у читателя там ещё нет. Место — конец «A cancellation that never
   lands», после `StuckCancellations`, со списком из трёх.

   Вердикт: принято, своей командой проверено (`errors.md:228`). Пример и место
   переписаны.

4. Нужно исправить. Изоляция в `MultiSoloObserver` копирует правило `_callHook`
   в другую библиотеку, хотя класс может жить в `solo.dart` (`solo.dart:9` уже
   импортирует `observer.dart`) и звать `Solo._callHook` напрямую, как
   `_SoloJobObserver` (`solo.dart:1240-1278`). Правила ядра и `solo`
   о брошенном `Cancelled` уже разные, третья копия — ещё одно место держать
   в лад.

   Вердикт: принято, класс в `solo.dart` и зовёт `_callHook`.

5. Нужно исправить. Правило 4 ловит один случай двойного слушания, а довод
   у него общий: `[a, a]` и наблюдатель, который стоит в списке и служит
   `answer` вложенного составного, тоже слышат всё дважды, и молча. Варианты:
   проверять любой повтор по `identical` через `LinkedHashSet.identity()` или
   сузить формулировку.

   Вердикт: принято, проверка любого повтора, считая вложенные составные —
   правило 4.

6. Нужно исправить. Вступление `observing.md:7-10` объясняет каждую строку
   цитат; пусть `Crashes` печатает `onUnanswered: $error`, как переопределение
   на странице (`observing.md:244-248`), и вступление получит одну фразу.

   Вердикт: принято, раздел «Документы».

7. Мелочь. Порядок строк цитаты первой попытки зависит от порядка списка:
   с `[Reporter(), Crashes()]` зона идёт раньше ответа. Зафиксировать в записи.

   Вердикт: принято, раздел «Документы».

8. Мелочь. Класс первой попытки — около 25 строк, а первые попытки страницы —
   одна-три. На странице хватит `onError` и `onUnanswered`, остальное
   комментарием; сторож держит класс целиком. Соседний вариант привычки —
   раздать четыре хука, а `onUnanswered` не трогать: ошибка уходит в зону раз,
   а `Crashes` не спрашивают; цитата совпала бы с `quoted[4]`, так что для
   страницы лучше вариант на пять хуков, а абзац с правилами может назвать
   и этот исход.

   Вердикт: принято, раздел «Документы»; второй исход абзац правил назовёт.
   Во второй редакции устарело вместе с вердиктом 7: первая попытка раздаёт
   четыре хука и ответа не печатает; замена — находка 5 второй редакции.

9. Мелочь. Правило 6 приписывает `super.onUnanswered` причину, которой нет:
   частью `job_base.dart` класс нужен ради `JobBase._notify`,
   а `super.onUnanswered` публичен.

   Вердикт: принято, правило 6.

10. Мелочь. «Неизменяемым» снаружи не проверить; полезнее тест на ленивый
    `Iterable`: при хранении как есть наблюдатели строятся на каждое событие,
    и наблюдатель на `Expando` теряет метку между `onStart` и `onFinish`.

    Вердикт: принято, правило 5 и тест.

11. Мелочь. Тест наследования прошёл бы с любым `JobObserver`, мутаций нового
    кода не ловит; теста на пустой список без `answer` в плане нет.

    Вердикт: принято, раздел «Тесты».

12. Мелочь. Ленивое сообщение `onLog` строит каждый наблюдатель, следующий
    соглашению `Log`; одна фраза в dartdoc.

    Вердикт: принято, правило 7.

13. Мелочь. `errors_rakes_test.dart` код «Watching every controller» не держит
    (`LoggingObserver` — 0 вхождений); если абзац переедет по пункту 3, код
    «Why cancellation was slow» сторож держит, и строку добавить туда.

    Вердикт: принято, своей командой проверено; раздел «Тесты».

14. Мелочь. Унаследованный `MultiJobObserver` в `CHANGELOG.md` `solo` правдив,
    только если поднята нижняя граница `async_job` (`pubspec.yaml:18`,
    `^0.2.0`); `floor` нехватку этого класса не поймает, если его не назовёт
    тест или пример `solo`. Прецедент — строка «Requires `async_job: ^…`»
    в `solo/CHANGELOG.md:423`.

    Вердикт: принято как задача выпуска, раздел «Документы»: граница
    поднимается при выпуске вместе с остальным невыпущенным ядром.

15. Вопрос 1. Оставить правило 3. «`answer` только отвечает» вместе с правилом
    4 делает непригодным класс, который пишет крошки в `onError` и отвечает;
    функция `onUnanswered:` теряет тело по умолчанию. Зонд порядка: `c onError`
    раньше `c onUnanswered`, крошки ложатся до ответа.

    Вердикт: принято, правило 3 остаётся.

16. Вопрос 2. Проверка полезна, но непоследовательна (пункт 5); одна проверка
    на любой повтор и отдельная на составной с `answer` в списке (пункт 1).

    Вердикт: принято, правило 4.

17. Вопрос 3. Правило `_callHook`: наблюдатель, который в одиночку отдаёт
    брошенный `Cancelled` в зону, внутри составного должен отдавать его
    туда же, иначе обёртка меняет, куда идёт ошибка, вопреки dartdoc
    `SoloObserver` (`observer.dart:11-13`). Расхождение ядра и `solo` — вопрос
    отдельный.

    Вердикт: принято, правило `_callHook` через сам `_callHook` (пункт 4).

18. Вопрос 4. Оставить `MultiJobObserver` и `MultiSoloObserver`: приставка
    знакома по `MultiBlocProvider` и `MultiProvider`, в экспорте имена ни с чем
    не сталкиваются. Если что менять, то параметр `answer:` — `answering:`
    ближе к словарю «answers for».

    Вердикт: за владельцем, раздел «Открытый вопрос владельцу: имя».

19. Документы. Первая попытка в `observing.md` следует из словаря: `observer:`
    принимает одного, пять хуков устроены одинаково, цикл на все пять —
    механический результат. Трасса держится. Место после «Work the job does not
    wait for» верное: только там пример проходит через `onUnanswered`. Новые
    блоки станут `quoted[5]` и `quoted[6]`.

    Вердикт: принято, правок не требует.

## Ревью второй редакции

Независимый ревьюер на Opus, 2026-10-01, по копии дерева на `dc1f10e`: прототип
по дизайну — разделение в ядре, `_handleUnanswered` с проверкой
`is! JobAnswerer`, `JobObserver.all` двумя приватными классами,
`SoloObserver.all` с `callHook` в `lib/src/call_hook.dart`,
`_SoloJobObserver implements JobAnswerer` — и зонды. Копия восстановлена.

Что подтвердилось. Разделение задевает 12 тестовых классов в 8 файлах: восемь
не собираются (`Hearing`, `Answering`, `ErrorObserver`, `JobJournal`,
`Counting`, `ThrowingNotice`, `Forwarding`, `Plain`), четыре дают только
`override_on_non_overriding_member` (`Answer`, `EngineAnswer`,
`_ThrowingObserver`, `ThrowingAnswer`), и эти четыре без `with JobAnswerer`
краснят шесть тестов. С правкой наборы зелёные: `async_job` 929, `solo` 822,
`flutter_solo` 85, пример `flutter_solo` 4; анализ `solo` и `flutter_solo`
чист. Пол 3.6.0: `with JobObserver, JobAnswerer` с `super.onUnanswered`,
`extends JobObserver with JobAnswerer`, `extends Base with JobObserver`,
`implements JobAnswerer`, `SoloObserver.all` собираются и работают. Правила
1–8: порядок для `[a, b-отвечающий, c]` — `onStart`, `onLog`, `onError` всем,
`b onUnanswered`, `onFinish` всем; изоляция; две зоны —
`creation=[Bad state: callback] canceller=[]`; `ArgumentError` на двух
отвечающих, вложенном втором, `[a, a]`, `[a, all([a])]`, `[inner, inner]`,
`[c, all([c])]`; вложенный отвечающий отвечает; ленивый `Iterable` обходится
раз; копия списка; наследование; `Job.ignore`, `then(observer: all(...))`,
`each`, отвечающий прямо в `observer:`, `implements JobObserver` в списке.
`SoloObserver.all`: семь хуков по порядку, изоляция, `Cancelled` в зону, как
у одиночного, повтор с вложенным, копия, ленивый. Блокеров нет.

1. Нужно исправить. План документов не включает dartdoc ядра: после разделения
   `dart analyze` даёт 14 `comment_references` на `[JobObserver.onUnanswered]`
   и `[onUnanswered]`
   (`job_base.dart:232, 290, 299, 1078, 1102, 1253, 1275, 1284, 1641`;
   `job_context.dart:362, 535`; `observer.dart:14, 79`; `outcome.dart:145`),
   код выхода 0, гейт не поймает. `job_base.dart:299` советует ловушку:
   «override [JobObserver.onUnanswered] in the child's observer». Проза
   `job_context.dart:578`, `:790` и комментарий `job_stream.dart:50` описывают
   маршрут, неверный для наблюдателя без `JobAnswerer`.

   Вердикт: принято, раздел «Документы».

2. Нужно исправить. «Документы» не называют страниц `async_job`, где правка
   нужна по существу: `children.md:69-76` и `:451`; рецепт движка
   `extending.md:65-70` — ровно ловушка, его сторожа `Answer` и `EngineAnswer`
   без `with JobAnswerer` краснеют четырьмя тестами; `observing.md:306-308`
   о `Reporter`, у которого `onUnanswered` больше нет; переводы. Строка
   «упоминания `JobObserver.onUnanswered` на страницах `solo` и `flutter_solo`»
   адресована не туда: там только `Solo.onUnanswered`.

   Вердикт: принято, своей командой сверено (`children.md:76`,
   `extending.md:68-70`, `observing.md:306`); раздел «Документы».

3. Нужно исправить. Мутацию «составной всегда `JobAnswerer`» запланированные
   тесты не убивают: тело по умолчанию у такого составного отдаёт ошибку
   туда же, куда ядро, набор с зондами зелёный (944). Различает только
   `[Crashes(), JobObserver.all([Log()])]` — под мутацией `ArgumentError`.
   Нужен тест «составной без отвечающего рядом с отвечающим принимается,
   и отвечает тот» или `JobObserver.all([Log()]) is! JobAnswerer`.

   Вердикт: принято, раздел «Тесты», оба.

4. Нужно исправить. Тест на две зоны и мутация «`Zone.current` вместо тела
   по умолчанию» смотрят мимо составного: без отвечающего путь целиком в ядре.
   Мутацию тела `JobAnswerer` уже убивает «the default answer goes to the zone
   the job was created in» (`unanswered_test.dart`); мутацию ветки ядра для
   наблюдателя без `JobAnswerer` набор ловит случайно, по строке отладки
   `debug_test.dart`, а зонд с двумя зонами убивает:
   `creation=[] canceller=[Bad state: callback]`. Тест на две зоны нужен
   в «Ядре», с одиночным наблюдателем; мутацию «ядро спрашивает любого» после
   разделения не написать, её заменить на «наблюдатель без `JobAnswerer` —
   никуда».

   Вердикт: принято, разделы «Тесты» и мутации.

5. Нужно исправить. Принятая находка 8 первой редакции устарела: варианта
   на пять хуков нет. Первая попытка на четыре хука печатает дословно
   `quoted[4]` (`observing_rakes_test.dart:38-42`, `observing.md:300-304`):
   с `Crashes` то же, что без него, и проза должна это сказать. Второй
   самодельный исход для абзаца правил — пересыльщик `with JobAnswerer`,
   раздающий `onUnanswered` по `whereType<JobAnswerer>()`: со списком
   `[Reporter()]` ошибка пропадает, с двумя отвечающими отвечают оба. Вердикт 7
   тоже устарел.

   Вердикт: принято, раздел «Документы»; к вердиктам 7 и 8 первой редакции
   дописано.

6. Мелочь. Фразы `CHANGELOG.md`, ложные после разделения: `async_job` — «A
   class that implements `JobObserver` stops compiling until it has an
   `onUnanswered`» (у 0.2.0 ровно четыре хука, по исходникам 0.2.0 не ломается
   ничего), «an override of `onUnanswered` with an empty body keeps the old
   behaviour», последний абзац «Changes you will see on upgrade»; `solo` — «a
   class that implements `JobObserver` needs an `onUnanswered`»;
   `flutter_solo` — «the new `JobObserver.onUnanswered`».

   Вердикт: принято, своей командой сверено (`async_job/CHANGELOG.md:22`,
   `solo/CHANGELOG.md:221`, `flutter_solo/CHANGELOG.md:85`); раздел
   «Документы».

7. Мелочь. «`@override` … а его требует `annotate_overrides`» неточно: линт
   требует аннотацию только на том, что переопределяет, и на `onUnanswered` без
   `JobAnswerer` не требует ничего. Предупреждение будет там, где `@override`
   уже стоит: в перенесённом коде и скопированном со страницы. Зонд:
   `implements JobObserver` с `onUnanswered` без аннотации — диагностики нет.
   Подсказка анализатора к голому `with JobAnswerer` ведёт
   к `extends_non_class`; dartdoc должен показать оба написания.

   Вердикт: принято. Формулировка в «Что ломается» исправлена, оба написания —
   в разделе «Документы».

8. Мелочь. `Forwarding` (`unanswered_test.dart:211`) пересылает `onUnanswered`
   полю `JobObserver? inner` и требует проверки `inner is! JobAnswerer`;
   `Plain` (`:20`) зовёт `onUnanswered` руками (`:1725-1727`). Анализатор
   назовёт обоих ошибкой.

   Вердикт: принято, раздел «Тесты».

9. Мелочь. Тело дизайна разошлось с вердиктом 4 первой редакции, и причина
   не названа: фабрика в `SoloObserver` не видит приватный класс `solo.dart`.
   Вариант `callHook` в прототипе чист; есть и вариант без нового имени
   в `src` — сделать `observer.dart` частью `solo.dart`.

   Вердикт: принято, причина записана в разделе `solo`. Остаётся
   `call_hook.dart`: `part` меняет устройство библиотеки ради одной функции,
   а имя в `src` наружу не выходит.

10. Мелочь. Копии наблюдателей в `errors_rakes_test.dart` берут `lines`,
    `LoggingObserver` там нет: строку страницы с тремя наблюдателями сторож
    дословно не удержит.

    Вердикт: принято, раздел «Тесты».

11. Мелочь. Вердикты первой редакции ссылаются на её нумерацию правил,
    а вердикт 1 обещает `ArgumentError` там, где вторая редакция решила иначе.

    Вердикт: принято: под заголовком ревью первой редакции названо
    соответствие номеров, к вердикту 1 дописан итог.

12. Мелочь. В тестах `SoloObserver.all` нет ленивого `Iterable` и вложенного
    повтора.

    Вердикт: принято, раздел «Тесты».

13. Вопрос 1. Оставить `mixin JobAnswerer on JobObserver`: класс, который
    только отвечает, пишется `extends JobObserver with JobAnswerer` и ничего
    не теряет; у независимого интерфейса нет пути в задачу, пропали бы тело
    по умолчанию и `super.onUnanswered`. Такие классы есть: `Crashes` страницы,
    `Answer`, `EngineAnswer`.

    Вердикт: принято, остаётся `mixin ... on JobObserver`.

14. Вопрос 2. Предупреждения анализатора достаточно, у ядра поймать нечем;
    `@nonVirtual` на члене `JobObserver` запретил бы переопределение и миксину.
    Все четыре класса, названные предупреждением, краснели тестами. Остаточный
    риск — новый код без `@override`; его закрывают dartdoc `JobAnswerer`,
    `CHANGELOG` и то, что страница всегда показывает заголовок класса
    с `with JobAnswerer`.

    Вердикт: принято.

15. Вопрос 3. Сверх `_SoloJobObserver` разделение в `solo` и `flutter_solo`
    ничего не ломает: `JobObserver` там только в `solo.dart:106, 1240, 1243`;
    тесты и анализ чисты; остаются фразы `CHANGELOG` из находки 6.

    Вердикт: принято.

16. Вопрос 4. Место нового раздела верное; первая попытка следует из словаря;
    трасса держится. Ещё на `observing.md`: строка 51 о `with JobObserver` —
    дописать `with JobObserver, JobAnswerer`; строки 263-266 «An override of
    `onUnanswered` closes the second» — закрывает отвечающий; строки 306-308.
    Фрагмент 244-248 становится классом по образцу `Answering`
    (`observing_rakes_test.dart:78`).

    Вердикт: принято, раздел «Документы».
