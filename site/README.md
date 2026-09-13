# sonocles.com

Astro, plain — not Starlight. The structure Rheocles settled, carried back
here: the docs are a designed surface with the same header as the landing
page and an API reference generated from `docs/openapi.yaml`; assembling
sidebar, search (pagefind) and code blocks (expressive-code) from parts costs
less than fighting a theme's chrome.

    pnpm install
    pnpm dev        # http://localhost:4321
    pnpm build      # → dist/, what Cloudflare Pages serves

Deploys on every push to `main` touching `site/` via
`.github/workflows/deploy-site.yml`. For a preview URL from a branch:

    export CLOUDFLARE_API_TOKEN="$(grep '^CLOUDFLARE_API_TOKEN=' ../.env | cut -d= -f2-)"
    pnpm deploy:preview

Brand: `../docs/BRAND.md`. Docs tree: `src/lib/docs-nav.ts`.

## What the build produces

- The landing page from `src/pages/index.astro` — the copy, plates and
  frames the single-file site shipped, unchanged.
- Pages under `src/content/docs/`; the docs tree order is
  `src/lib/docs-nav.ts`.
- A social card per docs page under `/og/…png` (`src/pages/og/[...slug].ts`,
  astro-og-canvas, fonts in `src/assets/og-fonts/` under the OFL). The
  landing page keeps its composed card, `public/img/og.png`, whose source is
  `og.html`: the popover (`src/assets/popover.png`, the app's own
  `--render-preview`, never a desktop capture) on the right, the philosopher
  and the scribe as a sticker (`art/sticker.py` → `art/stickers/`, from the
  untouched plate in `art/originals/`) in front. `node art/og.mjs og.html
  public/img/og.png` renders it; the comment at the top of `og.html` says
  how to re-shoot the popover.
- `sitemap-index.xml`, `robots.txt`, `404.html`, `_redirects`, the favicon
  set (`public/`, rasterised once from the mark).

Plates: `src/assets/plates/`, generated once by `../art/make.py`. Every run
costs money; do not run it to reproduce what is already there.
