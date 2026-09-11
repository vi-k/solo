> **Состояние на 2026-09-11:** подготовка `flutter_solo` 0.2.0 к выпуску
> выполнена, подтверждённых блокеров нет; публикация не выполнялась.
> **Что это:** отвязка от локальных `solo` и ядра, проверки против
> опубликованных пакетов и dry-run перед выпуском `flutter_solo`.
> **Связанные записи:**
> `2026-09-11[1]-solo-release-readiness-report.md`,
> `2026-09-11[2]-solo-release-report.md`.

# Область работы

Владелец попросил подготовиться к публикации `flutter_solo`. Это
подготовка в дереве, не поручение выполнить связку выпуска. Релизный
коммит, тег, push и `flutter pub publish` не выполнялись.

# Правки

`packages/flutter_solo/pubspec_overrides.yaml` удалён целиком: `solo`
0.2.0 и `async_job` 0.2.0 опубликованы, пакет берёт их с pub.dev.
В `pubspec.lock` источник обоих `hosted`, sha256 `95487cd8…aa0a`
и `60c88a81…ac6b`.

`packages/flutter_solo/example/pubspec_overrides.yaml` сокращён до одного
оверрайда на `flutter_solo` по пути `../`. Совсем убрать его нельзя:
`example/pubspec.yaml` объявляет `flutter_solo: ^0.2.0`, а такой версии
на pub.dev ещё нет, и пример не разрешится. Это отличие от примера
`solo`, который берёт свой пакет путём прямо в `pubspec.yaml`. Оверрайд
снимается после публикации. Комментарий в файле переписан под одну
оставшуюся запись.

`packages/flutter_solo/.pubignore` — поправлен комментарий: он говорил
о нескольких неопубликованных пакетах, остался один. Сама запись
`example/pubspec_overrides.yaml` нужна и остаётся: файл ведёт за
пределы архива, а `example/` едет внутри пакета.

# Проверки

Из `packages/flutter_solo` против опубликованных `solo` и ядра:

- `flutter analyze`: No issues found;
- `flutter test`: 8 тестов прошли;
- `dart format` для `lib`, `test`, `example`: 4 файла, 0 изменений;
- `dart doc --dry-run`: 0 предупреждений и 0 ошибок;
- `flutter pub publish --dry-run`: 0 предупреждений, архив 10 KB;
- `flutter pub outdated`: прямые зависимости актуальны.

Из `packages/flutter_solo/example`: `flutter analyze` чистый. Тестов
у примера нет, только `lib/main.dart`.

Из корня: `python3 tool/check_line_width.py` — нет строк шире 79;
`python3 tool/check_translations.py` — no differences (пять пар).

Состав архива проверен по списку dry-run: `README.md`, `CHANGELOG.md`,
`LICENSE`, `analysis_options.yaml`, `lib/`, `test/` и `example/` из
`pubspec.yaml`, `analysis_options.yaml` и `lib/main.dart`. `README.ru.md`
и оверрайд примера исключены. Каталог `doc/` в архив не попал и не
должен: в нём только `api/`, вывод `dart doc`, закрытый `.gitignore`.

Первый dry-run повторил историю `solo`: одно предупреждение о
checked-in и ignored `pubspec_overrides.yaml`, потому что удаление ещё
не попало в индекс git. После `git add` предупреждение ушло. Вместе
с ним ушло `Failed to update packages.` в конце вывода.

Внешние адреса README и pubspec отвечают 200:
`pub.dev/packages/solo`, `pub.dev/packages/async_job`, ссылка на
`vs-bloc.md` в GitHub, `repository` и `issue_tracker`. Относительных
ссылок в README нет. `https://pub.dev/api/packages/flutter_solo`
отвечает 404 — имя свободно, выпуск будет первым.

CHANGELOG проверен отдельно после истории с `solo`: абзац о первом
выпуске здесь и так стоит первым, пометок **Breaking** внутри раздела
нет. Править нечего.

# Что осталось владельцу решить

**Dev-зависимость `flutter_lints` отстаёт.** В дереве `^5.0.0`,
разрешима `6.0.0`. На потребителей не влияет: dev-зависимости не
наследуются. Это тот же разговор, что и про `lints` в `solo`, и делать
его надо разом во всех пакетах. Отдельная работа.

**У примера нет README.** У примера `solo` он есть и объясняет, что
запускать и что будет на выходе; здесь pub.dev покажет сам
`example/lib/main.dart`. Не блокер, но страница выпуска выглядела бы
ровнее. Текст писать не стал.

# Что закроется этим выпуском

README опубликованного `solo` зовёт `flutter pub add flutter_solo`
и ссылается на страницу пакета на pub.dev, которая сейчас отвечает 404.
Выпуск `flutter_solo` 0.2.0 закрывает это без правок текста.

# Не выполнялось

Связка выпуска целиком: релизный коммит `Release flutter_solo 0.2.0`,
аннотированный тег `flutter_solo-v0.2.0`, push и `flutter pub publish`.
Разрешения на неё не было; по `AGENTS.md` оно приходит отдельным
запросом, который не содержит ничего, кроме просьбы опубликовать.

Чужая правка `.vscode/launch.json` вне пакета не тронута.
