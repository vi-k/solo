> **Состояние на 2026-10-29:** сделано, в `origin` не отправлено; на pub.dev
> придёт со следующими выпусками `async_job`, `solo` и `flutter_solo`.
> **Что это:** `solo_lints` в README трёх пакетов и на странице частых ошибок.
> **Связанные записи:** `2026-10-29-example-lints-report.md`,
> `2026-10-29-solo-lints-release-report.md`.

# solo_lints в README пакетов

До этой работы о плагине говорил только его собственный README. Владелец выбрал
2026-10-29 из трёх мест два: раздел «Install» README и вступление страницы
частых ошибок. Третье, строка в таблице «Guides» README `solo`, отпало: таблица
перечисляет страницы, а не пакеты.

## Что сделано

- Раздел «Install» README `async_job`, `solo` и `flutter_solo` получил абзац
  о плагине, блок `yaml` с `plugins: solo_lints: ^0.1.1` и фразу о том, что так
  включаются предупреждения, а линты — по имени, со ссылкой на раздел «Install»
  README плагина. `async_job` называет две ошибки-предупреждения, ожидание
  в уборке и ресурс, потерянный при отмене; `solo` и `flutter_solo` ссылаются
  на страницу частых ошибок. `flutter_solo` добавляет, что начиная с Flutter
  3.44 `flutter analyze` диагностик плагина не показывает
  (`2026-10-29-example-lints-report.md`).
- Вступление `packages/solo/doc/mistakes.md` говорит, что о большинстве ошибок
  страницы плагин сообщает. «Большинство», а не «все»: раздел «Answering for
  every failure» правила не имеет.
- Ссылки на раздел установки плагина — адресом на GitHub, а не на pub.dev:
  такие `check_links.py` проверяет вместе с якорем.
- Переводы всех правленых файлов, записи «Unreleased» в CHANGELOG трёх пакетов
  и их переводах.

## Сторожа README

Три сторожа держали правило «каждый блок README прогоняется или назван» и упали
на новом блоке: `readme_recipe_test.dart` ядра, `readme_rakes_test.dart` `solo`
и `flutter_solo`. Теперь они называют блок `yaml` и проверяют его:

- у `solo` и `flutter_solo` — что версия в README та же, что
  в `example/analysis_options.yaml` пакета. Пример лежит в архиве, поэтому
  проверка идёт и в `floor`. Мутация версии в README `solo` на `^0.2.0` роняет
  сторожа;
- у `async_job` версию сверять не с чем: примера с плагином у ядра нет,
  а пакета плагина в архиве нет. Сторож держит форму блока.

Отсюда правило в `docs/conventions.md`: выпуск `solo_lints` с новой минорной
версией правит версию в примерах, в трёх README и переводах одним коммитом.

## Чем проверено

- `dart format`, `dart analyze --fatal-infos` и тесты README в `async_job`
  (+51) и `solo` (+43); в `flutter_solo` — `flutter analyze`
  и `readme_rakes_test.dart` (+76); `solo_lints` целиком — +191;
  `tool/flutter_snippets.py`;
- `reflow.py --check`, `check_line_width.py`, `check_translations.py`,
  `check_links.py`, `check_doc_shape.py`, `check_page_code.py`, сборка сайта
  и её тесты;
- новые русские абзацы — линтер `humanizer--ru` без ERROR.

Пол на `c99ae07c`: `tool/archive_floor.py stage` — все четыре пакета по 0
предупреждений, `run` на Flutter 3.38.1 с Dart 3.10.0 — «every archive passes
its gate on the floor: 6 roots»; сторожа README `solo` и `flutter_solo` читают
`example/analysis_options.yaml` и в архиве.
