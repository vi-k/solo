> **Состояние на 2026-10-23:** связка выпуска `flutter_solo` 0.3.0 выполняется
> релизным коммитом; итог публикации дописывается следующим коммитом.
> **Что это:** снятие оверрайдов `flutter_solo` и выполнение разрешённой
> владельцем связки выпуска `flutter_solo`.
> **Связанные записи:** `2026-10-23-solo-release-report.md`,
> `2026-10-23-async-job-release-report.md`,
> `2026-10-22-release-check-report.md`,
> `2026-09-11[4]-flutter-solo-release-report.md`.

# Выпуск flutter_solo 0.3.0

Владелец разрешил публикацию отдельным запросом «публикуй flutter_solo»,
состоящим только из просьбы опубликовать. Публикуется `flutter_solo` 0.3.0
из `main` после выпусков `async_job` и `solo` 0.3.0. На pub.dev сейчас
`latest: 0.2.0`. Это последний из трёх пакетов выпуска.

## Подготовка

Оверрайды сняты коммитом `6282917d`: удалены
`packages/flutter_solo/pubspec_overrides.yaml`
и `packages/flutter_solo/example/pubspec_overrides.yaml`, удаление добавлено
в индекс. Оба вели `solo` и `async_job` на дерево. Пример зависит
от `flutter_solo` путём `../`, и оверрайд на сам пакет ему не нужен. Других
`pubspec_overrides.yaml` в дереве не осталось; стенды `tool/doc_snippets.py`
и `tool/accumulation_snippets.py` по-прежнему ведут `async_job` на дерево,
а оно совпадает с тегом `async_job-v0.3.0`.

Проверки против опубликованных пакетов. В `pubspec.lock` пакета и примера
`solo` 0.3.0, sha256 `8b85dc41…ca10`, и `async_job` 0.3.0, sha256
`3f32d2bc…01fe`, оба с источником `hosted`.

- `packages/flutter_solo`: формат — 34 файла, 0 изменений;
  `flutter analyze --fatal-infos` — No issues found; `flutter test` — +242, All
  tests passed; `dart doc --dry-run` — 0 предупреждений и 0 ошибок;
- `packages/flutter_solo/example`: формат — 2 файла, 0 изменений; анализ
  чистый; `flutter test` — +6;
- `flutter pub publish --dry-run` — 0 предупреждений.

Пол 3.27.0 прогнан локально на `6282917d`: `tool/archive_floor.py stage`
разложил архивы трёх пакетов, у каждого dry-run без предупреждений,
`tool/archive_floor.py run` прошёл все пять корней — «every archive passes its
gate on the floor: 5 roots». Оверрайдов в раскладке больше нет, поэтому впервые
с начала цикла `floor` доказывает и ограничения между пакетами:
`flutter pub downgrade solo` у `flutter_solo` дошёл до нижней границы `^0.3.0`.

CI на релизном коммите `solo`, `c685e082`, зелёный во всех пяти заданиях
`gate`.
