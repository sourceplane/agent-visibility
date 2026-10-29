# agent-visibility

Cloudflare's [Agent Visibility template](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
— one content store, served to AI agents through every surface they read:
`/llms.txt` and `/llms-full.txt`, a typed `/index.json`, per-page Markdown
and JSON-LD, a `/robots.txt` that names the AI crawlers it welcomes, and a
`Content-Signal` header on each, every page enriched once by **Workers AI**
(a title, a summary, key points, topics, a clean Markdown body) and cached
in **Workers KV**, with a small dashboard previewing the surfaces — running
on **Cloudflare Workers + Static Assets**, with the KV namespace provisioned
by Terraform through [Orun](https://github.com/sourceplane/orun) — and, at
its last milestone (AV4), packaged as an **Orun baseline**: one command
taking a new product from nothing to live on stage and prod, in its own
repository, under its own name, in ONE landing.

The Worker, its surfaces, its enrichment and its dashboard are upstream's,
unchanged; the dashboard is built by Vite into the Worker's Static Assets.
Every surface is **public by design** — it exists to be read by agents.
Writes — adding a page, clearing the cache — are **refused until its owner
stores an admin token**, as upstream ships it. See
[`specs/epics/agent-visibility`](specs/epics/agent-visibility/README.md)
for the design, the milestones and the as-built status.

## What is here

| Surface | Where |
|---|---|
| The Worker: every agent surface, the dashboard's API, the optional Web Bot Auth surface | `apps/web/src/worker/index.ts` |
| The health route (the deploy smoke's store check) | `apps/web/src/worker/health.ts` |
| The enrichment (Workers AI, and its deterministic fallback) and the surfaces' renderers | `apps/web/src/enrichment` |
| The KV store, the sample pages, the types | `apps/web/src/lib` (`store.ts`, `content.ts`, `types.ts`) |
| The dashboard | `apps/web/src/react-app`, `apps/web/index.html`, built by `apps/web/vite.config.ts` |
| Workers bindings and deploy contract | `apps/web/wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The admin token's path to the Worker (a Worker secret) | `tooling/wire/worker-secrets.mjs` |
| The KV namespace (stage, prod) | `infra/terraform/cloudflare-kv` |
| The wrangler renderer | `tooling/wire` |
| Tests | `tests/web` (vitest: upstream's suite over an in-memory KV store and a stand-in model, the health route, the enrichment and its fallback, writes with no token, the config's routes and bindings) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # the dashboard → apps/web/dist/client
```

```bash
pnpm --filter @app/web dev          # the site on http://localhost:8787: a local KV store, the model off
pnpm --filter @app/web dev:remote   # the same with your account's Workers AI (wrangler login first)
```

`pnpm dev` runs `wrangler dev --local`, remote bindings off, as upstream's
dev server does: Workers AI has no local mode, so every page is enriched by
upstream's fallback from its own text (its `model` reads `… (fallback)`).
`dev:remote` calls the real model and may incur Workers AI usage.

## Adding your pages

The site starts with upstream's five sample pages for "Acme" (in
`apps/web/src/lib/content.ts`). Replace them in the source, or post your
own: store `ADMIN_TOKEN` for an environment — an Orun secret,
`orun secrets set ADMIN_TOKEN --env <env>` — and redeploy it; the deploy
pushes it to the Worker as a Worker secret. Then:

```bash
curl -X POST "https://<your-site>/api/resources" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "content-type: application/json" \
  -d '{"slug":"changelog","title":"Changelog","url":"https://example.com/changelog","body":"# Changelog\n\nv2 adds templates."}'
```

```bash
curl -X POST "https://<your-site>/api/refresh" -H "Authorization: Bearer $ADMIN_TOKEN"
```

The first adds (or replaces) one page — `slug` is 1–63 characters of
`[a-z0-9-]`, `body` HTML or Markdown up to 100 kB, at most 100 pages — and
enriches it; the second clears the enriched cache, so the next read
re-enriches every page. With no token stored both answer `401`, and so
does a wrong one. Locally the token goes in `apps/web/.dev.vars`
(`.dev.vars.example`). The site's name on its surfaces is `SITE_NAME` in
`apps/web/wrangler.template.jsonc` (`pnpm run wire:fixture` after editing).

## Deploying

A merge to `main` applies the KV namespace on stage and prod and then
deploys `agent-visibility-web-{stage,prod}` bound to it and to Workers AI,
once `intent.yaml` names the product's Orun workspace (it names the
placeholder `ws_CHANGE_ME` until it is linked, and CI plans nothing). By
hand: Run workflow on `main` (`ci.yml`) with the environment, and
optionally the components, to deploy. The deploy's smoke reads
`/api/health`, which never calls the model: the first visitor's read of a
surface enriches the pages.

## How it maps to Cloudflare's template

| The template | Here |
|---|---|
| `src/worker`, `src/enrichment`, `src/lib`, `src/react-app`, `index.html` | The same files in `apps/web`, plus `src/worker/health.ts` and its one route |
| `vite` + `@cloudflare/vite-plugin` (dev server and build) | Vite with the React plugin builds the dashboard into `dist/client`; wrangler bundles the Worker. `pnpm dev` is `wrangler dev --local`, remote bindings off as upstream's (`remoteBindings: false`) |
| A KV namespace provisioned by "Deploy to Cloudflare" | `infra/terraform/cloudflare-kv`, applied by Orun before the Worker deploys, one namespace per environment, its id rendered into the binding |
| `"ai": { "binding": "AI" }` | Unchanged: keyless, the account's Workers AI |
| `SITE_NAME` "Acme Docs", `SITE_DESCRIPTION` | The product's name and a line about it; the sample pages stay upstream's |
| `npx wrangler secret put ADMIN_TOKEN` | `orun secrets set ADMIN_TOKEN --env <env>` and redeploy: pushed as a Worker secret |
| `npx wrangler deploy` | Orun applies the namespace and deploys `<repo>-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |
| "Deploy to Cloudflare" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |
| `test/index.test.ts` under `@cloudflare/vitest-pool-workers` | `tests/web`: the same assertions, the Worker's own `fetch` over an in-memory store |
| npm, `hono` 4.11.1, `react` 19.2.1 | pnpm, the same versions pinned exactly |

## How the namespace reaches the Worker

```
infra/terraform/cloudflare-kv ──apply──► orun secret WIRING_CLOUDFLARE_KV (stage, prod)
                                               │   (each deploy resolves it as it starts;
                                               │    a missing one fails the lane)
                                               ▼
apps/web  dependsOn cloudflare-kv (enforced on main) · secretEnv WIRING_CLOUDFLARE_KV_<ENV>
          optionalSecretEnv ADMIN_TOKEN
  build:  tooling/wire/live.mjs → wrangler.jsonc with the environment's namespace id
          (dev, verify-only, renders the fixture) → vite build (the token unset)
          → tooling/wire/worker-secrets.mjs: the token, when stored, to the Worker
  deploy: CLOUDFLARE_API_TOKEN (workers-deploy); Workers AI through the AI binding, no key
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds; `tests/web` fails if the
committed render and the fixture disagree.

## CI

| Workflow | What it runs |
|---|---|
| `ci.yml` | the Orun pipeline: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the KV root planned for stage and prod, the dashboard built and the Worker dry-deployed per environment, the tests run); a merge applies the KV namespace, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them |

## Credits

The template this port starts from is Cloudflare's
[`agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template),
MIT (© 2018 Cloudflare, Inc.; kept as `apps/web/LICENSE`).
