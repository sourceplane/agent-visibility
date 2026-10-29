# apps/web — the site

Cloudflare's [Agent Visibility template](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
(MIT, `LICENSE`): one Hono Worker serving a content store to AI agents on
every surface they read, and a React dashboard previewing them, deployed as
one Worker with Static Assets.

| Path | What it is |
|---|---|
| `src/worker/index.ts` | upstream's Worker: `/llms.txt`, `/llms-full.txt`, `/index.json`, `/:slug.md`, `/:slug.jsonld`, `/jsonld`, `/robots.txt`, the dashboard's `/api/*`, the optional Web Bot Auth surface |
| `src/worker/health.ts` | not upstream's: `/api/health`, the store check the deploy smoke reads (never the model) |
| `src/enrichment/` | upstream's Workers AI enrichment and its deterministic fallback; the surfaces' renderers |
| `src/lib/` | upstream's KV store, sample content (`content.ts`), types and Web Bot Auth module |
| `src/react-app/`, `index.html` | upstream's dashboard, built by Vite into `dist/client` |
| `wrangler.template.jsonc` | the config's source; `wrangler.jsonc` is its render (`pnpm run wire:fixture`) |
| `component.yaml` | the Orun component: render, build, push the admin token, deploy, smoke |

## Scripts

| Command | What it does |
|---|---|
| `pnpm dev` | builds the dashboard, then `wrangler dev --local`: a local KV store, remote bindings off, so the model is not called and each page is enriched by upstream's fallback |
| `pnpm dev:remote` | the same with the signed-in account's Workers AI (`wrangler login` first; it may incur usage) |
| `pnpm build` | the dashboard into `dist/client` |
| `pnpm typecheck`, `pnpm lint` | the Worker and the dashboard |
| `pnpm run wire:fixture` | re-renders `wrangler.jsonc` from the template and `wiring.fixture.json` |

Writes (`POST /api/resources`, `POST /api/refresh`) need `ADMIN_TOKEN`:
copy `.dev.vars.example` to `.dev.vars` locally; deployed, it is the Orun
secret of the same name, pushed to the Worker as a Worker secret.
