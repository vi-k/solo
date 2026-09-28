# Dartdoc `async_job` вне порядка работ (волна А)

> **Состояние на 2026-09-28:** сделано и смержено.
> **Что это:** отчёт о правке dartdoc `async_job` по M9, L18, L20, L22, L23,
> L24, L26 и L79 из `2026-09-26-async-job-project-review.md` — первой волне
> пункта 8 его порядка работ.
> **Связанные записи:** `2026-09-26-async-job-project-review.md`,
> `2026-09-28-async-job-humanizer-report.md` (пункт 7, после которого нашлись
> эти находки).

После пункта 7 порядка работ оказалось, что у M9 и 21 Low вердикт принят,
а итога нет: в порядок работ они не попали, а решение владельца им не нужно.
Они разложены на четыре волны в пункте 8 порядка работ записи ревью. Эта —
первая, только dartdoc; код ядра не менялся.

## Что сделано

- **M9.** Пример `Job.ignore` даёт задаче наблюдателя:
  `Job<void>(observer: reporter, (ctx) => ctx.wait(device.close)).ignore();`.
- **L18.** `disown`, `_Cleanup` и `addCleanup` называют `run` рядом с `wait`
  и `join`.
- **L20.** `isChild` и `children` называют вход — `startChild`, через который
  идут `run`, `runAll` и `each`. Сверх вердикта: `isChild` говорит, что
  ребёнок, которому родитель отказал, тоже ребёнок — зонд показал
  `isChild=true` у такого.
- **L22.** `run`: `StateError` для задачи, которая уже кончилась, в том числе
  отменённой до старта, для вызова после конца тела и из `unattended`.
  `runAll`: повтор хэндла — `ArgumentError`. `each`: типы ошибок.
  `JobBase.start`: отменённая до старта задача, как у `DeferredJob.start`.
  `adoptedBy`: как отказать, куда выходит ошибка и что ребёнок остаётся
  `created`. `cascadeToChildren`: спрашивает всех и бросает первую ошибку.
- **L23.** Ни одна первая строка dartdoc не говорит словами `solo`:
  `ManualCancelReason` — «the default reason of `Job.cancel`», `check`,
  `started`, `finished`, `beforeChildStart` получили свою первую строку,
  а `solo` ушёл в пояснение «for example». Так же переписаны пояснения
  у `Job.debug`, `key`, `reportToZone`, `JobContextBase`, `uncancellable`,
  `disown`, `unattended` и `Cancelled.description`. У `unattended` снята фраза
  об `emit` `solo`: у читателя ядра нет ни `emit`, ни контроллера. Конструктор
  `JobContextBase` и `Job.deferred` описаны контрактом, а не устройством;
  `Job.deferred` говорит, что отменённая до старта задача кончается `Cancelled`
  со `started: false` и тело не запускается.
- **L24.** Страница библиотеки: что это, с чего начать (`Job` и `JobContext`),
  что `Job` — не `Future`, и адрес руководств на сайте из `documentation:`
  в `pubspec.yaml`.
- **L26.** `log`: бесплатно только сообщение, переданное объектом или
  замыканием, строка с интерполяцией строится всегда; пример с замыканием.
  `onLog`: вызвать замыкание — соглашение слушателя.
- **L79.** `onCancel`: колбэки идут в порядке регистрации, каждый один раз.
  Тесты `waiting_test.dart` и `cancel_test.dart`, которые держали этот порядок,
  теперь держат контракт.

В `## Unreleased` `CHANGELOG.md` — запись в «Documentation».

## Ревью

Независимый ревьюер Opus получил дифф и тексты находок, без моих рассуждений,
и проверял утверждения чтением кода и зондом с движком, у которого `adoptedBy`
и `cancelWith` бросают. Всё, что он проверил, подтвердилось; замечаний семь,
все Low или мельче.

- `isChild`: «it has a parent» неверно — `finish` отпускает родителя,
  а у задачи нет публичного `parent`. Стало «its [level] is its parent's plus
  one». Принято.
- `run`: список `StateError` пропускал задачу, которая кончилась, не начавшись.
  Принято, и этот текст теперь согласен с `JobBase.start`.
- Страница библиотеки: ревьюер просил ссылки `[Job]` и `[JobContext]`.
  Не принято: файл только экспортирует, и `dart analyze` отвечает на такие
  ссылки `comment_references`; оставлен код-спан.
- L23 сделан не везде: остались `solo` без «for example» у `uncancellable`,
  `disown` и `unattended`. Принято, переписаны; фраза об `emit` у `unattended`
  снята. Упоминания в `cancel`, `cancelWith`, классе `JobObserver`
  и `Cancelled.by` оставлены: они уже читаются как пример.
- Запись CHANGELOG не называла L20 и L23. Принято, дописано.
- `adoptedBy`: у `runAll`, если отказали не первой ветке, ошибка приходит через
  future, после остановки уже запущенных веток. Принято, оговорка в тексте.
  Там же ревьюер нашёл устаревший комментарий в `run_all.dart`: «`startChild`
  has already finished this child» неверно для отказа до усыновления.
  Переписан.
- `log` мог бы ссылаться на `onLog`. Не принято: оговорка стоит в `onLog`,
  а фраза читается и так.

## Проверки

`packages/async_job`: `dart format`, `dart analyze`, `dart test` — 851,
`dart doc --dry-run` — 0 предупреждений. Из корня: `reflow.py --check`,
`check_line_width.py`, `check_links.py`, `check_translations.py`,
`check_doc_shape.py`, `build_site_test.py`.
