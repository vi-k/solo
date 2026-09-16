> **Состояние на 2026-09-16:** шаг 1 (код и тесты) сделан и смержен,
> коммиты `84ee53f` и `1eaa283`. Шаг 2 (документы) не начат.
> **Что это:** план по спеке `2026-09-15[14]-solo-stream-mixin-design.md`
> — перенос стрима в миксин `SoloStream`, `SoloBase` → `Solo`.
> **Связанные записи:** `2026-09-15[14]-solo-stream-mixin-design.md`,
> `2026-09-15[15]-solo-stream-mixin-design-review.md`,
> `2026-09-15[16]-solo-stream-mixin-design-review-2.md`.

## Шаг 0 (сделан): радиус измерен, не взят из спеки

Спека называла «тридцать мест» по памяти самой спеки. Замерено пробой:
временный `abstract` на нынешнем `Solo` (`lib/src/solo.dart`, класс, который
станет `SoloStream`), `dart analyze` в `solo`, правка отменена. Ровно **30
ошибок instantiate_abstract_class** в четырёх файлах:

- `test/accumulation_timing_test.dart` — 16 (строки 14, 48, 75, 106, 136, 171,
  215, 266, 294, 328, 355, 384, 420, 448, 473, 522);
- `test/accumulator_test.dart` — 9 (18, 45, 103, 136, 180, 214, 880, 1474,
  1523);
- `test/hooks_test.dart` — 1 (113);
- `test/then_test.dart` — 4 (18, 34, 58, 83).

`packages/solo/example` и `flutter_solo` — ноль ошибок, как и утверждала спека.
Число подтверждено, план ниже на него и рассчитан.

Заодно уточнён список приватных фикстур, которым нужен миксин (девятое
и десятое из спеки не были названы поимённо). Проверено по каждому кандидату
`extends Solo<TestState>`, читает ли он `.stream`:

- `_ExposedStreamSolo` (`closed_state_test.dart:293`) — читает (`:72`, `:180`),
  **нужен миксин**;
- `_ThrowingChange` (`hooks_test.dart:367`) — читает (`:250`), **нужен**;
- `_Reentrant` (`close_test.dart:281`) — читает (`:154`), **нужен**;
- `_ReentrantSolo` (`disposal_test.dart:182`) — не читает, **не нужен**;
- `_Reentrant` (`zone_test.dart:320`, другое, приватное имя того же файла) —
  не читает, **не нужен**.

Девятое объявление — фикстура для `runSolo`-тестов, которым нужен стрим.
`runSolo` (`test/support/run_solo.dart`) создаёт `TestSolo`, у которого после
правки стрима не будет («Миксин ей не даётся» — решение уже в спеке). Проверено
пробой, а не только чтением: `TestSolo` временно переставлена
на `extends SoloBase<TestState>` (симуляция потери стрима без переименования),
`dart test` в `solo` — **ровно два файла падают компиляцией**,
`close_test.dart` (строки 17, 183) и `sequential_test.dart` (109), больше
никаких скрытых расхождений в сборках close/journal нет; правка отменена. Три
вызова читают `solo.stream` через `runSolo`. Им заводится параллельная пара:
фикстура `TestSoloStream extends Solo<TestState> with SoloStream<TestState>`
рядом с `TestSolo` и функция `runSoloStream`, тем же телом, что `runSolo`,
только с этим типом — по образцу имени `PlainSolo`/`Solo`, без придумывания
новой схемы именования.

## Шаг 1: код и тесты, один коммит

Неделим по той же причине, что и раньше в этом проекте: половина переименования
не собирается.

1. **Файлы, пять шагов** — как в спеке, дословно:
   `src/solo.dart` → `src/solo_stream.dart` (класс → миксин
   `SoloStream`); `src/solo_base.dart` → `src/solo.dart` (`SoloBase` →
   `Solo`); пять `part of` (`job.dart`, `job_context.dart`, `queue.dart`,
   `accumulator.dart`, `accumulation_timing.dart`); два `import`
   (`observer.dart`, `solo_cancel_reason.dart`); экспорт в `lib/solo.dart`
   переставлен после `solo_cancel_reason.dart` для алфавита
   `directives_ordering`.
2. **`PlainSolo`** — новый файл `test/support/plain_solo.dart`:
   ```dart
   final class PlainSolo<S extends Object> extends Solo<S> {
     PlainSolo(super.initialState);
   }
   ```
   Тридцать мест из шага 0 переписываются `Solo<T>(v)` →
   `PlainSolo<T>(v)`, импорт `support/plain_solo.dart` добавляется
   в четыре файла.
3. **`TestSoloStream` и `runSoloStream`** — в `test/support/test_solo.dart`
   и `test/support/run_solo.dart` соответственно, по образцу выше. Три
   места (`close_test.dart:17`, `:183`, `sequential_test.dart:109`)
   переходят на `runSoloStream`.
4. **Три приватные фикстуры** получают `with SoloStream<TestState>`:
   `_ExposedStreamSolo`, `_ThrowingChange`, `_Reentrant`
   (`close_test.dart`).
5. **Сделано:** `solo_base_test.dart` → `test/solo_test.dart` (имя класса,
   который в нём проверяется). Приватная фикстура `_Bare` снята — она
   дублировала уже существующий `PlainSolo`, и тест взял его вместо
   своего класса. Название теста стало
   `'a Solo subclass compiles and reads state, with no stream of its own'`.
6. **`async_job`**, дартдок: `job_base.dart:315` и `:888` называют
   `SoloBase.debug`/`SoloBase.errorHandler` — правятся на `Solo.…`. Это
   правка нижнего пакета для верхнего дартдока, без смены поведения;
   `pubspec_overrides.yaml` уже стоят.
7. **Механическое переименование `SoloBase` → `Solo` по всему дереву** —
   отдельным пунктом от списка выше, потому что это не решение, а замена
   текста. Список того, что называет `SoloBase`, не совпадает ни
   с «тридцатью местами» (шаг 0), ни с девятью объявлениями (список выше):
   найдено **123 обращения к статическим членам**
   (`SoloBase.observer`/`.errorHandler`/`.debug`) в тестах `solo`
   и `flutter_solo`, плюс пятнадцать `extends SoloBase<`/`SoloBase<S>`
   как тип. Замена везде, где `SoloBase` встречается как идентификатор,
   на `Solo` — включая `test/support/run_solo.dart:17,21,28,29`
   и `tool/doc_snippets.py:1806`. Порядок важен: этот проход делается
   **после** переименования файлов из пункта 1 (класс уже называется
   `Solo`), а не смешивается с отдельным превращением старого `Solo`
   в `SoloStream` — это два разных идентификатора, и обращение с ними
   как с одной заменой перепутает то, что было `SoloBase`, с тем, что
   было `Solo`. `dart analyze`/`flutter analyze` ловят всё пропущенное:
   имя `SoloBase` перестаёт резолвиться.

**Проверка шага:** `dart analyze` без единого info в `solo` и его примере;
`flutter analyze` в `flutter_solo`; `dart test` — числа читаются на месте
свежим прогоном, а не переносятся из спеки или из этого плана.

**Сделано, и предположение о трёх сторожах не подтвердилось.** Из трёх пунктов
критерия «Механика» два действительно уже под тестами (`close_test.dart`):
стрим закрывается после движка, повторный `close` отдаёт ту же future. Третий —
про порядок в `with` — **новое поведение этой самой правки**, и до неё
сторожить было нечему: миксина не существовало. Зелёный прогон после переноса
доказывает, что рефакторинг собрался, а не что `SoloStream` действительно
на что-то влияет. Написан `test/solo_stream_test.dart`: сосед `_Bomb`, чей
`publish` зовёт `super` и потом бросает, в одном порядке
(`with SoloStream, _Bomb`) отдаёт стриму событие перед броском, в другом
(`with _Bomb, SoloStream`) — нет. Отдельно проверено мутацией: без
`with SoloStream<TestState>` у `TestSoloStream` падают ровно те же три места,
что нашёл зонд шага 0 (`close_test.dart`, `sequential_test.dart`), и ничего
больше. `solo`: 579 (было 577).

**Найдено по дороге, не в исходном списке.** Фикстура `flutter_solo`
`_StreamController` (`solo_builder_test.dart`) заявляла в комментарии «carries
a `stream`» — после правки уже нет, только «не `ValueListenable`» осталось
истиной. Переименована в `_PlainController`, комментарий и название теста
поправлены. `solo_selection_test.dart:28` из того же пункта спеки при чтении
оказался без ложной посылки — `_PlainController` там ничего про стрим
не утверждает, и трогать нечего.

**Стенды остаются красными до шага 2, и это ожидаемо.** `tool/doc_snippets.py`
собирает `vs-bloc.md` в реальные пакеты,
а `PlayerController`/`ReportController` там всё ещё без `with SoloStream` —
фрагменты получат его только в шаге 2. Прогонять
`doc_snippets.py`/`accumulation_snippets.py`/`check_traces.py` как проверку
шага 1 не нужно: зелёными они станут только после шага 2, и это не сигнал
регресса, а порядок работы. Шаг 1 и шаг 2 не проверяются независимо — план
об этом не должен создавать впечатление, что проверяются.

## Шаг 2: документы, отдельный коммит

Ровно по списку спеки, раздел «Документы — по утверждениям, а не по именам
файлов»:

- **README обоих пакетов** — `solo`: первый пример на `addListener` (решение
  владельца 2026-09-16 по вопросу 2), `SoloStream` — отдельным примером ниже;
  абзац про `profile.stream` переезжает туда же. `flutter_solo`: «There is no
  `stream` on this controller…» и соседние фразы переворачиваются;
- **`doc/state.md`** — таблица трёх типов, `Logged extends SoloBase<S>`,
  «`Solo` is this override with a broadcast `StreamController`», раздел «A
  delivery of your own», `Camera` получает `with SoloStream`;
- **`doc/errors.md`, `doc/testing.md`** — сигнатуры `SoloBase.…`,
  переименование без смены сути;
- **`doc/flutter.md`** — «a `Solo` with its stream, or a `SoloBase` of your
  own» переворачивается;
- **`doc/vs-bloc.md`** — строка таблицы
  `| state, stream | currentState, stream |` (стрим — опция, не умолчание);
  `PlayerController`, `ReportController` получают `with SoloStream`,
  `tool/doc_snippets.py` не трогает `.stream`;
- **`doc/children.md`** — поле `final Solo<Session> session` →
  `SoloStream<Session>`;
- **русские копии всех перечисленных**, построчно, `check_translations.py`
  сверяет заголовки, число блоков и код;
- **`CHANGELOG.md`** обоих пакетов, нерелизные разделы: восемь упоминаний
  у `solo`, семь у `flutter_solo`, плюс `flutter_solo/CHANGELOG.md:69-75`
  сворачивается в новую запись, а не переименовывается;
- **`docs/architecture.md`** — пять мест (25-26, 113, 267, 303, 310) и абзац
  27-30 «братья, а не цепочка» — переписывается по сути, не по имени;
- **`docs/conventions.md:51`**, **`docs/handoff.md`** — по имени;
- **проза «по слову `Solo`, а не только `SoloBase`»** — из раздела рисков
  спеки: `solo_base.dart:22`, `solo_listenable.dart:8`, `doc/state.md:131`,
  `:168`, `doc/flutter.md:97`, `flutter_solo/README.md:181`, `:392`,
  `docs/architecture.md:113`, `vs-bloc.md:43`, `:49` — ссылки на `[Solo]`,
  сменившие смысл со «стрим» на «база»;
- **шапка `2026-09-12[4]-listenable-on-base-report.md`** помечается
  пересмотренной — критерий «Записи» спеки.

**Проверка шага:** `check_translations.py`, `check_line_width.py`,
`check_doc_shape.py`, `reflow.py --check`, оба стенда (`doc_snippets.py`,
`accumulation_snippets.py`) вместе с `check_traces.py`, `dart doc` без
предупреждений о нерезолвящихся ссылках, сборка сайта.

## Не входит в план

Версии в `pubspec.yaml` не трогаются — обе правки ломающие и лягут под уже
существующие записи `## Unreleased`. Публикация — отдельное поручение, как
и всегда.
