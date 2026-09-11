// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

import config from './site.json' with { type: 'json' };

/** One sidebar entry, named in both languages. */
const page = (slug, label, ru) => ({ slug, label, translations: { ru } });

// Content under src/content/docs/ is generated from the packages by
// `python3 tool/build_site.py` and is not kept in git. The packages stay
// the single source of truth; this site renders them. English is the root
// locale and comes from the packages; Russian lives under /ru/ and comes
// from each package's README.ru.md and from docs/ru/<package>/.
export default defineConfig({
  site: config.site,
  base: config.base,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: config.title,
      description: config.tagline,
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
        ru: { label: 'Русский', lang: 'ru' },
      },
      social: [
        { icon: 'github', label: 'GitHub', href: config.repo },
      ],
      sidebar: [
        {
          label: 'solo',
          items: [
            page('solo', 'Overview', 'Обзор'),
            page('solo/jobs', 'Jobs and the queue', 'Задачи и очередь'),
            page('solo/state', 'State', 'Состояние'),
            page('solo/cancellation', 'Cancellation', 'Отмена'),
            page(
              'solo/resources',
              'Resources and cleanup',
              'Ресурсы и освобождение',
            ),
            page(
              'solo/children',
              'Children and streams',
              'Дочерние задачи и стримы',
            ),
            page(
              'solo/accumulation',
              'Event accumulation',
              'Накопление событий',
            ),
            page(
              'solo/errors',
              'Errors and observation',
              'Ошибки и наблюдение',
            ),
            page('solo/testing', 'Testing', 'Тестирование'),
            page('solo/flutter', 'Flutter', 'Flutter'),
            page('solo/camera', 'Camera example', 'Пример камеры'),
            page(
              'solo/vs-bloc',
              'solo and bloc, side by side',
              'solo и bloc рядом',
            ),
          ],
        },
        {
          label: 'async_job',
          items: [
            page('async_job', 'Overview', 'Обзор'),
            page('async_job/outcomes', 'Outcomes', 'Исходы'),
            page('async_job/cancellation', 'Cancellation', 'Отмена'),
            page(
              'async_job/children',
              'Children, streams and chains',
              'Дети, стримы и цепочки',
            ),
            page('async_job/cleanup', 'Cleanup', 'Уборка'),
            page(
              'async_job/observing',
              'Observing and testing',
              'Наблюдение и тестирование',
            ),
            page(
              'async_job/extending',
              'Building on the core',
              'Своё поверх ядра',
            ),
          ],
        },
        {
          label: 'flutter_solo',
          items: [page('flutter_solo', 'Overview', 'Обзор')],
        },
      ],
    }),
  ],
});
