# agent-visibility

Cloudflare's [Agent Visibility template](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
— one content store, served to AI agents through every surface they read:
`/llms.txt` and `/llms-full.txt`, a typed `/index.json`, per-page Markdown
and JSON-LD, a `/robots.txt` that names the AI crawlers it welcomes, and a
`Content-Signal` header on each, every page enriched once by **Workers AI**
and cached in **Workers KV**, with a small dashboard previewing the surfaces
— running on **Cloudflare Workers + Static Assets**, with the KV namespace
provisioned by Terraform through [Orun](https://github.com/sourceplane/orun),
and packaged as an **Orun baseline**: one command takes a new product from
nothing to live on stage and prod, in its own repository, under its own
name — in ONE landing.

The Worker, its surfaces, its enrichment and its dashboard are upstream's,
unchanged; the dashboard is built by Vite into the Worker's Static Assets.
Every surface is **public by design**. Writes — adding a page, clearing the
cache — are **refused until its owner stores an admin token**, as upstream
ships it. What the baseline adds is everything needed to make a copy of it
somebody else's, built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) is since
its one-landing bootstrap. See
[`specs/epics/agent-visibility`](specs/epics/agent-visibility/README.md) for
the design, the milestones and the as-built status.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/agent-visibility
cd agent-visibility
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-docs --run-hooks --resume \
  --set reponame=acme-docs --set productname="Acme Docs" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`agent-visibility` → Build). Two phases: **`01-product`** creates the
repository and lands the whole product as ONE pull request — intent, CI,
tooling, the KV root, the site and its tests — and one convergence applies
the KV namespace on stage and prod and then deploys the site bound to it;
**`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The only connection a build needs is Cloudflare. The site works from the
first deploy with upstream's sample pages: the Worker reaches its namespace
and Workers AI through its bindings, so there is no key to paste. Its admin
token — `ADMIN_TOKEN`, an optional Orun secret the deploy pushes to the
Worker as a Worker secret — is the owner's to set after the build.

The new repository receives the **product only** — the site, its KV root,
its tests, its CI, its tooling, a README and an `AGENTS.md` of its own and
its operating contract — renamed throughout to the product's name (on every
agent surface, via `SITE_NAME`, and in the dashboard's title), repository,
Cloudflare Worker and namespace titles. None of this repository's machinery
ships.

**Two upstream names begin with the slug.** Cloudflare's template directory,
`agent-visibility-template`, and the typed index's protocol,
`agent-visibility/0.1`, which every `/index.json` carries for the agents that
read it: the rename engine renames this baseline's slug everywhere EXCEPT
those (`tooling/rebrand/rebrand.mjs`, `UPSTREAM`; held by
`testing/rebrand.test.sh` and `testing/placement.test.sh`).

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, and the bootstrap's task contracts | `.baseline/` |
| The rename engine | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's README, `AGENTS.md` and context pack | `.baseline/product/`, `ai/context/` |
| The baseline's tests: contract, wiring, leak, offline bootstrap, end to end (with a Workers AI stand-in) | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

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
committed render and the fixture disagree, and so does `testing/wire.test.sh`.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the KV root planned for stage and prod, the dashboard built and the Worker dry-deployed per environment), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it (the landing checked its commit in the box); a merge applies the KV namespace, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests, the wiring path, the blueprint read by the pinned orun, the leak gate, the offline bootstrap with the product's own plan, the landing installed, type-checked, linted, tested and built, the product built in the job tree, dry-deployed and served over a local store with a Workers AI stand-in — every surface, writes refused, then admitted with a token | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |

## Credits

The template this port starts from is Cloudflare's
[`agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template),
MIT (© 2018 Cloudflare, Inc.; kept as `apps/web/LICENSE`).
