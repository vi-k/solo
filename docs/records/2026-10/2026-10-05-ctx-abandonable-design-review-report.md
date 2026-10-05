> **Состояние на 2026-10-05:** ревью дизайна сделано; все семь находок
> приняты и внесены в `2026-10-05-ctx-abandonable-design.md` тем же
> коммитом, код ещё не писался.
> **Что это:** независимое ревью дизайна переименования `ctx.wait`
> в `ctx.abandonable` на Opus — зонды на Dart 3.13.0 и на полу 3.6.0, счёт
> упоминаний, семь находок.
> **Связанные записи:** `2026-10-05-ctx-abandonable-design.md`.

# Ревью дизайна `ctx.abandonable`

Ревьюер применил дизайн буквально к копиям `async_job` и `solo` (`abandonable`,
`@Deprecated wait` в `JobContext` и `JobContextBase`, `solo` смотрит на копию
через оверрайд) и гонял анализатор на Dart 3.13.0 из PATH и на 3.6.0
(`~/fvm/versions/3.27.0`). Зонды лежали в каталоге сессии, вне репозитория.

## Находки

### 1. Анализатор не найдёт вызовы, а гейт не покраснеет. Блокирует

Раздел «Как найти все вызовы» опирается
на `deprecated_member_use_from_same_package`. На 3.13 это линт, по умолчанию
выключенный; в `analysis_options.yaml` его нет, `lints/recommended` его
не включает. Копия `async_job` с псевдонимом: `dart analyze` — «No issues
found!» при 561 вызове в `test/`, 9 в `lib/`, неквалифицированном `wait(`
в `job_stream.dart:179` и 23 ссылках `[wait]`; с включённым линтом — 574 info.
Info не роняют `dart analyze` (код выхода 0, с `--fatal-infos` — 1). Копия
`solo`: 187 info `deprecated_member_use`, выход 0. `gate.yml` гоняет голый
`dart analyze` для `async_job`, `solo`, его примера и стенда `snippets`;
краснеет только `flutter analyze`, где infos фатальны по умолчанию. На 3.6.0
подсказка для того же пакета включена сама: 31 info в `lib`.
И «с предупреждением» в записи неверно: это info, не warning.

Предложение: на волну включить `deprecated_member_use_from_same_package`
в `async_job/analysis_options.yaml` (или гонять `dart analyze --fatal-infos`
во всех пакетах и стендах); критерий конца волны — ноль таких info; тест
псевдонима — с `// ignore:`.

**Вердикт.** Принято. Сам проверил: `analysis_options.yaml` трёх пакетов
правила не называют, гейт зовёт `dart analyze` без `--fatal-infos`
(`gate.yml:124`), копия ревьюера с псевдонимом и вызовами проходит анализ
с кодом 0. Дизайн теперь: линт включается в `async_job` насовсем, если пол его
принимает, иначе только на волну; критерий конца — `dart analyze --fatal-infos`
без единого `deprecated_member_use*` во всех пакетах, примерах и стендах; тесты
псевдонима несут `// ignore:` с именем правила.

### 2. `@Deprecated` и на переопределении в `JobContextBase`. Надо исправить

Запись не говорит, что пометка стоит на обоих объявлениях, а устаревание
не наследуется. Без аннотации на переопределении из отчёта пропадают 17 мест —
вызовы на приёмнике-подклассе `JobContextBase` (`extending_rakes_test.dart`,
`cancel_test.dart:454`, `cleanup_test.dart:1079`, `late_value_test.dart:530`,
`support/extending_first_attempts.dart:55`, `job_context.dart:710,839`),
и так же у движков пользователей вроде `MyContext` из `doc/extending.md`.
`SoloContext` `wait` не переобъявляет, его 187 мест видны. Псевдониму
в интерфейсе нужен dartdoc, иначе сработает `public_member_api_docs`.

**Вердикт.** Принято: в дизайне пометка и dartdoc на обоих объявлениях.

### 3. Текст ошибки «cannot abandonable». Надо исправить

`throwIfFinished` и `throwIfDisposing` собирают текст как `'cannot $action'`
(`job_context.dart:786,800`); по схеме записи выходит
`Bad state: Job() has already finished, cannot abandonable`. Соседи передают
глагольную фразу: `'run an uncancellable action'`, `'register onCancel'`. Тест
на `cannot wait` сейчас нет ни одного.

**Вердикт.** Принято, проверил строки 786 и 800. Новое имя передаёт
`'run an abandonable action'`, псевдоним — `'wait'`; сторож сверяет точный
текст обоих.

### 4. Список мест неполон, два пункта указаны зря. Надо исправить

Вызовов на контексте — 1027 в 155 файлах, `[wait]` — 24, имени `wait`
в бэктиках — 110, строковых литералов с именем члена — около 90. Нет в записи:
`docs/architecture.md` (один `ctx.wait`, десять `wait` в бэктиках); сторожа,
которые цитируют прозу (`_says(...)` в `vs_bloc_rakes_test.dart`,
`errors_rakes_test.dart`, `testing_rakes_test.dart`, `readme_rakes_test.dart`
`flutter_solo`; ключи в `resources_rakes_test.dart`,
`cancel_delay_recipe_test.dart`, `errors_rakes_test.dart`;
`solo/test/cancellation_rakes_test.dart:1505–1516` вынимает список членов
из прозы `doc/cancellation.md` и ждёт в нём `'wait'`) — проза и они меняются
одним коммитом; `tool/accumulation_snippets.py:1145–1146` и 1292–1300;
комментарии `lib` (`job_context.dart:950,1091,1095,1103,1137`) и литерал
`'wait'` в 1211; идентификаторы `viaWait`, `exportWithWait`, `delayUnderWait`,
`throughWait`, `probeWait`, `runWaitingDownload`. Указано зря:
`tool/flutter_snippets.py` (`ctx.wait` там нет, четыре совпадения — глагол)
и `QUOTED`/`SAID` в `tool/doc_snippets.py` (там `wait` нет).

**Вердикт.** Принято. Проверил `docs/architecture.md` (11 упоминаний)
и `cancellation_rakes_test.dart:1505–1516`. Список в дизайне дополнен, два
лишних пункта сняты, идентификаторы, названные по члену, переименовываются.

### 5. `packages/solo/test/wait_test.dart` — решить сейчас. Мелочь

Все тесты файла о члене; переименовать в `abandonable_test.dart`. Имена тестов
внутри `waiting_test.dart` (15, 36, 135) и `parallel_wait_test.dart` (1012)
называют член и попадают под общее правило; имена файлов верны.

**Вердикт.** Принято.

### 6. «Migrating» обещает только предупреждение. Надо исправить

У пользователя `flutter_solo` `flutter analyze` по умолчанию делает infos
фатальными, и его CI после обновления покраснеет; запись в `CHANGELOG.md`
должна сказать это прямо. В `Unreleased` `async_job` 14 упоминаний, `solo` 2,
`flutter_solo` 0.

**Вердикт.** Принято: «Migrating» говорит, что анализ, для которого infos
фатальны, — `flutter analyze` по умолчанию, `dart analyze --fatal-infos`, —
краснеет до замены.

### 7. Риски без проблем и одна оговорка. Мелочь

На полу 3.6.0 псевдоним на интерфейсе с переопределением собирается и работает.
Подделок `JobContext`/`SoloContext` в репозитории нет, `noSuchMethod` только
на `Job` и `JobBase`. Расширение одно — `_JobStreamBody on JobContext`, его
неквалифицированный `wait(` — находка 1. Оверрайды у `solo`, `flutter_solo`
и примеров смотрят на дерево. Оговорка: `solo/pubspec.yaml` держит
`async_job: ^0.2.0`, и `solo` не выйдет раньше `async_job` 0.3.0 с поднятым
ограничением; сайт покажет `abandonable` раньше pub.dev, как и всё
из `Unreleased`.

**Вердикт.** Принято к сведению; порядок выпуска записан в дизайне одной
строкой.
