> **Состояние на 2026-09-12:** сделано и смержено.
> **Что это:** отчёт о переносе `SoloListenable` с `Solo` на `SoloBase`:
> контроллер Flutter остался без стрима.
> **Связанные записи:** `2026-09-02[1]-solo-design.md`,
> `2026-09-12[3]-current-state-rename-report.md`.

# `SoloListenable` на `SoloBase`: виджету нужен только интерфейс

Владелец спросил, почему `SoloListenable` написан на `Solo`, а не на
`SoloBase`, и на ответ сказал: «в `SoloListenable` stream не нужен,
только интерфейс `ValueListenable`».

## Что было и почему

Решение 2026-09-02, `2026-09-02[1]-solo-design.md`:

> Цепочка линейная, а не вилка от базы: Flutter-контроллер сохраняет
> `stream` (`where`, `distinct`, подписка в `initState` ради навигации по
> `Failed`) и подходит везде, где ожидается `Solo`. Цена — один
> `StreamController` на экземпляр.

Оба довода сняты решением владельца: виджет перестраивается по `value`,
а результат операции ждут через её `Job`, и второй канал доставки ему ни
к чему.

## Что стало

`SoloListenable<S> extends SoloBase<S> implements ValueListenable<S>`.
Ушло ровно то, что давал `Solo`:

- `StreamController.broadcast()` на экземпляр — поле, а не ленивое
  значение, так что его нёс и тот контроллер, у которого стрим никто не
  спрашивал;
- `add` на каждое изменение состояния;
- `_controller.close()` в цепочке закрытия.

Своя цепочка `_closed` у `SoloListenable` осталась: она нужна не ради
стрима, а ради сброса слушателей после `super.close()` и ради того,
чтобы повторный `close` из хука или слушателя получил тот же future.

Ломающее: контроллер больше не подходит туда, где объявлен `Solo<S>`.
Общий тип для обоих — `SoloBase<S>`; в `CHANGELOG` это сказано прямо.

## Тесты

Тест `listeners fire now, the stream on the next microtask` проверял два
факта сразу, и половина его предмета исчезла. Заменён на `listeners fire
inside the change, not on a microtask`: слушатель зовётся внутри
изменения, до возврата из `set` и до ближайшей микротаски, — то же
утверждение о синхронности, но без стрима.

Мутация: `_listeners.notify(this)` заменён на
`scheduleMicrotask(() => _listeners.notify(this))`. Падает в том числе
новый тест — и с ним ещё семь, от подписок до проекций. Файл возвращён
копией из каталога вне дерева, набор снова зелёный.

## Гейт

- `dart analyze` чист в `flutter_solo`, `flutter analyze` — в его
  примере; `solo` не тронут;
- `flutter test` — 37;
- `dart format` — 0 изменённых;
- `dart doc --dry-run` — 0 предупреждений, 0 ошибок;
- `check_translations.py` — 20 пар без расхождений;
- `check_doc_shape.py`, `check_line_width.py` — чисто;
- `build_site.py` — 42 страницы.
