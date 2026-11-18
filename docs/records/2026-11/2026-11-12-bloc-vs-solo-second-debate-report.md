> **Состояние на 2026-11-18:** спор проведён 2026-11-12, пять раундов, Opus
> за bloc. Свежим оппонентом итог не проверялся: владелец выбрал вместо этого
> независимое ревью `solo` — `2026-11-12-solo-project-review.md`. Два дефекта
> документов из раунда 3 исправлены 2026-11-18 по слову владельца.
> Предложение линии с пределом одновременности записано в бэклог 2026-11-18.
> Запись написана 2026-11-18 по текстам раундов и переписке того дня.
> **Что это:** второй спор «bloc или solo», уже с линиями `SoloLanes`: Opus
> за bloc, Claude за solo, доводы владельца в раунде 4; зонды на solo и на bloc
> с их ключевым кодом и выводом.
> **Связанные записи:** `2026-11-07-bloc-vs-solo-debate-report.md`,
> `2026-11-10-solo-lanes-design.md`, `2026-11-11-solo-lanes-report.md`,
> `2026-11-12-solo-project-review.md`.

# Второй спор «bloc или solo»: Opus за bloc

По слову владельца 2026-11-12: «можем мы теперь снова провести дискуссию?»

## Как шёл спор

Первый спор, `2026-11-07-bloc-vs-solo-debate-report.md`, шёл до линий. Его
сильнейший довод за bloc — «bloc выбирает границы последовательности
по регистрации, а solo делает последовательным весь контроллер» — линии
`SoloLanes` отвечают прямо, поэтому повтор не был пересказом. Claude предложил
прежний состав: оппонент `gpt-6.1-sol` через `codex exec`. Владелец ответил:
«пусть оппонентом будет Opus». Оппонент — субагент Claude Code на `opus`,
раунды шли продолжением той же его сессии. Claude, ведущий спора, — за solo.

**Дерево.** Отвязанная копия на `f846472a`, голове ветки `solo-lanes` (часть
C). В ней `solo` 2.0.0 и `flutter_solo` 2.0.0 с линиями, патчи
`async_job_lints` и минор `solo_lints` 0.3.0 с правилами `stale_emit`
и `lane_outside_constructor`. Ничего из этого не выпущено, на pub.dev — `solo`
1.x; оппоненту это сказано как факт, но спор — о дереве. Исходники bloc —
в `~/.pub-cache`: `bloc` 9.2.1, `flutter_bloc` 9.1.1, `bloc_concurrency` 0.3.0,
`bloc_test` 10.0.0, `synchronized` 3.4.1+1; `hydrated_bloc` в кеше нет.

**Правила задания.** Цель — слова владельца к первому заходу: «выявить наши
сильные и слабые стороны»; побеждать риторикой не нужно. До первого слова
оппонент читает итог первого захода как отправную точку, `docs/settled.md`
(довод против решения — только с новым фактом и пометкой «повтор решения N»)
и страницы `lanes.md`, README `solo`, `bloc.md`, `vs-bloc.md`, README
`flutter_solo` и `solo_lints`. Каждое утверждение о solo — со ссылкой
`путь:строка` в дереве, о bloc — на исходник в кеше или с пометкой «факт
экосистемы». Без чучел: спорить с тем, как solo задуман и описан. Зонды можно
писать только в тестах `packages/solo` или `packages/flutter_solo` копии
и цитировать последние строки дословно. Чего не проверял — так и сказать.
Вступление — не больше 1500 слов.

**Ход.** Раунд 1 — вступление Opus за bloc, раунд 2 — ответ Claude, раунд 3 —
Opus с зондами на bloc, раунд 4 — доводы владельца, проверенные зондом на solo,
раунд 5 — ответ Opus владельцу. После него владелец назначил не проверку свежим
оппонентом, а независимое ревью `solo` (ниже, «Итог»).

Ссылки `путь:строка` в этой записи — на дерево `f846472a`, как их давали
стороны; в `main` строки с тех пор сдвинулись. Ссылки на bloc —
от `~/.pub-cache/hosted/pub.dev/`. Зонды жили в одноразовой копии и в отдельном
пакете вне репозитория: ниже их ключевой код дословно и вывод, который несёт
довод.

## Раунд 1: вступление за bloc

**Что изменилось с первого захода**, по Opus:

- «bloc выбирает границы последовательности по регистрации» — закрыт частично.
  Два вида работы над одним состоянием линии разводят
  (`packages/solo/doc/lanes.md:89-131`,
  `packages/solo/doc/vs-bloc.md:311-316`). Не закрыта другая половина:
  регистрация bloc задаёт и модель исполнения внутри очереди, по умолчанию
  `concurrent` (`bloc-9.2.1/lib/src/bloc.dart:61-65`, `:195-197`), а линия
  исполняет задачи по одной, и набор линий застывает после конструктора
  (`packages/solo/lib/src/solo.dart:1773-1780`). Очередь на сущность — не цель
  дизайна (`docs/records/2026-11/2026-11-10-solo-lanes-design.md:100-102`),
  и решение 84 (`docs/settled.md:1212-1225`) говорит, что линия по ключу
  на лету его посылку меняла бы.
- Разбиение на контроллеры — частично: внутри одного состояния его нет,
  остаётся для частей с разным временем жизни (`lanes.md:519-525`) и для
  работы, число экземпляров которой задаёт пользователь.
- `SoloListener` — закрыт (решение 153). Линт на `done` без разбора исхода —
  закрыт (`discarded_outcome`, `outcome_after_await`). Ответ bloc в «Closing
  and cancelling» — закрыт (`vs-bloc.md:553-555`).
- `bloc_test`, `hydrated_bloc`, адаптер `solo_bloc`, страница приложения
  устройства — не закрыты, они в `docs/backlog.md:20-33`. Общий контракт
  Cubit/Bloc — частично: у `Solo` и `SoloLanes` общая база `SoloController`,
  лёгкого аналога Cubit нет.

**Тезис.** Для большого Flutter-приложения bloc остаётся архитектурой
по умолчанию, а solo — инструментом для отдельных контроллеров со сложной
жизнью операций. Линии сузили разрыв в удобстве, но принесли свою цену:
связность через правила, тихую смену смысла старого кода и новый класс
взаимоблокировок.

**Семь доводов:**

1. *Линии статичны и строго последовательны.* Зонд 1: лайки двух постов в одной
   линии идут друг за другом. Документ это признаёт: «A like of a second post
   still waits for the first: there is one likes lane» (`lanes.md:356-357`).
   В bloc одновременность — умолчание, порядок по ключу собирается своим
   трансформером (`EventTransformer` — любая функция над потоком,
   `bloc.dart:33`; `groupBy` из `rxdart` 0.28.0). Трансформер Opus в этом
   раунде не собирал.
2. *Правила связывают линии, и откат молча пропадает.* Запись любой линии
   заново спрашивает правила задач всех остальных (`lanes.md:9-14`,
   `:595-596`), а отменённая правилами задача не получает `ifCancelled`
   (`lanes.md:406-408`, `packages/solo/lib/src/job.dart:283-296`). Зонд 2: флаг
   `pending: true` после записи соседней линии зависает навсегда. Таблица
   `packages/solo/doc/state.md:785` перечисляет источники несовместимой записи
   (`externalSetState`, родитель, ребёнок) и другую линию не называет. В bloc
   `emit` одного обработчика эмиттеры других не трогает (`bloc.dart:197-209`),
   и откат в `catch` выполняется; цена — проверка допуска руками.
3. *Переход с `Solo` на `SoloLanes` меняет смысл написанного.* Копия
   `ctx.state`, прочитанная до `await` и записанная после, в `Solo` безопасна,
   а в линиях теряет чужую запись (`lanes.md:172-176`). Страховка
   `stale_emit` — lint, включается по имени
   (`packages/solo_lints/README.md:42-44`), эвристический и слепой к ответу
   сервера целиком, телу-tear-off, записи ребёнком прочитанного родителем
   и циклам (`:208-215`); дизайн: «Замена целиком не проверяется»
   (`2026-11-10-solo-lanes-design.md:728`). Opus сам оговорил: та же гонка
   в одновременных обработчиках bloc есть, линта против неё он не знает, так
   что довод — о цене перехода.
4. *Новый класс взаимоблокировок.* Зонд 3: задача линии `a` ждёт задачу в `b`,
   та — задачу в `a`; обе висят. Таблица документа это признаёт
   (`lanes.md:599`), `await_own_queue` видит только свою линию
   (`solo_lints/README.md:113-118`). В bloc `add` возвращает `void`
   (`bloc.dart:82`), такого цикла нет, но нет и исхода вызова — это сила solo.
5. *Открытый трансформер против закрытого перечня.* `EventTransformer` — любая
   функция, `bloc_concurrency` сам так собран; `Policy` — закрытый `enum`
   из четырёх значений (`packages/solo/lib/src/policy.dart:11`).
6. *Линии не убирают многоконтроллерность.* Одно закрытие на все линии
   (`lanes.md:519-525`, `:601-603`), у линии нет своих `close` и `cancelAll`
   (`packages/solo/lib/src/lane.dart:26-27`), барьера «дождаться всех линий»
   нет (`2026-11-10-solo-lanes-design.md:103-108`), исключения команд одному
   устройству между линиями нет (`lanes.md:129-131`).
7. *Экосистема и статус.* `bloc_test` и `hydrated_bloc` против рецептов
   и бэклога; линии не выпущены, в дереве ещё `version: 1.1.1`.

**Что Opus признал за solo:** исход вызова, политики внутри линии и переоценку
правил по записи соседа — эпоху (`lanes.md:361-411`), которой bloc без
поколений не даёт; объявление линий защищено рантаймом (`solo.dart:1794-1814`)
и включённым по умолчанию `lane_outside_constructor`.

**Три вопроса к solo:** очередь на сущность — что у solo в коде и сколько это
стоит против `concurrent()` или трансформера по ключу; зависший
`pending: true` — задумано ли, как писать оптимистичную запись и почему таблица
`state.md:785` молчит о другой линии; какой инструмент solo покажет цикл через
линии и порчу старых тел при переходе до продакшена.

**Что открыто, по Opus:** трансформер с `groupBy` не собран; `solo_lints`
на цикле и на теле зонда 2 не гонялся, молчание `await_own_queue` выведено
из README; цена переоценки правил на частой записи не мерилась; `flutter_solo`
с линиями не проверялся.

### Зонд solo раунда 1

Тест в `packages/solo/test/` копии, `fakeAsync`,
`@Timeout(Duration(seconds: 10))`, `dart test` из `packages/solo`. Контроллер:

```dart
typedef Dev = ({String mode, bool pending});

final class _Feed extends SoloLanes<Dev> {
  late final SoloLane<Dev> a;
  late final SoloLane<Dev> b;

  _Feed() : super((mode: 'on', pending: false)) {
    a = lane('a');
    b = lane('b');
  }

  SoloJob<void> like(String id, List<String> log, FakeAsync f) =>
      a.enqueue<Dev, void>((ctx) async {
        log.add('${f.elapsed.inMilliseconds} ms: like $id start');
        await ctx.join(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        log.add('${f.elapsed.inMilliseconds} ms: like $id end');
      });

  // An optimistic flag with a rollback, and a keep rule on another field.
  SoloJob<void> command(List<String> log, FakeAsync f, {bool rule = true}) =>
      a.enqueue<Dev, void>(
        keepWhile: rule ? (s) => s.mode == 'on' : null,
        ifCancelled: (s, c) {
          log.add('${f.elapsed.inMilliseconds} ms: ifCancelled called');
          return (mode: s.mode, pending: false);
        },
        (ctx) async {
          ctx.emit((mode: ctx.state.mode, pending: true));
          await ctx.join(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          ctx.emit((mode: ctx.state.mode, pending: false));
        },
      );

  SoloJob<void> setMode(String mode) =>
      b.enqueue<Dev, void>((ctx) async {
        ctx.emit((mode: mode, pending: ctx.state.pending));
      });

  // A cycle: a job of lane a awaits a job of lane b, which awaits a job of a.
  SoloJob<String> outer() => a.enqueue<Dev, String>((ctx) async {
    return ctx.join(() => b.enqueue<Dev, String>((ctx) async {
      return ctx.join(() => a.enqueue<Dev, String>((ctx) async => 'inner').value);
    }).value);
  });
}
```

Драйверы, каждый в `fakeAsync` с `f.flushMicrotasks()` после конструктора:
`like('p1')` и `like('p2')`, потом 200 мс; `command()`, через 30 мс
`setMode('off')`, потом 200 мс и печать исхода и `currentState`; на новом
контроллере `command(rule: false)`, через 30 мс `cancel()`, потом 200 мс;
`outer()` и 60 с, печать `isFinished` и `pending`. Вывод:

```text
00:00 +0: one lane: two likes of different posts
0 ms: like p1 start
50 ms: like p1 end
50 ms: like p2 start
100 ms: like p2 end
00:00 +1: rollback after a cancel by another lane vs by hand
by lane b: Cancelled(rules: keepWhile); state (mode: off, pending: true)
by hand: Cancelled(manual); state (mode: on, pending: false)
330 ms: ifCancelled called
00:00 +2: a cycle across lanes
after 60 s: isFinished false; pending SoloPending(a: SoloPending([null] in its body, 1 queued: [null]), b: SoloPending([null] in its body))
00:00 +3: All tests passed!
```

## Раунд 2: ответ за solo

Claude сверил цитаты Opus с деревом и прочёл зонды: неверных ссылок нет.

**Признано:**

- Очередь на сущность — свойство модели. Корни `Solo` и каждой линии идут
  по одному, параллельной политики корней нет (`vs-bloc.md:94-99`), линия
  по ключу на лету — не цель (решение 84). Ответ solo на N загрузок с отменой
  каждой: дети одного корня, контроллер на сущность или задачи `async_job` без
  очереди (решение 133). Для работы, которая приходит вызовами в разное время,
  остаются последние два. У bloc это одна регистрация.
- Цикл через две линии не ловят ни линт, ни рантайм; видно его только снимком
  `pending`.
- Пробел таблицы `state.md:785`: тот же документ в `:84` называет задачу другой
  линии третьим источником записи, а таблица ручек отката — нет. Дефект
  документа.
- Статус: на pub.dev `solo` 1.x; версию поднимает коммит подготовки выпуска.

**С чем Claude спорил:**

- *Довод 2.* Откат не теряется, так решено и записано дважды:
  `lanes.md:406-408` и таблица `state.md:785`. `keepWhile: mode == 'on'`
  говорит, что команда и её поправка имеют смысл только в режиме `on`. Линия
  `b` сама пишет `pending: ctx.state.pending` — переносит флаг чужой операции
  в новую эпоху. Ответ solo — пример выхода из аккаунта (`lanes.md:361-411`):
  запись, открывающая эпоху, пишет её состояние целиком,
  `(mode: 'off', pending: false)`. Если поправка нужна в любом режиме, правило
  ей не нужно, и ручная отмена в зонде откатилась. В bloc под `concurrent()`
  откат в `catch` ложится поверх записи соседа (`emitter.dart`, `emit`
  проверяет только `isDone`): старая поправка попадает на новые данные, если
  не завести поколение операции, — это признал Sol в раунде 6 первого спора.
- *Довод 3.* Переход не тихий: `SoloLanes` — другой класс, тело переезжает
  правкой автора. В bloc с умолчанием `concurrent()` та же гонка без
  инструмента; solo даёт одну очередь без гонки и линии, где она частично
  ловится.
- *Довод 5.* Закрытый перечень — цена гарантий, которых трансформер над
  `Stream<E>` не даёт: исход каждого вызова, правила на каждой записи, снимок
  `pending`.
- *Довод 6.* Частью согласен: части с разной жизнью — разные контроллеры
  в обеих моделях, а жизнью во Flutter правит scopo, признанный в первом споре
  сильнее `BlocProvider`.

**Вопросы Opus**, с просьбой ответить зондами на bloc: собрать трансформер
по ключу и показать отмену одной сущности и исход своего вызова (с оговоркой:
если нужен `Completer` в событии, это и есть цена); тот же сценарий отката
в bloc и цена поколения; ловит ли что-нибудь цикл в bloc, когда обработчик под
`sequential()` ждёт `stream.firstWhere(...)`, а нужное состояние даёт событие
за ним.

## Раунд 3: Opus за bloc, зонды на bloc

**Ответ на возражения:**

- *Довод 2 — принят почти целиком*, зонд q2 подтвердил его против bloc. Без
  поколения провал в bloc откатывается удобно, но успешная команда кладёт
  результат на новые данные: `applied: 1` при `mode: off`. Поколение — счётчик,
  захват и две проверки, около пяти строк на команду, и с ним тот же зависший
  флаг, что у solo. Значит, флаг — цена правила «старая поправка не ложится
  на новые данные», а не изъян линий; снимает его тот, кто открывает эпоху
  (`lanes.md:369-373`). Уступка сверх вопроса: отменённый `restartable`
  обработчик bloc откатиться не может, `emit` после отмены молча глотается
  (`bloc-9.2.1/lib/src/emitter.dart:135`), а `Policy.restart` у solo зовёт
  `ifCancelled` и публикует его до следующей задачи (`state.md:790`). Здесь
  solo сильнее.
- *Довод 3 — частично.* Как сравнительный снят. Остаётся: правка при переезде
  механическая (`enqueue` → `_lane.enqueue`), тела выглядят прежними,
  а `stale_emit` включается по имени и не видит записи целиком. Слабость solo,
  но не довод за bloc.
- *Довод 4 — снят как сравнительный.* q3: обработчик `sequential()` ждёт
  `stream.firstWhere` своего bloc, и через 2000 мс ничего не сообщает;
  `close()` такого bloc не завершится. Разница в частоте — оценка Opus,
  не замер: в solo ожидание чужой операции — идиома (`job.value`), в bloc —
  редкий приём.
- *Довод 5 — рамка Claude принята*: обмен, а не выигрыш. Исход своему
  вызывающему bloc даёт `Completer` в событии, ценой поля и ручного завершения
  на каждой ветви; без проверки `emit.isDone` в теле `Completer` повис бы.
- *Довод 6 — согласие*: части с разной жизнью — разные контроллеры в обеих
  моделях, scopo доступен обеим и сильнее `BlocProvider`.

**Ответы на вопросы.** Очередь на сущность в bloc — одна регистрация
с трансформером по ключу: порядок внутри ключа, ключи параллельно, отмена одной
сущности (мягкая: тело останавливается, только проверив `emit.isDone`, `Future`
внутри не прерывается, как и под `ctx.join`). Исход — `Completer` в событии,
откат отменённой сущности невозможен: в состоянии осталось `a: running`.
`groupBy` без `duration` держит поток группы на каждый виденный ключ
(`rxdart-0.28.0/lib/src/transformers/group_by.dart:10`, `:28`), утечку Opus
не мерил. Откат после смены режима:

| Вариант | Что видит пользователь |
| --- | --- |
| провал, без поколения | `(applied: 0, mode: off, pending: false)` — откат лёг, и здесь он верен |
| успех, без поколения | `(applied: 1, mode: off, pending: false)` — результат старой эпохи лёг на новую |
| успех, с поколением | `(applied: 0, mode: off, pending: true)` — тот же зависший флаг, что у solo |

Цикл в bloc не ловится ничем: довод 4 общий для обеих моделей.

**Слабые стороны solo после раунда 3**, по важности:

1. Нет очереди на сущность и параллельных корней одного вида — *свойство
   модели*; у bloc это одна регистрация.
2. Ошибки линий без инструмента: цикл через две линии молчит, `stale_emit`
   выключен по умолчанию и не видит записи целиком. У bloc инструмента нет
   вовсе, так что это предел гарантий solo, а не сравнительная слабость.
3. Нет готовых `bloc_test` и `hydrated_bloc` — *пробел экосистемы*, важность
   невысокая.
4. Таблица ручек отката не называет запись другой линии (`state.md:785` против
   `:84`) — *дефект документа*.
5. Тот, кто открывает эпоху, сам сбрасывает оптимистичные поля чужих линий,
   иначе флаг зависает. Это цена правила и в bloc с поколением, но рецепт эпохи
   (`lanes.md:404-411`) пишет `Feed(epoch: …)` целиком и не говорит, что именно
   это снимает флаги — *дефект документа*, мелкий.
6. Не выпущено — временное.

**Где solo сильнее:** исход вызова без `Completer`; откат после отмены
по `restart`; правило продолжения одним `keepWhile` против поколения в каждой
команде.

**Что открыто, по Opus:** утечку `groupBy` не мерил; тайминги bloc — реальные
таймеры, порядок устойчив, миллисекунды нет; в q3 процесс завершился сам,
зависание видно только по состоянию; частоту циклов в приложениях не знает.

### Зонд bloc раунда 3

Отдельный пакет: `bloc: 9.2.1`, `bloc_concurrency: 0.3.0`, `rxdart: 0.28.0`,
`sdk: ^3.10.0`, `dart pub get --offline`, `dart analyze` — `No issues found!`,
программа зонда — `dart run`. Время — реальные таймеры, округлённые до 10 мс:

```dart
final _clock = Stopwatch()..start();
String get t => '${(_clock.elapsedMilliseconds / 10).round() * 10} ms';
Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
```

Вопрос 1. События `Start(id, ms)` с полем `Completer<String> done`
и `Stop(id)`, общий тип `DlEvent` с геттером `id`:

```dart
EventTransformer<E> perKeyRestartable<E extends DlEvent>() =>
    (events, mapper) =>
        events.groupBy((e) => e.id).flatMap((g) => g.switchMap(mapper));

EventTransformer<E> perKeySequential<E extends DlEvent>() =>
    (events, mapper) =>
        events.groupBy((e) => e.id).flatMap((g) => g.asyncExpand(mapper));

final class Downloads extends Bloc<DlEvent, Map<String, String>> {
  Downloads({required bool restart}) : super(const {}) {
    on<DlEvent>((e, emit) async {
      switch (e) {
        case Stop():
          return; // its arrival in the group is the cancellation
        case Start(:final id, :final ms, :final done):
          print('$t: $id start');
          emit({...state, id: 'running'});
          for (var left = ms; left > 0; left -= 10) {
            await wait(10);
            if (emit.isDone) {
              print('$t: $id emitter done, body stops');
              emit({...state, id: 'rolled back'}); // dropped: cancelled
              done.complete('cancelled');
              return;
            }
          }
          emit({...state, id: 'done'});
          print('$t: $id end');
          done.complete('done');
      }
    }, transformer: restart ? perKeyRestartable() : perKeySequential());
  }
}
```

q1a: `restart: true`, `Start('a', 100)` и `Start('b', 100)`, в 30 мс
`Stop('a')`, ждать оба `done`. q1b: `restart: false`, `Start('p1', 50)` дважды
и `Start('p2', 50)`.

Вопрос 2. События `Command({fail, generation})` и `SetMode(mode)`:

```dart
typedef Dev = ({String mode, bool pending, int applied});

final class DevBloc extends Bloc<DevEvent, Dev> {
  int _epoch = 0;

  DevBloc() : super((mode: 'on', pending: false, applied: 0)) {
    on<SetMode>((e, emit) {
      _epoch++;
      emit((mode: e.mode, pending: state.pending, applied: state.applied));
    });
    on<Command>((e, emit) async {
      if (state.mode != 'on') return; // the start rule, by hand
      final epoch = _epoch;
      bool stale() => e.generation && epoch != _epoch;
      emit((mode: state.mode, pending: true, applied: state.applied));
      try {
        await wait(100);
        if (e.fail) throw StateError('device said no');
        if (stale()) return; // the keep rule, by hand
        emit((mode: state.mode, pending: false, applied: state.applied + 1));
      } on StateError {
        if (stale()) return;
        emit((mode: state.mode, pending: false, applied: state.applied));
      }
    });
  }
}
```

Для `(fail, generation)` из `(true, false)`, `(false, false)`, `(false, true)`:
новый bloc, `Command`, через 30 мс `SetMode('off')`, через 150 мс печать
`state`.

Вопрос 3. События `WaitOpen` и `Open`; драйвер добавляет оба подряд, ждёт две
секунды и печатает состояние:

```dart
final class Gate extends Bloc<GateEvent, bool> {
  Gate() : super(false) {
    on<GateEvent>((e, emit) async {
      switch (e) {
        case WaitOpen():
          await stream.firstWhere((open) => open);
          print('$t: saw it open');
        case Open():
          emit(true);
      }
    }, transformer: sequential());
  }
}
```

Вывод:

```text
--- q1a: per-key restartable, Stop(a) at 30 ms
10 ms: a start
10 ms: b start
50 ms: a emitter done, body stops
130 ms: b end
130 ms: a -> cancelled, b -> done
130 ms: state {a: running, b: done}
--- q1b: per-key sequential, two of p1 and one of p2
0 ms: p1 start
0 ms: p2 start
60 ms: p1 end
60 ms: p1 start
60 ms: p2 end
120 ms: p1 end
q2 fail: true, generation: false -> (applied: 0, mode: off, pending: false)
q2 fail: false, generation: false -> (applied: 1, mode: off, pending: false)
q2 fail: false, generation: true -> (applied: 0, mode: off, pending: true)
2000 ms: q3 state false, still waiting
```

Claude перезапустил зонд своей командой: вывод совпал строка в строку. Оба
дефекта документов, пункты 4 и 5, Claude проверил по дереву и признал
настоящими; править их — только по слову владельца.

После раунда 3 Claude предложил владельцу три пути и советовал первый:
проверить итог свежим оппонентом, как в первом споре, где оппонент в длинной
сессии уступал, а свежий часть выводов не подтвердил; дать доводы владельца
раундом 4; закончить и писать запись.

## Между раундами: что такое очередь на сущность

Владелец спросил: «объясни по очереди на сущность и параллельным корням одного
вида». Ответ Claude, коротко. Корни контроллера идут строго по одному: у `Solo`
в общей очереди, у `SoloLanes` в каждой линии, а набор линий задан
в конструкторе. Очередь на сущность — своя очередь на каждый пост по ключу
`postId`, заведённая при первом лайке: лайки разных постов идут вместе, лайк
и снятие одного поста — по порядку. Параллельные корни одного вида — несколько
задач одного рода, каждую запускает свой вызов в своё время, со своим исходом
и отменой: N загрузок файлов, команды N устройствам. Обходные пути solo:

- дети одного корня — когда вся работа известна в одном вызове; файл,
  добавленный позже, к идущему родителю не присоединить;
- свой контроллер на сущность — когда работа приходит вызовами в разное время;
  контроллеры надо хранить, закрывать и связывать с общим состоянием;
- задачи ядра `async_job` без очереди — когда нужны только исход и отмена; нет
  состояния, правил и линтов `solo`.

Для лайков ожидание 50 мс за соседним почти незаметно; важно это для долгих
независимых операций.

## Раунд 4: доводы владельца

Владелец ответил на слабость 1, его слова дословно:

> очередь на сущность - одна очередь на лайки. лайки аккумулируются через
> collect и внутри параллельно обрабатываются детьми или одним запросом все
> сразу, если сервер позводяет. все лайки параллельно - это нагрузка на сеть
> и на сервер. нужен нормальный бэк, который позволит ставить сразу группу
> лайков, и debounce, что бы не убить сеть и сервер
>
> Параллельные корни одного вида - bloc может запустить много задач одного
> вида, но как он их собирается отменять? а мы можем, опять же, собирать
> (collect, throttle) задачи и выполнять их параллельно внутри партией.
> следующая партия в этом время собирается и ждёт. да, это пауза, но зато мы
> не перегружаем процессор и сеть. при этом пользователю возвращать свою Job
> на задачу, которую он может отменить. второй вариант: отдельная линия
> с вечноработающей задачей, которая сразу принимает и выполняет созданные
> Job. и снова пользователь получает свою личную Job.

До передачи оппоненту Claude проверил обе схемы зондом на solo и передал доводы
вместе с ценой, которую нашёл первый прогон.

### Схема A: партии

Линия `likes`, `collect` с `throttle(100 ms, startAtOnce: false)`. Событие
партии — `SoloJob<void>`, сделанная `likes.job(...)`: задача создана,
но в очередь не поставлена. `like()` отдаёт вызывающему его личную задачу,
партия запускает живые задачи группы детьми через `ctx.run` параллельно.

```dart
final class Batched extends SoloLanes<int> {
  Batched(this.log, this.f) : super(0) {
    likes = lane('likes');
  }

  final List<String> log;
  final FakeAsync f;
  late final SoloLane<int> likes;
  late final _batch = likes.collect<int, SoloJob<void>, void>(
    (ctx, jobs) async {
      log.add('${ms(f)}: batch of ${jobs.length} starts');
      // A caller may have cancelled its job before the batch: skip it.
      final live = [for (final job in jobs) if (!job.isFinished) job];
      log.add('${ms(f)}: ${jobs.length - live.length} finished before');
      await [for (final job in live) ctx.run(job).then((_) {}, onError: (_) {})]
          .wait;
      log.add('${ms(f)}: batch ends');
    },
    timing: AccumulationTiming.throttle(
      const Duration(milliseconds: 100),
      startAtOnce: false,
    ),
  );

  SoloJob<void> like(String post) {
    final job = likes.job<int, void>(key: post, (ctx) async {
      log.add('${ms(f)}: like $post sent');
      await ctx.join(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      ctx.emit(ctx.state + 1);
      log.add('${ms(f)}: like $post confirmed');
    });
    _batch.add(job);
    return job;
  }
}
```

Здесь `ms(f)` — `'${f.elapsed.inMilliseconds} ms'`. Драйвер в `fakeAsync`:
`like('p1')`, `like('p2')`, `like('p3')`; через 20 мс `like('p4')` и сразу его
`cancel()`; через 100 мс `cancel()` у `p2`, потом `like('p5')`; 400 мс, исходы
пяти задач и `currentState`.

```text
20 ms: p4 cancelled by its caller before the batch
100 ms: batch of 4 starts
100 ms: 1 finished before
100 ms: like p1 sent
100 ms: like p2 sent
100 ms: like p3 sent
120 ms: p2 cancelled by its caller while it runs
150 ms: like p1 confirmed
150 ms: like p3 confirmed
150 ms: batch ends
200 ms: batch of 1 starts
200 ms: 0 finished before
200 ms: like p5 sent
250 ms: like p5 confirmed
250 ms: batch ends
p1: Done(null)
p2: Cancelled(manual)
p3: Done(null)
p4: Cancelled(manual)
p5: Done(null)
state 3
```

### Схема B: рабочая линия

Линия `uploads` с задачей на всё время контроллера: она ждёт следующую
сделанную задачу из входящих через `ctx.abandonable` над `Completer`
и запускает её ребёнком без ожидания. `upload()` отдаёт личную задачу.

```dart
final class Worker extends SoloLanes<int> {
  Worker(this.log, this.f) : super(0) {
    uploads = lane('uploads');
    uploads.enqueue<int, void>(key: 'worker', (ctx) async {
      while (true) {
        final next = Completer<SoloJob<void>>();
        _next = next;
        final job = await ctx.abandonable(() => next.future);
        unawaited(ctx.run(job).then((_) {}, onError: (_) {}));
      }
    });
  }

  final List<String> log;
  final FakeAsync f;
  late final SoloLane<int> uploads;
  Completer<SoloJob<void>>? _next;
  final _inbox = <SoloJob<void>>[];

  void _feed() {
    final next = _next;
    if (next == null || next.isCompleted || _inbox.isEmpty) return;
    _next = null;
    next.complete(_inbox.removeAt(0));
  }

  // Jobs made but never run end with the controller.
  @override
  void onClose() {
    for (final job in _inbox) {
      job.cancel();
    }
    _inbox.clear();
  }

  SoloJob<void> upload(String file, int millis) {
    final job = uploads.job<int, void>(key: file, (ctx) async {
      log.add('${ms(f)}: upload $file starts');
      await ctx.join(() => Future<void>.delayed(Duration(milliseconds: millis)));
      ctx.emit(ctx.state + 1);
      log.add('${ms(f)}: upload $file done');
    });
    if (isClosed) {
      job.cancel();
      return job;
    }
    _inbox.add(job);
    scheduleMicrotask(_feed);
    return job;
  }
}
```

Драйвер: `upload('a', 100)`, через 10 мс `upload('b', 100)`, через 10 мс
`upload('d', 100)`; через 30 мс `cancel()` у `b`; через 200 мс
`upload('e', 1000)`; через 50 мс `close()` без ожидания
и `upload('after close', 10)`; 2000 мс, исходы, состояние и `isFinished`.

```text
0 ms: upload a starts
10 ms: upload b starts
20 ms: upload d starts
50 ms: b cancelled by its caller
100 ms: upload a done
120 ms: upload d done
250 ms: upload e starts
300 ms: close
a: Done(null)
b: Cancelled(manual)
d: Done(null)
e: Cancelled(parent)
after close: Cancelled(manual)
state 2, finished true
```

### Что пришлось делать руками

Первый прогон обеих схем упал; Claude передал оппоненту и цену:

1. **A: задачу, отменённую вызывающим до партии, надо пропустить.** `ctx.run`
   над законченной задачей бросает синхронно:
   `Bad state: Job(p4) has already finished; a job runs once,
   and a child needs a new Job.deferred` (`JobContextBase._checkChild`). Без
   фильтра `!job.isFinished` падает вся партия.
2. **B: ожидание входящих — `ctx.abandonable`, не `ctx.join`.** С `join`
   `close()` висит: рабочая задача не отпускает `Completer`, который никто
   не завершит.
3. **B: сделанная и не запущенная задача сама не кончается.** Оставшиеся
   во входящих отменяет `onClose()`, а `upload()` после закрытия проверяет
   `isClosed` и отменяет сразу. Без этого вызывающий ждёт исхода вечно.
4. **A, один запрос на партию.** Если сервер принимает группу одним запросом,
   отмена личной задачи после отправки запрос не отзовёт: вернётся `Cancelled`,
   а лайк на сервере встанет.

**Вопросы оппоненту:** закрывают ли схемы слабость 1 и что остаётся; как в bloc
отменить один из N обработчиков `concurrent()` и узнать исход своего; пауза
партии против `groupBy` по ключу — цена или довод; оговорки 1–3 — то, что solo
должен закрыть API (`lane.spawn`, пул в линии), или приемлемая ручная работа.

## Раунд 5: Opus отвечает владельцу

**Закрывают ли схемы слабость 1 — частично.** Обе дают каждому вызывающему
личную `Job` с исходом и отменой, чего у bloc нет без самодельного билета, —
здесь владелец прав. Но на краях у каждой схемы поломки, две из них — дефекты
рецепта, а не цена.

- *A1, лайк и снятие одного поста в одной партии.* Требования
  `packages/solo/doc/jobs.md:676-679` — сердце загорается сразу, лайк и снятие
  доходят до сервера в порядке нажатий — схема нарушает оба. Лайк `p1` нажат
  в 10 мс, снятие в 20 мс; оба уходят в 100 мс одновременно, сервер
  подтверждает снятие первым, лайк последним: на экране `{p1: false}`,
  а на сервере лайк стоит. Дети партии идут параллельно, `key: post` их
  не упорядочивает: политика правит только очередью (решение 50). Сердце горит
  не при нажатии, а при старте партии, потому что оптимистичная запись сидит
  в теле задачи.
- *A2, голова очереди.* Медленный лайк (2000 мс) держит следующую партию: `p2`,
  нажатый в 150 мс, уходит в 2000 мс, потому что следующая партия — следующий
  корень той же линии.
- *B1, гибель рабочего.* Оговорка 1 в B не учтена. Вызывающий отменяет задачу
  сразу после `upload()`, до микрозадачи `_feed`; рабочий получает законченную
  задачу, `ctx.run` бросает синхронно, тело рабочего падает, ошибка уходит
  в зону, и все следующие загрузки висят без исхода.
- *B2, `close(mode: SoloCloseMode.drain)` не кончается никогда.* Рабочий сам
  не завершится, а осушение ждёт, пока опустеет очередь каждой линии
  (`lanes.md:602`). Контракт `drain` для такой линии сломан.
- *Пула в B нет.* Рабочий запускает каждую задачу сразу и без предела — это
  `concurrent()` bloc, и довод «не перегружать сеть» к B не относится.

Что остаётся от слабости 1: встроенного способа исполнять корни одного вида
параллельно или по ключу у solo нет. Посылку решения 84 «одновременно
работающих корней не больше, чем линий» (`docs/settled.md:1212-1217`) схема B
обходит: корень один, детей сколько угодно.

**Отмена одного из N в bloc.** Событие несёт `Ticket` — флаг отмены
и `Completer` исхода, обработчик проверяет флаг и `emit.isDone` после каждого
ожидания. Под `concurrent()` пять загрузок стартуют разом, отменённая `u2`
встаёт. Пул без паузы — одна строка трансформера,
`(events, mapper) => events.flatMap(mapper, maxConcurrent: 2)`
(`rxdart-0.28.0/lib/src/transformers/flat_map.dart:10`, `:20`): отмена `u2`
сразу освобождает место для `u3`. Цена в bloc: `Ticket` руками, около восьми
строк; отмена кооперативная, `ifCancelled` и барьера уборки нет; событие,
отменённое до старта, всё равно стартует — этого Opus не проверял. Признано:
исход и отмена своего вызова у solo сильнее, но пул у bloc — одна строка,
а у solo — рецепт с ловушками.

**Пауза партии.** Цена — там, где видна задержка или важен порядок по ключу:
сердце в 100 мс вместо 10, 1850 мс за медленным лайком, лайк и снятие одного
поста. Довод — только при эндпоинте, принимающем группу одним запросом. При
поштучном API партия не снижает нагрузку, а превращает её во всплеск: N
запросов в одну миллисекунду. Нагрузку без паузы и без головы очереди
ограничивает пул; партия и пул решают разные задачи, и в solo готова только
партия.

**Оговорки 1–3 — дело API.** Рецепт в три десятка строк от внимательного автора
движка потребовал трёх поправок после первого прогона и ещё двух после зонда
Opus, причём B1 отключает линию целиком. Ловушки сидят в контрактах движка:
`ctx.run` над законченной задачей бросает, `drain` ждёт корень, сделанная
и не поставленная задача сама не кончается. Дизайн линий оставил дверь: очередь
на сущность «можно добавить минором позже, если найдётся пример»
(`2026-11-10-solo-lanes-design.md:100-102`), и примеров теперь два — лайки
по ключу и пул загрузок. Форма — `lane('uploads', concurrency: 4)`, где каждый
вызов получает свою корневую `Job` с политиками, правилами, `ifCancelled`,
`drain` и `pending`, или линия по ключу; в обоих случаях нужен пересмотр
посылки решения 84.

**Что открыто, по Opus:** склейку партии по ключу (последний вызов на пост
выигрывает) не собирал — она, вероятно, чинит A1, но не A2 и не время отклика;
оптимистичную запись в `like()` через `externalSetState` не проверял; `Ticket`,
отменённый до старта, не проверял; тайминги bloc — реальные таймеры.

### Зонд solo раунда 5

Схемы A и B как в раунде 4, на краях. В A состояние — `Map<String, bool>`,
сердце пишет само тело лайка, задержка своя у каждого лайка, `startAtOnce`
задаётся драйвером; батч тот же, без строки `finished before`:

```dart
SoloJob<void> like(String post, {bool liked = true, int millis = 50}) {
  final job = likes.job<Map<String, bool>, void>(key: post, (ctx) async {
    ctx.emit({...ctx.state, post: liked});
    log.add('${ms(f)}: $post ${liked ? 'like' : 'unlike'} sent, screen $post ${ctx.state[post]}');
    await ctx.join(
      () => Future<void>.delayed(Duration(milliseconds: millis)),
    );
    log.add('${ms(f)}: $post ${liked ? 'like' : 'unlike'} confirmed');
  });
  _batch.add(job);
  return job;
}
```

A1, `startAtOnce: true`: сразу `like('p0')`, через 10 мс
`like('p1', millis: 80)`, ещё через 10 мс
`like('p1', liked: false, millis: 20)`; 400 мс и `currentState`. A2:
`like('slow', millis: 2000)`, в 150 мс `like('p2')`, 3000 мс. В B класс
`Worker` тот же, что в раунде 4, только задача рабочего сохранена в поле
`worker`. B1 и B2:

```dart
// B1
runZonedGuarded(() {
  final c = Worker(log, f);
  f.flushMicrotasks();
  final x = c.upload('x', 100);
  x.cancel();
  f.elapse(const Duration(milliseconds: 10));
  final y = c.upload('y', 100);
  f.elapse(const Duration(milliseconds: 1000));
  log
    ..add('worker: ${c.worker.outcome}')
    ..add('x: ${x.outcome}')
    ..add('y: ${y.outcome}');
}, (e, s) => errors.add('zone: $e'));

// B2
final c = Worker(log, f);
f.flushMicrotasks();
c.upload('a', 100);
f.elapse(const Duration(milliseconds: 10));
var closed = false;
unawaited(
  c.close(mode: SoloCloseMode.drain).then((_) => closed = true),
);
f.elapse(const Duration(seconds: 60));
log.add('after 60 s: drain closed $closed; pending ${c.pending}');
```

Вывод, `perl -e 'alarm 300; exec @ARGV' dart test <файл>` из `packages/solo`:

```text
00:00 +0: A1: a like and an unlike of one post in one batch
0 ms: batch of 1 starts
0 ms: p0 like sent, screen p0 true
10 ms: tap like p1
20 ms: tap unlike p1
50 ms: p0 like confirmed
50 ms: batch ends
100 ms: batch of 2 starts
100 ms: p1 like sent, screen p1 true
100 ms: p1 unlike sent, screen p1 false
120 ms: p1 unlike confirmed
180 ms: p1 like confirmed
180 ms: batch ends
screen at the end: {p0: true, p1: false}
00:00 +1: A2: a slow like holds the next batch
0 ms: batch of 1 starts
0 ms: slow like sent, screen slow true
150 ms: tap like p2
2000 ms: slow like confirmed
2000 ms: batch ends
2000 ms: batch of 1 starts
2000 ms: p2 like sent, screen p2 true
2050 ms: p2 like confirmed
2050 ms: batch ends
00:00 +2: B1: a caller cancels its upload at once
worker: Failed(Bad state: Job(x) has already finished; a job runs once, and a child needs a new Job.deferred)
x: Cancelled(manual)
y: null
zone: Bad state: Job(x) has already finished; a job runs once, and a child needs a new Job.deferred
00:00 +3: B2: close with drain
0 ms: upload a starts
100 ms: upload a done
after 60 s: drain closed false; pending SoloPending(uploads: SoloPending([worker] in its body, draining))
00:00 +4: All tests passed!
```

### Зонд bloc раунда 5

Тот же пакет, вторая программа, тот же `t` и `wait`:

```dart
/// What a caller holds: a cancel switch and the outcome of its own event.
final class Ticket {
  bool _cancelled = false;
  final _outcome = Completer<String>();
  void cancel() => _cancelled = true;
  Future<String> get outcome => _outcome.future;
}

final class Upload {
  final String id;
  final int ms;
  final Ticket ticket = Ticket();
  Upload(this.id, this.ms);
}

final class Uploads extends Bloc<Upload, int> {
  Uploads(EventTransformer<Upload> transformer) : super(0) {
    on<Upload>((e, emit) async {
      print('$t: ${e.id} starts');
      for (var left = e.ms; left > 0; left -= 10) {
        await wait(10);
        if (e.ticket._cancelled || emit.isDone) {
          print('$t: ${e.id} stops');
          e.ticket._outcome.complete('cancelled');
          return;
        }
      }
      emit(state + 1);
      e.ticket._outcome.complete('done');
    }, transformer: transformer);
  }
}
```

Драйвер: пять `Upload('u$i', 50)` подряд, в 20 мс `cancel()` у `u2`, потом
ждать все исходы; первый раз с `concurrent()`, второй
с `(events, mapper) => events.flatMap(mapper, maxConcurrent: 2)`.

```text
--- concurrent()
10 ms: u1 starts
10 ms: u2 starts
10 ms: u3 starts
10 ms: u4 starts
10 ms: u5 starts
30 ms: u2 cancelled by its caller
30 ms: u2 stops
70 ms: outcomes [done, cancelled, done, done, done], state 4
--- pool of 2: flatMap(maxConcurrent: 2)
0 ms: u1 starts
0 ms: u2 starts
20 ms: u2 cancelled by its caller
30 ms: u2 stops
30 ms: u3 starts
60 ms: u4 starts
90 ms: u5 starts
150 ms: outcomes [done, cancelled, done, done, done], state 4
```

Claude прогнал оба зонда раунда 5 своей командой, вывод совпал, ссылки Opus
сверил с исходниками. Поломку B1 Claude признал своей: оговорку, найденную для
A, он в B пропустил.

## Итог

**Слабые стороны solo после раунда 5**, по Opus, по важности:

1. **Нет пула и очереди по ключу внутри линии.** Корни линии идут по одному.
   Рецепты владельца закрывают это частично, но теряют порядок по ключу и время
   отклика (A) или содержат ломающую ловушку и ломают `drain` (B). У bloc пул —
   одна строка трансформера. *Свойство модели*, а для рецептов — *пробел
   экосистемы*: готового API нет.
2. **Ошибки линий почти без инструмента.** Цикл через две линии молчит,
   `stale_emit` выключен по умолчанию и слеп к записи целиком
   (`packages/solo_lints/README.md:42-44`, `:113-118`, `:208-212`). *Свойство
   модели* и *пробел экосистемы*.
3. **Нет готовых `bloc_test` и `hydrated_bloc`** (`docs/backlog.md:20-33`).
   *Пробел экосистемы*, важность невысокая.
4. **Таблица `packages/solo/doc/state.md:785`** не называет запись другой
   линии. *Дефект документа.*
5. **Рецепт эпохи** не говорит, что запись новой эпохи целиком снимает чужие
   оптимистичные флаги (`packages/solo/doc/lanes.md:404-411`). *Дефект
   документа*, мелкий.
6. **Не выпущено.** Временное.

Снятые Opus доводы: откат «пропадает», смена смысла кода при переходе как
сравнительный довод, цикл через линии как сравнительный довод.

**Где solo сильнее**, по Opus: личная `Job` на каждый вызов — исход, отмена,
правила, `ifCancelled` — без самодельного билета, и в схемах A и B она работает
(`p2`, `p4` и `b` дают `Cancelled(manual)`, остальные `Done`); откат после
отмены по `restart`, которого у bloc нет вовсе; `keepWhile` вместо поколения
в каждой команде; партии с debounce и throttle из коробки (`collect`), где
у bloc нужен `stream_transform`.

**Предложение Opus** — линия с пределом одновременности,
`lane('uploads', concurrency: 4)`, или линия по ключу: каждый вызов получает
свою корневую `Job` с политиками, правилами, `ifCancelled`, `drain`
и `pending`. Опора — «Не цели» дизайна линий,
`2026-11-10-solo-lanes-design.md:100-102`:

> - Линия по ключу на лету (очередь на пост, на устройство). Её можно добавить
>   минором позже, если найдётся пример, где без очереди на сущность
>   не обойтись; сузить её обратно до объявленных было бы мажором.

Цена, которую Opus назвал сам: пересмотр посылки решения 84.

**Проверки свежим оппонентом не было.** После раунда 5 Claude снова
рекомендовал её: после пяти раундов у сторон общая слепая зона. Владелец выбрал
другое: «давай сделаем просто независимое ревью solo без прямого сравнения
с bloc. но попросим поискать похожие решения на pub.dev и сравнить с ними.
но сравнивать объективно, без авторитета других пакетов, их распространённости,
кол-ва звёзд и прочего. подумай, что ещё мы можем запросить у ревьюеров.
назначить Astra и Fable». Это ревью проведено на том же `f846472a` —
`2026-11-12-solo-project-review.md`. Находку о пуле и очереди по ключу Claude
ревьюерам не называл, чтобы проверить, придут ли они к ней сами; пул в линии
или очередь по ключу как недостающее API не предложил ни один, оба назвали
много сущностей границей модели.

## Что проверено

Во время спора Claude сверял цитаты Opus с деревом и исходниками до ответа:
в раунде 1 неверных ссылок не нашлось, в раунде 5 ссылки точные. Зонды bloc
обоих раундов и зонд solo раунда 5 Claude перезапускал своей командой, вывод
совпадал.

2026-11-18, при записи, три зонда solo — раундов 1, 4 и 5 — перезапущены
на той же копии `f846472a`: вывод совпал с процитированным выше строка
в строку, последние строки — `00:00 +3: All tests passed!`,
`00:00 +2: All tests passed!` и `00:00 +4: All tests passed!`. Зонды bloc при
записи не перезапускались. Состояние обоих дефектов и предложения проверено
по `main` на `00c4dbc0` и по голове ветки `solo-lanes` — ниже.

## Находки

### Н1. Таблица ручек отката не называет запись другой линии

`packages/solo/doc/state.md:785` в дереве `f846472a`, таблица «Handler
eligibility and errors»: первая строка перечисляет несовместимые записи,
которых задача не делала и которые навсегда выключают её `ifCancelled`
и `ifFailed`, — `externalSetState`, `emit` родителя, ребёнка или другого
ребёнка того же родителя. Запись задачи другой линии там не названа, хотя
`state.md:84` того же документа называет её третьим источником записи, а зонд
раунда 1 показал, что она выключает ручки так же. Нашёл Opus в раунде 1,
признал Claude в раунде 2, в итоге — пункт 4.

**Вердикт:** открыто, правка — по слову владельца. В `main` на `00c4dbc0`
строка — `packages/solo/doc/state.md:786`, и текст её прежний: «An incompatible
update the job did not make (`externalSetState`, or the `emit` of its parent,
of its child or of another child of the same parent)». `git log -S`
и `git log -L` по этой строке после спора правок не показывают; ветка
`solo-lanes` её тоже не трогает.

Итог 2026-11-18, по слову владельца «давай по открытому»: строка таблицы
в `state.md` и её перевод называют и `emit` задачи другой линии. Тест
не добавлялся: что такая запись отключает ручки навсегда, держит тест «a job
its rules cancelled gets no ifCancelled» в `lanes_rakes_test.dart`.

### Н2. Рецепт эпохи не говорит, что запись эпохи снимает чужие флаги

`packages/solo/doc/lanes.md`, раздел «Work that a new epoch makes stale»
(`:361-411` в дереве): `signOut` пишет `Feed(epoch: ctx.state.epoch + 1)`
целиком, и поэтому оптимистичная отметка лайка, отменённого правилом,
не остаётся висеть. Текст этого не говорит: пояснения под примером — об отмене
лайков и о том, что `ifCancelled` не зовётся, но не о том, что запись новой
эпохи целиком должна сама сбросить оптимистичные поля чужих линий, иначе флаг
зависнет, как `pending: true` в зонде раунда 1. Нашёл Opus в раунде 3, проверил
Claude, в итоге — пункт 5.

**Вердикт:** открыто, правка — по слову владельца. В `main` на `00c4dbc0`
раздел стоит в `packages/solo/doc/lanes.md:378-436`, пример и пояснения под ним
прежние: о том, что запись эпохи целиком снимает чужие оптимистичные флаги,
текста нет. `git log -L` по разделу последней называет правку `ea108546`
от 2026-11-11, то есть до спора: коммиты после него, тронувшие `lanes.md`
(`820936ed`, `a9953f9a`, `91e334f8`, `c058229d`), этот раздел не правили. Ветка
`solo-lanes` его тоже не трогает.

Итог 2026-11-18, тем же словом: в раздел эпохи `lanes.md` и его перевод
добавлен пункт о том, что отметку лайка снимает сам выход, потому что пишет
новый `Feed` без отметок, а выход, который перенёс бы отметки в новую эпоху,
оставил бы отметку `p1` в пути навсегда. Обе версии держит тест «the sign-out
takes down the mark the like put up» в `lanes_rakes_test.dart`.

### Предложение: линия с пределом одновременности или по ключу

`lane(..., concurrency: N)` или линия по ключу, с корневой `Job` на каждый
вызов, — предложение Opus из раунда 5 (выше, «Итог»), с пересмотром посылки
решения 84.

**Вердикт:** предложение, владелец его в работу не брал. В `docs/settled.md`
решения о нём нет, в `docs/backlog.md` записи нет, в записях 2026-11-12 и позже
решения тоже нет. Посылка решения 84 в `main` прежняя: «одновременно работающих
корней не больше, чем линий… линия по ключу на лету её бы меняла». Ревью
`2026-11-12-solo-project-review.md` пула не предложило; по его находке S2 Astra
страница линий говорит, что объявленный набор — для видов работы, а не для
каждого элемента растущего списка, и такие элементы берут контроллер каждый или
слой над контроллерами (`91e334f8`, конец «In the constructor body»
`lanes.md`).

Итог 2026-11-18: по слову владельца «Запиши пул в линии в бэклог» пул записан
в `docs/backlog.md` — подумать после выпуска `solo` 2.0.
