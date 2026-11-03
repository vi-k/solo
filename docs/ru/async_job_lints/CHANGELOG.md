## 0.1.0

- Первый выпуск. Пять правил для кода на async_job — `ctx_in_cleanup`,
  `release_on_the_call`, `catch_without_check`, `sync_fake_async`
  и `bare_await` — и быстрые исправления `release_on_the_call`
  и `catch_without_check` пришли из solo_lints 0.1.4 и ведут себя, как там,
  с одним отличием: `bare_await` сообщает об ожидании задачи из собственной
  очереди контроллера solo, которое solo_lints оставляет `await_own_queue`.
- `package:async_job_lints/plugin_api.dart` регистрирует правила в другом
  плагине — для плагинов анализатора, построенных поверх этого.
- У пакета есть пример: рекордер на async_job с тремя ошибками, строки,
  о которых сообщает плагин, и та же задача исправленной.
