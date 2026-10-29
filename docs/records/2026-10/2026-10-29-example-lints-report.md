> **Состояние на 2026-10-29:** сделано в ветке работы, в `main` не влито.
> **Что это:** `solo_lints` в примерах `solo` и `flutter_solo`, и что
> `flutter analyze` начиная с Flutter 3.44 диагностик плагина не показывает.
> **Связанные записи:** `2026-10-29-solo-lints-release-report.md`,
> `2026-10-29-bare-await-design.md`.

# solo_lints в примерах

По слову владельца 2026-10-29 «давай линты в примерах». Вопрос стоял
в `docs/handoff.md` с выпуска 0.6.0: ни пример `solo`, ни пример `flutter_solo`
плагин не подключали.

## Что сделано

- `packages/solo/example/analysis_options.yaml`
  и `packages/flutter_solo/example/analysis_options.yaml` называют плагин
  `solo_lints: ^0.1.1` с pub.dev и включают все четыре линта:
  `catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs`
  и `bare_await`. Предупреждения включены и так. В `pubspec.yaml` плагин
  не стоит: его скачивает сервер анализа.
- Пример `solo` дал одну находку: `catch_without_check` в тесте
  `test/camera_rakes_test.dart`, на варианте первой попытки «An opening that
  fails» страницы `camera.md`, который ловит, что бросил `emit` в `catch`.
  Дословная первая попытка в `test/support/camera_attempts.dart` молчит:
  `ctx.emit` первой строкой `catch` правило считает вопросом к задаче.
  У варианта `emit` стоит во вложенном `try`, и правило его там не видит.
  Вариант пишет `try` нарочно, поэтому получил `// ignore:` с причиной.
- Пример `flutter_solo` чистый: ни одной находки ни у `flutter analyze`,
  ни у `dart analyze`.
- Задание `flutter` гейта гоняет в примере `flutter_solo` ещё
  и `dart analyze --fatal-infos` (причина ниже). Пример `solo` идёт через
  `dart analyze --fatal-infos` в задании `dart`, как и раньше.
- `docs/conventions.md` описывает, где подключён плагин и почему.

## flutter analyze и плагины

Контрольный файл в `lib/` примера `flutter_solo` с голым `await` в теле `Job`
и с `ctx.pause` в `onDispose`:

| Flutter | Dart | `flutter analyze` | `dart analyze` |
| --- | --- | --- | --- |
| 3.38.1 | 3.10.0 | `bare_await` | `bare_await` |
| 3.44.4 | 3.12.2 | ни одной находки | — |
| 3.47.0 | 3.13.0 | ни одной находки, и `ctx_in_cleanup` уровня warning тоже | `bare_await`, `ctx_in_cleanup` |

`flutter analyze` начиная с 3.44 запускает `dart language-server`, а не прежний
сервер анализа (`flutter_tools`, `lib/src/dart/analysis.dart`): на 3.38.1 там
стоял `server.setSubscriptions` прежнего протокола. Почему по новому протоколу
диагнозов плагина нет — не выяснено; возможно, он кончает работу раньше, чем
плагин их присылает.

Следствия:

- README `solo_lints` и перевод говорили, что диагностики плагина показывает
  `flutter analyze`. Теперь говорят: на Flutter 3.38 — да, начиная с 3.44 —
  нет, во Flutter-пакете плагин проверяют через `dart analyze`. В списке
  изменений и переводе — раздел «Unreleased» с этой правкой; на pub.dev она
  придёт со следующим выпуском `solo_lints`.
- CI на Flutter stable, сейчас 3.47.0, без отдельного `dart analyze`
  проверял бы пример `flutter_solo` без плагина.
- Сессия tez работает на Flutter 3.44.4 и подключила `solo_lints` в CI; если
  у них гейт — `flutter analyze`, плагин в нём молчит.

## Чем проверено

На Dart 3.13.0 и Flutter 3.47.0:

- `packages/solo/example`: формат — 12 файлов, 0 изменений;
  `dart analyze --fatal-infos` — No issues found; `dart test` — +112;
- `packages/flutter_solo`: формат — 36 файлов, 0 изменений; `flutter analyze` —
  No issues found;
- `packages/flutter_solo/example`: `flutter analyze`
  и `dart analyze --fatal-infos` — No issues found; `flutter test` — +6;
- `check_translations.py`, `reflow.py --check`, `check_line_width.py` —
  зелёные; изменённые русские абзацы — линтер `humanizer--ru` без ERROR.

Что плагин в примерах действительно работает, показал тот же контрольный файл:
в примере `solo` — находка в тесте выше, в примере `flutter_solo` — находки
у `dart analyze`. Контрольный файл удалён.
