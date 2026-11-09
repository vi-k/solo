> **Состояние на 2026-11-09:** волна сделана по одобренному дизайну и влита
> в `main`.
> **Что это:** отчёт о честной волне по `packages/solo/doc/vs-bloc.md`
> и о причине, по которой у `flutter_solo` нет `SoloProvider`.
> **Связанные записи:** `2026-11-09-vs-bloc-fairness-design.md`,
> `2026-11-07-bloc-vs-solo-debate-report.md`.

# Честная волна по vs-bloc.md: отчёт

Владелец 2026-11-09 одобрил дизайн `2026-11-09-vs-bloc-fairness-design.md`
словом «делай». Ниже — что сделано по каждой правке, где исполнение разошлось
с дизайном и чем это проверено.

## Что сделано

**Правка 1, вступительная таблица.** У карты сценариев `vs-bloc.md` между
первой попыткой и solo встал столбец «What bloc uses» с ответом bloc каждого
раздела, у «Awaiting a particular request» — и ответом `Cubit`. Вводная фраза
называет три столбца, решение 86 `docs/settled.md` — тоже.

**Правка 2, «Closing and cancelling in-flight work».** Ответ bloc проверяет
`isClosed` до вызова и после него; проза под кодом говорит, что `close()` ждёт
только вызов в полёте, и что обеим проверкам нужен bloc 9.2.1. Абзац solo
больше не противопоставляет очередь: сообщение в очереди не уходит и там,
и там, а разница — в вызове, который уже идёт: `ctx.abandonable` его отпускает.
«What solo gives» говорит то же. Строка таблицы «Where bloc keeps its answer»
в `bloc.md` ссылается на ответ как есть.

**Правка 3, «Typed methods with queued execution».** Требование называет обе
половины: методы контроллера и перемещение, которое устарело, не занимает
карту, а зум перемещение не отменяет. Под заголовком Bloc — ответ с токеном
на каждое перемещение в методе, с трассой solo. `restartable()` — абзацем,
почему он не подходит: трасса первой попытки и `MapState(0, z4)`. «What solo
gives» и проза solo говорят о том, чего ответ bloc не даёт: исход у каждого
вызова (`Cancelled(replaced)`), замена политикой метода, остановка перемещения
в полёте при `close()`, ключ задачи в наблюдателе. Строка этого сценария
в таблице `bloc.md` переписана под новый ответ.

**Правка 4, «Awaiting a particular request».** Вводный абзац первой попытки
говорит, что делает `droppable()` и почему к нему тянет; абзац о заказе B
называет обе ловушки и то, что ни один из четырёх трансформеров
bloc_concurrency 0.3.0 ключа не различает. Фраза из `SAID` на месте.

**Правка 5, «Ordering updates to shared state».** После «no arrangement of the
methods can give two of them a queue each» — цена: команда, которая заметок
не трогает, ждёт за обновлением так же, и выход для неё — отдельный контроллер,
как в разделе `jobs.md` «A tap that does not wait for a reload».

**Правка 6, `SoloProvider`.** В README `flutter_solo`, «The controller's life»,
второй абзац говорит, что провайдер ничего не добавил бы к `State`,
`ScopeModel` и `package:provider`: все закрывают из синхронного `dispose`,
а дождаться асинхронного `close()` может только асинхронный жизненный цикл.
«What is not here» того же README ссылается на этот раздел. Утверждения сверены
по исходникам: `Dispose<T>` в `provider-6.1.5+1` (`inherited_provider.dart`) —
`void Function(BuildContext, T)`; `BlocProvider` во `flutter_bloc-9.1.1`
закрывает `(_, bloc) => bloc.close()`; `ScopeModel.dispose` в `scopo-1.0.0`
синхронный, `AsyncDataScope` берёт `FutureOr<void> Function(T) disposeData`.

**`docs/settled.md`.** Решение 64 получило вторую причину отсутствия
провайдера, решение 86 — три столбца карты, решение 148 — самописный `Lock`.

**Бэклог.** Удалены «Ответ bloc в «Closing…»» и «Остальные замечания Sol…»;
запись о проверке свежим оппонентом сокращена до ловушки рабочего типа и исхода
внешнего действия на `state.md` и `jobs.md`; из записи о провайдере и слушателе
остался `SoloListener`.

## Где исполнение разошлось с дизайном

- **Ссылка из `vs-bloc.md` на README `flutter_solo`.** Дизайн ставил в строку
  `BlocProvider` таблицы соответствий ссылку на «The controller's life».
  `check_links.py` её отверг: страница `solo` не ссылается вверх,
  на `flutter_solo`. Строка говорит довод сама: «a provider would close a
  controller from a synchronous `dispose`, no better than a `State` does».
- **Решение 148.** Дизайн добавлял, что готовые замены `Lock` страница
  не советует. В записи спора этого слова владельца нет — есть только «он
  показывает, как барьер устроен изнутри»; решение говорит только это.
- **Задание стенда для строки «Typed methods» в `bloc.md`.** Дизайн допускал
  задание `tool/bloc_snippets.py` по образцу `solo_table_closing`.
  Не понадобилось: строка ссылается на ответ `vs-bloc.md` как есть, а его
  держит `bloc/item6` стенда `tool/doc_snippets.py`.
- **Время закрытия в прозе.** Миллисекунд проза не называет, поэтому в `QUOTED`
  они не идут; время держат сторожа.

## Стенды

`tool/doc_snippets.py`:

- `BLOC_PUBSPEC` — `bloc: ^9.2.1`.
- `bloc/item3`, «queued behind, guarded»: требует, чтобы ушло только `hi`
  и `close()` ждал вызова в полёте (не меньше 30 мс из 40).
- `solo/item3`: печатает время закрытия и требует, чтобы `close()` вернулся
  раньше ответа на вызов в полёте (меньше 30 мс). Прогон: 0 мс у solo, 40 мс
  у bloc.
- `bloc/item6`: сторож на трассу с `moveTo 1 stopped` у ответа с токеном;
  закрытие во время перемещения — `[moveTo 1 start, moveTo 1 end]`, `close()`
  bloc ждёт; вариант с `restartable()` собирается из блока `CommandMapBloc`
  заменами с `assert` (простой `moveTo` вместо метода с токеном, без поля
  `_moving` и `typedef`, `restartable()` вместо `sequential()`, имя
  `RestartMapBloc`) и требует трассу первой попытки и `MapState(0, z4)`.
- `solo/item6`: исходы двух первых перемещений — `Cancelled(replaced)`;
  наблюдатель видит `MapKey.moveTo`; закрытие во время перемещения —
  `[moveTo 1 start, moveTo 1 stopped]`.
- `QUOTED` и `SAID` пополнены цитатами новой прозы.

`tool/bloc_snippets.py`, `solo_table_closing`: берёт ответ `vs-bloc.md` как
есть и требует двух проверок `isClosed` в блоке; мёртвый `requireGuarded`
удалён.

Прогон 2026-11-09 на дереве волны: все пять стендов, 83 драйвера, анализ
с `--fatal-infos` без замечаний; `check_traces.py` — «every quoted trace is
what the bench prints». Задание `docs` целиком, с `build_site.py`, зелёное;
тесты README `flutter_solo` (`readme_rakes_test.dart`,
`readme_scopo_test.dart`) — 85 из 85.

## Мутации

Каждый новый сторож покраснел на своей мутации сгенерированного драйвера,
со своим сообщением и кодом 255:

| Мутация | Сторож |
| --- | --- |
| из ответа bloc в `bloc/item3` убрана проверка до вызова | «the check before the call must keep the queued message from the API» |
| то же в `solo_table_closing` | «"bye" must not be sent» |
| `ctx.abandonable` в `ChatController` заменён на `ctx.join` | «close must not wait for the reply in flight» |
| из `moveTo` ответа bloc убрана отмена прежнего токена | «the token must stop the first move and skip the second» |
| в варианте с `restartable()` снова `sequential()` | «a restart must leave the calls running and the zoom must restart the move» |
| у `moveTo` контроллера solo убрана `Policy.restart` | «a replaced move must end Cancelled(replaced)» |

## Переводы

`docs/ru/solo/vs-bloc.md`, `docs/ru/solo/bloc.md`,
`packages/flutter_solo/README.ru.md` правились тем же заходом;
`check_translations.py` — «no differences». Линтер скилла `humanizer--ru`
на изменённых строках дал четыре `ERROR`, все ложные: «математические знаки» —
`=` в коде `final token = _moving = CancelToken();` и дефисы в якорях ссылок
таблицы `bloc.md`. В прозе ошибок нет.
