# Четыре кодовых Medium из ревью: правки и сторожа

> **Состояние на 2026-09-19:** сделано, правки в `main`.
> **Что это:** отчёт о правке M12, M7, M2 и M3 из ревью — что было
> сломано, чем починено, чем закрыто и где находка оказалась неточной.
> **Связанные записи:** `2026-09-19-solo-project-review.md`,
> `2026-09-19-high-findings-report.md`.

Владелец выбрал четыре кодовых Medium, вторую волну после трёх High. Порядок
брался по цене: сперва однострочная правка со сроком, потом три дефекта движка.
Каждая закрыта сторожем, каждая часть правки проверена своей мутацией.

| Находка | Пакет | Правка | Сторожа |
| --- | --- | --- | --- |
| M12 | `flutter_solo` | `@protected` повторён в переопределении | 1 |
| M7 | `solo` | таймеры гасятся на общем конце закрытия | 1 |
| M2 | `solo` | очередь публикации дочерпывается до конца | 2 |
| M3 | `solo` | хэндл отпускает тело, обработчики и предка | 4 |

## M12. Защищённый хук, ставший публичным

```dart
@protected
@override
void onListenerError(Object error, StackTrace stackTrace) {
```

`@protected` в Dart не наследуется, а переопределение в миксине аннотацию
не повторяло: у всякого контроллера с `SoloListenable` хук движка был обычным
публичным членом и ушёл бы таким в `dart doc`. Вернуть аннотацию после
выпуска — ломающая правка, до выпуска — бесплатная.

Проверено анализатором, а не рассуждением: временный файл, зовущий
`onListenerError` снаружи класса, до правки собирался молча, после неё даёт
диагностику.

```text
warning • The member 'onListenerError' can only be used within instance
members of subclasses of 'SoloListenable' • invalid_use_of_protected_member
```

Сторож читает исходник — «the mixin repeats @protected on the engine hook».
Иначе никак: аннотация видна только анализатору, а вызов во время прогона
одинаков с ней и без неё. Такой сторож в пакете уже есть, про импорты базовых
классов, и этот сделан по его образцу.

## M7. Слив, оставлявший таймер накопления

```dart
_cancelTimers();
_draining = false;
```

`_stopWork` снимал все таймеры, `_pump` — ни одного, поэтому
`close(mode: drain)` заканчивался с живым таймером интервала. Тот держит
накопитель, накопитель — контроллер. Во Flutter это красный `testWidgets`
со словами «A Timer is still pending even after the widget tree was disposed»
у того, кто всего лишь закрыл контроллер. Снятие переехало в `_finishClose` —
общий конец обоих путей закрытия.

`doc/accumulation.md` уже обещала «`close()` cancels every timing timer» без
оговорки про слив, поэтому правка делает страницу верной, а не требует её
менять.

Сторож — «a drain takes the accumulation timers down with it»
в `drain_test.dart`: `throttle(10 s)`, одно событие, слив и миллисекунда
времени, потом `async.pendingTimers` пуст.

## M2. Изменение, терявшееся за упавшим `publish`

```dart
try {
  publish(change.$1, change.$2);
} on Object catch (error, stackTrace) {
  if (failure == null) {
    failure = error;
    failureTrace = stackTrace;
  } else {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
```

`_publishPending` снимал пару с очереди и звал `publish`; бросок уносил проход
целиком, и всё, что стояло за упавшим изменением, оставалось в очереди
навсегда — хотя `currentState` это изменение уже содержит. Теперь очередь
дочерпывается до конца, первая ошибка выходит наружу по окончании прохода,
остальные уходят туда же, куда уходит ошибка упавшего хука.

**Что уточнилось в документе.** `doc/state.md` говорила про упавший `publish`
одно: «It goes to `Zone.current.handleUncaughtError`». Зонд показал три разных
маршрута:

```text
direct: escaped Bad state: boom on b
via hook: nothing escaped to the writer
in body: outcome=Failed(Bad state: boom on c)
zone got: [Bad state: boom on b, Bad state: boom on hook-trigger]
```

Ошибка уходит туда, откуда пришла запись: в тело, позвавшее `ctx.emit`;
вызывающему `externalSetState`; и в зону — только когда этот вызывающий сам хук
движка, чью ошибку ловит `_callHook`. Строка таблицы переписана на оригинале
и в переводе, рядом встала вторая — про очередь за упавшим изменением.

Сторожа — группа «a delivery that throws» в `state_rakes_test.dart`, где
и живут сторожа этой страницы: доставка, бросающая на названных состояниях,
и два изменения, записанные из первой же публикации.

## M3. Хэндл, державший дерево

```dart
_body = null;
_onError = null;
_onCancel = null;
_parentJob = null;
```

Ядро обе меры делает нарочно и объясняет зачем: обнуляет `_parent` и обнуляет
тело. `_SoloJob` их снимал молча — тело, оба правила и оба обработчика были
`final`, а `_parentJob` не обнулялся нигде. Один хэндл в поле держал всё
дерево, из которого вышел, и всё, что это дерево захватило.

**Правила отпустить нельзя, и находка тут неточна.** Её вердикт называет «тело,
правила и `_parentJob`». Первая версия правки так и сделала, и прогон покраснел
дважды: `unattended_test.dart` — «a fresh Cancelled(rules) from a leaked
context reaches the observer» и `zone_test.dart` — «a cancellation never
reaches the zone». Контекст, утёкший из тела, читает состояние через
`_rejectKeep` спустя сколько угодно времени после исхода, и отмена, которую он
строит из отказа правила, — весь его диагноз. Поэтому `_canStart`
и `_keepWhile` остались `final`, а у поля стоит комментарий, почему они
переживают задачу. Четвёртый сторож — «the rules outlive the job, because a
leaked context reads them» — держит это утверждение прямо.

Три сторожа об освобождении — `retention_test.dart`, сделанный по образцу
`packages/async_job/test/retention_test.dart`: `WeakReference` и помощник
`collected`, который просит сборщик мусором. Помощник скопирован
в `test/support/reachability.dart`, потому что пакет свои тесты
не экспортирует. Мутации:

```text
M3: keep the body -> a finished job lets go of its body
M3: keep the handlers -> a finished job lets go of its state handlers
M3: keep the parent -> a finished child lets go of the job that ran it
```

## Что прошло целиком

| Проверка | Результат |
| --- | --- |
| `dart analyze` и `dart test` в `solo` | чисто, 672 зелёных |
| `flutter analyze` и `flutter test` в `flutter_solo` | чисто, 96 зелёных |
| `dart doc --dry-run` в `solo` | 0 предупреждений |
| `packages/solo/example` | чисто, 9 зелёных |
| стенд документов и `check_traces.py` | 13 трасс, все на месте |
| пять питоновских проверок документов | зелёные |

## Чего эта работа не трогала

Остальные находки ревью — четырнадцать Medium и тринадцать Low — стоят как
стояли. Шесть документных (M15, M16, M1, M6, M10, M11) ждут вычитки страниц,
в которую они ложатся; список «что лишнее» ждёт решений владельца.
