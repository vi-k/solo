# Прибор для `close`, который не вернулся без задачи

> **Состояние на 2026-09-30:** сделано по слову владельца «согласен. делай»
> и закоммичено вместе с этой записью, не отправлено; отчёт —
> `2026-09-30-close-hold-instrument-report.md`. Независимое ревью дизайна
> на Opus: P1 нет, четыре P2 и пять P3 приняты и внесены в текст.
> **Что это:** как `Solo.pending` будет называть два случая, где `close` ждёт,
> а задачи нет: слив, в очереди которого группа ждёт своего окна, и поток
> `SoloStream`, который ждёт приостановленного подписчика.
> **Связанные записи:** `2026-09-19-solo-project-review.md` (M4 и «Чего
> не хватает»), `2026-09-19-medium-findings-report-3.md`,
> `2026-09-30-close-hold-instrument-report.md`.

## Задача

M4 ревью `2026-09-19-solo-project-review.md` закрыт минимумом: `null`
у `Solo.pending` назван в dartdoc и документах «задача не идёт». Прибора,
который называл бы, чем держится `close` без задачи, нет. Владелец 2026-09-30
взял его в работу.

Сегодня `close()` держат три вещи, а `pending` называет одну:

| Что держит `close` | `pending` сейчас | Что знает движок |
| --- | --- | --- |
| задача: тело, дети или уборка | `SoloPending` | всё, что в таблице `doc/errors.md` |
| слив, в очереди которого нет готовой задачи: группа `collect` или `accumulate` ждёт окна | `null` | очередь и то, чья группа ещё не готова |
| поток `SoloStream`: движок закрыт, приостановленный подписчик не взял событие done | `null` | что `_controller.close()` вызван и не вернулся |

Оба `null` сторожит группа `a close held with nothing pending`
в `packages/solo/test/pending_test.dart`, и `errors_rakes_test.dart` держит
страницу: `pending is null while a group waits for its window`.

`null` у простаивающего контроллера и `null` у контроллера, чей `close` держит
очередь, неотличимы. Рецепт `doc/errors.md` «closing is held by
${controller.pending}» печатает `closing is held by null` в обоих случаях.

## Решение

`SoloPending` ещё не выпущен: он в `## Unreleased` `packages/solo/CHANGELOG.md`
и выходит в `0.3.0`. Поэтому его форму можно менять без миграции.

`SoloPending` становится `sealed`, у него три наследника:

```dart
@immutable
sealed class SoloPending {
  const SoloPending();
}

/// A job the controller is waiting for: what `SoloPending` is today.
final class SoloPendingJob extends SoloPending {
  final Job<Object?> job;
  final SoloPhase phase;
  final Cancelled? cancellation;
  final Cancelled? heldCancellation;
  final int children;
  final bool inUncancellableSection;
  final bool refusesCancellation;
  final bool closing;

  /// Whether the close is a drain: the job runs to its end by the usual
  /// rules rather than being cancelled.
  final bool draining;

  bool get cancellationPending => ...;
}

/// A drain with no job running: the queue it has still to run.
final class SoloPendingQueue extends SoloPending {
  /// The jobs the drain has still to run, in queue order.
  final List<Job<Object?>> jobs;
}

/// The engine has closed; the stream of `SoloStream` waits for a
/// subscription to take its done event.
final class SoloPendingStream extends SoloPending {
  const SoloPendingStream();
}
```

`Solo.pending`:

```dart
SoloPending? get pending {
  final current = _current;
  if (current != null) {
    return current._pending(closing: isClosed, draining: _draining);
  }
  if (_draining) {
    final jobs = [
      if (_inTransition case final job?) job,
      ..._queue._jobs,
    ];
    if (jobs.isNotEmpty) return SoloPendingQueue(List.unmodifiable(jobs));
  }
  return null;
}
```

Список — копия, а не вид на `_queue._jobs`: снимок, взятый раньше, не меняется
вместе с очередью. `_inTransition` идёт первым: пока движок спрашивает правила
задачи, она снята с очереди и ещё не `_current`, а его же комментарий зовёт её
«queued work until it is launched». Правило, которое закрыло контроллер сливом
и спросило `pending`, увидит в нём свою задачу, а не соседа за ней.

Очередь без готовой задачи — то, что видно не дольше микрозадачи. `_takeFirst`
обходит группу, чьё окно не открылось, и берёт готовую за ней, а насос крутит
цикл. Поэтому, если задача не идёт и микрозадача прошла, в `jobs` лежат только
группы, которые держит их время. Готовая задача в `jobs` видна синхронно: сразу
после `close(mode: drain)` или из хука, пока насос не пришёл. Отдельный список
«держит время» поэтому не нужен: вне этой микрозадачи он совпадал бы с `jobs`.
Это инвариант, и он идёт в dartdoc.

`SoloStream` переопределяет `pending`:
`super.pending ?? (_streamClosing ? const SoloPendingStream() : null)`. Флаг
ставится в `.then` перед `_controller.close()` и снимается его `.whenComplete`.
`_controller.close()` не бросает: контроллер закрытый и приватный, `addStream`
на нём нет.

После правки `null` значит «`close` ничто не держит, о чём знает контроллер»:
задача не идёт, слив не ждёт очереди, поток не ждёт подписчика. Оговорки идут
в dartdoc:

- `close`, который заканчивается, читает `null` из `onFinish` своей последней
  задачи и из `onClose`: задача уже снята с `_current`, а `close` вернётся
  через микрозадачу. То же у простаивающего контроллера сразу после `close()`.
  Хук последнего подписчика `onDone` ещё видит `SoloPendingStream`. Таймер эти
  окна не застаёт никогда, а синхронный хук и наблюдатель — застают;
- подкласс, чей `close` ждёт своего до или после `super.close`, держит его сам,
  и контроллер об этом не знает. Для уборки домена есть хук `onClose` (M6).

`toString` всех трёх начинается с `SoloPending(`. Трассы на странице
`doc/errors.md` — `SoloPending([stuck] in its body)` — остаются как есть: лог
читают глазами, и имя подкласса там ничего не добавляет. Задача
в `SoloPendingQueue` названа так же, как в `SoloPendingJob`: `[key]` или
`[key: description]`. Под сливом `SoloPendingJob` пишет `draining` вместо
`closing`, как и строка очереди: иначе читающий лог видит `closing` без
`cancelled by` и сам гадает, слив это или застрявшая отмена. Новые строки:

```text
SoloPending([b] in its body, draining)
SoloPending(draining, 1 queued: [g])
SoloPending(stream: a subscription has not taken its done event)
```

Точная форма строки — при реализации; её держит сторож.

## Почему так

- **Одно место спросить.** Рецепт «closing is held by …» остаётся одной строкой
  и начинает говорить правду во всех трёх случаях. Кто разбирает случаи, пишет
  `switch` по `sealed` и получает от анализатора пропущенный случай.
  Исчерпывающий `switch` с веткой `null` и деструктуризацией собирается: зонд
  ревьюера `probe_switch_test.dart`.
- **`SoloPendingQueue` только под сливом.** Без `close` группа, ждущая окна,
  ничего не держит: контроллер простаивает, и `null` это и говорит.
  `close(mode: cancel)` очередь снимает сразу, так что держать нечем.
- **Поля задачи остаются только у задачи.** Втиснуть очередь и поток в один
  класс с `job` и `phase` значило бы сделать `job` nullable или назначить
  задачей первую из очереди, у которой ни отмены, ни детей: поля начали бы
  врать о пустом.
- **Список задач, а не число.** Читающему лог нужно знать, какая группа держит
  слив, а геттер `Solo.queue` защищённый, и снаружи очереди не видно.
- **Поток — наследник без полей.** Широковещательный `StreamController`
  не говорит ни сколько подписчиков, ни какой приостановлен, а `isPaused`
  у него `false` и с приостановленным подписчиком. Зонд
  `.artifacts/2026-09-30-close-hold/probe_paused_test.dart`:
  `isPaused=false hasListener=true`, `done after close with paused: false`,
  `done after resume: true`. Честно назвать можно только сам факт.

## Цена

- **Ломающая для тех, кто читал поля.** `pending!.phase` больше
  не компилируется, и `pending?.phase` тоже: нужен `switch`, образец
  `SoloPendingJob(:final phase)` или `(pending as SoloPendingJob?)?.phase`.
  `SoloPending` не выпущен, так что миграции нет: пункт `Add Solo.pending`
  в `CHANGELOG.md` переписывается, а не дополняется «Breaking».
- **Иерархию не расширить снаружи.** `sealed` наследуется только в своей
  библиотеке: миксин домена, который держит `close` своим, через `pending`
  об этом не скажет никогда, и вторая оговорка выше постоянная. Четвёртый
  наследник позже ломает исчерпывающие `switch` пользователей. Ветку
  `SoloPendingStream` пишет и тот, у чьего контроллера потока нет.
- **Очередь видна снаружи.** `pending` публичный, а `SoloPendingQueue.jobs`
  отдаёт ручки задач очереди, и у `Job` есть `cancel()`. Доступ к очереди
  у контроллера защищённый: вызывающий видит операции, а не то, как они встали
  в очередь. Прецедент есть — `SoloPending.job` уже отдаёт то же, что
  защищённый `current`, — но здесь это вся очередь, а не одна задача.
  Принимается ради лога: ключ и описание задачи — это и есть `Job`.
- **Виртуальный `pending`.** Чтобы `SoloStream` добавил свой случай, геттер
  переопределяется миксином. Он и сейчас не `@nonVirtual`.

Меняются документы:

- `packages/solo/lib/src/pending.dart`: dartdoc класса и полей переезжает
  к `SoloPendingJob`, у базы свой текст, у двух новых — свой;
- dartdoc `Solo.pending` и `SoloStream.close`;
- `packages/solo/doc/errors.md`, раздел «What is holding the controller»: фраза
  над таблицей «`SoloPending` is a snapshot of the job» и сама таблица говорят
  о `SoloPendingJob`, абзац «`null` says that no job is running» заменяется
  абзацем о двух новых случаях; «`SoloPending` answers while the job is still
  running» дальше на странице называет `SoloPendingJob`;
- `packages/solo/doc/state.md`, абзац о потоке, который держит `close()`;
- переводы `docs/ru/solo/errors.md` и `docs/ru/solo/state.md`;
- `packages/solo/CHANGELOG.md`: пункт `Add Solo.pending` переписывается, пункт
  о `null` из минимума M4 уходит в него;
- вердикт M4 в `2026-09-19-solo-project-review.md` получает итог, а пункт
  «Прибора для „`close` не вернулся“ вне задачи» в «Чего не хватает» — ссылку
  на него.

Проверено, правки не нужно: `doc/jobs.md` и перевод — «pending answers with the
gate» остаётся правдой, README `solo` и перевод, остальные пункты
`CHANGELOG.md` о `pending`, `tool/doc_snippets.py` — его `pending` другой.
`flutter_solo` ни `close`, ни `pending` не переопределяет и не читает.

## Сторожа

- Группа `a close held with nothing pending` в `pending_test.dart`
  переименовывается и ждёт `SoloPendingQueue` и `SoloPendingStream` вместо
  `isNull`; каждому — `null` после того, как `close` вернулся.
- Слив с готовой задачей и группой за ней, прочитанный синхронно сразу после
  `close(mode: drain)`: `jobs` — обе в порядке очереди. После микрозадач —
  `SoloPendingJob` с `draining`, после неё — `SoloPendingQueue` с одной
  группой. Тест говорит в тексте, что читает синхронно.
- Слив, закрытый из `canStart`: в `jobs` первой стоит задача, чьё правило
  спрашивают.
- Простаивающий контроллер: `close(mode: drain)`, прочитанный синхронно, —
  `null`; `pending` из `onFinish` последней задачи слива — `null`.
- Снимок `SoloPendingQueue` сохраняет свой список, когда очередь опустела.
- Простаивающий контроллер с группой, ждущей окна, без `close`: `null`.
- `close(mode: cancel)` поверх слива: `SoloPendingQueue` уходит.
- `SoloStream` со сливом и приостановленным подписчиком: `SoloPendingQueue`,
  затем `SoloPendingStream`, затем `null`, в этом порядке.
- `errors_rakes_test.dart`: сторож страницы о `null` меняет смысл на новый
  абзац; сторож таблицы читает поля через `SoloPendingJob`.
- `toString` каждого наследника: строки, которые цитирует страница.

Мутации: `pending` без ветки очереди; без проверки `_draining`; без проверки
пустой очереди; без `_inTransition`; вид на `_queue._jobs` вместо копии;
`draining` всегда `false`; `SoloStream` без переопределения; флаг потока,
поставленный при вызове, а не перед `_controller.close()`; флаг, не снятый
по завершении; порядок `super.pending ??` наоборот.

## Вне этой работы

- Под сливом с идущей задачей `SoloPendingJob` не говорит, сколько задач ждёт
  за ней. Слив ждёт и их, но задача названа, и следующий вопрос — к ней.
- Сторож, который сам заметил бы зависший `close`, — это бэклог «Общий отлов
  зависаний», решено оставить рецептами.

## Ревью

Независимый ревьюер на Opus, по копии дерева на `6e0e723`. Собрал дизайн
прототипом в отдельной копии: полный набор `solo` падает ровно на четырёх
тестах, которые дизайн предсказывает, `flutter_solo` зелёный. Состояния, где
`close` держится дольше микрозадачи, а `pending` молчит, не нашёл. P1 нет. Его
зонды `probe_hold_states_test.dart` и `probe_switch_test.dart` и файлы
прототипа перенесены в `.artifacts/2026-09-30-close-hold/`, не под гитом;
восемь случаев первого я прогнал сам на его прототипе, вывод совпал с его
отчётом.

1. **P2: окна `null` не две, а больше, и правило видит не свою задачу.**
   `onFinish` последней задачи и `onClose` читают `null`, пока `close`
   не вернулся; `onDone` подписчика ещё видит поток. Правило, закрывшее
   контроллер сливом, видело в `jobs` соседа за своей задачей. Вердикт:
   принято; оговорки в dartdoc расширены, `_inTransition` идёт первым в `jobs`.
2. **P2: вне синхронного чтения «держит время» совпадает со всем списком.**
   Вердикт: принято; второй список снят, инвариант идёт в dartdoc, сторож
   смешанной очереди читает синхронно.
3. **P2: мутацию «очередь без проверки на пустоту» не ловит ни один сторож.**
   Вердикт: принято; добавлены сторожа простаивающего слива и `onFinish`,
   снимка, порядка очередь — поток — `null`, и мутации к ним.
4. **P2: список документов неполон.** Не названы пункт минимума M4
   в `CHANGELOG.md`, фраза над таблицей и «`SoloPending` answers…»
   в `doc/errors.md` с переводом, dartdoc полей, вердикт M4 и пункт «Чего
   не хватает» в записи ревью, форма `pending?.phase`. Вердикт: принято, список
   в «Цене» дополнен.
5. **P3: `sealed` не растёт.** Вердикт: принято в «Цену»; выбор `sealed`
   ревьюер поддержал.
6. **P3: `SoloPendingJob` под сливом не говорит «draining».** Вердикт: принято;
   поле `draining` и слово в строке.
7. **P3: `jobs` отдаёт ручки очереди публично.** Вердикт: принято в «Цену»
   сознательно.
8. **P3: фрагменты дизайна теряют `@immutable`, конструктор базы и копию
   списка; ключ без имени пишется `[null]`.** Вердикт: принято; фрагменты
   поправлены, `[null]` — как у `SoloPending` сегодня.
9. **P3: «`SoloQueue.jobs` защищённый» неточно, защищённый геттер
   `Solo.queue`.** Вердикт: принято.
