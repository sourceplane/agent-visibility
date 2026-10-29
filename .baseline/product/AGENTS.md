# AGENTS.md — agent-visibility

For a coding agent (or a person) about to change this repository.

## What this is

A site made readable by AI agents: one content store served as `llms.txt`
and `llms-full.txt`, a typed `index.json`, per-page Markdown and JSON-LD,
and a `robots.txt` for AI crawlers, each with a `Content-Signal` header, and
a dashboard previewing them. A Hono Worker on Cloudflare Workers + Static
Assets (the dashboard built by Vite), each page enriched by Workers AI
through the Worker's `AI` binding and cached in a Workers KV namespace that
Terraform provisions per environment. It is an
[Orun](https://github.com/sourceplane/orun) repository: `intent.yaml`
declares the environments, and each `component.yaml` is a component Orun
plans and deploys.

| Component | Path | What it is |
|---|---|---|
| `web` | `apps/web` | the Worker and its dashboard, `agent-visibility-web-<env>` |
| `cloudflare-kv` | `infra/terraform/cloudflare-kv` | the KV namespace on stage and prod |
| `web-tests` | `tests/web` | vitest, the Worker over an in-memory KV store and a stand-in model |

## Read first

1. `README.md` — run, test, preview, add pages with the admin token, and how
   it deploys.
2. `ai/context/operations.md` — the operating contract: deploy order,
   secrets, caveats, common operations.
3. `ai/context/deployment.md` — what is live now: URLs, workspace, secrets
   by name.
4. `apps/web/src/worker/index.ts` — every route; then
   `apps/web/src/lib/store.ts` (the KV store and when it enriches),
   `apps/web/src/enrichment/index.ts` (the model call and its fallback) and
   `apps/web/src/enrichment/surfaces.ts` (what each surface renders).
5. `infra/terraform/cloudflare-kv` — the namespace, and the wiring document
   (`WIRING_CLOUDFLARE_KV`) the site's build reads its id from.

## Before you push

```bash
pnpm install
pnpm run wire:fixture        # apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck && pnpm lint && pnpm test && pnpm build
```

Run them yourself: the pull request's lanes build and dry-deploy the site
and plan the KV root, but do not run the tests or the linter.

## How changes land

- One change, one pull request into `main`. If the work is an Orun task,
  open the pull request for it: `orun pr open --task <KEY>`.
- On the pull request, `ci.yml` plans with `orun plan --changed` and
  verifies: the KV root plans, the site builds and dry-deploys. Nothing
  applies or deploys.
- The merge is the deploy. `ci.yml` plans the changed components and runs
  each lane: the KV namespace applies first, then the site builds with its
  id, hands the stored admin token to the Worker as a secret, deploys and is
  smoke-tested — stage, then prod.
- A new component is a directory under `apps/`, `infra/`, `packages/` or
  `tests/` with a `component.yaml`; `ai/context/operations.md` says how to
  add a binding.

## What not to touch

- `intent.yaml` → `execution.state.workspace`: the workspace CI
  authenticates to. Also the stack-tectonic pin (`0.19.0`); its comment says
  why it is not `0.20.0`.
- `apps/web/wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`,
  then `pnpm run wire:fixture`, and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.
- `apps/web/component.yaml`'s `dependsOn: cloudflare-kv`: it is what makes
  the namespace apply before the Worker deploys on `main`.
- The last line of each `component.yaml` (`# orun: redeploy …`) is a deploy
  trigger; change it only to redeploy.
- `ai/context/deployment.md` is regenerated from probed state; a hand edit is
  overwritten. `.rebrand/values.json` records the site's identity; leave it.
- Only `ci.yml` may run on a push to `main`.
- No secret value goes in the repository, and none reaches the build: the
  admin token is an Orun secret the build strips from its environment
  (`env -u ADMIN_TOKEN`) and hands to the Worker as a Worker secret. The
  Cloudflare token and account id are brokered from the workspace's
  Cloudflare connection; list secrets by name only (`orun secrets list`).
- `/api/health` must never call the model: the deploy's smoke reads it on
  every deploy, and a model call there would spend Workers AI each time.
- `INDEX_PROTOCOL` (`agent-visibility/0.1`, in
  `apps/web/src/enrichment/surfaces.ts`) names the shape of `/index.json`
  for the agents that read it; change it only with the shape.
- Every surface is public. Nothing private belongs in the store.
