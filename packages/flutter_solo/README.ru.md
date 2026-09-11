# flutter_solo

Управление состоянием для Flutter: последовательные задачи над одним
состоянием, монопольное владение им, кооперативная отмена и перерисовка
через `ValueListenable`.

`SoloListenable<S>` — контроллер, который владеет состоянием и гоняет по
нему задачи по одной за раз, и одновременно он `ValueListenable<S>`,
поэтому вставляется прямо в `ValueListenableBuilder`, `ListenableBuilder`,
`AnimatedBuilder` и `Listenable.merge`.

## Зачем

У экрана есть жизненный цикл, и у работы на нём тоже: загрузка, которую
надо бросить, когда пользователь ушёл; сохранение, которое нельзя разрезать
пополам; второе нажатие, которое не должно отправить второй запрос.
`setState` и `ChangeNotifier` дают, где держать состояние, и ничего не
говорят про работу; bloc даёт работу и просит класс события на каждый
вызов.

Здесь метод остаётся методом и отдаёт хэндл:

```dart
final job = profile.load();

await job.cancel();  // возвращается, когда задача действительно встала
print(job.outcome);  // Cancelled(manual)
```

За что держится движок:

- одна корневая задача контроллера за раз, в порядке очереди, — значит,
  две из них никогда не пишут одно и то же состояние;
- правила вместо флагов: задача объявляет, с какими состояниями работает и
  при каком условии живёт, и её отменяют, когда условие перестало
  выполняться;
- отмена, о которой может попросить вызывающий и мимо которой тело не
  пройдёт, забыв проверку;
- исход у каждой задачи — `Done`, `Failed` или `Cancelled`, — а именно его
  экрану и надо показать.

Длинный разбор, десять сценариев, решённых сначала на bloc, а потом здесь,
— в [solo и bloc, бок о бок](https://github.com/vi-k/solo/blob/main/packages/solo/doc/vs-bloc.md).

Чего здесь нет: ни `SoloProvider`, ни кодогенерации, ни внедрения
зависимостей, ни персистентности, ни параллельных корневых задач — одна за
раз это предмет пакета, а не предел его движка.

## Установка

```sh
flutter pub add flutter_solo
```

Одной зависимости достаточно: `flutter_solo` реэкспортирует целиком
[solo](https://pub.dev/packages/solo), а тот — целиком
[async_job](https://pub.dev/packages/async_job). `Solo`, `SoloContext`, `Job`,
`Outcome`, `Policy` и `ValueListenable` приходят вместе с

```dart
import 'package:flutter_solo/flutter_solo.dart';
```

а `SoloListenable` — единственный класс, который этот пакет добавляет
сверху.

## Как пользоваться

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class Profile {}

final class Empty extends Profile {}

final class Loading extends Profile {}

final class Loaded extends Profile {
  final String name;

  Loaded(this.name);
}

final class ProfileController extends SoloListenable<Profile> {
  final ProfileApi api;

  ProfileController(this.api) : super(Empty());

  Job<String> load() => run<Profile, String>(
        key: 'load',
        policy: Policy.droppable, // второе нажатие вернёт первую задачу
        (ctx) async {
          ctx.emit(Loading());
          final name = await ctx.wait(api.fetchName);
          ctx.emit(Loaded(name));

          return name;
        },
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

`run<Profile, String>` говорит, что задача работает с состояниями `Profile`
и возвращает `String`; внутри тела `ctx.emit` — единственный способ
записать состояние, а `ctx.wait` ждёт так же, как `await`, но сдаётся в тот
момент, когда задачу отменяют. Всё API целиком — правила, очередь, дети,
наблюдатели — описано в [solo](https://pub.dev/packages/solo).

## Выбор одного значения

Виджету, которому нужно одно поле, незачем перестраиваться из-за
остальных. `select` отдаёт `ValueListenable` одного этого поля и
уведомляет только тогда, когда меняется само поле:

```dart
class _SaveButtonState extends State<SaveButton> {
  late final canSave = widget.controller.select((state) => state.canSave);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: canSave,
        builder: (context, canSave, _) => ElevatedButton(
          onPressed: canSave ? widget.controller.save : null,
          child: const Text('Save'),
        ),
      );
}
```

Держите проекцию в поле, как `canSave` выше: созданная внутри `build`
подписывалась бы и отписывалась каждый кадр — и селектор, написанный там
же по месту, тоже. Выборка считается изменившейся при `!=`, если на этот
вопрос не отвечает сам `compare:` — `true` значит изменилась. На источник
проекция подписана, только пока у неё есть слушатели, и освобождать её не
нужно. `value` читает состояние каждый раз, поэтому никогда не отстаёт —
держите селектор дешёвой выборкой.

`select` — расширение, поэтому свой контроллер с методом `select` его
сохраняет: побеждает ваш, а проекция тогда строится напрямую,
`SoloSelection(controller, (state) => state.canSave)`.

## Подписка без хранения колбэка

`addListener` требует вернуть тот же самый колбэк, поэтому замыканию
нужно собственное поле, где жить. `listen` хранит его сам и отдаёт
`SoloSubscription`; `SoloSubscriptions` снимает группу таких разом:

```dart
final _listening = SoloSubscriptions();

@override
void initState() {
  super.initState();
  widget.controller.listen(_onState).addTo(_listening);
  canSave.listen(_onCanSave).addTo(_listening);
}

@override
void dispose() {
  _listening.cancel();
  super.dispose();
}
```

`listen` работает и на контроллере, и на проекции. Повторная отмена не
делает ничего, а отменённая группа не хранит то, что ей передали, а
сразу отменяет. Если один участник отказывается отпускать, остальные всё
равно отменяются: первая ошибка бросается по окончании прохода,
остальные уходят в отчёт.

## Жизнь контроллера

Контроллер за вас никто не закроет. `SoloProvider`'а нет: контроллер — это
объект, и живёт он там же, где остальные ваши объекты.

```dart
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

`close()` отменяет то, что выполняется, — тело встанет на ближайшем
обращении к контексту, поэтому уход с экрана и стоит так дёшево, — сбрасывает
всех слушателей и больше никого не уведомляет. Он безопасен по обе стороны
от `super.dispose()`. `SoloListenable` — не `ChangeNotifier`: метод
называется `close()`, а не `dispose()`, и возвращает `Future`, который
завершается, когда задача действительно остановилась.

Контроллер, общий для нескольких экранов, живёт там же, где остальные ваши
синглтоны — регистрация в `get_it`, `InheritedWidget`, поле объекта
приложения, — и закрывается там же, один раз.

## Исходы

Задача отдаёт хэндл, поэтому экран может дождаться конца работы, которую он
же и начал:

```dart
Future<void> _load() async {
  switch (await controller.load().done) {
    case Done(:final value):
      if (mounted) _toast('hello $value');
    case Failed(:final error):
      if (mounted) _toast('$error');
    case Cancelled():
      break; // ушли с экрана или нажали второй раз, пока шла первая
  }
}
```

`done` не бросает никогда; `value` отдаёт значение и перебрасывает ошибку.
`mounted` после `await` — обычное правило Flutter, и здесь оно тоже
действует. Задача, на которую никто не смотрит, не молчит: неотслеженный
`Failed` уходит в зону, создавшую задачу, поэтому «запустил и забыл» — это
`controller.load().ignore()`, где `ignore()` и говорит, что исход никого не
интересует. По той же дороге идёт провал работы, отданной
`ctx.unattended`, если его не взял ни `onError`, ни `SoloObserver`.

Что значит «в зону» во Flutter: ошибка идёт по зонам наружу, так что своя
error-зона вокруг `runApp` увидит её первой; дальше она доходит до
`PlatformDispatcher.instance.onError`, если он задан, и до лога движка,
если нет. Что будет потом — дело этого колбэка и встраивающей стороны:
фреймворк не обещает, что работа продолжится, а
`PlatformDispatcher.onError` может и завершить процесс. Чего тут точно
нет, так это `EXIT=255` обычной программы на Dart: это ответ самой VM на
необработанную ошибку, а не Flutter.

## Тестирование

`testWidgets` работает на фальшивых часах: задача, ждущая таймера, так и
будет ждать, пока тест сам не сдвинет время, а кадр всегда отстаёт от
состояния на один. `pumpAndSettle` делает и то и другое — гоняет часы до
тишины и перерисовывает:

```dart
testWidgets('the profile appears', (tester) async {
  final controller = ProfileController(FakeApi());
  addTearDown(controller.close);
  await tester.pumpWidget(
    MaterialApp(home: ProfileView(controller: controller)),
  );

  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();

  expect(find.text('Ada Lovelace'), findsOneWidget);
});
```

Хэндл — точная версия того же самого, для теста, которому надо знать, что
задача кончилась, а не что экран затих:

```dart
final job = controller.load();
await tester.pump(const Duration(milliseconds: 20)); // сдвигаем часы
await job.done;
await tester.pump(); // кадр, показывающий последнее состояние
```

Один только `await job.done` — это дедлок, если работа ждёт таймера: часы
внутри `testWidgets` двигает только сам тест. Не работает и «запустить
задачу и один раз прокачать» — состояние сдвигается микротаской после этой
прокачки, и увидит ли его проверка, зависит от того, сколько стояло в
очереди.

## Заметки

- Слушателей зовут синхронно, в порядке подписки, на каждое изменение
  состояния. `stream` у `Solo` продолжает работать и приходит микротаской
  позже; `value` и `state` — один и тот же объект.
- Равные состояния не фильтруются: `emit` состояния, равного текущему, всё
  равно уведомляет — так же, как у `Solo`. Кадр может склеить несколько
  таких, слушатель — нет. `select` фильтрует своё значение, а виджету
  обычно важно именно оно.
- Несколько контроллеров на одном экране работают как ожидается, каждый со
  своим билдером, а `Listenable.merge([a, b])` в `ListenableBuilder`
  закрывает случай, когда один виджет зависит от двух.
- Сеттера у `value` нет. Состояние принадлежит задачам, а лицо
  `ValueNotifier` с сеттером его бы раздало.

## solo

[solo](https://pub.dev/packages/solo) — это сам контроллер: очередь и её
политики, рабочий тип задачи, `canStart` и `keepWhile`, дети, наблюдатели,
семья ожидания и остальное API, которое этот пакет наследует целиком. Если
вы пишете не виджеты, берите его — он на чистом Dart.
