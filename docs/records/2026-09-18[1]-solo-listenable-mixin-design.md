> **Состояние на 2026-09-18:** сделано и смержено в `main` двумя коммитами:
> шаг 1 — `018db09`, шаг 2 — `feat(flutter_solo)!: SoloListenable becomes
> a mixin` следом за ним; не запушено. Вторая редакция прошла после круга
> ревью (два ревьюера Opus, оба — «годится с правками», все находки приняты,
> две — частично). При работе поправлены однострочник миграции в `CHANGELOG`
> ядра и раздел «План», который склеил `reflow.py`; критерий «Вывод» смягчён:
> единственное совпадение `grep` — проза `CHANGELOG`, где перенос свёл
> на одну строку два код-спана, а не позиция типа; тест 3 назван
> `'…reports over an onListenerError of the base'` — без апострофа, ради
> одинарных кавычек. Круг ревью работы пройден: два ревьюера Opus, оба —
> «годится с правками», записи
> `2026-09-18[4]-solo-listenable-mixin-work-review.md`
> и `2026-09-18[5]-solo-listenable-mixin-work-review-2.md`; находки закрыты
> коммитом `fix: close the SoloListenable mixin work review`.
> **Что это:** `SoloListenable` из класса становится миксином
> `on Solo<S>`, как `SoloStream`; заодно аргумент типа у обоих миксинов
> в `with` пишется выводом.
> **Связанные записи:** `2026-09-18[2]-solo-listenable-mixin-design-review.md`, `2026-09-18[3]-solo-listenable-mixin-design-review-2.md`, `2026-09-15[14]-solo-stream-mixin-design.md`, `2026-09-16[3]-solo-stream-mixin-plan.md`, `2026-09-16[4]-solo-stream-mixin-work-review.md`, `2026-09-12[4]-listenable-on-base-report.md`, `2026-09-13[2]-solo-listeners-design.md`.

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
`2026-09-15[14]-solo-stream-mixin-design.md`. `SoloBuilder`,
`SoloSelectBuilder` и `SoloSelection.of` берут `Solo<S>`, поэтому
`SoloListenable` нужен тем API, которые хотят `ValueListenable` или
`Listenable`: чужим — `ValueListenableBuilder`, `ListenableBuilder`,
`AnimatedBuilder`, `Listenable.merge` — и своим: `SoloSelector`, конструктору
`SoloSelection`, расширениям `select` и `listen`.

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

**В позиции типа аргумент пишется явно**, как и сегодня у `SoloStream<Session>`
в `doc/children.md`: вывод бывает только у применения миксина. Анализатор этого
не требует — см. «Риски».

## Замеры

Изолированная копия дерева на `cbcf5ca` в скретчпаде, не рабочее дерево. Оба
ревьюера воспроизвели всё ниже в своих копиях независимо.

**Прототип.** Класс заменён миксином ровно как выше, восемь фикстур в четырёх
тестовых файлах и контроллер примера переведены в форму
`extends Solo<X> with SoloListenable`:

- `flutter analyze` в `packages/flutter_solo` — «No issues found», в том числе
  под `strict-raw-types`, `prefer_mixin`, `public_member_api_docs`
  и `comment_references`;
- `flutter test` — 89 из 89, как на `main`; пример анализируется чисто;
- `dart doc` — 0 предупреждений, 0 ошибок: `[currentState]` и `[value]`
  в дартдоке миксина резолвятся; `dart format` в `flutter_solo` ничего
  не меняет.

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
после `set(7)`), и `Listenable.merge` его принимает. Моки `implements Leaf`
и `implements SoloListenable<int>` компилируются, `is SoloListenable<int>`
истинно.

**Старшинство `onListenerError`.** Три раскладки, база переопределяет
`onListenerError` и пишет в свой журнал, слушатель бросает:

```
Leaf: base log=[] reported=[flutter: Bad state: boom]
LeafOwn: base log=[leaf: Bad state: boom]
Migrated: base=[base: Bad state: boom] flutter=[]
```

- `Leaf` — миксин на листе под базой без Flutter. Миксин стоит в линеаризации
  над базой, и его отчёт через `FlutterError` побеждает. **Это новая раскладка:
  до правки её не было.**
- `LeafOwn` — у листа своё переопределение, оно побеждает миксин. Обычная
  семантика Dart. `super.onListenerError` из листа приходит в миксин,
  а не в базу: реализация базы под миксином недостижима через `super`.
- `Migrated` — механическая миграция сегодняшнего `extends SoloListenable<S>`:
  база `extends Solo<S> with SoloListenable` и переопределяет в своём теле.
  Тело класса стоит под миксином, который сам подмешивает, и база побеждает,
  как сегодня. **Миграция старшинства не меняет.**

Вариант «миксин зовёт `super`» хуже: по умолчанию `Solo.onListenerError` отдаёт
ошибку в зону, и каждая ошибка слушателя уходила бы дважды. Мутация это
показывает: краснеют три существующих теста.

**Вывод у `SoloStream`.** В той же копии все `with SoloStream<X>` в тестах
`solo` (пять файлов, семь объявлений, включая пару с `_Bomb<TestState>`)
переписаны на `with SoloStream`: `dart analyze lib test` чист, `dart test` —
581 плюс зонд на обобщённый
`class C<T extends Object> extends Solo<T> with SoloStream`, читающий `stream`
через поле `SoloStream<int>`. Форма
`_Both extends SoloListenable<int> with SoloStream` — при `SoloListenable` ещё
классом — тоже собирается: аргумент выводится из суперкласса. Оба стенда
с фрагментами `vs-bloc.md` в форме `with SoloStream` зелёные у обоих ревьюеров:
27 драйверов, `check_traces.py` без пропусков.

**Ветка `docs/state-rakes`.** Трёхсторонний `git merge-file` правок обоих
коммитов в `state.md` и его переводе против ветки — 0 конфликтов, у меня
и у обоих ревьюеров.

## Что меняется в дереве

### Код

- `packages/flutter_solo/lib/src/solo_listenable.dart` — класс → миксин,
  конструктор снят. Дартдок переписывается по смыслу: нынешний («built on the
  engine itself, not on `SoloStream` … unless a subclass mixes `SoloStream`
  in») описывает класс. Миксин говорит: во что он подмешивается
  (`extends Solo<Profile> with SoloListenable`); что стрима нет, пока
  не подмешан `SoloStream`, и порядок с ним не важен, хотя документы пишут
  `with SoloStream, SoloListenable`; правило `onListenerError` — побеждает
  переопределение выше по цепочке (выше — более производный класс, как
  в правиле `SoloStream`), миксин на листе перекрывает базу, база под ним
  недостижима через `super`, и база, которой нужен свой отчёт, держит его
  в методе под другим именем, а лист зовёт его из своего переопределения; что
  в позиции типа аргумент пишется явно.
- `packages/flutter_solo/lib/src/solo_selection.dart:180–185` — абзац
  переписывается целиком: «subclass» стоит в нём четыре раза, а подкласса
  у миксина нет — контроллер его подмешивает. Строки `:44` и `:48` остаются
  верными.
- `packages/solo/lib/src/solo.dart:190–194`, дартдок `onListenerError` — одна
  фраза: подмешанный выше по цепочке миксин (`SoloListenable` пакета
  `flutter_solo`) перекрывает переопределение базы.
- Фикстуры, **восемь, а не семь**, как считала запись бэклога:
  `solo_selector_test.dart:13`; `solo_listenable_test.dart:7`, `:16`, `:22`
  (`_Both` — становится `extends Solo<int> with SoloStream, SoloListenable`);
  `solo_selection_test.dart:22`, `:127`; `subscription_test.dart:6`, `:14`.
- `packages/flutter_solo/example/lib/main.dart:36`.
- `with SoloStream<X>` → `with SoloStream` в тестах `solo`:
  `test/support/test_solo.dart:27`, `hooks_test.dart:368`,
  `close_test.dart:281`, `closed_state_test.dart:294`,
  `solo_stream_test.dart:88`, `:98`, `:105`. В `:98` миксин стоит вторым —
  `with _Bomb<TestState>, SoloStream<TestState>`; приватный `_Bomb<TestState>`
  в двух строках теряет аргумент тем же правилом. После правки — `dart format`:
  он сводит заголовки `closed_state_test.dart` и `solo_stream_test.dart` в одну
  строку, и CI (`gate.yml:101–102`) требует этого.

В `lib/` ни одного `with SoloStream<` нет.

### Новые тесты

По одному на сценарий, как велит `docs/conventions.md`. Отличающих мутаций
у них нет, и это измерено обоими ревьюерами: каждую мыслимую мутацию
библиотеки, которую они ловят, ловит и нынешний набор. Поэтому они — запись
обещаний документов, а не новые стражи механики.

`packages/flutter_solo/test/support/plain_base.dart` — библиотека с импортом
только `package:solo/solo.dart`: `AppController<S>` повторяет фрагмент нового
раздела `flutter.md`, `ReportingBase<S>` переопределяет `onListenerError`
и пишет в журнал.

В `packages/flutter_solo/test/solo_listenable_test.dart`, 89 → 93, а после
круга ревью работы 94: тесты 3 и 4 получили контроль своей предпосылки,
и добавлен страж импорта —
`'the bases of these tests import nothing of Flutter'` (вердикт первой находки
`2026-09-18[4]-solo-listenable-mixin-work-review.md`):

1. `'SoloListenable ahead of SoloStream in with delivers both too'` — обратный
   порядок, фикстура `with SoloListenable, SoloStream`. Демонстрация
   утверждения «порядок не важен». Мутация «`publish` в миксине зовёт `super`
   дважды» краснит существующий тест с прямым порядком (`[1, 1]`), а этот
   оставляет зелёным; мутация с броском роняет оба порядка раньше, чем они
   доходят до стрима.
2. `'a leaf over a base without Flutter drives ValueListenableBuilder and
   Listenable.merge'` — лист над `AppController` ведёт `ValueListenableBuilder`
   и `Listenable.merge`. Держит правду фрагмента `flutter.md`.
3. `'SoloListenable on the leaf reports over an onListenerError of the base'` —
   лист над `ReportingBase`: отчёт уходит в `FlutterError`, журнал базы пуст.
   Мутации «миксин зовёт `super.onListenerError`» и «миксин без
   `onListenerError`» краснят его вместе с тремя существующими тестами
   (`a throwing listener is reported and the rest still hear`,
   `a throwing listener does not hold back the rules`,
   `a throwing selector is reported and changes nothing else`).
4. `'a base that mixes SoloListenable in keeps its own onListenerError'` —
   мигрированная форма: база во Flutter `extends Solo<S> with SoloListenable`
   со своим переопределением побеждает. Запись обещания `CHANGELOG` «миграция
   старшинства не меняет»; мутации библиотеки его не сломают — это семантика
   Dart.

Случай «лист со своим переопределением побеждает миксин» в тест не идёт: он
ничего не сторожит. Правило стоит в дартдоке и в `flutter.md`.

В `packages/solo/test/solo_stream_test.dart`, 581 → 582:

5. `'a generic controller takes SoloStream by inference'` — фикстура и есть
   однострочник миграции из `CHANGELOG` ядра,
   `final class _Generic<T extends Object> = Solo<T> with SoloStream;`; стрим
   читается через поле `SoloStream<int>`, состояние меняет задача.

### Документы — по утверждениям

Список страниц — не задание; задание — что перестаёт быть правдой. Каждое место
с переводом.

- **`packages/solo/README.md:10–11`**: «`flutter_solo` adds a controller that
  implements `ValueListenable`» — пакет добавляет миксин. Фрагмент `:145–146` —
  вывод, заголовок сводится в строку. `:152`, `:302`, `:322` остаются.
- **`packages/flutter_solo/README.md`**: первый абзац («`SoloListenable<S>` is
  a controller that owns a state…») — миксин не контроллер, а лицо контроллера;
  `:64` «the class this package is about»; фрагмент `:86`; `:180–182` — «a
  controller built on `Solo` directly is not» и перечень, где «the base class
  of some other package» стоит среди контроллеров без `ValueListenable`: такая
  база теперь получает лицо на листе; `:382`, таблица Notes, «it extends `Solo`
  directly, with no `SoloStream` mixed in» — стрима нет, пока не подмешан
  `SoloStream`. `:294` остаётся.
- **`packages/solo/doc/flutter.md`**: `:3–5` «as the controller base class. It
  extends `Solo<S>` and implements `ValueListenable<S>`» — неправда целиком;
  фрагмент `:14`; раздел «A controller with both deliveries» — фрагмент
  `:126–127` становится
  `extends Solo<SessionState> with SoloStream, SoloListenable`, хвост «which a
  plain `SoloListenable` never did» остаётся.
- **Новый раздел `flutter.md`, «A base class without Flutter»** — входит
  в работу. Открывается фрагментом: база `AppController<S> extends Solo<S>`
  в пакете без Flutter и лист
  `extends AppController<ProfileState> with SoloListenable`. Дальше — правило
  `onListenerError` для этой раскладки и рецепт: база, которой нужен свой
  отчёт, держит его в методе под другим именем, а лист зовёт его из своего
  `onListenerError`. Правду фрагмента держит тест 2 — `plain_base.dart`
  повторяет его базу.
- **`packages/solo/doc/state.md`**: строка таблицы `:107` →
  `| Solo<S> with SoloStream |`, `:108` → `| Solo<S> with SoloListenable |`;
  абзац `:131–133` «it extends `Solo` directly … carries no stream of its own»
  — он миксин, как `SoloStream`, и контроллер с обоими подмешивает оба;
  фрагмент `Camera` `:192` — вывод. `:124–127` («unless a subclass says
  otherwise») и `:170` остаются: первое верно и для миксина на листе, класс,
  куда он подмешан, и есть тот подкласс, а абзац переписан на ветке
  `docs/state-rakes`.
- **`packages/solo/doc/vs-bloc.md`**: строка таблицы `:43`
  `| Solo<S>, SoloListenable<S> |` — в форму соседней строки
  `| state, stream |`: `Solo<S>`; `ValueListenable` with `SoloListenable` mixed
  in. Фрагменты `:798–799`, `:1488–1489` — вывод, заголовки сводятся в строку;
  их собирает стенд.
- **Заголовки фрагментов** после вывода сводятся туда, куда свёл бы
  `dart format`: `docs/conventions.md` отдаёт ширину кода ему.
- **Русские копии всех перечисленных** — `packages/solo/README.ru.md`,
  `packages/flutter_solo/README.ru.md`,
  `docs/ru/solo/{flutter,state,vs-bloc}.md`. `check_translations.py` поймает
  разошедшийся код, прозу — нет.

### CHANGELOG

Только `## Unreleased`; выпущенные разделы — история.

- `packages/flutter_solo/CHANGELOG.md`: первая запись («follows `solo`'s rename
  … combines `SoloListenable` with `with SoloStream`») сворачивается с новой
  ломающей. Что в ней: `SoloListenable` — миксин; `extends SoloListenable<S>`
  становится `extends Solo<S> with SoloListenable`, контроллер со стримом —
  `with SoloStream, SoloListenable`; `SoloListenable<S>(value)` больше
  не компилируется — «Mixins can't be instantiated»; механическая миграция
  сохраняет старшинство `onListenerError` — база, подмешавшая миксин
  и переопределившая метод, по-прежнему побеждает; новое — база без Flutter
  с миксином на листе, где миксин перекрывает отчёт базы, и рецепт с методом
  под другим именем; в позиции типа аргумент обязателен, и анализатор этого
  не требует. `:65` «The class behaves as it did» — слово «class» уходит.
  Записи `:62`, `:78`, `:86`, `:93` описывают поведение, а не форму,
  и остаются.
- `packages/solo/CHANGELOG.md:3–20`: «`SoloListenable` is unaffected in shape
  -- it already extended the bare engine» — неправда, становится «в
  `flutter_solo` он стал миксином того же рода, и они комбинируются»; три
  `with SoloStream<S>`/`<T>` — вывод; однострочник `:15` →
  `class C<T extends Object> = Solo<T> with SoloStream;` — нынешний
  не компилируется ни до правки, ни после. **Поправка при работе, 2026-09-18:**
  форма `class C<T extends Object> extends Solo<T> with SoloStream {}`, которую
  предложили оба ревью и первая версия второй редакции, не компилируется тоже —
  у `Solo` нет конструктора без аргументов, «The superclass 'Solo<T>' doesn't
  have a zero argument constructor». Применение миксина пробрасывает
  конструктор `Solo` и остаётся одной строкой; миграция «a field or parameter
  typed `Solo<S>` … becomes `SoloStream<S>`» — позиция типа, остаётся явной.

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

**Старшинство `onListenerError` в новой раскладке.** Миграция его не меняет —
измерено (`Migrated`). Меняется оно только там, где миксин подмешан в лист под
базой без Flutter, а такой раскладки до правки не было: база, переопределившая
`onListenerError`, уступает миксину, и её реализация недостижима через `super`.
Сказано в дартдоке миксина, в дартдоке `Solo.onListenerError`, в разделе
`flutter.md` и в `CHANGELOG`, под тестами 3 и 4.

**Сырой тип в позиции типа линт не ловит.** `strict-raw-types` срабатывает
на неявный `dynamic`, а у `SoloStream` и `SoloListenable` граница `Object`:
`final SoloListenable profile;` молча становится `SoloListenable<Object>`.
Замерено: на `SoloStream? raw;` и `SoloListenable? rawFace;` анализатор молчит,
на `List? rawList;` — `strict_raw_type`. Ошибка всплывёт ниже по коду
(`ValueListenableBuilder<P>` не примет `SoloListenable<Object>`),
а во фрагментах документов, которые никто не собирает, не всплывёт вовсе.
Поэтому правило «в позиции типа аргумент явный» сказано словами — в дартдоке
миксина и в `CHANGELOG` обоих пакетов, — а фрагменты проверяются глазами.

**Тихо ломается проза, а не код.** В коде всё громко:
`extends SoloListenable<S>` — «Classes can only extend other classes», прямое
`SoloListenable<S>(value)` — «Mixins can't be instantiated», старый `super(0)`
в непереведённом подклассе — ошибка числа аргументов. Ссылки `[SoloListenable]`
в дартдоке продолжают резолвиться, сменив смысл. Сквозной `grep`
по `SoloListenable` нужен, но не достаточен: ревью нашло три места, которые он
не видит, — первую строку README ядра, строку Notes README `flutter_solo`
и «the base class of some other package». Финальный проход — `grep`
по `SoloListenable`, по «subclass», «base class» и «extends `Solo`» в тех же
файлах.

**`state.md` делит страницу с веткой `docs/state-rakes`.** Параллельная сессия
ведёт вычитку этой страницы, ветка живая и за время ревью сдвинулась дважды.
`git merge-tree` между `main` и веткой здесь не годится: он видит только
коммиты и уже сегодня конфликтует на `docs/handoff.md`. Проверка —
трёхсторонний `git merge-file` по двум файлам, перед каждым из двух коммитов:

```sh
B=$(git merge-base main docs/state-rakes)
for f in packages/solo/doc/state.md docs/ru/solo/state.md; do
  git show "$B:$f" > /tmp/base; git show "docs/state-rakes:$f" > /tmp/theirs
  cp "$f" /tmp/ours
  git merge-file -p /tmp/ours /tmp/base /tmp/theirs > /dev/null
  echo "$f conflicts=$?"
done
```

Если конфликт есть, правка `state.md` и его перевода уходит отдельным последним
коммитом, и владельцу называется место.

**Стенды.** Фрагменты `vs-bloc.md` собирает `tool/doc_snippets.py`; адресация
блоков — по разделу и объявленному имени (`tool/doc_blocks.py`), заголовок
класса в ключ не входит — проверено прогоном обоих ревьюеров. Фрагменты
`accumulation.md` стрима не читают и не затрагиваются.

## План

Два коммита, каждый зелёный сам по себе.

### Коммит 1: `refactor: infer the type argument of SoloStream in with`

- Тесты `solo`: семь объявлений в пяти файлах, затем `dart format`.
- Тест 5 в `solo_stream_test.dart`.
- `packages/flutter_solo/test/solo_listenable_test.dart:22`:
  `_Both extends SoloListenable<int> with SoloStream` — класс ещё класс, вывод
  из суперкласса работает, и заголовок коммита держит слово «все».
- Фрагменты: `packages/solo/README.md:145–146`, `doc/state.md:192` и строка
  таблицы `:107`, `doc/flutter.md:126–127`
  (`extends SoloListenable<SessionState> with SoloStream`),
  `doc/vs-bloc.md:798–799`, `:1488–1489`; переводы.
- `packages/solo/CHANGELOG.md`: две формы `with SoloStream<S>` — вывод,
  однострочник — применение миксина, позиция типа — явный аргумент с оговоркой
  про анализатор; фраза про `SoloListenable` не трогается — её переписывает
  коммит 2.
- Проверки: `dart analyze` и `dart format --set-exit-if-changed` в `solo`
  и `flutter_solo`; `dart test` в `solo` (582); `flutter test` в `flutter_solo`
  (89); оба стенда и `check_traces.py`; `check_translations.py`,
  `check_doc_shape.py`, `check_line_width.py`, `reflow.py --check`;
  `merge-file` против `docs/state-rakes`.

### Коммит 2: `feat(flutter_solo)!: SoloListenable becomes a mixin`

- Миксин и его дартдок; `solo_selection.dart:180–185`; фраза в дартдоке
  `Solo.onListenerError`.
- Восемь фикстур, пример; `test/support/plain_base.dart`; тесты 1–4.
- Документы и переводы из раздела «Документы», включая новый раздел
  `flutter.md`; `CHANGELOG` обоих пакетов.
- `docs/architecture.md`, `docs/conventions.md`, шапка
  `2026-09-12[4]-listenable-on-base-report.md`, удаление записи
  из `docs/backlog.md`, `docs/handoff.md`.
- Проверки: все проверки коммита 1, плюс `flutter analyze` примера
  `flutter_solo`, `dart analyze`/`dart test` в `async_job` и примере `solo`,
  `dart doc` в `solo` и `flutter_solo`, сборка сайта, сквозной `grep`
  из «Рисков».

### Для обоих

Мутации — те, что названы у тестов 1 и 3; каждая вносится копией файла
и откатывается копией, не `git checkout`. Гейт каждого коммита прогоняется
в отдельной копии дерева на `HEAD`: рабочее дерево делит соседняя сессия.

## Критерии приёмки

**Форма.** `SoloListenable` объявлен `mixin SoloListenable<S extends Object> on
Solo<S> implements ValueListenable<S>`, без конструктора; тело `value`
и `onListenerError` не изменилось.

**Вывод.** В `with` ни одного `SoloStream<` и `SoloListenable<` в коде
и фрагментах: `grep -rnE "with .*Solo(Stream|Listenable)<"` по `packages/`,
`docs/ru/` и `tool/` (без `.dart_tool` и `doc/api`) пуст; совпадение в прозе
`CHANGELOG`, если перезаливка его даст, разбирается глазами и допустимо, когда
это проза, называющая форму, а не код. В позиции типа аргумент на месте —
проверено глазами по `grep -rnwE "SoloStream|SoloListenable"` в коде
и фрагментах: линт этого не страхует.

**Фикстуры.** Восемь фикстур и пример переведены; `extends SoloListenable`
не встречается в `lib/`, `test/`, `example/` и во фрагментах кода документов.
Запись миграции в `CHANGELOG`, записи и handoff этим критерием не охватываются.

**Тесты.** Пять новых тестов из раздела «Новые тесты» и страж импорта,
добавленный кругом ревью работы, по одному на сценарий, с теми именами
и фикстурами; база тестов 2–3 живёт в библиотеке без импорта Flutter. Мутации
у тестов 1 и 3 ведут себя, как там написано; «только ими» не утверждается.

**Проза и дартдок.** Утверждения из разделов «Код» и «Документы» переписаны
по смыслу в обоих языках, включая три места, которые не видит `grep`
по `SoloListenable`, и абзац `solo_selection.dart:180–185`. Дартдок миксина
называет: что порядок с `SoloStream` не важен; правило старшинства
`onListenerError` с рецептом метода под другим именем; явный аргумент в позиции
типа. Раздел `flutter.md` «A base class without Flutter» есть в обоих языках
и открывается фрагментом. `CHANGELOG` `flutter_solo` называет миграцию, «Mixins
can't be instantiated», сохранённое старшинство при миграции, новую раскладку
и явный аргумент в позиции типа; фраза «`SoloListenable` is unaffected in
shape» из `CHANGELOG` ядра ушла, однострочник компилируется. Сквозной `grep`
из «Рисков» пройден глазами.

**Проверки.** По плану, у каждого коммита свои, в отдельной копии дерева
на `HEAD`. В сумме: `dart analyze` без единого info в `async_job`, `solo`,
`solo/example`; `flutter analyze` в `flutter_solo` и его примере;
`dart format --set-exit-if-changed` во всех пакетах, как в `gate.yml`;
`dart test` — `solo` 582, `async_job` 430, пример 9; `flutter test` —
`flutter_solo` 94; `dart doc` без предупреждений в `solo` и `flutter_solo`; оба
стенда с `check_traces.py`; `check_translations.py`, `check_line_width.py`,
`check_doc_shape.py`, `reflow.py --check`, сборка сайта; `merge-file` против
`docs/state-rakes` — 0 конфликтов перед каждым коммитом, иначе `state.md`
уходит отдельным коммитом.

**Записи.** Запись бэклога удалена; `docs/architecture.md`,
`docs/conventions.md`, `docs/handoff.md` обновлены; шапка
`2026-09-12[4]-listenable-on-base-report.md` помечена.
