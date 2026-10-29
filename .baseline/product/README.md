# agent-visibility

A site made readable by AI agents on every surface they look at — one content
store served as [`/llms.txt`](https://llmstxt.org) and `/llms-full.txt`, a
typed `/index.json`, per-page Markdown (`/<slug>.md`) and schema.org JSON-LD
(`/<slug>.jsonld`, `/jsonld`), and a `/robots.txt` that names the AI crawlers
it welcomes, each with a `Content-Signal` header saying how the content may be
used — with a dashboard at `/` previewing every surface. Each page is
enriched once by **Workers AI** (a title, a summary, key points, topics and a
clean Markdown body) through the Worker's own binding, with no key, and
cached in a **Workers KV** namespace that Terraform provisions per
environment. Cloudflare's
[Agent Visibility template](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
on **Cloudflare Workers + Static Assets**.

Building on it with an agent? Start it at [AGENTS.md](AGENTS.md): what to
read first, how a change lands, and what not to touch.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace and the secrets the site uses into
[ai/context/deployment.md](ai/context/deployment.md); how the site deploys
and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

Every surface is **public by design**: it exists to be read by agents, and
so does everything you add to it. Writes — adding a page, clearing the
cache — are refused until you store an admin token (Adding your pages,
below).

## What is here

| Surface | Where |
|---|---|
| The Worker: every agent surface, the dashboard's API, the optional Web Bot Auth surface | `apps/web/src/worker/index.ts` |
| What the deploy's smoke reads (the store, never the model) | `apps/web/src/worker/health.ts` |
| The enrichment (Workers AI, and its fallback) and the surfaces' renderers | `apps/web/src/enrichment` |
| The KV store, the sample pages, the types | `apps/web/src/lib/store.ts`, `apps/web/src/lib/content.ts`, `apps/web/src/lib/types.ts` |
| The dashboard | `apps/web/src/react-app`, `apps/web/index.html`, built by `apps/web/vite.config.ts` |
| The site's name, the model, the cache's lifetime, the Content-Signal | `vars` in `apps/web/wrangler.template.jsonc` |
| Workers bindings and deploy contract | `apps/web/wrangler.template.jsonc` + `wiring.fixture.json` (→ `wrangler.jsonc`), `component.yaml` |
| The KV namespace (stage, prod) | `infra/terraform/cloudflare-kv` |
| Tests | `tests/web` (vitest, the Worker over an in-memory KV store and a stand-in model) |

## Getting started

```bash
git clone https://github.com/sourceplane/agent-visibility.git
```

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # the dashboard → apps/web/dist/client
```

```bash
cp apps/web/.dev.vars.example apps/web/.dev.vars   # optional: ADMIN_TOKEN, to try writes
pnpm --filter @app/web dev          # http://localhost:8787 — a local KV store, the model off
pnpm --filter @app/web dev:remote   # the same with your account's Workers AI (wrangler login first)
```

Workers AI has no local mode. `pnpm dev` runs `wrangler dev --local`, so
every page is enriched by the Worker's fallback from its own text (its
`model` field reads `… (fallback)`); `dev:remote` calls the real model and
may incur Workers AI usage.

Make it yours: the site's name and description are `SITE_NAME` and
`SITE_DESCRIPTION` in `apps/web/wrangler.template.jsonc` (then
`pnpm run wire:fixture`); the pages it starts with are the five samples in
`apps/web/src/lib/content.ts`; the dashboard is `apps/web/src/react-app`.

## Adding your pages

Store an admin token for an environment — the Orun secret `ADMIN_TOKEN`
(`orun secrets set ADMIN_TOKEN --env prod`) — and redeploy that environment
(Deploy by hand, below): the build hands it to the Worker as a Worker secret,
the value over stdin, never in a bundle. Then, with the same value:

```bash
curl -X POST "https://agent-visibility-web-prod.your-workers-subdomain.workers.dev/api/resources" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "content-type: application/json" \
  -d '{"slug":"changelog","title":"Changelog","url":"https://example.com/changelog","body":"# Changelog\n\nv2 adds templates."}'
```

```bash
curl -X POST "https://agent-visibility-web-prod.your-workers-subdomain.workers.dev/api/refresh" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

The first adds (or replaces) one page — `slug` is 1–63 characters of
`[a-z0-9-]`, `body` HTML or Markdown up to 100 kB, at most 100 pages — and
enriches it; the second clears the enriched cache, so the next read
re-enriches every page. Until the token is stored both answer `401`, and so
does a wrong one. Locally, put it in `apps/web/.dev.vars`. Removing the Orun
secret does not remove the Worker's copy: delete it with
`wrangler secret delete ADMIN_TOKEN --name agent-visibility-web-<env>` too.

The first read of a cold store enriches every page, one model call each, so
it is slow and spends Workers AI usage; the result is cached for
`ENRICHMENT_CACHE_TTL` (an hour), or for a minute when the model failed on a
page and its fallback stood in.

## How the namespace is wired

The Worker binds the namespace as `VISIBILITY_CACHE`. Its id is never
hand-written: `apps/web/wrangler.template.jsonc` names it as a wiring token,
and `wrangler.jsonc` is that template rendered — from `wiring.fixture.json`
(placeholder ids) for local work and verification, and on every deploy from
the document the `cloudflare-kv` Terraform root publishes after its apply
(`WIRING_CLOUDFLARE_KV`, per environment). Edit the template, then
`pnpm run wire:fixture` and commit the render with the template.

KV is eventually consistent: a page added in one location can take up to a
minute to appear in another.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. The KV namespace applies first, then
the site builds with that environment's namespace id and deploys — to
`stage`, then to `prod` once stage has converged on the same commit; `dev`
only verifies. The Worker is `agent-visibility-web-<env>` on your account's
workers.dev subdomain, and every deploy is smoke-tested over HTTP:
`/api/health` must answer ok, its KV store read — the model never called —
and the dashboard must be served. A pull request runs the same pipeline's
verify lanes, with nothing applied or deployed: the KV namespace planned for
stage and prod, and the site built and dry-deployed for each environment.
They do not run the tests or the linter — run those before you push
(Getting started, above).

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id are brokered per run from the workspace's
Cloudflare connection, the namespace ids travel as Orun secrets, and the
admin token is an Orun secret you store; nothing provider-shaped is stored in
the repository or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after storing or
rotating the token, say. A component with nothing to run in that environment
(a test suite in `prod`) is left out with a notice.

## Custom domain

The site answers on workers.dev from its first deploy. To serve it on your
own domain, add the domain to the Cloudflare account the site deploys into
and attach it to the Worker (dashboard → Workers & Pages →
`agent-visibility-web-prod` → Settings → Domains & Routes → Add → Custom
domain). Every surface builds its absolute links from the request it is
answering, so nothing else has to change; the repository names the domain
in one place, `BASE_DOMAIN` in `intent.yaml`, which the site was born with
as the reserved placeholder `agent-visibility.example.com`. Replace it with
your domain in the same change that records it.

## Credits

The site is Cloudflare's
[`agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template),
MIT (© 2018 Cloudflare, Inc.; `apps/web/LICENSE`).
