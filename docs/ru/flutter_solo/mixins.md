# Миксины

`SoloListenable` делает контроллер `ValueListenable`, а значит, и `Listenable`:
`ValueListenableBuilder`, `ListenableBuilder` и `AnimatedBuilder` фреймворка
принимают контроллер как есть, а экран из раздела
[«Как пользоваться»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#как-пользоваться)
README пакета построен на первом из них. Билдеры этого пакета, `SoloBuilder`
и `SoloSelector`, принимают любой контроллер, с миксином и без. Эта страница
о том, что стоит вокруг `SoloListenable`: `SoloStream` из `solo` рядом с ним,
экран на этом стриме и базовый класс контроллеров в пакете без Flutter, куда
`SoloListenable` не подмешать.

Строки под блоком кода показывают, что даёт его запуск: текст на экране после
каждого шага или место, куда ушло сообщение об ошибке слушателя. Два раздела
открываются версией, к которой ведёт словарь фреймворка и движка: виджетом,
который принимает стрим, и хуком, названным по ошибке, о которой он сообщает.
Оба показывают, что этот код делает. Если версия, которая это чинит, всё ещё
ошибается, она стоит второй попыткой, а версия, которой стоит пользоваться,
идёт под своим заголовком. В разделе об обеих доставках ошибаться не на чем,
и он открывается ответом.

## Контроллер с обеими доставками

`SoloListenable` комбинируется с `SoloStream`, когда контроллер, который кормит
виджеты, ещё и отдаёт broadcast-`stream` коду, который его принимает:

```dart
sealed class SessionState {
  const SessionState();
}

final class SignedOut extends SessionState {
  const SignedOut();
}

final class SignedIn extends SessionState {
  final String name;

  const SignedIn(this.name);
}

final class Session extends Solo<SessionState> with SoloStream, SoloListenable {
  Session(super.initialState);

  Job<void> signIn(String name) =>
      run<SessionState, void>((ctx) async => ctx.emit(SignedIn(name)));
}
```

Обе доставки работают, каждая по своему расписанию: слушатель
за `ValueListenableBuilder` срабатывает синхронно, внутри изменения, а событие
`stream` приходит микротаской позже. Порядок двух миксинов ничего не меняет:
ни один не переопределяет того, что переопределяет другой.

Комбинация стоит двух вещей. У одного изменения два маршрута ошибок: ошибка
слушателя идёт в `FlutterError`, а ошибка подписчика `stream` идёт в зону,
в которой он подписался. И `await close()` ждёт, пока каждый подписчик `stream`
не получит событие завершения, тогда как контроллер с одним `SoloListenable`
не ждёт никого из своих слушателей: `await for` по `stream` держит `close()`,
пока его тело ещё чего-то ждёт. Всё это время `pending` равен
`SoloPendingStream`, а как его спросить, показывает раздел
[«Что удерживает контроллер»](../solo/errors.md#что-удерживает-контроллер)
страницы об ошибках `solo`.

## Экран на стриме

Требование обычное: бейдж показывает состояние той сессии, которую ему дали,
с первого же кадра. У `Session` выше есть `stream`, а у фреймворка есть виджет,
который стрим принимает.

### Первая попытка

```dart
class SessionBadge extends StatelessWidget {
  final Session session;

  const SessionBadge(this.session, {super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<SessionState>(
        stream: session.stream,
        builder: (context, snapshot) => Text(
          switch (snapshot.data) {
            SignedIn(:final name) => 'signed in as $name',
            SignedOut() => 'signed out',
            null => 'nothing yet',
          },
        ),
      );
}
```

Ветка `null` написана потому, что она есть у типа, и с неё экран открывается:

```text
mounted over a session signed in as Ada: nothing yet
after Bob signs in: signed in as Bob
```

Broadcast-стрим ничего не повторяет. Подписчик слышит изменения, пришедшие
после подписки, а состояние, в котором контроллер уже был, к ним не относится,
поэтому бейдж ждёт изменения, чтобы показать то, что было верно ещё до его
постройки. Состояние всё это время на месте: `currentState` держит `SignedIn`
в том же билдере, который рисует `nothing yet`.

Экран встречает это каждый раз, когда строится заново: когда его маршрут
открыли, когда с вкладки ушли и на неё вернулись. Ждать приходится
до следующего изменения, а для сессии это может быть остаток дня. Закрытие
делает ожидание бесконечным: после `close()` стрим завершён, и события уже
не будет никогда, а `currentState` по-прежнему держит состояние, которого бейдж
так и не показал.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### Вторая попытка

`initialData` даёт билдеру состояние, с которого начать, а состояние, в котором
сессия находится сейчас, отдаёт `currentState`:

```dart
StreamBuilder<SessionState>(
  stream: session.stream,
  initialData: session.currentState,
  builder: (context, snapshot) => Text(
    switch (snapshot.requireData) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
    },
  ),
)
```

Данные снимка и `currentState` отличаются тем, откуда они берутся. Данные
снимка стрим доставил этому подписчику, а пока он ничего не доставил, это
`initialData`; `currentState` хранит состояние, в котором контроллер находится
сейчас. `initialData` отдаёт подписчику это состояние в момент подписки,
поэтому данные у снимка есть с первого кадра, и `requireData` читает их без
ветки `null`. Изъян виден, когда бейджу дают другую сессию:

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
handed another session, signed in as Cy: signed in as Bob
```

`StreamBuilder` читает `initialData` один раз, при первой постройке. Получив
новый стрим, он подписывается на него и оставляет данные, которые доставил
старый, поэтому бейдж показывает Боба поверх сессии Сая, пока та не изменится.
Если рядом с `initialData` стоит `key: ObjectKey(session)`, `StreamBuilder` для
другой сессии строится заново и читает `initialData` ещё раз, и бейдж сразу
показывает Сая: два аргумента, которые несёт каждый виджет на стриме.

### Билдер, который принимает контроллер

Билдер этого пакета принимает контроллер, а не доставку, поэтому передавать
на первый кадр нечего:

```dart
SoloBuilder<SessionState>(
  solo: session,
  builder: (context, state, _) => Text(
    switch (state) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
    },
  ),
)
```

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
handed another session, signed in as Cy: signed in as Cy
```

`SoloBuilder` читает `currentState` в `build` и переходит на контроллер,
который ему дали, поэтому бейдж показывает состояние своей сессии с первого
кадра и с того кадра, в котором ему дали другую. То же делает
`ValueListenableBuilder`, которому `Session` годится, потому что подмешивает
`SoloListenable`: с `valueListenable: session` он показывает те же три строки.
`stream` нужен не виджетам: журналу, мосту в код, который принимает `Stream`,
тесту, которому нужна вся последовательность изменений.

## Базовый класс без Flutter

Общий базовый класс контроллеров приложения может жить в пакете без Flutter:
пакет зависит от `solo`, а `SoloListenable` подмешивает лист, контроллер
приложения. В базу идёт то, что общее у всех контроллеров, и здесь это
сообщение об ошибке слушателя в собственный журнал приложения, `AppLog`.
`Profile` и `Empty` в коде ниже взяты из раздела
[«Как пользоваться»](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md#как-пользоваться)
README пакета: там объявлены его состояния.

### Первая попытка

У движка есть хук для этой ошибки, и база его переопределяет:

```dart
// Свой пакет, без Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);
}

// Приложение.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());
}
```

Слушатель `ProfileController` бросает, и сообщение проходит мимо базы:

```text
AppLog: nothing
FlutterError: Bad state: the listener blew up
```

От того, где стоит миксин, зависит, чей `onListenerError` сообщит об ошибке
слушателя. Миксин стоит над классом, написанным перед `with`, здесь над
`AppController`, поэтому побеждает его переопределение с отчётом через
`FlutterError`, а переопределение базы не вызывается вовсе. Анализатор об этом
молчит. Через `super` лист до базы тоже не дотянется: `super` там ведёт
в миксин, а переопределение, которое только его и зовёт, анализатор называет
лишним.

### Отчёт под другим именем

База держит свой отчёт в методе под другим именем, которого не переопределяет
ни один миксин, и её собственный хук зовёт его:

```dart
// Свой пакет, без Flutter.
import 'package:meta/meta.dart';
import 'package:solo/solo.dart';

abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  @protected
  void reportListenerError(Object error, StackTrace stackTrace) =>
      AppLog.error(error, stackTrace);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}

// Приложение.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}
```

```text
AppLog: Bad state: the listener blew up
FlutterError: nothing
```

Хук базы сообщает за контроллер, который ничего не подмешивает, а хук листа
отправляет туда же ошибки слушателей листа. Лист, которому нужен ещё и отчёт
через `FlutterError`, зовёт `super.onListenerError` рядом
с `reportListenerError`. `@protected` повторён на каждом переопределении,
потому что Dart его не наследует: без него хук становится публичным членом
этого класса и каждого класса, который наследует такое переопределение.
Аннотация лежит в `package:meta`, а его не экспортируют ни `solo`, ни этот
пакет: пакет без Flutter ради неё зависит от `meta`, а в приложении её
экспортирует `package:flutter/foundation.dart`.

Это переопределение пишет сам лист, и лист, который подмешал `SoloListenable`
без него, сообщает через `FlutterError`, как в первой попытке, при таком же
молчании анализатора. Приложение с несколькими контроллерами пишет его один
раз, в собственном классе между базой и листьями:

```dart
// Приложение.
abstract class ListenableController<S extends Object> extends AppController<S>
    with SoloListenable {
  ListenableController(super.initialState);

  @protected
  @override
  void onListenerError(Object error, StackTrace stackTrace) =>
      reportListenerError(error, stackTrace);
}

final class ProfileController extends ListenableController<Profile> {
  ProfileController() : super(Empty());
}
```

Класс стоит над миксинами, которые подмешивает, поэтому срабатывает
переопределение `ListenableController`, и так у каждого листа, который от него
наследуется: `ProfileController` здесь сообщает в `AppLog`, а не через
`FlutterError`. База, в которой Flutter есть, так же подмешивает
`SoloListenable` сама и сохраняет своё переопределение. Только подмешивайте его
один раз: подмешанный ещё раз на листе над таким классом, он встаёт над этим
переопределением и глушит его, как в первой попытке.
