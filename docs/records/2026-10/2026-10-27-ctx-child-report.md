> **Состояние на 2026-10-27:** сделано и влито в `main`, не опубликовано:
> `ctx.child` выйдет с `async_job` 0.5.0, `SoloContext.child` — со следующим
> выпуском `solo`.
> **Что это:** отчёт о работе над `ctx.child`: что сделано, проверки и оба
> ревью работы, Opus и codex, с вердиктами.
> **Связанные записи:** `2026-10-27-ctx-child-design.md` — дизайн и его ревью;
> `2026-10-27-ctx-child-plan.md` — план и его ревью.

# `ctx.child`: отчёт

## Откуда

Заявка сессии HisBible: общий код, у которого есть только `JobContext`, не мог
сделать ребёнка, которого примет любой движок. `Job.deferred` — ребёнок ядра,
и контроллер `solo` его отвергает. Решение владельца 2026-10-27 — фабрика
`ctx.child` в контексте; дизайн и план — в связанных записях.

## Что сделано

Коммиты по шагам плана:

- `694f4a22` — оверрайды `async_job` на дерево у `solo` и его примера;
- `3c708ed6` — `JobContext.child` и `JobContextBase.child` с `@useResult`,
  `createEachJob` берёт ребёнка у `child`, тесты 1–8 дизайна;
- `8119ea36` — `SoloContext.child`: задача того же контроллера с `W`
  и `keepWhile` создателя, текст отказа называет `ctx.child`, тесты 9–18;
- `ad0af1eb` — тест: переданный ребёнок берёт наблюдателя задачи, которая его
  запускает;
- `260c7512` — вердикты ревью плана и решения 112–115 `docs/settled.md`;
- `79ba66d9` — документы ядра: README, `children.md`, `time.md`,
  `extending.md`, `engine.md`, dartdoc `ChildJob`, CHANGELOG;
- `03db0b32` — документы `solo` и `docs/architecture.md`.

Коммит этого отчёта — правки по обоим ревью работы, разобранные ниже.

## Ревью работы: Opus

Субагент Opus, своя копия на `03db0b32`, около 17 минут. Прогон по его разделу
«Прогон»: полные наборы `solo` (+2131) и `async_job` (+1884; до этого под
нагрузкой машины около 72 краснел тест на время `let_go_together_test.dart`,
повтор зелёный), анализ, формат, проверки документов, два зонда и 18 мутаций;
примеры, `flutter_solo`, стенды и пол не гонял — это шаг 6, его делал автор.
Находки — Н1–Н7.

### Находки

#### Н1. P2 — обещание «`SoloContext.child` ничего не проверяет» без сторожа

**Место.** `packages/solo/lib/src/job_context.dart`, `_SoloContext.child`;
`packages/solo/test/child_factory_test.dart`; dartdoc `JobContext.child`
(«Starts nothing and checks nothing, so it never throws for the state of this
job»), пункт 113 `docs/settled.md`.

**Суть.** В ядре это обещание держат пять тестов группы
`child makes a child wherever run refuses one` (`unattended`, уборка, конец
тела, законченная задача, принятая отмена). У переопределения в `solo` таких
тестов нет. Два мутанта, которые добавляют проверку в `_SoloContext.child`,
проходят оба полных набора:

- MS10 — проверка правил при создании, как в `createEachJob`:
  `if (pendingCancel == null) { _checkedState(); }`;
- MS11 — `throwIfFinished('child')`.

**Механика.** `createEachJob` в `solo` теперь зовёт `child`, поэтому мутанты,
которые ломают путь `each`, ловят тесты `each` (MS7, MS8 ниже). А проверку,
которую `each` и так делает, `each` заметить не может, а тесты `child` в `solo`
зовут его только на живой задаче с выполненными правилами. Это ровно та ошибка,
от которой предостерегают пункт 113 и ответ codex на вопрос 2 в дизайне
(«перенос такой проверки в `child` нарушил бы обещание фабрики»): общий код,
который держит контекст задачи, нарушившей правила, получил бы `Cancelled`
из фабрики вместо ребёнка.

**Доказательство.** Как ведёт себя дерево (зонд, тест
`probe: child where run refuses, in solo`): задача `enqueue<Preparing, void>`
с `keepWhile: (s) => s.progress < 50` зовёт `ctx.child` в `unattended`
и в `onDispose`, а после конца задачи
и `externalSetState(Preparing(progress: 60))` — на утёкшем контексте:

```dart
ctx.unattended(() async {
  final c = ctx.child((c) async {});
  made.add('unattended: ${c.outcome}');
  c.cancel().ignore();
});
ctx.onDispose(() {
  final c = ctx.child((c) async {});
  made.add('cleanup: ${c.outcome}');
  c.cancel().ignore();
});
// после конца задачи, правила нарушены:
final c = leaked.child((c) async {});
made.add('finished, rules broken: ${c.outcome}');
```

```text
unattended: null
cleanup: null
finished, rules broken: null
```

Под мутантами:

```text
== MS10 solo child checks the rules when made, as each does
  async_job: 00:15 +1884: All tests passed!
  solo: 00:05 +2131: All tests passed!
== MS11 solo child refuses a finished job
  async_job: 00:15 +1884: All tests passed!
  solo: 00:05 +2131: All tests passed!
```

**Предложение.** В `packages/solo/test/child_factory_test.dart` — группа
по образцу ядра: `child` на задаче, чьи правила уже нарушены (после
`externalSetState`), на законченной, в `unattended`, в уборке и после принятой
отмены возвращает ребёнка с `outcome == null`, и другая задача контроллера его
запускает (или он кончается `Cancelled(rules)` на старте, если правила
создателя его не пускают). Хватит и двух случаев: «правила нарушены» убивает
MS10, «задача закончена» — MS11.

**Вердикт.** Принято: тест
`child checks nothing: not the rules, nor the end of the job`
в `packages/solo/test/child_factory_test.dart`. Ребёнок сделан в `unattended`,
в уборке и на законченной задаче с нарушенными правилами; фабрика ничего
не бросает, первых двух запускает другая задача контроллера, третьего правила
создателя отвергают на старте. MS10 и MS11 под ним красные. Совпадает
с находкой 3 codex. Случай «после принятой отмены» отдельно не добавлен: его
держат тесты `each` (MS7, MS8).

#### Н2. P3 — `@useResult` на `JobContextBase.child` без сторожа

**Место.** `packages/async_job/lib/src/job_context.dart`,
`JobContextBase.child`; `packages/solo/test/child_factory_test.dart`, тест
`a child made and dropped is a warning, through either context`.

**Суть.** П9 ревью плана: аннотацию переопределение не наследует, поэтому она
стоит и на `JobContextBase.child` — ради тела движка, чей контекст типизирован
своим классом. Тест 18 проверяет вызов через `JobContext` и `SoloContext`,
но не через наследника `JobContextBase`. Мутант MC6 (аннотация снята
с `JobContextBase.child`) проходит оба полных набора. Копия `compileWarnings`
в `packages/async_job/test/support/compile_errors.dart` в ядре не используется
ни одним тестом.

**Доказательство.** Зонд `packages/async_job/test/zz_warn_test.dart`:

```dart
final warnings = await compileWarnings('''
import 'package:async_job/engine.dart';

final class MyContext extends JobContextBase {
  MyContext(super.owner);
}

void ofEngine(MyContext ctx) {
  ctx.child<void>((ctx) async {});
}
''');
print('warnings: $warnings');
```

На дереве:

```text
warnings: [unused_result: The value of 'child' should be used.]
```

Под MC6:

```text
warnings: []
```

```text
== MC6 no useResult on JobContextBase.child
  async_job: 00:17 +1884: All tests passed!
  solo: 00:06 +2131: All tests passed!
```

**Предложение.** Тест в ядре на `compileWarnings` с этим фрагментом: так сторож
встаёт рядом с аннотацией, и копия помощника в ядре перестаёт быть мёртвой.

**Вердикт.** Принято: тест
`a child dropped in the body of an engine is a warning`
в `packages/async_job/test/child_factory_test.dart` зовёт `child` через
наследника `JobContextBase`. MC6 под ним красный, копия `compileWarnings`
в ядре теперь в деле. Совпадает с находкой 4 codex.

#### Н3. P3 — отказ чужому ребёнку `ctx.child` советует `ctx.child`

**Место.** `packages/solo/lib/src/solo.dart`, `_notCreatedHere`.

**Суть.** Ребёнка, сделанного `ctx.child` в задаче контроллера A, задача
контроллера B отвергает текстом, который советует сделать его «with
ctx.child» — так он и был сделан. Совет верен только для `ctx` этого
контроллера, а текст об этом молчит.

**Доказательство.** Зонд, тест `probe: child of another controller`: `other` —
второй `TestSolo`, его задача делает `foreign = ctx.child((c) async => 1)`,
задача `solo` зовёт `ctx.run(foreign)`:

```text
foreign: Invalid argument (job): was not created by this Solo (make it with job(...) of this controller or with ctx.child): "Job()"
```

**Предложение.** «make it with job(...) or ctx.child of this controller». Цитат
пять (`children_test.dart`, `children_rakes_test.dart`, `start_test.dart`,
`doc/children.md`, `docs/ru/solo/children.md`), правятся одним коммитом. Или
оставить как есть: вред только в лишнем шаге отладки.

**Вердикт.** Принято: отказ — «make it with job(...) or ctx.child of this
controller», пять цитат правятся тем же коммитом.

#### Н4. P3 — dartdoc `SoloContext.child`: правила действуют «на старте»

**Место.** `packages/solo/lib/src/job_context.dart`, dartdoc
`SoloContext.child`: «keeps this job's working type `W` and `keepWhile` rule,
so a state they refuse cancels it at the start with `Cancelled(rules)`».

**Суть.** Правила создателя действуют на ребёнка всю его жизнь, а не только
на старте: смена состояния, которую не пускает `keepWhile` создателя, отменяет
уже идущего ребёнка его собственной причиной `rules`. Для ребёнка, переданного
другой задаче, это значит, что правило создателя оборвёт его посреди работы под
чужим родителем. Фраза «at the start» читается как «только на старте». Dartdoc
`each` рядом говорит «keeps … including after the parent's body ends» без
такого сужения.

**Доказательство.** Зонд, тест `probe: keepWhile broken while the child runs`:
родитель `enqueue<Preparing, void>` с `keepWhile: (s) => s.progress < 50`
запускает `ctx.child((c) => c.abandonable(() => delay(100)))`, через 10 мс —
`externalSetState(Preparing(progress: 60))`:

```text
parent caught: Cancelled(rules: keepWhile)
child: Cancelled(rules: keepWhile); parent: Cancelled(rules: keepWhile)
```

**Предложение.** «so a state they refuse cancels it with `Cancelled(rules)`, at
the start or while it runs». Строку справочника `reference.md` и абзац
`children.md` это не задевает: там «with the working type and `keepWhile`».

**Вердикт.** Принято: dartdoc `SoloContext.child` — «cancels it with
`Cancelled(rules)`, at the start or while it runs». Сторож — тест
`cancel a child that runs under another job`: ребёнок кончается
`Cancelled(rules)`, а задача, которая его запустила, — `Cancelled(handler)`.

#### Н5. P3 — handoff и комментарий оверрайдов разошлись с деревом и планом

**Место.** `docs/handoff.md`, абзац «Оверрайды снова в дереве…»; первые строки
четырёх `pubspec_overrides.yaml`.

**Суть.** Абзац говорит только «`flutter_solo` и его пример держат `solo`
из дерева до выпуска `solo` после 0.4.0», а абзацем выше — «Оверрайды `solo`
и его примера сняты 2026-10-25». С `694f4a22` в дереве оверрайды `async_job`
в `packages/solo`, `packages/solo/example` и у обоих `flutter_solo`. Абзац
об `ctx.child` упоминает их одним словом («оверрайды на ядро из дерева»),
но не до чего они живут. Вердикт О4 обещал «абзац в handoff». Комментарий
в файлах — «Use the next async_job release from this checkout until it is
published.», а план (шаг 1) и дизайн («Почему ломающее») называют «Use local
async_job until 0.5.0 is published.» / «до выпуска `async_job` 0.5.0».

**Предложение.** Переписать абзац handoff: какие четыре файла держат что
и до какого выпуска. Комментарий оставить или назвать 0.5.0, но дизайн и план
привести к тому, что в дереве.

**Вердикт.** Принято: абзац handoff называет все четыре файла и то, до чего
каждый живёт. Комментарий двух файлов `solo` — «until 0.5.0 is published», как
в плане; дизайн и план не правились, они и так говорят 0.5.0.

#### Н6. P3 — строка шапки записи дизайна шире 79

**Место.** `docs/records/2026-10/2026-10-27-ctx-child-design.md`, строка 2.

**Суть.**
`> дизайн исправлен по вердиктам; реализация идёт по плану, ядро и `solo` готовы.` —
80 символов. `check_line_width.py` записи пропускает («`docs/records/` is not
checked»), а `reflow.py` цитаты не трогает, поэтому ни одна проверка этого
не ловит. Остальные строки шире 79 в обеих записях — блоки кода, таблицы
и заголовки.

**Доказательство.** Подсчёт символов питоном по обеим записям:
`design.md 2 80`.

**Предложение.** Перенести «готовы.» на следующую строку шапки при очередном её
обновлении.

**Вердикт.** Принято: строка перенесена тем же коммитом, при обновлении шапки
дизайна.

#### Н7. P3 — CHANGELOG ядра не говорит движку, что `child` надо переопределить

**Место.** `packages/async_job/CHANGELOG.md` и перевод, «Breaking changes»
и «Added»; `doc/time.md`, «A deadline for one step»: «made by `ctx.child`,
which any engine of the job accepts».

**Суть.** «Breaking» перечисляет только поломки компиляции. Тихая поломка для
чужого движка — того, что владеет детьми (как `solo`) или держит правила
в `check()`, — в том, что после обновления `ctx.child` в его телах
компилируется и отдаёт `Job.deferred`: его `run` такого ребёнка отвергнет, или
ребёнок не спросит правило. «Added» говорит об этом описательно («An engine
whose children are jobs of its own overrides it»), без слов о том, что движку
теперь надо сделать. Движок, который ради своих детей переопределял
`createEachJob`, — ровно такой: до 0.5.0 ему хватало этого крючка. «Any engine»
на `time.md` верно только для движков, которые это сделали.

**Доказательство.** Тест
`an engine with rules that keeps child gets a child of the core`
в `extending_test.dart`: контекст ребёнка — не `CheckingContext`, ребёнок
доходит до конца после того, как правило сломалось.

**Предложение.** В «Breaking changes» ядра — фраза для движков: «An engine that
makes children of its own, in `createEachJob` or elsewhere, or keeps rules in
`check`, overrides `child`: the default is a `Job.deferred`». На `time.md` —
«which the engine of the job accepts», как в dartdoc.

**Вердикт.** Принято: в «Breaking changes» ядра и перевода стоит фраза для
движка, который делает своих детей или держит правила в `check()`: он
переопределяет `child` с `@useResult`, потому что по умолчанию это
`Job.deferred`. `time.md` и перевод говорят «the engine of the job» вместо «any
engine».

### Мутации

| Мутант | Что сделано | Кто убил |
| --- | --- | --- |
| MC1 | `JobContextBase.child` без `timeout` | 4 теста `child_factory_test.dart` ядра (`the timeout of a child …`, нулевой срок, `uncancellable`) и `time_rakes_test.dart: A deadline a step with a deadline goes out without its thumbnail` |
| MC2 | `JobContextBase.child` без `key` | `a child made by the context runs and hands its value over`, `a child handed to another job runs there`, `time_rakes_test.dart: … rethrows a thumbnail somebody else cancelled` |
| MC3 | `JobContextBase.child` без `describe` | `a child made by the context runs and hands its value over` |
| MC4 | `createEachJob` ядра — `Job.deferred` мимо `child` | `extending_test.dart: an engine that overrides child gives each its children too` |
| MC5 | без `@useResult` на `JobContext.child` | `solo` `child_factory_test.dart: a child made and dropped is a warning, through either context` |
| MC6 | без `@useResult` на `JobContextBase.child` | **никто**, оба полных набора зелёные (Н2) |
| MC7 | `JobContextBase.child` зовёт `throwIfFinished('child')` | `child makes a child wherever run refuses one in cleanup`, `… on a finished job` |
| MS1 | `_SoloContext.child` без `timeout` | `child_shared_code_test.dart: … gets the deadline of its step as Cancelled(timeout)`, `… let out, it reaches ifCancelled of the parent`, `child_factory_test.dart: a timeout of zero or less throws from child, before run` |
| MS2 | `_SoloContext.child` без `keepWhile` | `child_factory_test.dart: … hold after its body has ended, and turn the child away`, `each_child_test.dart: keepWhile stops a child after the parent body returned` |
| MS3 | `_SoloContext.child` без `describe` | 8 тестов `each_test.dart` и `each_child_test.dart`, среди них `a child is named by the key and describe given to each`; ни одного теста `child` |
| MS4 | `_SoloContext.child` без `key` | `child_shared_code_test.dart: … runs its child`, `each_child_test.dart: a child is named by …` |
| MS5 | `_SoloContext.child` берёт `cancellable` создателя | `child_factory_test.dart: … leave canStart out and cancellable: false to the maker`, `each_child_test.dart: a noncancellable parent can still have its subscription cancelled` |
| MS6 | `_SoloContext.child` повторяет `canStart` создателя | тот же тест `child_factory_test.dart`, `each_child_test.dart: canStart is not repeated …` |
| MS7 | `_SoloContext.child` зовёт `_checkedState()` всегда | `each_test.dart: after the job emits a state its rules refuse a job that has accepted a cancellation is left to it` |
| MS8 | `_SoloContext.child` зовёт `throwIfFinished` и `throwIfCancelled` | тот же тест `each_test.dart` |
| MS9 | без `@useResult` на `SoloContext.child` | `child_factory_test.dart: a child made and dropped is a warning, through either context` |
| MS10 | `_SoloContext.child` зовёт `_checkedState()`, если отмена не принята | **никто**, оба полных набора зелёные (Н1) |
| MS11 | `_SoloContext.child` зовёт `throwIfFinished('child')` | **никто**, оба полных набора зелёные (Н1) |

Мутации дизайна (MC1, MC4, MC5, MS1, MS2, MS9) краснеют, как обещает handoff.
Мутант «снять `child` из `SoloContext` и `_SoloContext`» не повторял: вердикт
П11 записывает его итог, а `child_factory_test.dart` без члена не соберётся.

MS3 убивают только тесты `each`: имя ребёнка `ctx.child` в `solo` (`describe`)
ни один тест `child` не проверяет. Сейчас это держит общий путь через
`createEachJob`, и отдельной находки я не завёл.

### Чего не хватает до мержа и выпуска 0.5.0

До мержа:

- Н1: тест «`child` в `solo` ничего не проверяет».
- Шаг 6 плана: примеры, `flutter_solo`, стенды, `dart doc --dry-run`, пол
  в отдельной копии — в этом ревью не гонялись.
- Запись `2026-10-27-ctx-child-report.md` с вердиктами по ревью работы и шапки
  дизайна и плана — «смержено», с коммитом.
- Н5: абзац handoff об оверрайдах.

До выпуска (вне этой работы, по `AGENTS.md`, отдельной просьбой владельца):

- `async_job/pubspec.yaml` — `version: 0.5.0`, заголовок «## 0.5.0»
  в `CHANGELOG.md` и переводе.
- `solo/pubspec.yaml` держит `async_job: ^0.4.0`, а это `<0.5.0`: новое ядро
  туда не входит, а на 0.4.x `SoloContext.child` не соберётся. Нужен
  `async_job: ^0.5.0`. Пока живут оверрайды, `floor` этого не ловит, так что
  ограничение надо поднять руками при снятии оверрайдов.
- Абзац выпуска `solo` о реэкспорте ядра со ссылкой на его CHANGELOG, как
  у 0.3.0 и 0.4.0.
- Сообщение сессии scopo в день выпуска ядра (П14) и сессии HisBible после
  вливания.

## Ревью работы: codex

`gpt-6-astra`, усилие `xhigh`, своя копия на `03db0b32`. Прогон по его разделу
ПРОГОН: полные наборы `solo` (+2131) и `async_job` (+1884 с `--concurrency=1`;
первый прогон параллельно с `solo` дал пять красных тестов на время и глубину
стека, повтор зелёный), пример `solo`, анализ, формат, проверки документов, два
зонда и десять мутаций; отказов песочницы не было. Приложения с исходниками
двух зондов не перенесены: их выводы стоят в находках. Находки — 1–4.

### Находки

Ошибки исполнения новой фабрики на исходном HEAD не подтверждены. Найдены
ошибка внутренней документации и три пробела сторожей. Пункты 112–115
`docs/settled.md` не оспариваются: предложения сохраняют выбранное поведение.

#### 1. P1 — инвариант об уборке всё ещё запрещает новый `child`

**Место:** `docs/architecture.md`, раздел «Инварианты», пункт 8, абзац
«Отдельная фаза — уборка» (строки 348–353). Связанный код:
`packages/solo/lib/src/job_context.dart`, `_SoloContext.child`,
и `packages/async_job/lib/src/job_context.dart`, `JobContextBase.child`.

**Суть.** Документ говорит: «контекст тела закрыт целиком. Законны только
`log`, `job`, сами регистрации (`onDispose`, `onDiscard`, `disown`)
и `unattended`». Это исчерпывающий список без `child`. Для новой фабрики
утверждение неверно. Карта модулей того же документа уже говорит, что `child`
ничего не проверяет; два раздела теперь противоречат друг другу.

**Механика.** Фабрика вызывает конструктор задачи, не проверяя фазу создателя.
В уборке можно создать ребёнка и передать его другой задаче. Старому контексту
запрещён именно запуск. Ошибочный инвариант подталкивает к добавлению проверки
в фабрику и тем самым к нарушению решения 113. По заданной шкале P1 здесь
относится к вводящему в заблуждение документу; текущий исполняемый код этого
дефекта не имеет.

**Доказательство.** Зонд из приложения A, ветка `cleanup`:

```dart
child = saved.child((ctx) async => ctx.state);
print('$stage: factory=created');
try {
  saved.run(child!).ignore();
} on Object catch (error) {
  print('$stage: own run=${error.runtimeType}');
}
```

Этот код вызван из `ctx.onDispose(make)`. После завершения создателя
`solo.run<int, int>((ctx) => ctx.run(child!))` запускает тот же хэндл. Точные
строки вывода исходника:

```text
cleanup: factory=created
cleanup: own run=StateError
cleanup: other run=Done(1)
```

**Предложение.** Добавить `child` в разрешённые члены инварианта 8 и явно
отделить создание хэндла от запуска. Заодно назвать его в перечне членов,
работающих после завершения задачи, непосредственно выше.

**Вердикт ревьюера:** Несоответствие документа реализации подтверждено; править
документ, сохраняя нынешнюю фабрику.

**Вердикт.** Принято: инвариант 8 `docs/architecture.md` называет `child`
в обоих перечнях — среди членов, которые после конца задачи не бросают, и среди
законных в уборке, — с оговоркой, что отказывают члены, которые запускают.
Тяжесть — по шкале задания: документ, а не код.

#### 2. P2 — полный набор `solo` пропускает удвоение срока ребёнка

**Место:** `packages/solo/test/child_shared_code_test.dart`, `loadWithin`, тест
`gets the deadline of its step as Cancelled(timeout)` и группа
`a deadline of a child of the controller`. Изменяемое место —
`_SoloContext.child`, аргумент `timeout` вызова `_solo.job`
в `packages/solo/lib/src/job_context.dart:189`.

**Суть.** Сторожа видят тип причины отмены, исход родителя и продолжение
очереди, но не переданное значение срока и не момент отмены. Все 2131 тест
прошли с неверной передачей длительности.

**Механика.** В сценарии таймаута работа занимает 50 мс, срок равен 10 мс.
После `async.flushTimers()` и 10, и 20 мс дают ту же отмену. У успешного
сценария работа занимает 10 мс при сроке 100 мс; удвоение также не меняет
исход. Проверка нуля и отрицательных длительностей сохраняется.

**Доказательство.** Мутация M1, одна замена:

```diff
-        timeout: timeout,
+        timeout: timeout == null ? null : timeout * 2,
```

Полный набор мутанта:

```text
00:16 +2131: All tests passed!
```

В приложении A ребёнок ждёт 50 мс через `ctx.pause`, а вызывающий передаёт
`timeout: const Duration(milliseconds: 10)`. Контрольные строки зонда:

```dart
clock.elapse(const Duration(milliseconds: 10));
print('deadline at 10ms: ${child.outcome}');
clock.elapse(const Duration(milliseconds: 10));
final reason = (child.outcome! as Cancelled).reason as TimeoutCancelReason;
print('deadline reason: ${reason.timeout.inMilliseconds}ms');
```

Точный вывод этих строк на исходнике:

```text
deadline at 10ms: Cancelled(timeout)
deadline reason: 10ms
```

На M1:

```text
deadline at 10ms: null
deadline reason: 20ms
```

**Предложение.** В тесте общего кода двигать время до границы срока и через
неё; проверить `TimeoutCancelReason.timeout == limit`. Полезно также сначала
выдержать незапущенный хэндл и проверить отсчёт от фактического старта. Ядро
отдельно проверяет длительность причины, но это не защищает аргумент, который
ему передаёт адаптер `solo`.

**Вердикт ревьюера:** Пробел сторожей подтверждён зелёным полным набором
мутанта и отдельным наблюдаемым изменением поведения; закрыть до мержа.

**Вердикт.** Принято: тест
`gets the deadline of its step as Cancelled(timeout)` двигает время на 9 мс,
где ребёнок ещё идёт, потом на 1 мс и сверяет `TimeoutCancelReason.timeout`
с 10 мс. M1 под ним красный. Отсчёт от фактического старта для `solo` отдельно
не проверяется: адаптер передаёт ядру только длительность, а срок незапущенного
ребёнка держит тест ядра.

#### 3. P2 — создание через законченный `SoloContext` не защищено тестами

**Место:** `packages/solo/test/child_factory_test.dart`, группа
`the rules of the job that made the child`, тест
`hold after its body has ended, and turn the child away`. Изменяемое место —
`_SoloContext.child` в `packages/solo/lib/src/job_context.dart:182`.

**Суть.** Тест создаёт ребёнка в ещё работающем теле, заканчивает создателя
и лишь затем запускает уже готового ребёнка. Он проверяет сохранение правил
у хэндла, но не вызов фабрики на сохранённом завершённом контексте. Такой вызов
прямо разрешён дизайном и общим договором `JobContext.child`.

**Механика.** В ядре подобный тест есть, однако `solo` переопределяет фабрику.
Проверка только базового метода не мешает адаптеру ввести новый отказ. Все
существующие вызовы `SoloContext.child` в этом наборе происходят до завершения
создателя.

**Доказательство.** Мутация M2 перед единственным вызовом `_solo.job`:

```diff
-      _solo.job<W, T>(
+      _job.isFinished
+          ? throw StateError('finished factory')
+          : _solo.job<W, T>(
```

Полный набор мутанта:

```text
00:15 +2131: All tests passed!
```

Ветка `finished` приложения A сохраняет контекст, прокачивает микрозадачи
до завершения создателя и только затем выполняет `saved.child(...)`. Исходник
печатает:

```text
finished: factory=created
finished: own run=StateError
finished: other run=Done(1)
finished rules: Done(Cancelled(rules: keepWhile))
```

Последняя строка — отдельный сценарий того же зонда: создатель завершён, его
`keepWhile` больше не выполняется, фабрика всё равно возвращает хэндл, а отказ
приходит при запуске другой задачей. На M2:

```text
finished: factory=Bad state: finished factory
finished rules: factory=Bad state: finished factory
```

**Предложение.** Добавить тест с сохранённым `SoloContext`: закончить
создателя, вызвать `child`, успешно запустить другим контекстом того же
контроллера; отдельным сценарием изменить состояние и получить отказ правил
создателя именно на запуске. Для переопределения `solo` закрепить также
создание в уборке и после принятой отмены: базовый тест их автоматически
не покрывает.

**Вердикт ревьюера:** Пробел сторожей подтверждён. Договор оставлен верным
в реализации, но его существенная граница не удерживается набором `solo`.

**Вердикт.** Принято вместе с Н1 Opus, тот же тест: M2 codex — то же, что MS11.

#### 4. P3 — `@useResult` базового класса можно потерять незаметно для сторожа аннотаций

**Место:** `packages/solo/test/child_factory_test.dart`,
`a child made and dropped is a warning, through either context`;
`packages/async_job/lib/src/job_context.dart`, `JobContextBase.child` (строки
548–557). Связанный принятый пункт — П9 ревью плана.

**Суть.** Сторож анализирует вызовы через `JobContext` и `SoloContext`.
`JobContextBase` — самостоятельная статическая поверхность; переопределение
не наследует аннотацию интерфейса. В реализации аннотация стоит правильно,
но её сохранение не проверяется.

**Доказательство.** M3 удаляет только `@useResult` непосредственно над
`JobContextBase.child`; аннотации интерфейсов остаются. Весь набор `solo`
прошёл: `00:13 +2131: All tests passed!`. Результаты полного ядра, включая
отказ теста переполнения стека в первом прогоне, приведены выше. Зонд
приложения B анализирует:

```dart
import 'package:async_job/engine.dart';
void dropped(JobContextBase ctx) {
  ctx.child<void>((ctx) async {});
}
```

Исходник:

```text
errors: []
warnings: [unused_result]
```

Мутант:

```text
errors: []
warnings: []
```

**Предложение.** Добавить вызов через `JobContextBase` в анализаторный сторож
ядра. Существующие две копии `compile_errors.dart` уже предоставляют нужный
`compileWarnings`; меняя помощник, сохранять их согласованность.

**Вердикт ревьюера:** Небольшой подтверждённый пробел проверки предупреждения;
текущая аннотация корректна, добавления нового API не требуется.

**Вердикт.** Принято вместе с Н2 Opus, тот же тест: вызов через наследника
`JobContextBase`, а не через сам класс, — так вызывает тело движка.

### Мутации

Каждая мутация сделана отдельно. Перед ней — `cp <файл> <файл>.orig`, после
неё, в `finally`, — `cp <файл>.orig <файл>` и удаление резервной копии. После
каждой выполнялся `git status --short`: изменений отслеживаемых файлов
не оставалось, присутствовали только временные материалы ревью в двух каталогах
`tool/`. Зонды не помещались в автоматически собираемые тестовые наборы.

| Мутация | Что изменено | Что её обнаружило |
| --- | --- | --- |
| M1 | `_SoloContext.child`: `timeout * 2` вместо исходного срока | Полный S зелёный, 2131 тест; отдельный зонд видит 20 мс вместо 10 мс. Находка 2. |
| M2 | `_SoloContext.child`: `StateError` при `_job.isFinished` | Полный S зелёный, 2131 тест; отдельный зонд не может создать ребёнка. Находка 3. |
| M3 | Удалён только `@useResult` у `JobContextBase.child` | Полный S зелёный, 2131 тест; анализаторный зонд теряет `unused_result`. Повтор полного A тоже зелёный, 1884 теста; первый прогон имел отказ теста стека, см. ПРОГОН. Находка 4. |
| M4 | Удалён `keepWhile: _job._keepWhile` | `child_factory_test.dart`: `the rules of the job that made the child hold after its body has ended, and turn the child away`; итог `+7 -1`. |
| M5 | `_SoloContext.child` не передаёт `timeout` | `child_shared_code_test.dart`: `gets the deadline of its step as Cancelled(timeout)` и `let out, it reaches ifCancelled of the parent`; итог `+4 -2`. |
| M6 | `JobContextBase.child` не передаёт `timeout` | `child_factory_test.dart`: оба теста `the timeout of a child`, проверка нуля/отрицательного срока и `inside uncancellable the parent is held and the deadline is not`; итог `+10 -4`. |
| M7 | `JobContextBase.createEachJob` снова вызывает `Job.deferred<void>` напрямую | `extending_test.dart`: `an engine that overrides child gives each its children too`; итог `+27 -1`. |
| M8 | Удалён `@useResult` только у `SoloContext.child` | `a child made and dropped is a warning, through either context`; итог `+0 -1`. |
| M9 | Удалён `@useResult` только у `JobContext.child` | Тот же тест предупреждений в S; итог `+0 -1`. |
| M10 | Удалены объявления `child` из `SoloContext` и `_SoloContext` | Все шесть тестов `child_shared_code_test.dart`; сборка файла прошла, отказ — во время выполнения; итог `+0 -6`. |

Для M10 первая ошибка содержит именно отказ контроллера, предусмотренный П11
ревью плана:

```text
Actual: Failed:<Failed(Invalid argument (job): was not created by this Solo (make it with job(...) of this controller or with ctx.child): "Job(step)")>
```

Зелёными полными наборами затронутого адаптера прошли M1 и M2. M3 пропустили
полный S и повтор полного A. Первый красный прогон A с M3 не был проверкой
аннотации и сохранён в разделе ПРОГОН. Для M4–M10 полные наборы повторно
не нужны: указанные существующие тесты уже обнаружили каждую мутацию.

### Сверка с дизайном, планом и документами

- Сигнатуры, тип результата, `key`, `describe`, отсутствие запуска и проверок
  в фабрике соответствуют дизайну. `SoloContext.child` возвращает задачу своего
  контроллера с `W` и `keepWhile` создателя. Фабрика не устанавливает родителя
  и не копирует отменяемость создателя.
- Принятые О1 и П4 исполнены: базовый метод возвращает `Job.deferred`,
  документы `extending.md` и `engine.md` объясняют необходимость
  переопределения для своих правил. `MyContext` честно оставлен с контекстом
  ядра у ребёнка; это проверяет новый тест в `extending_test.dart`.
- О2, К2, К3 исполнены в коде: создатель выбирает правила, запускающая задача
  становится родителем, незапущенный ребёнок не входит в ожидание и отмену
  создателя. Тесты проверяют наблюдателя фактического родителя, каскад отмены,
  отсутствие срока до старта, незавершённый `done` и завершение `close()` при
  оставшемся хэндле. Пробел позднего вызова фабрики `solo` указан отдельно
  в находке 3.
- О3, К1, П1–П3 и П6 исполнены: таблицы README и справочника, парсер
  `@useResult`, список пустых ячеек, текст отказа `_own` и его цитаты
  согласованы. Ошибка документа в находке 1 находится в другом перечне,
  в архитектурном инварианте.
- П5, П9 и П11 исполнены в реализации: помощники предупреждений добавлены в обе
  копии, `@useResult` стоит и на базовом классе, общий код отделён в свой
  тестовый файл. Копии помощника совпадают после первой строки. M10
  подтверждает отказ выполнения, а не только отказ компиляции.
- П8 исполнен: решения 112–115 присутствуют. П10 исполнен в принятом объёме:
  `ChildJob`, README, `streams.md`, карта модулей и срок шага обновлены.
  Оставленные примеры с `Job.deferred` сами по себе корректны.
- Нулевой и отрицательный срок проверяются в обоих пакетах, `ifCancelled`
  родителя, продолжение очереди, независимость от `cancellable: false`,
  `start`, `runAll` и пробуждаемая пауза покрыты. Старые тесты `each` проходят;
  M7 подтверждает новый путь базовой фабрики.
- Изменённые английские страницы и переводы передают один договор;
  `check_translations.py` также прошёл. В обоих CHANGELOG новый член помечен
  как ломающий; ядро называет конфликт подкласса и затенение расширения, `solo`
  сохраняет запись о `onError` и ведёт к списку ядра. Дополнительного
  пропущенного ломающего изменения в этом диффе не найдено.
- Четыре оверрайда направлены на соседние пакеты правильно. В разрешённых
  конфигурациях S и E `async_job` действительно указывает на дерево.
  Формулировки комментариев оверрайдов менее конкретны, чем буквальный текст
  плана про 0.5.0; функциональной ошибки в этом не найдено.

Прогоны подтверждают состояние проверенной копии; историческое выполнение
humanizer и всех проверок перед каждым старым коммитом этим ревью
не устанавливалось.

### Что остаётся до мержа и выпуска

До мержа: исправить противоречивый инвариант, добавить сторожа находок 2–3
(и небольшую проверку находки 4), разобрать оба заказанных ревью
в `2026-10-27-ctx-child-report.md` с вердиктами. Завершить шаг 6 плана:
Flutter-пакет и пример, стенды со сверкой трасс, `dart doc --dry-run`, сборка
сайта и её тест, архивный floor. Приведённые результаты ядра с переполнением
стека нужно учитывать при приёмке полного гейта; их причинную связь
с `ctx.child` отчёт не утверждает.

До выпуска 0.5.0: поднять версии и межпакетные ограничения, заменить
`Unreleased` выпускной записью и снять оверрайды на соответствующем этапе.
Сейчас `async_job` и `solo` имеют `version: 0.4.0`, зависимость `solo` ещё
`async_job: ^0.4.0`; `flutter_solo` держит `solo: ^0.4.0` и `scopo: ^0.19.0`.
Проверки с оверрайдами не доказывают разрешимость публикуемых ограничений.
После выпуска ядра нужны выпуск `solo`, выпуск scopo под новое ядро и затем
`flutter_solo` в порядке, установленном AGENTS.md. Публикация и межсессионные
сообщения в этом ревью не выполнялись.

## Проверки

До ревью работы, на `03db0b32`, весь гейт CI локально: оба пакета, пример
`solo`, `flutter_solo` с примером, `dart doc --dry-run` в трёх пакетах, стенды
`vs-bloc`, `accumulation` и `flutter_solo` со сверкой трасс, все проверки
документов, тесты скриптов и сборка сайта — зелёные, дерево не сдвинулось. Пол
3.27.0 в отдельной копии на коммите: пять наборов зелёные.

Мутации — в таблицах обоих ревью ниже: по одной, возврат копией. Выжили четыре
разных мутанта, все — дыры в тестах, а не в коде: MS10, MS11 (он же M2 codex)
и MC6 (он же M3 codex) у Opus и M1 у codex. После правок по ревью все красные,
каждый под своим новым тестом из вердиктов.

После правок по ревью — тот же гейт: `async_job` +1885, `solo` +2133, пример
`solo` +112, `flutter_solo` +249 и его пример +6, стенды и проверки документов
зелёные; дерево сдвинулось ровно на эти правки.

## До выпуска

Публикация — отдельной просьбой владельца. Что к ней готовить, кроме обычного
порядка выпуска: `solo` требует `async_job: ^0.4.0`, а `SoloContext.child`
собирается только на 0.5.0, поэтому при снятии оверрайдов ограничение
поднимается до `^0.5.0` — пока оверрайды живут, `floor` этого не видит.
