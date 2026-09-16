> **Состояние на 2026-09-16:** план написан, к реализации не приступали.
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
правки стрима не будет («Миксин ей не даётся» — решение уже в спеке). Три
вызова читают `solo.stream` через `runSolo`: `close_test.dart:17`,
`close_test.dart:183`, `sequential_test.dart:109`. Им заводится параллельная
пара: фикстура
`TestSoloStream extends Solo<TestState> with SoloStream<TestState>` рядом
с `TestSolo` и функция `runSoloStream`, тем же телом, что `runSolo`, только
с этим типом — по образцу имени `PlainSolo`/`Solo`, без придумывания новой
схемы именования.

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
5. **`solo_base_test.dart`** переименовывается (новое имя решить по
   содержимому файла на месте — сама спека имя не называет), тест
   `'a SoloBase subclass without a stream compiles and reads state'`
   переименовывается по тому, что он теперь проверяет: без стрима —
   любой подкласс, а не особый случай.
6. **`async_job`**, дартдок: `job_base.dart:315` и `:888` называют
   `SoloBase.debug`/`SoloBase.errorHandler` — правятся на `Solo.…`. Это
   правка нижнего пакета для верхнего дартдока, без смены поведения;
   `pubspec_overrides.yaml` уже стоят.

**Проверка шага:** `dart analyze` без единого info в `solo` и его примере;
`flutter analyze` в `flutter_solo`; `dart test` — все наборы на прежних числах
(`solo` от 577, пример 9, `flutter_solo` от 87) плюс
`TestSoloStream`/`runSoloStream` не меняют число тестов, только их внутренний
тип. Три сторожа из критериев приёмки спеки («Механика»): стрим закрывается
после движка; повторный `close` отдаёт ту же future; сосед по `with`,
не зовущий `super.publish`, глушит стрим сверху и не глушит снизу — уже есть
в наборе `close_test.dart`/`hooks_test.dart` по замерам ревью, отдельно писать
не нужно, только убедиться, что они остались зелёными после переноса.

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
