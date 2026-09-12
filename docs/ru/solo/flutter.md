# Flutter

Используйте `SoloListenable<S>` из `flutter_solo` как базовый класс
контроллера. Он наследует `SoloBase<S>` и реализует
`ValueListenable<S>`; стрима у него нет — виджет перестраивается по
`value`, а результат операции ждут через её `Job`. Контроллер профиля
сохраняет те же состояния и метод `load`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

final class ProfileController extends SoloListenable<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  // ...задачи из быстрого старта...
}
```

Экран может владеть контроллером: создайте его в `initState` и закройте
в `dispose`. Общий контроллер может находиться в существующем контейнере
зависимостей: `provider`, `get_it` или `InheritedWidget`. За закрытие
отвечает владеющий им код; `flutter_solo` не предоставляет `SoloProvider`
и не закрывает контроллеры автоматически.

`ValueListenableBuilder` перестраивается при изменении состояния.
Чтобы перейти на другой экран или показать сообщение после конкретной
операции, дождитесь исхода её `Job` в месте вызова. После ожидания
проверьте `mounted`, прежде чем обращаться к контексту виджета.
Здесь `ProfilePage` является экраном назначения в приложении:

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

`value` и `currentState` ссылаются на один объект. Сеттера значения нет;
`Job` контроллера выполняют обновления через контекст.
`ListenableBuilder` и `AnimatedBuilder` также принимают контроллер,
когда самому билдеру значение состояния не нужно.
