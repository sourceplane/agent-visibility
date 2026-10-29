# agent-visibility — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, the secrets it uses) live in
[deployment.md](deployment.md), rendered from probed reality by the
bootstrap's `02-docs` phase; this file is the contract that stays true
between deployments. It is written to give an agent with repository read
access enough context to reason about and operate the site without any
other source.

## What this system is

A site made readable by AI agents on Cloudflare — one content store served
as llms.txt, llms-full.txt, a typed JSON index, per-page Markdown and
JSON-LD and a robots.txt for AI crawlers, each page enriched by Workers AI —
expressed as an Orun component-native desired-state repo.

- **`infra/terraform/cloudflare-kv`** — one Workers KV namespace per deployed
  environment (`stage`, `prod`), applied by Terraform. After each apply it
  publishes a wiring document — `{app_kv_id, app_kv_title}` — as the Orun
  secret `WIRING_CLOUDFLARE_KV` on that environment.
- **`apps/web`** — the site: a Hono Worker plus its dashboard as Static
  Assets (built by Vite). The Worker answers the agent surfaces and the
  dashboard's `/api/*` ahead of the assets (`run_worker_first`); everything
  else is the dashboard. The `VISIBILITY_CACHE` binding holds the raw pages
  (`resources:raw`, absent until a page is posted — the sample pages stand
  in) and their enrichment (`resources:enriched`, put with a TTL). A cold
  store is enriched on the first read that needs it, one model call per page
  through the `AI` binding; a page the model fails on is enriched from its
  own text instead, and a store holding one is cached for 60 s only.
  `/api/health` is what the deploy's smoke reads; it never calls the model.
- **`tests/web`** — upstream's suite and this repository's, the Worker over
  an in-memory KV store and a stand-in model (vitest), verified on the
  `dev` rung.
- **`tooling/*`** — shared TypeScript and ESLint configuration, the wrangler
  renderer that turns `wrangler.template.jsonc` plus a wiring document into
  `wrangler.jsonc`, and the helper that hands the stored admin token to the
  Worker as a secret.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys, and no KV
namespace exists for it (its build renders the committed fixture).

## Who can do what

| Who | Can |
|---|---|
| Anyone, agents first | read every surface and the dashboard — everything in the store is public |
| A bearer of `ADMIN_TOKEN` | add or replace a page (`POST /api/resources`) and clear the enriched cache (`POST /api/refresh`) |
| Nobody, while no token is stored | write: both routes answer `401` |

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. **The namespace before the Worker.** `cloudflare-kv` applies for the
   environment and publishes `WIRING_CLOUDFLARE_KV`. `apps/web` declares an
   enforced `dependsOn` on it for pushes to `main`, so its deploy starts only
   after that apply — and a job resolves its secrets when it starts, so the
   document is there.
4. `apps/web` renders `wrangler.jsonc` from that document (the real
   namespace id), builds the dashboard once per environment, `wrangler
   deploy` ships `agent-visibility-web-<env>` — first handing it the admin
   token as a Worker secret when the environment has one — and a smoke test
   fetches `/api/health`, which must answer `"ok":true` (the store read
   through its binding, the model never called), and `/`, the dashboard.
5. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
6. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

On a pull request nothing applies or deploys: the KV root plans, the site
builds and dry-deploys, and the edges in step 3 are advisory.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/web`.
- `wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`, run
  `pnpm run wire:fixture` and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.
- A deploy does not clear the store. A change to the sample pages, the
  enrichment or `SITE_NAME` reaches the surfaces when the cached store
  expires (`ENRICHMENT_CACHE_TTL`, an hour) or is cleared
  (`POST /api/refresh`).

## Secrets model

- **Brokered provider secrets**: `CLOUDFLARE_API_TOKEN` (the
  `workers-deploy` scope: Workers Scripts and KV Storage write) and
  `CLOUDFLARE_ACCOUNT_ID` — pointers minted per run from the workspace's
  Cloudflare connection. No long-lived values at rest; nothing to rotate by
  hand. The KV root and the Worker deploy use the same two. Workers AI needs
  no key: the `AI` binding runs on the account the Worker is deployed to.
- **Wiring**: `WIRING_CLOUDFLARE_KV` on `stage` and `prod`, written by the
  KV root's apply (lease-published), read by the Worker's build as
  `WIRING_CLOUDFLARE_KV_<ENV>`. It holds ids, not credentials.
- **The admin token, optional**: `ADMIN_TOKEN`, stored by you per
  environment. The build resolves it when it exists (a missing one is
  skipped, not an error), keeps it out of the bundle (`env -u ADMIN_TOKEN`)
  and hands it to the Worker with `wrangler secret bulk` before the deploy.
  Without it every write answers `401`.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the health check on each environment (also recorded, probed, in
# deployment.md): the store read, the AI binding bound, how many pages cached
curl -s https://agent-visibility-web-stage.your-workers-subdomain.workers.dev/api/health
curl -s -o /dev/null -w '%{http_code}\n' https://agent-visibility-web-prod.your-workers-subdomain.workers.dev/

# a surface (on a cold store, this read enriches every page)
curl -s https://agent-visibility-web-prod.your-workers-subdomain.workers.dev/llms.txt

# the wiring the deploys read, and workspace readiness
orun secrets list --org <ws> --env stage && orun secrets list --org <ws> --env prod
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| change the dashboard | edit `apps/web/src/react-app`, merge |
| change a surface | `apps/web/src/enrichment/surfaces.ts` (what each renders), `apps/web/src/worker/index.ts` (the routes; a new path needs its entry in `assets.run_worker_first` in `wrangler.template.jsonc`) |
| change the site's name or description | `SITE_NAME` / `SITE_DESCRIPTION` in `apps/web/wrangler.template.jsonc` (render, commit, merge), then clear the cache |
| change the sample pages | `apps/web/src/lib/content.ts`, merge, then clear the cache |
| store or rotate the admin token | `orun secrets set ADMIN_TOKEN --org <ws> --env <env>`, then deploy that environment by hand |
| add or replace a page | `POST /api/resources` with `Authorization: Bearer <ADMIN_TOKEN>` (README, "Adding your pages") |
| clear the enriched cache | `POST /api/refresh` with the token; the next read re-enriches every page |
| remove the token | `orun secrets revoke ADMIN_TOKEN --org <ws> --env <env>` and `wrangler secret delete ADMIN_TOKEN --name agent-visibility-web-<env>` — the Worker keeps its copy until then |
| change the model, the cache's lifetime or the Content-Signal | `AI_MODEL`, `ENRICHMENT_CACHE_TTL`, `CONTENT_SIGNAL` as `vars` in `apps/web/wrangler.template.jsonc` (render, commit, merge) |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| add a binding (R2, D1, another KV) | a Terraform root under `infra/terraform/` that publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its fixture entry, the root in the build's `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv and an enforced `dependsOn` on it in `apps/web/component.yaml` |
| inspect the store | `wrangler kv key get resources:enriched --namespace-id <id> --remote` (the id is in the environment's `WIRING_CLOUDFLARE_KV`) |
| serve a custom domain | attach it to the Worker in Cloudflare (README, "Custom domain"), then replace the placeholder `agent-visibility.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it |
| add a runtime secret of your own | `orun secrets set <KEY> --org <ws> --env <env>`, its ref under `optionalSecretEnv` in `apps/web/component.yaml` and a `--secret <KEY>` (and `-u <KEY>`) in its `buildCommand` |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Web Bot Auth (agent identity) ships off: turning it on means replacing the
sample key in `apps/web/src/lib/web-bot-auth.ts` with the keys of agents you
trust and setting `ENABLE_WEB_BOT_AUTH` to `"true"`. A store larger than
upstream's cap (100 pages) would outgrow one KV value per store — a D1
database of its own. Structural changes follow the same contract that
deployed the site: add a component under `apps/`, `infra/` or `packages/`
with a `component.yaml`, land it as a pull request, and the convergence run
applies it.
