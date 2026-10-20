// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';

import config from './site.json' with { type: 'json' };

/** One sidebar entry, named in both languages. */
const page = (slug, label, ru) => ({ slug, label, translations: { ru } });

/** The changelog of a package: the last entry of its group. */
const changelog = (segment) =>
  page(`${segment}/changelog`, 'Changelog', 'Список изменений');

// Content under src/content/docs/ is generated from the packages by
// `python3 tool/build_site.py` and is not kept in git. The packages stay
// the single source of truth; this site renders them. English is the root
// locale and comes from the packages; Russian lives under /ru/ and comes
// from each package's README.ru.md and from docs/ru/<package>/. A changelog
// is a page too: CHANGELOG.md of the package and its translation.
export default defineConfig({
  site: config.site,
  base: config.base,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: config.title,
      description: config.tagline,
      plugins: [
        // Publishes /llms.txt, /llms-full.txt and /llms-small.txt: the
        // documentation as plain text, for agents that would otherwise
        // crawl the repository page by page. English only -- the plugin
        // takes the default locale, which is what we want here.
        starlightLlmsTxt({
          projectName: 'solo',
          description:
            'solo manages state and asynchronous work in Dart. A ' +
            'controller holds one immutable state and runs jobs over it ' +
            'one at a time; each job declares which states let it start ' +
            'and continue, owns its children and its cleanup, and ends ' +
            'with Done, Failed or Cancelled.',
          details: [
            'Three packages, one dependency:',
            '',
            '- `async_job` is the kernel: one operation, its children, ' +
              'its cleanup and cooperative cancellation. Pure Dart.',
            '- `solo` adds the controller: a queue with policies, state ' +
              'rules, event accumulation. Re-exports `async_job`.',
            '- `flutter_solo` adds the Flutter face: `SoloBuilder`, ' +
              '`ValueListenable`, `select`, `listen`. Re-exports `solo`.',
            '',
            'Cancellation is cooperative: `cancel()` requests it and the ' +
              'body answers at a checkpoint -- `ctx.abandonable`, `ctx.join`, ' +
              '`ctx.uncancellable` or `ctx.check` -- and which one it is ' +
              'decides what happens to the operation behind it.',
          ].join('\n'),
          // A changelog tells what changed, not how the package works, and
          // its older sections name API that is gone: it closes the full
          // file and stays out of the abridged one.
          demote: ['**/changelog'],
          exclude: ['**/changelog'],
          optionalLinks: [
            {
              label: 'solo and bloc, side by side',
              url: `${config.site}/solo/vs-bloc/`,
              description:
                'Ten application scenarios implemented in both packages.',
            },
            {
              label: 'Repository',
              url: config.repo,
              description: 'Source, examples and tests.',
            },
          ],
        }),
      ],
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
              'Children and chains',
              'Дочерние задачи и цепочки',
            ),
            page('solo/streams', 'Streams', 'Стримы'),
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
            page('solo/mistakes', 'Common mistakes', 'Частые ошибки'),
            page('solo/reference', 'Reference', 'Справочник'),
            page('solo/camera', 'Camera example', 'Пример камеры'),
            page(
              'solo/vs-bloc',
              'solo and bloc, side by side',
              'solo и bloc рядом',
            ),
            changelog('solo'),
          ],
        },
        {
          label: 'async_job',
          items: [
            page('async_job', 'Overview', 'Обзор'),
            page('async_job/outcomes', 'Outcomes', 'Исходы'),
            page('async_job/cancellation', 'Cancellation', 'Отмена'),
            page('async_job/time', 'Time', 'Время'),
            page('async_job/children', 'Children', 'Дети'),
            page('async_job/groups', 'Groups', 'Группы'),
            page('async_job/chains', 'Chains', 'Цепочки'),
            page('async_job/streams', 'Streams', 'Стримы'),
            page('async_job/cleanup', 'Cleanup', 'Уборка'),
            page('async_job/observing', 'Observing', 'Наблюдение'),
            page('async_job/errors', 'Errors', 'Ошибки'),
            page('async_job/testing', 'Testing', 'Тестирование'),
            page(
              'async_job/extending',
              'Building on the core',
              'Своё поверх ядра',
            ),
            changelog('async_job'),
          ],
        },
        {
          label: 'flutter_solo',
          items: [
            page('flutter_solo', 'Overview', 'Обзор'),
            page('flutter_solo/mixins', 'Mixins', 'Миксины'),
            page('flutter_solo/testing', 'Testing', 'Тестирование'),
            changelog('flutter_solo'),
          ],
        },
      ],
    }),
  ],
});
