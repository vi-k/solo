# С riverpod и bloc

Задача встаёт под провайдер riverpod или обработчик bloc, и слой состояния
менять не нужно. Провайдер или обработчик знает, когда работа перестала быть
нужна; он отменяет задачу, а задача останавливается в следующей контрольной
точке и выполняет уборку. Код ниже идёт на riverpod 3, bloc 9
с `bloc_concurrency`, http 1.5 и dio 5, на чистом Dart: `flutter_riverpod`
и `flutter_bloc` дают те же `Ref` и `Emitter`.

| Где идёт задача | Что её отменяет | Раздел |
| --- | --- | --- |
| `FutureProvider.autoDispose` | `ref.onDispose(job.cancel)` | [Провайдер, которого больше нет](#провайдер-которого-больше-нет) |
| Метод `AsyncNotifier` | Следующий вызов и `ref.onDispose`, через поле | [Нотифаер, который начинает заново](#нотифаер-который-начинает-заново) |
| Обработчик bloc | `emit.forEach(watch(job), …)` | [Обработчик, который перезапускается](#обработчик-который-перезапускается) |
| Тело, которое шлёт HTTP-запрос | Собственный токен клиента, отменённый в `ctx.onCancel` | [Запрос, который надо прервать](#запрос-который-надо-прервать) |

## Провайдер, которого больше нет

Экран показывает строки, которые задача читает из базы. Задача открывает базу,
читает три страницы по 20 мс и закрывает базу, чем бы ни кончилась:

```dart
Job<List<String>> readRows(String query) => Job((ctx) async {
  final db = await ctx.join(
    () => Database.open(query),
    dispose: (db) => db.close(),
  );
  return [
    for (var page = 1; page <= 3; page++)
      await ctx.join(() => db.readPage(page)),
  ];
});
```

`Database` — та же база, что в быстром старте README, только читает
по страницам; она печатает, когда открывается, читает страницу и закрывается.
Провайдер `autoDispose`: уходит экран — уходит и последний слушатель,
и riverpod освобождает провайдер. На этом чтение должно остановиться, а база —
закрыться. В трассах ниже экран уходит во время чтения первой страницы.

### Первая попытка

Провайдер возвращает значение задачи:

```dart
// Первая попытка: задача читает дальше, когда провайдера уже нет.
final rows = FutureProvider.autoDispose.family<List<String>, String>(
  (ref, query) => readRows(query).value,
);
```

```text
database opened for dart
screen left
dart: page 1 read
dart: page 2 read
dart: page 3 read
database for dart closed
```

riverpod бросает переданный ему future, а задаче никто ничего не говорит: она
читает все страницы впустую.

### Вторая попытка

`ref.onCancel` по имени — то самое место для отмены:

```dart
// Вторая попытка: экран на паузе отменяет задачу, и начинается новая.
final rows = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  query,
) {
  final job = readRows(query);
  ref.onCancel(job.cancel);
  return job.value;
});
```

```text
database opened for dart
screen covered
dart: page 1 read
database for dart closed
screen shown
database opened for dart
dart: page 1 read
dart: page 2 read
dart: page 3 read
database for dart closed
```

Когда экран уходит, это работает. Но riverpod 3 зовёт `onCancel`, когда
последний слушатель уходит или встаёт на паузу, а Flutter ставит на паузу
слушателей экрана, который закрыт непрозрачным маршрутом. Задача кончается
`Cancelled`, а `Cancelled` — это `Exception`: riverpod считает его сбоем
и повторяет провайдер, как только экран снова виден, и чтение начинается заново
с первой страницы. С выключенными повторами экран вместо этого возвращается
к ошибке.

### Отмена при освобождении

`onDispose` вызывается, когда состояние, которому служит задача, выбрасывают:
когда провайдер освобождается и когда он перестраивается, но не на паузе:

```dart
final rows = FutureProvider.autoDispose.family<List<String>, String>((
  ref,
  query,
) {
  final job = readRows(query);
  ref.onDispose(job.cancel);
  return job.value;
});
```

```text
database opened for dart
screen left
dart: page 1 read
database for dart closed
```

Освобождение отменяет задачу, `join` дожидается страницы, которая уже читается,
и база закрывается. Экран, который просит другой запрос, слушает другой
провайдер семейства, а тот, который он перестал слушать, освобождается так же.

До зоны отмена не доходит, но `ProviderObserver` её всё равно слышит:
`providerDidFail` получает `Cancelled(manual)` освобождённого провайдера.
Наблюдатель, который шлёт сбои в отчёты, её пропускает:

```dart
final class CrashReports extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is Cancelled) return;
    report(error, stackTrace);
  }
}
```

`Cancelled`, которым задача кончилась сама, например по своему сроку, для
riverpod тоже сбой, и провайдер повторяет его, как любой другой.

## Нотифаер, который начинает заново

Нотифаер, который запускает задачу из метода, держит текущую в поле. Следующий
вызов отменяет её, прежде чем начать новую. Освобождение, которое riverpod
запускает и перед перестройкой, отменяет ту, что идёт, и очищает поле:

```dart
final class Search extends AsyncNotifier<List<String>> {
  Job<List<String>>? _current;

  @override
  List<String> build() {
    ref.onDispose(() {
      unawaited(_current?.cancel());
      _current = null;
    });
    return const [];
  }

  Future<void> search(String query) async {
    unawaited(_current?.cancel());
    final job = _current = readRows(query);
    state = const AsyncLoading();

    final outcome = await job.done;
    // Состояние теперь принадлежит более новому поиску, перестройке или
    // освобождению.
    if (!identical(job, _current)) return;
    state = switch (outcome) {
      Done(:final value) => AsyncData(value),
      Failed(:final error, :final stackTrace) => AsyncError(error, stackTrace),
      Cancelled() => AsyncError(outcome, StackTrace.current),
    };
  }
}

final search = AsyncNotifierProvider.autoDispose<Search, List<String>>(
  Search.new,
);
```

```text
database opened for d
search: da
database opened for da
d: page 1 read
database for d closed
da: page 1 read
da: page 2 read
da: page 3 read
database for da closed
state: [da: page 1, da: page 2, da: page 3]
```

Проверка перед записью состояния важна так же, как отмена. Отменённый поиск всё
равно кончается, и без проверки его `Cancelled` лёг бы поверх поиска, который
его сменил. Перестройка, например после `ref.invalidate`, сохраняет нотифаер
и его поле, а `ref.mounted` к тому времени снова истинно: что состояние больше
не его, старому поиску говорит только очищенное поле.

## Обработчик, который перезапускается

Поиск идёт на каждую клавишу, и bloc с `restartable()` из `bloc_concurrency`
оставляет только последний: новый запрос должен останавливать поиск перед ним,
а `close()` — тот, что идёт. События и состояние:

```dart
final class Searched {
  const Searched(this.query);

  final String query;
}

final class SearchState {
  const SearchState(this.rows, [this.error]);

  final List<String> rows;
  final Object? error;
}
```

### Первая попытка

Обработчик ждёт значение задачи:

```dart
// Первая попытка: restartable() бросает обработчик, а не задачу.
final class SearchBloc extends Bloc<Searched, SearchState> {
  SearchBloc() : super(const SearchState([])) {
    on<Searched>((event, emit) async {
      final rows = await readRows(event.query).value;
      if (!emit.isDone) emit(SearchState(rows));
    }, transformer: restartable());
  }
}
```

```text
database opened for a
a: page 1 read
database opened for ab
a: page 2 read
ab: page 1 read
a: page 3 read
database for a closed
```

```text
bloc closed
abc: page 2 read
abc: page 3 read
database for abc closed
```

`restartable()` перестаёт слушать старый обработчик, а `close()` — все,
но обработчик — это `Future`, и отменить его нечем. Поиск по `a` дочитывает
до конца рядом с поиском по `ab`, а поиск по `abc` читает и после того, как
bloc закрыт.

### Стрим, который отменяет задачу

Колбэка на свою отмену у `Emitter` нет, но подписки своих `forEach` и `onEach`
он отменяет сразу: до них доходят и `restartable()`, и `close()`. Поэтому
задача уходит в стрим, отмена которого отменяет задачу:

```dart
/// Значение [job] как стрим. Отмена подписки отменяет задачу.
///
/// Слушать его нужно сразу: значение читается в `onListen`, а стрим, который
/// никто не слушает, оставляет задачу без присмотра и её провал без
/// наблюдения.
Stream<T> watch<T>(Job<T> job) {
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      job.value
          .then(controller.add, onError: controller.addError)
          .whenComplete(controller.close);
    },
    onCancel: job.cancel,
  );
  return controller.stream;
}

final class SearchBloc extends Bloc<Searched, SearchState> {
  SearchBloc() : super(const SearchState([])) {
    on<Searched>((event, emit) async {
      await emit.forEach(
        watch(readRows(event.query)),
        onData: SearchState.new,
        onError: (error, stackTrace) => SearchState(const [], error),
      );
    }, transformer: restartable());
  }
}
```

```text
database opened for a
a: page 1 read
database opened for ab
a: page 2 read
database for a closed
```

```text
bloc closed
abc: page 2 read
database for abc closed
```

Поиск по `a` останавливается на странице, которую читал, и `close()` так же
останавливает поиск по `abc`. Ни тот, ни другой этой уборки не ждёт: эмиттер
не ждёт `job.cancel()`, а `restartable()` запускает новый обработчик раньше,
чем вообще отменяет старый, поэтому база для `ab` открывается раньше, чем
закрывается база для `a`, а `close()` возвращается раньше, чем закроется база
для `abc`. Ресурсу, который может быть открыт только один раз, нужно, чтобы
новый поиск дождался старого.

`close()` отменяет идущие обработчики при `concurrent()`, который стоит
по умолчанию, и при `droppable()` и `restartable()`, так что `watch` стоит
своего и без `restartable()`. При `sequential()` он сначала дожидается идущего
обработчика и событий в очереди, и отменять уже нечего. `onError:` нужен для
задачи, которая кончается `Cancelled` сама, например по своему сроку: `forEach`
передаёт ему ошибку, а без `onError:` bloc отдаёт её в `onError` самого блока
и дальше в зону.

`watch` — код страницы, а не часть `async_job`: скопируйте его.

## Запрос, который надо прервать

Задача забирает отчёт с сервера, который отвечает 300 мс. Когда задачу
отменяют, запрос должен остановиться: соединение закрывается, и сервер
перестаёт готовить ответ, который никто не прочтёт.

### Первая попытка

Тело ждёт запрос через `join`, как в быстром старте:

```dart
// Первая попытка: отмена ждёт ответа целиком.
final job = Job<String>((ctx) async {
  final response = await ctx.join(() => client.get(url));
  return response.body;
});
```

```text
cancel
server: sending the body
outcome: Cancelled(manual)
```

`join` дожидается действия, которое начал, и остановиться запросу никто
не говорит: отмена кончается, только когда пришёл весь ответ. `ctx.abandonable`
завершил бы задачу сразу, но запрос шёл бы дальше, и ответ пришёл бы уже
никому, как показывает раздел
[«Остановка операции»](cancellation.md#остановка-операции).

### Токен клиента

Оба клиента принимают собственный сигнал остановки, и `ctx.onCancel` подаёт его
вместе с отменой, как раздел
[«Токен через `onCancel`»](cancellation.md#токен-через-oncancel) делает это для
базы:

```dart
// http 1.5 и новее: запрос с триггером прерывания.
final job = Job<String>((ctx) async {
  final abort = Completer<void>();
  ctx.onCancel(abort.complete);

  final response = await ctx.join(() async {
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    );
    return http.Response.fromStream(await client.send(request));
  });
  return response.body;
});
```

```dart
// dio: CancelToken.
final job = Job<String>((ctx) async {
  final token = CancelToken();
  ctx.onCancel(token.cancel);

  final response = await ctx.join(
    () => dio.getUri<String>(url, cancelToken: token),
  );
  return response.data!;
});
```

```text
cancel
server: client hung up
outcome: Cancelled(manual)
```

Оба печатают одно и то же: клиент закрывает соединение, и сервер тело так
и не отправляет. `Client` из http, который не поддерживает `abortTrigger`, его
не замечает, и тогда запрос идёт до конца, как в первой попытке.

Прерванный запрос всё равно бросает: `RequestAbortedException` из http,
`DioException` типа `cancel` из dio. `join` пропускает её дальше, и она доходит
до зоны как неперехваченная ошибка, как любой провал тела, которого не несёт
ни один исход. Одна строка в `main` называет обе остановкой клиента:

```dart
Job.isCancellationError = (error) =>
    error is http.RequestAbortedException ||
    error is DioException && error.type == DioExceptionType.cancel;
```

Названная ею ошибка доходит до наблюдателя и на нём останавливается. Фильтр
разобран в разделе [«Ошибки отмены»](errors.md#ошибки-отмены) страницы
об ошибках.
