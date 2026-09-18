# Flutter

Подмешайте в контроллер `SoloListenable` из `flutter_solo`. Он делает `Solo<S>`
ещё и `ValueListenable<S>` и стрима не добавляет — виджет перестраивается
по `value`, а результат операции ждут через её `Job`. Контроллер профиля
сохраняет те же состояния и метод `load`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends Solo<ProfileState> with SoloListenable {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...задачи из быстрого старта...
}
```

Экран может владеть контроллером: создайте его в `initState` и закройте
в `dispose`. Общий контроллер может находиться в существующем контейнере
зависимостей: `provider`, `get_it` или `InheritedWidget`. За закрытие отвечает
владеющий им код; `flutter_solo` не предоставляет `SoloProvider` и не закрывает
контроллеры автоматически.

`ValueListenableBuilder` перестраивается при изменении состояния. Чтобы перейти
на другой экран или показать сообщение после конкретной операции, дождитесь
исхода её `Job` в месте вызова. После ожидания проверьте `mounted`, прежде чем
обращаться к контексту виджета. Здесь `ProfilePage` является экраном назначения
в приложении:

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
          child: ValueListenableBuilder<ProfileState>(
            valueListenable: profile,
            builder: (context, state, _) => state is Loading
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

`value` и `currentState` ссылаются на один объект. Сеттера значения нет; `Job`
контроллера выполняют обновления через контекст. `ListenableBuilder`
и `AnimatedBuilder` также принимают контроллер, когда самому билдеру значение
состояния не нужно.

Контроллеру, который не является `ValueListenable`, — собственному наследнику
`Solo` или контроллеру `with SoloStream` — достаётся `SoloBuilder`: он
принимает любой `Solo` и строит то же поддерево из того же состояния.
Отличаются две вещи, и обе про то, откуда это состояние берётся. Он читает
`currentState` в `build`, тогда как `ValueListenableBuilder` строит по копии,
которую обновляет каждое уведомление. И контроллеры он сравнивает
по идентичности: получив новый контроллер, про который `==` говорит, что это
старый, `SoloBuilder` переходит на него, а `ValueListenableBuilder` остаётся
со старым. Когда экран следит за одним значением из большого состояния,
`SoloSelectBuilder` перестраивается только на изменение этого значения,
а остальное состояние оставляет в покое:

```dart
SoloSelectBuilder<ProfileState, bool>(
  solo: profile,
  selector: (state) => state is Loading,
  builder: (context, loading, _) => loading
      ? const CircularProgressIndicator()
      : ElevatedButton(
          onPressed: _open,
          child: const Text('Open profile'),
        ),
)
```

Там, где родитель перестраивается часто, держите выбирающую функцию в поле или
в `static`: её сравнивают по идентичности, поэтому написанное на месте
замыкание — каждый раз новое, и каждое такое перестроение делает новую выборку.

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
final class ProfileController extends AppController<ProfileState>
    with SoloListenable {
  ProfileController() : super(const Initial());
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
