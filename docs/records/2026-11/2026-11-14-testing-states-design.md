> **Состояние на 2026-11-14:** форма раздела одобрена владельцем в переписке
> («Форму одобряю, пиши короткий дизайн»); дизайн ждёт его одобрения, ничего
> не построено.
> **Что это:** короткий дизайн раздела «The states on the way» страницы
> `packages/solo/doc/testing.md` — тест, который сверяет все состояния
> задачи, а не одно последнее.
> **Связанные записи:** `2026-11-07-bloc-vs-solo-debate-report.md`.

# Раздел «The states on the way» страницы testing

## Зачем

Владелец 2026-11-14 решил не заводить пакет `solo_test`, решение 162
`docs/settled.md`. Из того, что пакет дал бы простому тесту контроллера,
на странице нет одного: как увидеть последовательность состояний одного
контроллера. Сейчас состояния видны только через `Journal` — глобальный
наблюдатель со сбросом в `addTearDown`, а он учит порядку задач, а не этому.
Раздел закрывает эту дыру рецептом, без нового API.

Цель: читатель, которому важно промежуточное состояние (`Loading`), пишет тест,
который его ловит. Не цель: обёртка вроде `soloTest`, новые члены API, правка
`ProfileController` страницы.

## Что показал зонд

Зонд гонял `ProfileController` страницы (из `testing_page_fixtures.dart`), его
копию с `SoloStream` и копию без строки `ctx.emit(const Loading())`, на удачной
загрузке и на ошибке `ApiException('no network')`; 14 из 14 зелёные.

| Как тест смотрит | Удача | Ошибка |
|---|---|---|
| `addListener` до вызова, затем `await done` | `Loading, Loaded` | `Loading, Failure` |
| `stream` до вызова, затем `await done` | `Loading, Loaded` | `Loading, Failure` |
| `stream` и `await value` / `close(drain)` | то же | то же |
| `expectLater(stream, emitsInOrder([...]))` | проходит | проходит |
| `fakeAsync`, `elapse(20 мс)`, оба способа | полный список | полный список |
| только `currentState`, без `emit(Loading())` | `Done`, `Loaded` | `Failed`, `Failure` |

Слушатель получает всё, включая состояние обработчика `ifFailed`, к моменту,
когда завершается `done`. `stream` доставляет на следующей микрозадаче, но тоже
раньше `done`. Ловушка одна: проверка последнего состояния не видит, что
промежуточного не было.

Тело зонда для удачи и `addListener`:

```dart
final profile = ProfileController(FakeProfileApi());
final states = <ProfileState>[];
profile.addListener(() => states.add(profile.currentState));
await profile.load().done;
// states: Loading, Loaded
await profile.close();
```

## Подходы

- **`addListener`** (выбран) — есть у любого контроллера, без подмешивания,
  локален тесту и не требует сброса.
- **`stream` с `emitsInOrder`** — то же самое, но нужен `SoloStream`, которого
  у `ProfileController` страницы нет; в разделе — одной фразой как вариант для
  контроллера, у которого он уже есть.
- **`Journal`** — уже на странице, но глобальный и про порядок задач; второй
  раз его не показываем.

## Раздел

Форма страницы: требование, «### The first attempt», ответ.

- **Место.** Сразу после «Awaiting a job», в группе тестов, которые ждут.
  Вступление получает девятый пункт в первой группе; «eight sections» — «nine»,
  «Four are for a test that awaits» — «Five», «The first four sections below
  await; `fakeAsync` starts with the fifth» — с пятью и шестым. То же
  в переводе и в dartdoc сторожа `testing_rakes_test.dart`, где сказано
  о первых четырёх разделах.
- **Требование.** Пока имя загружается, экран показывает `Loading`; тест должен
  это поймать.
- **Первая попытка.** Тест «load fills in the name» из «Awaiting the outcome»
  как есть: `await done`, затем `currentState`. Под ним — тот же контроллер без
  `ctx.emit(const Loading())`, и тот же тест зелёный. Это не выдуманная ошибка:
  так страница сама проверяет загрузку двумя разделами выше.
- **Ответ.** `addListener` до вызова собирает состояния, тест сверяет
  `[isA<Loading>(), isA<Loaded>()]`; на ошибке — `Loading, Failure`, потому что
  обработчики `ifFailed` и `ifCancelled` успевают до `done`. Одной фразой:
  `stream` контроллера с `SoloStream` даёт то же через `emitsInOrder`; под
  `fakeAsync` список полон после `elapse`.

## Ограничения

- Код страницы дословно лежит в `test/support/testing_*.dart` и сверяется
  `testing_rakes_test.dart` (`page_code.dart`); новые листинги — туда же,
  по тем же правилам. Контроллер без `Loading` — фикстура рядом
  с `testing_page_fixtures.dart`.
- Сторож первой попытки: в отличие от остальных, она не падает, а проходит
  на контроллере без `Loading`; сторож держит именно это, а ответ на том же
  контроллере падает.
- Перевод `docs/ru/solo/testing.md` тем же коммитом; `check_translations.py`;
  `humanizer--ru` только `ERROR`.
- Скилл `doc-reader`: о зонде и «измерениях» в тексте страницы ни слова.
- Справочник API и `CHANGELOG.md` не меняются: API не меняется. Выпуска нет.

## Что остаётся строителю

Имена фикстуры и тестов, точные формулировки прозы, разложение по файлам
`test/support/` в рамках правил выше.
