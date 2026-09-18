> **Состояние на 2026-09-09:** ревью проведено, все восемь находок
> подтверждены приёмкой и закрыты — пять кода в `e1776cf`, две примера в
> `e6e850a`, одна документа в `3049d98`.
> **Что это:** полное независимое ревью пакета `solo` перед его первой
> публикацией, сделано `codex exec` на отдельном клоне.
> **Связанные записи:** 2026-09-06[5]-solo-docs-review.md,
> 2026-09-09[3]-solo-user-review.md.
> **Наработки:** задание, логи команд и зонды приёмки —
> `.artifacts/2026-09-09-solo-project-review/`, вне гита.

## Приёмка

Ревьюер не выполнил ни одного прогона: песочница не пустила ни `dart`
(бинарь в PATH — из FVM, а тому нужен свой кеш; я не дал
`--add-dir ~/fvm`), ни `git checkout` для возврата подмен (`workspace-write`
не пускает на запись `.git` — ни в worktree, ни в клоне). Отказы приведены
им дословно; все находки получены чтением.

Все восемь проверены мной. Пять поведенческих воспроизведены зондом
(`verify_probes_test.dart` в каталоге наработок), две — прогоном на
примере, одна — чтением. **Не подтвердилась ни одна не полностью:**
воспроизвелось всё, включая обе High. После правок каждый из пяти новых
тестов проверен подменой своего же исправления — краснеет ровно свой.

# ПРОГОН

Объект: `packages/solo` в клоне
`/Users/user/development/my/solo/.artifacts/solo-review-project`,
HEAD `4f3bdd694ab4c06263fabd5caf8b64f83e6f6bc4`.
Контракты наследования сверены непосредственно с hosted-кодом
`/Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/`;
именно этот пакет указан в существующем
`packages/solo/.dart_tool/package_config.json`.

**Ни один Dart-прогон не состоялся.** Все шесть запрошенных проверок
вызваны, каждая повторена один раз после отказа песочницы. Оболочка FVM
останавливается до запуска Dart. Поэтому `No issues found!`, 266 тестов
пакета, 7 тестов примера, отсутствие изменений форматирования,
`0 warnings, 0 errors` документации и `0 warnings` публикационного
dry-run здесь **не подтверждены**. Число исполненных тестов — 0.
Во связке проверки примера `dart test` не был вызван: предшествующий
`dart analyze` завершился ошибкой, и `&&` остановил связку.

**Подмен — 0.** До изменения файлов проверена возможность требуемого
возврата на неизменённом `packages/solo/lib/src/solo_base.dart`.
Обе попытки `git checkout --` получили отказ на `.git/index.lock`.
После этого код не менялся: подмена без возможности вернуть файл
нарушила бы правило задания. Обходов отказов, другого SDK, эскалаций,
коммитов и изменений `docs/handoff.md` не было. Все вызовы
`git status --short` дали пустой вывод.

Вне клона подготовлен [probes.dart](probes.dart) с восемью отдельными
сценариями. **Он не скомпилирован и не исполнен.** Приведённые в находках
последствия выведены из кода, а не сняты этим зондом. Имена сценариев:
`add-close`, `rule-cancel`, `checkpoint-cancel`, `child-rule-error`,
`debug-close`, `camera-close-error`, `camera-init-error`,
`rule-error-zone`. Зонд печатает наблюдения при будущем запуске;
утверждений о красном или зелёном тесте в отчёте нет.

Шаблон для самостоятельной перепроверки; **эта команда не выполнялась**:

```sh
rtk proxy dart --packages=/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo/.dart_tool/package_config.json /Users/user/development/my/solo/.artifacts/2026-09-09-solo-project-review/probes.dart add-close
```

## Выполненные проверки и дословные отказы

Команды приведены с фактическим префиксом `rtk proxy` из `RTK.md`;
он передаёт вывод без фильтрации. Рабочий каталог задавался параметром
инструмента, а не командой `cd`. В таблице указана последняя строка
полученного вывода; завершительный перевод строки не считается
дополнительной пустой строкой.

**1. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project`.

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project checkout -- packages/solo/lib/src/solo_base.dart
```

Код завершения: 128. Полный вывод; последняя строка — строка 1 блока:

```text
fatal: Unable to create '/Users/user/development/my/solo/.artifacts/solo-review-project/.git/index.lock': Operation not permitted
```

**2. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project`.

```sh
rtk proxy dart --version
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.56986: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**3. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project`.

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project checkout -- packages/solo/lib/src/solo_base.dart
```

Код завершения: 128. Полный вывод; последняя строка — строка 1 блока:

```text
fatal: Unable to create '/Users/user/development/my/solo/.artifacts/solo-review-project/.git/index.lock': Operation not permitted
```

**4. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project`.

```sh
rtk proxy dart --version
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57522: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**5. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart analyze
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57551: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**6. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart analyze
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57580: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**7. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart test
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57611: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**8. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart test
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57640: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**9. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart format --output=none --set-exit-if-changed lib test
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57669: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**10. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart format --output=none --set-exit-if-changed lib test
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57698: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**11. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo/example`.

```sh
rtk proxy zsh -c 'dart analyze && dart test'
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57728: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**12. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo/example`.

```sh
rtk proxy zsh -c 'dart analyze && dart test'
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57758: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**13. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart doc --dry-run
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57787: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**14. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart doc --dry-run
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57816: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**15. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart pub publish --dry-run
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57845: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**16. Рабочий каталог:** `/Users/user/development/my/solo/.artifacts/solo-review-project/packages/solo`.

```sh
rtk proxy dart pub publish --dry-run
```

Код завершения: 1. Полный вывод; последняя строка — строка 2 блока:

```text
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 71: /Users/user/fvm/versions/stable/bin/cache/engine.stamp.tmp.57877: Operation not permitted
/Users/user/fvm/versions/stable/bin/internal/update_engine_version.sh: line 78: /Users/user/fvm/versions/stable/bin/cache/engine.realm: Operation not permitted
```

**Проверки состояния клона** (рабочий каталог — корень клона):

| Команда дословно | Код | Последняя строка |
| --- | --- | --- |
| <code>rtk proxy git status --short</code> | 0 | <code>〈вывод пуст〉</code> |
| <code>rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project status --short</code> | 0 | <code>〈вывод пуст〉</code> |
| <code>rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project rev-parse HEAD</code> | 0 | <code>4f3bdd694ab4c06263fabd5caf8b64f83e6f6bc4</code> |
| <code>rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project status --short</code> | 0 | <code>〈вывод пуст〉</code> |

## Команды чтения

Вывод длинных первоначальных чтений частично усекался инструментом;
значимые для находок участки прочитаны отдельными командами ниже.
Чтения не являются проверкой исполнения кода.
Все команды этого подраздела выполнялись из корня клона.

<details>
<summary>Журнал чтения основного ревьюера</summary>

| Команда дословно | Код | Последняя строка |
| --- | --- | --- |
| <code>cat /Users/user/.codex/RTK.md</code> | 0 | <code>```</code> |
| <code>cat AGENTS.md</code> | 0 | <code>номера версии.</code> |
| <code>cat docs/handoff.md</code> | 0 | <code>  движке очередь устроена иначе, решение не перенесено.</code> |
| <code>cat docs/architecture.md</code> | 0 | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>cat docs/conventions.md</code> | 0 | <code>- Публикация на pub.dev — только по правилам из `AGENTS.md`.</code> |
| <code>cat docs/backlog.md</code> | 0 | <code>  `// ignore:`, чтобы так сделать.</code> |
| <code>cat /Users/user/.codex/skills/project-review/SKILL.md /Users/user/.agents/skills/code-critic/SKILL.md</code> | 0 | <code>Then briefly state what was reviewed and any important limitations, such as unavailable tests, missing call sites, incomplete platform implementations, inability to execute the code, or unresolved external API behavior.</code> |
| <code>rtk proxy sed -n '1,240p' docs/handoff.md</code> | 0 | <code>  `ctx.onCancel`, и на нём видно, чем `join` отличается от `uncancellable`</code> |
| <code>rtk proxy cat docs/architecture.md</code> | 0 | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>rtk proxy cat docs/conventions.md</code> | 0 | <code>- Публикация на pub.dev — только по правилам из `AGENTS.md`.</code> |
| <code>rtk proxy cat docs/backlog.md</code> | 0 | <code>  `// ignore:`, чтобы так сделать.</code> |
| <code>rtk proxy rg --files -g AGENTS.md -g '*.dart' -g '*yaml' -g '*.md' packages/solo</code> | 0 | <code>packages/solo/test/support/test_solo.dart</code> |
| <code>rtk proxy cat docs/architecture.md</code> | 0 | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>rtk proxy sed -n '241,550p' docs/handoff.md</code> | 0 | <code>остановки, о котором договорились с владельцем — круг, вернувший только</code> |
| <code>rtk proxy sed -n '551,830p' docs/handoff.md</code> | 0 | <code>`2026-09-05[1]-generators-migration-review.md`: переезд верен,</code> |
| <code>rtk proxy sed -n '831,1150p' docs/handoff.md</code> | 0 | <code>  движке очередь устроена иначе, решение не перенесено.</code> |
| <code>rtk proxy cat 'docs/records/2026-09-06[5]-solo-docs-review.md'</code> | 0 | <code>  `issue_tracker` и `topics` на месте.</code> |
| <code>rtk proxy cat packages/solo/lib/src/solo_base.dart</code> | 0 | <code>}</code> |
| <code>rtk proxy sed -n '241,320p' docs/handoff.md</code> | 0 | <code>**README ядра прочитан свежим взглядом**, `codex exec` на копии дерева, —</code> |
| <code>rtk proxy sed -n '285,605p' 'docs/records/2026-09-06[5]-solo-docs-review.md'</code> | 0 | <code>〈пустая строка〉</code> |
| <code>rtk proxy cat packages/solo/pubspec.yaml packages/solo/.dart_tool/package_config.json packages/solo/example/pubspec.yaml</code> | 0 | <code>  test: ^1.26.3</code> |
| <code>rtk proxy cat packages/solo/lib/src/job.dart packages/solo/lib/src/job_context.dart</code> | 0 | <code>}</code> |
| <code>rtk proxy cat packages/solo/lib/src/solo.dart packages/solo/lib/src/queue.dart packages/solo/lib/src/policy.dart packages/solo/lib/src/observer.dart packages/solo/lib/src/solo_cancel_reason.dart packages/solo/lib/solo.dart</code> | 0 | <code>export 'src/solo_cancel_reason.dart';</code> |
| <code>rtk proxy sed -n '1,290p' packages/solo/README.md</code> | 0 | <code>**Handing a resource over.** When the body gives the resource to someone</code> |
| <code>rtk proxy rg -n 'void start&#124;void finish&#124;void cancelWith&#124;void _markCancelled&#124;void _debug&#124;Future&lt;void&gt; _execute&#124;bodyEnded&#124;adoptedBy&#124;whenDone&#124;notifyObserver&#124;notifyError' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_base.dart</code> | 0 | <code>1030:  void start() =&gt; super.start();</code> |
| <code>rtk proxy rg -n 'Job&lt;T&gt; run&#124;beforeChildStart&#124;throwIfFinished&#124;throwIfDisposing&#124;cancelOwnJob&#124;void check' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_context.dart</code> | 0 | <code>863:      final rejection = beforeChildStart(child);</code> |
| <code>rtk proxy sed -n '290,460p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_base.dart</code> | 0 | <code>        // Marked before the cascade, and only marked: a callback of a child</code> |
| <code>rtk proxy sed -n '560,738p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_base.dart</code> | 0 | <code>  /// Runs the body with [ctx]; a subclass narrows the type with</code> |
| <code>rtk proxy sed -n '756,820p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_base.dart</code> | 0 | <code>      while (_cleanups.isNotEmpty) {</code> |
| <code>rtk proxy sed -n '795,900p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_context.dart</code> | 0 | <code>    // which call threw. The cleanup window stays open on purpose — a</code> |
| <code>rtk proxy sed -n '290,610p' packages/solo/README.md</code> | 0 | <code>〈пустая строка〉</code> |
| <code>rtk proxy sed -n '375,505p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_context.dart</code> | 0 | <code>    FutureOr&lt;T&gt; Function() action, {</code> |
| <code>rtk proxy cat packages/solo/test/start_rules_test.dart packages/solo/test/leaked_context_test.dart</code> | 0 | <code>}</code> |
| <code>rtk proxy cat packages/solo/example/lib/src/camera_controller.dart packages/solo/example/lib/src/camera_state.dart packages/solo/example/lib/src/fake_camera_hardware.dart</code> | 0 | <code>}</code> |
| <code>rtk proxy rg -n -C 10 'throw&#124;canStart&#124;onError&#124;Failed' packages/solo/test/children_test.dart</code> | 0 | <code>514-      parent = ForeignJob&lt;void&gt;((ctx) async {</code> |
| <code>rtk proxy cat packages/solo/test/zone_test.dart</code> | 0 | <code>}</code> |
| <code>rtk proxy sed -n '610,980p' packages/solo/README.md</code> | 0 | <code>〈пустая строка〉</code> |
| <code>rtk proxy cat packages/solo/example/test/camera_controller_test.dart packages/solo/example/README.md packages/solo/CHANGELOG.md packages/solo/analysis_options.yaml packages/solo/.pubignore</code> | 0 | <code>example/pubspec_overrides.yaml</code> |
| <code>rtk proxy rg --files .github tool</code> | 2 | <code>tool/check_line_width.py</code> |
| <code>rtk proxy sed -n '500,560p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_context.dart</code> | 0 | <code>  /// Cleans up [value] that came out after the body had ended.</code> |
| <code>rtk proxy sed -n '695,790p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_context.dart</code> | 0 | <code>    // The action may have cancelled this job while it ran: `_markCancelled`</code> |
| <code>rtk proxy sed -n '980,1140p' packages/solo/README.md</code> | 0 | <code>```</code> |
| <code>rtk proxy sed -n '605,780p' 'docs/records/2026-09-06[5]-solo-docs-review.md'</code> | 0 | <code>  искать пришедший с bloc.</code> |
| <code>rtk proxy sed -n '910,945p' /Users/user/.pub-cache/hosted/pub.dev/async_job-0.1.0/lib/src/job_base.dart</code> | 0 | <code>    _cancelled.complete();</code> |

</details>

Три независимых субагента выполняли только чтение. Ниже — их журнал,
переданный основному ревьюеру самими исполнителями. Для первых двух
исполнителей приведены последние непустые строки полученной выдачи;
полный исходный вывод этих команд у основного ревьюера не сохранён.
Усечённые чтения не выдаются за полный прогон или проверку тестов.

<details>
<summary>Очередь и правила</summary>

| Команда дословно | Последняя строка по журналу исполнителя |
| --- | --- |
| <code>rtk proxy cat /Users/user/.codex/RTK.md /Users/user/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0/skills/using-superpowers/SKILL.md /Users/user/.agents/skills/code-critic/SKILL.md</code> | <code>Then briefly state what was reviewed and any important limitations, such as unavailable tests, missing call sites, incomplete platform implementations, inability to execute the code, or unresolved external API behavior.</code> |
| <code>rtk proxy cat AGENTS.md docs/handoff.md docs/architecture.md docs/conventions.md docs/backlog.md</code> | <code>  `// ignore:`, чтобы так сделать.</code> |
| <code>rtk proxy cat docs/handoff.md</code> | <code>  движке очередь устроена иначе, решение не перенесено.</code> |
| <code>rtk proxy cat docs/architecture.md</code> | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>rtk proxy rg --files packages/solo/lib packages/solo/test packages/async_job/lib</code> | <code>packages/solo/test/support/test_solo.dart</code> |
| <code>rtk proxy sed -n '260,550p' docs/handoff.md</code> | <code>остановки, о котором договорились с владельцем — круг, вернувший только</code> |
| <code>rtk proxy sed -n '551,850p' docs/handoff.md</code> | <code>но остальной код английский, и это выбивается. Два, оставшихся после</code> |
| <code>rtk proxy sed -n '851,1150p' docs/handoff.md</code> | <code>  движке очередь устроена иначе, решение не перенесено.</code> |
| <code>rtk proxy cat docs/architecture.md</code> | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>rtk proxy cat 'docs/records/2026-09-06[5]-solo-docs-review.md' packages/solo/lib/src/queue.dart packages/solo/lib/src/policy.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/lib/src/solo_base.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/lib/src/job.dart packages/solo/lib/src/job_context.dart packages/solo/test/start_rules_test.dart</code> | <code>}</code> |
| <code>rtk proxy rg -n 'void start&#124;void finish&#124;adopt&#124;cancelWith&#124;Future&lt;void&gt; cancel&#124;started\(&#124;_execute&#124;beforeChildStart&#124;Job&lt;T&gt; run&#124;throwIfFinished&#124;bodyEnded' packages/async_job/lib/src/job_base.dart packages/async_job/lib/src/job_context.dart packages/solo/README.md packages/solo/test/policy_test.dart packages/solo/test/close_test.dart packages/solo/test/external_state_test.dart</code> | <code>packages/async_job/lib/src/job_base.dart:1030:  void start() =&gt; super.start();</code> |
| <code>rtk proxy sed -n '390,455p;565,655p;750,825p' packages/async_job/lib/src/job_base.dart</code> | <code>        }</code> |
| <code>rtk proxy sed -n '300,500p' packages/solo/README.md</code> | <code>throw its `Cancelled`. `log` never throws.</code> |
| <code>rtk proxy cat packages/solo/test/policy_test.dart packages/solo/test/queue_test.dart</code> | <code>}</code> |
| <code>rtk proxy sed -n '800,900p' packages/async_job/lib/src/job_context.dart</code> | <code>    // which call threw. The cleanup window stays open on purpose — a</code> |
| <code>rtk proxy sed -n '405,455p;505,530p;590,630p;695,755p' packages/async_job/lib/src/job_context.dart</code> | <code>          cancelled.stackTrace ?? StackTrace.current,</code> |
| <code>rtk proxy rg -n 'reentrant&#124;reentran&#124;keepWhile:&#124;canStart:&#124;onFinish&#124;onCancel&#124;close\(' packages/solo/test/emit_test.dart packages/solo/test/cancellable_test.dart packages/solo/test/external_state_test.dart packages/solo/test/close_test.dart packages/solo/test/leaked_context_test.dart</code> | <code>packages/solo/test/close_test.dart:228:    reentered ??= close();</code> |
| <code>rtk proxy cat packages/solo/test/external_state_test.dart packages/solo/test/close_test.dart packages/solo/test/emit_test.dart</code> | <code>}</code> |

</details>

<details>
<summary>Жизненный цикл, наследование и API</summary>

| Команда дословно | Последняя строка по журналу исполнителя |
| --- | --- |
| <code>rtk proxy cat /Users/user/.codex/RTK.md /Users/user/.agents/skills/code-critic/SKILL.md /Users/user/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0/skills/using-superpowers/SKILL.md</code> | <code>User instructions (CLAUDE.md, AGENTS.md, GEMINI.md, etc, direct requests) take precedence over skills, which in turn override default behavior. Only skip skill workflows or instructions when your human partner has explicitly told you to.</code> |
| <code>rtk proxy cat AGENTS.md docs/handoff.md docs/architecture.md docs/conventions.md docs/backlog.md</code> | <code>  `// ignore:`, чтобы так сделать.</code> |
| <code>rtk proxy sed -n '1,240p' docs/handoff.md</code> | <code>  `ctx.onCancel`, и на нём видно, чем `join` отличается от `uncancellable`</code> |
| <code>rtk proxy sed -n '1,230p' docs/architecture.md</code> | <code>тестами.</code> |
| <code>rtk proxy rg --files packages/solo/lib packages/solo/test packages/async_job/lib</code> | <code>packages/solo/test/unobserved_failure_test.dart</code> |
| <code>rtk proxy cat packages/solo/lib/src/solo.dart packages/solo/lib/src/job.dart packages/solo/lib/src/job_context.dart packages/solo/lib/src/observer.dart packages/solo/lib/solo.dart</code> | <code>export 'src/solo_cancel_reason.dart';</code> |
| <code>rtk proxy cat packages/solo/lib/src/solo_base.dart</code> | <code>}</code> |
| <code>rtk proxy rg -n 'class JobBase&#124;_observer&#124;_body&#124;void finish&#124;void start&#124;finished\(&#124;execute\(&#124;release&#124;clear&#124;bodyEnded&#124;notifyObserver&#124;notifyError&#124;adoptedBy&#124;beforeChildStart&#124;run&lt;T&gt;' packages/async_job/lib/src/job_base.dart packages/async_job/lib/src/job_context.dart packages/solo/README.md packages/solo/test/close_test.dart packages/solo/test/leaked_context_test.dart</code> | <code>packages/solo/README.md:1088:of applying them to the next frame. `queue.clear()` without</code> |
| <code>rtk proxy sed -n '232,330p' packages/async_job/lib/src/job_base.dart</code> | <code>      Zone.current.handleUncaughtError(error, stackTrace);</code> |
| <code>rtk proxy sed -n '560,895p' packages/async_job/lib/src/job_base.dart</code> | <code>      return Cancelled.by(</code> |
| <code>rtk proxy cat packages/solo/test/close_test.dart packages/solo/test/zone_test.dart packages/solo/test/leaked_context_test.dart</code> | <code>}</code> |
| <code>rtk proxy sed -n '440,525p' packages/async_job/lib/src/job_context.dart</code> | <code>      final disposer = dispose ?? discard;</code> |
| <code>rtk proxy sed -n '795,900p' packages/async_job/lib/src/job_context.dart</code> | <code>    // which call threw. The cleanup window stays open on purpose — a</code> |
| <code>rtk proxy rg -n 'debug&#124;close\(&#124;after.*finish&#124;context&#124;unattended&#124;immutable&#124;side effect&#124;pure&#124;canStart&#124;keepWhile&#124;rules' packages/solo/README.md packages/solo/test/hooks_test.dart packages/solo/test/solo_base_test.dart packages/solo/test/children_test.dart</code> | <code>packages/solo/test/children_test.dart:547:        'Cancelled(handler: child null: Cancelled(rules: is not Working))',</code> |
| <code>rtk proxy sed -n '130,205p' packages/solo/README.md</code> | <code>checks `paused`, and there is no `if` left to forget.</code> |
| <code>rtk proxy sed -n '450,585p' packages/solo/README.md</code> | <code>after the job was cancelled: an action that `wait` stopped waiting for</code> |
| <code>rtk proxy cat packages/solo/lib/src/queue.dart packages/solo/lib/src/policy.dart packages/solo/lib/src/solo_cancel_reason.dart</code> | <code>}</code> |
| <code>rtk proxy cat 'docs/records/2026-09-06[5]-solo-docs-review.md'</code> | <code>  `issue_tracker` и `topics` на месте.</code> |
| <code>rtk proxy rg -n -C 8 'throw&#124;rule' packages/solo/test/start_rules_test.dart packages/solo/test/children_test.dart</code> | <code>packages/solo/test/start_rules_test.dart-286-</code> |

</details>

<details>
<summary>Тесты и пример</summary>

| Команда дословно | Последняя строка по журналу исполнителя |
| --- | --- |
| <code>rtk proxy cat /Users/user/.agents/skills/code-critic/SKILL.md /Users/user/.codex/RTK.md AGENTS.md</code> | <code>номера версии.</code> |
| <code>rtk proxy cat docs/handoff.md docs/architecture.md docs/conventions.md docs/backlog.md</code> | <code>〈исполнитель сообщил усечение вывода; точная последняя строка им не зафиксирована〉</code> |
| <code>rtk proxy wc -l docs/handoff.md docs/architecture.md docs/conventions.md docs/backlog.md</code> | <code>    1506 total</code> |
| <code>rtk proxy rg --files packages/solo/test packages/solo/example packages/solo/lib packages/solo/doc</code> | <code>packages/solo/test/hooks_test.dart</code> |
| <code>rtk proxy cat docs/architecture.md</code> | <code>  `onCancel` и ожидание одного `Completer`, а не `await for`.</code> |
| <code>rtk proxy cat packages/solo/example/lib/src/camera_controller.dart packages/solo/example/lib/src/camera_state.dart packages/solo/example/lib/src/fake_camera_hardware.dart packages/solo/example/bin/main.dart packages/solo/example/README.md packages/solo/example/test/camera_controller_test.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/README.md packages/solo/CHANGELOG.md</code> | <code>Never published.</code> |
| <code>rtk proxy sed -n '175,320p' packages/solo/example/test/camera_controller_test.dart</code> | <code>}</code> |
| <code>rtk proxy wc -l packages/solo/test/*.dart packages/solo/test/support/*.dart packages/solo/README.md packages/solo/lib/src/*.dart</code> | <code>    9006 total</code> |
| <code>rtk proxy sed -n '1,250p' packages/solo/README.md</code> | <code>    );</code> |
| <code>rtk proxy cat packages/solo/test/children_test.dart packages/solo/test/start_rules_test.dart packages/solo/test/support/run_solo.dart packages/solo/test/support/test_solo.dart packages/solo/test/support/lifecycle.dart</code> | <code>];</code> |
| <code>rtk proxy sed -n '250,530p' packages/solo/README.md</code> | <code>that way, and that is normal traffic, not something to report. It is an</code> |
| <code>rtk proxy cat packages/solo/lib/src/job_context.dart packages/solo/lib/src/job.dart</code> | <code>}</code> |
| <code>rtk proxy sed -n '530,820p' packages/solo/README.md</code> | <code>〈пустая строка; последняя непустая: ## Flutter〉</code> |
| <code>rtk proxy cat packages/solo/test/close_test.dart packages/solo/test/cancellable_test.dart packages/solo/test/cancel_test.dart packages/solo/test/disposal_test.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/test/zone_test.dart packages/solo/test/unobserved_failure_test.dart packages/solo/test/unattended_test.dart</code> | <code>}</code> |
| <code>rtk proxy sed -n '1,210p' packages/solo/lib/src/solo_base.dart</code> | <code>    bool Function(W state)? keepWhile,</code> |
| <code>rtk proxy cat packages/solo/test/hooks_test.dart packages/solo/test/sequential_test.dart packages/solo/test/queue_test.dart packages/solo/test/policy_test.dart packages/solo/test/solo_base_test.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/test/wait_test.dart packages/solo/test/join_test.dart packages/solo/test/late_value_test.dart packages/solo/test/each_test.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/test/emit_test.dart packages/solo/test/external_state_test.dart packages/solo/test/leaked_context_test.dart packages/solo/test/on_cancel_test.dart packages/solo/test/outcome_test.dart packages/solo/test/support/foreign_job.dart packages/solo/test/support/journal.dart packages/solo/test/support/test_state.dart packages/solo/example/test/support/journal.dart packages/solo/example/lib/solo_example.dart packages/solo/example/pubspec.yaml packages/solo/example/analysis_options.yaml</code> | <code>    sort_pub_dependencies: true</code> |
| <code>rtk proxy cat packages/solo/test/scenario_closing_test.dart packages/solo/test/scenario_external_test.dart packages/solo/test/scenario_children_test.dart</code> | <code>}</code> |
| <code>rtk proxy cat packages/solo/test/scenario_queue_test.dart</code> | <code>}</code> |

</details>

## Завершающая проверка артефакта и клона

Это проверка структуры Markdown и ссылок на сценарии, **не исполнение
Dart-кода и не подтверждение поведения из находок**.
Рабочий каталог — корень клона.

```sh
rtk proxy python3 - <<'PY'
from pathlib import Path
import re
base = Path('/Users/user/development/my/solo/.artifacts/2026-09-09-solo-project-review')
report = (base / 'report.md').read_text()
probes = (base / 'probes.dart').read_text()
header = '> **Состояние на 2026-09-09:** ревью проведено, находки не разобраны.\n> **Что это:** полное независимое ревью пакета `solo` перед его первой\n> публикацией.\n> **Связанные записи:** 2026-09-06[5]-solo-docs-review.md.\n'
assert report.startswith(header)
findings = report.split('# НАХОДКИ\n', 1)[1]
assert len(re.findall(r'^## \d+\.', findings, re.M)) == 8
assert findings.count('**Вердикт:**') == 8
assert '<!-- COMMAND_LOG -->' not in report
assert '<!-- AGENT_READ_LOG -->' not in report
for name in ['add-close', 'rule-cancel', 'checkpoint-cancel', 'child-rule-error', 'debug-close', 'camera-close-error', 'camera-init-error', 'rule-error-zone']:
    assert name in report and name in probes
assert report.count('**Тяжесть: High.**') == 2
assert report.count('**Тяжесть: Medium.**') == 5
assert report.count('**Тяжесть: Low.**') == 1
print('Report checks passed: exact header; 8 findings (2 High, 5 Medium, 1 Low); 8 verdicts; 8 probe references. Dart probes remain uncompiled and unexecuted.')
PY
```

Код завершения: 0. Единственная и последняя строка вывода:

```text
Report checks passed: exact header; 8 findings (2 High, 5 Medium, 1 Low); 8 verdicts; 8 probe references. Dart probes remain uncompiled and unexecuted.
```

Последняя проверка дерева:

```sh
rtk proxy git -C /Users/user/development/my/solo/.artifacts/solo-review-project status --short
```

Код завершения: 0. Вывод пуст, последней строки нет.
После этой проверки менялся только этот отчёт вне клона.

# НАХОДКИ

## 1. Закрытие из хука политики оставляет входящую задачу в закрытой очереди

**Тяжесть: High.**

**Координата:** `packages/solo/lib/src/solo_base.dart`, `SoloBase.add`.
Якоря в порядке выполнения:

```dart
if (isClosed) {
```

```dart
_queue.removeWhere((other) => other.key == impl.key);
```

```dart
_queue._insert(impl, first: first);
```

Поставить `old` с ключом `x`, затем добавить `incoming` с тем же ключом
и `Policy.replace`; из `onFinish(old)` вызвать `close()`.
Удаление старой задачи синхронно вызывает её хук завершения.
В этот момент `incoming` уже прошла проверку `isClosed`, но ещё не
вставлена в очередь. Закрытие осушает очередь без неё и планирует
завершение. Вернувшись из хука, `add` вставляет `incoming` в уже закрытый
контроллер. `_pump` выходит по `isClosed`, а повторный `close` возвращает
сохранённую future и заново очередь не осушает. В результате `close`
завершается, но `incoming.done` без дополнительного ручного вмешательства
не завершится; задача остаётся `isQueued == true` с `outcome == null`.

Это нарушает контракты `close` («drops every queued job») и `add`
на закрытом контроллере (`Cancelled(closed)`). Реентерабельный `close`
из хука допустим: `Solo.close` специально сохраняет `_closed` до вызова
`super.close`, чтобы обслуживать именно такой повторный вход.

**Подтверждение:** чтение цепочки `_SoloQueue.remove` →
`_SoloJob.cancelWith` → `JobBase.finish` → хук `onFinish` → `close`
и возврата к `_insert`; guard после политики отсутствует.
Непрогнанный сценарий — `add-close`; уверенность по чтению высокая.

**Предложение:** после синхронных вызовов политики повторно проверять
закрытие перед вставкой и завершать входящую задачу `Cancelled(closed)`.

**Вердикт:** подтверждена зондом: после `close()` у входящей задачи
`outcome=null`, `isQueued=true`, очередь пуста. Закрыто в `e1776cf`:
`add` перепроверяет закрытие после политики и роняет входящую
`Cancelled(closed)`. Тест «a job added while a policy hook closed the
controller is dropped».

## 2. Самоотмена из `canStart` оставляет завершённую задачу в `current` и останавливает очередь

**Тяжесть: High.**

**Координата:** `packages/solo/lib/src/solo_base.dart`, `SoloBase._pump`.
Якорь:

```dart
_current = job;
job._launch();
```

Стартовое правило задачи вызывает её `cancel()` и возвращает `true`.
Перед вызовом правила задача уже вынута через `_takeFirst`, но ещё имеет
статус `created`. `_SoloJob.cancelWith` не находит её в очереди;
унаследованный `JobBase.cancelWith` для `created` немедленно вызывает
`finish(Cancelled(...started: false))`. Завершение происходит, пока
`_current` ещё `null`.

После возвращённого правилом `true` памп проверяет только `isClosed`,
назначает уже завершённую задачу текущей и вызывает `start`.
Ядро бросает `StateError` с текстом `has already finished`.
В `_pump` этот вызов не защищён; повторного `finished()` для задачи не
будет. Все последующие попытки прокачки выходят по `_current != null`,
оставляя следующие задачи ждать. Оговорки о запрете побочных действий
правил нет; унаследованный `JobContextBase.run` прямо учитывает правило,
которое вызывает `cancel()` или `close()` и всё же отвечает `true`.

**Подтверждение:** чтение обеих веток жизненного цикла в hosted
`async_job` и порядка операций в `_pump`; `_added` защищает повторный
`add`, но отмене не препятствует. Непрогнанный сценарий — `rule-cancel`;
уверенность по чтению высокая.

**Предложение:** после стартовых правил пропускать уже завершённую
задачу до присваивания `_current`.

**Вердикт:** подтверждена зондом, со стеком ровно из находки:
`Bad state: Job(first) has already finished` в `JobBase.start` ←
`_SoloJob._launch` ← `SoloBase._pump`; следующая задача не стартовала
никогда. Закрыто в `e1776cf`: памп перешагивает законченную задачу. Тест
«a start rule that gives its own job up lets the queue move on».

## 3. Контрольная точка пропускает отмену внутри `keepWhile` и разрешает начать действие

**Тяжесть: Medium.**

**Координата:** `packages/solo/lib/src/job_context.dart`,
`_SoloContext._checkedState`. Якоря:

```dart
throwIfCancelled();
final current = _solo._state;
final rejection = _job._rejectKeep(current);
```

```dart
return current as W;
```

На старте `keepWhile` отвечает `true`. Тело включает флаг и вызывает
`ctx.wait(action)`; при этой проверке `keepWhile` снимает флаг,
синхронно вызывает `job.cancel()` и снова отвечает `true`.
Отмена уже принята, но `_checkedState` проверяла её только до вызова
пользовательского предиката. Она успешно возвращает состояние.

Унаследованный `wait` сразу после `check()` исполняет
`final result = action();`; у `join` аналогично следует
`final result = await action();`. Поэтому новое действие запускается
уже после пометки задачи. Проверка после результата может выбросить
отмену, но начатый запрос или команду устройства она не отменяет.
Это противоречит контракту контрольной точки: она должна бросить
принятую отмену, прежде чем запускать работу.

**Подтверждение:** чтение `_checkedState`, `JobBase.cancelWith` и
обоих унаследованных методов в hosted `async_job`; между предикатом
и началом действия другой проверки нет. Непрогнанный сценарий —
`checkpoint-cancel`; уверенность по чтению высокая.

**Предложение:** повторно проверять отмену после выполнения `keepWhile`
до успешного возврата из `_checkedState`.

**Вердикт:** подтверждена зондом: действие стартовало один раз уже после
принятой отмены. Закрыто в `e1776cf`: контрольная точка перепроверяет
отмену после `keepWhile`. Тест «a keepWhile that gives the job up stops
the next action».

## 4. Ошибка стартового правила ребёнка проходит мимо `onError`

**Тяжесть: Medium.**

**Координата:** `packages/solo/lib/src/job_context.dart`,
`_SoloContext.beforeChildStart`. Якорь:

```dart
final rejection = impl._rejectStart(_solo._state);
```

Родитель запускает ребёнка с бросающим `canStart` и ловит исключение
`ctx.run(child)`. Переопределение `beforeChildStart` не уведомляет
наблюдателя об ошибке правила. Обработчик в `JobContextBase.run`
выполняет:

```dart
child
  ..ignore()
  ..finish(Failed(error, stackTrace));
rethrow;
```

`finish` вызывает `onFinish`, но не `onError`; `ignore()` отключает
маршрут ненаблюдённого `Failed`. Родитель, поймавший исключение,
завершается `Done`. В результате у ребёнка есть `Failed`, но ни
`SoloObserver.onError`, ни `SoloBase.onError` его не получили.
Если родитель не поймает исключение, ошибка будет объявлена как ошибка
родителя, всё равно без уведомления от имени ребёнка.

Контракт `SoloObserver.onError` прямо перечисляет бросившие
`canStart`/`keepWhile`; README обещает `Every failure also reaches the
hooks`. Для корня `_pump` выполняет `_notifyObserver` перед
`_drop(Failed(...))`, поэтому различие возникает на границе адаптации
дочерних правил `solo` к ядру.

**Подтверждение:** чтение `beforeChildStart`, обработчика `run`,
`JobBase.finish` и корневого обработчика `_pump`.
Непрогнанный сценарий — `child-rule-error`; уверенность по чтению высокая.

**Предложение:** в `beforeChildStart` уведомлять наблюдателя ребёнка
об исключении его правила перед повторным выбрасыванием.

**Вердикт:** подтверждена зондом: родитель `Done(null)`, ребёнок
`Failed(rule boom)`, в журнале только `finished`, ни строки `error`.
Закрыто в `e1776cf`: `beforeChildStart` уведомляет наблюдателя ребёнка
перед rethrow. Тест «a start rule of a child that throws reaches the
observer».

## 5. Ошибка диагностического канала делает `close()` незавершимым

**Тяжесть: Medium.**

**Координата:** `packages/solo/lib/src/solo_base.dart`,
`SoloBase._debug` и `SoloBase.close`. Якоря:

```dart
debug(message());
```

```dart
final completer = _closing = Completer<void>();
_debug(() => 'close');
```

Установить `SoloBase.debug`, который бросает на сообщении `close`, и
вызвать `close()`. Поле `_closing` уже заполнено, но осушение очереди,
отмена текущей задачи и планирование `_finishClose` ещё не произошли.
Первый вызов бросает синхронно; после снятия бросающего debug повторный
вызов вернёт сохранённую future, которую завершать уже некому.
`Solo.close` тоже заранее сохранил `_closed`, поэтому его обёртка
сохраняет зависание и не закрывает стрим.

Защита диагностики ядра здесь не действует: `SoloBase._debug` —
отдельный вызов без `try/catch`. Бросок при построении сообщения,
например из `toString` состояния, проходит тем же незащищённым путём.
Диагностический канал вызывается между изменениями внутреннего
состояния, поэтому его ошибка оставляет публичный жизненный цикл
частично выполненным.

**Подтверждение:** чтение `_debug`, `close`, `_finishClose`,
`Solo.close` и отдельного защищённого `JobBase._debug`.
Непрогнанный сценарий — `debug-close`; уверенность по чтению высокая.

**Предложение:** изолировать построение и доставку сообщения в
`SoloBase._debug`, передавая исключение в текущую зону.

**Вердикт:** подтверждена зондом: первый `close()` бросил, второй не
завершился никогда. Закрыто в `e1776cf`: канал изолирован, как у ядра, —
ошибка уходит в текущую зону. Тест «a debug channel that throws does not
hang close».

## 6. Пример сообщает успешный `dispose` и продолжает `reopen` после провала закрытия камеры

**Тяжесть: Medium.**

**Координата:**
`packages/solo/example/lib/src/camera_controller.dart`,
`CameraController.dispose` и `CameraController.reopen`; тот же вызов
есть в `packages/solo/README.md`, фрагменте `CameraController.dispose`.
Общий якорь:

```dart
await ctx.run(_closeCameraJob()).done;
```

После успешного `init` установить
`hw.failures['close'] = StateError('close-failed')`.
`_closeCameraJob` завершится `Failed`, но `.done` возвращает объект исхода
и не бросает его ошибку. Ни один из двух вызывающих методов исход не
проверяет. `dispose` излучает `Disposed` и заканчивается `Done`, а
следующий `dispose` уже пропускает закрытие по
`if (ctx.state is Disposed)`. `reopen` после того же провала начинает
`hw.open`, а при успехе следующих вызовов сообщает `Ready` и `Done`.

Отказ закрытия тем самым не доходит до вызывающего публичный метод:
прочитанная `.done` уже пометила ошибку ребёнка наблюдённой, и без
наблюдателя она не попадёт в зону как ненаблюдённый провал.
Контракт `dispose` обещает закрытие оборудования; показанный в README
`switch` по исходу `dispose` при этом выберет ветку успеха.

**Подтверждение:** чтение реального механизма ошибок
`FakeCameraHardware._operation`, обоих вызовов `.done` и getter'ов
`JobBase.done`/`value`; исход нигде не разбирается.
Непрогнанный сценарий — `camera-close-error`; уверенность по чтению высокая.

**Предложение:** ожидать `.value` либо явно разбирать исход закрытия
перед последующим открытием и публикацией `Disposed`.

**Вердикт:** подтверждена прогоном на примере: с `failures['close']`
получено `dispose outcome=Done(null), state=Disposed()`. Закрыто в
`e6e850a`: `dispose` и `reopen` берут `.value`, README обоих языков
поправлен. Тест «a close that fails is not a disposal».

## 7. Ошибка первого открытия оставляет пример в `Preparing`, из которого не стартует восстановление

**Тяжесть: Medium.**

**Координата:**
`packages/solo/example/lib/src/camera_controller.dart`,
`CameraController.init`. Якорь:

```dart
ctx.emit(const Preparing());
await ctx.join(hw.open);
ctx.emit(const Ready());
```

Если перед `init()` установить ошибку `hw.failures['open']`,
`hw.open` бросит, задача закончится `Failed`, а состояние останется
`Preparing`. Сам этот тип документирован как `Hardware is opening.`,
хотя операция открытия уже окончена. После удаления ошибки повторный
`init` не стартует: его `canStart` требует `Initial`. `reopen` тоже
не стартует: он допускает только `Ready` или `Broken`.
Публичные методы открытия существующего контроллера больше не дают
восстановиться после временной ошибки; остаётся окончательный `dispose`.

`FakeCameraHardware._operation` при броске не вызывает `onError`:
внешнее уведомление реализовано отдельным `fail`. Поэтому подписка
конструктора не переводит этот провал в `Broken`. В отличие от `init`,
метод `reopen` уже имеет обработчик ошибки открытия с таким переходом.

**Подтверждение:** чтение `init`, обоих стартовых предикатов,
`FakeCameraHardware._operation`/`fail` и определения `Preparing`.
Непрогнанный сценарий — `camera-init-error`; уверенность по чтению высокая.

**Предложение:** при ошибке первого открытия переводить состояние
в `Broken`, сохраняя исходный провал задачи.

**Вердикт:** подтверждена прогоном: после провала открытия состояние
осталось `Preparing()`, и ни `init`, ни `reopen` больше не стартовали.
Закрыто в `e6e850a`: `init` садится в `Broken`, как давно делает
`reopen`. Тест «a first open that fails leaves a state reopen can start
from».

## 8. README обещает остановку ошибок в `onError`, хотя без обработчика они идут в зону

**Тяжесть: Low.**

**Координата:** `packages/solo/README.md`, абзац `A rule that throws`
в `Rules that are not visible in signatures` и конец `Errors`.
Якоря:

```text
reevaluation after a state change it goes to `onError` and stops
```

```text
`onError` in a controller is the end of the line.
```

```text
`Cancelled` never goes to the zone, and neither does an error that arrives
after the job was cancelled: an action that `wait` stopped waiting for
and that fails later is reported to `onError` and stops there.
```

Оба безусловных обещания неверны при `SoloBase.observer == null` и
непереопределённом `SoloBase.onError`. Ошибка переоценки идёт по цепочке
`_reevaluate` → `_notifyError` → `_SoloJob.notifyError`, который
устанавливает `_homeless`, → `SoloBase.onError` → `_reportToZone`.
Поздний провал брошенного действия `wait` попадает в тот же маршрут
через `JobContextBase._race` → `notifyError`.
Фильтр ядра исключает объект `Cancelled`, но не произвольную ошибку,
пришедшую после отмены. Она становится необработанной ошибкой зоны,
хотя цитируемый текст обещает остановить её в hook.

**Подтверждение:** чтение обеих цепочек, `JobBase._toZone`, актуального
описания fallback в `SoloBase.onError` и CHANGELOG. Существующий
`zone_test.dart` содержит сценарий `a rule that throws reaches the zone`,
но результат этого теста не установлен. Непрогнанный сценарий зонда —
`rule-error-zone`; уверенность по чтению высокая.

**Предложение:** в обоих абзацах указать передачу ошибки в зону при
отсутствии наблюдателя и переопределения `onError`.

**Вердикт:** подтверждена зондом: без наблюдателя поздний провал
брошенного действия пришёл в зону. Закрыто в `3049d98`: оба обещания в
README обоих языков получили условие про наблюдателя.

Отдельных находок по удержанию ссылок и подписок после `close()`
чтением не установлено; измерения памяти не выполнялись.

Самостоятельных находок о тестовом покрытии нет: подмены не выполнены,
чувствительность тестов к поломкам не установлена.

Дополнительных находок по границам модулей и публичному API, сверх
указанных нарушений контрактов, чтением не установлено.
