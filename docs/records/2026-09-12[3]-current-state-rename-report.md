> **Состояние на 2026-09-12:** сделано и смержено.
> **Что это:** отчёт о переименовании `SoloBase.state` в `currentState`
> и об объяснении этого имени в README.
> **Связанные записи:** `2026-09-02[1]-solo-design.md`.

# `currentState`: чтобы `state` в теле не компилировался

Владелец спросил, как сделать так, чтобы разработчик не ошибался и не
писал `state` вместо `ctx.state`, и из четырёх предложенных способов
выбрал один: убрать имя из области видимости, с объяснением в README,
почему `currentState`, а не `state`.

## Что было измерено до правки

Черновой пакет с путевой зависимостью на `packages/solo`, `dart analyze`:

- `state` в теле задачи компилировался молча — и при `run<St, void>`,
  и при `run<Ready, void>`;
- `externalSetState(...)` в теле тоже компилируется: он `@protected`,
  а тело — замыкание внутри метода наследника;
- ловился ровно один случай: тело берёт член, который есть только у `W`.
  `state.free` при `run<Ready, void>` не собирается
  (`undefined_getter`), `print(state)` собирается. То есть защита была
  только там, где `W` уже `S`, и только если тело читает узкое поле.
  В образце из README (`run<ProfileState, String>`) её не было вовсе.

Цена ошибки: `ctx.state` — чекпойнт (отменена, `keepWhile` перестал
держать → `Cancelled`), `state` — обычное чтение. Тело после отмены идёт
дальше до ближайшего `emit` или `wait`, и всё, что оно успеет сделать
наружу, уже сделано.

## Правка

`SoloBase.state` → `SoloBase.currentState`. Больше ничего: чтения через
контекст (`ctx.state`, `ctx.stateAs`), параметры `state` у `canStart`,
`keepWhile`, `onError`, `onCancel` и `externalSetState` не тронуты.
`SoloListenable.value` остался и теперь отдаёт `currentState`;
переименовать его нельзя — имя требует `ValueListenable`.

Устаревшего синонима нет намеренно. `@Deprecated('...') S get state` в
теле задачи по-прежнему компилировался бы — то есть дыра, ради которой
всё и делалось, осталась бы открытой, а предупреждение сыпалось бы в
первую очередь на законные внешние чтения.

Остаточная дыра одна: `value` у `SoloListenable` виден в теле так же,
как был виден `state`, и `ctx.emit(value.copyWith(...))` соберётся. Имя
не похоже на `ctx.state` настолько, чтобы его набрали по привычке, но
закрыть эту дыру переименованием нельзя — только линтом, если однажды
заведём.

## Проверка правки

Тем же черновым пакетом, после правки:

```
error - bin/main.dart:21:15 - Undefined name 'state'. - undefined_identifier
error - bin/main.dart:34:11 - The getter 'state' isn't defined for the
        type 'Ctl'. - undefined_getter
```

Первая строка — ошибка в теле задачи, ради которой работа затевалась;
вторая — внешнее чтение `c.state`, то самое ломающее изменение.
`ctx.state` и `currentState` рядом компилируются.

## Объяснение имени

Новая секция README обоих языков — «Why `currentState` and not `state`»
и «Почему `currentState`, а не `state`» — стоит сразу за «Быстрым
стартом», где читатель впервые видит `profile.currentState`. Показывает
фрагмент с обоими чтениями рядом: снимок чужого контроллера
(`session.currentState`) и собственное состояние задачи (`ctx.state`), —
и говорит, почему обычное чтение не названо `state`.

Тот же довод короче стоит в дартдоке `currentState` и в
`doc/state.md`. Законное чтение чужого контроллера из тела — не выдумка
для примера: оно уже было в `doc/children.md`, где экран читает сессию.

## Что изменилось в дереве

| Файл | Что |
| --- | --- |
| `lib/src/solo_base.dart` | геттер и его дартдок |
| `lib/src/solo.dart`, `flutter_solo/lib/src/solo_listenable.dart` | ссылки в дартдоке, `value` отдаёт `currentState` |
| тесты и пример | 71 чтение контроллера |
| `README.md`, `README.ru.md` пакета `solo` | новая секция и два чтения |
| `doc/state.md`, `testing.md`, `children.md`, `flutter.md`, `vs-bloc.md` | чтения и прозаические упоминания |
| `flutter_solo/README.md` и перевод | строка таблицы про `value` |
| `docs/architecture.md` | `state` движка |
| оба `CHANGELOG.md` | запись `**Breaking:**` |

Переводы правились в том же коммите.

## Гейт

- `dart analyze` чист в `solo`, `flutter_solo` и примере;
- `dart test` — 492 в `solo`, 9 в примере; `flutter test` — 37;
- `dart format` — 0 изменённых в обоих пакетах;
- `dart doc --dry-run` — 0 предупреждений, 0 ошибок в обоих;
- `check_translations.py` — 20 пар без расхождений;
- `check_doc_shape.py`, `check_line_width.py` — чисто;
- `build_site.py` — 42 страницы.
