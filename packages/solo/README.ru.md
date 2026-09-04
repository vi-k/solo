# solo

> Это перевод [`README.md`](README.md). Источник правды — английский
> оригинал; перевод обновляется в том же коммите, что и оригинал. В пакет,
> публикуемый на pub.dev, этот файл не попадает.

Управление состоянием для контроллеров с жизненным циклом: одна задача за
раз, монопольное владение состоянием, декларативные правила и кооперативная
отмена. Чистый Dart, без зависимости от Flutter;
[`flutter_solo`](https://pub.dev/packages/flutter_solo) добавляет лицо
`ValueListenable`.

## Зачем

`solo` вырос из шести претензий к bloc:

1. очередью событий нельзя управлять;
2. если все события `sequential`, одно из них нельзя сделать `restartable`,
   не вынося в отдельную очередь;
3. события, работающие параллельно, пишут в одно и то же состояние;
4. после отмены обработчик продолжает работать, пока сам не проверит
   `emit.isDone`;
5. нельзя дождаться своего события: `stream` говорит, что состояние
   изменилось, а не кто его изменил;
6. снаружи хочется звать метод, а не собирать событие и делать `add`.

[solo и bloc рядом](https://github.com/vi-k/solo/blob/main/docs/ru/solo/vs-bloc.md)
берёт восемь сценариев из разных предметных областей, решает каждый сначала
на bloc — тем обходным путём, который опытная команда и напишет, — а потом
на `solo`.

## Установка

```sh
dart pub add solo
```

Для Flutter берите вместо него `flutter_solo` — он реэкспортирует весь
`solo`:

```sh
flutter pub add flutter_solo
```

## Быстрый старт

Состояние — один неизменяемый объект. Для начала хватит одного класса;
sealed-иерархия появится позже, когда состояния начнут различаться тем, что
они разрешают:

```dart
final class Profile {
  final String name;
  final bool loading;

  const Profile({this.name = '', this.loading = false});

  Profile copyWith({String? name, bool? loading}) =>
      Profile(name: name ?? this.name, loading: loading ?? this.loading);

  @override
  String toString() => 'Profile("$name", loading: $loading)';
}
```

Контроллер — обычный класс с обычными методами. Каждый метод создаёт задачу
и отдаёт её очереди; возвращаемый хэндл — не `Future`, поэтому вызвать метод
без `await` законно и линтов это не поднимает:

```dart
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable,
        (ctx) async {
          ctx.emit(ctx.state.copyWith(loading: true));
          final name = await ctx.guard(api.fetchName);
          ctx.emit(Profile(name: name));
          return name;
        },
      );
}
```

Снаружи:

```dart
final profile = ProfileController(ProfileApi());
final subscription = profile.stream.listen(print);

final job = profile.load();
profile.load(); // droppable: та же задача, а не вторая

print(await job.value); // Ada Lovelace; сбой будет переброшен здесь
print(profile.state.name); // то же имя, прямо из состояния

await subscription.cancel();
await profile.close();
```

`run<Profile, String>` говорит, что задача работает с состояниями `Profile`
и возвращает `String`. Внутри тела `ctx.emit` — единственный способ записать
состояние, а `ctx.guard` ждёт future так же, как `await`, но сдаётся в тот
момент, когда задачу отменяют. `Policy.droppable` с `key: 'load'` означает,
что второй `load()`, пока первый ещё стоит в очереди или выполняется, вернёт
ту первую задачу, а не запустит вторую.

Чтение бесплатно: `profile.state` — текущее состояние, синхронно, для кого
угодно; `profile.stream` — broadcast-стрим всех изменений, доставляемых
микротаской позже. Пишут только задачи: по одной за раз, в порядке очереди,
никогда не накладываясь.

`close()` выключает контроллер насовсем: стоящие в очереди задачи
заканчиваются `Cancelled(closed)`, выполняющаяся отменяется, а последующие
вызовы вместо броска возвращают задачи, уже завершённые с
`Cancelled(closed)`.

## Понятия

**Состояние.** Один неизменяемый объект типа `S`, обычно sealed-иерархия с
объединёнными интерфейсами (`NotDisposed`, `Initialized`), чтобы задачи
могли объявлять рабочий тип шире одного класса. `solo.state` читается кем
угодно и когда угодно; пишут только задачи.

**Контроллер.** Владелец состояния и очереди. Иерархия линейная:
`SoloBase<S>` — движок и `state`; `Solo<S>` добавляет broadcast-`stream`;
`SoloListenable<S>` в `flutter_solo` добавляет `ValueListenable`.
Различаются они только тем, как доставляется изменение.

**Задача.** Единица работы: `async`-тело `Future<T> Function(JobContext)`,
необязательный `key`, правила и хэндл `Job<T>`. `job(...)` создаёт задачу,
не ставя её в очередь, `add(job, policy: ...)` ставит её в очередь,
`run(...)` делает и то и другое одним вызовом.
`describe: () => 'zoom: $zoom'` даёт задаче подпись для логов, наблюдателя
и `toString`, который печатает `Job(key: label)` вместо `Job(key)`.
Одновременно выполняется не больше одной корневой задачи, и пока она идёт,
никакая другая задача этого контроллера состояние не трогает.

**Рабочий тип `W`.** Подтип `S`, с которым задача согласна работать. Тело
видит `ctx.state` уже суженным до `W`. Тип проверяется перед стартом задачи,
при каждом изменении состояния, пока она идёт, и при каждом чтении через
контекст.

**Правила.** `canStart` проверяется один раз, когда задачу берут из очереди;
провал выбрасывает задачу с `Cancelled(rules, 'canStart')` и
`started: false`. `keepWhile` проверяется непрерывно — и перед стартом тоже,
вместе с `canStart`: задача, у которой инвариант уже нарушен, не стартует
вовсе, вместо того чтобы стартовать и умереть на первом чтении.

**Отмена.** Кооперативная: прервать чужой `await` в Dart нельзя. Отменённая
задача узнаёт об этом при следующем обращении к контексту — любой член
`JobContext`, кроме `log` и `job`, бросает `Cancelled` этой задачи, как
только она отмечена. После голого `await` зовите `ctx.check()`. Чтобы
дождаться чего-то и сразу сдаться при отмене, оберните это в
`ctx.guard(() => ...)`: guard возвращает управление, как только придёт одно
из двух: результат действия или отмена.

**Чего guard не делает.** Он прекращает ожидание, но не работу. Действие
доработает до конца, а его результат будет выброшен. Для чтения, которое не
жалко бросить, это нормально; для всего, что обязано остановиться
по-настоящему или что нельзя запускать дважды одновременно, — нет. Отдайте
отмену самой работе через `ctx.onCancel(callback)`, который срабатывает в
момент пометки задачи, и дождитесь её возврата, а не уходите от неё:

```dart
Job<void> seek(Duration position) => run<Ready, void>(
      key: 'seek',
      policy: Policy.restart,
      (ctx) async {
        final token = CancelToken();
        ctx.onCancel(token.cancel);
        // Устройство останавливается само, и задача заканчивается только
        // после его возврата, поэтому следующий seek не наложится на этот.
        // Если отмена пришла, пока оно останавливалось, emit ниже бросит
        // Cancelled.
        await _player.seek(position, cancelToken: token);
        ctx.emit(ctx.state.copyWith(position: position));
      },
    );
```

**Дети.** `ctx.run(child)` запускает задачу прямо сейчас, в обход очереди,
ребёнком текущей. Родитель завершается только после всех своих детей.
`ctx.run(child).done` даёт исход и никогда не бросает;
`ctx.run(child).value` даёт значение и бросает `Cancelled` ребёнка или его
ошибку в тело родителя.

**Внешнее состояние.** `externalSetState(next)` устанавливает состояние вне
всякой задачи: листенер железа, принудительный переход. Каждая работающая
задача, кроме излучившей, немедленно переоценивается по новому состоянию;
излучившая проверяется лениво, на следующем чтении.

**Исходы.** `Outcome<T>` — sealed, поэтому `switch` по трём его случаям
исчерпывающий: `Done` несёт возвращённое `value`, `Failed` несёт `error` и
`stackTrace`, `Cancelled` несёт `reason`, флаг `started`, необязательное
`description` и стектрейс самой отмены. Причина — это `CancelReason`:
`manual`, `rules`, `closed`, `parent`, `handler`. `job.done` завершается
исходом и никогда не бросает; `job.value` завершается значением или бросает;
`job.whenCancelled` завершается в момент, когда задача отмечена отменённой,
ещё до конца тела; `job.cancel()` отменяет и ждёт, пока задача действительно
завершится; `job.ignore()` говорит, что на исход никто смотреть не будет.

**Очередь и политики.** `queue` — объект первого класса, видимый
наследникам: `jobs`, `remove`, `removeWhere`, `clear`, `lastWhere`. Три
удаляющих метода пропускают задачи с `cancellable: false`, если не передан
`force: true`, и ни один из них не трогает выполняющуюся задачу. Политики —
сахар для типового случая одного ключа: `sequential` дописывает в конец;
`droppable` возвращает стоящую в очереди или выполняющуюся задачу с тем же
ключом, а новую выбрасывает; `replace` удаляет из очереди задачи с тем же
ключом; `restart` вдобавок отменяет выполняющуюся, не дожидаясь её.
`add(job, first: true)` ставит задачу в голову.

**Стрим.** `Solo.stream` — broadcast-стрим всех изменений состояния, по
порядку, доставляемых следующей микротаской: стрим асинхронный. Источник
правды — `state`: к моменту прихода события `state` может быть уже новее.
Равенство не проверяется; каждое изменение — одно событие. В `flutter_solo`
слушатели `SoloListenable` зовутся синхронно, в порядке подписки, пока
событие стрима ещё в пути.

## Правила, не видные из сигнатур

`cancellable: false` защищает задачу от чужой воли: ручного `cancel`,
`clear` без `force`, отмены родителя, `close`. От реальности не защищает:
если состояние перестало подходить по `W` или `keepWhile`, задача отменяется
всё равно, потому что читать ей уже нечего. Неотменяемой задаче, которая
должна пережить любое состояние, нужен базовый тип `S` и никакого
`keepWhile`.

`ctx.uncancellable(action)` говорит то же самое про один шаг тела, а не
про всю задачу, и составляет пару к `ctx.guard`: `guard` прекращает
ожидание, но не работу, а этот на время `action` вовсе не даёт себя
отменить. Годится для
шага, который назад не отыграть, — платёж, уже ушедший на сервер, запись,
уже идущая по проводу. Пришедшие в это время `cancel` и `close` получают
отказ, а не откладываются, `close` дожидается тела, и правила этим тоже не
покрыты. Участки вкладываются друг в друга, а ответ, действовавший до
шага, возвращается после — бросил шаг или нет.

`emit` доверяем, чтения проверяем. Излучённое состояние не проверяется
против правил излучившей задачи — иначе задача `close`, объявленная как
`run<NotClosed, void>`, отменяла бы сама себя в тот момент, когда излучит
`Closed()`. Следующее чтение, впрочем, проверяется как обычно, поэтому
задача, излучившая себя за пределы своего `W`, больше не должна трогать
`ctx`: излучайте такое состояние последней инструкцией тела, иначе задача
кончится `Cancelled(rules, 'is not W')` на следующем чтении.

`ctx.run(child)` возвращает хэндл, а не значение.
`await ctx.run(child).value` бросает в родителя,
`switch (await ctx.run(child).done)` — нет. Забытый `await` ничего не
ломает: родитель дожидается своих детей в любом случае.

Задача, переданная в `ctx.run`, становится ребёнком, даже если её выбросят
до старта. Сначала она регистрируется ребёнком и только потом проверяется по
правилам, поэтому родитель всегда отчитывается за каждую задачу, которую
пытался запустить.

`add` в закрытый контроллер не бросает. Он возвращает задачу, уже
завершённую с `Cancelled(closed)`, так что местам вызова проверка
`isClosed` не нужна.

Любая политика, кроме `sequential`, при `key == null` бросает
`ArgumentError`, а не `assert`: в release `null == null` истинно, и
`replace` вычистил бы из очереди все задачи без ключа.

`ctx.emit` и `ctx.run` после завершения задачи бросают `StateError`.
Контекст, утёкший из своей задачи — захваченный замыканием, которого никто
не дождался, — не должен писать состояние вне критической секции. Чтения
(`state`, `stateAs`, `check`, `guard`) после нормально завершившейся задачи
законны; после отменённой они всё так же бросают её `Cancelled`. `log` не
бросает никогда.

`close()`, которого ждут изнутри тела текущей задачи, не завершается
никогда: он ждёт как раз это тело. То же и с `cancelAll()`. Отменяйте
изнутри выходом из тела или броском `Cancelled('why')`.

Из тела задачи видна вся поверхность наследника `Solo`, поэтому `ctx.solo`
и нет.

## Ошибки

Задача, бросившая исключение, не ломает контроллер и не останавливает
очередь: ошибка становится исходом задачи, и запускается следующая.
`Outcome<T>` — sealed, поэтому один `switch` покрывает всё, что может
случиться с задачей:

```dart
switch (await profile.load().done) {
  case Done(:final value):
    print('loaded $value');
  case Failed(:final error):
    print('not loaded: $error');
  case Cancelled(:final reason):
    print('gave up: $reason');
}
```

`job.done` не бросает никогда. `job.value` вместо исхода даёт значение, а
ошибку тела перебрасывает с её исходным стектрейсом или бросает `Cancelled`
задачи. `Cancelled` — не сбой: так заканчивается задача, выброшенная как
дубликат, обрезанная `close` или та, чьё состояние перестало подходить под
её правила. Это обычный ход дел, а не повод для отчёта.

Любой сбой доходит и до хуков, ещё до того как исход будет выдан тому, кто
его ждёт: `onError` у самого контроллера и `SoloObserver.onError` на весь
процесс. Поставьте наблюдателя на старте — и каждый сбой каждого
контроллера будет отправлен один раз и в одном месте.

Задача, на которую никто не смотрит, не молчит. Когда задача кончается
`Failed`, а её исход никто не наблюдал — ни `job.done`, ни `job.value`, ни
`job.ignore()`, — движок отдаёт ошибку в зону, в которой задача была
создана, через `Zone.handleUncaughtError`, ровно так же, как Dart поступает
с необработанной ошибкой `Future`. Вызов `profile.load();` отдельной
строкой, без ожидания, всё равно сообщит, что пошло не так.

Когда сбой и правда обрабатывается в другом месте — в `onError`, у
наблюдателя, — так и скажите:

```dart
profile.load().ignore(); // аналог Future.ignore
```

`ignore()` помечает задачу наблюдаемой, не дожидаясь её.

`Cancelled` в зону не уходит никогда, и ошибка, пришедшая после отмены
задачи, — тоже: действие, которого `guard` перестал ждать и которое упало
позже, доходит до `onError` и там останавливается.

## Тесты

Никакого `bloc_test` здесь нет, и он не нужен: точка синхронизации — хэндл
задачи. Запустите задачу, дождитесь её исхода, потом смотрите на состояние.

```dart
test('load fills in the name', () async {
  final profile = ProfileController(FakeProfileApi());

  final outcome = await profile.load().done;

  expect(outcome, isA<Done<String>>());
  expect(profile.state.name, 'Ada Lovelace');

  await profile.close();
});
```

Берите `job.value` вместо `job.done`, когда тест про возвращаемое значение,
и `await expectLater(profile.load().value, throwsA(...))`, когда он про
сбой.

Когда важно время — debounce, таймаут, гонка двух задач, — заворачивайте
тест в `fakeAsync` и двигайте время руками. Наблюдатель, собирающий один
упорядоченный журнал, превращает целый эпизод в один `expect`, а это ловит
ошибки порядка, которых не увидит никакая проверка конечного состояния:

```dart
final class Journal extends SoloObserver {
  final lines = <String>[];

  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      lines.add('${job.key} ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      lines.add('state: $current');
}

test('a second load while the first one runs is dropped', () {
  fakeAsync((async) {
    final journal = Journal();
    SoloBase.observer = journal;
    final profile = ProfileController(FakeProfileApi());

    final first = profile.load();
    final second = profile.load();
    expect(identical(first, second), isTrue);

    async.elapse(const Duration(milliseconds: 20));
    expect(journal.lines, [
      'load Cancelled(manual: duplicate)',
      'load started',
      'state: Profile("", loading: true)',
      'state: Profile("Ada Lovelace", loading: false)',
      'load Done(Ada Lovelace)',
    ]);

    profile.close();
    async.flushTimers();
    SoloBase.observer = null;
  });
});
```

`SoloBase.observer` — глобальная переменная: ставьте её в начале теста и
сбрасывайте в конце. `stream` тоже работает с
`expectLater(..., emitsInOrder([...]))`, но он асинхронный: после
`await job.done` состояние уже конечное, так что обычно хватает чтения
`state`.

## Рецепты

**Таймаут.** Движок ничего не знает о таймаутах; `guard` плюс
`Future.timeout` — вот и весь рецепт. На таймауте тело бросает, и задача
заканчивается исходом `Failed`:

```dart
Job<void> connect() => run<Idle, void>(
      key: 'connect',
      (ctx) async {
        await ctx.guard(
          () => hw.open().timeout(const Duration(seconds: 5)),
        );
        ctx.emit(const Connected());
      },
    );
```

**Debounce.** Тоже вне движка: держите `Timer` в контроллере и запускайте
задачу, когда он сработает. Совмещайте это с `Policy.restart`, чтобы задачу,
всё ещё работающую с предыдущим вводом, отменяли, а не дожидались. Эту
задачу никто не ждёт, поэтому сбой `api.search` уйдёт в зону; способы этого
избежать — в разделе [Ошибки](#ошибки):

```dart
import 'dart:async';

final class Search extends Solo<SearchState> {
  final SearchApi api;

  Timer? _debounce;

  Search(this.api) : super(const SearchState.idle());

  void query(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      run<SearchState, void>(
        key: 'query',
        policy: Policy.restart,
        describe: () => text,
        (ctx) async {
          final results = await ctx.guard(() => api.search(text));
          ctx.emit(SearchState.results(results));
        },
      );
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
```

**Хуки.** Контроллер может переопределить `onStart`, `onFinish`, `onError`,
`onLog` и `onChange`, чтобы реагировать на собственные задачи:

```dart
final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  // ...задачи выше...

  @override
  void onError(Job<Object?> job, Object error, StackTrace stackTrace) {
    reportCrash(error, stackTrace);
  }
}
```

**Наблюдатель.** `SoloObserver` — сквозная версия тех же пяти хуков плюс
`onCreate` и `onClose`: аналитика, отправка ошибок, единый лог на все
контроллеры процесса. Движок зовёт наблюдателя перед собственным хуком
контроллера и независимо от него — наследник, забывший `super`, наблюдателя
не выключает:

```dart
final class LoggingObserver extends SoloObserver {
  @override
  void onStart(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job started');

  @override
  void onFinish(SoloBase<Object> solo, Job<Object?> job) =>
      print('$job finished ${job.outcome}');

  @override
  void onChange(SoloBase<Object> solo, Object previous, Object current) =>
      print('state: $current');
}

void main() {
  SoloBase.observer = LoggingObserver();
}
```

Хуки — канал, а не звено цепи: ошибка, брошенная любым из них, хоть хуком
контроллера, хоть наблюдателем, уходит в текущую зону — ровно как Dart
поступает с необработанной ошибкой `Future`, — и больше ни на что не влияет.
Задача заканчивается тем исходом, который у неё был, очередь идёт дальше,
`close` завершается, а хук, стоящий рядом с бросившим, всё равно вызывается.

Чтобы трассировать сам движок, а не задачи, поставьте
`SoloBase.debug = print`.

## Flutter

`flutter_solo` добавляет `SoloListenable<S> extends Solo<S> implements
ValueListenable<S>` и реэкспортирует весь `solo`. В контроллере меняется
только базовый класс — задачи остаются ровно такими, какие они есть:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Profile());

  // ...задачи выше...
}
```

Никакого `SoloProvider` нет, и контроллер за вас никто не закрывает.
Контроллер, принадлежащий одному экрану, создаётся в `initState` и
закрывается в `dispose`; контроллер, общий для нескольких экранов, кладётся
в то, чем вы для этого уже пользуетесь, — `provider`, `get_it`,
`InheritedWidget`, — и закрывается там.

Побочный эффект — не состояние: весь механизм в том, чтобы дождаться задачи.
Проверьте `mounted` после ожидания, как после любого `await` в `State`, и
дальше решайте, что делать с исходом:

```dart
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController profile;

  @override
  void initState() {
    super.initState();
    profile = ProfileController(ProfileApi());
  }

  @override
  void dispose() {
    unawaited(profile.close());
    super.dispose();
  }

  Future<void> _open() async {
    final outcome = await profile.load().done;
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case Done():
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
        );
      case Failed(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      case Cancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ValueListenableBuilder<Profile>(
            valueListenable: profile,
            builder: (context, state, _) => state.loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _open,
                    child: const Text('Open profile'),
                  ),
          ),
        ),
      );
}
```

`ListenableBuilder` и `AnimatedBuilder` тоже принимают контроллер — он
`Listenable`, — когда билдеру само значение не нужно. `value` и `state` —
один и тот же объект. Сеттера нет намеренно: лицо `ValueNotifier` было бы
дырой в гарантии владения.

## Переход с bloc

| bloc | solo |
| --- | --- |
| `Bloc<E, S>`, `Cubit<S>` | `Solo<S>`, `SoloListenable<S>` |
| класс события, `on<E>`, `add(E())` | метод, возвращающий `Job<T>` |
| `EventTransformer` | `Policy` у задачи |
| `emit(next)` | `ctx.emit(next)` |
| `if (emit.isDone) return;` | `ctx.check()` или `ctx.guard(...)` |
| `state`, `stream` | `state`, `stream` |
| `BlocObserver` | `SoloObserver` |
| `BlocBuilder`, `BlocSelector` | `ValueListenableBuilder` |
| `BlocListener` | `await job.done` в месте вызова |
| `BlocProvider` | `initState` плюс `dispose` |
| `close()` | `close()` |
| `blocTest` | `test` плюс `await job.done` |

Трансформеры ложатся по именам: `sequential()` — это `Policy.sequential`,
`droppable()` — `Policy.droppable`, `restartable()` — `Policy.restart`. У
`Policy.replace` — выбросить то, что в очереди, оставить то, что
выполняется, — своего трансформера нет, и политика выбирается на вызов, а не
на тип события.

Три вещи не имеют аналога намеренно. Трансформера `concurrent` нет: задачи
одного контроллера никогда не накладываются, а работа, которая и правда
параллельна, уходит внутрь одной задачи, и та дожидается её сама.
Защищаться не от чего вроде `emit` после `close`: `add` в закрытый
контроллер возвращает задачу, уже завершённую с `Cancelled(closed)`, так
что местам вызова проверка `isClosed` не нужна. И событие — не значение, за
которое можно держаться: вызов метода отдаёт `Job<T>`, и вызывающий может
дождаться ровно той работы, которую сам и запустил.

## Пример

Камера ниже — форма настоящего контроллера: несколько задач с разными
политиками, задача, которую нельзя отменять, и освобождение ресурсов,
чистящее очередь перед собственным запуском. Состояние — sealed-иерархия,
а `NotDisposed` — объединённый интерфейс, который задачи могут объявлять
своим рабочим типом:

```dart
sealed class CameraState {
  const CameraState();
}

sealed class NotDisposed extends CameraState {
  const NotDisposed();
}

final class Initial extends NotDisposed {
  const Initial();
}

final class Preparing extends NotDisposed {
  const Preparing();
}

final class Ready extends NotDisposed {
  final double zoom;
  final bool paused;

  const Ready({this.zoom = 1, this.paused = false});

  Ready copyWith({double? zoom, bool? paused}) =>
      Ready(zoom: zoom ?? this.zoom, paused: paused ?? this.paused);
}

final class Disposed extends CameraState {
  const Disposed();
}
```

```dart
enum CameraKey { init, closeCamera, setZoom, takePhoto, dispose }

final class CameraController extends Solo<CameraState> {
  final FakeCameraHardware hw;

  CameraController(this.hw) : super(const Initial());

  Job<void> init() => run<NotDisposed, void>(
        key: CameraKey.init,
        policy: Policy.droppable,
        canStart: (state) => state is Initial,
        (ctx) async {
          ctx.emit(const Preparing());
          await ctx.guard(hw.open);
          ctx.emit(const Ready());
        },
      );

  Job<void> setZoom(double zoom) => run<Ready, void>(
        key: CameraKey.setZoom,
        policy: Policy.replace,
        describe: () => 'zoom: $zoom',
        canStart: (state) => !state.paused,
        (ctx) async {
          await ctx.guard(() => hw.setZoom(zoom));
          ctx.emit(ctx.state.copyWith(zoom: zoom));
        },
      );

  Job<Photo> takePhoto() => run<Ready, Photo>(
        key: CameraKey.takePhoto,
        policy: Policy.droppable,
        canStart: (state) => !state.paused,
        (ctx) async {
          final photo = await ctx.guard(hw.capture);
          queue.clear();
          ctx.log('captured $photo');
          return photo;
        },
      );

  Job<void> _closeCameraJob() => job<NotDisposed, void>(
        key: CameraKey.closeCamera,
        cancellable: false,
        (ctx) async => hw.close(),
      );

  Job<void> dispose() {
    queue.clear(force: true);
    current?.cancel();
    return run<CameraState, void>(
      key: CameraKey.dispose,
      policy: Policy.droppable,
      cancellable: false,
      (ctx) async {
        if (ctx.state is Disposed) {
          return;
        }
        if (ctx.state is! Initial) {
          await ctx.run(_closeCameraJob()).done;
        }
        ctx.emit(const Disposed());
      },
    );
  }
}
```

Снаружи:

```dart
final camera = CameraController(FakeCameraHardware());
await camera.init().done;

camera.setZoom(2); // await не нужен, и линта об этом нет

final photo = await camera.takePhoto().value;

switch (await camera.dispose().done) {
  case Done():
    print('disposed');
  case Cancelled(:final reason):
    print('cancelled: $reason');
  case Failed(:final error):
    print('failed: $error');
}

await camera.close();
```

Четыре вещи в этом контроллере стоят по фразе каждая.

**Рабочий тип шире условия старта.** `init` стартует только из `Initial`, но
объявлен как `run<NotDisposed, void>`, потому что первой же строкой излучает
`Preparing`, а тело потом продолжает читать контекст. Условие старта живёт в
`canStart`; `W` покрывает все состояния, через которые проходит тело.

**`takePhoto` чистит очередь.** Команды, накопившиеся, пока затвор был
открыт, целились в тот кадр, который только что снят. Как только съёмка
удалась, они протухли, и снимок их выбрасывает, вместо того чтобы применять
к следующему кадру. `queue.clear()` без `force` не трогает задачи с
`cancellable: false` и никогда не трогает выполняющуюся задачу — сам снимок.

**`dispose()` — задача; `close()` — конец контроллера.** `dispose()`
возвращает железо на место, и его можно поставить в очередь, выбросить как
дубликат и дождаться, как любую другую задачу. `close()` сбрасывает
очередь, отменяет выполняющуюся задачу и отказывает всему, что придёт после.
Одно не подразумевает другого: один только `close()` оставит камеру
открытой. Сначала дождитесь `dispose()`, потом закрывайте.

**Стоящий в очереди `setZoom` заменяется, выполняющийся — нет.**
`Policy.replace` удаляет из очереди задачи с тем же ключом; уже
выполняющуюся оставляет доработать. `Policy.restart` отменил бы и её, а
`Policy.droppable` — то, чем пользуется `takePhoto`, — сохраняет
выполняющуюся задачу и выбрасывает новую.

[`packages/solo/example/`](packages/solo/example) — работающий пакет с этим
контроллером, только расширенным: фейковая камера, железо которой отвечает с
задержкой и может сломаться само, состояние `Broken`, задачи `reopen`,
`pause`, `resume` и фокуса, четыре теста по упорядоченному журналу и
`bin/main.dart`, печатающий тот же журнал в реальном времени.

```sh
cd example
dart pub get
dart run bin/main.dart
dart test
```
