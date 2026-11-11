# solo_lints

`solo_lints` — плагин анализатора для кода
на [solo](https://pub.dev/packages/solo)
и [flutter_solo](https://pub.dev/packages/flutter_solo). Он сообщает
об ошибках, которые компилируются, работают и часто проходят первый тест:
ожидание в уборке, которое так и не случается; ресурс, потерянный при отмене;
`catch`, который сбрасывает исправное устройство; задача, которая ждёт саму
себя; один ключ на все запросы; ожидание, которое отмена не прерывает; исход,
которого дождались и выбросили; запись поверх того, что написала другая линия;
линия, объявленная слишком поздно. За большинством правил стоит раздел
[«Частых ошибок»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md) —
страницы solo, где каждая ошибка показана рядом с правильным способом.

Правила ядра, async_job, приходят
из [async_job_lints](https://pub.dev/packages/async_job_lints), и этот плагин
их включает: коду на solo нужен только `solo_lints`. Называйте один из двух
плагинов, а не оба: сервер анализа разрешает версии всех плагинов вместе,
и если они не сходятся, не работает ни один.

Эта страница есть
и на [сайте документации](https://docs.yet-another.dev/ru/solo_lints/),
с поиском.

## Установка

Назовите плагин в `analysis_options.yaml` в корне пакета или рабочего
пространства:

```yaml
plugins:
  solo_lints: ^0.2.1
```

Плагин сервер анализа скачивает сам, поэтому в `pubspec.yaml` он
не зависимость. Плагинам нужен Dart 3.10 или новее. Его диагностики показывают
`dart analyze` и редактор. Запускайте `dart analyze` для корня пакета или для
отдельных файлов: для каталога ниже корня, например `dart analyze lib`, он
не показывает ни одной. `flutter analyze` показывает их на Flutter 3.38,
но начиная с Flutter 3.44 не показывает ни одной; во Flutter-пакете плагин
проверяют через `dart analyze`. Правку раздела `plugins` редактор видит после
перезапуска своего сервера анализа.

Предупреждения включаются, как только плагин назван. Пять линтов,
`catch_without_check`, `key_per_request`, `ignore_failure_hides_bugs`,
`stale_emit` и `bare_await`, включаются по имени:

```yaml
plugins:
  solo_lints:
    version: ^0.2.1
    diagnostics:
      catch_without_check: true
      key_per_request: true
      ignore_failure_hides_bugs: true
      stale_emit: true
      bare_await: true
```

Вместо `true` правилу можно дать уровень: `error`, `warning` или `info`.
`key_per_request: warning` включает линт как предупреждение, и тогда
`dart analyze` на нём падает, как на любом предупреждении. `false` выключает
предупреждение.

Диагностику глушат именем плагина перед именем правила:
`// ignore: solo_lints/ctx_in_cleanup` строкой выше или
`// ignore_for_file: solo_lints/ctx_in_cleanup` на весь файл.

Быстрые исправления предлагает редактор. `dart fix` их не применяет: он
применяет исправления самого анализатора, а не плагинов.

На Dart 3.12 `dart analyze` в пакете, где назван плагин, печатает каждую
диагностику самого анализатора дважды. Dart 3.13 печатает её один раз.

## Правила

| Правило | Вид | Сообщает |
| --- | --- | --- |
| [`ctx_in_cleanup`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#ctx_in_cleanup) | предупреждение | член контекста, который ждёт, вызван в уборке |
| [`release_on_the_call`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#release_on_the_call) | предупреждение | освобождение зарегистрировано строкой ниже вызова, который приносит ресурс |
| [`catch_without_check`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#catch_without_check) | линт | широкий `catch` в теле, которое действует, не спросив задачу |
| [`sync_fake_async`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#sync_fake_async) | предупреждение | `async`-колбэк `fakeAsync` |
| `await_own_queue` | предупреждение | задача ждёт задачу из очереди своего же контроллера |
| `key_per_request` | линт | один ключ у задачи `Policy.droppable`, чьё тело читает аргумент |
| `ignore_failure_hides_bugs` | линт | `ignoreFailure()` у задачи, которая называет свои ожидаемые ошибки |
| `stale_emit` | линт | `emit` в задаче `SoloLanes` значения, прочитанного из состояния до `await` |
| `lane_outside_constructor` | предупреждение | `lane(...)` у `SoloLanes` вызван вне тела конструктора |
| [`bare_await`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#bare_await) | линт | `await` в теле задачи, который идёт мимо контекста |
| [`discarded_outcome`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#discarded_outcome) | предупреждение | исход `done`, которого дождались и выбросили |
| [`outcome_after_await`](https://github.com/vi-k/solo/blob/main/packages/async_job_lints/README.ru.md#outcome_after_await) | предупреждение | первое чтение результата задачи, стоящее после ожидания |

Семь правил ядра описаны в README `async_job_lints`: их имена в таблице ведут
к их разделам в нём. Там `// ignore:` ставит перед правилом `async_job_lints/`;
когда назван этот плагин, — `solo_lints/`, как и для пяти правил ниже.

### await_own_queue

```dart
Job<void> syncAndRecord(int item) =>
    enqueue<Ready, void>(key: _Op.syncAndRecord, (ctx) async {
      final path = await sync(item).value; // await_own_queue
      await recordPath(path).value; // await_own_queue
    });
```

`sync(item)` ставит задачу в очередь за той, что её ждёт, и ничего не движется,
пока `close()` не отменит обе. Выполняйте задачу через `ctx.run(_sync(item))`.
Правило берёт метод того же контроллера, который приносит `SoloJob` —
по объявленному типу или, если метод объявлен в том же файле, по тому, что он
возвращает, — а также `close()` и `cancelAll()`. Оно смотрит в тело задачи
с `SoloContext`, поставленной в очередь этого контроллера, включая то, что тело
возвращает, в действия, которых это тело ждёт через `join`, `abandonable`
и `uncancellable`, и в его уборку: её очередь тоже ждёт. Контроллер — и `mixin`
с `on Solo`, а для `close()` и `cancelAll()`, которые ждут все линии, — любой
`SoloController`. В `SoloLanes` дедлок — внутри одной линии: правило сообщает
о теле, поставленном `_likes.enqueue(...)`, которое ждёт задачу из `_likes`,
поставленную туда прямо или методом, чьё тело ставит её туда, и называет линию.
Задача другой линии идёт насосом своей линии, а там, где линии не видно, как
у линии из геттера, линии, которую контроллер получает извне, а не объявляет
через `lane(...)` в теле конструктора, линии, объявленной в другом файле
(в суперклассе оттуда или в другой части библиотеки), задачи из поля или
параметра, тела дочерней задачи или обработчика накопителя, правило молчит.
`bare_await`, который сообщает об остальных простых ожиданиях тела, молчит
на ожиданиях, о которых сообщает это правило. Подробнее в разделе
[«Шаги детьми»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#шаги-детьми).

### key_per_request

```dart
Job<Profile> load(String id) => enqueue<Ready, Profile>(
  key: _Op.load, // key_per_request
  policy: Policy.droppable,
  (ctx) => ctx.abandonable(() => api.load(id)),
);
```

Политика сравнивает ключи, а не аргументы. При одном ключе на все `load(id)`
`Policy.droppable` принимает `load('grace')`, вызванный, пока идёт
`load('ada')`, за дубликат и отдаёт его вызывающему профиль Ады. Положите
аргумент в ключ: `key: (_Op.load, id)`. Правило берёт `enqueue` класса `Solo`
с `Policy.droppable` и `enqueueJob` с `job` и той же политикой, когда ключ
не читает ни одного параметра объемлющего метода или функции, а тело читает.
Ключ, который читает локальную переменную или параметр замыкания, правило
не трогает. Это линт, а не предупреждение: один ключ иногда задуман, когда
результат от аргумента не зависит. Подробнее в разделе
[«Ключ на каждый запрос»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#ключ-на-каждый-запрос).

Быстрое исправление заменяет ключ `K` записью `(K, a, b)` из параметров,
которые читает тело. Исправление предлагается, когда каждый из них сравнивается
по значению: `String`, число, `bool`, перечисление или один из них с `null`.

### ignore_failure_hides_bugs

```dart
SoloJob<Profile> load() => enqueue<Ready, Profile>(
  (ctx) => api.load(),
  isExpectedError: (e) => e is ApiException,
);

profiles.load().ignoreFailure(); // ignore_failure_hides_bugs
```

`isExpectedError` уже держит названные в нём ошибки тихими и пропускает баги
в зону, а `ignoreFailure()` прячет и их. Уберите `ignoreFailure()`: ожидаемые
ошибки останутся тихими, а баг по-прежнему будет замечен. Правило берёт
`ignoreFailure()` у задачи, которая пришла из `job` или `enqueue`
с `isExpectedError` или из `add` поля с `collect` или `accumulate` с ним, в том
числе через метод или функцию той же библиотеки, чьё тело — `=>` или один
`return`, когда задача дальше никому не нужна: сам вызов или каскад, значение
которого отброшено, как у `onPressed` кнопки. У страницы частых ошибок раздела
для этого правила нет. Это линт, а не предупреждение: задача, чей исход никому
не нужен, а отчёт оставлен хукам, может вызывать `ignoreFailure()` намеренно,
см.
[«Ответ за каждую ошибку»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/mistakes.md#ответ-за-каждую-ошибку).

### stale_emit

```dart
Job<void> setLiked(String postId, {required bool liked}) =>
    _likes.enqueue<Feed, void>((ctx) async {
      final feed = ctx.state;
      ctx.emit(feed.mark(postId, Mark(liked)));
      await ctx.join(() => api.setLiked(postId, liked: liked));
      ctx.emit(feed.mark(postId, Mark(liked, ++_confirmations))); // stale_emit
    });
```

В `SoloLanes` другие линии пишут, пока задача ждёт, и второй `emit` пишет
копию, прочитанную до ожидания, поверх того, что они написали: посты, которые
за это время опубликовала перезагрузка, пропадают. Читайте состояние там, где
задача пишет:
`ctx.emit(ctx.state.mark(postId, Mark(liked, ++_confirmations)))`.

Правило берёт `ctx.emit` в теле задачи, которая идёт в линии: в теле, отданном
линии, какой бы линия ни была, или в теле, поставленном в `SoloLanes` вокруг
него, включая тело дочерней задачи. Оно сообщает о записи, когда значение
построено на `ctx.state` или `ctx.stateAs<T>()` — через вызовы членов, чтение
свойств и индексов, каскады, приведения и `!`, в любой ветви `?:`, `??`
и выражения switch, прямо или через локальные переменные того же тела, —
а между чтением и записью в тексте задачи стоит `await` или `await for` тела
или действия, внутри которого запись: ожидание в одной ветви считается и для
записи в другой. Сообщение называет переменную, в которую ушло чтение. Запись
в действии `await ctx.join(...)` идёт раньше, чем задача приостанавливается,
и о ней правило не сообщает. Для чтения в самом `emit`,
`ctx.emit(ctx.state.withPosts(await ctx.abandonable(fetchPosts)))`, у правила
своё сообщение: дождитесь значения в локальную переменную до `emit`,
а `ctx.state` читайте в `emit` уже после неё.

У `Solo` другой линии нет, и там правило молчит. Это эвристика и линт,
а не предупреждение: копия, записанная обратно намеренно, для него выглядит
так же, как и часть, прочитанная до ожидания и наложенная после него на свежее
состояние: о `final pending = ctx.state.pending;` до ожидания
и `ctx.emit(pending.applyTo(ctx.state))` после него правило сообщает, поэтому
и `ctx.state.pending` читайте после ожидания. Оно не видит ответ сервера,
записанный целиком, `ctx.emit(await ctx.abandonable(api.fetchFeed))`, который
теряет написанное другими линиями точно так же, ни тело, переданное ссылкой
на метод, `_likes.enqueue(_like)`, ни значение, которое прочитал родитель,
а пишет его дочерняя задача, ни чтение и запись в разных проходах цикла.
Подробнее в разделе
[«Запись, которая бережёт работу другой линии»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/lanes.md#запись-которая-бережёт-работу-другой-линии).

### lane_outside_constructor

```dart
late final _reload = lane('reload'); // lane_outside_constructor

FeedController(this.api) : super(const Feed());
```

`SoloLanes` запечатывает набор линий через микрозадачу после конструктора,
а линия в поле `late final` объявляется при первом чтении поля, в первом вызове
метода, где `lane` бросает `StateError`. Объявляйте линии в теле конструктора,
`_reload = lane('reload');`, в поле `late final SoloLane<Feed> _reload;`.
Правило берёт `lane(...)` у `SoloLanes` везде, кроме самого тела конструктора
на `this` или `super`: в инициализаторе поля, в методе, в геттере, в функции,
объявленной в теле конструктора. Лямбда — тоже такая функция, хотя `map`
вызывает её сразу: о `_lanes = names.map((name) => lane(name)).toList();`
правило сообщает, а for в литерале списка,
`_lanes = [for (final name in names) lane(name)];`, объявляет те же линии прямо
в теле. О методе, который вызывает конструктор, правило тоже сообщает, хотя
вызов там работает: `await_own_queue` линию, объявленную там, тоже не видит.
Подробнее в разделе
[«Объявление линий»](https://github.com/vi-k/solo/blob/main/docs/ru/solo/lanes.md#объявление-линий).

## Версии

Плагин работает на Dart 3.10 и новее, с `analyzer` от 12.1 до 14. SDK Dart,
которому нужен `analyzer` 15, эту версию не загружает, и её правила молчат,
пока выпуск не поднимет границу.

Типы solo правила узнают по именам и библиотеке, откуда те пришли, и от пакета
не зависят. На версии solo, где имя сменилось, правило молчит, а не сообщает
о правильном коде. Правила ядра — это правила `async_job_lints`, и их изменения
перечисляет его
[список изменений](https://github.com/vi-k/solo/blob/main/docs/ru/async_job_lints/CHANGELOG.md).
