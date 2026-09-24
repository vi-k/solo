# Миксины

`SoloListenable` делает контроллер `ValueListenable`, а значит, и `Listenable`:
`ValueListenableBuilder`, `ListenableBuilder` и `AnimatedBuilder` фреймворка
принимают контроллер как есть,
и [README](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md)
строит свой экран на первом из них. Билдеры этого пакета, `SoloBuilder`
и `SoloSelector`, принимают любой контроллер, с миксином и без. Эта страница —
о том, что стоит вокруг `SoloListenable`: `SoloStream` из `solo` рядом с ним,
экран на этом стриме и базовый класс контроллеров в пакете без Flutter, куда
`SoloListenable` не подмешать.

Строки под кодом — то, что он печатает при запуске. Два раздела открываются
версией, к которой ведёт словарь фреймворка и движка, — виджетом, который
принимает стрим, и хуком, названным по ошибке, о которой он сообщает, —
и показывают, что этот код делает. Если версия, которая это чинит, всё ещё
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

Обе доставки живут, каждая на своём такте: слушатель
за `ValueListenableBuilder` срабатывает синхронно, внутри изменения, а событие
`stream` приходит тактом позже. Комбинация стоит двух вещей. У одного изменения
два маршрута ошибок: ошибка слушателя идёт в `FlutterError`, а ошибка
подписчика `stream` — в зону, в которой он подписался. И `await close()` ждёт,
пока каждый подписчик `stream` не получит событие завершения, чего чистый
`SoloListenable` не делает: `await for` по `session.stream` держит `close()`,
пока его тело ещё чего-то ждёт.

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
постройки. Сессия тут ни при чём: `currentState` держит `SignedIn` всё это
время — в том же билдере, который рисует `nothing yet`.

Экран встречает это каждый раз, когда строится заново, — когда его маршрут
открыли, когда с вкладки ушли и на неё вернулись, — и ждать приходится
до следующего изменения, а для сессии это может быть остаток дня. Закрытие
уносит состояние совсем: после `close()` стрим завершён, и события уже не будет
никогда.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### Вторая попытка

`initialData` даёт билдеру состояние, с которого начать, а состояние, в котором
сессия находится, — это `currentState`:

```dart
StreamBuilder<SessionState>(
  stream: session.stream,
  initialData: session.currentState,
  builder: (context, snapshot) => Text(
    switch (snapshot.data) {
      SignedIn(:final name) => 'signed in as $name',
      SignedOut() => 'signed out',
      null => 'nothing yet',
    },
  ),
)
```

`snapshot.data` и `currentState` отличаются тем, откуда они берутся.
`snapshot.data` — это то, что стрим доставил этому подписчику; `currentState` —
состояние, в котором контроллер находится сейчас, а `initialData` — то, что
отдаёт подписчику это состояние в момент подписки. Изъян виден, когда бейджу
дают другую сессию:

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
handed another session, signed in as Cy: signed in as Bob
```

`StreamBuilder` читает `initialData` один раз, при первой постройке. Получив
новый стрим, он подписывается на него и оставляет данные, которые доставил
старый, поэтому бейдж показывает Боба поверх сессии Сая, пока та не изменится.

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
кадра и с того кадра, в котором ему дали другую. Ветки `null` у состояния
теперь нет: у контроллера состояние есть всегда. `stream` — для того, что
виджетом не является: журнал, мост в код, который принимает `Stream`, тест,
которому нужна вся последовательность изменений.

## Базовый класс без Flutter

Общий базовый класс контроллеров приложения может жить в пакете без Flutter,
а лист подмешивает `SoloListenable`. В базу идёт то, что общее у всех
контроллеров, и здесь это сообщение об ошибке слушателя в собственный журнал
приложения, `AppLog`.

### Первая попытка

У движка есть хук для этой ошибки, и база его переопределяет:

```dart
// Свой пакет, без Flutter.
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
слушателя. Миксин стоит над классом, в который его подмешали, здесь — над
`AppController`, поэтому побеждает его переопределение с отчётом через
`FlutterError`, а переопределение базы не вызывается вовсе. Анализатор об этом
молчит. Через `super` лист до базы тоже не дотянется: `super` там — миксин,
а переопределение, которое только его и зовёт, анализатор называет лишним.

### Отчёт под другим именем

База держит свой отчёт в методе под другим именем, которого не переопределяет
ни один миксин, и её собственный хук зовёт его:

```dart
// Свой пакет, без Flutter.
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
отправляет его ошибки туда же. Лист, которому нужен ещё и отчёт через
`FlutterError`, зовёт `super.onListenerError` рядом с `reportListenerError`.
`@protected` повторён на каждом переопределении, потому что Dart его
не наследует: без него хук становится публичным членом каждого контроллера
приложения.

База, в которой Flutter есть, подмешивает `SoloListenable` сама и сохраняет
своё переопределение: класс стоит над миксинами, которые подмешивает. Только
подмешивайте его один раз: подмешанный ещё раз на листе над такой базой, он
встаёт над её переопределением и так же его глушит.
