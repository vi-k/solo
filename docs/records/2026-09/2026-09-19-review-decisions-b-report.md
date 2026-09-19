# Решения по ревью, волна B: `flutter_solo`

> **Состояние на 2026-09-19:** сделано, правки в `main`.
> **Что это:** отчёт о второй из четырёх волн по решениям владельца на остаток
> ревью — `changed:`, `SoloSelection.from`, один `SoloSelector` над `Solo`,
> реэкспорт `ValueListenable` и переезд страницы о Flutter.
> **Связанные записи:** `2026-09-19-solo-project-review.md` (раздел «Решения
> владельца»), `2026-09-19-review-decisions-a-report.md`.

Владелец ответил «ок» на волну B. В неё вошло всё, что по решениям лежит
в `flutter_solo`: M9, M14, слияние двух селекторов, реэкспорт `ValueListenable`
и L9. Каждая правка кода закрыта сторожем, каждый сторож проверен мутацией;
страница и README держатся стендом.

| Решение | Где | Сторожа |
| --- | --- | --- |
| M9, `changed:` | `SoloSelection`, `select`, `SoloSelector` | 1 |
| M14, `SoloSelection.from` | `SoloSelection` | — |
| один `SoloSelector` над `Solo` | `SoloSelector`, без `SoloSelectBuilder` | 8 |
| без реэкспорта `ValueListenable` | `flutter_solo.dart` | — |
| L9, страница о Flutter | `doc/mixins.md`, README, стенд, сайт | стенд |

## Что из этого ломающее

`SoloSelection`, `SoloSelector`, `SoloSelectBuilder`, `SoloBuilder`,
`SoloSelection.of` и `compare` появились после `0.2.0`: в выпуске
`flutter_solo` был один `SoloListenable`. Поэтому переименования правят пункты
«Add» в `## Unreleased`, а не добавляют ломающие. Ломающий пункт один —
реэкспорт `ValueListenable`: он был в `0.2.0`. `package:flutter/widgets.dart`
отдаёт `Listenable`, `ValueNotifier` и `ChangeNotifier`,
но не `ValueListenable`, так что файлу, где тип назван по имени, теперь нужен
свой импорт `package:flutter/foundation.dart`. Таких нашлось два:
`solo_listenable_test.dart` и драйвер базового класса на стенде.

## M9 и M14

`compare` стал `changed` везде, где был: в конструкторе `SoloSelection`,
в `from`, в `select` и в виджете. Смысл прежний — `true` значит «изменилось».
Комментарий-напоминание в `solo_selection_test.dart` и оговорка «`true` means
changed» в README убраны: имя говорит это само. Мутация, которая читает ответ
как равенство, будит 26 тестов в двух файлах.

`SoloSelection.of` стал `from` и остался статическим методом,
а не конструктором: конструктор берёт параметры типа своего класса, а класс
оставляет `S` без границы, тогда как `Solo` требует `S extends Object`. Это
сказано в dartdoc метода.

## Один `SoloSelector`

`SoloSelector` принимает `solo:` — любой `Solo`, с `SoloListenable` или без —
и строит выборку через `SoloSelection.from`. От прежнего `SoloSelector` у него
dartdoc: зачем выборку держать и почему селектор сравнивается по идентичности.
От `SoloSelectBuilder` — сравнение контроллеров по идентичности и тип
`S extends Object`. Чужой `ValueListenable`, не контроллер, выбирается через
`SoloSelection` и `ValueListenableBuilder`; это сказано в dartdoc виджета
и в changelog.

Тесты двух виджетов, по девять в каждом файле, слиты
в `solo_selector_test.dart`: тринадцать тестов над `Solo`. Одинаковые у двух
файлов слились в один. Прежний тест над контроллером с `SoloListenable` остался
отдельным: такой контроллер принимается так же. Добавлен сторож на `changed`,
переданный родителем при перестроении: без него мутация, снимающая эту проверку
в `didUpdateWidget`, проходит.

```text
solo compared by nothing -> 1 caught
solo compared by == -> 1 caught
    a new controller is followed even when == calls it the old one
selector not compared -> 3 caught
changed not compared -> 1 caught
    a changed handed over in its place answers instead
changed not handed on -> 3 caught
selection made on every rebuild -> 1 caught
    a parent rebuild with the same controller, selector and changed keeps the value the answer is given from
dispose keeps the listener -> 2 caught
old selection keeps the listener -> 3 caught
changed read as equality -> 26 caught
```

## L9: страница о Flutter

`packages/solo/doc/flutter.md` переехала
в `packages/flutter_solo/doc/mixins.md`, перевод —
в `docs/ru/flutter_solo/mixins.md`. Имя сменилось вместе с содержимым. Вводный
обход страницы повторял README `flutter_solo`: как подмешать `SoloListenable`,
как экрану владеть контроллером, `ValueListenableBuilder`, ожидание исхода,
выбор одного значения. Он же советовал `SoloSelectBuilder` там, где README
советовал `SoloSelector`, — это и был спор из L9. Обход убран, спор ушёл вместе
со вторым виджетом. Две вещи обхода, которых в README не было, переехали туда:
чем `SoloBuilder` отличается от `ValueListenableBuilder` и что функцию выборки
держат в поле или в `static`. Остались три раздела — оба способа доставки
вместе, экран на стриме и базовый класс без Flutter. Все три о том, какие
миксины у контроллера и где они стоят, отсюда имя. Базовый класс теперь стоит
на модели README `flutter_solo`, `Profile` и `Empty`, а не на быстром старте
`solo`.

README `flutter_solo` ссылается на страницу из раздела о билдерах. Строки
таблиц в README `solo` ведут в README `flutter_solo`, а рецепт про лишние
перестроения называет `SoloSelector` вместо `select` на `SoloListenable`. Пункт
changelog `solo` о переезде справки в `doc/` больше не числит `flutter.md`
и говорит, куда ушёл раздел о Flutter. Пункт о `doc/flutter.md` в разделе
о слушателях снят.

Стенд `tool/flutter_snippets.py` читает новый путь. Драйвер вводного экрана
ушёл вместе с разделом. Быстрый старт README `solo` строился как код,
на который страница ссылалась. Он остался отдельным файлом `quick_start_test`:
другого стенда у него нет. Блок билдеров в README теперь одно выражение, и тест
на него — один `SoloBuilder`. Гейт, `check_translations.py`,
`docs/conventions.md` и боковое меню сайта в `site/astro.config.mjs` переведены
на новый путь.

## Что прошло целиком

| Проверка | Результат |
| --- | --- |
| `flutter_solo`: `dart format`, `flutter analyze`, `flutter test`, `dart doc --dry-run` | без изменений, чисто, 97 зелёных, 0 предупреждений |
| пример `flutter_solo` | чисто, 4 зелёных |
| стенд Flutter | анализ чисто, 19 зелёных, 4 трассы на месте |
| пять документных проверок | зелёные |
| сайт: `tool/build_site.py` и `npm run build` | 43 страницы, `mixins` в обоих языках |

Код `solo` и `async_job` в этой волне не менялся — в `solo` правились только
README и changelog, — поэтому их наборы и стенды `vs-bloc.md`
и `accumulation.md` не гонялись.

## Чего эта работа не трогала

Волна C — защищённые `job`, `add`, `run`, `collect`, `accumulate`. Волна D —
Low без решений, пробел модели Usage в README `flutter_solo` и предложения
сверх находок. Карта модулей в `docs/architecture.md` называет у `flutter_solo`
только `SoloListenable`: неполна, но коду не противоречит, оставлена как есть.
