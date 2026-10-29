---
title: solo
description: По одной задаче за раз, монопольное владение состоянием, кооперативная отмена.
template: splash
editUrl: false
hero:
  tagline: |
    Управление состоянием для Dart, где у работы есть жизненный цикл:
    по одной задаче за раз, правила вместо флагов и отмена, мимо которой
    тело не пройдёт, забыв проверку.
  actions:
    - text: Быстрый старт
      link: solo/
      icon: right-arrow
    - text: solo и bloc рядом
      link: solo/vs-bloc/
      variant: minimal
---

## Пакеты

| Пакет | Что это |
| --- | --- |
| [solo](solo/) | Контроллер: очередь с политиками, правила состояния, дети, накопление. Чистый Dart. |
| [async_job](async_job/) | Ядро: отмена, дети и освобождение ресурсов для одной операции. Чистый Dart, зависит только от `meta`. |
| [flutter_solo](flutter_solo/) | Лицо для Flutter: `SoloBuilder`, `ValueListenable`, `select`, `listen`. |
| [solo_lints](solo_lints/) | Плагин анализатора: сообщает о частых ошибках в коде на `async_job` и `solo`. |

`solo` реэкспортирует `async_job`, а `flutter_solo` — `solo`, поэтому
достаточно одной зависимости. `solo_lints` — не зависимость: его называют
в `analysis_options.yaml`.
