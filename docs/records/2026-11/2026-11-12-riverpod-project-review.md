> **Состояние на 2026-11-12:** ревью проведено двумя независимыми ревьюерами,
> Fable 5.2 и Astra, на теге `riverpod-v3.5.0` репозитория
> `rrousselGit/riverpod`. Находки уровня Medium и выше и все выжившие
> мутации перепроверены моими командами, у каждой находки стоит вердикт.
> Действий от нас не требует: это чужой пакет, ревью сделано, чтобы знать его
> сильные и слабые стороны.
> **Что это:** независимое ревью `riverpod` 3.5.0, `riverpod_annotation` 4.0.8
> и сгенерированного кода `riverpod_generator` 4.0.10 без сравнения с другими
> библиотеками и без доводов о популярности: код, тесты с мутациями, API
> на следующий мажор, порог входа, масштаб, документация, ИИ-агенты; оба
> отчёта целиком, мои вердикты и задание.
> **Связанные записи:** `2026-11-12-bloc-project-review.md`,
> `2026-11-12-solo-project-review.md`.

# Независимое ревью `riverpod` 3.5.0: Fable и Astra

## Как это делалось

Задание владельца: «сделай теперь такое же ревью для riverpod» — вслед за ревью
`bloc` (`2026-11-12-bloc-project-review.md`). Выполнять код `riverpod` в копиях
владелец разрешил отдельно: «разрешаю выполнять код riverpod в этих копиях».

Задание — то же, что у `bloc`, переписанное под этот пакет. Область:
`packages/riverpod` с экспериментальными мутациями и сохранением,
`riverpod_annotation` целиком, сгенерированный код `riverpod_generator` и 23
страницы сайта: установка, первое приложение, все страницы `concepts2/`, выбор
кодогенерации, пять рецептов `how_to/`, FAQ, «do and don't» и миграция на 3.0.
Запрещены доводы о популярности, загрузках, лайках, звёздах, очках pub.dev,
издателе, известности автора, возрасте пакета, «так принято» и привычности API,
запрещено чтение отзывов, статей и issues о `riverpod`. Сравнения с другими
библиотеками и оценки «на фоне» нет. Задание целиком — в конце записи.

Все пять пакетов выпущены с одного коммита `7a02bedc`: `riverpod` 3.5.0,
`flutter_riverpod` 3.5.0, `riverpod_annotation` 4.0.8, `riverpod_generator`
4.0.10, `riverpod_lint` 3.2.0. Репозиторий — pub workspace с `sdk: ^3.12.0`
и Flutter master в `.fvmrc`; на стабильном SDK он не разрешается: мешает
ограничение на `test_api`. Поэтому я поставил Flutter master через
`fvm install master --setup` (Flutter 3.51.0-1.0.pre-90, Dart
3.15.0-139.0.dev), и все прогоны обоих ревьюеров шли на нём. До ревью набор
ядра в обеих копиях давал `00:12 +1647 ~5: All tests passed!`.

Ревьюеры работали каждый в своей копии клона на теге `riverpod-v3.5.0` и друг
друга не видели: Fable 5.2 — субагентом Claude Code, около 25 минут; Astra —
`codex exec` с `gpt-6-astra` на усилии `xhigh`, около 41 минуты. У Astra было
два отказа песочницы: `/bin/ps` и запись
`/Users/user/.dartServer/.plugin_trust`. Из-за второго первые три
`dart analyze` упали с `The analysis server crashed unexpectedly`; Astra
перенесла состояние анализатора в каталог копии через
`ANALYZER_STATE_LOCATION_OVERRIDE` и повторила их. Astra прогнала ещё
и `riverpod_lint` настоящим плагином анализатора в отдельном пакете и сам
генератор на своих зондах; Fable о линтах судил по списку правил,
о генераторе — по закоммиченным `*.g.dart`.

Как я принимал. Перепрогнал своими командами зонды обоих ревьюеров: у Fable —
`probe_core`, `probe_persist`, `probe_agent`, `probe_cycle` в debug и product,
`probe_chain` 800 и 1600 в product, `probe_scale family` 10 000 и 20 000
и `listeners` в product; у Astra — `probe_persist`, `probe_core` с assert
и без, `probe_lifecycle`, `probe_retry`, `probe_docs`, `probe_scope`
и `probe_codegen`. Все вывели то, что процитировано в отчётах; времена масштаба
у меня меньше, отношения те же. Обе выжившие мутации-дыры перепрогнал своим
скриптом с возвратом файла копией: m01 Fable (она же M8 Astra) и M2 Astra —
набор зелёный, после возврата tracked diff пуст. Страж `persist`, проверку
цикла под `kDebugMode`, `_runCallbacks` и ключ `@JsonPersist` в генераторе
сверил по коду, тексты документации и CHANGELOG — по дереву. Остальное помечено
в вердиктах как принятое по чтению или по отчёту. Зонды ревьюеров живут в их
копиях и в репозиторий не перенесены: их вывод процитирован в находках. Ссылки
отчёта Astra на файлы копии заменены именами файлов; больше проза отчётов
не правлена, только уровни заголовков.

## Итог приёмки

Оценки из десяти:

| | Fable | Astra |
| --- | --- | --- |
| Общая | 6,5 | 6,5 |
| Код | 6,5 | 7 |
| Тесты | 8 | 7,5 |
| Документация | 5,5 | 5 |
| Для ИИ-агентов | 5 | 5,5 |

Для справки: те же два ревьюера по заданию того же склада дали `bloc` 6 и 6
(`2026-11-12-bloc-project-review.md`), `solo` — 8 и 8,8
(`2026-11-12-solo-project-review.md`). У `solo` было ещё сравнение с похожими
пакетами pub.dev и ревью шло по ветке перед выпуском; `bloc` и `riverpod`
ревьюеры смотрели по опубликованному выпуску. Числа одной шкалы, но не одного
опыта.

Что нашли оба независимо — всё подтверждено моими прогонами:

- страж `didChange` в `persist` мёртв: он сбрасывается в том же синхронном
  вызове, и ответ медленного хранилища затирает свежее состояние,
  у `AsyncNotifier` — возвращает завершённую загрузку в `AsyncLoading` (Fable
  C2, Astra C1);
- `persist` удаляет сохранённое значение при любом `AsyncError`, хотя старое
  значение ещё в памяти (Fable C3, Astra C3), и набор это закрепляет тестом;
- набор пропускает удаление самого стража: мутация m01 Fable и M8 Astra;
- пример ручного сохранения на странице `offline` падает в рантайме, ошибка
  уходит в зону, а запись не обновляется (Fable D6, Astra D1);
- `_runCallbacks` обходит список колбэков без копии: снятие `onDispose` изнутри
  даёт `ConcurrentModificationError`, и следующие колбэки очистки не вызываются
  (Fable C6, Astra C5);
- одна и та же ошибка приходит разными типами: `.future` — исходной, синхронное
  чтение — `ProviderException`, через звено — вложенной; рецепт миграции
  с `on ProviderException` вокруг `.future` не срабатывает (Fable C5, B5, D7;
  Astra B3, D3);
- повтор по умолчанию: миграция обещает «until it succeeds», dartdoc
  аннотации — «unlimited retries», а `defaultRetry` останавливается после
  десяти попыток (Fable D2, Astra D3);
- `Mutation.run` без `await` публикует `MutationError` и одновременно роняет
  ошибку в зону, страница показывает именно такой вызов (Fable C7, D17; Astra
  B5, D5);
- `@riverpod` по умолчанию autoDispose, ручной провайдер — нет, а вкладки
  страниц подаются как одна программа (Fable B11, S2, D9; Astra B1);
- в страницах остались несуществующие имена: `MyProviderRef`, `valueOrNull`,
  `hasData`, а депрекация и CHANGELOG советуют `provider.exist` при геттере
  `exists` (Fable B2, D3, D4, D5; Astra D4);
- «waits for one frame (cf. `await null`)» на странице `auto_dispose` неверно
  для чистого Dart: после `await null` провайдер ещё жив (Fable D14, Astra D6);
- первая сборка длинной цепочки рекурсивна и кончается `Stack Overflow` около
  тысячи звеньев (Fable S3, Astra S3);
- `state.add(x); state = state;` не уведомляет никого и ничем не ловится (Fable
  A5, Astra A1); список как аргумент `family` даёт новый элемент на каждый
  вызов (Fable S5, Astra S2);
- имена с цифрой `overrideWith2`, `ProviderTransformer2` (Fable B3, B13; Astra
  B8); шаблон `sdk: ^3.7.0` на странице установки при `^3.12.0` у пакета (Fable
  D12, Astra D7).

Только у Fable: ошибка под повтором по умолчанию 38,2 с выглядит как
`AsyncLoading`, и `switch` по классам из README показывает загрузку (C1, A1);
синхронный `Notifier` теряет восстановленное значение (C4); ручной `state =`
во время ожидающего `build` затирается его результатом (C8); проверка циклов
живёт только в debug, в product — `StackOverflowError` (C9); квадратичная
работа при многих зависимых и снятии подписок (S4); `ref.watch` и `ref.listen`
в методе notifier молча подписывают и копят слушателей (A2, A3); CHANGELOG
3.5.0 называет зависимость `material_ui`, которой у ядра нет; `test_api`
и пререлиз `listen` в рантайм-зависимостях (B8, B9).

Только у Astra: геттер `ref` notifier после `await` отдаёт `Ref` нового
запуска, так что проверка `ref.mounted` из миграции пропускает старый `build`
к побочному эффекту (B2, D2); асинхронные записи хранилища могут лечь
в обратном порядке (C2); `@JsonPersist` строит один ключ для `('x, y', 'z')`
и `('x', 'y, z')` (C4); закрытая `MutationTransaction` в release держит
провайдер навсегда, защита — только assert (C6); scoped-провайдер без
`dependencies` молча читается из корня и с assert (B7); набор пропускает смену
срока хранения по умолчанию (T1, мутация M2).

Мутации: Fable — 16, применено 14, набор пропустил одну (m01); Astra — 8,
пропущено две (M2 и M8, M8 совпадает с m01). Обе различные дыры перепроверены
и выжили.

Сильные стороны, которые оба оставили бы как есть: ленивый согласованный
пересчёт (миллион обновлений — одна пересборка производного у Fable, ромб без
промежуточной пары у Astra), тексты исключений жизненного цикла с причиной
и лечением (`UnmountedRefException`, scoped `dependencies`), вынос старых
провайдеров в `legacy.dart`, проверка механики через `ProviderContainer` без
Flutter, быстрый набор тестов, который ловит точечные мутации.

## Отчёт Fable 5.2

Копия: `review-fable`, тег `riverpod-v3.5.0`, коммит `7a02bedc`. SDK: Dart
3.15.0-139.0.dev из `fvm/versions/master`. Все зонды — новые файлы
`packages/riverpod/test/probe_*.dart`; мутации возвращены копией, под конец
`git status --short` показывает только `.review-tmp/` и пять `probe_*`.

### 1. Оценки

| Оценка | Балл |
|---|---|
| Общая | **6.5 / 10** |
| Код | **6.5 / 10** |
| Тесты | **8 / 10** |
| Документация | **5.5 / 10** |
| Для ИИ-агентов | **5 / 10** |

**Код — 6.5.** Подняло: ядро графа (ленивая пересборка, фильтр по `==`, пауза
подписок, scoping с проверкой `dependencies`) ведёт себя как описано; тексты
исключений по большей части называют причину и лечение
(`UnmountedRefException`, ошибка scoped-зависимости, «uninitialized notifier»);
миллион обновлений с производным провайдером — 0.4 с в product. Опустило:
повтор по умолчанию, который 38 секунд держит ошибку под видом загрузки (C1);
мёртвый страж в `persist`, после которого провайдер навсегда остаётся
в `AsyncLoading` (C2); стирание офлайн-кеша при ошибке сети (C3); рекурсивная
сборка, которая на цепочке ~1000 провайдеров кончается переполнением стека
через 24–38 секунд (S3); квадратичная работа на провайдере с десятками тысяч
зависимых (S4); проверка циклов только в debug (C9); несогласованность того,
каким типом приходит ошибка (C5).

**Тесты — 8.** Подняло: 1647 тестов за 12 секунд, из 14 применённых мутаций
поймано 13, причём узкими, по имени понятными тестами (retry-счётчик, кап
задержки, `pause/resume`, `Mutation ==`). Опустило: единственная пропущенная
мутация стоит ровно на дефекте C2 — тест с названием «провайдер выигрывает
у асинхронного адаптера» асинхронного адаптера не содержит (T1); есть тест,
который закрепляет потерю кеша как требование (T2); нет тестов на глубину
цепочки и на число зависимых (T3).

**Документация — 5.5.** Подняло: страницы `concepts2/` короткие, по одной теме,
с парными вкладками «руками / codegen»; `first_app.mdx` доводит до работающей
программы; `testing.mdx` и `do_dont.mdx` честно предупреждают о части граблей.
Опустило: README чисто дартового пакета показывает Flutter и кодогенерацию
и не говорит, как пакет поставить (D1); в страницах живут имена, которых
в 3.5.0 нет: `valueOrNull`, `hasData`, `MyProviderRef`, `provider.exist` (D3,
D4, D5, B2); пример ручного сохранения падает в рантайме (D6); страница
миграции утверждает о `ProviderException` то, что зонд опровергает (D7);
о главном следствии повтора по умолчанию — 38 секунд спиннера и тесты
на ошибку, которые ждут 38 секунд, — не сказано нигде (D2).

**Для ИИ-агентов — 5.** Подняло: исключения жизненного цикла текстом говорят,
что делать; линты ловят часть ошибок codegen. Опустило: много правдоподобного
кода собирается и молча ведёт себя не так — `switch` по классам `AsyncValue`
из README (A1), `ref.watch` в методе notifier (A2), `ref.listen` в методе (A3),
`container.read` autoDispose-провайдера (A4), `state.add(x); state = state`
(A5), список как аргумент `family` (A6), `on ProviderException` вокруг
`.future` по рецепту миграции (D7). Ни анализатор, ни assert на них
не срабатывают, а устаревшие имена в документации заставляют агента писать код,
который не собирается.

**Общая — 6.5.** Ядро зрелое и хорошо покрытое, но значения по умолчанию
(повтор, autoDispose в codegen против ручного, пауза потоков) расходятся с тем,
что читатель ожидает по документации, экспериментальная часть (persist)
содержит дефект с потерей данных, а документация отстала от API.

### 2. Сводка

- Повтор по умолчанию (10 попыток, 200 мс … 6.4 с) превращает любую ошибку
  `Exception` в 38.2 секунды `AsyncLoading`; пример из README в это время
  показывает спиннер, `provider.future` висит, синхронный `Provider`
  пересобирается 11 раз.
- `persist`: страж «состояние уже поменяли» сбрасывается раньше, чем
  срабатывает; при хранилище медленнее сети провайдер навсегда остаётся
  `AsyncLoading(value: cached)`. Мутация, удаляющая страж, набором не поймана.
- `persist` удаляет ключ при `AsyncError`: сбой сети стирает офлайн-кеш.
- Ошибка провайдера приходит то исходным типом (`.future`),
  то `ProviderException` (`read`, `selectAsync`),
  то `ProviderException(ProviderException)` — рецепт миграции не работает.
- Цепочка зависимостей ~1000 звеньев — `Stack Overflow` после 24–38 секунд
  молчания; 100 000 зависимых одного провайдера — 44 секунды на перечитывание
  в product-режиме, в debug уже 20 000 дают 81 секунду.
- Проверка циклов живёт только в debug: в product поздно замкнутое кольцо —
  `StackOverflowError`.
- Документация отстала: `valueOrNull`, `hasData`, `MyProviderRef`,
  `provider.exist`, `sdk: ^3.7.0`, «retry until it succeeds».
- Codegen по умолчанию autoDispose, ручной провайдер — нет: парные вкладки
  страниц показывают неэквивалентный код.
- Тесты сильные: 13 из 14 мутаций пойманы.

### 3. На следующий мажор

#### B1. `ProviderContainer.defaultRetry` — значение по умолчанию.

Место: `lib/src/core/provider_container.dart`, `defaultRetry`; параметр `retry`
у `ProviderContainer`, `ProviderScope`, провайдеров. Что не так: повтор включён
для всех провайдеров, включая синхронные и чисто вычислительные; итоговая
ошибка откладывается на 38.2 с. Правка сломает тех, кто рассчитывает
на автоматический повтор сетевых запросов. Что сделать: по умолчанию
не повторять; повтор включать явно (`retry:` у провайдера или контейнера), либо
хотя бы не повторять синхронные `Provider`/`Notifier` и ограничить умолчание
2–3 попытками. Доказательство: `probe_core.dart`, разделы 1 и 2 (C1).

**Вердикт:** Подтверждено, см. вердикт C1: `defaultRetry`
в `provider_container.dart` с `maxRetries = 10`, `minDelay` 200 мс, `maxDelay`
6400 мс. Предложение — дело авторов `riverpod`.

#### B2. `provider.exists` против `provider.exist`.

Место: `lib/src/core/provider/provider.dart`, геттер `exists`; `ref.dart:655`
и `provider_container.dart:1154`, текст `@Deprecated`; `CHANGELOG.md` 3.5.0.
Что не так: геттер называется `exists`, а сообщение депрекации, dartdoc геттера
(`ref.watch(provider.exist)`) и CHANGELOG («Added `provider.exist`»,
«Deprecated `Ref.exist`») называют `exist`. Следуя подсказке анализатора,
получаешь ошибку компиляции. Правка текста ничего не ломает. Что сделать:
исправить три текста сейчас, в патче. Доказательство: по чтению (`grep`
в ПРОГОНЕ).

**Вердикт:** Подтверждено по дереву: геттер `get exists` в `provider.dart:71`,
а тексты `@Deprecated('Use ref.read/watch/listen(provider.exist) instead')`
в `ref.dart:655` и `provider_container.dart:1155`, dartdoc геттера и CHANGELOG
3.5.0 («Added `provider.exist`») называют `exist`.

#### B3. `overrideWith2`.

Место: семейства notifier-провайдеров, `overrideWith` (deprecated)
и `overrideWith2`. Что не так: цифра в имени публичного члена — след миграции,
а не имя. Правка сломает вызовы `overrideWith2`. Что сделать: в мажоре вернуть
имя `overrideWith` с новой сигнатурой, `overrideWith2` оставить депрекацией
на один мажор. По чтению.

**Вердикт:** Принято по чтению.

#### B4. `StorageCacheTime.unsafe_forever`.

Место: `lib/experimental/persist.dart`. Что не так: snake_case в публичном API
Dart; «unsafe» не говорит, чем опасно. Что сделать: `StorageCacheTime.forever`
с dartdoc о миграциях схемы. Ломает только экспериментальный API. По чтению.

**Вердикт:** Принято по чтению.

#### B5. Тип ошибки при чтении провайдера.

Место: `ProviderException` (экспортирован только из `misc.dart`),
`provider.future`, `selectAsync`, `container.read`, `AsyncValue.requireValue`.
Что не так: см. C5 — три разных формы одной ошибки, а тип, который велено
ловить, не виден из основного импорта. Что сделать: одно правило на все пути
(либо всегда исходная ошибка, либо всегда одна обёртка, без вложения),
`ProviderException` — в `riverpod.dart`. Сломает `catch` в пользовательском
коде на одном из путей. Доказательство: `probe_agent.dart`, `probe_core.dart`
раздел 5.

**Вердикт:** Подтверждено моим прогоном `probe_agent.dart`:
`await read(p.future)` — `caught the original FormatException`,
`requireValue` — `ProviderException(FormatException)`, провайдер поверх
упавшего — `ProviderException(ProviderException)`; см. вердикт C5.

#### B6. `AsyncValue.value` и `requireValue` при ошибке.

Место: `lib/src/core/async_value.dart`. Что не так: `value` у `AsyncError`
с предыдущим значением молча отдаёт старое значение; в паре с рекомендованным
`switch` «сначала значение» (first_app, pull_to_refresh) ошибка обновления
не показывается вовсе. Что сделать: либо переименовать в `latestValue`
и оставить `value` только свежему, либо убрать из документации шаблон
«value-first» как основной. Ломает чтение `value` в ветке ошибки. По чтению
и по D8.

**Вердикт:** Принято по чтению; связь с шаблоном «сначала значение» — см. D8.

#### B7. `AsyncValueExtensions.retrying`, `isFromCache` — флаги вместо состояния.

Место: `async_value.dart`. Что не так: «ошибка, ждём повтор» кодируется как
`AsyncLoading(error:, retrying: true)`; сопоставление по классам, которое
показывает README, этого не видит. Что сделать: либо отдельное состояние, либо
`AsyncError(retrying: true)` — ошибка остаётся ошибкой, пока новый запрос
не начат. Ломает код, который полагается на `isLoading` во время ожидания
повтора. Доказательство: `probe_core.dart`, разделы 1 и 28.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, разделы 1 и 28:
во время повторов
`AsyncLoading<int> isLoading=true hasError=true retrying=true`,
`switch AsyncError class -> loading`.

#### B8. `ProviderContainer.test` и зависимость `test_api` в рантайме.

Место: `pubspec.yaml` (`test_api: ^0.7.0`), `ProviderContainer.test`. Что
не так: тестовая утилита в основной библиотеке тянет `test_api` в каждое
приложение и привязывает ядро к версии тестового раннера. Что сделать: вынести
в `package:riverpod/test.dart` отдельного пакета или принять `addTearDown`
параметром. Ломает импорт у тех, кто зовёт `ProviderContainer.test`. По чтению.

**Вердикт:** Подтверждено по `pubspec.yaml` ядра: `test_api: ^0.7.0`
в `dependencies`. Остальное — по чтению.

#### B9. Зависимость `listen: ^1.0.0-beta.3`.

Место: `pubspec.yaml`. Что не так: стабильный выпуск 3.x зависит от пререлиза
ради `provider.listenable`. Что сделать: до стабильного `listen` держать
`.listenable` в `experimental/`. По чтению.

**Вердикт:** Подтверждено по `pubspec.yaml` ядра: `listen: ^1.0.0-beta.3`.

#### B10. `Mutation.call<ChangedT extends ResultT>` и ключи мутаций.

Место: `lib/src/core/mutations.dart`. Что не так: `call` у объекта, который сам
не вызывается как действие, а возвращает ключёванную копию
(`deleteTodo(todo.id)`), читается как запуск; два одновременных `run` делят
одно состояние (C7). Что сделать: именованный метод (`byKey`/`family`),
описанная политика одновременных запусков. Ломает экспериментальный API.
Доказательство: `probe_persist.dart`, M3.

**Вердикт:** Принято. Общее состояние двух одновременных запусков подтверждено
моим прогоном `probe_persist.dart`, M3: `results: [first, second]`,
`states: [MutationPending<String>(), MutationSuccess<String>(second)]`.

#### B11. Codegen: autoDispose по умолчанию.

Место: `riverpod_annotation`, `@riverpod` / `@Riverpod(keepAlive: false)`. Что
не так: одна и та же библиотека имеет противоположные умолчания в двух способах
записи (см. S2, D9). Что сделать: одно умолчание; если autoDispose —
то и у ручных провайдеров. Ломает время жизни у одной из половин пользователей.
Доказательство: `sync.g.dart` (`isAutoDispose: true`), `probe_core.dart` раздел
12.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 12:
`sync read after inc: 1`, `read after async gap: 0`. `isAutoDispose: true`
в `sync.g.dart` не сверял.

#### B12. Экспорт `riverpod_annotation`.

Место: `packages/riverpod_annotation/lib/riverpod_annotation.dart`. Что не так:
экспорт повторяет половину ядра (`AsyncValue`, `Ref`, `ProviderContainer`),
но не всё (`Provider`, `NotifierProvider`, `ProviderException` — нет), плюс два
десятка `$`-имён с `// ignore: invalid_export_of_internal_element`.
Пользователь codegen не знает, какой импорт ему нужен. Что сделать: либо
экспортировать `riverpod.dart` целиком, либо только аннотации; `$`-имена —
в отдельную библиотеку `riverpod_annotation/generated.dart`. По чтению.

**Вердикт:** Принято по чтению.

#### B13. `ProviderBase implements Override`, `WhenComplete` (nullable typedef), `SyncProviderTransformerMixin` / `ProviderTransformer2` / `SyncProviderTransformer2`.

Место: `misc.dart`. Что не так: провайдер сам является `Override`
(в `overrides: [provider]` он компилируется и значит «scope», что из типа
не видно); ещё два имени с цифрой. Что сделать: в мажоре убрать депрекации
и вернуть имена без цифр. По чтению.

**CHANGELOG.** `riverpod` 3.5.0: запись «added `material_ui` as a dependency» —
в `pubspec.yaml` ядра такой зависимости нет (запись скопирована
из Flutter-пакета); «Added `provider.exist`» / «Deprecated `Ref.exist`» — имена
неверны (B2). 3.4.0 и 3.4.3 дублируют «Upgraded `analyzer` to `<15.0.0`».
3.4.2 — «Fix a different source of `markNeedsBuild` error. Those are tricky!»
не говорит, что изменилось. Остальные проверенные записи 3.5.0
(`ProviderDisposedException`, публичный конструктор
`AsyncValueIsLoadingException`, экспорт `debugTrackProviderCreation`) с кодом
сходятся; мутация m14 показала, что `ProviderDisposedException` держат 22
теста.

**Вердикт:** B13 принято по чтению. Абзац о CHANGELOG сверил по дереву: раздел
`## 3.5.0
- 2026-11-06` содержит «Migrated Material imports to
  `package:material_ui/material_ui.dart` and added `material_ui` as a
  dependency», а в `pubspec.yaml` ядра такой зависимости нет; «Deprecated
  `Ref.exist`» и «Added `provider.exist`» — см. B2.

### 4. Находки по коду

#### C1. Повтор по умолчанию держит ошибку под видом загрузки 38.2 секунды.

Тяжесть: **High**. Место: `lib/src/core/provider_container.dart`,
`ProviderContainer.defaultRetry`; `element.dart`, планирование повтора.
Механика: любой бросок, кроме `Error` и `ProviderException`, запускает до 10
повторов с задержками 200 мс, 400, 800, … до 6.4 с. Всё это время состояние —
`AsyncLoading(error: …, retrying: true)`, `isLoading == true`. Таймеры держат
процесс живым. Доказательство: `test/probe_core.dart`, раздел 1 — падающий
`FutureProvider`:
`builds=11, future failed at=0:00:38.200000, final=AsyncError<int>`;
`when() -> loading`; `switch AsyncError class -> loading`;
`switch hasError-first -> error`. Раздел 2 — синхронный `Provider`, бросающий
`Exception`: `builds=11`, `onError` слушателя
в `[200, 600, 1400, 3000, 6200, 12600, 19000, 25400, 31800, 38200]` мс.
Следствия: пользователь 38 секунд смотрит на спиннер;
`await ref.read(p.future)` 38 секунд не завершается; тест на ошибочный путь без
`retry: (_, __) => null` ждёт 38 секунд или падает по таймауту; побочный эффект
в `build` (запрос на запись) повторяется 11 раз. Предложение: B1; до мажора —
`ProviderContainer.test` с `retry` выключенным по умолчанию и абзац в README
и `testing.mdx`.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`:
`builds=11, future failed at=0:00:38.200000, final=AsyncError<int>`, слушатель
синхронного `Provider` получает `onError`
в `[200, 600, 1400, 3000, 6200, 12600, 19000, 25400, 31800, 38200]` мс. Вариант
`switch` с проверкой `hasError` первой даёт `error`, по классам — `loading`.

#### C2. `persist`: страж `didChange` мёртв; медленное хранилище затирает свежее состояние и оставляет провайдер в `AsyncLoading` навсегда.

Тяжесть: **High** (экспериментальный API, но страница `offline.mdx` ведёт
к нему обычным кодом). Место: `lib/src/core/provider/notifier_provider.dart`,
`NotifierPersistX.persist`, строка `if (didChange) return null;`. Механика:
флаг `didChange` выставляется слушателем состояния, но сбрасывается в `finally`
сразу после синхронной части, поэтому к моменту, когда асинхронное чтение
хранилища вернулось, флаг всегда `false`; декодированное значение записывается
поверх `AsyncData(fresh)` как
`AsyncLoading(value: cached, valueSource: cache)`, и ничто больше не переводит
его в `AsyncData`. Доказательство: `test/probe_persist.dart`, P1 — хранилище
отвечает за 50 мс, `build` за 10 мс: `AsyncLoading<String>() ->
AsyncData<String>(value: fresh) -> AsyncLoading<String>(value: cached,
valueSource: cache)`; `final: … isLoading=true isFromCache=true`. P1b
(хранилище быстрее) — порядок верный. Мутация m01 (строка стража удалена)
набором не поймана. Предложение: флаг не сбрасывать до конца чтения (или
сравнивать поколение состояния), добавить тест с настоящим `await`
в `Storage.read`.

**Вердикт:** Подтверждено. По коду: в `NotifierPersistX.persist` слушатель
`listenSelf` ставит `didChange = true` и в `finally` того же синхронного вызова
возвращает `false`, так что к ответу `storage.read` страж всегда ложен. Мой
прогон `probe_persist.dart`, P1: `AsyncLoading<String>() ->
AsyncData<String>(value: fresh) -> AsyncLoading<String>(value: cached,
valueSource: cache)`, итог `isLoading=true isFromCache=true`.

#### C3. `persist` удаляет ключ из хранилища при `AsyncError`.

Тяжесть: **High** для заявленного назначения «offline». Место: там же,
`_callEncode`. Механика: переход состояния в `AsyncError` вызывает
`storage.delete(key)`. Сценарий «есть кеш, сети нет»: кеш показан, запрос
упал — кеш стёрт; следующий запуск офлайн покажет пустоту. Доказательство:
`probe_persist.dart`, P2:
`state: AsyncError<String>(value: cached, error: Exception: offline …`,
`storage log: [delete todos] remaining keys: ()`. Поведение закреплено тестом
(T2). Предложение: при ошибке хранилище не трогать; удаление — только явным
`persist.clear`/истечением `cacheTime`.

**Вердикт:** Подтверждено моим прогоном `probe_persist.dart`, P2:
`storage log: [delete todos] remaining keys: ()`.

#### C4. Синхронный `Notifier` + `persist`: восстановленное значение затирается возвратом `build`, и в хранилище уходит начальное значение.

Тяжесть: **Medium**. Место: там же. Механика: `persist(...)` в синхронном
`build` ставит `state = 7` из хранилища, затем `return 0` перезаписывает
состояние, слушатель сохранения пишет `0`. Доказательство:
`probe_persist.dart`, P3: `restored state on first read: 0`,
`storage after first build: 0`. Правильная запись (`return state` после
`persist`) нигде не показана. Предложение: `persist` возвращает восстановленное
значение или `build` получает его параметром; до того — пример в `offline.mdx`.

**Вердикт:** Подтверждено тем же прогоном, P3:
`restored state on first read: 0`, `storage after first build: 0`.

#### C5. Одна и та же ошибка приходит тремя разными типами.

Тяжесть: **Medium**. Место: `element.dart` (`.future`),
`modifiers/select_async.dart`, `ProviderContainer.read`,
`AsyncValue.requireValue`. Доказательство: `probe_agent.dart` —
`[await read(p.future) on failure] caught the original FormatException`;
`[read(p).requireValue on failure] caught ProviderException(FormatException)`;
`[read of a provider watching a failed provider] caught
ProviderException(ProviderException)`; `probe_core.dart`, раздел 5 —
`p.future -> FormatException`, `p.selectAsync -> ProviderException`. Следствие:
`e.exception is NotFoundException` из страницы миграции ложно уже на втором
звене зависимости, а `on ProviderException` вокруг `.future` не ловит ничего.
Предложение: B5; минимум — не вкладывать `ProviderException`
в `ProviderException`.

**Вердикт:** Подтверждено, см. вердикт B5; `probe_core.dart`, раздел 5:
`p.future -> FormatException`, `p.selectAsync -> ProviderException`.

#### C6. `_runCallbacks` итерирует список колбэков жизненного цикла без копии.

Тяжесть: **Medium**. Место: `lib/src/core/ref.dart`, `_runCallbacks`. Механика:
колбэк `onCancel`/`onResume`/`onDispose`, который снимает себя (возвращённой
функцией удаления) во время вызова, меняет список под итератором.
Доказательство: `probe_core.dart`, раздел 4:
`sub.close() threw ConcurrentModificationError`, остальные колбэки не вызваны
(`sub.closed=true`, то есть подписка закрыта наполовину). Предложение:
итерировать по копии (`toList()`), как это сделано для слушателей.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 4:
`sub.close() threw ConcurrentModificationError`. По коду: `_runCallbacks`
в `ref.dart` идёт `for (final cb in callbacks)` по самому списку.

#### C7. Мутации: одно состояние на одновременные запуски, необработанная ошибка при fire-and-forget.

Тяжесть: **Medium** (экспериментальный API). Место:
`lib/src/core/mutations.dart`, `Mutation.run`. Доказательство:
`probe_persist.dart`. M2 — `m.run(...)` без `await`, как в `mutations.mdx`:
состояние `MutationError`, и та же ошибка в зоне:
`uncaught zone errors: [Exception: save failed]` (во Flutter это красный
экран/краш-репорт на ожидаемую ошибку формы). M3 — два одновременных `run`:
`states: [MutationPending<String>(), MutationSuccess<String>(second)]` —
состояние `Success`, пока первый запуск ещё идёт; результат первого теряется.
M4 — после `container.dispose()` `tsx.get` бросает `StateError` без текста
о причине. Предложение: описать политику (очередь/последний побеждает/отказ)
и дать её параметром; `run`, чьё `Future` не слушают, не должен ронять ошибку
в зону, раз она уже лежит в `MutationError`.

**Вердикт:** Подтверждено моим прогоном `probe_persist.dart`: M2 —
`MutationError` и `uncaught zone errors: [Exception: save failed]`; M3 — см.
B10; M4 — `tsx.get after dispose threw StateError`.

#### C8. `state =` в методе `AsyncNotifier` во время ожидающего `build` перезаписывается результатом `build`.

Тяжесть: **Medium**. Место: `AsyncNotifier`, `element.dart`. Доказательство:
`probe_core.dart`, раздел 27:
`[AsyncLoading<int>(), AsyncData<int>(value: 42), AsyncData<int>(value: 1)]`.
Оптимистичная запись пользователя молча пропадает. Предложение: либо описать
в dartdoc `state`, либо отменять результат `build`, если `state` выставили
руками после его начала (как это делает `persist` по замыслу).

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 27:
`[AsyncLoading<int>(), AsyncData<int>(value: 42), AsyncData<int>(value: 1)]`.

#### C9. Проверка циклов и `dependencies` работает только в debug.

Тяжесть: **Medium**. Место: `ref.dart`, `_debugAssertCanDependOn`;
`element.dart`, `flush`/`_maybeRebuildDependencies`. Доказательство:
`probe_cycle.dart`. Debug: `late ring: ProviderException: …
CircularDependencyError: Circular dependency detected. … The circular
dependency chain is as follows`. С `-Ddart.vm.product=true`: прямой цикл —
`Bad state: Tried to read the state of an uninitialized provider`, кольцо,
замкнутое после первой сборки, —
`late ring: StackOverflowError: Stack Overflow` (трасса из 10 660 кадров
`flush → _maybeRebuildDependencies → visitAncestors`). Предложение: дешёвый
страж «элемент уже в flush» в релизе.

**Вердикт:** Подтверждено. По коду: все вызовы `_debugAssertCanDependOn`
в `ref.dart` стоят под `if (kDebugMode)`, внутри неё поиск цикла
с `CircularDependencyError`. Мои прогоны `probe_cycle.dart`: в debug —
`CircularDependencyError: Circular dependency detected.`, в product —
`late ring: StackOverflowError: Stack Overflow`, код выхода 255.

#### C10. `StreamProvider` без слушателей ставит поток на паузу; `read` отдаёт застывшее значение.

Тяжесть: **Low** (описано в миграции как «out of view providers are paused»,
но не для `container.read`). Доказательство: `probe_core.dart`, 19a:
`listened: 1`, `after unlistened events, read: 1 (isPaused=true)`,
`later read: 1` при событиях 2 и 3. Буфер приостановленного
`StreamSubscription` растёт. Предложение: dartdoc `StreamProvider`
и `refs.mdx` — «`read` не снимает паузу».

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, 19a:
`after unlistened events, read: 1 (isPaused=true)`, `later read: 1`.

#### C11. Экземпляр `Notifier` переживает пересборку и `invalidate`.

Тяжесть: **Low**. Доказательство: `probe_core.dart`, раздел 13:
`same instance after dependency rebuild: true field=7 builds=2 state=0`,
`same instance after invalidate: true`. Поля класса сохраняются, состояние
сбрасывается; в `providers.mdx` об этом ни слова, а линт
`avoid_public_notifier_properties` намекает, но не объясняет. Предложение:
абзац в dartdoc `Notifier.build`.

**Вердикт:** Подтверждено тем же прогоном, раздел 13:
`same instance after dependency rebuild: true field=7 builds=2 state=0`,
`same instance after invalidate: true`.

#### C12. `ref.watch` в колбэке `ref.listen` и в `onDispose` не отвергается.

Тяжесть: **Low**. Доказательство: `probe_agent.dart`:
`[ref.watch inside listen callback] OK`, `[ref.watch inside onDispose] OK`;
изменение чужого notifier из `build` —
`[modify another provider in build] OK -> 0`. `do_dont.mdx` это запрещает, код
молчит. Предложение: assert в debug.

**Вердикт:** Подтверждено моим прогоном `probe_agent.dart`:
`[ref.watch inside listen callback] OK`, `[ref.watch inside onDispose] OK`,
`[modify another provider in build] OK -> 0`.

#### C13. Сообщение «state read inside first build» говорит о цикле.

Тяжесть: **Low**. Доказательство: `probe_agent.dart`: чтение `state` в первом
`build` — `Bad state: Tried to read the state of an uninitialized provider.
This generally means that have a circular dependency…`. Цикла нет. Предложение:
различать «build ещё не вернулся» и цикл.

**Вердикт:** Подтверждено тем же прогоном: `Tried to read the state of an
uninitialized provider. This generally means that have a circular d…` при
чтении `state` в первом `build`.

#### C14. dartdoc `retrying` противоречит коду.

Тяжесть: **Low**. Место: `async_value.dart:61` — «[retrying] can be true and
[isLoading] false». Зонд, раздел 28:
`retrying=true isLoading=true type=AsyncLoading<int>`; после исчерпания попыток
`retrying=false`.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 28:
`retrying=true isLoading=true type=AsyncLoading<int>`. Строку dartdoc
не сверял.

### 5. Тесты

#### T1. Тест стража `persist` не содержит асинхронного чтения.

Тяжесть: **High** (держит дефект C2 зелёным). Место:
`test/src/core/provider/notifier_provider_test.dart`, «If a provider sets a
value before an asynchronous adapter, it wins». Механика: `Storage.read`
в тесте синхронный, а «асинхронность» — это `Future` внутри данных. Мутация m01
(страж удалён): `00:14 +1647 ~5: All tests passed!`. Предложение: тест
с `await Future.delayed` в `read` и ожиданием `AsyncData(fresh)` после него.

**Вердикт:** Подтверждено моим прогоном мутации m01 (удалён
`if (didChange) return null;`), скрипт с возвратом файла копией: весь набор
`00:10 +1647 ~5: All tests passed!`, после возврата `git status` — только
`.review-tmp/` и зонды.

#### T2. Тест закрепляет потерю кеша.

Тяжесть: **Medium**. Место: там же, «encode calls Persist.clear if state is set
to error». Мутация m02 (ошибка не удаляет ключ) роняет 16 тестов — то есть
поведение C3 записано как требование. Предложение: заменить тестом «ошибка
оставляет кеш».

**Вердикт:** Принято по отчёту: m02 не перепрогонял, но удаление ключа при
ошибке видно и в моём прогоне P2 (C3).

#### T3. Нет тестов масштаба.

Тяжесть: **Low**. Ни глубина цепочки (S3), ни число зависимых (S4), ни закрытие
многих подписок набором не сторожатся; регресс в сложности пройдёт
незамеченным.

**Вердикт:** Принято.

#### T4. `_runCallbacks` под изменением списка не покрыт

(C6) — по чтению тестов `ref_test.dart` на «remove itself» не нашёл; зонд
бросает.

Таблица мутаций (весь набор `dart test`, каждая с пределом времени; после
каждой `git status --short` показывал только `.review-tmp/` и `probe_*`):

| № | Файл и член | Что изменил | Итог |
|---|---|---|---|
| m01 | `notifier_provider.dart`, `persist` | удалён `if (didChange) return null;` | **не поймана** |
| m02 | `notifier_provider.dart`, `_callEncode` | `AsyncError` не удаляет ключ | поймана, 16 тестов («encode calls Persist.clear if state is set to error») |
| m03 | `provider_container.dart`, `defaultRetry` | убрано `\|\| error is Error` | поймана, 14 («retry default ignores Errors») |
| m04 | `element.dart`, retry | убран сброс `_retryCount` при смене зависимости | поймана, 1 («custom retry passes the correct retry count and error») |
| m05 | `ref.dart`, `invalidateSelf` | убрать проверку `isActive` | не применилась (шаблон не найден), не считается |
| m06 | `async_value.dart`, `whenData` | loading без `progress` | поймана, 1 («whenData transforms data if any») |
| m07 | `select_async.dart` | всегда уведомлять | поймана, 2 («can watch async selectors») |
| m08 | `mutations.dart`, `reset` | без `setRef(resetRef)` | поймана, 4 («Mutation .reset …») |
| m09 | `async_value.dart`, `==` | без сравнения loading | поймана, 9 (`async_value_test.dart: ==`) |
| m10 | `provider_container.dart`, `pump` | без `parent.pump` | поймана, 3 («auto dispose works if used across a ProviderContainer») |
| m11 | `provider_container.dart`, `defaultRetry` | без капа 6.4 с | поймана, 1 («default retry delays from 200ms to 6.4 seconds») |
| m12 | `ref.dart`, `isPaused` | без `_insideBuildFrame` | поймана, 1 («isPaused always starts as false») |
| m13 | — | намеренная пустышка для проверки скрипта | SKIP |
| m14 | `element.dart`, dispose | `StateError` вместо `ProviderDisposedException` | поймана, 22 |
| m15 | `provider_subscription.dart`, `resume` | `_pauseCount = 0` | поймана, 1 («resume needs to be called as many times as pause()») |
| m16 | `mutations.dart`, `Mutation ==` | без `_matchesT` | поймана, 1 («Supports generic mutations») |

Итого: применено 14, поймано 13, пропущена 1.

**Вердикт:** Принято: зонд бросает (вердикт C6), тест на это я не искал.

### 6. Понятия и масштаб

#### S1. Порог входа.

До первой правильной программы на чистом Dart — 4 понятия: `Provider`,
`ProviderContainer`, `Ref`, `ref.watch` против `read`. Во Flutter добавляются
`ProviderScope`, `ConsumerWidget`/`Consumer`, `WidgetRef` —
7. До программы с асинхронными данными, обновлением и отменой — ещё около 14:
   `FutureProvider` или `AsyncNotifier`+`AsyncNotifierProvider`, `AsyncValue`
   (три класса и флаги `isLoading`, `hasValue`, `hasError`, `isRefreshing`,
   `isReloading`, `retrying`, `isFromCache`), `ref.listen`, `invalidate` против
   `refresh`, `.future`, `.notifier`, `ref.onDispose`, `ref.mounted`,
   autoDispose, `keepAlive`, `retry`, `family`, `select`. Что можно убрать или
   отложить: `retry` — если выключить по умолчанию, он перестаёт быть
   обязательным знанием (сейчас без него не понять, почему ошибка не показана);
   `refresh` слить с `invalidate` (`refresh` = `invalidate` + `read`);
   `isRefreshing` /`isReloading` — одно из двух новичку не нужно;
   legacy-провайдеры уже вынесены и это правильно. Доказательство: чтение
   страниц области.

**Вердикт:** Принято: счёт понятий — суждение ревьюера.

#### S2. Цена выбора «руками или кодогенерация».

Тяжесть: **Medium**. Выбор стоит новичку: `build_runner`, `part`, `_$Name`, две
зависимости и, главное, другое время жизни — `@riverpod` autoDispose, ручной
провайдер нет (`sync.g.dart`: `isAutoDispose: true`). Страницы показывают пары
вкладок как эквивалент, и читатель, переключивший вкладку, получает другую
программу: `probe_core.dart`, раздел 12 — `container.read(p.notifier).inc()`
у autoDispose-notifier: `sync read after inc: 1`, `read after async gap: 0`.
`about_code_generation.mdx` советует codegen «только если уже используете
кодогенерацию», а README ядра открывается примером на `@riverpod`. Предложение:
одно умолчание (B11); README — на ручном синтаксисе; в каждой паре вкладок
ручной вариант писать с `.autoDispose` либо codegen с `keepAlive: true`.

**Вердикт:** Подтверждено, см. вердикт B11.

#### S3. Длинная цепочка: рекурсия и `Stack Overflow` через полминуты.

Тяжесть: **Medium**. Место: `element.dart`, `flush` → `build` → `ref.watch` →
`_addListener` → `flush`. Упирается в реализацию: первая сборка цепочки идёт
рекурсией, несколько кадров на звено. Доказательство: `probe_chain.dart`.
Debug: 800 звеньев — `first read = 799 in 52 ms`; 1000
(из `probe_scale.dart`) —
`THROW ProviderException … Stack Over… after 24213 ms`, затем
`Unhandled exception: Stack Overflow` при `dispose`, код выхода 255. Product:
800 — 23 мс; 1600 —
`first read THROW ProviderException (Stack Overflow inside) in 32699 ms`;
3200 — 38655 мс. Полминуты уходит на то, что каждое из ~1000 звеньев ловит
ошибку и заворачивает её со снятием стека. Обновление в debug растёт
квадратично (400 звеньев — 73 мс, 800 — 245 мс), в product линейно (38 → 65
мс). Предложение: итеративная сборка зависимостей либо явный предел глубины
с понятной ошибкой; `StackOverflowError` не заворачивать на каждом уровне.

**Вердикт:** Подтверждено моим прогоном `probe_chain.dart` в product:
`chain 800: first read = 799 in 19 ms`, `chain 1600: first read THROW
ProviderException (Stack Overflow inside) in 20233 ms`. Абсолютные времена
у меня меньше (20 с против 33 с), вывод тот же. Debug-ветку не перепрогонял.

#### S4. Много зависимых у одного провайдера: квадратичная работа.

Тяжесть: **Medium**. Место: `element.dart`/`provider_subscription.dart`,
удаление подписки из списка зависимых (`List.remove`), debug-проверки
`_assertValidInternalPauseState`. Упирается в реализацию (список вместо
связного списка/множества). Доказательство: `probe_scale.dart family N` —
`Provider.family`, каждый элемент смотрит на один корень; после изменения корня
перечитываем все. Product: 10 000 — 425 мс, 20 000 — 1730 мс, 100 000 —
`read each after update: 44438 ms`, `dispose: 5073 ms`. Debug: 10 000 —
обновление корня 2753 мс, перечитывание 9436 мс; 20 000 — 27180 мс и 81363 мс;
100 000 не уложилось в 240 с на первом же чтении. То же с подписками:
`listeners` — закрытие 40 000 подписок по порядку: product 3903 мс (10 000 —
158 мс), debug 36086 мс; добавление 40 000 в debug — 35766 мс. Предложение:
удаление за O(1) (индекс в подписке или связный список), debug-проверки
не линейные на операцию.

**Вердикт:** Подтверждено моим прогоном `probe_scale.dart` в product:
`family-watching 10000: read each after update: 298 ms`, `20000: … 1286 ms` —
рост ×4,3 при удвоении; `listeners 10000: close all, in order: 113 ms`,
`40000: … 2776 ms`. Debug и 100 000 не перепрогонял.

#### S5. Большая `family` без autoDispose: память растёт без границы, аргумент без `==` — утечка.

Тяжесть: **Medium** (модель, а не реализация). Доказательство:
`probe_scale.dart`: 100 000 элементов `Provider.family<int,int>` —
`rss +170 MB` в product (`+222 MB` в debug), ~1.7–2.2 КБ на элемент;
`invalidate(family)` — 58 мс, `dispose` — 168 мс (линейно, хорошо). `list` —
`1000 reads of fam([1,2,3]) -> 1000 builds (one element each, never disposed)`.
Линт `provider_parameters` ловит литерал списка, но только при установленном
`riverpod_lint`; в рантайме предупреждения нет. Предложение: debug-assert
на аргумент, у которого `==` — тождество, а тип — коллекция.

**Вердикт:** Принято по отчёту, не перепрогонял.

#### S6. Что хорошо масштабируется.

`probe_scale.dart updates`: миллион `state =` с одним слушателем и одним
производным провайдером — 426 мс в product (2016 мс в debug), производный
пересчитан один раз (`calls=1000001`); миллион `container.read` — 160 мс; 10
000 слушателей получают обновление за 7 мс.

**Вердикт:** Принято по отчёту, не перепрогонял.

### 7. Находки по документации

#### D1. README ядра показывает не этот пакет.

Тяжесть: **Medium**. Место: `packages/riverpod/README.md`, первый пример. Что
не так: чисто дартовый пакет открывается кодом с `@riverpod`
и `ConsumerWidget`, которых в нём нет; нет раздела установки и ни одной строки
с `ProviderContainer`; значки версий всех пакетов семейства показывают версию
`riverpod`. Пример `switch` по классам `AsyncValue` при ошибке 38 секунд
показывает загрузку (C1). Предложение: пример на `Provider` + `FutureProvider`
+ `ProviderContainer`, установка `dart pub add riverpod`, ссылка
  на `flutter_riverpod` одной строкой.

**Вердикт:** Принято по чтению.

#### D2. О цене повтора по умолчанию не сказано.

Тяжесть: **High**. Место: `concepts2/retry.mdx`, `how_to/testing.mdx`,
`3.0_migration.mdx` «Automatic retry». Что не так: миграция пишет «it will
automatically retry until it succeeds» — неверно, 10 попыток; нигде не сказано,
что во время повторов состояние — `AsyncLoading`, что `.future` ждёт 38 с, что
тест на ошибку нужно писать с `retry: (_, __) => null`. В `retry.mdx`
комментарий «Stop retrying on ProviderException» стоит не у той строки.
Доказательство: `probe_core.dart`, разделы 1, 2. Предложение: таблица
«попытка — задержка — состояние» и абзац в `testing.mdx`.

**Вердикт:** Подтверждено: `3.0_migration.mdx:25` — «it will automatically
retry until it succeeds», а `defaultRetry` останавливается после десяти попыток
(C1).

#### D3. `retry.mdx`: codegen-фрагменты с `MyProviderRef`.

Тяжесть: **Medium**. Место: `concepts2/retry.mdx`, строки 47, 109, 114. Тип
`XxxRef` генератор не выдаёт (`grep` по `*.g.dart` пуст; миграция сама пишет
«use `Ref` directly»). Фрагменты заданы строками в `.mdx`, а не файлами,
поэтому анализатор их не видит — вопреки правилу самого `CONTRIBUTING.md`.

**Вердикт:** Подтверждено по дереву: `MyProviderRef` в `concepts2/retry.mdx`,
строки 47, 109, 114.

#### D4. `pull_to_refresh.mdx`: проза о несуществующих членах.

Тяжесть: **Medium**. Место: `how_to/pull_to_refresh.mdx`, строки 111–123: «We
use `valueOrNull` here… Riverpod 3.0 will change this», `:final valueOrNull?`,
`AsyncValue(hasData: true, :final valueOrNull)`. В 3.5.0 нет ни `valueOrNull`,
ни `hasData` (`grep` по `lib/`: `hasData` только у внутреннего `$Result`). Код
рядом уже использует `value`.

**Вердикт:** Подтверждено по дереву: `how_to/pull_to_refresh.mdx:111–119` — «We
use `valueOrNull` here», «Riverpod 3.0 will change this».

#### D5. `3.0_migration.mdx`: код «After» не собирается.

Тяжесть: **Medium**. Место: раздел «Simplified Ref and removed Ref subclasses»,
строки 260 и 299: `state.valueOrNull`. Раздел «AutoDispose interfaces are
removed»: «replace of `AutoDispose` to ` `» превратит
`AutoDisposeProvider<int>((ref)…)` в не-autoDispose провайдер — время жизни
меняется молча, страница об этом не говорит.

**Вердикт:** Принято по чтению.

#### D6. `offline.mdx`: пример ручного сохранения падает в рантайме.

Тяжесть: **High**. Место:
`website/docs/concepts2/offline/manual_persist/raw.dart`.
`Storage<String, String>`, а `encode` возвращает `List`; тип выводится как
`Object`, код собирается. Доказательство: `probe_persist.dart`, P4:
`uncaught zone errors: [type 'List<Map<String,
String>>' is not a subtype of type 'String' of 'value']` — сохранение молча
не работает, ошибка уходит в зону. Страница также не предупреждает о C2, C3,
C4.

**Вердикт:** Подтверждено моим прогоном `probe_persist.dart`, P4:
`uncaught zone errors: [type 'List<Map<String,
String>>' is not a subtype of type 'String' of 'value']`.

#### D7. `3.0_migration.mdx`: рецепт `on ProviderException` вокруг `.future`.

Тяжесть: **Medium**. Место: «Provider failures are now rethrown as
ProviderExceptions». Зонд: `await container.read(failing.future)` —
`caught the original FormatException`; а там, где обёртка есть, через одно
звено зависимости `e.exception` — снова `ProviderException` (C5).
`ProviderException` экспортирован только из `misc.dart`, импорт в рецепте
не назван.

**Вердикт:** Подтверждено, см. вердикт B5.

#### D8. Шаблон «сначала значение» прячет ошибку обновления.

Тяжесть: **Medium**. Место: `tutorials/first_app.mdx` «Handling loading and
error states», `how_to/pull_to_refresh.mdx`. `case AsyncValue(:final value?)`
первым — после неудачного `invalidate` пользователь видит старую шутку
и ни слова об ошибке; учебник заканчивается фразой «we have handled all
edge-cases». Тот же шаблон не работает для `AsyncValue<T?>` (есть линт
`async_value_nullable_pattern`, но он не обязателен). По чтению.

**Вердикт:** Принято по чтению.

#### D9. Парные вкладки неэквивалентны по времени жизни

— S2. Место: `concepts2/refs.mdx`, `providers.mdx`, `family.mdx` и др.

**Вердикт:** Подтверждено, см. вердикт B11.

#### D10. `providers.mdx`: блок «Do this instead» без `return`.

Тяжесть: **Low**. `Future<int> build() { state = …; }` не собирается; фраза
«тип `Ref` определяется именем функции» устарела.

**Вердикт:** Принято по чтению.

#### D11. `refs.mdx`: оборванная фраза

«check if a provider currently is loaded or»; нет `ref.mounted`, хотя миграция
делает его обязательным после `await`.

**Вердикт:** Принято по чтению.

#### D12. `getting_started`: `dart_pubspec.tsx` с `sdk: ^3.7.0`.

Тяжесть: **Medium**. `riverpod` 3.5.0 требует `^3.12.0`, `riverpod_lint` —
`>=3.13.0-0`. Новичок на вкладке «Dart only» получит отказ разрешения версий
(или старый `riverpod`). Flutter-вкладка (`pubspec.tsx`) уже `^3.12.0`.

**Вердикт:** Подтверждено по дереву: `getting_started/dart_pubspec.tsx` —
`sdk: ^3.7.0` дважды, `pubspec.yaml` ядра — `sdk: ^3.12.0`.

#### D13. Битый якорь `enabling-riverpod_lintcustom_lint`

в `family.mdx` и `do_dont.mdx`; в `consumers.mdx` якорь
`enabling-riverpod_lint`.

**Вердикт:** Принято по чтению.

#### D14. `auto_dispose.mdx`: «waits for one frame (cf. `await null`)».

В чистом Dart это `Timer(Duration.zero)` (`scheduler.dart:36`), то есть
не микрозадача: `await null` в тесте уничтожения не дождётся. Тяжесть: **Low**.

**Вердикт:** Принято по чтению.

#### D15. dartdoc с ошибками.

`Ref.watch` — пример `[...todos].sort(...)` (возвращает `void`);
`List<Todo>> build()`; `Mutation` — `deleteTodo(todo.id).run`
и `deleteMutation` против `deleteTodoMutation`;
`ProviderObserver.didUpdateProvider` — искажённый текст («///mutation», пустые
`[]`); `retrying` (C14). По чтению.

**Вердикт:** Принято по чтению.

#### D16. README `riverpod_annotation` — две строки

, отсылающие к `riverpod_generator`; `packages/riverpod/example` требует ключи
Marvel API и `configuration.json` — запустить его «чтобы посмотреть» нельзя.

**Вердикт:** Принято по чтению.

#### D17. `mutations.mdx`

показывает `run` без `await` и не говорит о C7.

**Вердикт:** Принято, см. вердикт C7.

### 8. Для ИИ-агентов

#### A1. `switch` по `AsyncData`/`AsyncError`/`AsyncLoading` из README.

Собирается, исчерпывающий, при ошибке 38 секунд идёт в ветку loading. Ничто
не предупреждает. См. C1, D1.

**Вердикт:** Подтверждено, см. вердикт C1.

#### A2. `ref.watch` в методе notifier.

Тяжесть: **Medium**. `probe_core.dart`, раздел 25:
`ref.watch in method: no error; state=2`, затем
`after other changed: state=0 builds=2` — метод молча подписал провайдер
на пересборку, состояние сброшено. Линта нет (в списке правил `riverpod_lint`
16 имён, такого нет), assert нет. Предложение: assert «watch вне build».

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 25:
`ref.watch in method: no error; state=2`,
`after other changed: state=0 builds=2`.

#### A3. `ref.listen` в методе notifier копит слушателей.

Тяжесть: **Medium**. `probe_agent.dart`:
`[ref.listen in a method x3, one change] callbacks=3`. Ни линта,
ни предупреждения.

**Вердикт:** Подтверждено моим прогоном `probe_agent.dart`:
`[ref.listen in a method x3, one change] callbacks=3`.

#### A4. `container.read(autoDisposeProvider.notifier).method()`

— C11/S2: состояние живёт до следующего цикла событий. Исключение при повторном
вызове на старом экземпляре (`UnmountedRefException`) текстом объясняет
причину — это хорошо; первый, «успешный» вызов не объясняет ничего.
`testing.mdx` предупреждает, остальные страницы нет.

**Вердикт:** Подтверждено, см. вердикты B11 и C11.

#### A5. `state.add(x); state = state;`

— `probe_core.dart`, раздел 21: `notified=0 state=[1]`. Самая частая ошибка
с изменяемыми коллекциями; ни assert (сравнение `identical` при присваивании
ловится тривиально), ни линта.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`, раздел 21:
`notified=0 state=[1]`.

#### A6. Список/запись со списком как аргумент `family`

— S5. Ловит только `riverpod_lint`, и только литерал.

**Вердикт:** Принято, см. S5.

#### A7. Подсказка анализатора ведёт к ошибке

— B2: `Use ref.read/watch/listen(provider.exist)` → `exist` не существует.

**Вердикт:** Подтверждено, см. вердикт B2.

#### A8. Устаревшие имена в страницах

— D3, D4, D5: агент, читающий страницы, напишет `valueOrNull`, `MyProviderRef`,
`hasData`. Здесь анализатор ловит, но текст ошибки («getter isn't defined»)
не говорит, чем заменить.

**Вердикт:** Подтверждено, см. вердикты D3 и D4.

#### A9. Изменение другого провайдера из `build`

— C12: в чистом Dart молча работает, `do_dont.mdx` запрещает.

**Вердикт:** Подтверждено, см. вердикт C12.

#### A10. Что ловится хорошо.

`state` в конструкторе notifier: `Tried to use a notifier in an uninitialized
state… move your logic inside the "build" method`; scoped-зависимость без
`dependencies`: `To fix, add Provider<int>#… to …'s 'dependencies' parameter`;
`requireValue` в загрузке: `AsyncValueIsLoadingException` с текстом; чтение
из уничтоженного контейнера:
`Tried to read a provider from a ProviderContainer that was already disposed`.
Провайдер, который смотрит на себя, в debug даёт `CircularDependencyError`
с цепочкой.

**Вердикт:** Подтверждено моим прогоном `probe_agent.dart`: тексты для `state=`
в конструкторе, `requireValue` в загрузке и чтения из уничтоженного контейнера
совпадают с отчётом.

### 9. Что сделать для 10/10

**Код (6.5 → 10).**
1. Повтор выключен по умолчанию или не касается синхронных провайдеров,
   а состояние ожидания повтора видно как ошибка (C1, B1, B7): +1.0.
2. `persist`: живой страж, ошибка не стирает кеш, синхронный notifier
   восстанавливается (C2, C3, C4): +0.75.
3. Один тип ошибки на всех путях чтения, без вложения (C5, B5): +0.5.
4. Итеративная сборка зависимостей и удаление подписки за O(1) (S3, S4): +0.5.
5. Страж цикла в релизе (C9), копия списка в `_runCallbacks` (C6): +0.25.
6. Политика одновременных мутаций и отсутствие двойной ошибки (C7), защита
   ручного `state` от позднего `build` (C8): +0.25.
7. Чистка имён и зависимостей (B2, B3, B4, B8, B9, B12, B13): +0.25.

**Тесты (8 → 10).**
1. Тест `persist` с настоящим асинхронным `read` (T1): +0.75.
2. Замена теста, закрепляющего удаление кеша (T2): +0.5.
3. Тесты масштаба с порогом: цепочка 5000, 50 000 зависимых, 50 000 подписок
   (T3): +0.5.
4. Тест на колбэк, снимающий себя (T4): +0.25.

**Документация (5.5 → 10).**
1. README ядра на чистом Dart с установкой и `ProviderContainer`; README
   `riverpod_annotation` с примером (D1, D16): +0.75.
2. Все фрагменты — файлами под анализатором, как требует `CONTRIBUTING.md`; это
   разом снимает D3, D4, D5, D6, D10: +1.25.
3. Правда о повторе: состояния, 38 секунд, тесты (D2): +0.75.
4. Правда об ошибках: какой тип где приходит (D7): +0.5.
5. Пары вкладок эквивалентны по времени жизни либо явно помечены (D9): +0.5.
6. Шаблон отображения, который не прячет ошибку обновления (D8): +0.25.
7. Мелочи: `sdk`, якоря, оборванная фраза, `ref.mounted`, dartdoc, CHANGELOG
   (D11–D15, B2): +0.5.

**Для ИИ-агентов (5 → 10).**
1. Debug-assert на `ref.watch` вне `build` и на `ref.listen` в методе без
   снятия (A2, A3): +1.0.
2. Debug-assert `identical(old, new)` при `state =` для изменяемых коллекций
   и на аргумент `family` без `==` (A5, A6): +0.75.
3. Ошибка остаётся ошибкой при повторе, так что `switch` из README верен (A1):
   +1.0.
4. Одно умолчание времени жизни (A4, B11): +0.75.
5. Документы под анализатором и верные тексты депрекаций (A7, A8): +1.0.
6. Страница «частые ошибки и их сообщения» — тексты исключений с лечением
   в одном месте: +0.5.

**Общая (6.5 → 10)** складывается из названного: умолчания без сюрпризов
(повтор, время жизни) +1.5; `persist` без потери данных +0.5; документация под
анализатором и README своего пакета +1.0; масштаб без квадратов и рекурсии
+0.5.

### 10. Страницы

| Страница | Читаемость | Почему | Что сделать для 10 |
|---|---|---|---|
| `packages/riverpod/README.md` | 4 | Показывает Flutter и codegen, нет установки, значки не свои | D1 |
| `packages/riverpod_annotation/README.md` | 2 | Две строки и ссылка | Пример `@riverpod`, список аннотаций, что импортировать |
| `introduction/getting_started.mdx` | 7 | Есть вкладка Dart only и hello world; `sdk: ^3.7.0` | D12, якорь линта |
| `tutorials/first_app.mdx` | 8 | Последовательно, до работающей программы; шаблон прячет ошибку обновления, не сказано про 38 с | D8, абзац о повторе |
| `concepts2/providers.mdx` | 6 | Обзор хороший; блок без `return`, устаревшая фраза о `Ref`, нет слова о жизни экземпляра notifier | D10, C11 |
| `concepts2/consumers.mdx` | 8 | Коротко и по делу; для ядра не нужна | Пометка «только Flutter», якорь |
| `concepts2/containers.mdx` | 7 | Понятно; мало о `ProviderContainer.test` и `pump` | Пример теста |
| `concepts2/refs.mdx` | 6 | Оборванная фраза, нет `ref.mounted`, пары неэквивалентны | D11, D9 |
| `concepts2/auto_dispose.mdx` | 7 | Модель объяснена; «`await null`» неверно для Dart | D14, пример с `read` |
| `concepts2/family.mdx` | 7 | Предупреждает о `==`; битый якорь | D13, слово о памяти (S5) |
| `concepts2/mutations.mdx` | 5 | `run` без `await`, нет политики одновременных запусков | D17, C7 |
| `concepts2/offline.mdx` | 4 | Пример падает, три ловушки не названы | D6, C2–C4 |
| `concepts2/retry.mdx` | 4 | `MyProviderRef`, не сказано о состоянии и длительности | D2, D3 |
| `concepts2/observers.mdx` | 7 | Достаточно; dartdoc `didUpdateProvider` искажён | D15 |
| `concepts2/overrides.mdx` | 7 | Ясно | Слово об `overrideWith2` |
| `concepts2/scoping.mdx` | 7 | Честно говорит, что сложно | Пример ошибки `dependencies` с её текстом |
| `concepts/about_code_generation.mdx` | 6 | Совет «только если уже используете codegen» спорит с README и вкладками по умолчанию | Таблица различий, в т.ч. autoDispose |
| `how_to/testing.mdx` | 7 | Предупреждает об autoDispose+`read` | Абзац о `retry` в тестах |
| `how_to/select.mdx` | 8 | Коротко, верно | — |
| `how_to/eager_initialization.mdx` | 7 | Понятно, только Flutter | Вариант для `ProviderContainer` |
| `how_to/pull_to_refresh.mdx` | 4 | Проза о `valueOrNull`/`hasData`, шаблон прячет ошибку | D4, D8 |
| `how_to/cancel.mdx` | 7 | Рабочий рецепт | `ref.mounted` после `await` |
| `root/faq.mdx` | 7 | Отвечает на реальные вопросы | Вопрос «почему ошибка не показывается» |
| `root/do_dont.mdx` | 7 | Полезный список; запреты не подкреплены assert'ами, битый якорь | D13, C12 |
| `3.0_migration.mdx` | 5 | `valueOrNull` в «After», неверно о `ProviderException` и «until it succeeds» | D2, D5, D7 |

### 11. Что хорошо и трогать не надо

- Ленивая пересборка: миллион обновлений — один пересчёт производного.
- Тексты исключений жизненного цикла (`UnmountedRefException`, scoped
  `dependencies`, «uninitialized notifier») — с причиной и лечением.
- Фильтр обновлений по `==` единый для всех провайдеров, с `updateShouldNotify`
  как выходом.
- `Ref` без параметра типа и без подклассов; отсутствие `XxxRef` в codegen.
- Вынос `StateProvider`/`StateNotifierProvider` в `legacy.dart`.
- `invalidate(family)` и `dispose` линейны и быстры на 100 000 элементов.
- Набор тестов: быстрый, с говорящими именами, ловит точечные мутации.
- `ProviderDisposedException` вместо `StateError` у `.future`.
- Структура `concepts2/`: одна страница — одно понятие.

### 12. ПРОГОН

Все команды — из копии, с `PATH=/Users/user/fvm/versions/master/bin:$PATH`
и `TMPDIR=<копия>/.review-tmp`, каталог `packages/riverpod`, если не сказано
иное.

| Команда | Последняя строка вывода |
|---|---|
| `dart test` (до мутаций) | `00:12 +1647 ~5: All tests passed!` |
| `python3 .review-tmp/mutate.py` (16 записей, на каждую `dart test` с пределом времени; журнал `.review-tmp/mutations.log`) | `DONE` |
| — m01 внутри него | `00:14 +1647 ~5: All tests passed!` |
| — m02…m12, m14…m16 | `For example, 'dart test --chain-stack-traces'.` (набор красный; числа упавших — в таблице мутаций) |
| `dart run test/probe_core.dart` | `retrying=true isLoading=true type=AsyncLoading<int> progress=null` |
| `dart run test/probe_persist.dart` | `result -1` |
| `dart run test/probe_agent.dart` (первый запуск) | ошибка компиляции моего зонда: `'ProviderException' isn't a type.` — тип не экспортирован из `riverpod.dart` |
| `dart run test/probe_agent.dart` (после правки зонда) | `[override on child of non-scoped provider] OK -> 0` |
| `dart run test/probe_cycle.dart` | `  Provider<` (вывод обрезан мной по ширине; строка выше — `The circular dependency chain is as follows:`) |
| `dart run -Ddart.vm.product=true test/probe_cycle.dart` | трасса `StackOverflowError`, последняя строка `#10660  _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:192:12)`; содержательная — `late ring: StackOverflowError: Stack Overflow` |
| `dart run test/probe_scale.dart <chain\|listeners\|family\|updates\|list>` (первый запуск) | ошибка компиляции моего зонда: `getAllProviderElements` не существует |
| `dart run test/probe_scale.dart chain` (debug) | `Unhandled exception:` / `Stack Overflow`, код выхода 255 |
| `dart run test/probe_scale.dart listeners` (debug) | `listeners 40000: close all, in order: 36086 ms` |
| `dart run test/probe_scale.dart family` (debug, 100 000) | `family 100000: dispose: 429 ms`, затем снят по пределу 240 с (код 142) на `family-watching` |
| `dart run test/probe_scale.dart family 10000` / `20000` (debug) | `family-watching 10000: dispose: 2442 ms` / `family-watching 20000: dispose: 17992 ms` |
| `dart run test/probe_scale.dart updates` (debug) | `reads 1000000: container.read of a mounted provider: 673 ms` |
| `dart run test/probe_scale.dart list` (debug) | `list-arg family: 1000 reads of fam([1,2,3]) -> 1000 builds (one element each, never disposed)` |
| `dart run -Ddart.vm.product=true test/probe_scale.dart listeners` | `listeners 40000: close all, in order: 3903 ms` |
| `… probe_scale.dart family 10000` / `20000` / `100000` (product) | `family-watching 10000: dispose: 83 ms` / `… 20000: dispose: 290 ms` / `… 100000: dispose: 5073 ms` |
| `… probe_scale.dart updates` (product) | `reads 1000000: container.read of a mounted provider: 160 ms` |
| `dart run test/probe_chain.dart 50 100 200 400` (debug) | `chain 400: dispose in 3 ms` |
| `dart run test/probe_chain.dart 600`, `800` (debug) | `chain 600: dispose in 12 ms`, `chain 800: dispose in 15 ms` |
| `dart run -Ddart.vm.product=true test/probe_chain.dart 400`, `800`, `1600`, `3200` | `chain 400: dispose in 9 ms`; `chain 800: dispose in 9 ms`; `chain 1600: first read THROW ProviderException (Stack Overflow inside) in 32699 ms`; `chain 3200: first read THROW ProviderException (Stack Overflow inside) in 38655 ms` |
| `dart test` в `packages/riverpod_generator` | `00:09 +83 ~1: All tests passed!` |
| `git status --short` (в конце) | `?? packages/riverpod/test/probe_scale.dart` (всего: `.review-tmp/` и `probe_agent`, `probe_chain`, `probe_core`, `probe_cycle`, `probe_persist`, `probe_scale`) |

Оговорки о прогоне:

- Времена — один прогон на машине, занятой другими задачами (часть зондов шла
  одновременно с набором генератора); это порядки величин, а не замеры. Вывод
  о квадратичности опирается на отношение времён при росте N,
  а не на абсолютные числа.
- Мутации m05 и m13 не применились (m13 — намеренно); в счёт не идут.
- Находки с пометкой «по чтению» зондом не проверялись.

Не запускал: `flutter test` и всё, что требует Flutter-виджетов (страницы для
Flutter проверены только через `ProviderContainer`); `build_runner`
на собственном коде — вид сгенерированного кода взят из закоммиченных
`packages/riverpod_generator/test/integration/*.g.dart`; `dart analyze`
с `riverpod_lint` на зондах — о линтах сужу по списку правил
в `packages/riverpod_lint/lib/src/lints/`; сборку сайта; `scripts/check.sh`.

Конфликт с правилами репозитория: `CONTRIBUTING.md` требует, чтобы у каждого
файла `lib/` был тест по тому же пути и чтобы изменение `lib/**/x.dart` шло
с изменением `x_test.dart`, а перед PR советует завести issue. Задание
запрещает менять отслеживаемые файлы и открывать issues; зонды лежат как
`test/probe_*.dart`, не по схеме имён репозитория. Выиграло задание.

## Отчёт Astra

### 1. Оценки

Ревью `riverpod` 3.5.0, `riverpod_annotation` 4.0.8 и `riverpod_generator`
4.0.10 на коммите `7a02bedc149ef35311d856993e5bb76e528dd036`. Основание — код
и документация этой копии, штатные тесты, восемь мутаций и собственные зонды.
Внешние отзывы, обсуждения и issues не использовались.

| Объект | Оценка | Что подняло | Что опустило |
|---|---:|---|---|
| В целом | **6,5/10** | Рабочее ядро зависимостей, изоляция контейнеров, управляемое владение подписками, полезная генерация | Потеря сохранённых данных в экспериментальном API; ошибки в рекомендуемых примерах; слишком много неочевидных условий правильного использования |
| Код | **7/10** | Проверенные обновления графа, подавление устаревшего результата async build, работающие keepAlive и autoDispose, информативная ошибка мёртвого Ref | Гонки persistence, коллизии ключей генератора, прерывание очистки ресурсов, различающиеся контракты sync/async ошибок |
| Тесты | **7,5/10** | 1647 проходящих тестов ядра; шесть из восьми мутаций пойманы; 84 теста генератора с проверкой эталонов проходят | Не моделируют несколько реальных расписаний асинхронного хранилища; пропускают изменение срока хранения; часть тестов закрепляет спорное поведение |
| Документация | **5/10** | Оба Dart hello world запускаются; хорошие объяснения containers, select, testing и отмены запроса | Рядом существуют примеры разных поколений API; пример offline падает во время исполнения; миграция даёт недостаточную защиту от старого build |
| Для ИИ-агентов | **5,5/10** | Явные сигнатуры, небольшие изолированные тесты, полезные сообщения ряда исключений | Правдоподобные ошибки компилируются; анализатор не проверяет бизнес-смысл lifecycle; линтер и документация иногда направляют к неверному исправлению |

Общая оценка — оценка пригодности всего заданного объёма, включая объявленные
экспериментальные возможности. Это не среднее арифметическое строк.
Экспериментальный статус объясняет нестабильность API, но не устраняет
последствия потери данных. Шаги и прибавки для каждой оценки — в разделе 9; для
отдельных страниц — в разделе 10.

### 2. Сводка

- Основная модель зависимостей работоспособна: ромб обновился согласованно,
  устаревший результат build не заменил новый.
- AutoDispose удалил все 30 000 проверенных состояний family; несколько
  keepAlive-ссылок корректно удерживают состояние до закрытия последней.
- Поздний ответ хранилища заменяет новое состояние старым; у AsyncNotifier он
  способен вернуть уже завершённую загрузку в вечный loading.
- Ошибка обновления удаляет последний сохранённый результат, хотя он ещё виден
  в памяти.
- Генератор строит неуникальные ключи persistence для разных строковых
  аргументов family.
- Снятие обработчика из собственного onDispose прерывает последующую очистку
  ресурсов.
- Наборы тестов сильнее всего защищают известные переходы состояния; реальные
  перестановки асинхронных операций защищены хуже.
- Документация позволяет начать, но не обеспечивает непротиворечивого пути
  до обновления, отмены и offline.
- Все временные изменения отслеживаемых файлов восстановлены копиями;
  исправления продукта не вносились.

### 3. На следующий мажор

Перечисленные ниже изменения API требуют решения о совместимости. Дефекты C1–C6
можно исправлять отдельно, не дожидаясь мажора.

#### B1. Единая политика времени жизни.

Место: `packages/riverpod/lib/src/providers/` — конструкторы семейств
провайдеров; `riverpod_annotation/lib/src/riverpod_annotation.dart` —
`Riverpod.keepAlive`. Ручная запись по умолчанию удерживает состояние,
`@riverpod` по умолчанию удаляет его без слушателей. Выбор способа записи
меняет поведение программы. Предлагаю одинаковый default и явно именованную
политику хранения; неограниченные family должны требовать осознанного
удержания. Сломает код, рассчитывающий на сегодняшние defaults; нужен
автоматический перенос с явным параметром, сохраняющим прежнее поведение.
Доказательство: конструкторы по чтению; `probe_codegen.dart` печатает
`codegen-default autoDispose=true`; масштаб — S2.

**Вердикт:** Подтверждено моим прогоном `probe_codegen.dart`:
`codegen-default autoDispose=true`. То же у Fable (B11).

#### B2. Ref конкретного запуска build.

Место: `lib/src/core/provider/notifier_provider.dart` — `AnyNotifier.ref`;
`lib/src/core/ref.dart` — `Ref.mounted`. Getter notifier возвращает текущий
Ref, включая Ref следующего build. Проверка после await поэтому может проверять
чужое поколение. Предлагаю передавать в build неизменный контекст запуска либо
явный токен актуальности; текущий Ref объекта именовать отдельно. Сломает
сигнатуры build и генерацию, но допускает механическую миграцию.
Доказательство: `probe_core.dart`, D2. Сам нынешний `Ref.mounted` для
захваченного Ref работает правильно.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`:
`stale-notifier effects=[build=1 current=true captured=true,
build=0 current=true captured=false] final=200`. Зонд честный: старый `build`
после `await` проверяет `if (!ref.mounted)`, геттер `ref` notifier уже отдаёт
`Ref` нового запуска, и проверка пропускает старое тело к побочному эффекту.
Захваченный `Ref` при этом верно говорит `mounted=false`. У Fable этой находки
нет.

#### B3. Единый контракт ошибки и завершения `.future`.

Место: `lib/src/common/stack_trace.dart`, `lib/src/core/element.dart`,
`lib/src/core/provider_container.dart` — `ProviderException`,
`ProviderDisposedException`, `read`, `.future`, `defaultRetry`. Синхронное
чтение оборачивает ошибку, await выдаёт исходную; это влияет и на retry
зависимых провайдеров. Pending Future после disposal может вернуть значение,
а pending Stream.future — ошибку disposal. Нужно явно выбрать единый контракт
либо разделить операции по именам и типам; экспортировать предназначенные для
catch исключения из основного barrel. Сломает существующие catch и ожидание
результата после disposal; нужен переходный unwrap и документированная отмена.
Доказательства: `probe_lifecycle.dart`, `probe_retry.dart`, D3. Это предложение
дизайна; нынешний возврат результата Future поддерживается собственными
тестами.

**Вердикт:** Подтверждено моими прогонами: `probe_lifecycle.dart` —
`sync-error type=ProviderException`,
`future-error type=_Exception wrapped=false`, `future-dispose result=99`,
`stream-dispose type=ProviderDisposedException`; `probe_retry.dart` —
`async-dependency parent=1 child=3`. Типы ошибок — то же у Fable (B5, C5).

#### B4. Разделить наличие данных, ход работы и результат попытки.

Место: `lib/src/core/async_value.dart` — `AsyncValue`, `AsyncResult`,
extensions; `lib/src/core/ref.dart` — `invalidate(asReload:)`. Три привычных
имени Data/Loading/Error скрывают сочетания старого значения, новой ошибки,
повторной загрузки и данных из cache. `asReload` звучит как выбор операции,
а его dartdoc обещает очистку, которой нет. Предлагаю согласованный snapshot
с отдельными признаками и явно названную политику показа предыдущих данных,
сохранив удобные pattern matching и requireValue. Сломает часть switch, when
и именованных аргументов. Доказательство: `probe_lifecycle.dart` печатает
`asReload value=1 hasValue=true isReloading=true`; остальные комбинации —
по чтению реализации и тестов.

**Вердикт:** Подтверждено моим прогоном `probe_lifecycle.dart`:
`asReload value=1 hasValue=true isReloading=true`. Остальное — по чтению.

#### B5. Явный результат и область действия Mutation.

Место: `lib/src/core/mutations.dart` — `Mutation.run`, `reset`,
`MutationTransaction.get`. Run одновременно публикует Error и возвращает
бросающий Future; reset сбрасывает представление, но не останавливает эффект.
Предлагаю различить операцию с возвращаемым результатом и вариант, который
бросает, назвать сброс состояния явно и документировать политику конкурентных
запусков. Проверять закрытую транзакцию во всех режимах. Реальная отмена
требует токена, который использует операция. Сломает сигнатуры и обработку
результата; запрет утечки транзакции — защитная правка. Доказательство:
`probe_core.dart`, C6, D5.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`:
`mutation errorState=true uncaught=[Exception: failed]`,
`mutation reset idle=true effect=true`. Двойной канал ошибки — то же у Fable
(C7).

#### B6. Persistence как типизированный протокол.

Место: `lib/src/core/persist.dart`, `NotifierPersistX.persist`;
`riverpod_annotation/lib/experimental/{persist,json_persist}.dart`;
`riverpod_generator/lib/src/json_generator.dart`. Предлагаю объект codec,
связывающий тип Storage с encode/decode, устойчивый формат ключей, определённый
порядок записи и явную политику восстановления/ошибок. `PersistResult.future`
сейчас описывает только декодирование; для гарантии записи нужен отдельный
flush/результат. Сломает вызовы persist и формат ключей; обязательна миграция
существующей базы. Доказательства: C1–C4, D1. Для произвольного
пользовательского типа ключа лучше требовать codec, чем молча использовать
toString.

**Вердикт:** Принято; дефекты, на которые опирается, подтверждены в вердиктах
C1–C4 и D1.

#### B7. Отдельно обозначить scoping и вычислительные зависимости.

Место: `lib/src/core/provider_container.dart`, параметры `dependencies`;
аннотации `Riverpod.dependencies`, `Dependencies`. Отсутствие списка
не означает автоматическое наследование всех override в child container:
зависимый provider может остаться в root. Предлагаю явный тип/маркер scoped
provider и проверку недопустимого пересечения областей в runtime. Сломает часть
declarations и размещение состояния по контейнерам; миграция должна сохранить
прежнюю область. Доказательство: `probe_scope.dart` даже с assertions печатает
`scope source=child derived=root derived`; с объявленными зависимостями —
`scope declared=child derived`.

**Вердикт:** Подтверждено моим прогоном `probe_scope.dart` с assert:
`scope source=child derived=root derived`, с объявленными зависимостями —
`scope declared=child derived`. У Fable этой находки нет.

#### B8. Упорядочить экспорт и убрать временные имена.

Место: `riverpod.dart`, `misc.dart`, `legacy.dart`, `riverpod_annotation.dart`;
family `overrideWith2`, `ProviderTransformer2`, `SyncProviderTransformer2`.
Общие типы сигнатур и catch-исключения распределены между barrels, а annotation
одновременно является пользовательским API и мостом к внутренним классам
генератора. Предлагаю основные типы сигнатур экспортировать рядом
с использующими их API; расширения генератора/трансформеры вынести в явную
интеграционную библиотеку, убрать суффикс 2 после удаления старого API. Сломает
импорты и имена extension-кода; нужны re-export-переходники. `legacy.dart`
оставить отдельным совместимым входом. Доказательство: по чтению экспортов;
переименование family уже обещано changelog 3.2.0.

Проверенный публичный периметр:

| Библиотека | Проверенные экспорты и решение |
|---|---|
| `riverpod.dart` | Все шесть видов Provider и соответствующие Notifier/AnyNotifier — B1–B3; AsyncValue/Data/Loading/Error/Result, extensions и AsyncValueIsLoadingException — B4; Container, Ref — B2/B7; ProviderReference, Observer/ObserverContext, Subscription, select и listenable — сохранить, исправляя отдельные контракты и документацию |
| `misc.dart` | Все шесть ProviderFamily, Family, ProviderBase, ProviderOrFamily, ProviderListenableOrFamily, Refreshable, ProviderListenable, AsyncProviderListenable, Override, KeepAliveLink — B1/B7/B8; ProviderException/ProviderDisposedException — B3; CustomProviderListenable, оба поколения Transformer, TransformerContext, SyncProviderTransformerMixin и WhenComplete — B8; оба debugTrack-флага — оставить выключенными по умолчанию |
| `legacy.dart` | StateNotifier, StateController, StateNotifierProvider/Family и StateProvider/Family — оставить изолированными, не расширять первый учебный маршрут |
| `experimental/mutation.dart` | Mutation, Transaction, Target и все пять экспортированных типов состояния — B5, C6 |
| `experimental/persist.dart` | Storage, StorageOptions, StorageCacheTime, PersistedData, NotifierPersistX, PersistResult — B6; имя unsafe_forever полезно подчёркивает обязанность очистки |
| `riverpod_annotation.dart` | Riverpod/riverpod, ProviderFor, Raw, MissingScopeException, FutureOr, публичные re-export — B1/B7/B8; весь мост `$…`, ProviderElement и WhenComplete — отделить от рекомендуемой поверхности пользователя |
| `riverpod_annotation/experimental/*` | JsonPersist, RiverpodPersist, Dependencies, re-export persistence, `$jsonCodex` — B6–B8; контракт стороннего генератора с `_$NameBase` сохранить явным |

Последние записи changelog сверены с реализацией, экспортами, pubspec
и тестами. В 3.5.0 подтверждаются новый конструктор
AsyncValueIsLoadingException, debug-экспорты, улучшенный текст ошибки
`.listenable`, защита observer после disposal и очистка устаревших stream
зависимостей по чтению соответствующего кода/тестов. В 3.4.3 подтверждается
переход на test_api. У generator 4.0.10 и annotation 4.0.8 сверены ограничения
зависимостей; набор генератора с эталонами прошёл. Неточности `.exist`
и ProviderDisposedException вынесены в D3/D4. Flutter/DevTools-изменения
из общего changelog отдельно в приложении не воспроизводились.

**Вердикт:** Принято по чтению; `overrideWith2` и имена с цифрой — то же
у Fable (B3, B13).

### 4. Находки по коду

Пути `lib/...` здесь относятся к `packages/riverpod`. Зонды находятся
в `packages/riverpod/test/probe_*.dart`, генераторные —
в `packages/riverpod_generator/test/`. Полные выводы —
в `.review-tmp/<имя-прогона>.log`.

#### C1 — High. Позднее восстановление затирает новое состояние.

Место: `lib/src/core/provider/notifier_provider.dart:249–286`,
`NotifierPersistX.persist`, `_setStateFromValue`. Флаг didChange
устанавливается только на время обработки очередного изменения и сразу
сбрасывается. Когда асинхронный read завершится позже, он уже false. Полученные
из базы старые данные без проверки поколения устанавливаются поверх свежих;
async-вариант всегда создаёт AsyncLoading. `probe_persist.dart` задерживает
read до записи 200 и получает `late-sync after=7 disk=7 writes=[100, 200, 7]`.
После уже завершённого сетевого Future со значением 200 получает
`AsyncLoading<int>(value: 7, valueSource: cache)`, `loading=true`. После
dispose завершение read даёт `late-disposed errors=[UnmountedRefException]`.
Предлагаю захватывать Ref/поколение и монотонную ревизию состояния перед read;
применять восстановление только к актуальному, ещё не заменённому состоянию.
Завершённую live-загрузку не превращать в loading.

**Вердикт:** Подтверждено моим прогоном `probe_persist.dart`:
`late-sync after=7 disk=7 writes=[100, 200, 7]`,
`late-async network=200 state=AsyncLoading<int>(value: 7,
valueSource: cache) loading=true`,
`late-disposed errors=[UnmountedRefException]`. Механику стража сверил по коду,
см. вердикт C2 Fable; то же у Fable (C2).

#### C2 — Medium. Асинхронные записи могут закончиться в обратном порядке.

Место: тот же файл, `persist`/`_callEncode`; `lib/src/core/persist.dart`,
`Storage.write`. Каждое изменение независимо запускает Future записи,
предыдущая запись не ожидается. Контракт Storage допускает Future и не требует
сериализации. Законный асинхронный backend может завершить старую запись
последней. `probe_persist.dart` завершает запись 200 перед 100:
`write-order state=200 disk=100 writes=[100, 200]`. Предлагаю очередь операций
на ключ, включая delete, либо явно заданный протокол версий/CAS. Это доказано
для пользовательского Storage; поведение очереди SQLite здесь не проверялось.

**Вердикт:** Подтверждено тем же прогоном:
`write-order state=200 disk=100 writes=[100, 200]`. У Fable этой находки нет.

#### C3 — High. Ошибка загрузки удаляет рабочий offline-cache.

Место: `lib/src/core/provider/notifier_provider.dart:318–328`,
`$AsyncNotifierBase._callEncode`. Ветка AsyncError безусловно вызывает
Storage.delete, даже если AsyncValue содержит ранее сохранённое значение.
`probe_persist.dart` кладёт 7 в Storage.inMemory, затем завершает сетевой
запрос ошибкой при отключённом retry: до ошибки `disk=7`, после
`offline after=7 disk=null error=true`. Следующий запуск уже не сможет
восстановить эти данные. Сохранить последний успешный cache до истечения срока,
явного удаления или несовместимой схемы; удаление при ошибке сделать явно
выбираемой политикой. Это существующее намеренно тестируемое поведение, но оно
противоречит практической задаче offline-данных.

**Вердикт:** Подтверждено тем же прогоном: `offline before=7 disk=7`,
`offline after=7 disk=null error=true`. То же у Fable (C3).

#### C4 — High. Сгенерированный ключ смешивает данные разных family.

Место: `packages/riverpod_generator/lib/src/json_generator.dart:65–69`,
генерация `resolvedKey` для `@JsonPersist`. Аргументы превращаются в строку
через представление record, без однозначного кодирования границ.
`probe_generate.dart` запускает настоящий генератор, затем `probe_codegen.dart`
последовательно открывает два контейнера с общей базой. Аргументы
`('x, y', 'z')` и `('x', 'y, z')` дают
`providersEqual=false keysEqual=true key=ProbeKey((x, y, z))`. Второй provider
возвращает `x, y|z`, ожидаемое его собственное значение — `x|y, z`.
Debug-проверка одновременных одинаковых ключей не защищает разные запуски
приложения. Нужен устойчивый однозначный codec ключа и стратегия переноса уже
записанных ключей.

**Вердикт:** Подтверждено моим прогоном `probe_codegen.dart` на коде, который
сгенерировал её `probe_generate.dart`:
`codegen-key providersEqual=false keysEqual=true key=ProbeKey((x, y, z))`,
`first=x, y|z second=x, y|z expectedSecond=x|y, z`. По коду генератора:
`json_generator.dart` строит ключ как `'${provider.name}($args)'`, где `args` —
запись аргументов, а запись `('x, y', 'z')` печатается так же, как
`('x', 'y, z')`. Генератор сам не перезапускал. У Fable этой находки нет.

#### C5 — Medium. Снятие onDispose прерывает освобождение следующих ресурсов.

Место: `lib/src/core/ref.dart:789`, `_runCallbacks`, `Ref.onDispose`.
Возвращённая функция снятия регистрации меняет список, который сейчас обходит
for-in. Ошибка возникает при продвижении итератора, вне защиты вызова callback.
`probe_lifecycle.dart` снимает первый callback из него самого и ставит второй
callback очистки: результат
`unregister-dispose error=ConcurrentModificationError`,
`unregister-dispose secondDisposed=false`. Обходить устойчивый snapshot либо
определить безопасную очередь снятий; обязательно продолжать независимые
cleanup после проблем одного обработчика. В соседнем
`_runManualInvalidationCallbacks` snapshot уже есть.

**Вердикт:** Подтверждено моим прогоном `probe_lifecycle.dart`:
`unregister-dispose error=ConcurrentModificationError`,
`unregister-dispose secondDisposed=false`. То же у Fable (C6); у Astra видно
ещё и последствие — второй `onDispose` не вызван.

#### C6 — Medium. Закрытая MutationTransaction может удержать provider навсегда.

Место: `lib/src/core/mutations.dart:18–35`, `MutationTransaction.get/_close`.
Защита от get после закрытия — только assert. Если сохранить транзакцию
и использовать после run, создаётся подписка, которой уже не достанется
следующий `_close`. `probe_core.dart` без assertions печатает
`closed-transaction accepted=true disposed=false` для autoDispose provider;
с assertions — `closed-transaction rejected=_AssertionError`. Это неправильное
использование API, но его последствия должны оставаться локальной ошибкой
во всех режимах. Проверять `_closed` в runtime и бросать StateError с советом
вызывать get только внутри ожидаемого callback run.

**Вердикт:** Подтверждено моими прогонами `probe_core.dart`: без assert —
`closed-transaction accepted=true disposed=false`, с `--enable-asserts` —
`closed-transaction rejected=_AssertionError`. У Fable этой находки нет.

### 5. Тесты

#### T1 — Medium. Срок хранения по умолчанию не защищён.

Место: `lib/src/core/persist.dart`, `StorageOptions`; тесты persistence
в `test/src/core/provider/notifier_provider_test.dart`. Мутация M2 меняет два
дня на один, и полный набор остаётся зелёным. Это наблюдаемое изменение
публичного default. Добавить проверку времени с fake clock между одним и двумя
днями, а также границы истечения.

**Вердикт:** Подтверждено моим прогоном мутации M2 (`Duration(days: 2)`
на `days: 1` в `StorageOptions`), скрипт с возвратом файла копией: весь набор
`00:10 +1647 ~5: All tests passed!`, после возврата tracked diff пуст.

#### T2 — High. Тестовая модель асинхронного Storage пропускает потерю данных.

Место: `test/src/core/provider/notifier_provider_test.dart`, группа persist.
Тест с названием
`If a provider sets a value before an asynchronous adapter, it wins` возвращает
синхронный `PersistedData(completer.future)`; это не задержанный
`Future<PersistedData>`, использованный в C1. В наборе не пойманы расписания
C1/C2 и завершение read после disposal. M8, удаляющая guard didChange, тоже
проходит. Для обычного Future этот guard и так сбрасывается раньше: выжившую M8
нельзя выдавать за доказательство отдельной наблюдаемой регрессии. Нужны
матрица порядка read/network/write, invalidate/dispose между ними и проверки
итоговой базы после нового контейнера. C3 показывает ещё и проблему ожидаемого
результата: M3 поймана тестами, которые требуют удалять cache при ошибке.

**Вердикт:** Подтверждено: M8 — та же мутация, что m01 у Fable, мой прогон —
набор зелёный (вердикт T1 Fable). Оговорку Astra об эквивалентности считаю
верной: страж и так мёртв, поэтому выжившая мутация показывает пустой тест,
а не отдельную регрессию.

#### T3 — Medium. Генератор проверяет примеры, но не уникальность ключей.

Место: `packages/riverpod_generator/test/`, JSON persistence fixtures. Штатные
83 теста с одним пропуском и 84 теста с `-P check` проходят, а настоящий
сгенерированный код допускает C4. Добавить свойства однозначности ключа для
строк с разделителями, null, вложенных аргументов и имён провайдеров, плюс
runtime round-trip между контейнерами. Подозрение на nullable-декодирование я
проверил отдельно: генерация, анализ и исполнение успешны,
`nullable decoded=ProbeModel`; дефекта по этому подозрению не заявляю.

**Вердикт:** Подтверждено, см. вердикт C4.

#### T4 — Low. Автоматическая проверка публичного документационного периметра неполна.

Место: `packages/riverpod/test/meta_test.dart` и документационные стенды.
В текущем наборе отключены проверки наличия dartdoc, неэкспортируемых типов
в публичном API и использования шаблонов. Анализ соседних Dart-файлов сайта
проходит, а извлечённые inline-фрагменты дают три ошибки типов/имён. Предлагаю
включить извлечение именно публикуемого кода и запускать его для обоих
вариантов; список примеров должен быть входом стенда.

Все восемь мутаций прогонялись на **полном наборе ядра**, с пределом 600
секунд, по одной. Перед каждой — `cp` в `.review-tmp/Mn.orig`, после — `cp`
обратно. После каждой проверены пустой tracked diff и `git status --short`;
снимки — `.review-tmp/Mn-status.log`.

| Мутация | Файл и член | Изменение | Результат полного набора |
|---|---|---|---|
| M1 | `core/provider/notifier_provider.dart`, persist | Убрать перенаправление ошибки Future записи в defaultOnError | Поймана: `Reports decoding/encoding errors to the zone` |
| M2 | `core/persist.dart`, StorageOptions | Default cacheTime: два дня → один | **Не поймана**, 1647 проходят, 5 пропущены |
| M3 | `core/provider/notifier_provider.dart`, _callEncode | Не удалять cache при AsyncError | Поймана: `encode calls Persist.clear if state is set to error`, проверки ошибок |
| M4 | `core/mutations.dart`, проверка activeRef | Пропустить результат устаревшего run | Поймана: concurrent run и оба теста reset во время run |
| M5 | `core/ref.dart`, mounted | Убрать проверку идентичности текущего Ref | Поймана: `mounted is false for previous ref when FutureProvider is invalidated during async build` |
| M6 | `core/provider_container.dart`, defaultRetry | Убрать ограничение maxDelay | Поймана: `default retry delays from 200ms to 6.4 seconds` |
| M7 | `core/provider_container.dart`, tryRemove | Не удалять пустой каталог familyPointers | Поймана: тесты удаления пустой family и family из transitive override |
| M8 | `core/provider/notifier_provider.dart`, persist | Убрать guard didChange перед decode | **Не поймана**, 1647 проходят, 5 пропущены; оговорка об эквивалентности — T2 |

Это целевой эксперимент на восьми выбранных местах, не статистическая оценка
mutation coverage всего проекта. Сильные стороны набора: проверки поколений
Ref, конкурентных mutation, retry, освобождения структур family и маршрутизации
ошибок действительно сработали.

**Вердикт:** Принято по чтению; извлечённые фрагменты страниц — см. вердикт D4.

### 6. Понятия и масштаб

#### S1 — Medium. До правильного небольшого приложения нужен длинный обязательный маршрут.

Место: публичные Provider/Container/Ref/Notifier и страницы
`concepts2/{providers,containers,refs,auto_dispose}.mdx`. По моей учебной
декомпозиции, для изменяемой синхронной Dart-программы нужны семь понятий:
определение provider отдельно от состояния; контейнер и его уничтожение; Ref;
read/watch/listen; Notifier как место изменения; равенство/неизменяемость
состояния; владение подпиской и временем жизни. Для async с обновлением
и отменой добавляются шесть: AsyncValue с прежними данными; проекция future;
invalidate/refresh; отмена внешней операции; поколение build после await;
политика retry. Итого около 13, ещё до family, scoping и persistence. Для
Flutter добавляются Scope и Consumer. Это подсчёт обязанностей читателя,
не объективная единица сложности. Доказательства цены ошибок — C1, B2, D2, D5
и `probe_core.dart`. Предлагаю один последовательный маршрут: значение →
изменение → async → обновление → отмена. Family, scoping, observers, select,
mutations и offline вводить по задаче. B1/B2/B4 убирают часть обязательных
различий.

**Вердикт:** Принято: счёт понятий — суждение ревьюера, у Fable около 18,
у Astra около 13.

#### S2 — Low. Без autoDispose большая family — неограниченный cache.

Место: `lib/src/core/provider_container.dart`, каталоги family;
`concepts2/family.mdx`. `probe_scale.dart` создаёт три серии по 10 000 разных
ключей в одном долгоживущем контейнере. Без autoDispose число активных
состояний: 10 000 → 20 000 → 30 000, уничтожено ноль. С autoDispose после pump:
каждый раз ноль активных, уничтожено суммарно 10 000 → 20 000 → 30 000. Это
ожидаемая модель удержания, а не доказанная утечка autoDispose. Native TTL/LRU
для такого cache пользователь собирает сам. Для объектов-ключей нужна
корректная equality: `probe_scope.dart` создаёт два равных по содержимому List
и получает `family-list duplicateBuilds=2`. Предлагаю безопасный default для
family, пример ограниченного cache и конкретную диагностику нестабильного
ключа. RSS в эксперименте рос и с autoDispose; без принудительного GC и heap
snapshot приписывать этот рост утечке нельзя.

**Вердикт:** Принято по отчёту: `probe_scale.dart` Astra не перепрогонял.
`family-list duplicateBuilds=2` — в моём прогоне `probe_scope.dart`.

#### S3 — Medium. Глубина графа ограничена рекурсивной реализацией.

Место: `lib/src/core/element.dart` и синхронный путь flush/read зависимостей.
`probe_chain.dart` строит линейную цепочку Provider. При 500 звеньях получены
значения 500 и 501 после изменения корня; при 1000 и 2000 первичное чтение
заканчивается ProviderException, корневая причина — StackOverflowError. Зонд
разворачивает обёртки, не печатая огромный stack trace. Это произошло и при
`-Ddart.vm.product=true`; это JIT-запуск с product-константой, не AOT
benchmark. Предлагаю итеративное вычисление глубокого графа либо предсказуемую
раннюю диагностику глубины. Точный порог зависит от VM, платформы и формы
функций; «1000» не является универсальным пределом пакета.

**Вердикт:** Принято; рекурсия и `Stack Overflow` подтверждены моим прогоном
зонда Fable, см. вердикт S3 Fable. Зонд цепочки Astra не перепрогонял.

#### S4 — Low. Частые обновления масштабируются по числу реально уведомляемых слушателей.

Место: уведомления ProviderSubscription и scheduler. `probe_listeners.dart`:
100 обновлений при 1000 слушателях дали 100 000 callback за 12 мс; при 10 000 —
1 000 000 за 31 мс внутри измеренного участка одного запуска. Для производных
значений есть объединение работы: `probe_lifecycle.dart`, ромб после 100
изменений до pump — `diamond builds=2 events=[(101, 200)]`, без промежуточной
несогласованной пары. Это положительный результат с естественной линейной
стоимостью fan-out. Select и неизменяемые компактные значения полезны; обещать
постоянную стоимость update при любом числе слушателей нельзя. Повторных серий,
AOT, профилирования allocations и измерения Flutter кадров не было.

Цена выбора codegen для новичка — дополнительная установка builder,
part-файл/сгенерированные имена и ожидание генерации. Взамен меньше
параллельных объявлений и удобнее многопараметрические family. Но нынешний
выбор меняет default lifetime, способ выражения аргументов и поверхность
ошибок. Его нельзя подавать только как вопрос сокращения бойлерплейта. Лучше
один первый маршрут, а второй — короткий перенос того же приложения с явно
отмеченными различиями поведения.

**Вердикт:** Принято по отчёту: `probe_listeners.dart` не перепрогонял.
`diamond builds=2 events=[(101, 200)]` — в моём прогоне `probe_lifecycle.dart`.
С выводом Fable (S4) не спорит: Fable мерил снятие подписок и много зависимых,
Astra — доставку уведомлений.

### 7. Находки по документации

#### D1 — High. Пример manual persistence несовместим с выбранным Storage.

Место: `website/docs/concepts2/offline.mdx`, ручная сериализация;
`concepts2/offline/manual_persist/{raw,codegen}.dart`. Хранилище строковое,
encode возвращает List<Map>, decode приводит String к List. Из-за вывода
типов/covariance этот код проходит статический анализ. `probe_docs.dart`
переносит эту механику в чистый Dart с тем же Storage<String, String>. Получены
обе runtime-ошибки:
`type 'String' is not a subtype of type 'List<dynamic>' in type cast`
и `type 'List<Map<String,
String>>' is not a subtype of type 'String' of 'value'`. Старая запись
остаётся, новое состояние не сохраняется. Исправить обе версии через JSON
encode/decode и исполнять round-trip самого опубликованного примера. Совет
не ждать persist отдельно требует исправления C1, иначе корректный codec
проблему порядка не решит.

**Вердикт:** Подтверждено моим прогоном `probe_docs.dart`: `manual-persist
errors=[type 'String' is not a subtype of type 'List<dynamic>' in type cast,
type 'List<Map<String,
String>>' is not a subtype of type 'String' of 'value']`,
`manual-persist disk=[{"task":"old"}]`. То же у Fable (D6).

#### D2 — Medium. Проверка ref.mounted из миграции не защищает старый build notifier.

Место: `website/docs/3.0_migration.mdx`, раздел об использовании Ref после
disposal, пример Example.build. Документ предлагает после await проверить
getter `ref.mounted`, затем безопасно читать другие providers.
`probe_core.dart` запускает новый build до завершения старого: лог
`build=0 current=true captured=false` показывает, что старый body прошёл guard
по новому Ref и исполнил эффект. Итоговое значение при этом правильно осталось
200: защита движка от устаревшего возвращаемого результата не отменяет
пользовательское тело функции. Показать захват `final buildRef = ref` до await
и проверку именно его либо onDispose с отменой операции. Аналогичную оговорку
добавить к обещанию доступности ref внутри методов notifier на странице refs.

**Вердикт:** Подтверждено, см. вердикт B2.

#### D3 — Medium. Ошибки, disposal и retry описаны шире реального контракта.

Место: `3.0_migration.mdx`,
`Provider failures are now rethrown as ProviderExceptions`; dartdoc
`ProviderException` в `lib/src/common/stack_trace.dart`;
`packages/riverpod/CHANGELOG.md`, 3.5.0; dartdoc `Riverpod.retry` в annotation.
Пример миграции ловит ProviderException вокруг await `.future`,
но `probe_lifecycle.dart` печатает
`future-error type=_Exception wrapped=false`. Тот же зонд после disposal
получает 99 из ожидавшего Future, а из Stream — ProviderDisposedException;
changelog не уточняет эту границу. `probe_retry.dart`: родитель падает один
раз, ребёнок с await parent.future строится трижды при maxRetries=2; исходная
ошибка не опознаётся как ошибка зависимости. Наконец, annotation обещает
unlimited retries, миграция — повторы до успеха, тогда как defaultRetry
прекращает их после десяти, не повторяет Error/ProviderException и ограничивает
задержку 6400 мс. Уточнить все четыре контракта и дать таблицу sync read /
await future / disposal / зависимость, связанную с исполняемыми примерами.

**Вердикт:** Подтверждено: прогоны — см. вердикт B3; dartdoc
в `riverpod_annotation.dart` говорит «has unlimited retries», миграция — «until
it succeeds», а `defaultRetry` останавливается после десяти попыток: моя строка
`probe_core.dart` —
`retry delays=[200, 400, 800, 1600, 3200, 6400, 6400, 6400, 6400, 6400, null]`.
Миграция — то же у Fable (D2, D7).

#### D4 — Medium. В публикуемом тексте остались несуществующие имена API.

Место: `concepts2/retry.mdx`, codegen-примеры; `how_to/pull_to_refresh.mdx`,
nullable-data tip; `3.0_migration.mdx`, примеры после миграции; `CHANGELOG.md`
3.5.0 и deprecation `Ref.exists`. Из первых двух страниц
`.review-tmp/extract.py` извлекает настоящий текст в `probe_doc_inline.dart`:
анализатор сообщает undefined MyProviderRef, hasData и valueOrNull. Это три
ошибки; четвёртое сообщение — info об импорте annotation в тестовом
scaffolding. Pull-to-refresh ещё описывает 3.0 как будущее изменение,
а после-миграционный пример использует valueOrNull. Changelog и текст
deprecation предлагают `provider.exist`, но доступно `provider.exists`.
По чтению также устарели callback без параметра в dartdoc Mutation.run
и именованный `storage:` в JsonPersist при позиционной сигнатуре. Заменить
имена и извлекать inline/dartdoc-код в стенд; чистый анализ соседних .dart
не проверяет эти фрагменты.

**Вердикт:** Подтверждено по дереву, см. вердикты D3, D4 и B2 Fable. Анализ
`probe_doc_inline.dart` не перепрогонял.

#### D5 — Medium. Пример mutation показывает состояние ошибки, но оставляет Future необработанным.

Место: `concepts2/mutations.mdx`, запуск mutation;
`concepts2/mutations/triggering.dart`; dartdoc run/reset. Callback кнопки
вызывает run без await/catch. Публикация MutationError не поглощает исключение
возвращённого Future. `probe_core.dart` воспроизводит
`mutation errorState=true uncaught=[Exception: failed]`. Там же reset оставляет
побочный эффект работающим: `mutation reset idle=true effect=true`. Показать
осознанную обработку результата/исключения, отдельно объяснить сброс UI,
подавление устаревшего результата и отмену внешней работы.

**Вердикт:** Подтверждено, см. вердикт B5. То же у Fable (D17).

#### D6 — Medium. Lifecycle описан словами, которые обещают другое наблюдаемое состояние.

Место: `concepts2/auto_dispose.mdx`, отсчёт до уничтожения;
`lib/src/core/ref.dart`, dartdoc `invalidate(asReload:)`. Страница приравнивает
ожидание кадра к await null; в чистом Dart зонд после await null получает
`disposed=0`, после container.pump — `disposed=1`. Нельзя использовать эту
формулировку как барьер очистки в тесте. Dartdoc asReload обещает clear/hard
refresh, но зонд сохраняет value=1 и hasValue=true во время isReloading.
Документировать планировщик и проверяемый барьер pump, а очистку ресурсов,
старое значение AsyncValue и повторное использование notifier различать явно.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`:
`dispose await-null=0`, `dispose after-pump=1`; `asReload` — см. вердикт B4.
Первая часть — то же у Fable (D14).

#### D7 — Low. Вход через README не доводит пользователя core-пакета до полного старта.

Место: `packages/riverpod/README.md`, первый пример; README annotation;
`introduction/getting_started.mdx`, установка;
`concepts/about_code_generation.mdx`, выбор генерации. README core начинается
с генерируемого Flutter-примера без полного окружения imports/part/Scope;
annotation README почти только перенаправляет дальше. Страница установки
исправляет многое: оба Dart-примера реально печатают Hello world. Но шаблон SDK
`^3.7.0` не объясняет, что выбранные нынешние версии пакетов требуют Dart
`^3.12.0`. Страница выбора сначала рекомендует codegen, затем ограничивает
рекомендацию теми, кто уже его использует. Дать в README маленький полный
Dart-пример с dispose, актуальный минимум SDK и одно объяснение выбора
с разницей lifetime.

Сопутствующий `packages/riverpod/example/` по чтению удачно показывает
асинхронную зависимость Configuration → Repository и onDispose HTTP-клиента.
Однако для первого запуска нужны внешняя учётная запись и ключи Marvel;
`main.dart` вызывает container.dispose только после успешного fetchComics. Для
учебного примера нужны локальная реализация без ключей и try/finally вокруг
использования контейнера. Сетевой запуск этого примера не выполнялся.

**Вердикт:** Принято по чтению; `sdk: ^3.7.0` — см. вердикт D12 Fable. То же
у Fable (D1, D12, D16).

### 8. Для ИИ-агентов

#### A1 — Medium. Типокорректность не подтверждает реактивность.

Место: `Notifier.state`, `Provider.family`, scoping dependencies.
В `probe_core.dart` изменение List на месте и присваивание того же объекта дают
`mutable-list state=[1] events=0`. Это ожидаемая equality-модель,
но правдоподобный код агента молча не обновляет подписчика. Необъявленная
scoped-зависимость также молча читает root, даже с assertions — B7/S2.
Предлагаю короткие обязательные примеры immutable update и области контейнера,
конкретные линты и runtime-ошибку неоднозначного scoping.

**Вердикт:** Подтверждено моим прогоном `probe_core.dart`:
`mutable-list state=[1] events=0`; scoping — см. вердикт B7. То же у Fable
(A5).

#### A2 — Medium. Реально запущенный линтер покрывает только часть таких ошибок.

Место: `.review-tmp/lint_app/probe_agent.dart`, локальный riverpod_lint 3.2.0.
В отдельном пакете настроен analyzer plugin из копии и выполнен
`dart analyze --plugins`. Он выдаёт provider_parameters для List-аргумента,
но предлагает «use a family», хотя вызов уже использует family. Изменение List
на месте, необработанный Mutation.run и отсутствие scoped dependencies
не диагностированы. Второе предупреждение — unused dart:async. Нужен текст про
стабильные ==/hashCode и новый экземпляр List, а не общий совет перейти
на family. Это проверка этих конкретных примеров, не заявление об отсутствии
других полезных правил пакета.

**Вердикт:** Принято по отчёту: пакет `lint_app` с плагином не перепрогонял.

#### A3 — Medium. Некоторые инструкции исправления воспроизводят ошибку.

Место: deprecation Ref.exists и руководства миграции. Ссылка на D4:
предлагаемого `.exist` нет. Ссылка на D2: совет проверить getter ref.mounted
не различает поколения notifier. C6 показывает зависимость защиты от assert,
D5 — двойной канал ошибки mutation. Исправления: сообщения должны показывать
существующий API и минимальный правильный контекст; контрактные проверки
владения нельзя оставлять исключительно отладочному режиму.

Положительная сторона: захваченный устаревший Ref бросает UnmountedRefException
с объяснением rebuild и советами onDispose/mounted. Неправильное чтение
`.listenable` выдаёт конкретное сообщение:
`Obtain .listenable through ref.watch, ref.listen or container.listen,
not read` (в оригинале имена заключены в обратные кавычки). Такие сообщения
помогают исправить код без угадывания внутренностей. Проверенный nullable-код
генератора также не следует браковать по внешнему виду: его анализ и исполнение
прошли.

**Вердикт:** Принято, см. вердикты B2, C6 и D5.

### 9. Что сделать для 10/10

Прибавки — моя оценка эффекта законченного и проверенного изменения. Они
складываются до 10 внутри каждой строки оценки; между разными оценками одни
и те же исправления закономерно учитываются повторно.

| Оценка сейчас | Шаг | Какой недостаток снимает | Прибавка |
|---|---|---|---:|
| Общая 6,5 | Исправить и проверить C1–C6 на публичных сценариях | Потеря состояния, cache и ресурсов | +1,5 |
| | Довести опубликованные примеры и контракты D1–D7 до одной версии | Ошибки следования документации | +0,8 |
| | Провести B1–B8 с миграцией и одним учебным маршрутом | Цена скрытых различий и выбора синтаксиса | +0,8 |
| | Закрепить масштаб и расписания тестами T1–T4/S3 | Непредсказуемые границы при развитии приложения | +0,4 |
| Код 7 | Порядок, актуальность и сохранность persistence, уникальные ключи C1–C4 | Потеря данных | +1,4 |
| | Безопасная очистка/транзакция C5–C6, устранение рекурсивного предела S3 | Потеря ресурсов и авария глубокого графа | +0,6 |
| | Контракты B1–B8, включая отдельный Ref запуска | Случайная корректность пользовательского async-кода | +1,0 |
| Тесты 7,5 | Реальные Future<Storage data>, перестановки операций и повторный запуск T2 | Гонки, которых текущие doubles не моделируют | +1,0 |
| | Защитить default TTL, ключи и runtime результата генерации T1/T3 | Незаметные изменения хранения | +0,7 |
| | Извлекать и выполнять все публикуемые примеры T4 | Зелёные проверки при сломанной документации | +0,5 |
| | Регрессии C5/C6 и глубокие/долгоживущие графы | Неохваченные границы lifecycle и реализации | +0,3 |
| Документация 5 | Исправить и запускать offline, retry, nullable refresh, migration и dartdoc | Нерабочий код D1/D4 | +1,8 |
| | Прописать поколения, ошибки, retry, disposal и reset | Неверные поведенческие обещания D2/D3/D5/D6 | +1,5 |
| | Полный первый Dart/Flutter маршрут и однозначный выбор codegen | Разрывы установки и лишние ранние понятия D7/S1 | +1,0 |
| | Справочник lifecycle, импортов, overrides и масштабирования | Недостающие границы применения | +0,7 |
| Для агентов 5,5 | Исполняемые канонические примеры с одинаковыми defaults | Правдоподобный устаревший код D1–D7/B1 | +1,5 |
| | Контекст build и runtime-проверки владения/scoping | Молчаливые ошибки B2/B7/C6 | +1,3 |
| | Конкретные диагностики equality, ignored result и правильные deprecation | Неэффективный цикл автоматического исправления A1–A3 | +1,0 |
| | Краткая таблица контрактов и шаблоны тестов отмены/повторного запуска | Агент проверяет только happy path | +0,7 |

### 10. Страницы

Оценка читаемости учитывает, может ли читатель правильно применить прочитанное
на этой версии. Для компактности пути сайта даны относительно `website/docs`;
расширение — `.mdx`. Последняя колонка содержит достаточную прибавку до 10
за указанную переработку, а не отдельную оценку качества кода.

| Страница | Читаемость | Почему | Что сделать для 10 |
|---|---:|---|---|
| `packages/riverpod/README.md` | 6/10 | Назначение видно; первый пример требует необъяснённой генерации и Flutter | Полный запускаемый Dart-старт, ссылки на lifetime и async; +4 |
| `packages/riverpod_annotation/README.md` | 4/10 | Почти только перенаправление, роль пакета и контракт аннотации не раскрыты | Минимальный пример, совместимые версии, part/build, defaults; +6 |
| `introduction/getting_started` | 7/10 | Оба Dart hello world работают; много развилок установки, старый минимум SDK | Сверить SDK, сгруппировать один путь, показать dispose; +3 |
| `tutorials/first_app` | 6/10 | Видимый результат, но большой UI заслоняет механизм; обработка обновления отложена | Законченные этапы с imports, async error/retry/cancel и проверкой результата; +4 |
| `concepts2/providers` | 7/10 | Хорошая классификация, шесть видов сразу перегружают начало | Начать с двух задач, исправить inline-сигнатуры, остальные виды отложить; +3 |
| `concepts2/consumers` | 8/10 | Понятны варианты и место чтения; много Flutter-обоснований до действия | Один основной способ, короткая таблица остальных и жизненный цикл listener; +2 |
| `concepts2/containers` | 8/10 | Хорошо объясняет принадлежность состояния и изоляцию; есть pure Dart | Добавить границу наследования child container и weak/strong владение; +2 |
| `concepts2/refs` | 7/10 | read/watch/listen объяснены; Ref notifier выглядит безопасным после любого await | Захват Ref запуска и таблица lifecycle методов; +3 |
| `concepts2/auto_dispose` | 7/10 | Практичные keepAlive/onDispose, но смешаны кадр, microtask и уничтожение состояния | Точный барьер очистки и различие ресурса, notifier и старых данных; +3 |
| `concepts2/family` | 8/10 | Удачная модель Map, предупреждения equality и retention | Показать ошибочный List-ключ, исправление и ограниченный cache; +2 |
| `concepts2/mutations` | 6/10 | Мотивация ясна, запуск скрывает необработанный Future | Обработка ошибки, concurrent run, reset и настоящая отмена; +4 |
| `concepts2/offline` | 4/10 | Полезный обзор, но основной ручной codec падает, порядок восстановления опасен | Рабочие оба codec, расписание restore/update, политика ошибок и миграция ключей; +6 |
| `concepts2/retry` | 5/10 | Есть сроки и настройка; codegen устарел, async-зависимости не разобраны | Ref вместо удалённых имён, таблица retry для sync/async, актуальные defaults; +5 |
| `concepts2/observers` | 8/10 | Короткая цель, полезное предупреждение об изменяемых previous/new | Полный пример подключения и порядок уведомлений при rebuild/dispose; +2 |
| `concepts2/overrides` | 6/10 | Понятна замена реализации, различия override-методов почти не раскрыты | Сверить ссылки, таблица value/build/family, границы областей; +4 |
| `concepts2/scoping` | 6/10 | Сложность честно названа, примеры помогают; тихий root fallback не виден | Контрпример B7, явные зависимости и диагностика пропуска; +4 |
| `concepts/about_code_generation` | 6/10 | Сравнение синтаксиса полезно, критерий выбора противоречив | Один критерий, отдельная таблица семантических различий, меньше повторов; +4 |
| `how_to/testing` | 8/10 | Изоляция контейнера, overrides и удержание autoDispose практичны | Async-ошибка, отключение retry, отмена и порядок pump в одном полном тесте; +2 |
| `how_to/select` | 9/10 | Объясняет цену выбора и неизменяемость, не обещает бесплатной оптимизации | Короткий воспроизводимый замер и граница equality выбранного значения; +1 |
| `how_to/eager_initialization` | 8/10 | Решает задачу ленивого старта и сохранения child | Полный error/retry-сценарий и граница времени жизни инициализации; +2 |
| `how_to/pull_to_refresh` | 4/10 | Основная идея полезна, текст от другой версии, nullable tip не компилируется | Синхронизировать текст и код, выполнить nullable/error/refresh сценарии; +6 |
| `how_to/cancel` | 8/10 | Хорошо показывает реальную отмену HTTP и debounce | Различить остановку транспорта, подавление результата и ожидающий future; +2 |
| `root/faq` | 8/10 | Полезные ответы про refresh/invalidate и ограничения модели | Привязать ответы к полным сценариям async и scope, уточнить момент пересчёта; +2 |
| `root/do_dont` | 8/10 | Практичные запреты init/side effects, причины в основном понятны | Для каждого опасного случая минимальный хороший вариант и граница проверки линтером; +2 |
| `3.0_migration` | 4/10 | Широкий охват изменений, но ошибочные catch, mounted и оставшиеся valueOrNull | Исполняемые before/after, точные retry/future/lifecycle контракты; +6 |
| `packages/riverpod_generator/README.md` | 5/10 | Дополнительная проверенная страница: роль генерации ясна, пример требует сверки имён | Согласовать имя функции/provider, полный part/build цикл и defaults; +5 |

### 11. Что хорошо и трогать не надо

- Ленивые определения отдельно от принадлежащего контейнеру состояния: это даёт
  проверяемую изоляцию и удобные overrides.
- Разделение read/watch/listen по намерению, select/selectAsync и подавление
  лишних уведомлений при корректной equality.
- Согласованный пересчёт проверенного ромба и отбрасывание устаревшего
  возвращаемого результата async build.
- Несколько независимых KeepAliveLink, автоматическое снятие зависимостей
  и очистка пустых family: эти механизмы подкреплены тестами и зондами.
- Сохранение предыдущих данных во время загрузки/ошибки полезно; нужно
  прояснить API, а не терять эту возможность.
- ProviderContainer.test, overrides и возможность проверить основную механику
  без Flutter.
- Отдельные experimental/legacy импорты и проверка генерируемого кода
  по эталонам.

### 12. ПРОГОН

Все проверки выполнены в указанной копии. Обозначения каталогов: R —
`packages/riverpod`, G — `packages/riverpod_generator`, W — `website`, L —
`.review-tmp/lint_app`, корень — текущая копия. Команды ниже запускались через
`rtk proxy python3 .review-tmp/run.py`, который сохраняет лог, выставляет PATH
с `/Users/user/fvm/versions/master/bin` первым, TMPDIR внутри `.review-tmp`
и добавляет **`perl -e 'alarm 600; exec @ARGV'`** перед каждой командой.
В строках цепочек дополнительно виден внутренний предел 30 секунд. В таблице
указана точная последняя непустая строка вывода дочерней команды; exit — её
код, а не код Python-обёртки. Полный журнал команд и времени —
`.review-tmp/runs.jsonl`.

Первые три запуска analyze упали из-за запрета записи
`/Users/user/.dartServer/.plugin_trust` в этой среде. После переноса состояния
анализатора через ANALYZER_STATE_LOCATION_OVERRIDE в `.review-tmp` проверки
повторены. Это ограничение окружения, не дефект Riverpod. 47 сообщений анализа
зондов — одно предупреждение unused import и 46 информационных замечаний стиля,
не ошибки типов. Два сообщения nullable-пробы — информационные. Для
доказательства работы riverpod_lint использован отдельный L с настоящим plugin;
запуск `--plugins` над core-тестами сам по себе таким доказательством
не считается.

Первый запуск probe_generate упал из-за отсутствующего в моём зонде импорта
experimental/persist.dart: генератор не нашёл PersistResult. После добавления
импорта зонд сгенерирован и выполнен. Это ошибка подготовки зонда, не находка
о nullable-генерации.

| Прогон | Каталог | Команда после общего префикса | Exit | Последняя строка |
|---|---|---|---:|---|
| generator-baseline | G | `dart test -r expanded` | 0 | `00:10 +83 ~1: All tests passed!` |
| baseline | R | `dart test -r expanded` | 0 | `00:14 +1647 ~5: All tests passed!` |
| probe-persist | R | `dart run test/probe_persist.dart` | 0 | `PERSIST PROBE DONE` |
| M1 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M2 | R | `dart test -r expanded` | 0 | `00:19 +1647 ~5: All tests passed!` |
| M3 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M4 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M5 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M6 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M7 | R | `dart test -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| M8 | R | `dart test -r expanded` | 0 | `00:11 +1647 ~5: All tests passed!` |
| probe-core | R | `dart run test/probe_core.dart` | 0 | `CORE PROBE DONE` |
| probe-docs | R | `dart run test/probe_docs.dart` | 0 | `DOCS PROBE DONE` |
| probe-generate | G | `dart test test/probe_generate.dart -r expanded` | 1 | `For example, 'dart test --chain-stack-traces'.` |
| generator-check | G | `dart test -P check -r expanded` | 0 | `00:13 +84: All tests passed!` |
| probe-generate2 | G | `dart test test/probe_generate.dart -r expanded` | 0 | `00:16 +1: All tests passed!` |
| probe-lifecycle | R | `dart run test/probe_lifecycle.dart` | 0 | `LIFECYCLE PROBE DONE` |
| probe-core-debug | R | `dart --enable-asserts run test/probe_core.dart` | 0 | `CORE PROBE DONE` |
| analyze-probes | R | `dart analyze test/probe_core.dart test/probe_docs.dart test/probe_persist.dart test/probe_lifecycle.dart` | 1 | `Bad state: The analysis server crashed unexpectedly` |
| analyze-nullable | G | `dart analyze test/probe_nullable.dart test/probe_nullable.g.dart` | 1 | `Bad state: The analysis server crashed unexpectedly` |
| analyze-docs | W | `dart analyze docs/introduction/getting_started docs/concepts2 docs/how_to/testing docs/how_to/select docs/how_to/eager_initialization docs/how_to/pull_to_refresh docs/how_to/cancel docs/concepts/about_codegen` | 1 | `Bad state: The analysis server crashed unexpectedly` |
| probe-codegen | G | `dart run test/probe_codegen.dart` | 0 | `CODEGEN PROBE DONE` |
| probe-scale | R | `dart run test/probe_scale.dart` | 0 | `SCALE PROBE DONE` |
| probe-chain1000 | R | `perl -e 'alarm 30; exec @ARGV' dart -Ddart.vm.product=true run test/probe_chain.dart 1000` | 0 | `CHAIN PROBE DONE` |
| probe-listeners | R | `dart -Ddart.vm.product=true run test/probe_listeners.dart` | 0 | `LISTENERS PROBE DONE` |
| analyze-nullable-local | G | `dart analyze test/probe_nullable.dart test/probe_nullable.g.dart` | 0 | `2 issues found.` |
| analyze-probes-local | R | `dart analyze test/probe_core.dart test/probe_docs.dart test/probe_persist.dart test/probe_lifecycle.dart` | 2 | `47 issues found.` |
| analyze-docs-local | W | `dart analyze docs/introduction/getting_started docs/concepts2 docs/how_to/testing docs/how_to/select docs/how_to/eager_initialization docs/how_to/pull_to_refresh docs/how_to/cancel docs/concepts/about_codegen` | 0 | `No issues found!` |
| probe-retry | R | `dart run test/probe_retry.dart` | 0 | `RETRY PROBE DONE` |
| analyze-probes-plugins | R | `dart analyze --plugins test/probe_core.dart test/probe_docs.dart test/probe_persist.dart test/probe_lifecycle.dart` | 2 | `47 issues found.` |
| probe-chain500 | R | `perl -e 'alarm 30; exec @ARGV' dart -Ddart.vm.product=true run test/probe_chain.dart 500` | 0 | `CHAIN PROBE DONE` |
| probe-chain2000 | R | `perl -e 'alarm 30; exec @ARGV' dart -Ddart.vm.product=true run test/probe_chain.dart 2000` | 0 | `CHAIN PROBE DONE` |
| lint-pub | L | `dart pub get --offline` | 0 | `Changed 18 dependencies!` |
| sdk | корень | `dart --version` | 0 | `Dart SDK version: 3.15.0-139.0.dev (dev) (Wed Nov 11 12:04:01 2026 -0800) on "macos_arm64"` |
| probe-scope | R | `dart --enable-asserts run test/probe_scope.dart` | 0 | `SCOPE PROBE DONE` |
| analyze-doc-inline | R | `dart analyze test/probe_doc_inline.dart` | 3 | `4 issues found.` |
| probe-generate3 | G | `dart test test/probe_generate.dart -r expanded` | 0 | `00:14 +1: All tests passed!` |
| lint-agent | L | `dart analyze --plugins` | 2 | `2 issues found.` |
| baseline-final | R | `dart test -r expanded` | 0 | `00:24 +1647 ~5: All tests passed!` |
| probe-nullable | G | `dart run test/probe_nullable.dart` | 0 | `NULLABLE PROBE DONE` |
| hello-raw | W | `dart run docs/introduction/getting_started/dart_hello_world/raw.dart` | 0 | `Hello world` |
| hello-codegen | W | `dart run docs/introduction/getting_started/dart_hello_world/main.dart` | 0 | `Hello world` |
| reviewed-head | корень | `git rev-parse HEAD` | 0 | `7a02bedc149ef35311d856993e5bb76e528dd036` |
| extract-inline | корень | `python3 .review-tmp/extract.py` | 0 | `EXTRACTED retry codegen block and pull_to_refresh pattern` |
| clean-check | корень | `python3 .review-tmp/check_clean.py` | 0 | `TRACKED FILES UNCHANGED; ONLY REVIEW FILES UNTRACKED` |

Управляющая команда мутаций — `rtk proxy python3 .review-tmp/mutations.py`,
последняя строка `MUTATIONS DONE`. Внутри выполнены восемь перечисленных
ограниченных по времени прогонов, восемь сохранений и восстановлений `cp`,
восемь проверок tracked diff и status. Точные подстановки сохранены в этом
скрипте. Контрольный status в конце содержит только `.review-tmp/` и новые
`probe_*` в двух разрешённых пакетах.

Базовый результат совпал с указанным в задании по числу тестов: 1647 проходят,
5 пропущены; отличается только длительность. Первый запуск занял 19,95 секунды
wall time, повторный — 26,48. Масштабный общий зонд занял 155,08 секунды,
включая дорогое форматирование вложенных ошибок; это время нельзя считать
стоимостью вычисления графа. Изолированные chain-прогоны завершились
за 1,65–2,49 секунды вместе со стартом Dart.

Не запускал: Flutter UI, физические устройства, HTTP-запросы из README,
SQLite-backend, AOT, browser/web, отдельный полный набор annotation, полный
набор riverpod_lint, coverage и mutation coverage всего дерева. Линтер проверен
только на описанном локальном пакете; документационные Dart-каталоги —
анализатором, inline-фрагменты — извлечением, два hello world и выбранные
поведенческие примеры — исполнением. Внешняя сеть для оценки не использовалась.
Просмотры исходников и поиски не являются тестовыми прогонами и в таблице
не перечислены.

Инструкции CONTRIBUTING о согласовании изменений публичного API и работе через
issues/PR относятся к внесению изменений. Если применять их к этому ревью, они
конфликтуют с прямым запретом задания на такую работу; приоритет отдан заданию.
Issues/PR, коммиты и публикации не создавались.

Оформление отчёта проверено отдельно:

| Команда из корня | Последняя строка |
|---|---|
| `rtk proxy python3 .review-tmp/finish_report.py` | `REPORT RUN TABLE WRITTEN` |
| `rtk proxy python3 /Users/user/.codex/skills/reflow/reflow.py .review-tmp/report.md` | `1 files refilled` |
| `rtk proxy python3 /Users/user/.codex/skills/reflow/reflow.py --check .review-tmp/report.md` | `every paragraph is filled to 79 columns` |
| `rtk proxy python3 .review-tmp/check_clean.py` | `TRACKED FILES UNCHANGED; ONLY REVIEW FILES UNTRACKED` |

Форматирование и его проверка выполнены дважды; последние строки совпали.

Артефакты: отчёт `report.md`, журнал прогонов `runs.jsonl`, итоговый status
`final-status.log`.

## Задание

Одно на обоих ревьюеров; `<клон>` и `<отчёт>` у каждого свои. Субагенту Fable
к нему добавлено: не входить в другие каталоги, в интернет за отзывами,
статьями и issues не ходить, субагентов не запускать, второго ревьюера
не искать.

Это ревью, а не реализация и не обсуждение. Вопросов не задавай и подтверждения
не жди: ждать его не у кого. Ход считается проваленным, если ты закончишь его
без отчёта по форме ниже. Отчёт целиком — твой последний ответ; перед ним
запиши тот же отчёт в файл `<отчёт>`.

### Где ты работаешь

Каталог `<клон>` — копия репозитория `rrousselGit/riverpod` на теге
`riverpod-v3.5.0` (коммит `7a02bedc`): то, что сейчас лежит на pub.dev как
`riverpod` 3.5.0, `riverpod_annotation` 4.0.8, `riverpod_generator` 4.0.10
и `riverpod_lint` 3.2.0 — все они выпущены с этого коммита. Работай только
в нём: команды запускай оттуда, временные файлы и пакеты для зондов держи
в `.review-tmp/` внутри копии. Для временных файлов:
`export TMPDIR="$PWD/.review-tmp"; mkdir -p "$TMPDIR"`; голый `mktemp` без
шаблона внутри копии может не работать. У команд, которые могут зависнуть,
ставь предел: `perl -e 'alarm 600; exec @ARGV' <команда>` (на macOS нет
`timeout`).

Репозиторий — pub workspace, и он требует Flutter master (`.fvmrc`).
На стабильном SDK workspace не разрешается. Поэтому все команды Dart и Flutter
запускай с `PATH=/Users/user/fvm/versions/master/bin:$PATH`: там `dart`
3.15.0-139.0.dev и `flutter` того же SDK. Зависимости workspace уже разрешены.
Пакет для зонда вне workspace (в `.review-tmp/`) подключай к пакетам копии
по пути и разрешай сам; если путевая зависимость на пакет workspace
не разрешается, пиши зонд как тест внутри пакета (см. «Чего не делать»).

На этой копии перед ревью `dart test` в `packages/riverpod` даёт:
`00:12 +1647 ~5: All tests passed!` (около 20 секунд). Если у тебя вышло иначе,
это сведения о твоём окружении — назови их в разделе ПРОГОН.

**Твоя область — ядро `riverpod`, его кодогенерация и документация:**

- `packages/riverpod`: `lib/` (включая `experimental/` — мутации и сохранение),
  `test/`, `example/`, `README.md`, `CHANGELOG.md`, `pubspec.yaml`;
- `packages/riverpod_annotation` целиком и `packages/riverpod_generator`:
  документация показывает каждый пример в двух видах, руками и через
  `@riverpod`, так что сгенерированный код — часть того, чем пользователь пишет
  на `riverpod`. Оценивай, что генератор выдаёт и как это ведёт себя,
  а внутренности генератора — только когда они бьют по пользователю;
- страницы сайта документации, на английском, в `website/docs/`:
  `introduction/getting_started.mdx`, `tutorials/first_app.mdx`, все страницы
  `concepts2/` из боковой панели (providers, consumers, containers, refs,
  auto_dispose, family, mutations, offline, retry, observers, overrides,
  scoping), `concepts/about_code_generation.mdx`, `how_to/` (testing, select,
  eager_initialization, pull_to_refresh, cancel), `root/faq.mdx`,
  `root/do_dont.mdx`, `3.0_migration.mdx`. Код страниц часто лежит рядом,
  в одноимённых каталогах (`.dart` и codegen-варианты), — это часть страницы.

Остальные пакеты (`flutter_riverpod`, `hooks_riverpod`, `riverpod_lint`,
`riverpod_sqflite` и прочие) читать можно, чтобы понять, чем пользователь
`riverpod` пишет и проверяет код. Находка о них — только когда она бьёт
по пользователю ядра: например, страница советует то, что пакет рядом делает
иначе. Многие страницы написаны для Flutter; их механику проверяй зондом
на чистом Dart через `ProviderContainer`, где это возможно.

### Как оценивать

Оценивай пакет по тому, что он делает, а не по тому, как его знают. Не доводы:
популярность, загрузки, лайки, звёзды, очки pub.dev, издатель, известность
автора или компании, возраст пакета, «стандарт индустрии», «так принято»,
размер сообщества, число статей и примеров в сети. Не читай отзывы, статьи,
обсуждения и issues о `riverpod`: оценка строится только на коде, документации
из копии и твоих зондах. Привычность API для тех, кто его уже знает, — тоже
не довод: оценивай его глазами того, кто видит пакет впервые.

Это ревью одного пакета. Не сравнивай его с другими библиотеками и не ставь
оценок «на фоне»; если без упоминания другой библиотеки мысль не выразить,
назови её одной фразой, но оценка и находки — только о `riverpod`.

### Главный вопрос

Насколько хорош `riverpod`, и что нужно сделать, чтобы ты поставил 10? Ответь
для каждой оценки, которую ставишь: перечень шагов, у каждого — какой
недостаток он снимает и насколько поднимет оценку.

### Что сделать

1. **Код.** Корректность, гонки и порядок обновлений, жизненный цикл и утечки
   (autoDispose, `keepAlive`, `onDispose`, `family`, подписки), обработка
   ошибок и `AsyncValue`, отмена и пересборка во время асинхронной работы,
   `ref` после уничтожения, граничные случаи, дизайн публичного API: имена,
   согласованность, что легко использовать неправильно. Отдельно —
   экспериментальные мутации и сохранение, повторы (`retry`) и сгенерированный
   код. Догадку проверяй зондом, а не только чтением.
2. **Тесты.** Что они действительно держат. Прогони набор `riverpod`
   (и `riverpod_generator`, если успеешь). Сделай от пяти до десяти своих
   мутаций в `packages/riverpod/lib/` — там, где, по-твоему, сторожей тоньше
   всего, — и прогони набор. Мутация, которую набор пропустил, — находка
   о тестах. Перед мутацией сохраняй файл копией
   (`cp <файл> .review-tmp/<имя>.orig`), после — возвращай копией;
   `git checkout` не используй. После каждой мутации `git status --short`
   должен снова показывать только твои файлы. Набор под мутацией гоняй
   с пределом времени; если весь набор долог, гоняй подмножество, которое
   мутацию должно ловить, и назови его.
3. **Публичный API на следующий мажор.** Пройди всё, что экспортируют
   библиотеки `riverpod.dart`, `misc.dart`, `legacy.dart`,
   `experimental/*.dart` и `riverpod_annotation`: что ты изменил бы при
   следующем мажоре и почему — имя, сигнатура, тип, значение по умолчанию,
   описанное поведение, экспорт. Проверь, что `CHANGELOG.md` говорит правду
   о последних выпусках.
4. **Понятия и порог входа.** Сколько понятий нужно освоить до первой
   правильной программы на `riverpod` и до первой программы с асинхронными
   данными, их обновлением и отменой. Какие из них можно убрать, слить или
   отложить. Отдельно — цена выбора «руками или кодогенерация» для новичка.
5. **Масштаб и долгая жизнь.** Много провайдеров и зависимостей между ними,
   длинные цепочки, большие `family`, частые обновления, много слушателей,
   долгоживущий контейнер: где `riverpod` упирается в модель, а где
   в реализацию; рост памяти и работы. Проверь зондом то, что утверждаешь.
6. **Документация глазами пользователя.** Ты — Dart/Flutter-разработчик,
   который впервые нашёл пакет на pub.dev. README, страницы из области, dartdoc
   публичного API, `CHANGELOG.md`, пример. Понятно ли, что это и зачем;
   можно ли по README и странице установки начать и не ошибиться; верен ли код
   в документах; где читатель споткнётся или сделает ошибку, о которой документ
   не предупредил; чего не хватает; что лишнее. Утверждение документа
   о поведении проверяй зондом, когда его можно проверить.
7. **Глазами ИИ-агента-пользователя.** Агент пишет приложение на `riverpod`
   по задаче человека, видит README и страницы, dartdoc, сигнатуры, тексты
   исключений и сообщения анализатора (с `riverpod_lint`, если документация его
   предлагает). Где правдоподобный код соберётся и молча поведёт себя не так;
   ловит ли это анализатор, assert или исключение, и говорит ли его текст, как
   исправить. Проверь зондом несколько таких ошибок.
8. **Оценки.** Общая, код, тесты, документация, для ИИ-агентов — каждая
   по десятибалльной шкале, где 10 — максимум. Объясни каждую: что подняло
   и что опустило. Затем таблица читаемости `README.md` пакета `riverpod`,
   README `riverpod_annotation` и каждой страницы сайта из области.

### Чего не делать

- Не меняй отслеживаемые файлы, кроме временных мутаций из пункта 2,
  возвращённых копией. Зонды — только как новые файлы: `test/probe_*.dart`
  внутри пакета или пакеты в `.review-tmp/`. Под конец `git status --short`
  копии должен показывать только твои `probe_*` и `.review-tmp/`.
- Если правила репозитория (`CONTRIBUTING.md` и подобное) спорят с этим
  заданием, выигрывает задание, а сам конфликт назови в отчёте.
- Не коммить, не пушь, не публикуй, не открывай issues и pull request'ы.

### Отчёт

По-русски, Markdown. Разделы по порядку:

1. **Оценки** — пункт 8, с объяснением каждой.
2. **Сводка** — пять–десять строк: главное, что ты увидел.
3. **На следующий мажор** — пункт 3: B1, B2, … У каждой: место — файл и имя
   члена; что не так; что сломает правка; что сделать; доказательство — зонд
   или «по чтению». Пусто — так и напиши, с тем, что ты проверил.
4. **Находки по коду** — C1, C2, … У каждой: тяжесть; место — файл и имя члена;
   что не так; механика; доказательство — зонд (файл, что делает, что
   напечатал) или «по чтению»; что предлагаешь. Тяжесть: **High** — неверное
   поведение, потеря данных или ресурса, до которых доходят обычным кодом;
   **Medium** — неверное поведение в редком, но законном случае, или API,
   которое подталкивает к ошибке; **Low** — остальное.
5. **Тесты** — T1, T2, … в той же форме; затем таблица мутаций: файл и член,
   что изменил, какой тест упал или «не пойман».
6. **Понятия и масштаб** — пункты 4 и 5: находки S1, S2, … в той же форме.
7. **Находки по документации** — D1, D2, … в той же форме; место — файл
   и заголовок раздела.
8. **Для ИИ-агентов** — пункт 7: находки A1, A2, … Находку, которая уже стоит
   выше, не повторяй — сошлись на неё.
9. **Что сделать для 10/10** — ответ на главный вопрос для каждой оценки.
10. **Страницы** — таблица «страница — оценка читаемости — почему — что сделать
    для 10».
11. **Что хорошо и трогать не надо** — коротко.
12. **ПРОГОН** — каждая команда, которую ты действительно запустил (проверки,
    зонды, мутации), с точной последней строкой её вывода. Чего не запускал или
    что упало из-за окружения — так и напиши: «не запускал» лучше пересказа.
