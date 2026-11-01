> **Состояние на 2026-11-01:** `async_job` 1.0.0 опубликован на pub.dev;
> релизный коммит `584a6545` и аннотированный тег отправлены в origin.
> **Что это:** выполнение разрешённой владельцем связки выпуска `async_job`.
> **Связанные записи:** `2026-10-30-one-zero-report.md`,
> `2026-10-31-fable-review-wave-report.md`,
> `2026-10-28-async-job-release-report.md`.

# Выпуск async_job 1.0.0

Владелец разрешил публикацию отдельным запросом «опубликуй async_job и solo
1.0.0», состоящим только из просьбы опубликовать. Публикуется `async_job` 1.0.0
из `main` на основе `82eb2a75`. На pub.dev сейчас `latest: 0.6.0`.

Связка этого пакета первая; `solo` выходит следом своей связкой, после того как
снимет оверрайды на дерево и пройдёт проверки против опубликованного ядра,
запись `2026-11-01-solo-release-report.md`. `flutter_solo` и `solo_lints`
не публикуются: `flutter_solo` ждёт scopo под ядро 1.0, `solo_lints` выходит
своей связкой.

## Подготовка

Подготовка 1.0.0 — `2026-10-30-one-zero-report.md`, полное ревью и волна
правок — `2026-10-31-fable-review-wave-report.md`. Перед связкой:

- `git fetch` выполнен, `origin/main` на `82eb2a75` и совпадает с `main`;
- тега `async_job-v1.0.0` нет ни локально, ни в origin;
- дерево чистое, оверрайдов у ядра нет;
- `dart pub publish --dry-run` из `packages/async_job`: 0 предупреждений;
- CI `gate` на `17487eaa` зелёный четыре раза подряд, `82eb2a75` меняет только
  `docs/handoff.md`; пол `tool/archive_floor.py` на `f427cf76`, последнем
  коммите с правкой кода, — «every archive passes its gate on the floor: 6
  roots».

## Связка

Связка выполнена подряд:

- `584a6545` — Release async_job 1.0.0;
- аннотированный тег `async_job-v1.0.0` указывает на `584a6545`;
- `origin/main` и тег отправлены, соответствие подтверждено `ls-remote`:
  `refs/heads/main` и `refs/tags/async_job-v1.0.0^{}` дают `584a6545`;
- `dart pub publish --force` завершился успешно, сервер подтвердил загрузку:
  «Successfully uploaded https://pub.dev/packages/async_job version 1.0.0»;
- API pub.dev вернул `latest: 1.0.0`;
- CI `gate` на `584a6545`: `dart`, `flutter`, `floor`, `snippets` и `docs`
  зелёные. `site` на этот push не запускался: его пути push не задел.

Пакет: https://pub.dev/packages/async_job/versions/1.0.0

Выпуск завершён. Следом вышел `solo` 1.0.0,
`2026-11-01-solo-release-report.md`.
