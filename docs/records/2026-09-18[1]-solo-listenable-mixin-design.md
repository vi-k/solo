> **Состояние на 2026-09-18:** первая редакция, до ревью. Кода по ней нет;
> прототип собран и прогнан в изолированной копии дерева.
> **Что это:** `SoloListenable` из класса становится миксином
> `on Solo<S>`, как `SoloStream`; заодно аргумент типа у обоих миксинов
> в `with` пишется выводом.
> **Связанные записи:** `2026-09-15[14]-solo-stream-mixin-design.md`, `2026-09-16[3]-solo-stream-mixin-plan.md`, `2026-09-16[4]-solo-stream-mixin-work-review.md`, `2026-09-12[4]-listenable-on-base-report.md`, `2026-09-13[2]-solo-listeners-design.md`.

# `SoloListenable` становится миксином

Решение владельца 2026-09-16, запись в `docs/backlog.md`; взято в работу
2026-09-18. Второе решение владельца, 2026-09-18: **аргумент типа у миксинов
в `with` выводится, у обоих** — `with SoloListenable` и `with SoloStream`,
а уже написанные `with SoloStream<X>` переписываются той же волной.

## Зачем

Одно правило вместо двух: `Solo` — движок, доставки примешиваются. Сегодня
стрим — миксин, а лицо `ValueListenable` — класс, и читатель должен помнить,
что из них как пишется.

Второе — свободный слот `extends` у листа. Сегодня база приложения, которой
нужен `ValueListenable` на листе, обязана сама наследовать `SoloListenable`,
то есть жить во Flutter-пакете. Миксином лицо вешается на лист, а база остаётся
во Flutter-свободном пакете и наследует `Solo`.

Расхода, ради которого миксином стал стрим, здесь нет: полей у класса нет,
аллокаций тоже. Развилка «стрим XOR `ValueListenable`» снята ещё работой
`2026-09-15[14]-solo-stream-mixin-design.md`. Узкое место — чужие API, которые
хотят `Listenable`: `SoloBuilder`, `SoloSelectBuilder` и `SoloSelection.of`
берут `Solo<S>`, поэтому `SoloListenable` нужен ровно `ValueListenableBuilder`,
`ListenableBuilder`, `AnimatedBuilder` и `Listenable.merge`.

`mixin class` не подходит: суперкласс у него обязан быть `Object`.

## Что получается

```dart
// packages/flutter_solo/lib/src/solo_listenable.dart
mixin SoloListenable<S extends Object> on Solo<S>
    implements ValueListenable<S> {
  @override
  S get value => currentState;

  @override
  void onListenerError(Object error, StackTrace stackTrace) {
    /* тело нынешнего класса без единой правки */
  }
}
```

Конструктор уходит: у миксина его нет, а подклассы, звавшие
`super(initialState)`, достают конструктор `Solo` через применение миксина
и не меняются.

Формы на стороне пользователя:

```dart
// Тела и конструкторы опущены.
final class Profile extends Solo<ProfileState> with SoloListenable {}
final class Session extends Solo<SessionState>
    with SoloStream, SoloListenable {}              // обе доставки
final class Leaf extends AppController<LeafState>
    with SoloListenable {}                          // база без Flutter
final SoloListenable<ProfileState> profile;         // позиция типа
```

В позиции типа аргумент пишется явно, как и сегодня у `SoloStream<Session>`
в `doc/children.md`: вывод бывает только у применения миксина.

## Замеры

Изолированная копия дерева на `cbcf5ca` в скретчпаде, не рабочее дерево.

**Прототип.** Класс заменён миксином ровно как выше, восемь фикстур в четырёх
тестовых файлах и контроллер примера переведены в форму
`extends Solo<X> with SoloListenable`:

- `flutter analyze` в `packages/flutter_solo` — «No issues found», в том числе
  под `strict-raw-types`: вывод аргумента в `with` линт не считает сырым типом;
- `flutter test` — 89 из 89, как на `main`; пример анализируется чисто;
- `dart doc` — 0 предупреждений, 0 ошибок: `[currentState]` и `[value]`
  в дартдоке миксина резолвятся.

**Порядок в `with` для `SoloListenable` ничего не решает.** Оба порядка
с `SoloStream`, одна запись:

```
StreamFirst: [listener 1, after set, stream 1] isVL=true
ListenableFirst: [listener 1, after set, stream 1] isVL=true
```

Причина — миксин не переопределяет ни `publish`, ни `close`, поэтому
в линеаризации ему не с кем спорить. Правило из дартдока `SoloStream` («put
`SoloStream` first») остаётся единственным и в документах соблюдается:
`with SoloStream, SoloListenable`.

**База без Flutter.** Библиотека, импортирующая только `package:solo`,
объявляет `abstract class AppController<S extends Object> extends Solo<S>`;
лист `extends AppController<int> with SoloListenable` — вывод аргумента
работает и через обобщённую базу. Такой лист, поданный как
`SoloListenable<int>`, ведёт `ValueListenableBuilder` (текст меняется на `7`
после `set(7)`), и `Listenable.merge` его принимает.

**`onListenerError` миксина перекрывает переопределение базы.** Та же база
переопределяет `onListenerError` и пишет в свой журнал; слушатель листа
бросает:

```
Leaf: base log=[] reported=[flutter: Bad state: boom]
LeafOwn: base log=[leaf: Bad state: boom]
```

Миксин стоит в линеаризации над базой, поэтому его отчёт через `FlutterError`
побеждает, а отчёт базы молча не зовётся. Свой отчёт в листе (`LeafOwn`)
побеждает миксин — обычная семантика. Сегодня такой картины нет вовсе: база,
наследующая класс `SoloListenable`, стоит под листом и над классом, и её
переопределение побеждает. См. «Риски».

**Вывод у `SoloStream`.** В той же копии все `with SoloStream<X>` в тестах
`solo` (пять файлов, включая пару с `_Bomb<TestState>`) переписаны
на `with SoloStream`: `dart analyze lib test` чист, `dart test` — 581 плюс зонд
на обобщённый `class C<T extends Object> extends Solo<T> with SoloStream`,
читающий `stream` через поле `SoloStream<int>`.

## Что меняется в дереве

### Код

- `packages/flutter_solo/lib/src/solo_listenable.dart` — класс → миксин,
  конструктор снят. Дартдок переписывается по смыслу: «It is built on the
  engine itself, not on `SoloStream` … unless a subclass mixes `SoloStream` in»
  описывает класс; миксин говорит, на что он вешается, что порядок
  с `SoloStream` не важен и что его `onListenerError` перекрывает
  переопределение класса, к которому он подмешан.
- `packages/flutter_solo/lib/src/solo_selection.dart:180` — «a controller of a
  domain is a subclass of it» становится неправдой: подкласса у миксина нет,
  контроллер его подмешивает. Строки `:44` и `:48` остаются верными.
- Фикстуры, **восемь, а не семь**, как считала запись бэклога:
  `solo_selector_test.dart:13`; `solo_listenable_test.dart:7`, `:16`, `:22`
  (`_Both`, со стримом — становится `with SoloStream, SoloListenable`);
  `solo_selection_test.dart:22`, `:127`; `subscription_test.dart:6`, `:14`.
- `packages/flutter_solo/example/lib/main.dart:36`.
- `with SoloStream<X>` → `with SoloStream` в тестах `solo`:
  `test/support/test_solo.dart:27`, `hooks_test.dart:368`,
  `close_test.dart:281`, `closed_state_test.dart:294`,
  `solo_stream_test.dart:88`, `:98`, `:105`. В `:98` миксин стоит вторым —
  `with _Bomb<TestState>, SoloStream<TestState>`, — и регулярка
  `with SoloStream<` его не видит; приватный `_Bomb<TestState>` в тех же двух
  строках теряет аргумент тем же правилом. После правки `dart format` может
  свести две строки заголовка в одну — это его право.

В `lib/` ни одного `with SoloStream<` нет.

### Новые тесты `flutter_solo`

- **Оба порядка доставляют обе доставки.** Тест
  `'SoloListenable with SoloStream delivers both, on their own schedules'` идёт
  по двум фикстурам — `with SoloStream, SoloListenable` и обратной. Сторожит
  утверждение «порядок не важен» на случай, если миксин когда-нибудь
  переопределит `publish`: мутация «`publish` в миксине, бросающий после
  `super`» отбирает событие у стрима ровно в одном порядке.
- **Чей `onListenerError`.** База во Flutter-свободной библиотеке
  (`test/support/plain_base.dart`, импорт только `package:solo`) переопределяет
  `onListenerError`; лист с миксином сообщает через `FlutterError`, а база
  не слышит ничего; лист со своим переопределением побеждает миксин. Мутации:
  миксин зовёт `super.onListenerError` — база слышит, тест краснеет; миксин без
  `onListenerError` — отчёт уходит базе, краснеет.

Набор `flutter_solo` — от 89 до 91; `solo` не меняет счёт.

### Документы — по утверждениям

Список страниц — не задание; задание — что перестаёт быть правдой.

- **`packages/flutter_solo/README.md`**: первый абзац («`SoloListenable<S>` is
  a controller that owns a state…») — миксин не контроллер, а лицо контроллера;
  `:64` «the class this package is about»; фрагмент `:86`; `:180` «A controller
  built on `Solo` directly is not» — верно по смыслу, но «directly» теперь
  значит «без миксина»; `:294` «`SoloListenable` is not a `ChangeNotifier`» —
  остаётся.
- **`packages/solo/doc/flutter.md`**: `:3–5` «as the controller base class. It
  extends `Solo<S>` and implements `ValueListenable<S>`» — неправда целиком;
  фрагмент `:14`; раздел «A controller with both deliveries» — фрагмент `:126`
  и хвост «which a plain `SoloListenable` never did» (верен, остаётся).
  **Предложение:** короткий раздел о базе без Flutter — фрагмент
  `AppController` + лист `with SoloListenable` и одна фраза о том, чей
  `onListenerError` побеждает. Ради этого слота правка и делается, и нигде
  больше читатель о нём не узнает; `check_doc_shape.py` раздел пропустит — он
  открывается кодом.
- **`packages/solo/doc/state.md`**: строка таблицы `:108`
  `| SoloListenable<S> |` → `| Solo<S> with SoloListenable |`, строка `:107` →
  `| Solo<S> with SoloStream |`; абзац `:131–133` «it extends `Solo` directly …
  carries no stream of its own» — переписывается: он миксин, как `SoloStream`;
  фрагмент `Camera` `:192` — вывод. `:170` остаётся.
- **`packages/solo/doc/vs-bloc.md`**: строка таблицы `:43`
  `| Solo<S>, SoloListenable<S> |` — тип остаётся валидным, но строка соседней
  `| state, stream |` уже говорит «with `SoloStream` mixed in»; та же форма:
  `Solo<S>`, `ValueListenable` with `SoloListenable` mixed in. Фрагменты
  `:799`, `:1489` — вывод; их собирает стенд.
- **`packages/solo/README.md`**: фрагмент `:146` — вывод; `:152`, `:302`,
  `:322` остаются.
- **Русские копии всех перечисленных** — `packages/flutter_solo/README.ru.md`,
  `packages/solo/README.ru.md`, `docs/ru/solo/{flutter,state,vs-bloc}.md`.
  `check_translations.py` поймает разошедшийся код, прозу — нет.

### CHANGELOG

Только `## Unreleased`; выпущенные разделы — история.

- `packages/flutter_solo/CHANGELOG.md`: первая запись («follows `solo`'s rename
  … combines `SoloListenable` with `with SoloStream`») сворачивается с новой
  ломающей: `SoloListenable` — миксин; `extends SoloListenable<S>` становится
  `extends Solo<S> with SoloListenable`; прямое `SoloListenable<S>(value)`
  больше не компилируется — класс был конкретным; база, переопределившая
  `onListenerError`, теперь уступает миксину. Записи `:62`, `:78`, `:86`, `:93`
  описывают поведение, а не форму, и остаются.
- `packages/solo/CHANGELOG.md:3–20`: «`SoloListenable` is unaffected in shape
  -- it already extended the bare engine» — неправда; три
  `with SoloStream<S>`/`<T>` — вывод; миграция «a field or parameter typed
  `Solo<S>` … becomes `SoloStream<S>`» — позиция типа, остаётся явной.

### Записи и документы проекта

- `docs/architecture.md`: абзац «Контроллер» `:24–32` («`SoloListenable<S>` …
  наследует `Solo`») и карта модулей `:342–344`.
- `docs/conventions.md:51–53`: в список наследуемых баз без `base`/`final`
  добавить `SoloListenable` рядом с `SoloStream`.
- Шапка `2026-09-12[4]-listenable-on-base-report.md` — пересмотрено ещё раз.
- `docs/backlog.md` — запись удаляется тем же коммитом, что делает работу.
- `docs/handoff.md`.

Сайт генерируется из пакетов (`site/src/content/docs/` и `site/dist/` не под
гитом), править там нечего; сборка входит в проверки.

## Риски

**Перевёрнутое старшинство `onListenerError`.** Измерено выше. Сегодня
перекрыть отчёт `SoloListenable` из базы можно; после правки база уступает
листу, а переопределение нужно писать в самом листе. Пользователей нет, версия
`0.x`, но утверждение должно стоять в дартдоке миксина, в `CHANGELOG` и под
тестом, иначе это тихая смена поведения. Альтернатива «миксин зовёт `super`»
хуже: по умолчанию `Solo.onListenerError` отдаёт ошибку в зону, и каждая ошибка
слушателя уходила бы дважды.

**Тихо ломается проза, а не код.** В коде всё громко:
`extends SoloListenable<S>` — «Classes can only extend other classes», прямое
создание — ошибка аргументов. Ссылки `[SoloListenable]` в дартдоке продолжают
резолвиться, сменив смысл: слова «subclass of it», «base class», «extends
`Solo` directly» перечислены выше поимённо. Финальный проход — `grep`
по `SoloListenable` в живых артефактах, а не чек-лист: у миксина `SoloStream`
именно сквозной `grep` поймал то, что пропустил список.

**`state.md` делит строки с веткой `docs/state-rakes`.** Параллельная сессия
ведёт вычитку этой страницы; на её ветке те же три упоминания `SoloListenable`
стоят в строках 153, 190 и 229, текст совпадает с `main`. Правка в `main` — три
строки и абзац; перед коммитом —
`git merge-tree --write-tree main docs/state-rakes` против дерева с правкой:
конфликт виден до коммита, а не у соседа. Если он есть, правка `state.md` и его
перевода уходит отдельным последним коммитом, и владельцу называется место.

**Вывод аргумента — только в `with`.** Правило владельца про вывод
не распространяется на позицию типа: поле `SoloStream<Session>` без аргумента
было бы `SoloStream<Object>`, и `strict-raw-types` это ловит. Перевод формы —
механический `with SoloStream<\w+>` → `with SoloStream`; вне `with` регулярка
не срабатывает.

**Стенды.** Фрагменты `vs-bloc.md` с `with SoloStream<PlayerState>`
и `<ReportState>` собирает `tool/doc_snippets.py`; адресация блоков —
по разделу и объявленному имени (`tool/doc_blocks.py`), заголовок класса в ключ
не входит. Фрагменты `accumulation.md` стрима не читают и не затрагиваются —
там стенд ищет класс по точному заголовку. Проверяется прогоном обоих стендов.

## План

Два коммита, каждый зелёный сам по себе.

1. `refactor: infer the type argument of SoloStream in with` — все
   `with SoloStream<X>` в тестах `solo`, в `README`, `doc/state.md`,
   `doc/flutter.md`, `doc/vs-bloc.md`, их переводах и в `Unreleased`
   `CHANGELOG` ядра. Поведение не меняется; проверки — `dart analyze`,
   `dart test` в `solo`, оба стенда с `check_traces.py`,
   `check_translations.py`.
2. `feat(flutter_solo)!: SoloListenable becomes a mixin` — миксин, фикстуры,
   пример, два новых теста, документы и переводы из списка выше, записи
   `CHANGELOG`, `docs/architecture.md`, `docs/conventions.md`, шапка
   `2026-09-12[4]-listenable-on-base-report.md`, удаление записи
   из `docs/backlog.md`, `docs/handoff.md`. Перед коммитом — `merge-tree`
   против `docs/state-rakes` и сквозной `grep`.

Мутации для второго коммита — две на тест `onListenerError` и одна на тест
порядка, названы в разделе «Новые тесты». Каждая вносится копией файла
и откатывается копией, не `git checkout`.

## Критерии приёмки

**Форма.** `SoloListenable` объявлен `mixin SoloListenable<S extends Object> on
Solo<S> implements ValueListenable<S>`, без конструктора; тело `value`
и `onListenerError` не изменилось.

**Вывод.** В `with` ни в одном живом артефакте нет ни `SoloStream<`,
ни `SoloListenable<`: `grep -rnE "with .*Solo(Stream|Listenable)<"`
по `packages/`, `docs/ru/` и `tool/` пуст (без `.dart_tool`, `doc/api`,
выпущенных разделов `CHANGELOG`) — форма с `.*` ловит и миксин, стоящий
в `with` вторым. В позиции типа аргумент на месте.

**Фикстуры.** Восемь фикстур и пример переведены; `extends SoloListenable`
не встречается нигде.

**Тесты.** Тест обеих доставок идёт по обоим порядкам; тест `onListenerError`
стоит на базе из Flutter-свободной библиотеки и проверяет три случая: миксин
над переопределяющей базой, лист со своим переопределением, база не слышит.
Названные мутации краснят свои тесты.

**Проза.** Утверждения из раздела «Документы» переписаны по смыслу в обоих
языках; дартдок миксина называет старшинство `onListenerError` и то, что
порядок с `SoloStream` не важен; `CHANGELOG` `flutter_solo` называет миграцию
и старшинство; фраза «`SoloListenable` is unaffected in shape» из `CHANGELOG`
ядра ушла. Сквозной `grep` по `SoloListenable` пройден глазами.

**Проверки.** `dart analyze` без единого info в `async_job`, `solo`,
`solo/example`; `flutter analyze` в `flutter_solo` и его примере; `dart test` —
`solo` 581, `async_job` 430, пример 9; `flutter test` — `flutter_solo` 91;
`dart doc` без предупреждений в `solo` и `flutter_solo`; оба стенда
с `check_traces.py`; `check_translations.py`, `check_line_width.py`,
`check_doc_shape.py`, `reflow.py --check`, сборка сайта.

**Записи.** Запись бэклога удалена; `docs/architecture.md`,
`docs/conventions.md`, `docs/handoff.md` обновлены; шапка
`2026-09-12[4]-listenable-on-base-report.md` помечена.
