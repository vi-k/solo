# flutter_solo

> Это перевод [`README.md`](README.md). Источник правды — английский
> оригинал; перевод обновляется в том же коммите, что и оригинал. В пакет,
> публикуемый на pub.dev, этот файл не попадает.

Интеграция [`solo`](../solo) с Flutter: лицо `ValueListenable` для
контроллеров `Solo`.

`SoloListenable<S>` наследует `Solo<S>` и реализует
`ValueListenable<S>`, поэтому подставляется прямо в `ValueListenableBuilder`
или `ListenableBuilder`. Листенеры вызываются синхронно, в порядке
подписки, на каждое изменение состояния; `stream` из `Solo` при этом
продолжает работать, доставляя событие микротаской позже.

## Установка

```yaml
dependencies:
  flutter_solo: ^1.0.0
```

## Как пользоваться

```dart
import 'package:flutter/material.dart';
import 'package:flutter_solo/flutter_solo.dart';

sealed class CounterState {}

class Idle extends CounterState {
  final int count;

  Idle(this.count);
}

class Counter extends SoloListenable<CounterState> {
  Counter() : super(Idle(0));

  Job<void> increment() => run<Idle, void>((ctx) async {
    ctx.emit(Idle(ctx.state.count + 1));
  });
}

class CounterView extends StatelessWidget {
  final Counter counter;

  const CounterView({super.key, required this.counter});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CounterState>(
    valueListenable: counter,
    builder: (context, state, _) => Text('${(state as Idle).count}'),
  );
}
```

Про сам контроллер — задачи, правила, отмену и остальное публичное API —
смотри [`solo`](../solo).
