# flutter_solo

Управление состоянием для Flutter: последовательные задачи над одним
состоянием, монопольное владение им, кооперативная отмена и перерисовка через
`ValueListenable`.

Контроллер владеет состоянием и выполняет над ним задачи по одной. Подмешайте
в него `SoloListenable`, и он одновременно станет `ValueListenable` своего
состояния, поэтому вставляется прямо в `ValueListenableBuilder`,
`ListenableBuilder`, `AnimatedBuilder` и `Listenable.merge`.

На [сайте документации](https://docs.yet-another.dev/ru/flutter_solo/) лежат
эта страница и руководства пакетов под ней.

## Зачем

У экрана есть жизненный цикл, и у работы на нём тоже: загрузка, которую надо
бросить, когда пользователь ушёл; сохранение, которое нельзя разрезать пополам;
второе нажатие, которое не должно отправить второй запрос. `setState`
и `ChangeNotifier` дают, где держать состояние, и ничего не говорят про работу.
`Bloc` планирует работу и просит класс события на каждый вызов; `Cubit`
оставляет обычные методы и ничего не планирует.

Здесь метод остаётся методом и отдаёт хэндл:

```dart
final job = controller.load();

await job.cancel(); // возвращается, когда Job действительно остановилась
print(job.outcome); // Cancelled(manual)
```

За что держится движок:

- одна корневая задача контроллера за раз, в порядке очереди, поэтому две
  из них никогда не пишут одно и то же состояние;
- правила вместо флагов: задача объявляет, с какими состояниями работает и при
  каком условии живёт, и её отменяют, когда они перестают выполняться;
- отмена, о которой может попросить вызывающий и мимо которой тело не пройдёт,
  забыв проверку;
- исход у каждой задачи, `Done`, `Failed` или `Cancelled`: его экрану и надо
  показать.

Длинный разбор, одиннадцать сценариев, решённых сначала на bloc, а потом здесь,
лежит в [solo и bloc рядом](../../docs/ru/solo/vs-bloc.md).

Чего здесь нет: ни `SoloProvider`, ни кодогенерации, ни внедрения зависимостей,
ни персистентности, ни параллельных корневых задач. По одной задаче за раз
пакет работает намеренно: в этом его предмет, а не предел его движка.

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

Пакет существует ради миксина `SoloListenable`; `SoloBuilder`, `SoloSelector`
и `SoloSelection` идут вместе с ним, а второй импорт по соседству добавляет
`select` и `listen` методами, вместе с подписками, которые отдаёт `listen`.

## Как пользоваться

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

final class ProfileController extends Solo<Profile> with SoloListenable {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable, // второе нажатие вернёт первую Job
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.abandonable(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
        // Без них упавшая или отменённая загрузка оставляет состояние
        // на Loading: спиннер, и нажать на экране нечего.
        onError: (state, error, stackTrace) => Empty(),
        onCancel: (state, cancelled) => Empty(),
      );

  Job<void> save() => run<Loaded, void>(
        key: 'save',
        (ctx) => ctx.join(() => api.saveName(ctx.state.name)),
      );
}

class ProfileView extends StatelessWidget {
  final ProfileController controller;

  const ProfileView({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Profile>(
        valueListenable: controller,
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

`run<Profile, String>` говорит, что `Job` работает с состояниями `Profile`
и возвращает `String`; `save` сужает это до `Loaded`, поэтому такая `Job`
ни в каком другом состоянии не стартует, а кончается там `Cancelled`, и её тело
читает `Loaded` с `name` внутри. Внутри тела состояние записывает только
`ctx.emit`, `ctx.abandonable` ждёт так же, как `await`, но сдаётся в тот
момент, когда `Job` отменяют, а `ctx.join` дожидается своего вызова в любом
случае, так что сохранение не рвётся пополам. `onError` и `onCancel` ведут
назад: они говорят, в каком состоянии остаётся упавшая или отменённая загрузка,
а без них экран держал бы спиннер задачи, которой уже нет. Всё API целиком,
с правилами, очередью, детьми и наблюдателями, описано
в [solo](https://pub.dev/packages/solo).

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
)
```

Выбранное значение считается изменившимся при `!=`, если на этот вопрос
не отвечает сам `changed:`. Селектор вызывается один раз на каждое изменение
состояния, поэтому держите его дешёвой выборкой, которая на одно и то же
состояние отвечает одинаково. `solo` принимает любой контроллер,
`ValueListenable` он или нет. Селектор сравнивается по идентичности, когда
родитель перестраивается, поэтому замыкание, написанное на месте, на каждом
таком перестроении новое и каждый раз создаёт новую проекцию: один
`removeListener`, один `addListener` и одна выборка, а при собственном
`changed:` значение, с которым идёт сравнение, начинается заново. Где родитель
перестраивается часто, держите функцию в поле или в `static`.

За вас виджет держит `SoloSelection`, то есть `ValueListenable` выбранного
значения, и там, где нужен именно listenable, это обычный объект:

```dart
class _SaveButtonState extends State<SaveButton> {
  late SoloSelection<Profile, bool> canSave = _select();

  SoloSelection<Profile, bool> _select() =>
      SoloSelection(widget.controller, (state) => state.canSave);

  @override
  void didUpdateWidget(SaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
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
на каждом построении новая: билдер под ней отписывается от старой
и подписывается на новую, а значение, которым проекция придерживает
уведомления, каждый раз начинается заново. Только поле создаётся по первому
виджету, а родитель может передать `State` другой контроллер: без
`didUpdateWidget` кнопка и дальше брала бы разрешение у старого контроллера,
а её нажатие уходило бы в новый. Обе заботы идут с полем, от которого избавляет
`SoloSelector`. На источник проекция подписана, только пока у неё есть
слушатели, и освобождать её не нужно.

## Билдеры для любого контроллера

`ValueListenableBuilder` требует `ValueListenable`, и контроллер с подмешанным
`SoloListenable` под это требование подходит. Контроллер без него не подходит:
ни голый `Solo`, ни контроллер только `with SoloStream`. Для них `SoloBuilder`
принимает сам контроллер:

```dart
SoloBuilder<Profile>(
  solo: controller,
  builder: (context, state, _) => Text(
    switch (state) {
      Empty() => 'no profile',
      Loading() => 'loading',
      Loaded(:final name) => name,
    },
  ),
)
```

Он перестраивается на каждое изменение состояния и передаёт `child` нетронутым.
Кроме контроллера, который он принимает, от `ValueListenableBuilder` его
отличает одно: контроллеры он сравнивает по идентичности. Получив новый
контроллер, который по `==` равен старому, `SoloBuilder` переходит на него,
а `ValueListenableBuilder` продолжает слушать старый.

Чтобы выбрать одно значение из такого контроллера, ничего нового не нужно.
`SoloSelector` принимает любой контроллер,
а `SoloSelection.from(controller, selector)` даёт его проекцию без виджета
вокруг, для поля в `State`, когда контроллер не `ValueListenable`.

Контроллер, у которого есть и `stream`, и `SoloListenable`, экран на этом
стриме и базовый класс контроллеров без Flutter описаны на отдельной странице,
[«Миксины»](../../docs/ru/flutter_solo/mixins.md).

## Подписка без хранения колбэка

`State` хочет узнавать о каждом изменении и получать новое состояние, поэтому
слушает замыканием, которое это состояние читает.

### Первая попытка

```dart
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
которого уже нет, пока контроллер не закроют. Чтобы замыкание можно было
вернуть, ему понадобилось бы собственное поле.

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
на проекции, на `ScrollController` самого фреймворка. Повторная отмена
не делает ничего, а отменённая группа не хранит то, что ей передали, а сразу
отменяет. Если один участник отказывается отпускать, остальные всё равно
отменяются, а каждый отказ уходит в `FlutterError.reportError`. Отмена группы
не бросает никогда: её место в `dispose()`, а исключение оттуда лишает
собственного `dispose()` элементы, которые стоят за ним в этом кадре, вместе
с их слушателями.

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

Это расширения, и стоят они на `ValueListenable` и `Listenable` самого
фреймворка, там же, где стоят `select` и `listen` других пакетов. Два
расширения с одинаковым именем члена на одном типе делают двусмысленным каждое
место вызова, так что пакет, который несёт их в любой файл, где его
импортируют, ломал бы соседа, о котором ничего не знает. Выбор делает импорт.

Без него пропадают методы, а то, что они делают, остаётся:
`SoloSelection(controller, (state) => state.canSave)` даёт ту же самую
проекцию, `SoloSelector` не требует и метода, а `listen` делает за вас
`addListener` с колбэком, который вы храните сами. `SoloSubscription`
и `SoloSubscriptions` приходят только со вторым импортом. Оттого что это
расширения, свой контроллер с методом `select` его и сохраняет: расширение
всегда уступает члену класса.

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
    controller.load().ignore();
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

`close()` отменяет всё, что стоит в очереди или выполняется, причём
выполняющееся тело остановится на ближайшем обращении к контексту, поэтому уход
с экрана и стоит так дёшево. Ещё он сбрасывает всех слушателей и больше никого
не уведомляет. Он безопасен по обе стороны от `super.dispose()`.
`SoloListenable` не `ChangeNotifier`: метод называется `close()`,
а не `dispose()`, и возвращает future, которая завершается, когда задача
действительно остановилась.

Контроллер, общий для нескольких экранов, живёт там же, где остальные ваши
синглтоны: в регистрации `get_it`, в `InheritedWidget`, в поле объекта
приложения. Там же он и закрывается, один раз.

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

`done` не бросает никогда; `value` отдаёт значение, перебрасывает ошибку
упавшей `Job` и бросает `Cancelled` отменённой. `mounted` после `await`
остаётся обычным правилом Flutter и здесь. `Job`, на которую никто не смотрит,
не молчит: `Failed`, который никто не наблюдал, уходит в зону, создавшую `Job`,
поэтому «запустил и забыл» пишется `controller.load().ignore()`, где `ignore()`
и говорит, что исход никого не интересует. По той же дороге идут ошибки,
которых не несёт ни один исход, например провал работы, которую тело отдало
`ctx.unattended`, если только контроллер не переопределил `onUnanswered`
и не установлен `Solo.errorHandler`, который за них отвечает: список есть
в разделе [«Ответ за ошибку»](../../docs/ru/solo/errors.md#ответ-за-ошибку)
страницы об ошибках `solo`. `SoloObserver` такой провал видит, но не забирает:
смотреть не значит отвечать.

Что значит «в зону» в приложении на Flutter: ошибка идёт по зонам наружу, так
что своя error-зона вокруг `runApp` увидит её первой. Дальше она доходит
до `PlatformDispatcher.instance.onError`, если он задан. Если не задан или если
колбэк вернул `false`, ошибку получает встраивающая сторона и по своему
запасному пути её печатает. Что будет потом, решает встраивающая сторона:
документация `onError` про процесс ничего не обещает, после колбэка он может
завершиться или перестать отвечать. Обычная программа на Dart отличается одним:
необработанная ошибка её завершает, с кодом выхода 255, и это ответ самой VM,
а не Flutter.

## Тестирование

Тест виджета запускает загрузку и смотрит на экран, когда она закончилась.
`FakeApi` ниже принадлежит тесту: он отвечает именем через десять миллисекунд
после вызова. Обычный тест дождался бы `Job`.

### Первая попытка

```dart
await controller.load().done;
await tester.pump();
```

Дальше первой строки тест не идёт: он стоит на ней до своего таймаута,
по умолчанию десять минут. `testWidgets` работает на фейковых часах, и двигает
их внутри него только сам тест. Десять миллисекунд фейка сделаны таймером,
поэтому задача ждёт, пока тест сдвинет время, а тест ждёт задачу.

### Двигаем часы

```dart
testWidgets('the profile appears', (tester) async {
  final controller = ProfileController(FakeApi());
  await tester.pumpWidget(
    MaterialApp(home: ProfileView(controller: controller)),
  );

  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();

  expect(find.text('Ada Lovelace'), findsOneWidget);
  await controller.close();
});
```

`pumpAndSettle` прокачивает по кадру каждые сто миллисекунд, пока кто-то просит
следующий кадр. Первой сотни этому фейку хватает с запасом, но дождались бы
и более медленного, потому что спиннер состояния `Loading` всё время просит
кадры. Ждут здесь экран, а не задачу: когда ничего не анимируется,
`pumpAndSettle` останавливается через кадр или два, а загрузка, которой нужно
больше, так и ждёт.

Хэндл ждёт саму задачу:

```dart
final done = controller.load().done; // до того, как Job может кончиться
await tester.pump(const Duration(milliseconds: 20)); // двигаем часы
final outcome = await done;
```

`pump` с длительностью сдвигает часы, а потом рисует, поэтому оставленный им
кадр показывает последнее состояние. `done` читается в первой строке, до того
как часы сдвинулись, и порядок важен: о `Failed`, про который никто не спросил,
движок сообщает, когда `Job` кончается, и сообщает в зону, где её создали.
Здесь это зона теста, и она тут же проваливает тест, а `tester.takeException()`
после этого забирать нечего. Упавшая загрузка делает тест красным, хотя он
и читает `done`, если читает его после прокачки. `Job`, которую тест запускает
и бросает, говорит об этом через `ignore()`.

К фейковым часам относятся ещё две вещи. `pump()` без длительности решает,
рисовать ли, раньше, чем выполняет микротаску, с которой стартует `Job`: после
`controller.load()` и одного `pump()` состояние сдвинулось, а экран нет, если
только кадр не был запрошен заранее, как сразу после прокачки `MaterialApp`.
Рисует его второй `pump()`. И контроллер закрывается в теле теста,
а не в `addTearDown`: колбэк `addTearDown` выполняется, когда фейковые часы уже
остановились, и `close()`, которого там ждут при ещё идущей задаче,
не возвращается никогда, а для этого хватит проверки, упавшей посреди загрузки.
Тест стоит до своего таймаута, и следующий за ним тест падает вместе с ним.

`Job`, которой дали `timeout`, приносит свой таймер, и ядро держит его, пока
`Job` не кончится. Если такая `Job` ещё идёт, когда кончается тело
`testWidgets`, тест падает
с `A Timer is still pending even after the widget tree was disposed`, а та же
`Job` без срока тест не роняет. Контроллер, закрытый в теле, как выше, кончает
`Job` и забирает её таймер с собой.

## Заметки

| Вопрос | Ответ |
| --- | --- |
| Когда зовут слушателей? | Синхронно, в порядке подписки, на каждое изменение состояния. `value` и `currentState` дают один и тот же объект. Стрима нет, пока не подмешан ещё и `SoloStream`: виджет перестраивается по `value`. |
| Фильтруются ли равные состояния? | Нет. `emit` состояния, равного текущему, всё равно уведомляет: слушатели принадлежат движку, а движок ничего не сравнивает. Кадр может склеить несколько таких, а слушатель нет. Проекция фильтрует своё значение, а виджету обычно важно именно оно. |
| Несколько контроллеров на одном экране? | Работают как ожидается, каждый со своим билдером, а `Listenable.merge([a, b])` в `ListenableBuilder` закрывает случай, когда один виджет зависит от двух. |
| Можно ли присвоить `value`? | Сеттера нет. Состояние принадлежит задачам, а лицо `ValueNotifier` с сеттером его бы раздало. |

## solo

[solo](https://pub.dev/packages/solo) и есть сам контроллер: очередь и её
политики, рабочий тип задачи, `canStart` и `keepWhile`, дети, наблюдатели,
семья ожидания и остальное API, которое этот пакет реэкспортирует целиком,
вместе с `SoloStream`, чей broadcast-`stream` нужен тому, что не виджет. Если
вы пишете не виджеты, берите его: он на чистом Dart.
