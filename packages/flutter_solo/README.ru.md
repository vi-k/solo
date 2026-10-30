# flutter_solo

Управление состоянием для Flutter: последовательные задачи над одним
состоянием, монопольное владение им, кооперативная отмена и перерисовка через
`SoloBuilder` или `ValueListenable`.

Контроллер владеет состоянием и выполняет над ним задачи по одной.
`SoloBuilder` перестраивает виджет на каждое изменение этого состояния.
Подмешайте в контроллер `SoloListenable`, и он станет ещё и `ValueListenable`
своего состояния, поэтому вставляется прямо в `ValueListenableBuilder`,
`ListenableBuilder`, `AnimatedBuilder` и `Listenable.merge`.

На [сайте документации](https://docs.yet-another.dev/ru/flutter_solo/) лежат
эта страница и руководства пакетов под ней.

## Зачем

У экрана есть жизненный цикл, и у работы на нём тоже. Загрузку надо бросить,
когда пользователь ушёл, сохранение нельзя разрезать пополам, а второе нажатие
не должно отправить второй запрос. `setState` и `ChangeNotifier` дают, где
держать состояние, и ничего не говорят про работу. `Bloc` планирует работу
и просит класс события на каждый вызов; `Cubit` оставляет обычные методы
и ничего не планирует.

Здесь метод остаётся методом и отдаёт хэндл:

```dart
final job = controller.load();

await job.cancel(); // возвращается, когда Job действительно остановилась
print(job.outcome); // Cancelled(manual)
```

За что держится движок:

- Одна корневая задача контроллера за раз, поэтому две из них никогда не пишут
  одно и то же состояние.
- Правила вместо флагов: задача объявляет, с какими состояниями работает и при
  каком условии живёт, и её отменяют, когда они перестают выполняться.
- Отмена, о которой может попросить вызывающий: её бросает следующая
  контрольная точка контекста, а тело, которое до такой точки не дошло, всё
  равно кончается `Cancelled` и само состояния не пишет.
- Исход у каждой задачи, один из `Done`, `Failed` и `Cancelled`: его экрану
  и надо показать.

Длинный разбор, одиннадцать сценариев, решённых сначала на bloc, а потом здесь,
лежит в [solo и bloc рядом](../../docs/ru/solo/vs-bloc.md).

Чего здесь нет: ни `SoloProvider`, ни кодогенерации, ни внедрения зависимостей,
ни персистентности, ни параллельных корневых задач. Зависимости оставлены
в стороне сознательно: их передают другими способами и пакетами, например
[scopo](https://pub.dev/packages/scopo). По одной задаче за раз пакет работает
тоже намеренно, отсюда и `solo` в его имени: в этом его предмет, а не предел
его движка.

## Установка

```sh
flutter pub add flutter_solo
```

Одной зависимости достаточно: `flutter_solo` реэкспортирует целиком
[solo](https://pub.dev/packages/solo), а тот целиком реэкспортирует
[async_job](https://pub.dev/packages/async_job). `Solo`, `SoloContext`, `Job`,
`Outcome` и `Policy` приходят вместе с

```dart
import 'package:flutter_solo/flutter_solo.dart';
```

Собственная часть пакета приходит с тем же импортом: миксин `SoloListenable`,
виджеты `SoloBuilder` и `SoloSelector`, класс `SoloSelection`. Второй импорт
по соседству добавляет `select` и `listen` методами, вместе с подписками,
которые отдаёт `listen`:

```dart
import 'package:flutter_solo/listenable.dart';
```

Почему он второй, объясняет раздел
[«Методы из второго импорта»](#методы-из-второго-импорта).

Плагин анализатора [solo_lints](https://pub.dev/packages/solo_lints) сообщает
в коде о большинстве [частых ошибок](../../docs/ru/solo/mistakes.md) `solo`.
Назовите его в `analysis_options.yaml`:

```yaml
plugins:
  solo_lints: ^0.1.1
```

Так включаются его предупреждения; линты включаются по имени, как показывает
его раздел
[«Установка»](https://github.com/vi-k/solo/blob/main/packages/solo_lints/README.ru.md#установка).
Начиная с Flutter 3.44 `flutter analyze` не показывает ни одной его
диагностики: запускайте `dart analyze` или смотрите их в редакторе.

## Как пользоваться

`ProfileApi` здесь — собственный сервис приложения: `fetchName()` возвращает
`Future<String>`, а `saveName(name)` — `Future<void>`. Вызов `fetchName()`,
который не удался, бросает `ApiException`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class Profile {
  // Что спрашивает кнопка Save; сохранять есть что только у загруженного.
  bool get canSave => this is Loaded;
}

final class Empty extends Profile {}

final class Loading extends Profile {}

final class Loaded extends Profile {
  final String name;

  Loaded(this.name);
}

final class ProfileController extends Solo<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => enqueue<Profile, String>(
    key: 'load',
    policy: Policy.droppable, // второе нажатие вернёт первую Job
    (ctx) async {
      ctx.emit(Loading());
      final name = await ctx.abandonable(api.fetchName);
      ctx.emit(Loaded(name));

      return name;
    },
    isExpectedError: (error) => error is ApiException,
    // Без них упавшая или отменённая загрузка оставляет состояние
    // на Loading: спиннер, и нажать на экране нечего.
    ifFailed: (state, error, stackTrace) => Empty(),
    ifCancelled: (state, cancelled) => Empty(),
  );

  Job<void> save() => enqueue<Loaded, void>(
    key: 'save',
    (ctx) => ctx.join(() => api.saveName(ctx.state.name)),
  );
}

class ProfileView extends StatelessWidget {
  final ProfileController controller;

  const ProfileView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => SoloBuilder<Profile>(
    solo: controller,
    builder: (context, state, _) => switch (state) {
      Empty() => TextButton(
        onPressed: controller.load,
        child: const Text('Load'),
      ),
      Loading() => const CircularProgressIndicator(),
      Loaded(:final name) => Text(name),
    },
  );
}
```

`enqueue<Profile, String>` говорит, что `Job` работает с состояниями `Profile`
и возвращает `String`. `save` сужает это до `Loaded`: в другом состоянии такая
`Job` не стартует, а кончается там `Cancelled`, и её тело читает `Loaded`
с `name` внутри. Внутри тела:

- Состояние записывает только `ctx.emit`.
- `ctx.abandonable` ждёт так же, как `await`, но сдаётся в тот момент, когда
  `Job` отменяют.
- `ctx.join` дожидается своего вызова в любом случае, так что сохранение
  не рвётся пополам.

`ifFailed` и `ifCancelled` ведут назад. Они говорят, в каком состоянии остаётся
упавшая или отменённая загрузка. Без них экран держал бы спиннер задачи,
которой уже нет.

Отвечают они за экран, а не за того, кто вызвал метод. Кнопка выбрасывает
`Job`, которую вернул `load`. Провал, который никто не прочитал, уходит в зону,
даже когда `ifFailed` уже вернул на экран `Empty`, если `load` не называет этот
провал в `isExpectedError` и за него не отвечает `Solo.unansweredHandler`.
`load` называет `ApiException`, поэтому неудачный вызов дальше `Empty` не идёт:
в ответ на него хватит экрана. Баг — это не `ApiException`, и он идёт дальше:
в приложении к `PlatformDispatcher.onError`, в виджет-тесте в сам тест, и тест
падает. Правило описано в разделе [«Исходы»](#исходы). Всё API целиком,
с правилами, очередью, детьми и наблюдателями, описано
в [solo](https://pub.dev/packages/solo).

Состояние рисует `SoloBuilder`: он принимает контроллер как `solo`,
перестраивается на каждое изменение состояния и передаёт `child` нетронутым.
Таблица называет все способы следить за контроллером, а разделы ниже разбирают
остальные:

| Что нужно экрану | Что взять |
| --- | --- |
| Виджет, который рисуется из всего состояния | `SoloBuilder` или `ValueListenableBuilder` с `SoloListenable` |
| Виджет, который перестраивается, только когда меняется одно значение | `SoloSelector` |
| Это значение как `ValueListenable`, который держит `State` | `SoloSelection` |
| Один виджет над двумя контроллерами | `Listenable.merge` в `ListenableBuilder`, с `SoloListenable` |
| Колбэк на каждое изменение вне `build` | `listen` из второго импорта, с `SoloListenable` |

## Контроллер как `ValueListenable`

У фреймворка есть свои билдеры, и они принимают `ValueListenable`. Подмешайте
в контроллер `SoloListenable`, и он им станет:

```dart
final class ProfileController extends Solo<Profile> with SoloListenable {
  // ...то же, что и выше...
}
```

Состояние он отдаёт как `value`, и `ValueListenableBuilder` принимает
контроллер как есть:

```dart
ValueListenableBuilder<Profile>(
  valueListenable: controller,
  builder: (context, state, _) => Text(switch (state) {
    Empty() => 'no profile',
    Loading() => 'loading',
    Loaded(:final name) => name,
  }),
),
```

`ListenableBuilder` и `AnimatedBuilder` принимают его так же,
а `Listenable.merge` объединяет его с другими listenable. Виджет над двумя
профилями перестраивается, когда меняется любой из них:

```dart
ListenableBuilder(
  listenable: Listenable.merge([left, right]),
  builder: (context, _) => Text(
    left.value.canSave && right.value.canSave ? 'both loaded' : 'waiting',
  ),
),
```

`SoloBuilder` по-прежнему принимает и его, как любой контроллер: с миксином,
без него или `with SoloStream`. От `ValueListenableBuilder` его отличает одно:
контроллеры он сравнивает по идентичности. Получив новый контроллер, который
равен старому по `==`, но не по `identical`, `SoloBuilder` переходит на него,
а `ValueListenableBuilder` продолжает слушать старый.

В позиции типа пишите аргумент типа явно, `SoloListenable<Profile>`: анализатор
пропускает голый `SoloListenable` как `SoloListenable<Object>`.

Разделы ниже о выборе значения и о подписке работают с контроллером, в который
миксин подмешан.

Контроллер, у которого есть и `stream`, и `SoloListenable`, экран на этом
стриме и базовый класс контроллеров без Flutter описаны на отдельной странице,
[«Миксины»](../../docs/ru/flutter_solo/mixins.md).

## Выбор одного значения

Виджету, которому нужно одно поле, незачем перестраиваться из-за остальных.
`SoloSelector` выбирает поле и перестраивается, только когда меняется оно само:

```dart
SoloSelector<Profile, bool>(
  solo: controller,
  selector: (state) => state.canSave,
  builder: (context, canSave, _) => ElevatedButton(
    onPressed: canSave ? controller.save : null,
    child: const Text('Save'),
  ),
),
```

Кнопка выбрасывает `Job`, которую вернул `save`, и делает это намеренно; так же
поступает и `SaveButton` ниже. Упавшее сохранение оставляет состояние `Loaded`,
и на экране об этом ничего нет. У `save` нет `ifFailed`, поэтому его провал
уходит в зону, раз `Solo.unansweredHandler` не задан, в приложении
к `PlatformDispatcher.onError`. `ignoreFailure()` оставил бы его неуслышанным.
Экран, который сообщает об этом пользователю, ждёт `save().done`, как в разделе
[«Исходы»](#исходы).

Правила `SoloSelector`:

- Выбранное значение считается изменившимся при `!=`, если на этот вопрос
  не отвечает сам `changed:`.
- Селектор вызывается один раз на каждое изменение состояния, поэтому держите
  его дешёвой выборкой, которая на одно и то же состояние отвечает одинаково.
- `solo` принимает любой контроллер, `ValueListenable` он или нет.

`changed:` получает два выбранных значения: последнее, которое виджет принял,
как `previous`, и новое. Обычно билдер `previous` уже получил, но не всегда.
Если до кадра пришли два изменения и первое принято, второе сравнивается с ним,
а билдер его ещё не видел. Поэтому то, на чём остановится экран, зависит только
от изменений, а не от того, как они легли на кадры.

Селектор и `changed:` можно писать замыканиями на месте, как селектор выше.
Такое замыкание на каждом построении родителя новое и может выбирать уже
другое. Поэтому виджет выбирает ещё раз и спрашивает `changed:` о результате.
Подписку он при этом не трогает. `changed:` по-прежнему сравнивает с последним
выбранным значением, которое виджет принял.

Там, где нужен именно listenable выбранного значения, ту же выборку делает
объект, проекция `SoloSelection`, и `State` держит её в поле:

```dart
class _SaveButtonState extends State<SaveButton> {
  late SoloSelection<Profile, bool> canSave = _select();

  SoloSelection<Profile, bool> _select() =>
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  void didUpdateWidget(SaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      canSave = _select();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: canSave,
    builder: (context, enabled, _) => ElevatedButton(
      onPressed: enabled ? widget.controller.save : null,
      child: const Text('Save'),
    ),
  );
}
```

Держите проекцию в поле, как `canSave` выше. Созданная внутри `build`, она
на каждом построении новая. Билдер под ней тогда отписывается от старой
и подписывается на новую, а каждая новая проекция начинается со своего выбора,
и выбор, с которым сравнивается изменение, на каждом построении начинается
заново.

Но инициализатор поля выполняется один раз и читает `widget.controller`, каким
тот был в этот момент. `State` при этом живёт дольше виджета: перестраиваясь,
родитель может передать ему новый `SaveButton` с другим контроллером. Без
`didUpdateWidget` кнопка и дальше брала бы разрешение у старого контроллера,
а её нажатие уходило бы в новый. От поля и от его `didUpdateWidget` избавляет
`SoloSelector`: виджету, который выбирает, не нужен `State`.

На источник проекция подписана, только пока у неё есть слушатели, и освобождать
её не нужно. Проекция безвредно переживает свой источник: `value` по-прежнему
читает последнее состояние закрытого контроллера.

Конструктор принимает `ValueListenable`: здесь это контроллер
с `SoloListenable`. Для контроллера без миксина ту же проекцию строит
`SoloSelection.from(controller, selector)`. Из `ValueListenable`, который
не контроллер, выбирают так же, проекцией `SoloSelection` под
`ValueListenableBuilder`: `SoloSelector` принимает только контроллер.

Селектор проекции работает внутри изменения, которое его вызвало, поэтому он
должен только выбирать: над контроллером с `SoloListenable` он не должен менять
состояние, запускать задачу или закрывать контроллер.

Пока кто-то слушает, проекция выбирает один раз на изменение, и слушатель
читает ту самую выборку, по которой решалось, уведомлять ли. Когда никто
не слушает, `value` выбирает каждый раз и ничего из выбранного не хранит.
Источник, который меняет своё значение на месте, сохраняет объект, поэтому
слушатель, которого источник зовёт раньше проекции, читает выборку, сделанную
до изменения. Контроллер `solo` с неизменяемым состоянием с этим
не сталкивается.

## Подписка без хранения колбэка

`State` хочет узнавать о каждом изменении и получать новое состояние, поэтому
слушает замыканием, которое это состояние читает.

### Первая попытка

```dart
// Первая попытка: dispose() ничего не снимает, слушатель остаётся.
@override
void initState() {
  super.initState();
  widget.controller.addListener(() => _onState(widget.controller.value));
}

@override
void dispose() {
  widget.controller.removeListener(() => _onState(widget.controller.value));
  super.dispose();
}
```

Замыкание в `dispose()` написано так же, как замыкание в `initState()`, но это
другой объект. `removeListener` нужно отдать тот самый колбэк, который взял
`addListener`; получив любой другой, он ничего не снимает и ничего не говорит.
Первое замыкание остаётся подписанным, и его зовут дальше, над `State`,
которого уже нет, пока контроллер не закроют.

### Метод вместо замыкания

```dart
void _onChange() => _onState(widget.controller.value);

@override
void initState() {
  super.initState();
  widget.controller.addListener(_onChange);
}

@override
void dispose() {
  widget.controller.removeListener(_onChange);
  super.dispose();
}
```

Метод можно назвать в обоих местах. `removeListener` сравнивает через `==`:
метод, названный дважды, равен сам себе, а замыкание, написанное дважды, нет.
Цена: свой метод на каждого слушателя и на каждый `addListener` свой
`removeListener`, который нельзя забыть в `dispose()`.

### Подписка, которая хранит колбэк

`listen` хранит колбэк сам и отдаёт `SoloSubscription`; `SoloSubscriptions`
отменяет группу таких разом:

```dart
import 'package:flutter_solo/listenable.dart';

final _listening = SoloSubscriptions();

@override
void initState() {
  super.initState();
  widget.controller
      .listen(() => _onState(widget.controller.value))
      .addTo(_listening);
  canSave.listen(() => _onCanSave(canSave.value)).addTo(_listening);
}

@override
void dispose() {
  _listening.cancel();
  super.dispose();
}
```

`listen` работает на любом `Listenable`: на контроллере с `SoloListenable`,
на проекции, на `ScrollController` самого фреймворка. Отмена подчиняется трём
правилам:

- Повторная отмена не делает ничего.
- Отменённая группа не хранит то, что ей передали, а сразу отменяет.
- Если один участник отказывается отпускать, остальные всё равно отменяются,
  а каждый отказ уходит в `FlutterError.reportError`.

Отмена группы не бросает никогда. Её место в `dispose()`, а исключение оттуда
лишает собственного `dispose()` элементы, которые стоят за ним в этом кадре,
вместе с их слушателями.

На что подписался `initState`, на том подписка и остаётся, когда виджету
передают другой контроллер. `State`, у которого источник может смениться,
в `didUpdateWidget` отменяет группу и берёт подписки заново, в новую группу:
отменённая отменила бы их сразу.

## Методы из второго импорта

`select` и `listen` приходят собственным импортом, рядом с тем, из которого
берётся всё остальное:

```dart
import 'package:flutter_solo/flutter_solo.dart';
import 'package:flutter_solo/listenable.dart';

final canSave = controller.select((state) => state.canSave);
final subscription = canSave.listen(() => _onCanSave(canSave.value));
```

Это расширения на `ValueListenable` и `Listenable` самого фреймворка, там же,
где стоят `select` и `listen` других пакетов. Два расширения с одинаковым
именем члена на одном типе делают двусмысленным каждое место вызова. Пакет,
который несёт их в любой файл, где его импортируют, ломал бы соседа, о котором
ничего не знает. Выбор делает импорт.

Без него пропадают методы, а то, что они делают, остаётся:

- `SoloSelection(controller, (state) => state.canSave)` даёт ту же самую
  проекцию;
- `SoloSelector` не требует и метода;
- `listen` делает за вас `addListener` с колбэком, который вы храните сами.

`SoloSubscription` и `SoloSubscriptions` приходят только со вторым импортом.
Свой контроллер с методом `select` его сохраняет, потому что расширение всегда
уступает члену класса.

## Жизнь контроллера

Контроллер за вас никто не закроет. Никакого `SoloProvider` нет: контроллер
остаётся обычным объектом и живёт там же, где остальные ваши объекты.

```dart
import 'dart:async';

class _ProfileScreenState extends State<ProfileScreen> {
  final controller = ProfileController(ProfileApi());

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProfileView(controller: controller);
}
```

`close()` отменяет всё, что стоит в очереди или выполняется. Выполняющееся тело
остановится на ближайшем обращении к контексту, поэтому уход с экрана и стоит
так дёшево; задача, созданная с `cancellable: false`, от отмены отказывается
и доходит до конца. Когда закрытие кончится, контроллер сбрасывает всех
слушателей и больше никого не уведомляет. До тех пор слушатели ещё слышат то,
что пишут закрываемые задачи: `ifCancelled` или тело задачи, отказавшейся
от отмены. Экран этого не ждёт: `SoloBuilder` отпускает контроллер
в собственном `dispose`. `close()` безопасен по обе стороны
от `super.dispose()`. Даже с `SoloListenable` контроллер не `ChangeNotifier`:
метод называется `close()`, а не `dispose()`, и возвращает future, которая
завершается, когда задача действительно остановилась.

Контроллер, общий для нескольких экранов, живёт там же, где остальные общие для
них объекты: в регистрации `get_it`, в `InheritedWidget` над этими экранами,
в скоупе [scopo](https://pub.dev/packages/scopo), в поле объекта приложения.
Там же он и закрывается, один раз.

Скоуп scopo может занять и место `State` из примера выше. `ScopeModel` создаёт
контроллер, когда скоуп монтируется, отдаёт его в `dispose`, когда скоуп уходит
из дерева, а поддерево достаёт контроллер через `ScopeModel.of`:

```dart
import 'dart:async';

import 'package:scopo/scopo.dart';

ScopeModel<ProfileController>(
  create: (context) => ProfileController(ProfileApi())..load(),
  dispose: (controller) => unawaited(controller.close()),
  builder: (context) => ProfileView(
    controller: ScopeModel.of<ProfileController>(context, listen: false),
  ),
),
```

Этот `dispose` синхронный, как у `State`, и закрытия никто не ждёт. Где ждать
должен асинхронный скоуп scopo над ним, положите контроллер в `AsyncDataScope`.
Он дожидается future, которую возвращает `disposeData`, а родительский
асинхронный скоуп scopo освобождается только после своих детей:

```dart
AsyncDataScope<ProfileController>(
  initData: (context, ctx) async {
    final controller = ProfileController(ProfileApi());
    final unregister = ctx.onDiscard(controller.close);
    await ctx.abandonable(() => controller.load().value);
    unregister(); // дальше его закрывает disposeData

    return controller;
  },
  disposeData: (controller) => controller.close(),
  progressBuilder: (context, _) => const CircularProgressIndicator(),
  errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
  builder: (context, controller) => ProfileView(controller: controller),
),
```

Скоуп готов, когда профиль загружен: до этого он показывает `progressBuilder`,
а провал загрузки показывает `errorBuilder`. Пока контроллер не возвращён, он
принадлежит только телу: скоуп отдаёт в `disposeData` лишь то значение, которое
получил. На двух других путях его закрывает `ctx.onDiscard`: при провале
загрузки и когда скоуп убирают посреди загрузки — тогда `ctx.abandonable` сразу
перестаёт ждать, а закрытие отменяет загрузку. Регистрацию снимают в момент
передачи, без ожидания между ней и возвратом.

То, что освобождает родитель, переживает задачи контроллера, включая
сохранение, которого контроллер дожидается через `ctx.join`. Под `ScopeModel`
родитель освобождает своё, пока сохранение ещё идёт. У обоих ожиданий есть
предел, `disposeScopeTimeout` у скоупа и `waitForChildrenTimeout` у его
родителя, по умолчанию три секунды. Когда он истёк, scopo сообщает об этом
и продолжает освобождение, как будто не ждал вовсе. `ScopeTimeout.none` снимает
предел для одного скоупа. Экран ниже по дереву достаёт контроллер через
`AsyncDataScope.of<ProfileController>(context, listen: false).data`.

## Исходы

Метод отдаёт свою `Job`, поэтому экран может дождаться конца работы, которую
он же и начал:

```dart
Future<void> _load() async {
  switch (await controller.load().done) {
    case Done(:final value):
      if (mounted) _toast('hello $value');
    case Failed(:final error):
      if (mounted) _toast('$error');
    case Cancelled():
      break; // ушли с экрана, и close() отменил Job
  }
}
```

`done` не бросает никогда. `value` отдаёт значение, перебрасывает ошибку
упавшей `Job` и бросает `Cancelled` отменённой. `mounted` после `await` и здесь
остаётся обычным правилом Flutter.

`Job`, на которую никто не смотрит, не молчит. `Failed`, который никто
не наблюдал, уходит в зону, создавшую `Job`, если `Job` не называет его ошибку
в `isExpectedError`. Поэтому у «запустил и забыл» две формы. `Job`, которая
называет свои ожидаемые ошибки, как `load` называет `ApiException`, больше
ничего не требует: вызов — это `controller.load()`, а баг всё равно доходит
до зоны. Вызов, которому исход не нужен вовсе, заканчивается
на `ignoreFailure()`: так он говорит, что исход никого не интересует, даже если
`Job` упала из-за бага.

По той же дороге идут ошибки, которых не несёт ни один исход, например провал
работы, которую тело отдало `ctx.unattended`. Контроллер, который переопределил
`onUnanswered`, или `Solo.unansweredHandler` отвечает за них вместо зоны,
а заодно и за `Failed`, который никто не наблюдал. Их таблица есть в разделе
[«Куда уходит каждая ошибка»](../../docs/ru/solo/errors.md#куда-уходит-каждая-ошибка)
страницы об ошибках `solo`. `SoloObserver` такой провал видит, но не забирает:
смотреть не значит отвечать.

В приложении на Flutter ошибка, которая дошла до зоны, идёт по зонам наружу:

1. Своя error-зона вокруг `runApp` увидит её первой.
2. Дальше она доходит до `PlatformDispatcher.instance.onError`, если он задан.
3. Если не задан или если колбэк вернул `false`, ошибку получает встраивающая
   сторона и по своему запасному пути её печатает.

Что будет потом, решает встраивающая сторона. Документация `onError` про
процесс ничего не обещает: после колбэка он может завершиться или перестать
отвечать. Обычная программа на Dart отличается одним: необработанная ошибка её
завершает, с кодом выхода 255. Это ответ самой VM, а не Flutter.

## Заметки

| Чей сбой | Куда уходит |
| --- | --- |
| Слушателя контроллера с `SoloListenable` | В `FlutterError.reportError`, как показывает раздел [«Базовый класс без Flutter»](../../docs/ru/flutter_solo/mixins.md#базовый-класс-без-flutter) страницы о миксинах. |
| Слушателя контроллера без него | В зону, как в разделе [«Куда уходит каждая ошибка»](../../docs/ru/solo/errors.md#куда-уходит-каждая-ошибка) страницы `solo` об ошибках: `SoloBuilder` и `SoloSelector` берут и такой контроллер, но `FlutterError.onError` о сбоях его слушателей не узнаёт. |
| Слушателя проекции | Через `FlutterError`, есть у контроллера `SoloListenable` или нет: о сбоях своих слушателей проекция сообщает сама. |
| Селектора проекции | Путём контроллера, по одной из двух строк выше: селектор работает внутри слушателя контроллера. |

| Вопрос | Ответ |
| --- | --- |
| Когда зовут слушателей? | Синхронно, в порядке подписки, на каждое изменение состояния. С `SoloListenable` `value` и `currentState` дают один и тот же объект. Стрима нет, пока не подмешан `SoloStream`: билдеры слушают сам контроллер. |
| Фильтруются ли равные состояния? | Нет. `emit` состояния, равного текущему, всё равно уведомляет: слушатели принадлежат движку, а движок ничего не сравнивает. Кадр может склеить несколько таких, а слушатель нет. Проекция фильтрует своё значение, а виджету обычно важно именно оно, как показывает раздел [«Выбор одного значения»](#выбор-одного-значения). |
| Несколько контроллеров на одном экране? | Каждый со своим билдером, как и ожидается. `Listenable.merge([a, b])` в `ListenableBuilder` закрывает случай, когда один виджет зависит от двух; ему нужны контроллеры с `SoloListenable`, как показывает раздел [«Контроллер как `ValueListenable`»](#контроллер-как-valuelistenable). |
| Можно ли присвоить `value`? | Сеттера нет. Состояние принадлежит задачам, а лицо `ValueNotifier` с сеттером его бы раздало. |
| Как тестировать экран? | На фейковых часах `testWidgets`: таймер, которого ждёт `Job`, например задержка фейкового API, срабатывает, только когда тест двигает часы. Три правила, которые отсюда следуют, приводит [«Тестирование»](../../docs/ru/flutter_solo/testing.md). |

## Версии

| Изменение | Выходит в |
| --- | --- |
| Исправление, которое не трогает публичный API | патч-выпуске, например `1.0.1` |
| Новый класс, член или необязательный параметр | минорном выпуске, например `1.1.0` |
| Удалённый или переименованный член, изменение сигнатуры или описанного в документации поведения | мажорном выпуске, например `2.0.0` |

С версии 1.0.0 `flutter_solo` следует семантическому версионированию:
ограничение `^1.0.0` принимает каждый минорный и патч-выпуск, и код, написанный
под 1.0.0, с ними продолжает работать, кроме случаев ниже. Публичный API — то,
что экспортируют `package:flutter_solo/flutter_solo.dart`
и `package:flutter_solo/listenable.dart`; текст сообщений об ошибках
и отладочного вывода в него не входит. Член, который уходит, сначала помечается
`@Deprecated` в минорном выпуске, с именем, которое брать вместо него,
и удаляется в следующем мажорном.

Минорный выпуск может добавить член в миксин, который вы подмешиваете, например
в `SoloListenable`, и одноимённый член в вашем коде после этого перестаёт
компилироваться. Он может добавить член и в интерфейс, который вы реализуете
ради мока, например в `JobContext` или `SoloContext`, и тогда перестаёт
компилироваться и фейк, который реализует его вручную, а не через
`noSuchMethod`. Список изменений такого выпуска называет члены, которые он
добавляет. Новое имя верхнего уровня может столкнуться с тем же именем,
импортированным из другого пакета, пока один из импортов не скроет его через
`hide`.

`flutter_solo` реэкспортирует `solo`, поэтому мажорный выпуск `solo` или
`async_job` выходит вместе с мажорным выпуском `flutter_solo`.

## solo

[solo](https://pub.dev/packages/solo) и есть сам контроллер: очередь и её
политики, рабочий тип задачи, `canStart` и `keepWhile`, дети, наблюдатели,
семья ожидания и остальное API. Этот пакет реэкспортирует всё это вместе
с `SoloStream`, чей broadcast-`stream` нужен тому, что не виджет. Если вы
пишете не виджеты, берите `solo`: он на чистом Dart.
