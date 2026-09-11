// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

import config from './site.json' with { type: 'json' };

// Content under src/content/docs/ is generated from the packages by
// `python3 tool/build_site.py` and is not kept in git. The packages stay
// the single source of truth; this site renders them.
export default defineConfig({
  site: config.site,
  base: config.base,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: config.title,
      description: config.tagline,
      social: [
        { icon: 'github', label: 'GitHub', href: config.repo },
      ],
      sidebar: [
        {
          label: 'solo',
          items: [
            { label: 'Overview', slug: 'solo' },
            { label: 'Jobs and the queue', slug: 'solo/jobs' },
            { label: 'State', slug: 'solo/state' },
            { label: 'Cancellation', slug: 'solo/cancellation' },
            { label: 'Resources and cleanup', slug: 'solo/resources' },
            { label: 'Children and streams', slug: 'solo/children' },
            { label: 'Event accumulation', slug: 'solo/accumulation' },
            { label: 'Errors and observation', slug: 'solo/errors' },
            { label: 'Testing', slug: 'solo/testing' },
            { label: 'Flutter', slug: 'solo/flutter' },
            { label: 'Camera example', slug: 'solo/camera' },
            { label: 'solo and bloc, side by side', slug: 'solo/vs-bloc' },
          ],
        },
        {
          label: 'async_job',
          items: [
            { label: 'Overview', slug: 'async_job' },
            { label: 'Outcomes', slug: 'async_job/outcomes' },
            { label: 'Cancellation', slug: 'async_job/cancellation' },
            {
              label: 'Children, streams and chains',
              slug: 'async_job/children',
            },
            { label: 'Cleanup', slug: 'async_job/cleanup' },
            { label: 'Observing and testing', slug: 'async_job/observing' },
            { label: 'Building on the core', slug: 'async_job/extending' },
          ],
        },
        {
          label: 'flutter_solo',
          items: [{ label: 'Overview', slug: 'flutter_solo' }],
        },
      ],
    }),
  ],
});
