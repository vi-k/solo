> **Состояние на 2026-09-13:** план написан, к работе не брался.
> **Что это:** порядок работ по спеке
> `2026-09-13[2]-solo-listeners-design.md` — слушатели в ядре, `SoloBuilder`,
> `SoloSelectBuilder` и `SoloSelection.of`. Решения приняты в спеке; здесь
> только последовательность, файлы, тесты и проверки.
> **Связанные записи:** спека `2026-09-13[2]-solo-listeners-design.md`,
> ревью `2026-09-13[3]` … `[8]`.

# План: слушатели в ядре и билдеры

Владелец взял все три новых имени: `SoloBuilder`, `SoloSelectBuilder`,
`SoloSelection.of`. Всё, что ниже, — по спеке; расхождение с ней означает
ошибку плана, а не свободу исполнителя.

Работа идёт в неотпущенном наборе 0.3.0. Оверрайды в дереве стоят, публиковать
между шагами ничего не нужно.

## Шаг 1. Ядро: контейнер

**Файлы:** новый `packages/solo/lib/src/listeners.dart` (приватный для пакета,
чистый Dart, без Flutter), `packages/solo/lib/src/solo.dart` — не трогать.

Контейнер: на каждую регистрацию своя запись с признаком живости.

- `add(listener)` — новая запись в конец;
- `remove(listener)` — гасит **самую раннюю живую** запись этой функции
  и говорит, была ли такая;
- `notify(report)` — проход по снимку списка записей, погашенные по дороге
  пропускаются, добавленные по дороге в этот проход не входят; каждый вызов
  изолирован, ошибка уходит в `report`;
- `isEmpty`, `clear`.

**Тесты** (`packages/solo/test/listeners_test.dart`, новый): порядок вызова;
две регистрации одной функции дают два вызова; `remove` снимает самую раннюю
живую; погашенная внутри прохода не вызывается; добавленная внутри прохода ждёт
следующего прохода; вложенный проход (`notify` изнутри `notify`) держит те же
три правила; бросивший слушатель не останавливает проход, его ошибка уходит
в `report`.

**Приёмка:** `cd packages/solo && dart analyze` без замечаний, `dart test`
зелёный.

## Шаг 2. Ядро: поверхность `SoloBase`

**Файл:** `packages/solo/lib/src/solo_base.dart`.

- поле одно: `null`, пока никто не подписался; контейнер после первой подписки;
  сигнальное значение после окончательного сброса;
- `addListener`, `removeListener` — публичные, сигнатура `void Function()`;
  после сброса `addListener` **ничего не регистрирует и не удерживает**,
  исключения не бросает;
- `@protected bool get hasListeners`;
- `@protected void onListenerError(Object error, StackTrace stackTrace)` —
  по умолчанию `Zone.current.handleUncaughtError`; вызывается через ту же
  изоляцию, что и хуки (`_callHook`), так что его собственная ошибка тоже
  уходит в зону и проход продолжается;
- уведомление — в `SoloBase.publish`, до тела наследника (наследник обязан
  звать `super.publish` первым, как `Solo` и делает);
- сброс — в `_finishClose`, **после**
  `_callHook(() => observer?.onClose(this))`.

**Тесты** (`packages/solo/test/listeners_base_test.dart`, новый):

- слушателя зовут на каждое изменение, в порядке подписки, синхронно;
- ошибка слушателя уходит в зону, проход продолжается **и переоценка правил
  после изменения всё равно происходит** — задача с нарушенным `keepWhile`
  получает `Cancelled(rules: …)`;
- ошибка `onListenerError` — то же самое;
- вложенный `externalSetState` из слушателя: трасса совпадает
  с `[publish:1, A:1, cancelled, A-return, B:2, publish:2, A:2, B:2]` из спеки;
- во время `close(mode: SoloCloseMode.drain)` уведомления идут, подписка
  работает;
- подписка из `observer.onClose` слышит синхронный `externalSetState` того же
  хука и сбрасывается сразу за ним;
- после сброса не уведомляют; `addListener` не удерживает колбэк (проверяется
  через `hasListeners` наследника и через живость объекта в замыкании —
  достаточно `hasListeners`);
- `close()` из слушателя не обрывает текущий проход;
- контроллер без подписчиков: `publish` работает, поля контейнера нет.

**Приёмка:** те же две команды в `packages/solo`; плюс
`cd packages/solo/example && dart test`.

## Шаг 3. `flutter_solo`: `SoloListenable` худеет

**Файл:** `packages/flutter_solo/lib/src/solo_listenable.dart`.

Убрать собственный список, `_dropped`, `addListener`, `removeListener`,
`publish` и **весь `close`**: базовый `close` уже возвращает один и тот же
future и сам сбрасывает слушателей. Остаётся `value`, объявление
`implements ValueListenable<S>` и переопределённый `onListenerError` —
`FlutterError.reportError` с `library: 'flutter_solo'`, как сейчас.

**Здесь же меняется наблюдаемое поведение:** микротаска, запланированная
из `observer.onClose`, больше никого не уведомляет (сегодня сброс идёт
в `.then`). Это записывается в `CHANGELOG` шагом 7 и закрывается тестом.

**Тесты** (`packages/flutter_solo/test/`): `SoloListenable` по-прежнему годится
для `ValueListenableBuilder`; ошибка слушателя уходит
в `FlutterError.reportError` и проход продолжается; микротаска из `onClose`
не уведомляет — тест на новую границу.

## Шаг 4. `flutter_solo`: контейнер выборок

**Файл:** `packages/flutter_solo/lib/src/listeners.dart`.

Тот же счёт регистраций, что в шаге 1, плюс **изоляция отчётчика**: если
`FlutterError.reportError` бросил, проход не обрывается и остальные слушатели
этой выборки получают своё.

Дублирование с ядром намеренное: ядро не может импортировать Flutter. Сказать
это комментарием в обоих файлах.

**Тесты:** те же случаи, что в шаге 1, плюс бросающий отчётчик не обрывает
проход самой выборки.

## Шаг 5. `flutter_solo`: `SoloSelection`

**Файл:** `packages/flutter_solo/lib/src/solo_selection.dart`.

- статическая фабрика `static SoloSelection<S, T> of<S extends Object,
  T>(SoloBase<S> solo, T Function(S state) selector, {bool Function(T,
  T)? compare})`; внутри — приватный источник `ValueListenable<S>` над
  контроллером, создаваемый **один раз, внутри выборки**;
- порядок `addListener` по спеке: регистрация; для первой — база сравнения,
  затем подписка на источник; после подписки перечитать и, если значение
  уехало, обновить базу и уведомить **микротаской**; если подписка бросила —
  снять только что добавленную регистрацию и пробросить ошибку, не оставив
  подписки.

**Тесты:** первое значение лениво подключённого источника доходит до виджета
(`ValueListenableBuilder` показывает его, а не прежнее); бросившая подписка
не оставляет ни регистрации, ни подписки; `SoloSelection<int?, int>`
по-прежнему компилируется и работает; `SoloSelection.of` живёт на `Solo`
и на `SoloListenable`.

## Шаг 6. `flutter_solo`: `SoloBuilder` и `SoloSelectBuilder`

**Файлы:** новые `solo_builder.dart` и `solo_select_builder.dart`, экспорт
из `packages/flutter_solo/lib/flutter_solo.dart`. В `listenable.dart` нового
нет; второго `select` не добавлять.

Оба по спеке: состояние читается при подключении и кешируется;
`didUpdateWidget` сравнивает контроллеры по идентичности, переподписывается
и читает состояние нового; `dispose` снимает подписку; `child`
не перестраивается.

**Тесты:** перестроение на изменение; переподписка при смене контроллера;
снятие подписки в `dispose`; после закрытия контроллера новых уведомлений нет;
`SoloSelectBuilder` переживает перестроение родителя без пересоздания выборки
и без потери базы сравнения; подключение уже закрытого контроллера показывает
его состояние.

## Шаг 7. Документы, переводы, `CHANGELOG`

- `packages/solo/doc/state.md`, секция «A delivery of your own» — переписать:
  ядро доставку уже даёт, `publish` остаётся для доставки другого рода (стрим,
  сигнал, лог). Правило миграции со старого рецепта: свой список убрать,
  переопределения снять, а если они нужны — звать `super` первым
  и не публиковать состояние синхронно изнутри `addListener`. Перевод
  `docs/ru/solo/state.md` — тем же коммитом;
- `packages/solo/doc/flutter.md` и `packages/flutter_solo/README.md` (+
  `README.ru.md`): назвать `SoloBuilder` и `SoloSelectBuilder`;
- `packages/solo/CHANGELOG.md`, `## Unreleased`: **Breaking** — четыре новых
  члена на `SoloBase`, наследник с такими же именами перестанет
  компилироваться;
- `packages/flutter_solo/CHANGELOG.md`, `## Unreleased`: новые виджеты
  и `SoloSelection.of`; **Fix** — поздняя подписка больше не удерживает колбэк;
  отдельной строкой — смена границы доставки при закрытии (микротаска
  из `observer.onClose`).

## Проверки перед каждым коммитом

```sh
cd packages/solo        && dart analyze && dart test          # было 492
cd packages/solo/example && dart analyze && dart test         # было 9
cd packages/flutter_solo && flutter analyze && flutter test   # было 37
cd packages/flutter_solo/example && flutter analyze && flutter test
python3 tool/reflow.py --check && python3 tool/check_line_width.py
python3 tool/check_translations.py && python3 tool/build_site.py
python3 tool/doc_snippets.py   # стенд vs-bloc: 22 драйвера
```

Числа тестов — нижняя граница: они обязаны вырасти, а не упасть.

## Мутации

Каждая снимается по одной, и падать обязан именно её тест:

- убрать изоляцию вызова слушателя в ядре;
- убрать изоляцию `onListenerError`;
- убрать изоляцию отчётчика в контейнере `flutter_solo`;
- в `remove` гасить последнюю живую регистрацию вместо самой ранней;
- в проходе идти по живому списку вместо снимка;
- сбросить слушателей **до** `observer?.onClose`;
- в `SoloSelection.addListener` вернуть прежний порядок (подписка раньше
  регистрации);
- в `SoloSelectBuilder.didUpdateWidget` сравнивать `==` вместо `identical`
  на разных контроллерах одного типа.

## Чего план не делает

- не трогает `Solo.stream` и `SoloSelector` сверх правки контейнера;
- не добавляет `select` на `SoloBase`;
- не ужесточает границы `S` у существующих выборок;
- не публикует ничего на pub.dev.
