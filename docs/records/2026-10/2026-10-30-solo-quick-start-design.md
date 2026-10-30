# Вход в `solo`: короткий quick start и рецепт двух контроллеров — дизайн

> **Состояние на 2026-10-30:** сделано и смержено в `main` коммитом «docs:
> give solo a one-screen quick start and a two-controller recipe». Дизайн
> пересмотрен по ревью Opus (раздел «Ревью дизайна»), сделанная работа прошла
> второе ревью (раздел «Ревью работы»); расхождения с дизайном — в разделе «Что
> вышло».
> **Что это:** как сократить quick start README `solo` до одного экрана,
> куда уходит модель документации и как устроен рецепт «несколько контроллеров
> на экран».
> **Связанные записи:** `2026-10-30-prospects-review.md` (пункт 4 «Что
> предлагаю владельцу», находки Fable F3 и Opus F5),
> `2026-10-30-riverpod-and-bloc-design.md`.

## Зачем

Fable F3: quick start `solo` — 174 строки между `## Quick start` и следующим
заголовком, у ядра — 42. Первый экран README — то, что pub.dev показывает
первым, и у `solo` он целиком уходит на объявление четырёх состояний,
исключения и API, а до вызова доходит к концу второго экрана.

Opus F5: корневые задачи контроллера идут строго по одной, и об этом одна фраза
в `vs-bloc.md:88–89`. Пользователь bloc соберёт на одном контроллере долгую
перезагрузку ленты и быстрый «лайк», и лайк будет ждать ленту.

Владелец согласился идти по списку «Что предлагаю владельцу» по порядку; пункт
4 — «quick start в один экран, длинная версия — страницей; рецепт „несколько
контроллеров на экран“».

## Что держит нынешний quick start

Это не только вход, но и общая модель документации. Его `ProfileController`
с `Initial`, `Loading`, `Loaded`, `Failure`, `ApiException`, `key: 'load'`,
`Policy.droppable`, `ifFailed`, `ifCancelled` и `isExpectedError` берут:

- README `solo`: «The dozen calls» («cancel it as the quick start does», «as
  [Quick start](#quick-start) says» о провале, который уходит в зону), «Why
  `currentState` and not `state`» (`reload()` на `Loaded`);
- `doc/jobs.md:12`, `doc/state.md:610` и `:678`, `doc/errors.md:109`, `:151`,
  `:515`, `doc/testing.md:48` и `:315`, `doc/reference.md:47` — ссылкой
  и словами «the quick start»;
- тесты: `test/support/readme_quick_start.dart` (код раздела дословно)
  импортируют `readme_rakes_test`, `jobs_rakes_test`, `testing_page_fixtures`,
  `readme_stream`, `readme_reload`, `jobs_page`; `testing_rakes_test` вырезает
  раздел по заголовку и сверяет строку `isExpectedError`; `errors_stubs`,
  `state_profile_stubs` повторяют его API;
- `tool/flutter_snippets.py` собирает блоки `quick-start/ProfileState`
  и `quick-start/ProfileApi` против `flutter_solo`.

Поэтому длинную версию нельзя вырезать: модель переезжает вместе с ней,
и ссылки идут за ней.

## Короткий quick start

Раздел в один экран: сценарий одной фразой, один блок кода, трасса, абзац.
Около 70 строк между заголовками против нынешних 174; 42 строки ядра
недостижимы, пока блок объявляет состояния.

Сценарий: экран грузит имя профиля, потом пользователь тянет обновить
и отменяет обновление до ответа. `ProfileApi` в блок не входит: о нём одна
фраза, как о `Database` у ядра, — «`ProfileApi` is your client; its
`fetchName()` returns the name». Запускаемая копия —
`packages/solo/example/bin/quick_start.dart` с API, который отвечает через 20
мс; сторож требует, чтобы блок README стоял в ней дословно. `ProfileApi` там —
`class`, а не `final class`: страница тестов реализует его фейком.

```dart
import 'package:solo/solo.dart';

sealed class ProfileState {
  const ProfileState();
}

final class Initial extends ProfileState {
  const Initial();
}

final class Loading extends ProfileState {
  const Loading();
}

final class Loaded extends ProfileState {
  final String name;

  const Loaded(this.name);
}

final class ProfileController extends Solo<ProfileState> {
  final ProfileApi api;

  ProfileController(this.api) : super(const Initial());

  Job<String> load() => enqueue((ctx) async {
    ctx.emit(const Loading());
    final name = await ctx.abandonable(api.fetchName);
    ctx.emit(Loaded(name));
    return name;
  });
}

Future<void> main() async {
  final profile = ProfileController(ProfileApi());
  profile.addListener(() {
    switch (profile.currentState) {
      case Initial():
        print('initial');
      case Loading():
        print('loading');
      case Loaded(:final name):
        print('loaded $name');
    }
  });

  print(await profile.load().value);

  // The user pulls to refresh, then cancels it before the answer.
  final refresh = profile.load();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await refresh.cancel();
  print(refresh.outcome);

  await profile.close();
}
```

Ожидаемая трасса (проверить зондом при работе):

```text
loading
loaded Ada Lovelace
Ada Lovelace
loading
Cancelled(manual)
```

Абзац под трассой: `enqueue` ставит задачу в очередь контроллера, и задачи идут
по одной; `ctx.emit` меняет состояние, `addListener` слышит его внутри
изменения; `ctx.abandonable` — место, где отмена кончает ожидание; `job.value`
и `job.cancel()` — ручка вызывающего. Ожидание перед `cancel()` даёт обновлению
начаться: задача, отменённая до старта тела, его не запускает и состояния
не трогает. Отменённое обновление оставило контроллер в `loading`, и вывести
его оттуда некому —
[State after failure or cancellation](doc/state.md#state-after-failure-or-cancellation)
начинается с этого `load` и даёт ему состояние, которое публикуется при отмене.
Слушатель не снимается: `close()` снимает всех; во Flutter слушают через
`listen` или виджеты `flutter_solo`.

Отмена остаётся (открытый вопрос 1 закрыт ревью): README обещает её в первом
абзаце, тур ссылается на «cancel it as the quick start does», ядро открывается
отменой. Оставшийся `loading` не недоделка входа, а первая попытка раздела
`state.md`, который уже так начинается.

## Модель документации — в начало `doc/jobs.md`

Новой страницы нет (ревью, H1): её четыре шага уже рассказаны — состояние после
провала и отмены в `state.md`, ключ и политика в `jobs.md`, провал, который
никто не читает, в `errors.md` и `testing.md`.

`doc/jobs.md` открывается разделом «The profile controller» (рабочее имя):
нынешний `ProfileController` целиком — состояния `Initial`, `Loading`,
`Loaded`, `Failure`, `ApiException`, `ProfileApi`, `load()`
с `enqueue<ProfileState, String>`, `key`, `policy`, `ifFailed`, `ifCancelled`,
`isExpectedError` — ответом, без попытки: ошибаться тут не на чем (правило 71).
Одна фраза: это контроллер quick start с тем, что есть у контроллера
в приложении; страницы пакета опираются на него. Под кодом — таблица: параметр,
что делает, раздел, где объяснён. Рабочий тип `W` определён здесь одной
фразой; в README его определение переезжает в «Why `currentState` and not
`state`», которое и так пишет `enqueue<Loaded, String>`.

Нынешний «Jobs and results» идёт вторым и говорит «`profile.load()` below is
the one from [The profile controller](#the-profile-controller)».

Ссылки «the quick start» на модель переходят на этот раздел: `jobs.md:12`,
`errors.md:109`, `:151`, `:515`, `testing.md:48`, `:315`, `reference.md:47`
(конструктор `Solo(initialState)` — на quick start остаётся, он там есть),
`state.md:678`. `state.md:610` остаётся на quick start: короткий контроллер
публикует `Loading` до ожидания, как раздел и говорит.

Из README уходят: блок `SoloStream` (есть в `state.md`, «Observing state»),
абзац о ненаблюдённом `Failed` (`errors.md`), пример отмены до старта
(`cancellation.md`). Тур «The dozen calls» ссылается о провале в зоне
на `errors.md#handled-and-unhandled-failures`, а не на quick start.

## Рецепт: лайк, который не ждёт ленту

Раздел `doc/jobs.md` после «Queue and policies», заголовок вида «A tap that
does not wait for a reload».

- **Требование.** Лента грузится секунды; лайк должен уйти сразу, а лайк
  и снятие лайка одного поста — по порядку.
- **Первая попытка** — словарь API ведёт к ней: `reload` и `like` в одном
  `FeedController`, каждый под своим ключом. Трасса: лайк нажат во время
  перезагрузки, ушёл после неё.
- **Вторая попытка** (если зонд подтвердит) — лайк мимо очереди через
  `externalSetState` в состояние ленты: идущая перезагрузка публикует свой
  снимок и затирает его. Та же гонка, что «Ordering updates to shared state»
  в `vs-bloc.md`.
- **Ответ** — контроллер на каждый порядок. Принцип уже назван в `state.md`, «A
  board of its own»: очередь, где стоят только короткие задачи; рецепт
  ссылается на него и тратит место на новое. `LikesController` с `like` /
  `unlike`; его состояние — карта `postId →` отметка, поверх поля поста.
  - **Когда запись уходит.** Запись помнит, когда лайк подтверждён; лента
    помнит, когда отправила перезагрузку, и по её концу зовёт
    `likes.settle(sentAt)`, который снимает записи, подтверждённые раньше.
    Перезагрузка, отправленная до подтверждения, несёт старое значение,
    и запись остаётся.
  - **Откат.** `ifFailed` снимает запись: оптимистичная отметка уходит.
  - Одна очередь `LikesController` упорядочивает и лайки разных постов:
    за медленным лайком следующий ждёт. Для лайков это приемлемо, и рецепт это
    говорит.
- **Альтернатива одной фразой.** «A delayed start» на той же странице держит
  долгую работу в `Job` вне очереди и ставит в очередь только короткий шаг
  публикации; так лайк проходит и в одном контроллере, когда результат
  перезагрузки можно опубликовать коротким шагом.
- **Не помогают:** `ctx.unattended` — задача, которая его зовёт, сама ждёт
  в очереди; дети — живут только внутри идущего тела. Политики конкурентных
  корневых задач нет.
- **Flutter.** Одна фраза: два контроллера на одном виджете —
  `Listenable.merge`, ссылкой на таблицу вопросов README `flutter_solo`.

Ссылки на рецепт: строка в «Recipes» README `solo`; «Coming from bloc» («all
root jobs share one queue»); `vs-bloc.md:88–89`; строка «Several controllers on
one screen?» таблицы вопросов `flutter_solo`.

## Что меняется

- README `solo` и перевод: «Quick start»; определение `W` в «Why
  `currentState`»; ссылка тура о провале в зоне; «Recipes»; «Coming from bloc».
- `packages/solo/example/bin/quick_start.dart` — запускаемая копия; сторож
  дословности в тестах `solo`.
- `doc/jobs.md` и перевод: раздел модели в начале, рецепт; `state.md`,
  `errors.md`, `testing.md`, `reference.md` и переводы — ссылки и слова;
  `vs-bloc.md` и перевод — ссылка; README `flutter_solo` и перевод — ссылка.
- Тесты `packages/solo/test/`: `readme_quick_start.dart` держит короткий quick
  start, модель — новый support-файл страницы `jobs.md`; шесть импортёров
  переходят на него; `readme_rakes_test` — новые проверки quick start (вместо
  «four immutable states»); `testing_rakes_test` сверяет модель с разделом
  `jobs.md`, а не с README; `readme_stream.dart` уходит вместе с блоком.
  Рецепт — support-файлы и тесты по образцу `jobs_rakes_test`.
- `tool/flutter_snippets.py`: тест quick start переписывается — блок теперь
  с `main`, без `droppable`.
- `CHANGELOG.md` `solo` и перевод — строка в Documentation.
- Проверки: `check_doc_shape.py` (раздел начинается с кода или таблицы,
  попытка — с пометки), `check_translations.py`, `check_links.py`, ширина
  и заливка.

## Ревью дизайна

Ревьюер на Opus прочёл первую версию дизайна в копии дерева, прогнал короткий
quick start и зонды на первые попытки. Находки пересказаны коротко.

**H1. Страница `first-controller.md` пересказала бы три готовых раздела.**
`state.md:607` уже открывается контроллером quick start и сильной первой
попыткой; `errors.md:149–283` и `testing.md:245–360` разбирают провал без
`isExpectedError`; `testing.md:53–70` печатает модель целиком. Предложено:
страницы нет, модель — ответом в начале `jobs.md`, ссылки — на неё.

Вердикт: подтверждаю по тексту: `state.md:609` — «The profile controller of the
Quick start … publishes `Loading` before its load starts waiting»,
`errors.md:151` — «the profile from the quick start, without its
`isExpectedError`», `testing.md:48` — модель со ссылкой на quick start.
Принято: раздел «Модель документации — в начало `doc/jobs.md`».

**H2. Карта `postId → liked` не чистится и перекрывает новые данные сервера.**
Зонд: после свежей перезагрузки, где сервер снял лайк, карта всё ещё показывает
`true`. Снимать запись по концу любой перезагрузки тоже неверно: отправленная
до лайка несёт старое значение.

Вердикт: принято по рассуждению: в первой версии запись не уходит никогда. Его
зонд `recipe.dart` в моей копии не собрался (ошибки типов, видимо, правленый
после прогона), поэтому вывод я не повторял; трассы рецепта снимет стенд при
работе. Правило — «Когда запись уходит» в разделе рецепта, плюс откат через
`ifFailed`.

**M3. Рецепт не отводит альтернативы и повторяет `state.md`.** «A delayed
start» пропускает лайк и в одном контроллере; `externalSetState` — естественная
вторая попытка, её затирает снимок перезагрузки; `ctx.unattended` и дети
не помогают; принцип уже назван в «A board of its own».

Вердикт: подтверждаю: `state.md:502–527` — вторая попытка «acceptance waits
behind the recording» и ответ своим контроллером. Принято: ссылка на принцип,
вторая попытка — если её подтвердит зонд, альтернатива одной фразой.

**M4. Бюджет в 60 строк недостижим.** Блок с API — 57 строк, раздел — около 80.
У ядра 42, потому что `Database` вне блока.

Вердикт: принято: `ProfileApi` вне блока, копия
в `example/bin/quick_start.dart`, цель — около 70 строк.

**M5. README теряет определение `W`; «до символа» пропускает шаги.**
Единственное определение рабочего типа — в quick start (`README.md:118–122`),
а тур и «Why `currentState`» им пользуются.

Вердикт: принято: `W` — в «Why `currentState`» и в разделе модели. Вопрос
«до символа» снят вместе со страницей: модель переезжает как есть.

**M6. `final class ProfileApi` — ловушка для копирующего.** `testing.md:82`
реализует его фейком.

Вердикт: подтверждаю: `class FakeProfileApi implements ProfileApi`. Принято:
`class`, и он вне блока.

**L7. `super(const Loading())` как начальное состояние.** Первая строка трассы
публикует тот же объект; отмена до старта оставляет `Loading` навсегда,
и `ifCancelled` тут не поможет.

Вердикт: принято: начальное `Initial`.

**L8. «Уходит» — это `close()`, а ожидание перед отменой надо объяснить.**

Вердикт: принято: «cancels the refresh» и фраза об ожидании.

**L9. Слушатель не снимается.**

Вердикт: принято: полфразы о `close()` и о `listen` во Flutter.

**L10. Пропущенные следствия:** тест quick start в `flutter_snippets.py`
переписывается, а не переименовывается; `readme_rakes_test.dart:169` держит
«four immutable states»; в боковой панели первым стоит Overview; ссылка
из «Coming from bloc».

Вердикт: принято, раздел «Что меняется»; страницы в боковой панели больше нет.

## Что вышло

Сделано по разделу «Что меняется», с такими расхождениями.

- Quick start README `solo` — 89 строк между заголовками, а не около 70: блок,
  трасса и абзац под ней с определением шагов. Короче не вышло без потери
  отмены, которую обещает первый абзац README.
- В «Coming from bloc» ссылки на рецепт нет. `check_doc_shape.py` держит
  последний раздел README в десяти строках прозы, и фраза со ссылкой их
  превысила. Раздел вернулся к прежнему тексту; рецепт достаётся из строки
  «Recipes» и из фразы `vs-bloc.md` об отдельных контроллерах.
- Рецепт говорит о `flutter_solo` словами, без ссылки: `check_links.py`
  запрещает страницам `solo` ссылаться на другой пакет. Строка заметок README
  `flutter_solo` ведёт на рецепт ссылкой на GitHub, перевод — относительной
  ссылкой на `docs/ru/solo/jobs.md`.
- Отметка снимается не по времени отправки, как в дизайне (`settle(sentAt)`),
  а по номеру подтверждения: лента берёт число подтверждений, когда отправляет
  перезагрузку. Время в тесте и в приложении разное, а счётчик один. Вместо
  `like` и `unlike` — один `setLiked(postId, liked:)`.
- Альтернатива из «A delayed start» не спасает одного контроллера, как обещал
  дизайн: зонд показал, что лайк тогда уходит сразу, но перезагрузка всё равно
  публикует то, что было на сервере до лайка. Фраза рецепта говорит именно это:
  отметки нужны и там.
- Вторая попытка (`externalSetState`) подтверждена зондом и стоит в рецепте.

Сторожа: `test/likes_recipe_test.dart` — зонды всех строк таблицы рецепта
и прозы с числами; `test/jobs_rakes_test.dart` держит код рецепта дословностью
support-файлов; `test/readme_rakes_test.dart` — короткий quick start и таблицу
раздела модели.

## Ревью работы

Ревьюер на Opus прочёл сделанную работу в отдельной копии дерева на коммите
с английской частью и тестами и гонял зонды на код рецепта. Находки пересказаны
коротко.

**H1. «Coming from bloc» роняет `check_doc_shape.py`.** Фраза со ссылкой
на рецепт вывела последний раздел README за десять строк прозы.

Вердикт: подтверждаю прогоном `check_doc_shape.py`. Сделано: раздел вернулся
к прежнему тексту в оригинале и переводе, рецепт достаётся из «Recipes»
и `vs-bloc.md`; подробности — в разделе «Что вышло».

**M1. Второе нажатие во время лайка в пути ждёт.** Отметка публикуется, только
когда задача начинается. Экран, который переключает сердечко по `shownLiked`,
теряет нажатия: при лайке в 300 мс три нажатия подряд оставляют пост на сервере
без лайка.

Вердикт: подтверждаю зондом. Сделано: рецепт говорит это прямо — второе нажатие
и его отметка ждут первого лайка, а экран берёт новое значение из своего
последнего нажатия, а не из `shownLiked`; строка таблицы «A second tap on the
post while its like is on its way». Зонды в `likes_recipe_test.dart`: второе
нажатие ждёт; три нажатия по `shownLiked` повторяют второе, три по последнему
нажатию оставляют лайк.

**M2. Строка таблицы модели говорит неверное правило.** «any other error goes
on to the zone» — а ошибка, которую кто-то читает, в зону не идёт.

Вердикт: подтверждаю по `isExpectedError`. Сделано: «any other error that
nobody reads goes on to the zone» в `jobs.md` и переводе, сторож
в `readme_rakes_test.dart` держит новую фразу.

**L1. Отменённый лайк оставляет отметку навсегда.** Без `ifCancelled` отметка
без номера остаётся поверх ленты.

Вердикт: принято. Сделано: `ifCancelled` возвращает `before`, как `ifFailed`.
Зонд показал то, о чём ревью не говорило: `ctx.join` держит задачу, пока запрос
не ответит, поэтому отмена срабатывает после ответа, а сервер лайк уже принял.
Строка таблицы «The like is cancelled» говорит это: пост показывает то, что
до нажатия, пока перезагрузка не принесёт слово сервера.

**L2. Ветка `null` в `settle` мертва.** `settle` стоит в той же очереди, что
и лайки, и отметки без номера не застаёт.

Вердикт: подтверждаю; с L1 это верно для каждого исхода лайка. Сделано:
`mark.confirmation! > seen`, проза объясняет, почему номер есть всегда; фраза
«its queue holds nothing but likes» стала «only short jobs, the likes and
`settle`»; тест «a like on its way is settled by no reload» переименован
в «settle waits behind a slow like and keeps its numbered mark».

**L3. Фраза об `ctx.unattended` говорит о задаче вообще.**

Вердикт: принято. Сделано: «a like that calls it waits in the queue first».

**L4. `FeedApi` и `ApiException` не названы до кода.**

Вердикт: принято. Сделано: первый абзац рецепта называет `FeedApi` и говорит,
что `setLiked` бросает `ApiException`, когда запрос не удался.

**L5. Проза рецепта ничем не держится.** Числа и строки таблицы могут разойтись
с зондами, а `droppable` второй перезагрузки не проверен.

Вердикт: принято. Сделано: `_says` в `likes_recipe_test.dart` держит числа
прозы и каждую строку таблицы в тесте, который их гоняет; зонды на ответы
сервера и на то, что `droppable` возвращает вторую перезагрузку первой задачей.

**L6. Повторы.** Вступление `jobs.md` дважды говорит «build on»; `W` определён
и в разделе модели, и в абзаце о камере; комментарий `errors.md` называет
`jobs.md`, а не контроллер.

Вердикт: принято. Сделано: вступление сокращено; абзац о камере ссылается
на раздел модели; комментарий — «the load() of the profile controller», вместе
с `test/support/errors_page.dart`. Переводы — тем же коммитом.

**L7. Мелочи:** `settle` публикует и тогда, когда ничего не снял; quick start
в 89 строк; строка в CHANGELOG.

Вердикт: принято. Сделано: `settle` публикует, только если снял отметку. Длина
quick start остаётся (раздел «Что вышло»); строка CHANGELOG уже стоит.
