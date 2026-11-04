> **Состояние на 2026-11-04:** зонд пройден, оба плагина по `version:`
> разрешаются и работают на Dart 3.13.0 и на полу 3.10.0, каждый один и оба.
> Кода не меняет.
> **Что это:** зонд пакета-пользователя, который называет опубликованные
> `solo_lints` и `async_job_lints` в `analysis_options.yaml` по `version:`.
> **Связанные записи:** `2026-11-03-lints-split-design.md`,
> `2026-11-03-lints-split-plan.md`, `2026-11-04-solo-lints-release-report.md`,
> `2026-11-04-async-job-lints-0-1-1-release-report.md`.

# Зонд: плагины линтов по `version:`

## Что проверялось

Дизайн `2026-11-03-lints-split-design.md` проверил разделение линтов
на плагинах, названных путём. Остался один вопрос: разрешается ли верхний
плагин, сам названный по `version:`, — без публикации его не проверить. После
выпусков `solo_lints` 0.1.5 и `async_job_lints` 0.1.0 и 0.1.1 план
`2026-11-03-lints-split-plan.md` велел пройти зонд: пакет-пользователь называет
`solo_lints: ^0.1.5` и `async_job_lints: ^0.1.0` по `version:`, каждый один
и оба.

## Стенд

Пакет-пользователь вне репозитория, зависимости с pub.dev:

```yaml
name: version_probe_user
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  async_job: ^1.0.0
  solo: ^1.0.0
```

`lib/core.dart` — задача на одном ядре с двумя правилами ядра:

```dart
import 'package:async_job/async_job.dart';

abstract interface class Device {
  Future<void> flush();

  Future<void> close();
}

Job<void> record(Future<Device> Function() open) => Job<void>((ctx) async {
  final device = await ctx.join(open);
  ctx.onDispose(device.close); // release_on_the_call
  ctx.onDispose(() async {
    await ctx.join(device.flush); // ctx_in_cleanup
  });
});
```

`lib/recorder.dart` — контроллер `solo` с правилом ядра и правилом, которое
есть только у `solo_lints`:

```dart
import 'package:solo/solo.dart';

abstract interface class Device {
  Future<void> close();
}

final class Recorder extends Solo<int> {
  Recorder(this._open) : super(0);

  final Future<Device> Function() _open;

  SoloJob<int> sync() => enqueue<int, int>((ctx) async => 1);

  Job<void> record() => enqueue<int, void>((ctx) async {
    final device = await ctx.join(_open);
    ctx.onDispose(device.close); // release_on_the_call
    await sync().value; // await_own_queue
  });
}
```

`lib/ignored.dart` — два `ctx_in_cleanup`, каждый под `// ignore:` своего
плагина. Какая строка осталась в выводе, показывает, чей это плагин в наборе:

```dart
import 'package:async_job/async_job.dart';

Job<void> silencedBySolo(Future<void> Function() flush) =>
    Job<void>((ctx) async {
      ctx.onDispose(() async {
        // ignore: solo_lints/ctx_in_cleanup
        await ctx.join(flush);
      });
    });

Job<void> silencedByCore(Future<void> Function() flush) =>
    Job<void>((ctx) async {
      ctx.onDispose(() async {
        // ignore: async_job_lints/ctx_in_cleanup
        await ctx.join(flush);
      });
    });
```

Четыре набора `analysis_options.yaml`: `solo` — один `solo_lints`, `core` —
один `async_job_lints`, `solo-core` и `core-solo` — оба, в этом порядке. Плагин
назван так:

```yaml
plugins:
  solo_lints:
    version: ^0.1.5
  async_job_lints:
    version: ^0.1.0
```

На каждом наборе `dart pub get`, затем `dart analyze` из корня пакета;
разрешённые версии — из `pubspec.lock` синтетического `plugin_entrypoint`,
который сервер анализа собирает в `~/.dartServer/.plugin_manager/`.

## Итог

Оба SDK, Dart 3.13.0 и Dart 3.10.0 из Flutter 3.38.1, дали одно и то же
построчно. Версии в таблице — `solo_lints` и `async_job_lints`; последняя
колонка — какой `// ignore:` в `ignored.dart` не заглушил свою строку:

| Набор | Версии | Диагностик | Не глушит |
| --- | --- | --- | --- |
| `solo` | 0.1.5 и 0.1.1 | 5 | `async_job_lints/` |
| `core` | — и 0.1.1 | 4 | `solo_lints/` |
| `solo-core` | 0.1.5 и 0.1.1 | 5 | `async_job_lints/` |
| `core-solo` | 0.1.5 и 0.1.1 | 5 | `solo_lints/` |

- Каждый плагин по `version:` разрешается с pub.dev и работает, один и вместе
  с другим. `^0.1.0` у `async_job_lints` берёт 0.1.1, и `solo_lints` 0.1.5
  получает тот же 0.1.1 своей зависимостью `^0.1.0`.
- `solo_lints` один приносит все правила: оба правила ядра в обоих файлах
  и `await_own_queue`. `async_job_lints` один — только правила ядра, и они
  срабатывают и в файле `solo`.
- Названы оба — дублей нет: каждая диагностика ядра приходит один раз. Хозяин
  правила с одним именем — плагин, названный первым: глушит `// ignore:` с его
  именем, а с именем второго — нет.

Вывод `solo` на Dart 3.13.0, сообщения сокращены до места и правила:

```text
warning lib/core.dart:11:3 release_on_the_call
warning lib/core.dart:13:11 ctx_in_cleanup
warning lib/ignored.dart:15:15 ctx_in_cleanup
warning lib/recorder.dart:16:5 release_on_the_call
warning lib/recorder.dart:17:11 await_own_queue
5 issues found.
```

Это подтверждает на опубликованных пакетах то, что дизайн выяснил на плагинах,
названных путём, и закрывает его последний непроверенный случай. Совета README
обоих пакетов зонд не меняет: «Name one of the two plugins, not both» — оба
работают вместе, пока их ограничения сходятся, а когда расходятся, не работает
ни один (зонд ревьюера в дизайне, `exit=4`).
