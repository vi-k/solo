# flutter_solo

Flutter integration for [`solo`](../solo): a `ValueListenable` face for
`Solo` controllers.

`SoloListenable<S>` extends `Solo<S>` and implements
`ValueListenable<S>`, so it drops straight into `ValueListenableBuilder`
or `ListenableBuilder`. Listeners fire synchronously, in subscription
order, on every state change; `Solo`'s `stream` still works, delivered a
microtask later.

## Install

```yaml
dependencies:
  flutter_solo: ^1.0.0
```

## Usage

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

See [`solo`](../solo) for the controller itself: jobs, rules, cancellation
and the rest of the public API.
