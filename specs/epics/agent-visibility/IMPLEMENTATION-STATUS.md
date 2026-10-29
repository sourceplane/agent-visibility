# agent-visibility (AV) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template
([cloudflare/templates `agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template),
at `7ae5750`, MIT).

| Milestone | State | PR |
|---|---|---|
| AV0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/agent-visibility/pull/1) (AV-1) |
| AV1 — the site on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/agent-visibility/pull/2) (AV-2) |
| AV2 — the KV namespace from Terraform | ✅ Shipped (validated; apply gated on a linked workspace) | [#3](https://github.com/sourceplane/agent-visibility/pull/3) (AV-3) |
| AV3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/agent-visibility/pull/4) (AV-4) |
| AV4 — a baseline | ✅ Shipped (offline-proven; no live bootstrap yet, risk AV-G) | [#5](https://github.com/sourceplane/agent-visibility/pull/5) (AV-5), tagged `baseline-v1` |

## Departures from the upstream template

### Where it lives

Upstream's template is `apps/web` (`@app/web`) in the monorepo, with its
`LICENSE` beside it (`apps/web/LICENSE`, the cloudflare/templates
licence). Its `src/` and `index.html` are carried file for file; its
`wrangler.jsonc` becomes `wrangler.template.jsonc`, rendered per
environment into `wrangler.jsonc`. Upstream's `package-lock.json`,
`worker-configuration.d.ts`, `tsconfig.node.json` and `vitest.config.ts`
are not carried: pnpm locks the workspace, `src/lib/types.ts` (upstream's)
with `@cloudflare/workers-types` declares the bindings, and two
`tsconfig`s extend the monorepo's — `tsconfig.json` for the Worker,
`tsconfig.app.json` for the dashboard — with upstream's compiler settings
for this code (the `ES2023` lib without `WebWorker`, whose stricter
WebCrypto signatures reject upstream's Web Bot Auth module, and no
unchecked-index rule).

### The build — Vite alone

Upstream builds the Worker and the client together with
`@cloudflare/vite-plugin`. Here Vite with `@vitejs/plugin-react` builds the
dashboard into `dist/client` (`vite.config.ts`) and wrangler bundles
`src/worker/index.ts` — the composition's `workerEntrypoint` — with the
same assets directory, `not_found_handling` and `run_worker_first` list.
`pnpm dev` is `vite build && wrangler dev --local` (remote bindings off, as
upstream's Vite config sets `remoteBindings: false`); `pnpm dev:remote`
drops `--local` and reaches the account's Workers AI.

### The KV namespace

Upstream's `kv_namespaces` entry carries an id from its own account. Here
the id is `@@wiring(cloudflare-kv/__ENV__:app_kv_id)@@`, rendered from the
`cloudflare-kv` root's wiring document on stage and prod, and from
`wiring.fixture.json` for dev and local work (the committed
`wrangler.jsonc` is the stage fixture render). The binding name,
`VISIBILITY_CACHE`, and every key the store writes are upstream's.

### The admin token's path to the Worker

Upstream sets `ADMIN_TOKEN` with `wrangler secret put`. Here it is an
optional Orun secret (`optionalSecretEnv`), so a product deploys without
it and refuses writes until it is stored. The deploy's `buildCommand`
renders the config, runs the build with it unset (`env -u ADMIN_TOKEN`),
then `tooling/wire/worker-secrets.mjs` pushes it, when present, to
`<repo>-web-<env>` with `wrangler secret bulk` over stdin, naming nothing
when it is not stored.

### `/api/health`

New (`src/worker/health.ts`, one route in `src/worker/index.ts`). It reads
`resources:enriched` from KV — never the model — and answers
`{ ok, kv, ai, cached, pages }`, or `503` with `ok: false` when KV fails.
It is the component's smoke (`"ok":true`, then `/` serving the dashboard,
`id="root"`) and the deployment record's probe.

### `SITE_NAME` and `SITE_DESCRIPTION`

Upstream's are the sample's ("Acme Docs", "Product documentation for the
Acme platform."). Here they are the product's name ("AI Agent Visibility",
upstream's own label for the template) and a line about it, so a product's
surfaces carry its own name; the sample pages themselves stay upstream's,
for their owner to replace.

### Tests

Upstream's `test/index.test.ts` ran under `@cloudflare/vitest-pool-workers`
against miniflare. `tests/web/src/worker.test.ts` carries it case for case,
every assertion kept, calling the Worker's own `fetch` over an in-memory KV
namespace and a model that fails every call (as upstream's did, with
remote bindings off), `ADMIN_TOKEN` "test-token". Added: the health route,
the enrichment of a cold store through the stand-in model (one call per
page, cached for the TTL) and its fallback (cached for 60 s), a posted
page's enrichment, writes refused with no token stored or a wrong one, the
site's identity, and the wrangler config's routes, bindings, vars and
wiring.

### Pins

`hono` 4.11.1, `react` and `react-dom` 19.2.1, `@vitejs/plugin-react`
5.1.1, `@types/react` 19.2.7, `@types/react-dom` 19.2.3 and `typescript`
5.9.3 are upstream's exact versions. `wrangler` is the workspace's
`^4.151.0` (upstream: 4.136.1); `vitest` is the monorepo's `^3.2.4`
(upstream: 4.1.10, for its Workers pool).

### Left out

Nothing of the Worker. Web Bot Auth ships off (`ENABLE_WEB_BOT_AUTH:
"false"`), as upstream's (risk AV-D). Upstream's `package.json`
`cloudflare` block (the Deploy to Cloudflare card's metadata) is not
carried; the Orun card is `blueprint.yaml` (AV4).

## What is proven, and how

| Claim | Proven by |
|---|---|
| The Worker serves every surface, the API and the dashboard's routes | `tests/web` (upstream's suite); `wrangler dev --local` by hand (AV1) |
| Writes are refused without the token and admitted with it | `tests/web`; `wrangler dev --local` with `.dev.vars` by hand (AV1) |
| The config binds `VISIBILITY_CACHE`, `AI` and `ASSETS` | `wrangler deploy --dry-run` (AV1); `tests/web/src/config.test.ts` |
| The KV root is valid and publishes `app_kv_id` | `terraform validate` (AV2) |
| The baseline: a product built offline, its plan, its build, its Worker served | Baseline CI's three tiers (AV4, below) |
| A deploy on a linked workspace | Not yet: gated on a linked workspace (risk AV-G) |

## AV4 — a baseline (AV-5)

The repository is an Orun baseline on the Cirrus conventions, held to the
starter standard and built the way turso-starter builds a product: ONE
landing. Its shape is edge-middleware-recipes' (a Hono Worker with optional
secrets handed over as runtime secrets), and its tree is r2-explorer's and
ai-artifacts' (a Static Assets Worker, a KV root, the keyless `AI` binding),
because edge-middleware-recipes has neither Static Assets nor a Terraform
root. `blueprint.yaml` is the card (`requires: [github, cloudflare]`; the
two brokered keys — `CLOUDFLARE_API_TOKEN` from `workers-deploy`,
`CLOUDFLARE_ACCOUNT_ID` — as a preview, and the admin token deliberately
not among them; the programme `01-product`, `02-docs`; `expectedMinutes` 6,
the two phase cards' 5 + 1). `repo-blueprint.yaml` places every module in
`01-product` and lands it as one pull request; `02-docs` records the
deployment from probed facts (`/api/health`: the store read) and puts the
bootstrap's deferrals back.

- **The rename engine** (`tooling/rebrand/rebrand.mjs`, Cirrus's engine,
  this tree's rules): the repository slug, the Worker, the namespace
  titles, the secret refs and the Worker the deploy pushes the token to,
  the domain placeholder, the workers.dev subdomain — and the product's
  name in two seams, `"SITE_NAME"` in the wrangler template and its
  committed render (JSON-encoded) and the dashboard's `<title>`
  (HTML-escaped). The slug is the first half of two upstream names, so
  `UPSTREAM` protects them: Cloudflare's template directory
  (`agent-visibility-template`) and the index protocol
  (`agent-visibility/0.1`, with upstream's own test asserting it). The
  dashboard's kicker, "AI Agent Visibility", is upstream's label for the
  template and is not a seam. The epic slug a bootstrap files its task under
  is `agent-visibility-baselining`.
- **The edge.** `web` on `cloudflare-kv` — `mode: enforced` on a push to
  main, advisory on a pull request.
- **The component docs** are generated (`tooling/catalog/gen-component-docs.py`)
  and checked in Baseline CI.
- **The Workers AI stand-in** (`testing/lib/fake-ai`): under `wrangler dev`
  the end-to-end tier points the `AI` binding at a Worker whose `run`
  answers upstream's prompt with JSON naming the model — or throws, for a
  page marked to fail, so the fallback is exercised on the served Worker
  too.

### Verified (AV4)

- Contract tests: manifest, phases, coverage, rebrand, retouch,
  bootstrap-defer, wire; the component docs match their manifests; `orun
  catalog validate` reports no errors.
- The blueprint read by the bootstrap floor (`orun new --status`); the leak
  gate (78 files derived, nothing local, built or provenance-shaped); the
  offline bootstrap with the blueprint's own hooks, then the product's own
  plan for the 01-product merge — cloudflare-kv → web on stage and prod,
  enforced; advisory on a pull request — and a `--resume` that changes
  nothing; the placed product still speaking `agent-visibility/0.1`.
- The end-to-end tier: the product installed, type-checked, linted, tested
  and built; the stage web lane's own steps in the job tree orun stages,
  with a random marker planted as the admin token in the build's
  environment and found in nothing it wrote or logged; its dry deploy
  binding the stage namespace, Workers AI and the assets (the Worker 23 KiB
  gzipped); the Worker-secrets step naming the token for
  `<repo>-web-stage`; the built Worker served by `wrangler dev` over a
  local store with the stand-in model — the component's own smoke, the
  dashboard under the product's name, every surface with its
  Content-Signal header and the product's name, five pages enriched through
  the binding, Web Bot Auth off, every write refused; then with the token in
  `.dev.vars`, a wrong token and a bad slug refused, a page posted and on
  every surface, a page the model failed on enriched by the fallback, and
  the cache cleared and re-enriched.
- Not verified: everything risks AV-G and AV-H name.
