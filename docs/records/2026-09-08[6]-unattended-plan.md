> **Состояние на 2026-09-08:** третья редакция, написанная по второму
> кругу ревью `2026-09-08[8]-unattended-plan-review-2.md`: двенадцать
> находок, все приняты. Этот круг шёл **с исполнением** — оба ревьюера
> прошли план задачами, прогнали сьюты и проверили тесты нарочными
> подменами, — и подтвердил замысел и механику; правки точечные, кроме
> радиуса решения 2. Вторая редакция была написана по первому кругу
> (`2026-09-08[7]-unattended-plan-review.md`, девять находок): в ней
> переписаны механика zone-value и тесты. К исполнению не приступали.
> **Что это:** план работ по `ctx.unattended` — члену контекста, который
> отдаёт ядру работу, не дожидаемую телом, чтобы её провал доставался
> наблюдателю задачи, а не ронял процесс. Семь задач с TDD и коммитом на
> каждую.
> **Связанные записи:** `2026-09-08[8]-unattended-plan-review-2.md`
> (второй круг ревью, с исполнением, вердикт у каждой находки),
> `2026-09-08[7]-unattended-plan-review.md` (первый круг, вердикт у
> каждой находки),
> `2026-09-08[4]-detached-design.md` (спека, вторая
> редакция; план аргументирует от неё),
> `2026-09-08[5]-detached-design-review.md` (ревью первой редакции
> двумя ревьюерами, вердикт у каждой находки),
> `2026-09-08[2]-zone-design.md` и `2026-09-08[3]-zone-design-review.md`
> (первая попытка — форк зоны всего тела — и ревью, её отклонившее),
> `2026-09-07[5]-dispose-plan.md` (тот же формат).

# `ctx.unattended`: план работ

> **Для агентов:** выполнять задачу за задачей по
> `superpowers:subagent-driven-development` (рекомендуется) или
> `superpowers:executing-plans`. Шаги отмечены чекбоксами.

**Цель:** закрыть запись бэклога «Ловить ошибку брошенной футуры». Тело
получает способ сказать «эта работа моя, но я её не жду», и всё, что
такая работа уронит — сейчас или через минуту после конца задачи, —
приходит наблюдателю задачи, а не в корневую зону процесса.

**Архитектура:** член `JobContext.unattended` запускает действие в
`runZonedGuarded`, форкая зону от зоны вызова. Всё, что действие
запланировало, наследует форк, и любая необработанная ошибка оттуда идёт
в `notifyError` — наблюдателю, а без него в зону создания задачи. Тело
задачи не форкается вовсе: граница error-зоны двусторонняя, и тело,
бегущее внутри неё, виснет на любой чужой future (спека, «Почему не форк
тела»). Форк несёт два zone-value. Первое, под общим ключом, — зона
тела: из неё конструктор `JobBase` берёт адрес, куда отчитываться
задаче, рождённой в фоне. Второе — метка под ключом, которым служит сам
объект задачи: по ней `run` и `uncancellable` узнают, что их позвали из
фона **своей** задачи, и отказывают, а форки разных задач при этом не
перекрывают друг друга.
Поверх этого `solo` получает недостающий маршрут: бездомная ошибка,
которую не взял ни глобальный наблюдатель, ни переопределённый хук,
уходит в зону создания задачи.

**Стек:** Dart 3.13.0 (stable) локально, пол `^3.6.0`; `package:meta`,
тесты на `package:test` и `package:fake_async`; Flutter 3.47.0 для
`flutter_solo`.

**Спецификация:** `docs/records/2026-09-08[4]-detached-design.md`, вторая
редакция. План аргументирует от неё; исполнитель читает обе записи.
Ссылки вида «спека, раздел „Фильтр отмены“» — на неё.

**Наработки ревьюеров:** `.artifacts/2026-09-08-unattended/` — папка в
`.gitignore`, в коммиты не идёт. Там два отчёта (`review-mechanics.md`,
`review-design.md`), дифф рабочего прототипа (`proto-mechanics.diff`) и
девять стендов (`stands/s1_main.dart` .. `s9_cost.dart`) с измеренными
выходами. Кейсы тестов ниже взяты оттуда; если папки нет, всё
существенное пересказано в `2026-09-08[5]-detached-design-review.md`, и
план исполним без неё.

## Когда это делать

До публикации пакетов на pub.dev. Работа добавляет член в публичный
интерфейс `JobContext`, а добавить член в интерфейс после публикации —
ломающая правка для всех, кто его реализует. Сегодня реализация одна и
своя (`JobContextBase`), внешних `implements JobContext` в дереве нет —
проверено.

Публикация в план не входит: это отдельная связка по правилам
`AGENTS.md`, только по отдельному запросу владельца.

## Глобальные ограничения

- Пол SDK во всех пакетах — `environment: sdk: ^3.6.0`. Ничего из языка
  новее 3.6.
- Зависимости не выше пинов Flutter на полу SDK: рантайм `meta: ^1.15.0`;
  dev `fake_async: ^1.3.1`, `test: ^1.26.3`, `lints: ^5.1.1`.
- Ядро без Flutter и без зависимостей, кроме `meta`.
- `dart analyze` без предупреждений и info; `dart test` зелёный в
  `packages/jobs` и `packages/solo`, `flutter test` — в
  `packages/flutter_solo`, `dart test` из `packages/solo/example/`.
- Публичные документы по-английски, записи и общение — по-русски.
  `README.ru.md` правится тем же коммитом, что оригинал; сверка —
  `python3 tool/check_translations.py` из корня.
- Строки кода до 80 колонок, одинарные кавычки, завершающие запятые,
  поля выше конструктора.
- Асинхронность в тестах — только `FakeAsync`, время сдвигается явно.
- Один коммит — одна задача, вместе с её тестами и документами.

## Решения, принятые в плане сверх спеки

Спека оставила плану шесть вопросов (раздел «Что решить в плане»). Ответы
здесь, по её нумерации.

1. **Форма защищённого члена для зоны создания —
   `reportToZone(error, stackTrace)`, не `Zone get zone`.** Механизму
   нужно одно: отдать бездомную ошибку туда, куда ядро отдаёт
   ненаблюдённый провал. Глагол называет ровно это, оставляет `Zone` вне
   защищённой поверхности и встаёт в один ряд с соседями —
   `notifyObserver`, `notifyError`. Геттер отдал бы наружу объект зоны, с
   которым можно делать что угодно, и первым же делом — `run` чужого кода
   в зоне создания; правило проекта «поверхность не расширяют, пока не
   покажет, что нужна» (решение владельца 2026-09-07) велит взять
   меньшее. Обратный ход дешёвый: добавить геттер позже — правка не
   ломающая.
2. **Отмену ребёнка, пришедшую от каскада этой же задачи, фильтруем —
   точной проверкой, а не эвристикой.** Ревьюер предложил отличать по
   `reason == CancelReason.parent` при `isCancelled` этой задачи; это
   heuristic: «какой-то родитель», не обязательно наш, а в `solo` при
   `close()` отменяется всё сразу, и чужой ребёнок под своим родителем
   попадёт под ту же примету. Точная проверка в ядре уже есть:
   `_outcomeChild` — `Expando` на родителе, ключ — сам объект исхода,
   значение — ребёнок, который его принёс; ядро пользуется ею в
   `_handlerCancel` ровно для случая «отмена ребёнка через
   `child.value`». Условие фильтра:
   `error is Cancelled && error.reason == CancelReason.parent &&
   _owner._outcomeChild[error] != null` — «это исход **нашего** ребёнка,
   и свалил его каскад». `Job.value` бросает сам объект исхода, так что
   ключ сходится. Всё остальное проходит: своя отмена ребёнка
   (`handler`), отмена по правилам `solo`, отмена чужой задачи.
3. **`vs-bloc.md` §4 — второй вариант добавляем,** одной фразой к
   существующей. Раздел про то, что после отмены обработчик у bloc
   продолжает работать, и фраза «work that would otherwise be
   fire-and-forget goes through `ctx.run(child)`» после этой работы стала
   бы неполной: у `ctx.run` есть исход и его ждут, у `ctx.unattended` нет
   и не ждут, и выбор между ними — как раз ответ на «а что с работой,
   которую никто не ждёт».
4. **Стенд без глобального наблюдателя — новый файл
   `packages/solo/test/zone_test.dart`.** `test/support/run_solo.dart`
   ставит `SoloBase.observer` всем тестам, и трогать его нельзя: на нём
   стоит вся сьюта. Новый файл не зовёт `runSolo` вовсе — он строит
   `TestSolo` руками внутри `fakeAsync` и ловит зону хелпером `_inZone`,
   уже написанным в `packages/solo/test/unobserved_failure_test.dart`
   (скопировать в новый файл: хелпер приватный, на восемь строк, и
   вытаскивать его в `support/` ради второго пользователя не за чем).
   Имя `zone_test.dart` — по образцу `packages/jobs/test/zone_test.dart`,
   который делает то же для ядра.
5. **Точка удара по сьюте.** Ожидание — ноль сломанных тестов, и вот
   почему: маршрут решения 2 включается только при
   `SoloBase.observer == null`, а `runSolo` ставит наблюдателя всегда.
   Именно поэтому стенд из пункта 4 обязателен: без него правильный и
   неправильный механизмы проходят сьюту одинаково. Ожидание проверяется
   прогоном, а не считается доказанным: шаг «прогнать всю сьюту `solo`»
   стоит в задаче 4 отдельно. Если что-то всё же покраснеет, разбирать
   поштучно — красный тест здесь означает либо переопределённый `onError`
   в самом тесте, либо ошибку в реализации флага.
6. **Порядок закрепляется тестами, а не подразумевается:** провал после
   `onFinish` — в задаче 1 (ядро), провал после `onClose` — в задаче 5
   (`solo`).

Сверх этих шести план принимает ещё четыре решения.

7. **Отказ после конца — своей проверкой, не `throwIfFinished`.** Спека в
   скобках называет `throwIfFinished('unattended')`, но тут же требует,
   чтобы член работал в окне уборки, а `throwIfFinished` в этом окне
   бросает: он зовёт `throwIfDisposing`. Берём форму, уже принятую в ядре
   для членов, которые в уборке живут, — `addCleanup` и `disown` пишут
   проверку `_owner.isFinished` прямо в теле. Требование спеки к тексту
   выполняется буквально: проверка стоит первым оператором, и сообщение
   называет член — `'$_owner has already finished, cannot start
   unattended work'`.
8. **Имена внутренних сущностей.** `_unattendedKey` — ключ первого
   zone-value, свежий `Object()`, так что назвать его снаружи библиотеки
   нечем; `throwIfUnattended(String action)` — защищённая проверка «меня
   позвали из фона этой же задачи»; `_homeless` — поле `SoloBase` с
   задачей, чья бездомная ошибка сейчас идёт через хуки. Спека называет
   только публичные имена, эти выбраны здесь.
9. **Два zone-value, и ключ второго — сам объект задачи.** Ревью первой
   редакции (`2026-09-08[7]-unattended-plan-review.md`, находки 1 и 2)
   снесло обе половины прежнего решения; вот что вместо них.

   **Метка запрета — под ключом-задачей.** Одна пара ключ-значение на
   все форки означает, что внутренний перекрывает внешний, и
   `a.unattended(() => b.unattended(() => a.run(child)))` проходит
   запрет: последний маркер принадлежит `b`. Ребёнок стартует в форке и
   вешает родителя насмерть — тот же `STUCK after 200ms`, что ревьюер
   спеки замерил для прямого случая. Ключом второго zone-value берётся
   **сам объект задачи** (`{_owner: true}`), и проверка — это
   `Zone.current[_owner] != null`. Форки разных задач тогда не
   перекрываются вовсе: каждая видит свой маркер под своим ключом.
   Цепочка владельцев решала бы то же самое обходом списка на каждом
   `run`; здесь обход не нужен, потому что перекрывать нечего.

   **Зона тела — транзитивно.** Прежнее решение клало в форк
   `Zone.current` как есть и называло верным адресом то, что задача,
   рождённая во внутреннем форке, отчитается наблюдателю хозяина. Это
   прямо против спеки, раздел «Задача, созданная внутри `action`»: у
   самостоятельной задачи свой исход и свой наблюдатель, а в `solo`
   вдобавок выходит второй отчёт под чужим именем. Форк кладёт
   `from = (Zone.current[_unattendedKey] as Zone?) ?? Zone.current` — то
   есть всегда зону тела, сколько бы форков ни было вложено. Лишняя
   строка, а не цепочка.
10. **Маршрут решения 2 фильтрует `Cancelled`, а всё прочее пускает.**
    Второй круг ревью (`2026-09-08[8]-unattended-plan-review-2.md`,
    находка 1) замерил, что радиус решения 2 много шире, чем говорила
    вторая редакция: в зону идёт **всё**, что дошло до `notifyError`, —
    уборщик, колбэк `onCancel`, поздний провал брошенного `wait`,
    `Cancelled` любого происхождения, — и это отменяет четыре письменных
    обещания сразу.

    Довод за выбранную ширину — в самом ядре.
    `packages/jobs/test/zone_test.dart:66` закрепляет, что бросивший
    `onCancel` и поздний провал брошенного действия **уже сегодня**
    уходят в зону, когда наблюдателя нет. Значит решение 2 не вводит
    нового поведения, а перестаёт делать `solo` глуше ядра, на котором он
    стоит: надстройка молчит там же, где молчит ядро.

    `Cancelled` — исключение, и единственное: у отмены есть хозяин, она
    не провал, а во Флаттере ушла бы в `PlatformDispatcher.onError` без
    всякой пользы. Первая половина инварианта 4 («`Cancelled` в зону не
    уходит никогда») этим сохраняется; правится вторая, про ошибку через
    `onError`.

    Узкий вариант — пускать только провал фоновой работы — отклонён: он
    оставил бы бросившего уборщика немым, а провал фона слышным, тогда
    как для пользователя это одно и то же «ошибке некуда идти».

    Асимметрия, которую эта правка оставляет: ядро `Cancelled` в
    `notifyError` не фильтрует, а `solo` будет. Выравнивание ядра — не
    эта работа.
11. **`notifyError` не переписываем на `reportToZone`.** Он уже пишет
    свою строку `_debug` перед развилкой, а `reportToZone` пишет свою;
    сведя одно к другому, получим две строки на одну ошибку. Общего кода
    там одна строка, и дублирование дешевле путаницы в трассировке.

## Карта файлов

**Ядро, `packages/jobs`:**

- `lib/src/job_context.dart` — `unattended` в интерфейсе `JobContext` и в
  `JobContextBase`; фильтр отмены; `_unattendedKey` и метка под
  ключом-задачей;
  `throwIfUnattended` и её вызовы в `run` и `uncancellable`; правки
  дартдока шапки класса (обе группы членов).
- `lib/src/job_base.dart` — `_zone` берёт зону из zone-value;
  защищённый `reportToZone`; дартдоки `Job.ignore`, `notifyError`.
- `lib/src/job_stream.dart` — абзац `each` про брошенный вызов.
- `lib/src/outcome.dart` — перечень маршрутов у `Failed`.
- `lib/src/observer.dart` — перечень у `JobObserver.onError`.
- `test/unattended_test.dart` (создать) — член целиком: маршрут провала,
  фильтр, отказы, порядок, композиция с `each`.
- `test/unattended_boundary_test.dart` (создать) — запреты `run` и
  `uncancellable` внутри работы и задача, созданная в работе.
- `README.md`, `README.ru.md`, `CHANGELOG.md`.

**Надстройка, `packages/solo`:**

- `lib/src/solo_base.dart` — поле `_homeless`, тело `onError` по
  умолчанию (с фильтром `Cancelled`) и его дартдок; дартдок
  `SoloObserver.onError` в `lib/src/observer.dart`. Оба дартдока, абзац
  «Errors of a disposer» в README и инвариант 4 правятся в задаче 4,
  вместе с поведением.
- `lib/src/job.dart` — `_SoloJob.notifyError` ставит и снимает флаг;
  обёртка `_reportToZone`.
- `test/zone_test.dart` (создать) — стенд без глобального наблюдателя.
- `test/unattended_test.dart` (создать) — порядок после `onClose` и
  остановка фоновой работы.
- `README.md`, `README.ru.md`, `CHANGELOG.md`, `doc/vs-bloc.md`.

**Flutter, `packages/flutter_solo`:** `README.md`, `README.ru.md`.

**Репозиторий:** `docs/ru/solo/vs-bloc.md`, `docs/architecture.md`
(«Понятия», инварианты 2, 4, 8, 10), `docs/handoff.md`.

---

## Фаза A. Ядро

### Задача 1. `unattended`: член, форк, фильтр, отказ

Спека, разделы «Что делаем», «Группа членов», «Фильтр отмены»,
«Решения владельца, которые остаются в силе» (пункт 1).

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_context.dart`
- Создать: `packages/jobs/test/unattended_test.dart`

**Интерфейсы:**
- Даёт дальше: `void unattended(FutureOr<void> Function() action)` в
  `JobContext` и `JobContextBase`; приватный `_unattendedKey`
  (`final Object` на верхнем уровне `job_context.dart`) — под ним форк
  несёт зону тела, её читает задача 3. Второй zone-value кладётся под
  ключом-задачей и читается задачей 2; своего имени у него нет.

- [ ] **Шаг 1.** Написать падающий тест — тот самый случай из бэклога.

```dart
@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

void main() {
  test('a failure of unattended work reaches the observer', () {
    final journal = JobJournal();
    fakeAsync((async) {
      Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() async {
          await delay(10);
          throw StateError('abandoned boom');
        });
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      '[j] finished Done(null)',
      '[j] error Bad state: abandoned boom',
    ]);
  });
}
```

- [ ] **Шаг 2.** Прогнать: тест не компилируется — `unattended` нет.

Команда: `cd packages/jobs && dart test test/unattended_test.dart`
Ожидание: FAIL, `The method 'unattended' isn't defined`.

- [ ] **Шаг 3.** Объявить член в интерфейсе `JobContext`, между `log` и
      геттером `job`.

```dart
  /// Runs [action] as work the job does not wait for.
  void unattended(FutureOr<void> Function() action);
```

Дартдок целиком пишется в задаче 6; здесь одна строка, чтобы
`dart analyze` не ругался на публичный член без документации.

- [ ] **Шаг 4.** Реализовать в `JobContextBase`, сразу за `log`, и
      добавить приватные объявления в конец файла, перед `_CoreContext`.

```dart
  @override
  void unattended(FutureOr<void> Function() action) {
    // First, and by name: a context outliving its job is the mistake this
    // member is likeliest to be caught in, and the message has to say
    // which call threw. The cleanup window stays open on purpose — a
    // disposer starting work nobody waits for is what this is for.
    if (_owner.isFinished) {
      throw StateError(
        '$_owner has already finished, cannot start unattended work',
      );
    }
    // The zone a job born in this work reports to. Taken from the fork
    // around us when there is one, so nesting does not walk the address
    // one fork outwards on every level: the answer is the zone the body
    // itself runs in, however deep the call is.
    final from = (Zone.current[_unattendedKey] as Zone?) ?? Zone.current;
    runZonedGuarded<void>(
      () {
        action();
      },
      _unattendedError,
      // Two values, and the key of the second is the job itself: forks of
      // different jobs nest, and one shared key would let the inner one
      // hide the outer. Under a key of its own each job sees its own work
      // and nobody else's.
      zoneValues: {_unattendedKey: from, _owner: true},
    );
  }

  /// The fork's handler: everything the work leaves uncaught, less this
  /// job's own giving up.
  void _unattendedError(Object error, StackTrace stackTrace) {
    if (_isOwnCancellation(error)) {
      return;
    }
    notifyError(error, stackTrace);
  }

  /// Whether [error] is this job giving up rather than something failing.
  ///
  /// The job's own cancellation is not news: whoever listens has heard it
  /// on the outcome already. A `Cancelled` built inside the work is not
  /// this — there is nobody to cancel there, and the observer gets it.
  bool _isOwnCancellation(Object error) {
    if (identical(error, _owner._pendingCancel) ||
        identical(error, _owner._outcome)) {
      return true;
    }
    // A child this job's own cascade took down, reaching the work through
    // `child.value`. The lookup is exact — the key is the outcome object
    // itself — so anyone else's child still comes through.
    return error is Cancelled &&
        error.reason == CancelReason.parent &&
        _owner._outcomeChild[error] != null;
  }
```

```dart
/// The zone-value key under which a fork of [JobContext.unattended]
/// carries the zone of the body. A fresh object, so nothing outside this
/// library can name it. The fork's other value is the mark of the job
/// that made it, and its key is that job.
final _unattendedKey = Object();
```

- [ ] **Шаг 5.** Прогнать тест шага 1.

Команда: `cd packages/jobs && dart test test/unattended_test.dart`
Ожидание: PASS.

- [ ] **Шаг 6.** Дописать остальные тесты файла. Тринадцать штук,
      кейсы — со стендов ревьюеров (`s1_main.dart`, `s3_filter.dart`,
      `s5_order.dart`, `s7_refusal.dart`).

  1. `a failure of unattended work reaches the observer` — шаг 1.
  2. `without an observer the failure goes to the zone that created the
     job` — тот же случай без `observer:`, обёрнутый в `runZonedGuarded`
     вокруг `fakeAsync`, как в `test/zone_test.dart`; в зоне ровно одна
     строка.
  3. `the failure arrives after the job has finished` — журнал шага 1
     уже это утверждает порядком строк; отдельным тестом закрепить, что
     между `finished` и `error` прошло время: `async.elapse` по 5 мс,
     `journal.take()` после первого шага пуст.
  4. `a synchronous throw of the action goes to the observer, not to the
     body` — `ctx.unattended(() => throw StateError('sync boom'))`; исход
     задачи `Done`, у наблюдателя строка `error`. Спека, «Группа членов»,
     последний пункт.
  5. `the job's own cancellation seen inside the work is not an error` —
     работа делает `await ctx.wait(() => delay(50))`, задачу отменяют
     снаружи через `job.cancel()`; у наблюдателя ни одной строки `error`.
  6. `a body cancelling itself leaves nothing at the observer` — тело
     бросает `throw const Cancelled('enough')`, работа стоит в
     `await ctx.wait(() => delay(50))` и **после ожидания зовёт
     `ctx.check()`**. Контрольная точка обязательна, и без неё тест
     пустой: при самоотмене `_execute` заполняет `_pendingCancel` голым
     присваиванием уже после детей и `_markCancelled` не зовёт намеренно
     (`job_base.dart:708-716`), так что брошенное `wait` тихо получает
     своё значение и без фильтра. Именно с `check` стоит эта проверка в
     стенде `s3_filter.dart`, функция `self`; первая редакция плана его
     потеряла, ревью нашло (находка 4).
  7. `a Cancelled built inside the work is an error like any other` —
     `ctx.unattended(() => throw Cancelled('mine'))`; исход задачи
     `Done`, у наблюдателя строка `error Cancelled(handler: mine)` —
     безымянный конструктор ставит `reason = CancelReason.handler`, и
     `toString` печатает причину (`outcome.dart:145-152`). Спека, «Фильтр
     отмены», перечень пропускаемого.
  8. `a child cancelled by this job's cascade is not an error, a child
     cancelling itself is` — два прогона одного стенда
     (`s3_filter.dart`, кейсы `child` и `child-own`): работа ждёт
     `child.value`, в первом ребёнка валит каскад отмены родителя — строк
     `error` нет, во втором ребёнок бросает `Cancelled` сам — строка
     есть.
  9. `a child of another job cancelled by its own parent is an error` —
     тот случай, ради которого решение 2 взяло точную проверку вместо
     эвристики, и без него оно не закреплено ничем. Две задачи: `a` с
     фоном, `b` с ребёнком `c`; фон задачи `a` ждёт `c.value`; отменяют
     **обе** задачи разом, так что `a` в момент провала помечена, а `c`
     несёт `reason == CancelReason.parent`. Эвристика «`parent` при
     `isCancelled` хозяина» тут погасила бы чужой сигнал; точная
     проверка через `_outcomeChild` его пропускает — у наблюдателя `a`
     есть строка `error`.
  10. `unattended after the job has finished throws and names itself` —
      контекст, утёкший в замыкание; `expect(() => ctx.unattended(() {}),
      throwsA(isA<StateError>().having((e) => '$e', 'message',
      contains('unattended'))))`.
  11. `a disposer may start unattended work` — `ctx.onDispose(() =>
      ctx.unattended(() async { await delay(10); throw
      StateError('late'); }))`; задача завершается, строка `error`
      приходит после `finished`. Спека, «Группа членов», «В уборке
      работает».
  12. `unattended on a cancelled but still running job does not throw` —
      задача помечена отменой, тело в `finally` зовёт член; исключения
      нет.
  13. `onCancel may hand an asynchronous stop to unattended work` —
      решающий довод спеки за то, что член не бросает `Cancelled`:
      `ctx.onCancel(() => ctx.unattended(device.stop))`. Задачу
      отменяют, остановка запускается, её провал приходит наблюдателю.
      Без этого теста первая же правка группы членов молча отменит
      довод (находка 8 второго круга ревью).
  14. `an abandoned each wrapped in unattended hands a late handler error
      to the observer` — `ctx.unattended(() => ctx.each(stream,
      onData))`, где `onData` падает уже после конца задачи; строка
      `error` у наблюдателя. Спека, «Что меняется в публичном контракте»,
      пункт про `each`.

- [ ] **Шаг 7.** Прогнать весь пакет.

Команда: `cd packages/jobs && dart analyze && dart test`
Ожидание: анализ чист, все тесты зелёные.

- [ ] **Шаг 8.** Коммит.

```bash
git add packages/jobs
git commit -m "feat(jobs): ctx.unattended, work the job does not wait for"
```

### Задача 2. Запреты внутри работы: `run` и `uncancellable`

Спека, раздел «Что запрещено внутри `action`».

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_context.dart`
- Создать: `packages/jobs/test/unattended_boundary_test.dart`

**Интерфейсы:**
- Берёт из задачи 1: метку форка под ключом-задачей.
- Даёт дальше: `@protected void throwIfUnattended(String action)` в
  `JobContextBase`.

- [ ] **Шаг 1.** Написать падающие тесты.

Импорта `dart:async` в файле пока нет: ни одному тесту задачи 2 он не
нужен, а лишний импорт — `warning` анализатора ровно в той точке, где
план обещает чистый анализ (находка 2 второго круга ревью). Он появится в
задаче 3 вместе с `runZonedGuarded`.

```dart
@Timeout(Duration(seconds: 5))
library;

import 'package:fake_async/fake_async.dart';
import 'package:jobs/jobs.dart';
import 'package:test/test.dart';

import 'support/delay.dart';
import 'support/journal.dart';

// Вынесены в константы, а не написаны соседними литералами внутри
// списка: `no_adjacent_strings_in_list` включён в
// `packages/jobs/analysis_options.yaml`.
const _noChild =
    '[j] error Bad state: Job(j) cannot run a child inside unattended work';
const _noSection = '[j] error Bad state: Job(j) cannot run an uncancellable '
    'action inside unattended work';

void main() {
  test('run inside unattended work throws and starts no child', () {
    final journal = JobJournal();
    var childRan = false;
    fakeAsync((async) {
      final job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(() {
          ctx.run(
            Job.deferred<void>(key: 'child', (c) async => childRan = true),
          );
        });
        await ctx.wait(() => delay(1));
      });
      async.flushTimers();
      expect(job.outcome, isA<Done<void>>());
    });
    // The whole journal, not the error lines alone: a check moved below
    // `child.start()` would still leave one error and a `Done` parent,
    // and filtering by the word `error` would throw away the very lines
    // that say the child ran.
    expect(journal.take(), [
      '[j] started',
      _noChild,
      '[j] finished Done(null)',
    ]);
    expect(childRan, isFalse);
  });

  test('uncancellable inside unattended work throws and holds nothing', () {
    final journal = JobJournal();
    var actionRan = false;
    late final Job<void> job;
    fakeAsync((async) {
      job = Job<void>(key: 'j', observer: journal, (ctx) async {
        ctx.unattended(
          () => ctx.uncancellable(() async {
            actionRan = true;
            await delay(50);
          }),
        );
        await ctx.wait(() => delay(100));
      });
      async.elapse(const Duration(milliseconds: 5));
      job.cancel();
      async.flushTimers();
    });
    expect(journal.take(), [
      '[j] started',
      _noSection,
      '[j] finished Cancelled(manual)',
    ]);
    // The refused section neither ran its action nor held the body's
    // cancellation: the job is cancelled at once, not 50 ms later.
    expect(actionRan, isFalse);
  });
}
```

Обе ошибки приходят наблюдателю, а не в тело: бросок из `action` — это
бросок внутри форка, и обработчик форка отдаёт его в `notifyError`. Это
то же правило, что у синхронного броска в задаче 1, тест 4. Порядок строк
в журнале — оттуда же: ошибка приходит из форка, пока тело ещё стоит в
`ctx.wait`, то есть до `finished`.

- [ ] **Шаг 2.** Прогнать.

Команда:
`cd packages/jobs && dart test test/unattended_boundary_test.dart`
Ожидание: FAIL, и вот с каким выходом — замерено:

```text
Expected: ['[j] started', '[j] error Bad state: Job(j) cannot run a child inside unattended work', '[j] finished Done(null)']
  Actual: ['[j] started', '> [child] started', '> [child] finished Done(true)', '[j] finished Done(null)']
```

Ничего при этом не виснет, и искать зависание не надо: под `fakeAsync`
тело ребёнка не ждёт чужой future и границы форка не касается.
Зависание, которым обоснован запрет (`job.done: STUCK after 200ms` у
ревьюера спеки), требует чужой future внутри ребёнка; эти тесты держат
более слабое и достаточное — «ребёнок стартовал там, где его никто не
ждёт». `uncancellable` сегодня проходит молча.

- [ ] **Шаг 3.** Добавить проверку в `JobContextBase`, рядом с
      `throwIfDisposing`.

```dart
  /// Throws [StateError] when called from inside this job's own
  /// [JobContext.unattended] work.
  ///
  /// Two members act on the whole job, and unattended work is not the
  /// job: a child started there would hang on the fork's boundary with
  /// the parent waiting for it forever, and a section opened there would
  /// hold a cancellation of a body that stands in no section at all.
  /// Another job's fork is not this job's business, and the key is the
  /// job itself: forks nest, and a shared key would let the inner one
  /// answer for the outer.
  @protected
  void throwIfUnattended(String action) {
    if (Zone.current[_owner] != null) {
      throw StateError('$_owner cannot $action inside unattended work');
    }
  }
```

- [ ] **Шаг 4.** Позвать её первым оператором в `run` и в
      `uncancellable`, до `throwIfFinished`.

```dart
  Future<T> uncancellable<T>(FutureOr<T> Function() action) async {
    throwIfUnattended('run an uncancellable action');
    throwIfFinished('run an uncancellable action');
    // ...
```

```dart
  Job<T> run<T>(Job<T> child) {
    throwIfUnattended('run a child');
    throwIfFinished('run a child');
    // ...
```

Порядок неслучаен: у работы, пережившей задачу, верны обе жалобы, но
чинить надо вызов из фона, и о нём сообщение говорит прямо.

- [ ] **Шаг 5.** Прогнать тесты шага 1.

Команда:
`cd packages/jobs && dart test test/unattended_boundary_test.dart`
Ожидание: PASS.

- [ ] **Шаг 6.** Дописать в файл пять тестов на границы проверки.

  1. `wait inside unattended work is allowed` — работа делает
     `await ctx.wait(() => delay(5))`, **доходит до строки после
     ожидания** и ставит флаг; у наблюдателя тихо. Спека, конец раздела
     «Что запрещено».
  1a. `join inside unattended work is allowed` — то же для `join`,
     отдельным тестом. Оба члена в одном тесте — пустая проверка:
     замерено, что запрет `throwIfUnattended('join')` оставляет всю
     сьюту зелёной, если `join` в тесте не позван (находка 5 второго
     круга ревью). Проверять надо не только отсутствие ошибки, но и то,
     что продолжение после ожидания выполнилось: запрет бросает **в**
     работу, и без флага после `await` тест не отличит запрет от
     разрешения.
  2. `a job of its own may run a child from inside another job's fork` —
     тело задачи `a` создаёт в своей работе задачу `b` (обычным
     `Job(...)`, не `ctx.run`), тело `b` зовёт `ctx.run` своего ребёнка;
     запрета нет, ребёнок отработал. Это и есть причина, по которой
     метка лежит под ключом-задачей, а не под общим.
  3. `a nested fork of another job does not lift the ban on run` —
     находка 1 ревью, дословно:
     `a.unattended(() => b.unattended(() => a.run(child)))` при двух
     живых контекстах. Запрет держится, ребёнок не стартовал, родитель
     `a` не завис. С общим ключом этот тест краснеет: внутренняя метка
     принадлежала бы `b`.
  4. `a nested fork of another job does not lift the ban on
     uncancellable` — то же для второго члена, той же формой.

- [ ] **Шаг 7.** Прогнать весь пакет.

Команда: `cd packages/jobs && dart analyze && dart test`
Ожидание: анализ чист, все тесты зелёные.

- [ ] **Шаг 8.** Коммит.

```bash
git add packages/jobs
git commit -m "feat(jobs): refuse run and uncancellable inside unattended work"
```

### Задача 3. Задача, созданная в работе, отчитывается своей зоне

Спека, раздел «Задача, созданная внутри `action`».

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart`
- Изменить: `packages/jobs/test/unattended_boundary_test.dart`
- Изменить: `packages/solo/test/unattended_test.dart` (создаётся в задаче
  5 — если задача 3 идёт раньше, файл создаётся здесь, а задача 5
  дописывает в него)

**Интерфейсы:**
- Берёт из задачи 1: зону тела под ключом `_unattendedKey`.
- Меняет: инициализацию поля `JobBase._zone`; наружу ничего нового.

- [ ] **Шаг 1.** Дописать падающий тест в
      `test/unattended_boundary_test.dart`, добавив в файл
      `import 'dart:async';` — здесь он впервые нужен, ради
      `runZonedGuarded`.

```dart
  test('a job created inside unattended work reports to the body zone', () {
    final journal = JobJournal();
    final caught = <String>[];
    runZonedGuarded(
      () {
        fakeAsync((async) {
          Job<void>(key: 'j', observer: journal, (ctx) async {
            ctx.unattended(() {
              Job<void>(key: 'stray', (c) async => throw StateError('stray'));
            });
            await ctx.wait(() => delay(1));
          });
          async.flushTimers();
        });
      },
      (error, stackTrace) => caught.add('$error'),
    );
    expect(caught, ['Bad state: stray']);
    expect(journal.take().where((line) => line.contains('error')), isEmpty);
  });
```

- [ ] **Шаг 2.** Прогнать.

Команда:
`cd packages/jobs && dart test test/unattended_boundary_test.dart`
Ожидание: FAIL — сегодня `caught` пуст, а провал `stray` приходит
наблюдателю задачи `j` под её именем: `_zone` задачи `stray` — форк, и
его обработчик ведёт в `notifyError` хозяина.

- [ ] **Шаг 3.** Починить инициализацию `_zone` в `JobBase`.

```dart
  /// The zone the job was created in; an unobserved [Failed] goes here.
  ///
  /// A job built inside [JobContext.unattended] takes the zone that work
  /// was started from, not the fork: the failure is the new job's own,
  /// and it must not arrive at the observer of the job that started the
  /// work. A job is not unattended work — it has an outcome and an
  /// observer of its own, and `ignore()` is how it is quenched.
  final Zone _zone = _creationZone();

  static Zone _creationZone() =>
      (Zone.current[_unattendedKey] as Zone?) ?? Zone.current;
```

Форк уже положил под этот ключ зону тела, а не себя, и положил её
транзитивно (задача 1): сколько бы форков ни было вложено, ответ один и
тот же — зона, в которой бежит тело.

- [ ] **Шаг 4.** Прогнать тест шага 1.

Команда:
`cd packages/jobs && dart test test/unattended_boundary_test.dart`
Ожидание: PASS.

- [ ] **Шаг 5.** Дописать второй тест ядра — **два уровня вложенности**,
      находка 2 ревью: `a job created inside nested unattended work still
      reports to the body zone`. Форма та же, что в шаге 1, но
      `ctx.unattended(() => ctx.unattended(() { Job(...); }))`. С прежним
      решением (форк кладёт `Zone.current` как есть) тест краснеет:
      задача снимает зону внешнего форка и отчитывается наблюдателю
      хозяина. Одного уровня для этого мало — на нём оба варианта дают
      один и тот же ответ.

- [ ] **Шаг 6.** Дописать третий тест — в `packages/solo`, потому что
      дубль виден только там, где наблюдатель есть у каждой задачи:
      `a job created inside unattended work is reported once, by itself`.
      **Два контроллера, объявленные в самом файле от `Solo<TestState>`**
      — `TestSolo` из `support/` не годится, он `final class` и
      переопределить `onError` у наследника нельзя (та же находка 3
      первого круга ревью, исправленная в задаче 4 и пропущенная здесь).
      Задача первого контроллера с фоном, а в фоне — задача **другого**
      контроллера, падающая и никем не наблюдаемая. Проверяется двоякое:
      её провал пришёл её собственному наблюдателю, и у наблюдателя
      хозяина строки об этой ошибке нет. Файл — `test/unattended_test.dart`
      пакета `solo`. Стенд — `s8_children.dart`; в нём случай `nested`
      проверяет обычный бросок, а не создание самостоятельной задачи, так
      что этот тест новый.

- [ ] **Шаг 7.** Прогнать оба пакета.

Команда: `cd packages/jobs && dart analyze && dart test`,
затем `cd packages/solo && dart analyze && dart test`
Ожидание: анализ чист, все тесты зелёные.

- [ ] **Шаг 8.** Коммит.

```bash
git add packages/jobs packages/solo
git commit -m "fix(jobs): a job born in unattended work reports to its own zone"
```

## Фаза B. `solo`

### Задача 4. Решение 2: бездомная ошибка доходит до зоны

Спека, разделы «Решения владельца, которые остаются в силе» (пункт 2) и
«Механизм решения 2». Наивное чтение ломает двадцать восемь тестов в
двенадцати файлах — прототип ревьюера это замерил; механизм ниже проверен
тем же прототипом на зелёной сьюте.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_base.dart` (`reportToZone`)
- Изменить: `packages/solo/lib/src/solo_base.dart`,
  `packages/solo/lib/src/job.dart`, `packages/solo/lib/src/observer.dart`
- Изменить: `packages/solo/README.md`, `README.ru.md`,
  `docs/architecture.md` — документы, описывающие **этот** хук, правятся
  здесь, а не в фазе C (находка 7 второго круга ревью)
- Создать: `packages/solo/test/zone_test.dart`

**Интерфейсы:**
- Даёт дальше: `@protected void reportToZone(Object error, StackTrace
  stackTrace)` в `JobBase`; приватные `SoloBase._homeless` и
  `_SoloJob._reportToZone`.

- [ ] **Шаг 1.** Написать падающий стенд — новый файл без глобального
      наблюдателя.

```dart
@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:solo/solo.dart';
import 'package:test/test.dart';

import 'support/test_solo.dart';
import 'support/test_state.dart';

void main() {
  test('a homeless error with no observer reaches the zone', () {
    final caught = <String>[];
    fakeAsync((async) {
      final solo = TestSolo();
      _inZone(caught, () {
        solo.run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('abandoned boom');
          });
        });
      });
      async.flushTimers();
      solo.close();
      async.flushTimers();
    });
    expect(caught, ['Bad state: abandoned boom']);
  });
}

void _inZone(List<String> errors, void Function() body) {
  Zone.current
      .fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) =>
              errors.add('$error'),
        ),
      )
      .run<void>(body);
}
```

- [ ] **Шаг 2.** Прогнать.

Команда: `cd packages/solo && dart test test/zone_test.dart`
Ожидание: FAIL, `caught` пуст. У каждой задачи `solo` наблюдатель есть
всегда (`_jobObserver`), поэтому `notifyError` до зоны не доходит
никогда, а хук `onError` по умолчанию пуст.

- [ ] **Шаг 3.** Добавить защищённый член в `JobBase`, следом за
      `notifyError`.

```dart
  /// Hands [error] to the zone the job was created in.
  ///
  /// For an engine of a domain whose own route for an error with nowhere
  /// to go ends with nobody: `solo` sends one here when neither an
  /// observer nor its hook took it. The core reaches the zone by itself,
  /// through [notifyError] without an observer and through an unobserved
  /// [Failed].
  @protected
  void reportToZone(Object error, StackTrace stackTrace) {
    _debug(() => '$this error went to the zone: $error');
    _zone.handleUncaughtError(error, stackTrace);
  }
```

- [ ] **Шаг 4.** Пометить бездомную ошибку в `_SoloJob`
      (`packages/solo/lib/src/job.dart`), рядом с `_notifyError`.

```dart
  /// Marks the controller while an error with nowhere to go passes
  /// through the hooks.
  ///
  /// [SoloBase.onError] takes two kinds and cannot tell them apart by
  /// itself: the body's failure, which has an outcome carrying it to the
  /// zone already, and this one, which has nothing. Only this one may end
  /// in the zone. Saved and restored, not merely set: the hooks are
  /// synchronously reentrant through `externalSetState` → `_reevaluate`
  /// → `_notifyError`.
  @override
  void notifyError(Object error, StackTrace stackTrace) {
    final previous = _solo._homeless;
    _solo._homeless = this;
    try {
      super.notifyError(error, stackTrace);
    } finally {
      _solo._homeless = previous;
    }
  }

  void _reportToZone(Object error, StackTrace stackTrace) =>
      reportToZone(error, stackTrace);
```

- [ ] **Шаг 5.** Дать телу `SoloBase.onError` содержимое
      (`packages/solo/lib/src/solo_base.dart`), а полю — место рядом с
      `_jobObserver`.

```dart
  /// The job whose error with nowhere to go is going through the hooks
  /// right now, set by `_SoloJob.notifyError`.
  _SoloJob<S, S, Object?>? _homeless;
```

```dart
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    final homeless = _homeless;
    // Only an error with nowhere else to go, only when nobody is
    // listening, and never a cancellation: a cancellation is a decision
    // somebody made, not a failure, and in Flutter it would reach
    // `PlatformDispatcher.onError` for nothing.
    if (homeless != null &&
        identical(homeless, job) &&
        observer == null &&
        error is! Cancelled) {
      homeless._reportToZone(error, stackTrace);
    }
  }
```

Условие `error is! Cancelled` — решение 10 плана, по находке 1 второго
круга ревью. Без него в зону уходит и отмена, а это отменяет первую
половину инварианта 4, которую решено сохранить.

- [ ] **Шаг 6.** Прогнать стенд шага 1.

Команда: `cd packages/solo && dart test test/zone_test.dart`
Ожидание: PASS.

- [ ] **Шаг 7.** Дописать в стенд шесть тестов — маршрут закрывается
      целиком, иначе его нечем удержать от регрессии.

  Тестовые контроллеры объявляются прямо в файле, `final class ...
  extends Solo<TestState>`: `TestSolo` из `support/` — `final class`, и
  наследоваться от него из другой библиотеки нельзя
  (`invalid_use_of_type_outside_library`, находка 3 ревью). `Solo<S>` —
  обычный класс и наследуется свободно; обёртка над `externalSetState`
  добавляется там, где она нужна.

  1. `a homeless error with no observer reaches the zone` — шаг 1.
  2. `the body's failure does not reach the zone twice` — тело падает,
     исход наблюдают через `job.done`; в зоне пусто. Это тот случай,
     который ломало наивное чтение.
  3. `a global observer switches the default route off` — тот же случай,
     что 1, но с `SoloBase.observer`, поставленным на время теста
     (и снятым в `finally`); в зоне пусто.
  4. `an override without super keeps the error out of the zone` —
     контроллер с пустым `onError`; в зоне пусто, ошибка у наследника.
  5. `an override calling super still hands it to the zone` — то же с
     `super.onError(job, error, stackTrace)`; в зоне одна строка.
  6. `a rule that throws reaches the zone` — `keepWhile`, бросающий
     вместо ответа, при `externalSetState`; в зоне одна строка. Это
     смена поведения: сегодня такая ошибка глохнет в пустом хуке. Ей
     место в `CHANGELOG` (задача 7).
  7. `a reentrant notification does not lose the outer error` — находка
     6 первого круга ревью: без него подмена восстановления флага на
     `_solo._homeless = null` проходит все шесть тестов выше.
     Переопределённый `onError` зовёт `externalSetState`, бросающее
     правило даёт вторую ошибку синхронно внутри первой, и после
     возврата внешний хук зовёт `super.onError`. Проверяется, что в зону
     ушли **обе** ошибки и что маршрут после вложенного вызова цел.
  8. `a disposer that throws reaches the zone` — уборщик
     `ctx.onDispose(() => throw StateError('cleanup'))`, ни наблюдателя,
     ни переопределения; в зоне одна строка. Это самый частый случай
     нового радиуса и тот, из-за которого правится
     `packages/solo/README.md`.
  9. `a cancellation never reaches the zone` — три источника подряд:
     отмена снаружи, `throw Cancelled(...)` внутри работы, свежая
     `Cancelled(rules: ...)` от протёкшего контекста. Во всех трёх в
     зоне пусто, а у переопределённого хука строки есть — то есть
     фильтруется маршрут в зону, а не сам хук. Без этого теста подмена
     «снять `error is! Cancelled`» проходит зелёной.

- [ ] **Шаг 8.** Поправить документы, описывающие изменённый хук, — тем
      же коммитом, что и поведение (`AGENTS.md`: документ, противоречащий
      коду, правится вместе с работой):

  - **дартдок `SoloBase.onError`** — переписать целиком: хук принимает
    два рода ошибок; по умолчанию тот, которому идти больше некуда,
    уходит в зону создания задачи, если глобального наблюдателя нет;
    отмена туда не уходит никогда; **переопределение это заменяет, а
    `super.onError(...)` — оставляет**. Провал тела в зону отсюда не
    идёт: он дойдёт туда своим путём, через ненаблюдённый исход.
  - **дартдок `SoloObserver.onError`** в
    `packages/solo/lib/src/observer.dart` — снять фразу «including the
    ones that end as `Cancelled` and are therefore never handed to the
    zone… Those are this hook's business alone»: половина про
    `Cancelled` остаётся верной, половина про «hook's business alone» —
    нет.
  - **`packages/solo/README.md`, §Cleanup, абзац «Errors of a
    disposer»** — сегодня он обещает: «in `solo` a job always has an
    observer, so nothing reaches the zone. With neither of the two
    overridden, a disposer that touches the context stops on its first
    line and nobody hears about it». После этой задачи обещание ложно.
    Переписать вместе с `README.ru.md`.
  - **`docs/architecture.md`, инвариант 4** — вторая половина фразы:
    ошибка, дошедшая до движка только через `onError`, остаётся делом
    observer'а **пока он есть**; без него и без переопределения она идёт
    в зону, как в ядре. Первая половина, про `Cancelled`, остаётся как
    есть.

- [ ] **Шаг 9.** Померить точку удара по сьюте: прогнать всё.

Команда: `cd packages/jobs && dart analyze && dart test`,
затем `cd packages/solo && dart analyze && dart test`,
затем `cd packages/solo/example && dart analyze && dart test`,
затем `cd packages/flutter_solo && flutter analyze && flutter test`
Ожидание: всё зелёное. `runSolo` ставит глобального наблюдателя каждому
тесту, поэтому маршрут в них выключен и старое поведение не меняется.
Если что-то покраснело — разбирать поштучно, не глуша: красный тест здесь
значит либо переопределённый `onError` в самом тесте, либо ошибку в
флаге.

- [ ] **Шаг 10.** Коммит.

```bash
git add packages/jobs packages/solo docs
git commit -m "feat(solo): an error with nowhere to go reaches the zone"
```

### Задача 5. Порядок, остановка и правила

Спека, разделы «Как фоновой работе остановиться» и «Удержание»; вопрос
плана 6.

**Файлы:**
- Создать: `packages/solo/test/unattended_test.dart`

**Интерфейсы:** только тесты, публичной поверхности не меняет.

- [ ] **Шаг 1.** Написать тест порядка: провал приходит после `onFinish`
      **и** после `onClose`. Стенд — `s5_order.dart`, кейс `solo`.

```dart
  test('a late failure arrives after the controller has closed', () {
    final lines = <String>[];
    SoloBase.observer = _Watcher(lines);
    try {
      fakeAsync((async) {
        final solo = _Watched(lines)
          ..run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() async {
            await delay(30);
            throw StateError('late boom');
          });
          await ctx.wait(() => delay(5));
          });
        async.elapse(const Duration(milliseconds: 10));
        solo.close();
        async.flushTimers();
      });
    } finally {
      SoloBase.observer = null;
    }
    expect(lines, [
      'finish j Done(null)',
      'observer.onClose',
      'error j Bad state: late boom',
    ]);
  });
```

`_Watched` — `final class ... extends Solo<TestState>` в самом файле,
пишущий в список из `onFinish` и `onError`. `_Watcher` — наследник
`SoloObserver`, пишущий строку из `onClose`: **настоящее** событие
закрытия живёт у наблюдателя, у `SoloBase` его нет вовсе. Первая
редакция писала строку из переопределённого `close()` после
`await super.close()` и закрепляла тем самым порядок относительно future
закрытия, а не относительно события, названного спекой; удаление вызова
`observer.onClose` из движка оставило бы её тест зелёным (находка 7
ревью).

Импорты файла: `dart:async`, `package:fake_async/fake_async.dart`,
`package:solo/solo.dart`, `package:test/test.dart`, и из `support/` —
`run_solo.dart` ради одного `delay`, `test_solo.dart`, `test_state.dart`.
Сам `runSolo` не звать: он ставит своего глобального наблюдателя и
закрывает контроллер за тебя, а тестам этого файла нужны свои.

- [ ] **Шаг 2.** Прогнать.

Команда: `cd packages/solo && dart test test/unattended_test.dart`
Ожидание: PASS сразу — порядок задан устройством, а не правкой. Тест
пишется, чтобы порядок нельзя было сломать молча; если он падает, значит
в задачах 1–4 что-то не так, и разбираться надо там.

- [ ] **Шаг 3.** Написать тест остановки: работа переживает `close()`,
      пока её не остановят.

```dart
  test('unattended work outlives close until the cleanup stops it', () {
    var ticks = 0;
    fakeAsync((async) {
      // Каскадом, а не двумя операторами: `cascade_invocations` включён.
      final solo = TestSolo()
        ..run<TestState, void>(key: 'j', (ctx) async {
          ctx.unattended(() {
            final timer = Timer.periodic(
              const Duration(milliseconds: 10),
              (_) => ticks++,
            );
            ctx.onDispose(timer.cancel);
          });
          await ctx.wait(() => delay(5));
        });
      async.elapse(const Duration(milliseconds: 100));
      expect(ticks, 0, reason: 'the cleanup stopped the timer with the job');
      solo.close();
      async.flushTimers();
    });
  });
```

И зеркальный к нему — без `ctx.onDispose`. Форму назвать точно, иначе
транскрипция по образцу соседа вешает `fakeAsync` (находка 3 второго
круга ревью): `flushTimers` гонит и периодические таймеры, а этот никто
не отменяет — по условию теста, — и прогон падает на
`Bad state: Exceeded timeout 1:00:00.000000 while flushing timers`.
Поэтому: ручку таймера вынести из форка в `late final Timer` теста,
время двигать `async.elapse` до и после `close()`, сравнивать счётчики
до и после, а `timer.cancel()` поставить перед выходом из `fakeAsync`.
`flushTimers` в этом тесте не звать вовсе. Тикающий после `close()`
счётчик и есть цена, названная в дартдоке.

Почему не `WeakReference`. Ревьюер померил на стенде `s6_retention.dart`,
что живой таймер в форке держит задачу, её исход, замыкание тела и через
`_solo` — контроллер целиком, а `timer.cancel()` всё отпускает. Повторить
это тестом нечем: `dart test` не умеет заставить VM собрать мусор, и
проверка была бы гаданием на давлении памяти. Тестом закрепляется
наблюдаемое следствие — работа живёт, пока её не остановят, — а сам граф
удержания остаётся на стенде и в дартдоке.

- [ ] **Шаг 4.** Написать три теста на ось правил `solo` — единственную
      ось спеки, у которой в плане не было ни одной проверки, и обе
      половины фильтра на ней держались честным словом (находка 4
      второго круга ревью). Всем трём нужен контроллер, поэтому они
      здесь, а не в задаче 1.

  1. `unattended does not look at the rules` — спека, «Группа членов»:
     член во второй группе, правила его не смотрят (инвариант 2). Тело
     делает `emit`, нарушающий собственное правило, и следом зовёт
     `ctx.unattended(...)`; вызов не бросает, задача кончается `Done`.
     Замерено, что без этого теста добавление `check()` перед вызовом
     оставляет всю сьюту зелёной, а контрольный сценарий даёт
     `Cancelled(rules: keepWhile)` вместо `Done`.
  2. `the job's own cancellation by the rules is filtered` — работа
     стоит в `ctx.wait`, состояние уходит из `keepWhile`, задача
     отменяется правилами; строк `error` у наблюдателя нет. Без теста
     снятие фильтра именно для этого случая проходит всю сьюту.
  3. `a fresh Cancelled(rules) from a leaked context reaches the
     observer` — третий случай, который спека в разделе «Фильтр отмены»
     называет пропускаемым намеренно, и единственный со стороны `solo`.
     Задача кончилась `Done`, состояние ушло из `keepWhile`, фон читает
     `ctx.state` — новый объект `Cancelled` проходит фильтр:
     `[j] Cancelled(rules: keepWhile)` у наблюдателя.

- [ ] **Шаг 5.** Прогнать пакет.

Команда: `cd packages/solo && dart analyze && dart test`
Ожидание: анализ чист, все тесты зелёные.

- [ ] **Шаг 6.** Коммит.

```bash
git add packages/solo
git commit -m "test(solo): order, stopping and rules of unattended work"
```

## Фаза C. Документы

Половина решения становится целым только документацией, и она должна
лежать там, где выбирают член, а не там, где разбирают маршрут ошибки
(спека, «Достаточно ли этого»). Эти две задачи — не хвост работы, а её
вторая половина.

### Задача 6. Документы ядра

Спека, раздел «Что меняется в публичном контракте», пункты про `jobs`.

**Файлы:**
- Изменить: `packages/jobs/lib/src/job_context.dart` (дартдок шапки
  класса и члена `unattended`), `lib/src/job_base.dart` (`Job.ignore`),
  `lib/src/job_stream.dart` (`each`), `lib/src/outcome.dart` (`Failed`),
  `lib/src/observer.dart` (`JobObserver.onError`)
- Изменить: `packages/jobs/README.md`, `README.ru.md`, `CHANGELOG.md`

- [ ] **Шаг 1.** Дартдок члена `unattended` — главный текст этой работы.
      В нём, по порядку:

  - что делает: запускает действие как работу, которой задача не ждёт;
  - куда идёт провал: наблюдателю, а без него в зону создания задачи, —
    включая провал, пришедший после конца задачи;
  - **правило про future в обе стороны, жирной строкой:** начинай работу
    внутри и не выноси наружу ничего, что внутри родилось. Future,
    созданная снаружи, внутри при падении не вернётся, а её ошибка уйдёт
    в зону создателя; future, рождённая внутри, снаружи вешает того, кто
    её ждёт, — и тело, и уборщика, и кэш;
  - чего не делает: не ждёт, не отменяет, не мешает работе пережить
    задачу;
  - запрет `run` и `uncancellable` внутри, с причиной в полстроки;
  - как фону остановиться: `job.isFinished` или `job.done`, а не
    `ctx.check()` — из фона он даёт `StateError` в окне уборки и не
    бросает вовсе после `Done`, так что вечный опрос не остановится
    никогда; работа, которая должна кончиться с задачей, кладёт свою
    остановку на стек (`ctx.onDispose(timer.cancel)`) или берёт отмену
    через `ctx.onCancel`;
  - что задача — не фоновая работа: у неё свой исход и свой наблюдатель,
    гасят её `ignore()`;
  - что незавершённая работа держит задачу, её исход и замыкание тела, а
    в `solo` — контроллер целиком, и после `close()` тоже; образец
    остановки — тот же `ctx.onDispose`;
  - что голый `unawaited(...)` по-прежнему уходит в зону: это цена того,
    что тело не форкается, и назвать её надо прямо;
  - что `emit` из работы законен, пока задача жива, — по той же причине,
    по которой законен `wait`: работа бежит внутри живой задачи, а
    монопольность письма держится тем, что корневая задача одна, а не
    тем, кто именно пишет из неё. После конца задачи `emit` бросает
    `StateError` сам. Фраза, не запрет: заводить третий случай в
    `throwIfUnattended` ради дыры, которую никто не назвал опасной, не
    за чем (находка 12 второго круга ревью);
  - пример:

```dart
/// ```dart
/// ctx.unattended(() => analytics.report(event));
/// ```
```

- [ ] **Шаг 2.** Дартдок шапки класса `JobContext`: `unattended` — во
      вторую группу, к тем, кто «только регистрирует». Обе перечислялки в
      шапке дополняются: он не бросает `Cancelled` на помеченной задаче и
      работает в окне уборки; после `isFinished` — `StateError`, как у
      всех.

- [ ] **Шаг 3.** Соседние дартдоки, по фразе на каждый:

  - `JobObserver.onError` — перечень того, что доходит до наблюдателя,
    пополняется работой без присмотра; назвать три случая, когда сюда
    приходит `Cancelled`: отмена ребёнка из `await child.value`, свежая
    `Cancelled(rules: ...)` от протёкшего контекста `solo`, и
    `throw Cancelled(...)` внутри самой работы;
  - `Failed` (`outcome.dart`) — перечень маршрутов пополняется;
  - `Job.ignore` — перекрёстная ссылка «задача — не фоновая работа»;
  - `each` (`job_stream.dart`) — абзац про брошенный вызов переписать.
    Сегодня он советует гасить `ignore()`, а этот совет теряет позднюю
    ошибку обработчика; теперь правильный ответ —
    `ctx.unattended(() => ctx.each(...))`, и он чинит это целиком.
    Заодно поправить соседнее употребление слова `unattended` в том же
    дартдоке (строка про «the handler in flight runs on unattended»),
    чтобы оно не читалось как ссылка на член.

- [ ] **Шаг 4.** `packages/jobs/README.md`:

  - **§Cancellation** — пятый пункт в списке членов («`unattended` — не
    ждать вовсе», в пару к «`wait` — ждать, но не работу», «`join` —
    ждать всё», «`uncancellable` — ждать, придержав отмену») и строка в
    примере;
  - **§Observer** — маршрут ошибки фоновой работы;
  - **§Building on the core** — два новых защищённых члена.

- [ ] **Шаг 5.** `CHANGELOG.md` пакета, секция 0.1.0 (не опубликована,
      правка складывается в текущую секцию). Не только приписать новое,
      но и **дополнить перечни, которые станут неполными** (находка 6
      второго круга ревью):

  - новая строка: `JobContext.unattended` и куда идёт провал;
  - пункт про «a waiting family that says what a cancellation does to a
    call» — четвёртый член в перечень;
  - пункт про защищённую поверхность `JobBase` и `JobContextBase` —
    назвать оба новых защищённых члена, `reportToZone` и
    `throwIfUnattended`. Это поверхность, про которую
    `packages/jobs/README.md` §«Building on the core» говорит «where half
    of this package lives»; там их тоже упомянуть, шагом 4.

- [ ] **Шаг 6.** Перевести правки в `README.ru.md` и сверить.

Команда: `python3 tool/check_translations.py` из корня
Ожидание: четыре пары сходятся.

- [ ] **Шаг 7.** `dart doc` без предупреждений.

Команда: `cd packages/jobs && dart doc`
Ожидание: 0 предупреждений, 0 ошибок.

- [ ] **Шаг 8.** Коммит.

```bash
git add packages/jobs
git commit -m "docs(jobs): unattended work as its user sees it"
```

### Задача 7. Документы `solo` и `flutter_solo`, инварианты, handoff

Спека, раздел «Что меняется в публичном контракте», пункты про `solo`,
`flutter_solo` и репозиторий.

**Файлы:**
- Изменить: `packages/solo/lib/src/solo_base.dart` (дартдоки `SoloBase`
  и `SoloBase.onError`), `lib/src/observer.dart`
  (`SoloObserver.onError`)
- Изменить: `packages/solo/README.md`, `README.ru.md`, `CHANGELOG.md`,
  `doc/vs-bloc.md`
- Изменить: `packages/flutter_solo/README.md`, `README.ru.md`
- Изменить: `docs/ru/solo/vs-bloc.md`, `docs/architecture.md`,
  `docs/handoff.md`

- [ ] **Шаг 1.** Дартдоки `SoloBase.onError` и `SoloObserver.onError`
      здесь **не правятся**: они переехали в задачу 4, туда, где меняется
      само поведение (находка 7 второго круга ревью). Здесь остаётся
      дартдок класса `SoloBase` в части хуков — упомянуть новый член в
      перечне того, что доходит до `onError`.

- [ ] **Шаг 2.** `packages/solo/README.md`:

  - **§Concepts** — продолжить абзац про голый `await`: у семьи членов
    появился четвёртый, и голый `unawaited` встаёт в один ряд с голым
    `await` — вне доктрины;
  - **§Concepts, абзац «Cancellation»** — перечислить группы поимённо с
    новым членом;
  - **§Errors** — маршрут ошибки фоновой работы и то, что по умолчанию
    бездомная ошибка уходит в зону; рядом с существующей фразой про
    fire-and-forget `profile.load();`. Абзац «Errors of a disposer» в
    §Cleanup здесь не трогать: он правится в задаче 4.

- [ ] **Шаг 3.** `packages/solo/doc/vs-bloc.md` §4 — дописать второй
      вариант к фразе про `ctx.run(child)`: работа со своим исходом,
      которую родитель ждёт, — это `ctx.run`; работа без исхода, которую
      он не ждёт, но чей провал слышит, — `ctx.unattended`. Перевод —
      `docs/ru/solo/vs-bloc.md`, тем же коммитом.

- [ ] **Шаг 4.** `packages/solo/CHANGELOG.md`, секция 0.2.0:

  - строка про новый член и маршрут его провала;
  - **отдельная строка про смену поведения, называющая весь набор**, а не
    один `keepWhile`: без глобального наблюдателя и без переопределения
    `onError` в зону создания задачи теперь уходят провал уборщика,
    провал колбэка `onCancel`, поздний провал брошенного `wait` и
    бросившее правило. Отмена не уходит никогда. Первая редакция
    называла здесь один `keepWhile`, и второй круг ревью показал, что
    радиус вчетверо шире (находка 1);
  - дополнить перечни, которые станут неполными (находка 6): «`JobContext`:
    `state`, `stateAs`, `emit`, `check`, `wait`, `join`, `uncancellable`,
    `onCancel`, `run`, `log`» и пункт «A body does not `await` on its
    own».

- [ ] **Шаг 5.** `packages/flutter_solo/README.md` — что значит «в зону»
      во Flutter: `PlatformDispatcher.instance.onError`, если задан,
      иначе лог движка; приложение при этом **не падает**, а `EXIT=255` —
      поведение VM. Место — §Outcomes, рядом с существующей фразой про
      зону создания задачи.

- [ ] **Шаг 6.** `docs/architecture.md`:

  - **«Понятия», абзац «Кооперативная отмена»** — четвёртый член семьи и
    что он делает с отменой (ничего: работу отмена не трогает);
  - **инвариант 2** — `unattended` в перечень членов, которые правила не
    смотрят;
  - **инвариант 4** — здесь не правится, он переехал в задачу 4;
  - **инвариант 8** — `unattended` законен в окне уборки, как
    регистрации; после `isFinished` — `StateError`;
  - **инвариант 10** — без изменений по существу, но проверить, что
    формулировка про изоляцию хуков не расходится с новым телом
    `onError`.

- [ ] **Шаг 7.** Перевести правки в `README.ru.md` обоих пакетов и
      сверить.

Команда: `python3 tool/check_translations.py` из корня
Ожидание: четыре пары сходятся.

- [ ] **Шаг 8.** `dart doc` в `solo`, `flutter doc`-эквивалент не нужен.

Команда: `cd packages/solo && dart doc`
Ожидание: 0 предупреждений, 0 ошибок.

- [ ] **Шаг 9.** Обновить `docs/handoff.md`: запись бэклога «Ловить ошибку
      брошенной футуры» закрыта, работа смержена, коммиты названы. Убрать
      запись из `docs/backlog.md` — тем же коммитом, по правилу
      `AGENTS.md`. Обновить шапку
      `docs/records/2026-09-08[4]-detached-design.md` («реализовано,
      коммиты такие-то») и шапку этого плана.

- [ ] **Шаг 10.** Прогнать всё в последний раз.

Команда: `cd packages/jobs && dart analyze && dart test`,
`cd packages/solo && dart analyze && dart test`,
`cd packages/solo/example && dart analyze && dart test`,
`cd packages/flutter_solo && flutter analyze && flutter test`,
`python3 tool/check_translations.py` из корня
Ожидание: всё зелёное.

- [ ] **Шаг 11.** Коммит.

```bash
git add packages/solo packages/flutter_solo docs
git commit -m "docs(solo): unattended work, its route and its price"
```

## Чего в плане нет

- **Ожидания фоновой работы и её отмены.** Зона видит ошибки, а не
  незавершённость; I/O она не видит вовсе. Спека, «Что вне спеки».
- **Ловли работы, запущенной мимо члена.** Голый `unawaited(...)`
  по-прежнему уходит в зону. Ни линта, ни обёртки для него не
  существует; цена названа в дартдоке (задача 6, шаг 1).
- **Правок `flutter_solo`, кроме README.** Кода там не меняется.
- **Теста на удержание через `WeakReference`.** Причина — в задаче 5,
  шаг 3.
- **Публикации.** Отдельная связка по правилам `AGENTS.md`, только по
  отдельному запросу владельца.

## Как план сверялся со спекой

Первая редакция сверялась только сама с собой, и первый круг ревью
(`2026-09-08[7]-unattended-plan-review.md`) справедливо назвал это
заявлением автора, а не доказательством: покрытие вложенности,
дедупликации и порядка было слабее обещанного. Во второй редакции
проверки на эти три места встали поимённо — задача 2, тесты 3 и 4
(вложенные форки), задача 3, шаги 5 и 6 (вложенность и дубль в `solo`),
задача 5, шаг 1 (порядок относительно настоящего `onClose`).

Второй круг (`2026-09-08[8]-unattended-plan-review-2.md`) шёл с
исполнением и нашёл, чем это заявление всё ещё было сильнее проверок:
ось правил `solo` не была покрыта вовсе (находка 4, три теста в задаче
5), тест «`wait` и `join` разрешены» звал только `wait` (находка 5,
разделён на два), решающий довод спеки про `onCancel` не имел теста
(находка 8, тест 13 задачи 1), а радиус решения 2 был назван вчетверо
уже настоящего (находка 1, условие `error is! Cancelled` и тесты 8 и 9
задачи 4). Список ниже — сверка по разделам, и читать его надо вместе с
обоими кругами.

Прошёл по разделам спеки; каждый закрыт задачей.

- «Что делаем» (член, форк, четыре шага работы) — задача 1.
- «Группа членов» (не бросает `Cancelled`, правила не смотрят, в уборке
  работает, `StateError` после конца, синхронный бросок наблюдателю) —
  задача 1, тесты 4, 9, 10, 11; дартдок — задача 6, шаг 2; инварианты 2 и
  8 — задача 7, шаг 6.
- «Что запрещено внутри `action`» — задача 2.
- «Правило про future, в обе стороны» — документационное целиком, задача
  6, шаг 1, жирной строкой.
- «Задача, созданная внутри `action`» — задача 3, все три её теста: один
  уровень вложенности, два уровня и дубль в `solo`.
- «Как фоновой работе остановиться» — дартдок, задача 6, шаг 1; тест —
  задача 5, шаг 3.
- «Решения владельца» пункт 1 (поздняя ошибка) — задача 1, тесты 1–3;
  пункт 2 (`SoloBase.onError` в зону) — задача 4; пункт 3 (дубль о
  провале ребёнка) — закрыт задачей 3: без форка тела случай возникает
  только через работу, и zone-value его снимает.
- «Механизм решения 2» — задача 4, шаги 3–5; стенд без глобального
  наблюдателя — шаги 1 и 7; смена поведения бросившего правила — тест 6
  и `CHANGELOG` (задача 7, шаг 4).
- «Фильтр отмены» — задача 1, шаг 4 и тесты 5–9; решение по вопросу
  плана — «Решения, принятые в плане сверх спеки», пункт 2. Тест 9 —
  чужой ребёнок под своим каскадом — и есть то, что отличает принятую
  точную проверку от отклонённой эвристики. Три случая, которые фильтр
  пропускает намеренно: первые два — тесты 7 и 8 задачи 1, третий
  (свежая `Cancelled(rules: ...)` от протёкшего контекста) — задача 5,
  шаг 4, тест 3.
- «Удержание» — задача 5, шаг 3; дартдок — задача 6, шаг 1.
- «Цена» — только в дартдок не идёт: 45 нс на вызов и около 48 нс на
  микрозадачу внутри фона названы здесь, чтобы исполнитель не искал их
  заново, и в документы не попадают.
- «Что меняется в публичном контракте» — четырнадцать пунктов, все в
  задачах 6 и 7; переводы и `check_translations.py` — шаги 6 и 7
  соответственно.
- «Что решить в плане» — шесть вопросов, ответы в «Решениях, принятых в
  плане сверх спеки», пункты 1–6.

Чего не проверено и после двух кругов — перечень в
`2026-09-08[8]-unattended-plan-review-2.md`, раздел «Что осталось
непройденным». Коротко: существо задач 6 и 7, то есть сама проза
дартдоков, README, инвариантов и переводов, не написано ни строки —
проверено лишь, что каждый адресат существует и механические проверки на
нём проходят. Плюс граф удержания, двусторонние зависания на границе
future, цена и утверждение про Flutter.
