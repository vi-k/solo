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
npm run dev     # http://localhost:4321/
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
| `base` | The path it is served under: `/` on the custom domain, `/solo` on the GitHub Pages project URL. |
| `title`, `tagline` | The site's name and its one-line description. |
| `repo` | The repository, for the GitHub link and for "Edit this page". |

`build_site.py` writes page links with `base` in front, so changing it in
one place moves the whole site.

## Publishing

`.github/workflows/site.yml` builds and deploys on every push to `main`
that touches a README, a `doc/` page, this folder or the assembler.
**Settings → Pages → Source** is set to *GitHub Actions*.

The domain is `docs.yet-another.dev`. A subdomain needs one DNS record —
`docs` as a `CNAME` to `vi-k.github.io` — and the apex stays free for
whatever else lives there.

The domain itself is a **Pages setting**, not a file. A deployment made by
GitHub Actions does not read `CNAME` out of the artifact the way a
branch-published site does, so `public/CNAME` only ends up served as a
plain file. Set the domain once, in Settings → Pages → Custom domain, or
with `gh api -X PUT repos/vi-k/solo/pages -f cname=docs.yet-another.dev`.
The file is kept beside it so the intended domain is visible in the
repository, and so a branch-published copy of this site would land on the
same name.

Moving the site elsewhere is three edits: `site` and `base` in
`site.json`, and `public/CNAME`. An apex domain would need four `A`
records (185.199.108–111.153) and four `AAAA`
(2606:50c0:8000–8003::153) instead of the single `CNAME`.

`.dev` is in the HSTS preload list, so browsers reach it over HTTPS only.
GitHub issues the certificate itself once the DNS record resolves; until
then the address does not open at all, and "Enforce HTTPS" in the Pages
settings stays greyed out. It can take up to 24 hours, usually minutes.

## Search

Built in, through [Pagefind](https://pagefind.app): it indexes the
generated HTML at build time and needs no service and no key.
