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
| AV4 — a baseline | Planned | — |

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
| A deploy on a linked workspace | Not yet: gated on a linked workspace |
