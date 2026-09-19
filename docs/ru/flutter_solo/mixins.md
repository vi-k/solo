# Миксины

`SoloListenable` — единственный миксин, который нужен
[README](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/README.ru.md):
он делает контроллер `ValueListenable`, а дальше его берут билдеры фреймворка.
Эта страница — о том, что стоит вокруг него: `SoloStream` рядом с ним, экран
на этом стриме и базовый класс контроллеров, в котором нет Flutter, чтобы его
подмешать.

## Контроллер с обеими доставками

`SoloListenable` комбинируется с `SoloStream`, когда экрану нужны сразу
виджетная сторона и broadcast-`stream`:

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
`stream` приходит тактом позже. У комбинации есть цена: ошибка слушателя идёт
в `FlutterError`, ошибка подписчика стрима — в зону, то есть у одного изменения
два маршрута ошибок; перестроение и событие стрима — два отдельных отклика
на одно изменение там, где виджет, читающий только `value`, получал один;
и `await close()` теперь ждёт ещё и подписчиков стрима, чего у чистого
`SoloListenable` не было.

## Экран на стриме

Требование обычное: с первого же кадра экран показывает состояние, в котором
контроллер находится. У `Session` выше есть `stream`, а у фреймворка есть
виджет, который стрим принимает.

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

Экран встречает это каждый раз, когда строится заново — переход туда и обратно,
вкладка, с которой ушли и на которую вернулись, — и ждать приходится
до следующего изменения, а для сессии это может быть остаток дня. Закрытие
уносит состояние совсем: после `close()` стрим завершён, и события уже не будет
никогда.

```text
mounted over a session signed in as Ada: nothing yet
after close(): nothing yet
```

### Состояние, которое нужно экрану, — это `currentState`

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

```text
mounted over a session signed in as Ada: signed in as Ada
after Bob signs in: signed in as Bob
```

`snapshot.data` и `currentState` отличаются тем, откуда они берутся.
`snapshot.data` — это то, что стрим доставил этому подписчику; `currentState` —
состояние, в котором контроллер находится сейчас, а `initialData` — то, что
отдаёт подписчику это состояние в момент подписки.

Билдер этого пакета принимает контроллер, а не доставку, поэтому разрыв
не открывается и передавать на первый кадр нечего:

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
```

Ветки `null` у состояния теперь нет: у контроллера состояние есть всегда.
`stream` — для того, что виджетом не является: журнал, мост в код, который
принимает `Stream`, тест, которому нужна вся последовательность изменений.

## Базовый класс без Flutter

Общий базовый класс контроллеров приложения может жить в пакете без Flutter,
а лист подмешивает `SoloListenable`:

```dart
// Свой пакет, без Flutter.
abstract class AppController<S extends Object> extends Solo<S> {
  AppController(super.initialState);

  // ...то, что общее у всех контроллеров приложения...
}

// Приложение.
final class ProfileController extends AppController<Profile>
    with SoloListenable {
  ProfileController() : super(Empty());
}
```

Где стоит миксин, решает, чей `onListenerError` сообщит об ошибке слушателя.
На листе, как здесь, он перекрывает базу: база, переопределившая
`onListenerError`, уступает отчёту миксина через `FlutterError`, и через
`super` лист до версии базы тоже не дотянется — `super` приходит в миксин.
База, которой нужен свой отчёт, держит его в методе под другим именем, а лист
зовёт этот метод из своего `onListenerError`. База, которая сама подмешивает
`SoloListenable`, сохраняет своё переопределение: класс стоит над миксинами,
которые подмешивает. Только подмешивайте его один раз — в базу или в лист:
подмешанный ещё раз на листе над такой базой, он встаёт над её переопределением
и так же его глушит.
