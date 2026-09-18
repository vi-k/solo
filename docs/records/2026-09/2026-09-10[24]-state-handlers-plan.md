> **Состояние на 2026-09-10:** реализовано и проверено; итог в
> `2026-09-10[25]-state-handlers-report.md`.
> **Что это:** план коррекции состояния при Failed и Cancelled.
> **Связанные записи:**
> `2026-09-10[23]-discard-state-proposal-report.md`.

# План onError/onCancel для состояния

Исполнение: последовательно в main через executing-plans и TDD.
Владелец уже согласовал API и правила; отдельного выбора ветки не нужно.

Цель: простой sealed-пример без try/catch, общего onFinish и
externalSetState для уборки собственной операции.

Архитектура: _SoloJob.finished получает уже окончательный outcome,
но ещё удерживает очередь. Синхронный обработчик применяется перед
_onJobFinished. Существующий async_job изменять не требуется.

Стек: Dart >=3.6, solo, async_job 0.2.0, fake_async, test.
Спецификация: `2026-09-10[23]-discard-state-proposal-report.md`,
последние два уточнения заменяют прежний вариант onDiscard.

## Ограничения

- Параметры run/job: S Function(S, Object, StackTrace)? onError и
  S Function(S, Cancelled)? onCancel.
- Только начавшееся тело; Failed/Cancelled сохраняются.
- Тело, дети и уборка заканчиваются перед обработчиком.
- Несовместимый внешний переход отзывает право коррекции окончательно,
  включая отменённую Job, ожидание детей и уборку.
- Учитываются W/keepWhile и запрет родителя; canStart не повторяется.
- Свой emit не проверяет собственные правила повторно.
- Обработчик синхронный; его ошибка диагностируется отдельно.
- Отмена из наблюдателя при коррекции не меняет зафиксированный исход.
- Работа в main, чужой launch.json не трогать; публикация не поручена.

## 1. API, жизненный цикл и правила

Файлы: packages/solo/lib/src/solo_base.dart, job.dart;
тесты: packages/solo/test/state_handlers_test.dart.

- [x] Добавить тесты с FakeAsync и управляемыми Completer: ошибка
  сохраняет Failed, отмена сохраняет Cancelled, успешная Job не вызывает
  обработчики, дубликат и отмена до старта не корректируют состояние.

```dart
final job = solo.run<String, void>(
  (ctx) async => throw failure,
  onError: (state, error, stackTrace) => 'failure',
)..ignore();
clock.flushMicrotasks();
expect(solo.state, 'failure');
expect(job.outcome, isA<Failed>());
```

- [x] Выполнить dart test test/state_handlers_test.dart и увидеть
  отсутствие именованных параметров до реализации.
- [x] Провести параметры через run/job в поля _SoloJob. В execute
  отметить вход в тело. В finished выбрать callback по outcome:

```dart
try {
  _correctState();
} finally {
  _solo._onJobFinished(this);
}
```

- [x] Добавить отзыв права коррекции при внешних переходах. Отслеживать
  его для Job с собственными обработчиками до удаления из running.
  Обычный родитель без них не продлевает правила после тела.
  Сначала отмечать несовместимость, затем вызывать наблюдателей:
  синхронный повторный переход не должен скрыть промежуточный запрет.
  Повторно проверить право после вызова преобразования перед записью.
- [x] Проверить W, keepWhile, ручную отмену до Disconnected, смену
  состояния во время уборки после ошибки, совместимый внешний переход,
  возврат в совместимое состояние после запрета, собственный переход,
  потомка после запрета родителя и повторный вход из обработчика.
- [x] Проверить порядок finally/дети/dispose/handler/onFinish/next,
  close, исключение callback, ошибку правил и сигнал ctx.onCancel.
- [x] Выполнить тесты и анализ solo; проверить отсутствие изменения
  исходов и очереди, покрытие каждого правила конкретным сценарием.

## 2. Публичные документы и итог

Файлы: packages/solo/README.md, README.ru.md, CHANGELOG.md;
docs/architecture.md, docs/handoff.md и запись отчёта этой работы.

- [x] Переписать Quick start на sealed ProfileState, Initial,
  Loading, Loaded, Failure и параметры обработки состояния.
- [x] Обновить связанные UI, тест и примеры ProfileController так,
  чтобы в README не осталось обращений к прежнему bool loading.
- [x] Описать пропуск обработчиков по правилам, момент вызова,
  сохранение исхода и отличие от ctx.onCancel; перевести вместе.
- [x] Извлечь и проверить новый быстрый старт с FakeAsync.
- [x] Выполнить dart analyze/dart test в solo и его примере,
  flutter analyze/flutter test в flutter_solo и анализ Flutter-примера.
- [x] Проверить переводы, ширину Markdown, AGENTS.md и записи отдельно,
  dart format и git diff --check. Обновить handoff и итоговый отчёт.
- [x] Проверить итоговый diff и закоммитить работу вместе с документами.
