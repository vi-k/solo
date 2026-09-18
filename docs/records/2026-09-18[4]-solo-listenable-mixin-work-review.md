> **Состояние на 2026-09-18:** ревью работы по
> `2026-09-18[1]-solo-listenable-mixin-design.md`; все находки приняты:
> первая — частично, шестая — как факт, без правки; вердикты у каждой; закрыты
> коммитом `fix: close the SoloListenable mixin work review`.
> **Что это:** независимое ревью двух коммитов — `018db09` и `9383e05`,
> ревьюер Opus в изолированной копии дерева на `9383e05`.
> **Связанные записи:** `2026-09-18[1]-solo-listenable-mixin-design.md`, `2026-09-18[5]-solo-listenable-mixin-work-review-2.md`, `2026-09-18[2]-solo-listenable-mixin-design-review.md`, `2026-09-18[3]-solo-listenable-mixin-design-review-2.md`.

# Ревью работы: `SoloListenable` миксином (`018db09`, `9383e05`)

Итог: **годится с правками**. Код правильный, гейт обоих коммитов зелёный,
каждое проверенное утверждение о поведении держится. Правки нужны в двух
тестах, которые своего условия не держат, и в прозе: семь находок уровня Low.

## Проверка дерева

```
/Users/user/development/my/solo/.claude/worktrees/agent-acf0418525a7cb2c9
HEAD is now at 9383e05 feat(flutter_solo)!: SoloListenable becomes a mixin
9383e05 feat(flutter_solo)!: SoloListenable becomes a mixin
018db09 refactor: infer the type argument of SoloStream in with
3bfea85 docs: review the SoloListenable mixin design and write its second edition
77a4ddd docs: the handoff takes SoloListenable as a mixin into work
40:mixin SoloListenable<S extends Object> on Solo<S>
22
```

Вершина и объявление совпадают с ожидаемым. Все прогоны шли в этой копии: Dart
3.13.0 и Flutter 3.47.0. Временные файлы лежали в `.rv/` внутри копии
и удалены. В конце `git status --porcelain` пуст, HEAD стоит на `9383e05`.

## Находки

### 1. [Medium] Тесты 3 и 4 не держат своего условия, а «база без Flutter» у тестов 2–3 ничем не охраняется

Мутации библиотеки ведут себя, как обещает спека. Мутации фикстур показывают
другое: тесты проходят и тогда, когда фикстура перестаёт быть тем, что
описывает имя теста.

- **Тест 4**,
  `'a base that mixes SoloListenable in keeps its own onListenerError'`
  (`solo_listenable_test.dart:492–507`). Я убрал `with SoloListenable`
  из `_FlutterBase` (`:48–58`), и `flutter test` остался зелёным: 93 из 93. Без
  миксина тест проверяет обычное переопределение метода `Solo`, и миграцию,
  которую он должен записывать, уже не видит. Хватит одной строки
  `expect(leaf, isA<ValueListenable<int>>())`, либо можно подать `leaf`
  в `ValueListenableBuilder`.
- **Тест 3**,
  `'SoloListenable on the leaf reports over an onListenerError of the base'`
  (`:473–490`). Я убрал переопределение `onListenerError` из `ReportingBase`
  (`test/support/plain_base.dart:19–22`): снова 93 из 93. Проверки
  `reports.single` и `leaf.reported` пуст выполняются и тогда, когда базе
  нечего перекрывать. Нужен контроль, что `ReportingBase` без миксина свой
  журнал заполняет.
- **«Без импорта Flutter»**. Я добавил в `plain_base.dart` импорт
  `package:flutter/foundation.dart` и `ValueNotifier` в теле:
  `solo_listenable_test.dart` прошёл, 22 из 22. Критерий «база тестов 2–3 живёт
  в библиотеке без импорта Flutter» сейчас выполнен, но держится только на том,
  что файл никто не правил. Совпадение `AppController` с фрагментом
  `flutter.md` тоже держится на ручной копии: сверки с документом нет.

Спека честно называет эти тесты записью обещаний, а не стражами механики.
Но запись, которая проходит без своей предпосылки, ничего не записывает.

**Вердикт: принято частично.** Обе мутации фикстур воспроизведены своими руками
— 22 из 22 зелёные в каждой. Тест 4 получил
`expect(leaf, isA<ValueListenable<int>>())`; тест 3 — контроль
`_PlainReportingLeaf`, та же база без миксина, чей журнал обязан заполниться;
импорт стережёт новый тест
`'the bases of these tests import nothing of Flutter'`, читающий
`plain_base.dart` и требующий единственный импорт `package:solo/solo.dart`.
После правки каждая из трёх мутаций — снятый миксин у `_FlutterBase`, снятое
переопределение у `ReportingBase`, импорт Flutter в базе — краснит ровно свой
тест. Сверки `AppController` с фрагментом `flutter.md` нет и не будет: фрагмент
лежит в другом пакете и держит свой комментарий `// ...`, а база — две строки;
ручная копия названа в самом файле. `flutter_solo` — 94.

### 2. [Low] «Выше» и «ниже» в цепочке миксинов значат в соседних дартдоках противоположное

- `packages/solo/lib/src/solo_stream.dart:8–13` говорит, что сосед, который
  зовёт `super.publish`, «sits above `SoloStream`». Выше здесь значит более
  производный класс, верхнее переопределение. Так же говорит
  `solo_stream_test.dart`: «`_Bomb` is the topmost override».
- `packages/flutter_solo/lib/src/solo_listenable.dart:29–32`: «The class that
  mixes `SoloListenable` in, and every class below it, overrides the mixin».
  Ниже здесь значит более производный.
- `packages/solo/lib/src/solo.dart:194–197` («further down the chain»)
  и `packages/solo/doc/flutter.md:161–168` («sits below it») пишут так же, как
  `SoloListenable`.

Внутри каждого текста картина последовательная, но между текстами она
перевёрнута. При этом дартдок `SoloListenable` сам отсылает читателя к правилу
`SoloStream` («goes first by its own rule»), и контроллер
`with SoloStream, SoloListenable` получает две противоположные картинки. Спека
тоже пишет в обе стороны: «в линеаризации над базой» и «подмешанный ниже
по цепочке».

**Вердикт: принято.** Картина выровнена по правилу `SoloStream`: выше — более
производный класс. Дартдок миксина говорит это прямо («a class sits above the
mixins it mixes in, as in the rule of `SoloStream`»), `Solo.onListenerError` —
«a mixin applied above a base class», `flutter.md` и перевод — «a class sits
above the mixins it mixes in»; в спеке оба места «ниже по цепочке» стали
«выше».

### 3. [Low] handoff говорит о записи в бэклоге, которой больше нет

`docs/handoff.md:24–25`: «В бэклоге владельца одна запись: `SoloListenable`
становится миксином, как `SoloStream`, — решение 2026-09-16, делать не сейчас».
`docs/backlog.md` в этом же коммите пуст. Фраза стоит в цепочке «Раньше:»
первого абзаца, но написана в настоящем времени, и читатель с чистого контекста
прочтёт её как текущее состояние.

**Вердикт: принято.** Фраза снята.

### 4. [Low] Фрагмент в дартдоке миксина не компилируется против типов из README

`solo_listenable.dart:8–13` пишет `ProfileController() : super(const Empty());`
над `Solo<Profile>`. `Profile` и `Empty`
из `packages/flutter_solo/README.md:74–76` и `example/lib/main.dart` объявлены
без const-конструктора. Зонд с этими типами даёт `const_with_non_const`: «The
constructor being called isn't a const constructor». Мелочь по соседству:
заголовок в дартдоке перенесён на `with`, хотя в одну строку он занимает 77
символов вместе с `/// `, а `dart format` свёл бы его в строку.
`docs/conventions.md` отдаёт такие решения форматтеру.

**Вердикт: принято.** `super(Empty())`, заголовок в одну строку. Перенос был
моей ошибкой счёта: я насчитал 82 символа там, где их 77.

### 5. [Low] Шапка спеки молчит о двух отступлениях работы от спеки

- Критерий «Вывод» переписан тем же коммитом, что делает работу (`9383e05`,
  запись `2026-09-18[1]-solo-listenable-mixin-design.md:438–444`). Было:
  совпадение в `CHANGELOG` «допустимо только как позиция типа». Стало:
  «допустимо, когда это проза, называющая форму». Сквозной
  `grep -rnE "with .*Solo(Stream|Listenable)<"` находит ровно одну строку,
  `packages/flutter_solo/CHANGELOG.md:8`: `` `with SoloStream,
  SoloListenable`. `SoloListenable<S>(value)` no longer ``. Это не позиция
  типа, а вызов конструктора, попавший в ту же строку после переноса. По старой
  редакции критерий был бы нарушен. Новая редакция его пропускает, но смена
  критерия под результат должна стоять в шапке.
- Тест 3 по спеке называется `'…reports over the base's onListenerError'`
  (запись, `:216`), в дереве —
  `'…reports over an onListenerError of the base'`. Критерий «Тесты» требует «с
  теми именами».

Шапка называет только поправку однострочника и раздела «План».

**Вердикт: принято.** Шапка спеки называет оба отступления и почему они
сделаны; имя теста 3 в спеке приведено к дереву.

### 6. [Low] Сообщение коммита `9383e05` приписывает ему пятый тест

«Five new tests record what the documents promise: … and the one-line class of
the core CHANGELOG». Тест
`'a generic controller takes SoloStream by inference'` лежит в `018db09`,
а `9383e05` добавляет четыре. Коммиты не запушены, так что это ещё можно
поправить.

**Вердикт: принято как факт, сообщение не переписывается.** Переписать
сообщение — значит сменить хэш коммита, который уже назван в двух записях
ревью, и на котором стояли копии обоих ревьюеров. Неточность записана здесь:
`9383e05` добавляет четыре теста, пятый пришёл в `018db09`.

### 7. [Low] Повторное подмешивание на листе тихо снимает отчёт базы

Раскладка такая: база во Flutter `extends Solo<S> with SoloListenable` со своим
`onListenerError`, лист `extends FlutterBase<int> with SoloListenable`. Лист
мог получить миксин, например, по рецепту нового раздела поверх уже
мигрированной базы. Зонд: `base=0 flutter=1`, отчёт базы потерян,
а `flutter analyze` не говорит ничего. Общее правило в дартдоке это покрывает,
но фраза «The class that mixes `SoloListenable` in, and every class below it,
overrides the mixin» для этой раскладки буквально неверна: второе применение
стоит ниже базы. Хватит одной фразы, что миксин подмешивают один раз, в базу
или в лист.

**Вердикт: принято.** Дартдок миксина и раздел `flutter.md` с переводом
говорят: подмешивать один раз, в базу или в лист, — повторное применение
на листе встаёт над переопределением базы и так же его глушит.

### 8. [Low] Проза перевода и README

- `docs/ru/solo/flutter.md:145–146`: «а `SoloListenable` подмешивает лист». При
  обычном порядке слов подлежащее здесь `SoloListenable`, и фраза читается как
  «SoloListenable подмешивает (в себя) лист». Однозначнее: «а лист подмешивает
  `SoloListenable`».
- `packages/flutter_solo/README.md:6–7` и `README.ru.md:7–9`:
  `ValueListenable<S>` появляется в первом абзаце, где `S` больше ничем
  не введён. Раньше его вводил `SoloListenable<S>`.

**Вердикт: принято.** «а лист подмешивает `SoloListenable`»; в первом абзаце
обоих README — «`ValueListenable` of its state» и «`ValueListenable` своего
состояния».

## Что проверено и держится

**Гейт на `9383e05`**
- `dart format --output=none --set-exit-if-changed`: 0 изменений в async_job
  (38 файлов), solo (74) и flutter_solo (18).
- `dart analyze` / `flutter analyze`: «No issues found» в async_job, solo,
  solo/example, flutter_solo и flutter_solo/example.
- `dart doc --dry-run`: 0 предупреждений и 0 ошибок в async_job, solo
  и flutter_solo.
- Тесты: async_job 430, solo 582, solo/example 9, flutter_solo 93, все зелёные.
  Совпадает с критериями и с handoff.

**Коммит `018db09` отдельно**
- Формат, анализ и тесты чистые: solo 582, flutter_solo 89.
- Оба стенда: 27 драйверов, 0 упавших.
- `check_traces.py`, `check_translations.py`, `check_line_width.py`,
  `reflow.py --check` и `check_doc_shape.py` чистые.
- Шаг зелёный сам по себе.

**Стенды на `9383e05`**
- `doc_snippets.py` и `accumulation_snippets.py` в каталоге внутри копии.
- `dart pub get` и `dart analyze bin/v` чистые во всех трёх пакетах.
- 27 драйверов, 0 упавших.
- `check_traces.py`: vs-bloc — 2 процитированные трассы, 0 не напечатано;
  accumulation — 11 и 0.
- `check_translations.py`: «no differences»; у `flutter.md` 3 заголовка и 5
  блоков кода с обеих сторон.
- Ширина строк, `reflow.py --check` и `check_doc_shape.py` чистые.
- `build_site.py`: 42 страницы.

**`docs/state-rakes`**
- Трёхсторонний `git merge-file` против вершины `b418f00` от базы `511421c`
  даёт 0 конфликтов по `packages/solo/doc/state.md` и `docs/ru/solo/state.md`.
- В слитом тексте нет `SoloStream<` и нет формулировок про класс.

**Критерии приёмки**
- **Форма.** `solo_listenable.dart:40–41` — ровно `mixin SoloListenable<S
  extends Object> on Solo<S> implements ValueListenable<S>`. Конструктора нет.
  Тела `value` и `onListenerError` по диффу не изменились.
- **Вывод.** Совпадение `grep` одно, `CHANGELOG`:8 (см. находку 5). Поиск
  голого типа в позиции типа (`SoloListenable?`, `SoloStream x`,
  `<SoloListenable>`) по `packages/`, `docs/ru/`, `docs/architecture.md`,
  `docs/conventions.md` и `tool/` ничего не нашёл.
- **Фикстуры.** Восемь фикстур и пример переведены. `extends SoloListenable`
  осталось только в записи миграции (`CHANGELOG`:5).
- **Тесты.** Пять тестов, фикстуры как в спеке, база в `plain_base.dart`
  импортирует только `package:solo`. Против прежнего класса тесты 1–4
  не компилируются: «Can't use 'SoloListenable' as a mixin because it has
  constructors». Тест 5 проходил бы и до правки, и это ожидаемо: он записывает
  строку `CHANGELOG`.
- **Проза и дартдок.** По спеке переписаны: оба README; `flutter.md`
  (вступление, два фрагмента, новый раздел на двух языках); `state.md`
  (таблица, абзац, `Camera`); `vs-bloc.md` (таблица, два фрагмента); три места,
  которые `grep` не видит (`solo/README.md:10–11`,
  `flutter_solo/README.md:180–182` и строка таблицы Notes `:382`);
  `solo_selection.dart:180–185`; фраза в `Solo.onListenerError`. Дартдок
  миксина называет безразличие порядка, правило старшинства с рецептом и явный
  аргумент в позиции типа. `CHANGELOG` `flutter_solo` называет всё, что велит
  критерий. «Unaffected in shape» из `CHANGELOG` ядра ушло.
- **Записи.** Бэклог пуст. `docs/architecture.md:23–35` и `:345–346`
  и `docs/conventions.md:51–55` обновлены. Шапка
  `2026-09-12[4]-listenable-on-base-report.md` помечена «Пересмотрено
  2026-09-18» и говорит правду. Шапка спеки верна, кроме находки 5: «не
  запушено» подтверждается, `origin/main` = `511421c`. В handoff верны числа
  582/93/430/9, 23 переписанные формы (пересчитал по диффу `018db09`), пять
  тестов и 0 конфликтов.

**Мутации в `solo_listenable.dart`** Каждая вносилась копией файла
и откатывалась копией; прогонялся весь `flutter test`.
- Миксин вдобавок зовёт `super.onListenerError`: красные ровно 4 — тест 3 и три
  названных в спеке.
- Миксин без `onListenerError`: те же 4.
- `publish` в миксине зовёт `super` дважды: тест прямого порядка красный, тест
  обратного порядка зелёный, как обещано.
- Свои: - отчёт уходит в зону вместо `FlutterError`: те же 4 красных; -
  `addListener` глотает регистрацию: 31 красный, включая тесты 1–4.

**Зонды на утверждения документов**
- Однострочник `class C<S extends Object> = Solo<S> with SoloListenable;`
  компилируется, `C<int>(0)` — это `ValueListenable<int>`, `value` равен 0.
- Однострочник ядра дословно,
  `class C<T extends Object> = Solo<T> with SoloStream;`, компилируется,
  `dart analyze` чист, поле `SoloStream<int>` читает `currentState`.
- Ошибки компиляции совпадают с документами: - `extends SoloListenable<int>` —
  «Classes can only extend other classes»; - старый `super(0)` — «Too many
  positional arguments»; - `SoloListenable<int>(0)` — «Mixins can't be
  instantiated».
- Голый `SoloListenable`, поданный в `ValueListenableBuilder<int>`, даёт
  «'SoloListenable<Object>' can't be assigned to 'ValueListenable<int>'».
  На `SoloListenable? rawFace;` и `SoloStream? rawStream;` анализатор под
  `strict-raw-types` молчит.
- `super.onListenerError` из листа над `ReportingBase` приходит в миксин:
  у листа 1, у `FlutterError` 1, в журнале базы 0.
- Рецепт с методом под другим именем: журнал базы 1, `FlutterError` 0.
- Мок `implements SoloListenable<int>` компилируется. Обратный порядок
  `with SoloListenable, SoloStream` даёт и `SoloStream<int>`,
  и `SoloListenable<int>`.
- Утверждение дартдока `SoloSelect`: член `select<T>` у миксина против
  `select(String)` контроллера — `invalid_override`, как сказано.
- Фрагменты, которые не собирает ни один стенд, анализируются чисто: первый
  `ProfileController` из `flutter.md`, `Session` и фрагмент нового раздела
  вместе с `AppController`. Фрагмент README `flutter_solo` совпадает
  с примером, а пример анализируется чисто.

**Переводы по смыслу** Сверил каждый изменённый абзац `README.ru.md` обоих
пакетов и `docs/ru/solo/{flutter,state,vs-bloc}.md` с оригиналом. Расхождений
по смыслу нет, кроме двусмысленности из находки 8.

**Что осталось неправдой** Сквозной поиск по `SoloListenable`, «subclass»,
«base class», «extends `Solo`», «directly» и «наследу» в живых артефактах
ни одного места, где `SoloListenable` назван классом или подклассом, не нашёл.
Там, где сказано «subclass» (`state.md:125`, `:174`, `:216`), речь
о контроллере, и спека оставила эти места сознательно.

Итог: **годится с правками**.
