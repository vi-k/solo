> **Состояние на 2026-11-13:** первый заход отправлен коммитом `d99edb2e`,
> второй — `159e4339`; оба прогона упали в `flutter`. Третий заход — конец
> раздела «После отправки», вливается в `main` вместе с этой правкой.
> **Что это:** отчёт о красном `gate` после пуша `1dc26d91`: что упало, чьё
> это и чем починено.
> **Связанные записи:** `2026-11-12-solo-review-candidates-report.md`,
> `2026-11-12-queue-key-index-report.md`.

# Красный CI после пуша 2026-11-12

## Что упало

Прогон `gate` на `1dc26d91` упал в трёх заданиях, `floor` пропущен вслед
за `flutter`. Прогон на `567bf830` днём раньше уже краснел в `dart`, последний
зелёный — `78df517c` 2026-11-10.

- `docs`: `tool/check_doc_shape.py` — раздел «Where another package fits
  better» README `solo` открывался прозой. Раздел добавил я в работе
  `2026-11-12-solo-review-candidates-report.md`, а `check_doc_shape.py` в моём
  наборе проверок перед коммитом не было.
- `dart`: CI поставил Dart 3.14.0 из `stable`, где `dart:mirrors` объявлен
  устаревшим, и анализ с `--fatal-infos` упал
  на `packages/async_job/test/cleanup_test.dart`. Задание выполняется
  с `bash -e`, поэтому остальные пакеты не проверялись.
- `flutter`: CI поставил Flutter 3.50.0 из `stable`, где
  `package:flutter/material.dart` устарел в пользу `package:material_ui`; 13
  замечаний в тестах и примере `flutter_solo`, `lib` его не импортирует.

## Что нашлось сверх лога

Локально есть Flutter 3.51 с Dart 3.15 (`fvm` `master`). Анализ и тесты всех
пакетов задания `dart` на нём и на локальном SDK 3.13 показали ещё три места:

- `dart:mirrors` ещё в трёх тестах `solo`: `accumulator_test.dart`,
  `controller_base_test.dart`, `reference_page_test.dart`.
- `packages/solo_lints/test/mistakes_page_test.dart` краснел на любом SDK:
  таблица теста требует строку на каждую пару страницы ошибок, а два раздела
  `mistakes.md` — «Listening to a stream in a job» и «A copy read before the
  wait, in a lane» — добавил я в той же работе и тест не пополнил. CI до тестов
  не дошёл.
- `children_test.dart` ядра и `solo` сверяли дословный текст ошибки
  анализатора, а в Dart 3.15 он другой: «The member 'start' isn't defined for
  the type 'ChildJob<void>'» вместо «The method 'start' isn't defined for the
  type 'ChildJob'». Есть ли эта перемена в 3.14, локально не проверить.

## Что сделано

- README `solo` и перевод: три случая раздела — таблица «случай, что подходит,
  почему», фраза о команде над сущностью семейства — под таблицей.
- `ignore: deprecated_member_use` с причиной над каждым импортом
  `material.dart` во `flutter_solo` (тринадцать файлов) и над `dart:mirrors`
  в четырёх тестах. Решение владельца: из трёх вариантов — подавить, перейти
  на `material_ui`, закрепить версию в CI — подавить: все выпуски
  `material_ui`, кроме первого 0.0.1, требуют Flutter 3.44 и выше, а пол —
  Flutter 3.38.1. Без `ignore` замечание на Flutter 3.51 есть, с ним нет;
  на 3.47 и 3.38.1 `ignore` лишних замечаний не даёт.
- В таблице `mistakes_page_test.dart` две строки с `null` и обвязки `_tracker`
  и `_feed`: оба раздела компилируются в обвязке, и ни одно правило
  `solo_lints` в `main` их не ловит.
- `children_test.dart` в обоих пакетах сверяет суть ошибки —
  `'start' isn't defined for the type 'ChildJob` — а не слова вокруг.

## Проверки

На Dart 3.15 и на локальном 3.13: `dart analyze --fatal-infos` и тесты
`async_job` +1905, `solo` +2481, `async_job_lints` +203, `solo_lints` +102;
пример `solo` +112. `flutter analyze` `flutter_solo` и примера чистый на 3.51
и 3.47, `flutter test` +344 и +6 — только на 3.47, на 3.51 тесты не гонялись,
и это пропустило падение из раздела ниже. Тринадцать проверок задания `docs`
зелёные; сборку сайта локально не гонял.

## После отправки

Прогон `gate` на `d99edb2e`: `docs`, `dart` и `snippets` зелёные, `flutter`
упал на десяти тестах из 344 — `readme_rakes_test.dart`
и `testing_rakes_test.dart`. Каждый сообщал «The value of reportTestException
was changed by the test.»

Оба файла гоняют тело виджетного теста внутри обычного `test` через
`_asWidgetTest`: ставят свой `reportTestException`, зовут `binding.runTest`,
затем возвращают прежний репортёр и зовут `binding.postTest()`. Биндинг
запоминает репортёр в начале `runTest`, то есть уже подменённый, и сверяет его
с текущим. Во Flutter 3.47 сверка шла внутри `runTest`, во Flutter 3.50 —
в `postTest`, а к нему репортёр был уже возвращён. Порядок переставлен: сначала
`postTest`, затем возврат репортёра, тоже в `finally`.

Воспроизведено на Flutter 3.51 до правки, после неё `flutter test`
`flutter_solo` +344 и примера +6 зелёные на 3.51 и 3.47, `flutter analyze`
чистый на обоих.

Прогон на `159e4339`: тесты `flutter_solo` прошли, упал следующий шаг задания,
«Analyze the bench». Стенд `tool/flutter_snippets.py` собирает экраны из README
`flutter_solo`, `doc/mixins.md` и `doc/testing.md`, а пять собранных файлов
импортируют `material.dart`, как его импортирует приложение читателя. В первом
заходе этот стенд локально не гонялся.

В документы `ignore` не ставится: это код для читателя. Его ставит генератор,
при записи файлов, в конец строки импорта. Правила стенда включают
`unnecessary_ignore`, а `ignore` нужен только по одну сторону Flutter 3.47:
строкой выше он на 3.47 дал пять замечаний `unnecessary_ignore`. Поэтому
`ignore` в конце строки называет оба правила, `deprecated_member_use`
и `unnecessary_ignore`, — на той строке, где второе было бы сказано.

Шаги стенда из задания — сборка, `pub get`, анализ,
`flutter test --concurrency=1` и `check_traces.py` по `doc/mixins.md` — зелёные
на Flutter 3.51 и 3.47: анализ без замечаний, +59, восемь трасс найдены.
