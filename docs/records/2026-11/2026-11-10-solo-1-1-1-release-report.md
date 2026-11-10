> **Состояние на 2026-11-10:** выпущено по слову владельца «публикуй»:
> подготовка `73997a76`, релизный коммит `78df517c`, аннотированный тег
> `solo-v1.1.1`, `solo` 1.1.1 на pub.dev.
> **Что это:** подготовка патча `solo` 1.1.1 — документация, которая называет
> `SoloListener` из `flutter_solo`.
> **Связанные записи:** `2026-11-10-solo-1-1-0-release-report.md`,
> `2026-11-10-flutter-solo-1-1-0-release-report.md`,
> `2026-11-10-solo-listener-report.md`.

# Выпуск solo 1.1.1

По слову владельца 2026-11-10 «готовь выпуск solo 1.1.1». Слово понято как
подготовка: разрешение на связку приходит отдельным запросом, состоящим только
из просьбы опубликовать.

## Что в выпуске

Одна запись «Unreleased» — задача 7 плана `2026-11-09-solo-listener-plan.md`,
коммит `2e3a980b`: dartdoc `SoloCancelReason` и `ReplacedCancelReason`, строка
`doc/reference.md` и таблица `doc/cancellation.md` называют `SoloListener`,
который отменяет реакцию с `ReplacedCancelReason`, а `doc/vs-bloc.md`
отправляет `BlocListener` для чужого изменения к `SoloListener`. С тега
`solo-v1.1.0` в `packages/solo` изменились только эти документы, их переводы
и комментарии `lib/src/solo_cancel_reason.dart`; кода нет, поэтому выпуск —
патч. `flutter_solo` 1.1.0 с `SoloListener` уже на pub.dev, так что имя ведёт
на опубликованный виджет.

Ядро то же: `async_job: '>=1.0.0 <1.1.0'`. «Unreleased» ядра — только
документация, и `solo` её не ждёт.

## Подготовка

Коммит `73997a76` «chore: prepare solo 1.1.1»:

- `version: 1.1.1` в `packages/solo/pubspec.yaml`;
- «Unreleased» в `CHANGELOG.md` стал разделом «1.1.1», в переводе
  `docs/ru/solo/CHANGELOG.md` — «Не выпущено» тоже; `check_translations.py` —
  «no differences».

README версию не называет.

## Чем проверено

Полный гейт, пять заданий CI, на чистом дереве `73997a76`, статус 0:

- `dart`: формат, `dart analyze --fatal-infos` и `dart doc --dry-run` чистые;
  `async_job` +1905, `solo` +2260, пример `solo` +112, `async_job_lints` +203,
  `solo_lints` +96; оба плагина через сервер анализа;
- `flutter`: `flutter_solo` +337, его пример +6, стенд `flutter_solo` +56,
  трассы `mixins.md` — 6, 0 не напечатано; раскладка архивов — 0
  предупреждений;
- `floor` на Flutter 3.38.1 — «every archive passes its gate on the floor: 7
  roots»;
- `snippets`: шесть пакетов стендов, анализ чистый, все драйверы, трассы шести
  страниц сходятся;
- `docs`: все питоновские проверки, их сторожа и сборка сайта, 96 страниц;
  дерево после прогона не сдвинулось.

`dart pub publish --dry-run` в `packages/solo` на том же чистом дереве —
«Publishing solo 1.1.1», «Package has 0 warnings».

На 2026-11-10: на pub.dev `solo` 1.1.0; тега `solo-v1.1.1` нет ни локально,
ни в origin; `main` впереди `origin/main` на запись выпуска `flutter_solo`
и подготовку, не отстаёт.

## Связка

По слову владельца 2026-11-10 «публикуй» — отдельный запрос, состоящий только
из просьбы опубликовать. Перед связкой: `main` чистый, впереди `origin/main`
(`09ba1338`) на 3 коммита и не отстаёт, тега `solo-v1.1.1` нет ни локально,
ни в origin, на pub.dev `solo` 1.1.0. Связка — релизный коммит «Release solo
1.1.1» с этой записью, аннотированный тег `solo-v1.1.1` на нём,
`git push --follow-tags` и `dart pub publish` из чистого дерева
`packages/solo`.

Связка прошла подряд: релизный коммит `78df517c` «Release solo 1.1.1»,
аннотированный тег `solo-v1.1.1` на нём, `git push --follow-tags` —
`origin/main` с `09ba1338` на `78df517c` вместе с тегом, —
и `dart pub publish --force` из чистого дерева `packages/solo`: «Successfully
uploaded https://pub.dev/packages/solo version 1.1.1». API pub.dev отдаёт
версию 1.1.1 с датой публикации 2026-11-10.
