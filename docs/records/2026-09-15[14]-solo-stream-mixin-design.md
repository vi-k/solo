> **Состояние на 2026-09-16:** спека прошла два независимых ревью, принятое внесено; оба открытых вопроса решены владельцем 2026-09-16 — готова к плану.
> **Что это:** `SoloBase` переименовывается в `Solo`, а нынешний `Solo` становится миксином `SoloStream`.
> **Связанные записи:** `2026-09-15[15]-solo-stream-mixin-design-review.md`, `2026-09-15[16]-solo-stream-mixin-design-review-2.md`, `2026-09-13[2]-solo-listeners-design.md`, `2026-09-12[4]-listenable-on-base-report.md`, `2026-09-12[3]-current-state-rename-report.md`.

# Стрим переезжает в миксин, база забирает имя пакета

Решение владельца 2026-09-15: миксин, стрим в пакете остаётся.

## Зачем

`SoloBase` врёт именем. Суффикс `Base` означает «меня не наследуют, наследуют
моего конкретного потомка» — так у `BlocBase`. Здесь наоборот: базовый класс
и есть то, что наследуют, а потомок добавляет один геттер.

Счёт по живым артефактам. Множество — файлы `.dart` и `.md` в `packages/`
и `docs/ru/`, без `docs/records`, без `docs/handoff.md` и без генерируемого
`doc/api/**`; `tool/*.py` считается отдельно, потому что стенды компилируют
свой код в CI:

- `extends Solo<` — 74 вхождения, плюс 9 в `tool/` (8
  в `accumulation_snippets.py`, 1 в `doc_snippets.py`); `extends SoloBase<` —
  15;
- стрим у контроллера читают девять объявлений, а не восемь мест. Перечислены
  ниже поимённо: вне тестов и витрины потребителей нет,
  в `packages/solo/example` стрима нет вовсе;
- `Solo` держит `final _controller = StreamController<S>.broadcast()` —
  не лениво, на каждый экземпляр. Семьдесят четыре объявления платят за то,
  чего не трогает ни одно.

Иерархия уже проголосовала до этой спеки: `SoloListenable extends SoloBase`,
стрима у него нет, и это было отдельной ломающей правкой — отчёт
`2026-09-12[4]-listenable-on-base-report.md`.

Вторая причина — развилка. Сегодня `Solo` и `SoloListenable` братья, поэтому
иметь одновременно `stream` и `ValueListenable` нельзя. Миксин это снимает,
и довод «братья, а не цепочка» из `2026-09-12[4]` этой спекой отменяется: его
шапку надо пометить пересмотренной.

## Что получается

```dart
// lib/src/solo.dart  (сегодня solo_base.dart)
abstract class Solo<S extends Object> { /* движок, как сейчас */ }

// lib/src/solo_stream.dart  (сегодня solo.dart)
mixin SoloStream<S extends Object> on Solo<S> {
  final _controller = StreamController<S>.broadcast();
  Future<void>? _closed;

  /// Every state change, in order, delivered on the next microtask.
  Stream<S> get stream => _controller.stream;

  @override
  Future<void> close({SoloCloseMode mode = SoloCloseMode.cancel}) {
    /* тело нынешнего Solo.close без единой правки */
  }

  @override
  void publish(S previous, S current) {
    /* тело нынешнего Solo.publish без единой правки */
  }
}
```

Четыре формы на стороне пользователя:

```dart
final class Profile extends Solo<ProfileState> {}                      // без стрима
final class Feed extends Solo<FeedState> with SoloStream<FeedState> {}  // со стримом
final class Screen extends SoloListenable<S> with SoloStream<S> {}      // и то и другое
final SoloStream<Session> session;                                      // зависимость, которой нужен стрим
```

Третья сегодня невозможна. Четвёртая — не украшение: в `doc/children.md` один
контроллер держит другой полем `final Solo<Session> session` и читает его
стрим; после правки такое поле объявляется типом миксина, иначе стрима у него
нет.

## Замеры

Миксин написан против нынешней базы под её старым именем и запущен — механика
переносится дословно, ни одна строка `Solo` не потребовала правки. Оба ревьюера
воспроизвели это независимо и добавили попытки сломать:

- публикация кормит стрим, `currentState` впереди события;
- стрим закрывается после движка, порядок сохранён; `close()` дважды отдаёт
  ту же future;
- `close(mode: drain)` — состояния, изданные во время дренажа, доходят
  до стрима, `done` после `isFinished`; плоский `close()` поверх идущего
  дренажа — та же future, `done` один раз;
- повторный `close` изнутри `onFinish` и изнутри `observer.onClose` — та же
  future: мемоизация через `_closed` до `super.close()` работает;
- без подписчиков `close` завершается; приостановленная подписка держит
  `close`, как и сегодня;
- `@mustCallSuper` доходит сквозь миксин: класс, переопределивший
  `close`/`publish` без `super`, даёт четыре предупреждения анализатора — ровно
  как над сегодняшним классом;
- два миксина, оба переопределяющие `publish`, работают в обоих порядках: оба
  канала живы. **Взаимного порядка этот замер не показывает** — стрим
  доставляет на микротаске, а сосед синхронно, поэтому в выводе он не виден.
  Что порядок решает, показывает замер ниже, в рисках.

Комбинация, ради которой миксин и выбран, проверена в `flutter_solo`:
`class Both extends SoloListenable<int> with SoloStream<int>` компилируется,
остаётся `ValueListenable<int>`, и обе доставки живы — слушатель получает
значение внутри изменения, стрим на микротаске. `ValueListenableBuilder`,
`StreamBuilder`, `SoloBuilder`, `SoloSelectBuilder`, `SoloSelector`
и `SoloSelection` над таким контроллером работают.

У комбинации есть цена, и она идёт в дартдок: два маршрута ошибок в одном
контроллере (слушатель — в `FlutterError`, подписчик стрима — в зону), две
перестройки на одно изменение при двух подписках, и `await close()` теперь ждёт
подписчиков стрима, чего у чистого `SoloListenable` не было.

## Что меняется в дереве

**Переименование файлов — пять шагов, не два.** Двух `git mv` не хватает,
дерево не собирается:

1. `src/solo.dart` → `src/solo_stream.dart`, класс становится миксином;
2. `src/solo_base.dart` → `src/solo.dart`, класс `SoloBase` → `Solo`;
3. `part of 'solo_base.dart'` → `part of 'solo.dart'` в пяти частях:
   `job.dart`, `job_context.dart`, `queue.dart`, `accumulator.dart`,
   `accumulation_timing.dart`;
4. `import 'solo_base.dart'` → `import 'solo.dart'` в `observer.dart`
   и `solo_cancel_reason.dart`;
5. в `lib/solo.dart` убрать `export 'src/solo_base.dart'` и поставить
   `export 'src/solo_stream.dart'` **после** `src/solo_cancel_reason.dart`:
   линт `directives_ordering` требует алфавита, а `dart analyze` по правилам
   проекта должен быть чист.

Переименование задевает одиннадцать файлов в `lib/src`, а не девять:
`queue.dart` и `accumulation_timing.dart` имени `SoloBase` не содержат,
но содержат `part of`.

**Девять объявлений, которым нужен миксин.** Это они, а не «места чтения»:

- `TestSolo` — общая фикстура набора, `test/support/test_solo.dart`. **Миксин
  ей не даётся:** иначе стрим получают десятки тестов, которым он не нужен,
  и набор перестаёт проверять базу в той форме, в какой её видит пользователь.
  Стримовые тесты получают отдельную фикстуру, `runSolo` — вариант под неё;
- `_ExposedStreamSolo`, `_ThrowingChange`, `_Reentrant` — приватные фикстуры
  в `closed_state_test.dart`, `hooks_test.dart`, `close_test.dart`;
- `ProfileController` в `packages/solo/README.md` и `camera` в `doc/state.md`;
- поле `final Solo<Session> session` в `doc/children.md` — становится
  `SoloStream<Session>`, четвёртая форма;
- `PlayerController` и `ReportController` в `doc/vs-bloc.md`: **фрагменты
  получают `with SoloStream`**, драйвер `tool/doc_snippets.py` остаётся
  на `.stream`. Страница сравнивает формы, и показать настоящую форму честнее,
  чем обойти её; вдобавок так миксин попадает под стенд — единственное место,
  где код этой правки проверяется автоматически.

Фрагменты `accumulation.md` стрим не читают и остаются `extends Solo<`. Это
важно: `tool/accumulation_snippets.py` заменяет их по точному заголовку класса
(`:768`, `:1257`), и добавленный `with SoloStream` молча перестал бы совпадать,
а стенд собрал бы два класса с одним именем.

**`tool/doc_snippets.py`** правится и сам: `:1806` ставит `SoloBase.observer`.

**Остальная рукописная поверхность:**

- `packages/solo/test` — восемнадцать файлов; `solo_base_test.dart`
  переименовывается, и его тест
  `'a SoloBase subclass without a stream compiles and reads state'` получает
  имя по тому, что проверяет: без стрима теперь каждый подкласс;
- `packages/flutter_solo/lib/src` — четыре файла, `test` — три. Два теста
  требуют не замены имени, а пересмотра посылки: `solo_builder_test.dart:37`
  объявляет `_StreamController extends Solo<_Screen>` с комментарием «has a
  `stream` and is no `ValueListenable`», а тест зовётся
  `'takes a plain Solo, which no ValueListenableBuilder would'`. После правки
  он компилируется и зеленеет, потеряв предмет. То же
  у `solo_selection_test.dart:28`;
- `packages/async_job/lib/src/job_base.dart:315` и `:888` — дартдок нижнего
  пакета называет `SoloBase.debug` и `SoloBase.errorHandler`. Правится: все три
  пакета идут на `0.3.0` одной волной;
- `docs/architecture.md` — пять мест: 25–26, 113, 267, 303, 310, и абзац 27–30
  («братья, а не цепочка») отменяется по сути;
- `docs/conventions.md:51`, `docs/handoff.md`.

**Документы — по утверждениям, а не по именам файлов.** Список страниц —
не задание; задание — что именно перестаёт быть правдой:

- **`state.md`:** таблица трёх типов; «`SoloListenable` is a sibling of `Solo`,
  not a subclass … carries no stream at all» — после миксина он и наследник,
  и может нести стрим; `Logged extends SoloBase<S>`; «`Solo` is this override
  with a broadcast `StreamController` behind it»; `Camera` нуждается в миксине,
  потому что его стрим читают. Раздел «A delivery of your own» учит
  переопределять `publish` в подклассе — пакет теперь возит то же миксином,
  и форма примера пересматривается;
- **`errors.md`, `testing.md`:** сигнатуры наблюдателя
  `onStart(SoloBase<Object> …)` и `SoloBase.observer/errorHandler/debug` —
  одиннадцать и несколько мест, замена имени;
- **`flutter.md`:** «a `Solo` with its stream, or a `SoloBase` of your own»
  переворачивается целиком;
- **`vs-bloc.md`:** строки таблицы `| state, stream | currentState, stream |` —
  стрим стал opt-in, и сравнение с Bloc это должно сказать;
- **`children.md`:** поле-зависимость, четвёртая форма;
- **README обоих пакетов:** у `solo` — первый пример и абзац про
  `profile.stream`; у `flutter_solo` — «There is no `stream` on this
  controller: it is a `SoloBase`, not a `Solo`» и соседние фразы;
- **русские копии всех перечисленных** — построчно. `check_translations.py`
  сверяет заголовки, число блоков и некомментарные строки кода: односторонний
  `with SoloStream` в английском фрагменте он поймает, прозу — нет.

**CHANGELOG.** Нерелизные разделы обоих пакетов сверяются и переписываются под
новые имена: восемь упоминаний в `Unreleased` у `solo`, семь у `flutter_solo`.
Одна запись не переименовывается, а сворачивается в новую —
`flutter_solo/CHANGELOG.md:69–75` утверждает «A controller no longer fits where
a `Solo<S>` is expected; `SoloBase<S>` is the type that covers both», и правка
выворачивает это наизнанку. **Выпущенные разделы не трогаются:** пять
упоминаний `SoloBase` в `## 0.2.0` у `solo` — это история.

**Версии и порядок выпуска.** Оба пакета на 0.2.0, во `flutter_solo` стоит
`solo: ^0.2.0`. Правка ломающая для обоих, поэтому `solo` выпускается первым,
пол во `flutter_solo` поднимается до `^0.3.0`, оверрайды разработки живут
до обоих релизов.

**Алиаса нет.** `typedef SoloBase<S> = Solo<S>` с `@Deprecated` оставил бы
чужой код компилирующимся один релиз, но пользователей нет и версия `0.x`:
алиас пережил бы правку только затем, чтобы его выпиливали отдельным релизом.

`doc/api/**` под гитом не лежит — он в `.gitignore`, и `dart doc` в гейте
не запускается. Перегенерировать нечего.

Стенды `vs-bloc.md` и `accumulation.md` компилируют свои фрагменты в CI,
поэтому ошибку в примерах этих двух страниц поймает гейт. У остальных страниц
такой защиты нет.

## Риски

**Тихо ломается проза, а не код.** Я считал главным риском тихую потерю
`.stream` у 74 объявлений. Это неверно: в коде любое чтение `.stream` после
правки — ошибка компиляции, и все двенадцать вызовов в дереве ловятся. Тихой
остаётся проза, потому что ссылки на **`Solo`** продолжат резолвиться, сменив
смысл с «класс со стримом» на «база»: `solo_base.dart:22` («see `Solo` for a
stream» — станет отсылкой к самому себе), `solo_listenable.dart:8` («built on
the engine itself, not on [Solo]» — при объявлении `extends Solo` двумя
строками ниже), `doc/state.md:131`, `:168`, `doc/flutter.md:97`,
`flutter_solo/README.md:181`, `:392`, `docs/architecture.md:113`,
`vs-bloc.md:43`, `:49`. Поэтому в поверхность входит проход по слову `Solo`,
а не только по `SoloBase`.

Сюда же — дартдок базы `solo_base.dart:21–22` «Subclasses add a delivery
channel through [publish]»: он устарел ещё 2026-09-13, когда слушатели
переехали в базу, и переписывается по смыслу при любом исходе открытого
вопроса.

И сюда же — сторожа, потерявшие предмет, но не цвет: два теста `flutter_solo`,
названных выше.

**Порядок в `with` решает, чьей доставке стоит ошибка соседа.** Замерено
миксином, чей `publish` бросает после `super`:

```
SoloStream, Bomb: thrown Bad state: bomb, stream [1]
Bomb, SoloStream: thrown Bad state: bomb, stream []
bomb inside a job: outcome Failed(Bad state: bomb), stream [], state 9
                   // keepWhile: s < 5 не перепроверен
```

Механика та же, что сегодня у подкласса, и `state.md` уже требует «A failure
must not leave `publish`». Но раньше порядок задавала иерархия и стрим стоял
ближе всех к базе; теперь одна перестановка в `with` отбирает у стрима событие,
а у работающей задачи — перепроверку правил. Это идёт в дартдок `SoloStream`
и под тест.

**Инстанцируемость.** Открытый вопрос ниже.

## Открытый вопрос 1: `Solo` абстрактный или нет

`SoloBase` сегодня `abstract`, а `Solo` — нет, и тесты инстанцируют
`Solo<int>(0)` тридцать раз. После переименования инстанцируемого контроллера
в ядре не остаётся вовсе. Абстрактных членов у базы нет: `abstract` здесь
только запрет на прямое создание.

Что выяснило ревью и чего в спеке не было:

- все тридцать прямых созданий — в `packages/solo/test`, в четырёх файлах.
  В документации, примере, `tool/` и `flutter_solo` их **ноль**. Мой довод «это
  живая возможность» держался на тестах и ни на чём больше;
- `externalSetState` защищён, поэтому голый `Solo<int>(0)` вне тестов двигают
  только `run`/`add` снаружи — ровно та форма, против которой написан
  `vs-bloc.md`;
- зато с 2026-09-13 слушатели живут в базе, поэтому голый `Solo<int>(0)` — уже
  не «движок без канала», а рабочий контроллер с `addListener`;
- `SoloListenable` — конкретный класс. При сохранённом `abstract` единственный
  инстанцируемый публичный контроллер окажется во `flutter_solo`, а в ядре
  ни одного.

Четыре варианта:

1. **снять `abstract`** — `class Solo`, тридцать мест не трогаются;
2. **оставить `abstract`** — фикстура
   `PlainSolo<S extends Object> extends Solo<S>` в `test/support/`, тридцать
   мест переписываются;
3. **оставить `abstract`, а тестам дать именованное применение миксина:**
   `final class StreamSolo<S extends Object> = Solo<S> with SoloStream<S>;` —
   одна строка на все `S`, без тела; закрывает и фикстуру, и стримовые тесты;
4. **`base class Solo`** — инстанцируемый и наследуемый,
   но не `implements`-уемый; движок с приватными инвариантами под интерфейсный
   мок и так не годится.

Механике всё равно: миксин собрался и против абстрактной базы.

**Решение владельца 2026-09-16: вариант 2, без алиаса.** `abstract` остаётся;
тестам заводится одна фикстура `PlainSolo<S extends Object> extends Solo<S> {}`
в `test/support/`, без стримового варианта. Вариант 3 (алиас `StreamSolo`)
предлагался и снят в том же разговоре: во-первых, `SoloStream`/`StreamSolo`
различаются только порядком слов — плохая пара имён для публичного API;
во-вторых, опора под ним не подтвердилась — проверены все тридцать мест прямого
создания в `packages/solo/test`, и **ни одно не читает `.stream`**;
единственное соседство `.stream` с похожим кодом в `hooks_test.dart:250` стоит
на `_ThrowingChange()`, отдельной именованной фикстуре, которая и так в списке
девяти объявлений, получающих миксин руками. Вариант 4 (`base class Solo`)
отклонён отдельно: измерено, что требование Dart «наследник `base`-класса сам
должен быть `base`/`final`/`sealed`» действует не только внутри пакета,
а на любой подкласс где угодно — цена ложится на каждого пользователя,
наследующего `Solo` в своём коде, ради риска (`implements Solo`), которого
никто не наблюдал.

## Открытый вопрос 2: чем открывается README

Первый пример `packages/solo/README.md` —
`ProfileController extends Solo<ProfileState>`, и через сорок строк
`profile.stream.listen`. После правки витрина пакета либо открывается формой
`with SoloStream`, либо переходит на `addListener` и показывает стрим ниже как
опцию.

Это выбор лица пакета, а не механическая замена, и он же решает, как выглядит
правая колонка таблицы в `vs-bloc.md`, где `solo` сравнивается с Bloc. Решения
не принимаю.

**Решение владельца 2026-09-16: `addListener`.** Первый пример открывается
голым `addListener`/`currentState`, без стрима; `SoloStream` появляется ниже
как форма для тех, кому он нужен. Довод: `addListener` живёт в `SoloBase` уже
с 2026-09-13, до этой спеки, и работает на голом `Solo` без всякого миксина —
витрина не обязана открываться самой дорогой формой, когда рефакторинг ровно
о том, что она нужна не всем. Строка `vs-bloc.md`
`| state, stream | currentState, stream |` переписывается заодно, тем же
критерием.

## Критерии приёмки

**Имя.** `SoloBase` не встречается в коде, дартдоке, документации и нерелизных
разделах CHANGELOG всех трёх пакетов, включая `async_job`. Выпущенные разделы
CHANGELOG не тронуты. Имя `solo_base_test.dart` и имя его теста пересмотрены.

**Формы.** Все четыре формы существуют и проверены. `Solo` остаётся `abstract`
(решение владельца 2026-09-16), поэтому первая форма проверяется
не инстанцированием, а объявлением подкласса — фикстурой
`PlainSolo<S extends Object> extends Solo<S> {}` в `test/support/`, которая
заменяет собой прямое создание на всех тридцати местах. Остальные три — как
были: `extends Solo with SoloStream`, `extends SoloListenable with SoloStream`
(тест в `flutter_solo`, обе доставки живы), `SoloStream<S>` в позиции типа.

**Механика.** Под тестами в `solo`: стрим закрывается после движка; повторный
`close` отдаёт ту же future; сосед по `with`, не зовущий `super.publish`,
глушит стрим, стоя над `SoloStream`, и не глушит, стоя под ним.

**Перевод.** Девять объявлений получили миксин. Отчёт о работе перечисляет
по файлам все просмотренные вхождения `extends Solo` с пометкой, почему стриму
там не место, — отдельно от тех, где посылка теста утверждала наличие стрима
(`solo_builder_test.dart`, `solo_selection_test.dart`).

**Проза.** Пройдено слово `Solo`, а не только `SoloBase`: перечисленные
в рисках дартдоки и строки страниц переписаны по смыслу. Дартдок `SoloStream`
называет правило порядка в `with` и цену ошибки соседа; `flutter.md` называет
цену комбинации.

**Версии.** `solo` 0.3.0 выпускается первым, `flutter_solo` поднимает пол
до `solo: ^0.3.0`, оверрайды на месте.

**Проверки.** `dart analyze` без единого info во всех пакетах и примерах;
`dart doc` без предупреждений о нерезолвящихся ссылках; оба стенда зелёные
вместе с `check_traces.py`; `check_translations.py`, `check_line_width.py`,
`check_doc_shape.py`, `reflow --check`, сборка сайта. Наборы: `solo` от 577,
`async_job` 388, пример 9, `flutter_solo` от 87, плюс названные выше новые
тесты.

**Записи.** Шапка `2026-09-12[4]-listenable-on-base-report.md` помечена
пересмотренной; `docs/architecture.md` и `docs/handoff.md` обновлены.
