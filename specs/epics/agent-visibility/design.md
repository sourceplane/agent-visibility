# agent-visibility — design

## 1. What the template is

Cloudflare's [`agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
(at `7ae5750`) is a Hono Worker plus a React dashboard, deployed together as
a Worker with Static Assets. Its Worker (`src/worker/index.ts`) serves one
content store through every agent-discovery surface:

| Route | What it is |
|---|---|
| `GET /llms.txt` | the [llms.txt](https://llmstxt.org) index: the site, then one link per page to its Markdown |
| `GET /llms-full.txt` | the same, every page's content inlined |
| `GET /index.json` | a typed index (`protocol: agent-visibility/0.1`), the surfaces and every page with its sources |
| `GET /:slug.md`, `GET /:slug.jsonld` | one page as Markdown, and as schema.org `Article` JSON-LD |
| `GET /jsonld` | the site as schema.org `WebSite` JSON-LD |
| `GET /robots.txt` | explicit directives for the known AI crawlers, a `Content-Signal` line, and the llms.txt pointer |
| `GET /api/site`, `GET /api/resources[/:slug]` | the JSON the dashboard reads |
| `POST /api/resources`, `POST /api/refresh` | add or replace a page, and clear the enriched cache — both behind `Authorization: Bearer <ADMIN_TOKEN>`, `401` while no token is set |
| `GET /.well-known/web-bot-auth/directory`, `/api/identity` | the optional Web Bot Auth identity surface, `404` unless `ENABLE_WEB_BOT_AUTH` is `"true"` |

Every text surface carries `Content-Signal: ai-input=yes, search=yes, ai-train=no`
(the `CONTENT_SIGNAL` var) and the machine-readable ones allow any origin.
`src/lib/store.ts` holds the store in the `VISIBILITY_CACHE` KV namespace:
the raw pages under `resources:raw` (upstream's five sample pages for "Acme"
until someone posts their own), the enriched ones under `resources:enriched`.
A cold cache is enriched page by page through the `AI` binding
(`@cf/meta/llama-3.3-70b-instruct-fp8-fast`, `AI_MODEL`) and written with a
TTL (`ENRICHMENT_CACHE_TTL`, 3600 s); a page the model fails on gets a
deterministic enrichment from its own text instead, and a store holding one
is cached for 60 s only, so an outage cannot pin a degraded surface. The
dashboard (`src/react-app`) lists the surfaces, previews each and shows the
enriched pages. `wrangler.jsonc` sends upstream's surface paths to the
Worker first (`assets.run_worker_first`) and everything else to the assets,
as a single-page app.

## 2. The mapping (upstream → here)

| The template | Here |
|---|---|
| `src/worker`, `src/enrichment`, `src/lib`, `src/react-app`, `index.html` | `apps/web/` — the same files, unchanged but for `/api/health` (§5) |
| `vite` + `@cloudflare/vite-plugin` building the Worker and the client together | Vite with `@vitejs/plugin-react` alone builds the dashboard into `dist/client`; wrangler bundles `src/worker/index.ts` as the Worker (the composition's `workerEntrypoint`), with the same assets directory and the same `run_worker_first` list |
| `npm run dev` (Vite's dev server, `remoteBindings: false`) | `pnpm dev`: the dashboard built, then `wrangler dev --local` — remote bindings off, as upstream's; `pnpm dev:remote` with the account's model (§4) |
| `"kv_namespaces": [{ "binding": "VISIBILITY_CACHE" }]` (provisioned by Deploy to Cloudflare) | `"id": "@@wiring(cloudflare-kv/__ENV__:app_kv_id)@@"`, rendered per environment (§4); `wrangler dev` uses a local store |
| `"ai": { "binding": "AI" }` | unchanged — keyless, the account's Workers AI (§4) |
| `SITE_NAME` "Acme Docs", `SITE_DESCRIPTION` | the product's name and a line about it, which a product's rename rewrites; the sample pages stay upstream's |
| `AI_MODEL`, `ENRICHMENT_CACHE_TTL`, `CONTENT_SIGNAL`, `ENABLE_WEB_BOT_AUTH` | unchanged vars |
| `ADMIN_TOKEN` (`wrangler secret put`) | an optional Orun secret, pushed to the Worker as a Worker secret (§3) |
| `wrangler deploy` | Orun: `apps/web/component.yaml` renders the config for `$ORUN_ENVIRONMENT`, builds the dashboard, pushes the token, and deploys `agent-visibility-web-{stage,prod}` on merge to `main`, after the namespace's apply |
| `test/index.test.ts` under `@cloudflare/vitest-pool-workers` | `tests/web`: the same assertions, the Worker's own `fetch` over an in-memory KV store and a stand-in model (§7) |
| npm, `package-lock.json` | pnpm; `hono`, `react` and `react-dom` pinned to upstream's versions |
| `worker-configuration.d.ts` (`wrangler types`) | `cloudflare-env.d.ts` and `@cloudflare/workers-types` |

Alternative rejected: keeping `@cloudflare/vite-plugin` as the build. The
composition deploys a Worker entrypoint and an assets directory with
wrangler; the plugin's build writes its own Worker bundle and a generated
wrangler config beside the client, a second deploy path the lane would
ignore. Vite builds the client exactly as the plugin's client environment
does (the same `index.html`, the same React plugin), so a visitor sees the
same dashboard.

## 3. The admin token

`POST /api/resources` and `POST /api/refresh` compare the bearer token
with `env.ADMIN_TOKEN`; with none set both answer `401`
("Unauthorized. Set the ADMIN_TOKEN secret."), which is how upstream
ships. Reading is open: every surface is public by design.

On a deployed environment the token is an Orun secret of the product
(`optionalSecretEnv` in `apps/web/component.yaml`,
`secret://<repo>/<repo>/<env>/ADMIN_TOKEN`), set by the owner after the
build — never minted, never part of the build's consent. The Worker reads it
at request time, so the deploy lane hands it to the Worker as a **Worker
secret**: the build runs with it unset (`env -u`), then
`tooling/wire/worker-secrets.mjs` pipes it, when present, to
`wrangler secret bulk --name <repo>-web-<env>` over stdin. No bundle, asset,
config file or log holds it. Locally it is `apps/web/.dev.vars`.

## 4. The bindings and the wiring flow

| Binding | Kind | From |
|---|---|---|
| `VISIBILITY_CACHE` | KV namespace | `app_kv_id` in the `cloudflare-kv` root's wiring document |
| `AI` | Workers AI | the account; no key, no resource |
| `ASSETS` | Static Assets | `dist/client`, the dashboard |

`apps/web/wrangler.template.jsonc` is the source; `tooling/wire/live.mjs`
renders `wrangler.jsonc` from it — from `wiring.fixture.json` for `dev`
(which no root applies to) and local work, and on stage and prod from
`WIRING_CLOUDFLARE_KV_<ENV>`, the document the root lease-publishes after
its apply. The committed `wrangler.jsonc` is the fixture's render, so a
fresh clone runs `wrangler dev` with no Orun at all.

Workers AI has no local mode, and `wrangler dev` with the `AI` binding
opens a remote session to the signed-in account (and does not start with
none). `pnpm dev` runs `wrangler dev --local` instead — remote bindings
off, as upstream's Vite config sets `remoteBindings: false` — where every
model call fails and upstream's enrichment answers with its deterministic
fallback, so the surfaces still serve; `pnpm dev:remote` uses the real
model (§7).

## 5. `/api/health`

Added: `GET /api/health` reads the enriched store's key from KV — never
the model — and answers `{ ok, kv, ai, cached, pages }`: whether KV answered,
whether the `AI` binding is bound, whether an enriched store is cached and
how many pages it holds. `ok` is `false` (and the status `503`) only when
KV fails. It is the deploy smoke's check and the probes': a smoke that
fetched `/llms.txt` on a cold cache would run the model over every page on
every deploy.

## 6. Out of scope

- **Web Bot Auth** stays off (`ENABLE_WEB_BOT_AUTH: "false"`), as upstream
  ships it: its directory is upstream's illustrative sample key, which an
  owner replaces before turning it on (AV-D).
- **AI Gateway, Analytics Engine, Durable Objects, Queues** — not used by
  the template, and none is provisioned.
- **A custom domain** — the product is served on `workers.dev`; a domain is
  its owner's to add.

## 7. Testing

`tests/web` imports upstream's Worker and calls its `fetch` with an
in-memory KV namespace (`get` with `"json"`, `put` with `expirationTtl`,
`delete`) and a stand-in `AI` binding: upstream's suite, every assertion
kept, seeds the enriched store as upstream's does; added cases cover
`/api/health`, writes with no token configured, the enrichment of a posted
page by the stand-in model, and the fallback when the model throws.
From AV4 the end-to-end tier serves the built Worker under `wrangler dev`
over a local store, its model a stand-in or absent: every surface, the
dashboard, writes refused, then admitted with a token from `.dev.vars`.
