> **Состояние на 2026-09-12:** сделано и смержено.
> **Что это:** отчёт о втором импорте `flutter_solo` под расширения
> `select` и `listen` и о виджете `SoloSelector`.
> **Связанные записи:** `2026-09-11[10]-selection-report.md`,
> `2026-09-11[12]-subscription-report.md`.

# Расширения — отдельным импортом, выборка — виджетом

Владелец сказал два: «расширения, связанные с listenable надо отдельным
экспортом» и «ты не стал брать `ListenableSelector` из `scopo`, а он
позволяет не сохранять `select` в стейте, чтобы им пользоваться».

## Что поменялось в раскладке

Библиотек стало две.

| Импорт | Что даёт |
| --- | --- |
| `package:flutter_solo/flutter_solo.dart` | `SoloListenable`, `SoloSelection`, `SoloSelector` и весь `solo` |
| `package:flutter_solo/listenable.dart` | методы `select` и `listen`, `SoloSubscription`, `SoloSubscriptions` |

Подписки уехали во вторую не за компанию: конструктор
`SoloSubscription._` приватный, и единственный способ её получить — это
`listen`. Класс без своего метода в первой библиотеке был бы виден и
непригоден.

## Расширения переехали на типы фреймворка

`2026-09-11[12]-subscription-report.md` объясняет, почему `listen` в
`flutter_solo` стоит на `SoloListenable`, а не на `Listenable`, как в
`scopo`: два расширения с одинаковым именем члена на один тип — ошибка
компиляции на каждом месте вызова, и проект владельца, где встретятся
оба пакета, перестал бы собираться. Частный тип побеждает общий, и
поэтому расширения сузили.

Отдельный импорт снимает причину целиком: столкнуться могут только те
расширения, которые оба внесены в файл, а вносит их теперь явный импорт.
Так что расширения разъехались обратно на типы фреймворка:

- `SoloListen on Listenable` — один метод вместо двух. Прежние
  `SoloListen on SoloListenable<S>` и
  `SoloSelectionListen on SoloSelection<S, T>` существовали только
  потому, что первый не покрывал второго;
- `SoloSelect on ValueListenable<S>`, и вместе с ним `SoloSelection`
  стала проекцией над любым `ValueListenable<S>`, а не над
  `SoloListenable<S>`. Внутри изменилось одно: `_source.state` стало
  `_source.value`, у контроллера это один и тот же объект.

Что из этого вышло сверх задуманного: проекция берётся из `ValueNotifier`
и из другой проекции — `name.select((it) => it.isEmpty)` сужает дальше.
Оба случая закреплены тестами.

Что осталось прежним: `select` — по-прежнему расширение, а не член
`SoloListenable`, и по той же причине. Контроллер списка со своим
`select(id)` не перестаёт собираться, потому что член класса всегда
побеждает расширение; тест «a select of its own wins over the extension»
на месте.

## SoloSelector

Виджет, который держит проекцию за того, кому её негде держать:

```dart
SoloSelector<Profile, bool>(
  listenable: controller,
  selector: (state) => state.canSave,
  builder: (context, canSave, _) => ElevatedButton(
    onPressed: canSave ? controller.save : null,
    child: const Text('Save'),
  ),
)
```

Тело `State` — три метода. `initState` строит `SoloSelection`,
`didUpdateWidget` строит новую, если родитель передал другой
`listenable`, `selector` или `compare` (сравнение по идентичности:
спросить у одного замыкания, делает ли оно то же, что другое, нельзя), а
`build` отдаёт проекцию в `ValueListenableBuilder`.

Отмены в `didUpdateWidget` нет, и это отличие от `scopo`, а не недосмотр.
У `scopo` `select` возвращает подписку, и её надо снимать руками. Здесь
проекция — `ValueListenable`, слушатель у неё ровно один, и это слушатель
`ValueListenableBuilder`; он сам снимает его со старой проекции, когда
переходит на новую, и в `dispose`. Потерявшая последнего слушателя
проекция отписывается от источника — это её собственный контракт с
прошлой работы. Проверено тестом «the listenable is let go when the
widget goes»: после ухода виджета изменение состояния не вызывает
селектор ни разу.

Имя не повторяет `ListenableSelector` из `scopo` — по той же причине, по
которой `SoloSubscription` не повторяет `ListenableSubscription`:
одинаковые имена типов из двух импортов конфликтуют на самом имени.

## Проверки

`flutter_solo`: анализ чистый, 37 тестов (было 29), формат без
изменений, `dart doc --dry-run` — 0 предупреждений и 0 ошибок. Пример:
анализ чистый. `solo` и `async_job` не затронуты. Переводы: двадцать пар
без расхождений, форма документов и ширина в норме, сайт собирается —
42 страницы.

Восемь новых тестов: пять на виджет (перестройка только на изменение
выборки, `child` мимо перестройки, свой `compare`, замена селектора,
отпускание источника) и три на расширенных получателей (`ValueNotifier`
как источник, проекция из проекции, `listen` на `ValueNotifier`).

Две мутации, обе поймались: снятая из `didUpdateWidget` проверка
селектора уронила «a selector handed over in its place picks instead»,
`child: null` вместо `child: widget.child` — «the child is handed back
untouched».
