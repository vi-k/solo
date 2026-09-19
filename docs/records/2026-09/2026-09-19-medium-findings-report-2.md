# Пять Medium из ревью: вводный пример, README `flutter_solo` и `onClose`

> **Состояние на 2026-09-19:** сделано, правки в `main`.
> **Что это:** отчёт о правке M15, M16, M11, M10 и M6 из ревью — что было
> неверно, чем исправлено, чем закрыто и что нашлось по дороге.
> **Связанные записи:** `2026-09-19-solo-project-review.md`,
> `2026-09-19-medium-findings-report.md`, `2026-09-19-high-findings-report.md`.

Третья волна по ревью. Владелец назвал пять находок из шести, отложенных
до вычитки страниц, хотя ждать им было нечего: M15 и M6 лежат на уже вычитанных
`cancellation.md` и `state.md`, а M16, M11 и M10 — ошибки README, которые
от порядка вычитки не зависят. По M6 он выбрал хук `onClose` на `Solo`,
а не починку одного рецепта. Каждая правка закрыта сторожем, каждый сторож
проверен мутацией.

| Находка | Где | Правка | Сторожа |
| --- | --- | --- | --- |
| M15 | `doc/cancellation.md` | ресурс из `join` уходит в `dispose` | 2 |
| M16 | README `flutter_solo` | наблюдатель смотрит, отвечает `errorHandler` | уже был |
| M11 | README `flutter_solo` | модель дописана, у страницы стенд | 12 |
| M10 | README `flutter_solo` | проекция в поле пересобирается | 1 из 12 |
| M6 | `Solo`, `doc/state.md` | хук `onClose`, рецепт переехал в него | 5 |

## M15. Вводный пример, терявший ресурс

```dart
final handle = await ctx.join(
  device.open,
  dispose: (handle) => handle.close(),
);
```

Было `await ctx.join(() => device.open())` и `ctx.onDispose(handle.close)`
следующей строкой — ровно первая попытка `resources.md`. Отмена, принятая
во время открытия, выходит из `join` вместо значения, и до строки с `onDispose`
тело не доходит. После таблицы встал абзац, который говорит это прямо
и ссылается на разбор в `resources.md`; перевод тот же.

Сторожа — группа «the opening example» в `cancellation_rakes_test.dart`,
у `Device` появился `open()` с дескриптором, закрытие которого пишется в след.
Обе мутации пойманы, каждая своим тестом:

```text
the old two lines back -> 1 caught
    a handle opened under a cancellation is closed all the same
dispose turned into discard -> 1 caught
    a handle that reached the body is closed when the job ends
```

Второй тест держит выбор `dispose`, а не `discard`: `discard` оставил бы
дескриптор открытым у задачи, которая закончилась `Done`.

## M16. Наблюдатель, который якобы перехватывает ошибку

README говорил, что провал работы из `ctx.unattended` уходит в зону, «when
neither `onError` nor a `SoloObserver` took it». Наблюдатель `solo` только
смотрит; отвечает переопределённый `onError` или `Solo.errorHandler`.
Исправлены README, перевод и инвариант 4 в `docs/architecture.md` — там стояло
«если не задан ни наблюдатель, ни переопределение хука». Инвариант теперь
различает ядро, где отвечает наблюдатель задачи, и `solo`, где наблюдатель
только смотрит.

Нового сторожа нет: маршрут уже держит `zone_test.dart` — «a global observer
leaves the default route alone», и держит именно на `unattended`.

## M11 и M10. README `flutter_solo` и его стенд

**Стенд.** Вердикт ревью советовал стенд, а не одну правку модели, иначе
разойдётся снова. Своего генератора не понадобилось: `tool/flutter_snippets.py`
уже собирал `packages/solo/doc/flutter.md` в виджетные тесты задания `flutter`
гейта, и README встал туда же, файлом `readme_test.dart`. Одиннадцать блоков
Dart из двенадцати идут в него как написаны — вне стенда только одиночная
строка импорта в Install, которую повторяет Usage; обвязка даёт только то, что
страница считает читательским: `ProfileApi`, `FakeApi`, виджеты, которым
принадлежат `State`, и `_toast`. Двенадцать тестов: каждый раздел README
запускается и сверяется с тем, что о нём сказано.

**Модель.** `sealed class Profile` получила
`bool get canSave => this is Loaded`, контроллер — `save()`
на `run<Loaded, void>` с `ctx.join`. Это та модель, на которую страница и так
опиралась. Абзац после Usage объясняет сужение рабочего типа: в другом
состоянии `save` не стартует. Стенд это проверяет —
`Cancelled(rules: is not Loaded)` на пустом профиле.

**M10.** Рецепт с проекцией в поле держит `late SoloSelection<Profile, bool>`
и пересобирает её в `didUpdateWidget`, когда родитель передаёт другой
контроллер. Абзац под рецептом называет цену старой версии: разрешение
от старого контроллера, сохранение — в новый. Та же оговорка встала в dartdoc
`SoloSelection` (`solo_selection.dart`) и абзацем в раздел про `listen`:
подписка из `initState` тоже остаётся на старом источнике, а брать её заново
надо в новую группу — отменённая группа отменяет то, что ей передали.

Мутации:

```text
the old field recipe back -> 1 caught
    the selection in a field follows a new controller
the README from HEAD -> flutter analyze: 10 issues
    canSave and save are undefined
```

**Что нашлось по дороге.** Комментарий в разделе Outcomes говорил, что
`Cancelled` приходит и тогда, когда «a second tap while the first ran». Стенд
показал другое: `Policy.droppable` отдаёт второму нажатию первую задачу, и оба
получают `hello Ada Lovelace`. Комментарий исправлен в оригинале и переводе,
стенд держит оба случая — двойное нажатие и закрытый контроллер.

## M6. Хук `onClose`

```dart
_callHook(() => observer?.onClose(this));
_callHook(onClose);
```

У всех хуков наблюдателя был близнец на `Solo`, кроме `onClose`, поэтому уборку
домена вешали на переопределение `close` — и рецепт `state.md` делал это
`async`-методом, который на каждом вызове запускался заново и возвращал свой
future вопреки обещанию `close`. Теперь `Solo.onClose` зовётся в `_finishClose`
один раз, после наблюдателя и после последней задачи, пока `isFinished` ещё
ложен. Хук `void`, как его соседи: future, начатый в нём, `close` не ждёт.

Рецепт `Camera` в `state.md` переехал в хук —
`void onClose() => unawaited(_link.cancel())`, — абзац о порядке переписан
вокруг момента, а не порядка вызовов, в `vs-bloc.md` и `errors.md` хук назван
среди остальных, в `docs/architecture.md` — в инварианте 8.

Сторожа — четыре теста в `hooks_test.dart` и один
в `state_external_recipe_test.dart`, где `Camera` теперь тоже на хуке:

```text
drop the call -> 4 caught
call it after the listeners are gone -> 3 caught
call it on every close() -> 1 caught
    onClose comes once, after the observer and after the last job
call it without _callHook -> 1 caught
    a throwing onClose hook still completes close
the recipe back to the override -> 1 caught
    every close is the one close, and the link goes once
```

Мутация «на каждом вызове» гонялась на одном тесте: с ней тест «a close from
inside onClose is the same close» уходит в синхронную рекурсию внутри
`fakeAsync`, где таймаут теста не срабатывает, и прогон висит.

## Что прошло целиком

| Проверка | Результат |
| --- | --- |
| `dart analyze`, `dart test`, `dart doc --dry-run` в `solo` | чисто, 679 зелёных, 0 предупреждений |
| `packages/solo/example` | чисто, 9 зелёных |
| `flutter analyze`, `flutter test`, `dart doc --dry-run` в `flutter_solo` | чисто, 96 зелёных, 0 предупреждений |
| пример `flutter_solo` | чисто |
| стенд Flutter: `flutter.md` и README | 20 зелёных, 4 трассы на месте |
| стенды `vs-bloc.md` и `accumulation.md` | три пакета чисто, 13 трасс на месте |
| пять питоновских проверок документов и их сторожа | зелёные |

## Чего эта работа не трогала

Остальные находки ревью стоят как стояли: девять Medium и тринадцать Low. M1
ждёт решения владельца о судьбе `SoloPhase.unknown`, вместе с остальным списком
«что лишнее». `SoloStream` по-прежнему закрывает свой стрим переопределением
`close` с запомненным future — он держит обещание сам, а перевод его на хук
в эту работу не входил.
