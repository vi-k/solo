# Documentation site

[Starlight](https://starlight.astro.build) over the packages' own
Markdown. The pages under `src/content/docs/` are **generated** and not
kept in git: `tool/build_site.py` reads the READMEs and the `doc/` folders,
adds the frontmatter Starlight wants, and rewrites the links between files
into links between pages. The packages stay the single source of truth, so
the site cannot drift from what ships on pub.dev.

Only the English originals are published. The Russian translations in
`docs/ru/` are for the owner and for agents.

## Running it

From the repository root:

```sh
python3 tool/build_site.py
```

Then here:

```sh
npm install     # once
npm run dev     # http://localhost:4321/solo/
npm run build   # static output in dist/
```

Re-run `build_site.py` after editing any README or page in `doc/`; `npm run
dev` watches only what it has already been given.

## Settings

`site.json` holds everything that changes between deployments, and both
the Astro config and `build_site.py` read it:

| Field | What it is |
| --- | --- |
| `site` | The origin the site is served from, for canonical URLs and the sitemap. |
| `base` | The path it is served under. `/solo` for the GitHub Pages project URL; `/` for a custom domain. |
| `title`, `tagline` | The site's name and its one-line description. |
| `repo` | The repository, for the GitHub link and for "Edit this page". |

`build_site.py` writes page links with `base` in front, so changing it in
one place moves the whole site.

## Publishing

`.github/workflows/site.yml` builds and deploys on every push to `main`
that touches a README, a `doc/` page, this folder or the assembler. Before
the first run, set **Settings → Pages → Source** to *GitHub Actions*.

For a custom domain: set `base` to `/` and `site` to the domain in
`site.json`, put a `CNAME` file holding the bare domain into `public/`,
and add the DNS records GitHub asks for — four `A` records for the apex
(185.199.108–111.153), four `AAAA` (2606:50c0:8000–8003::153), or a
`CNAME` to `<user>.github.io` for a `www` subdomain. "Enforce HTTPS" in
the Pages settings becomes available once the certificate is issued,
which can take up to 24 hours.

## Search

Built in, through [Pagefind](https://pagefind.app): it indexes the
generated HTML at build time and needs no service and no key.
