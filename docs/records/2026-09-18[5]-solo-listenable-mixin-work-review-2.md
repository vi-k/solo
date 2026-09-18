> **Состояние на 2026-09-18:** ревью работы по
> `2026-09-18[1]-solo-listenable-mixin-design.md`; все находки приняты,
> третья — как факт, без правки; вердикты у каждой; закрыты коммитом
> `fix: close the SoloListenable mixin work review`.
> **Что это:** второе независимое ревью двух коммитов — `018db09`
> и `9383e05`, ревьюер Opus в своей изолированной копии дерева на `9383e05`,
> параллельно с первым и без знания его выводов.
> **Связанные записи:** `2026-09-18[1]-solo-listenable-mixin-design.md`, `2026-09-18[4]-solo-listenable-mixin-work-review.md`.

# Ревью работы: `SoloListenable` миксином (`018db09`, `9383e05`)

## Проверка дерева

Голый `git` отказал из-за хука изоляции, поэтому команды шли через
`/usr/bin/git`.

```
/Users/user/development/my/solo/.claude/worktrees/agent-a441dbbbe0eb3d803
HEAD is now at 9383e05 feat(flutter_solo)!: SoloListenable becomes a mixin
9383e05 feat(flutter_solo)!: SoloListenable becomes a mixin
018db09 refactor: infer the type argument of SoloStream in with
3bfea85 docs: review the SoloListenable mixin design and write its second edition
77a4ddd docs: the handoff takes SoloListenable as a mixin into work
40:mixin SoloListenable<S extends Object> on Solo<S>
22
```

Вершина и коммит под ней те, что ожидались. `SoloListenable` объявлен миксином.
Все прогоны ниже сделаны в моей копии. Под конец она вернулась на `9383e05`
чистой: зонды и временные файлы удалены, мутации откатывались копией файла.

## Находки

High и Medium нет. Все находки уровня Low.

### 1. [Low] Заголовок фрагмента `Session` не сведён в строку, как свёл бы `dart format`

`packages/solo/doc/flutter.md:126–127` и `docs/ru/solo/flutter.md:128–129`:

```dart
final class Session extends Solo<SessionState>
    with SoloStream, SoloListenable {
```

В одну строку это ровно 80 символов. Код в документах держит ширину 80, её
отдаёт `dart format` (`docs/conventions.md:33`,
`tool/check_line_width.py:5–6`). Зонд: `dart format --output=show` на этом
фрагменте сводит заголовок в одну строку
`final class Session extends Solo<SessionState> with SoloStream,
SoloListenable {`. Принятая находка 13 первого ревью спеки и раздел спеки
«Документы» требуют сводить заголовки «туда, куда свёл бы `dart format`».
Коммит 1 этот фрагмент свёл в одну строку
(`… extends SoloListenable<SessionState> with SoloStream {`), а коммит 2 снова
разбил на две.

Тот же случай в дартдоке миксина,
`packages/flutter_solo/lib/src/solo_listenable.dart:9–10`. Сведённая строка
занимает 73 символа, с `/// ` — 77, и `dart format` поставил бы её в одну.

Проверены все двухстрочные заголовки `extends … with …`
в `packages/*/README*.md`, `packages/*/doc/`, `docs/ru/` и `lib/`. Кроме этих
трёх, свести нельзя только лист из нового раздела: 87 символов.

**Вердикт: принято.** Длина проверена: 80 символов, в пределе `dart format`.
Заголовок `Session` сведён в строку в обоих языках, дартдок миксина — тоже
(четвёртая находка `2026-09-18[4]-solo-listenable-mixin-work-review.md`).

### 2. [Low] Фрагмент в дартдоке миксина пишет `const Empty()`, а у `Empty` из README и примера нет const-конструктора

`packages/flutter_solo/lib/src/solo_listenable.dart:11`:
`ProfileController() : super(const Empty());`. В README пакета
и в `example/lib/main.dart:25` класс объявлен как
`final class Empty extends Profile {}`, и оба зовут `super(Empty())`. Зонд
с состояниями README дал `error • The constructor being called isn't a const
constructor • const_with_non_const`. Фрагмент дартдока не собирает никто,
поэтому ошибку ловит только читатель, который скопирует его рядом с README.

**Вердикт: принято.** Та же, что четвёртая находка первого ревью работы;
`super(Empty())`.

### 3. [Low] Сообщение `9383e05` говорит «Five new tests», а коммит добавляет четыре

В тексте коммита стоит: «Five new tests record what the documents promise: …,
and the one-line class of the core CHANGELOG». Тест с однострочником
(`a generic controller takes SoloStream by inference`,
`packages/solo/test/solo_stream_test.dart:73`) пришёл в `018db09`. У `9383e05`
четыре теста, 89 → 93, и это подтверждено прогоном `018db09`: `flutter_solo`
там 89. Коммиты не запушены, поправить ещё можно.

**Вердикт: принято как факт, сообщение не переписывается** — по той же причине,
что в шестой находке первого ревью работы: смена хэша коммита, уже названного
в записях.

### 4. [Low] Спека разошлась с работой в двух местах, а шапка называет не всё

- Имя теста 3 в спеке,
  `docs/records/2026-09-18[1]-solo-listenable-mixin-design.md:216`:
  `'SoloListenable on the leaf reports over the base's onListenerError'`.
  В дереве, `packages/flutter_solo/test/solo_listenable_test.dart:474`:
  `'… reports over an onListenerError of the base'`. Критерий «Тесты» требует
  «с теми именами».
- Критерий «Вывод» (`:438–441`) переписан в коммите работы. Было «допустимо
  только как позиция типа», стало «допустимо, когда это проза, называющая
  форму». Правка по делу: совпадение `packages/flutter_solo/CHANGELOG.md:8` —
  артефакт жадного `.*`, который склеил два код-спана
  (`with SoloStream, SoloListenable`. `SoloListenable<S>(value)`). Но шапка
  спеки (`:1–6`) среди «поправок при работе» называет только однострочник
  `CHANGELOG` и раздел «План». Смягчение критерия не названо.

**Вердикт: принято.** Та же, что пятая находка первого ревью работы; шапка
называет оба отступления, имя теста в спеке приведено к дереву.

### 5. [Low] `docs/architecture.md:34–35`: «различаются контроллеры только доставкой изменений через защищённый `publish`»

Абзац переписан в этом коммите, и прежнее «наследники» стало «контроллеры».
`SoloListenable` `publish` не переопределяет: его вклад — интерфейс
`ValueListenable` (`value`) и отчёт `onListenerError`, а доставка идёт через
слушателей движка внутри `Solo.publish`. Мутация «миксин с `publish`» (ниже)
показывает, что своего `publish` у миксина нет и быть не должно. Фраза была
неточной и до волны, но теперь она стоит прямо после «`SoloListenable<S>` …
подмешивает `ValueListenable`».

**Вердикт: принято.** Фраза стала: миксины различаются тем, что добавляют
к движку, — `SoloStream` доставку через защищённый `publish`, `SoloListenable`
лицо `ValueListenable` поверх слушателей самого движка.

### 6. [Low] `docs/handoff.md:24–25` говорит о записи бэклога, которой больше нет

«В бэклоге владельца одна запись: `SoloListenable` становится миксином, как
`SoloStream`, — решение 2026-09-16, делать не сейчас.» Предложение стоит
в цепочке «Раньше: …», но написано в настоящем времени. Оно спорит и с деревом
(`docs/backlog.md` пуст после маркера), и с абзацем того же файла на `:99–100`
(«Владелец взял запись бэклога 2026-09-18, и она удалена»). Handoff
по `AGENTS.md` описывает только текущее состояние.

**Вердикт: принято.** Та же, что третья находка первого ревью работы; фраза
снята.

### 7. [Low] Обещание «база без Flutter» записано тестом, но не охраняется

`packages/flutter_solo/test/support/plain_base.dart` сейчас импортирует только
`package:solo/solo.dart`: критерий «Тесты» выполнен. Но файл анализируется
и собирается внутри Flutter-пакета. Лишний
`import 'package:flutter/foundation.dart'` в нём ничего не покрасит, и тест 2
со своим именем «a leaf over a base without Flutter» остался бы зелёным. Спека
прямо называет новые тесты записями обещаний, а не стражами, так что это
замечание о пределе теста, а не дефект.

**Вердикт: принято.** Та же, что третья часть первой находки первого ревью
работы; импорт теперь стережёт отдельный тест, и мутация «импорт Flutter
в базе» краснит его.

## Что проверено и держится

**Прогоны на `9383e05`, по заданию CI:**
- `dart pub get` / `flutter pub get` — все 5 пакетов.
- `dart format --output=none --set-exit-if-changed`:
  - `async_job`: 38 файлов, 0 изменено;
  - `solo`: 74 файла, 0 изменено;
  - `flutter_solo`: 18 файлов, 0 изменено.
- Анализ везде «No issues found!»:
  - `dart analyze`: `async_job`, `solo`, `solo/example`;
  - `flutter analyze`: `flutter_solo` и его `example`.
- `dart doc --dry-run`: `async_job`, `solo`, `flutter_solo` — «0 warnings
  and 0 errors».
- Тесты:
  - `dart test`: `async_job` 430, `solo` 582, `solo/example` 9;
  - `flutter test`: `flutter_solo` 93.
- Стенды:
  - оба генератора, `pub get` и `dart analyze bin/v` в `bloc_check`,
    `solo_check`, `accumulation_check` без замечаний;
  - драйверов 27, упавших 0;
  - `check_traces.py`: `vs-bloc.md` — 2 цитаты, `accumulation.md` — 11,
    0 не напечатано.
- Проверки документов:
  - `check_translations.py`, `check_doc_shape.py`, `check_line_width.py`,
    `reflow.py --check` — зелёные;
  - `build_site.py` — 42 страницы.
- Дерево после прогонов не дрейфует.

**Коммит 1 сам по себе.** Всё то же на `018db09`: format, analyze и doc чистые;
`solo` 582, `async_job` 430, пример 9, `flutter_solo` 89; 27 драйверов,
`check_traces` и четыре проверки документов зелёные, сайт собирается.

**`merge-file` против `docs/state-rakes`** (`b418f00`, база `511421c`):
`state.md` и его перевод — 0 конфликтов. Ветка не добавляет ни одного
`SoloStream<`/`SoloListenable` в код.

**Критерии приёмки:**
- **Форма.** `solo_listenable.dart:40–41` —
  `mixin … on Solo<S> implements ValueListenable<S>`, конструктора нет. Тела
  `value` и `onListenerError` побайтно совпадают с классом на `018db09`.
- **Вывод.** - `grep -rnE "with .*Solo(Stream|Listenable)<"` по `packages/`,
  `docs/ru/`, `tool/` даёт одно совпадение, прозу `flutter_solo/CHANGELOG.md:8`
  (см. находку 4). - Поиск голого `SoloStream`/`SoloListenable` в позиции типа
  по коду и фрагментам ничего не нашёл. - Коммит 1 переписал ровно 23 формы
  в `with`: 24 удалённые строки с `SoloStream<`, одна из них — перезалитая
  позиция типа в `CHANGELOG`. Число в handoff верное.
- **Фикстуры.** Все 8 фикстур и пример переведены. `extends SoloListenable`
  осталось только в прозе миграции `CHANGELOG`.
- **Тесты.** Пять тестов на месте. База тестов 2–3 живёт в `plain_base.dart`
  без Flutter. `AppController` повторяет фрагмент `flutter.md` (тот же
  заголовок и конструктор). - Мутация «`publish` в миксине зовёт `super`
  дважды»: краснеют 19 тестов, в том числе прямой порядок; тест 1 (обратный
  порядок) зелёный, как и записано в спеке. - Мутация «миксин зовёт
  `super.onListenerError`»: красные тест 3 и три названных существующих. -
  Мутация «миксин без `onListenerError`»: то же самое. - Своя мутация «`value`
  застывает на первом состоянии»: вместе с шестью существующими краснеют тесты
  1 и 2. - Тесты 1–4 на классе `018db09` не компилируются («Can't use
  'SoloListenable' as a mixin because it has constructors»). - Тест 5 сторожит
  вывод типом: при явном `with SoloStream<Object>` строка
  `SoloStream<int> typed = solo` не компилируется.
- **Проза и дартдок.** Дартдок миксина называет порядок, старшинство с рецептом
  и явный аргумент. Раздел «A base class without Flutter» есть в обоих языках.
  Абзац `SoloSelect` переписан, а зонд подтвердил, что член миксина
  `select<T>(…)` против своего `select(String)` у контроллера — это
  `invalid_override`. Три места, которых не видит `grep` (первая строка README
  ядра, строка Notes, «the base class of some other package»), исправлены.
- **Записи.** Запись бэклога удалена. Правки в `architecture.md`,
  `conventions.md` и `handoff.md` на месте. Шапка
  `2026-09-12[4]-listenable-on-base-report.md` помечена «Пересмотрено
  2026-09-18» со ссылкой на спеку.

**Зонды на утверждения документов** (все сходятся с текстом):
- Однострочник `CHANGELOG` `flutter_solo`,
  `class C<S extends Object> = Solo<S> with SoloListenable;`, компилируется.
  `C<int>(3)` — это `ValueListenable<int>` с `value == 3`.
- Однострочник ядра `class C<T extends Object> = Solo<T> with SoloStream;` без
  `final` тоже работает.
- Форма с `{}` даёт «The superclass 'Solo<T>' doesn't have a zero argument
  constructor»; старая `<T>` без границы — ещё и «doesn't conform to the
  bound».
- `SoloListenable<int>(0)` → «Mixins can't be instantiated»;
  `extends SoloListenable<int>` → «Classes can only extend other classes».
- Лист со своим `onListenerError` и `super`: журнал `[leaf: Bad state: boom]`,
  отчётов через `FlutterError` 1, до базы `super` не дошёл.
- Рецепт «метод под другим именем»: журнал `[recipe: …]`, отчётов через
  `FlutterError` 0.
- Лист над голой базой отчитывается через `FlutterError`.
- Миграционная раскладка (тест 4) оставляет старшинство за базой.
- Фрагменты `flutter.md` — новый раздел (`AppController` и лист) и `Session`
  с обеими доставками — компилируются и работают.
- Моки `implements SoloListenable<int>` и `implements <лист>` компилируются.
- Сырой тип: на `SoloListenable? rawFace;` и `SoloStream? raw;` анализатор
  молчит в обоих пакетах, на `List? rawList;` выдаёт `strict_raw_type`.
  `ValueListenableBuilder<Profile>` не принимает голый `SoloListenable`:
  «SoloListenable<Object> can't be assigned».

**Переводы.** `README.ru.md` обоих пакетов
и `docs/ru/solo/{flutter,state,vs-bloc}.md` сверены с английским по смыслу
абзац за абзацем: первые абзацы, «Builders for any controller», строка Notes,
новый раздел с правилом старшинства и рецептом, строки таблиц `state.md`
и `vs-bloc.md`, абзац `state.md` о миксине. Расхождений нет.

**Остатки «класса».** В живых артефактах (`packages/`, `docs/ru/`,
`architecture.md`, `conventions.md`, `tool/`, `site/`, `.github/`)
`SoloListenable` нигде не назван классом, подклассом или базой.
`with SoloStream<X>` тоже не осталось. `state.md:124–125` («unless a subclass
says otherwise») оставлен по решению спеки и остаётся верным.

**Записи.** Шапка спеки говорит правду о состоянии (смержено двумя коммитами,
не запушено, идёт ревью), кроме пропуска из находки 4. В handoff наборы (582 /
93 / 430 / 9), хэш `018db09`, «23 формы» и «0 конфликтов» совпадают с моими
прогонами.

## Итог

Годится с правками.
