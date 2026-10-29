# agent-visibility — implementation plan

## AV0 — the spec (AV-1)

**Done when**
- the five documents and `epic.yaml` are on `main`, with `tasks/AV-1..AV-5.TaskContract.yaml`
- the repository's intent (`intent.yaml`, workspace `ws_CHANGE_ME` until it is linked), `ci.yml` (the plan job a green no-op until then), the workspace files and the shared tooling (`tooling/{eslint,tsconfig,wire}`) are on `main`

## AV1 — the site on Workers (AV-2)

**Done when**
- `apps/web` is upstream's template — its Worker, enrichment, store, sample content and dashboard, upstream's bindings, vars and `run_worker_first` list — plus `/api/health`, the Vite-only dashboard build and the wrangler template with its committed fixture render
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally; `tests/web` runs upstream's suite over an in-memory store
- `wrangler deploy --dry-run` lists `env.VISIBILITY_CACHE`, `env.AI` and `env.ASSETS`
- `wrangler dev` serves the dashboard and every surface over a local store; writes are refused with no `.dev.vars`, and with `ADMIN_TOKEN` in it a page is posted and served as Markdown
- the deploy hands the optional token to the Worker as a Worker secret (`tooling/wire/worker-secrets.mjs`), the build running without it

## AV2 — the KV namespace from Terraform (AV-3)

**Done when**
- `terraform validate` passes on `infra/terraform/cloudflare-kv`, and `app_kv_id` is the key the template's token names
- the root publishes `WIRING_CLOUDFLARE_KV` to stage and prod; `web` declares its edge on it, enforced on main and advisory on a pull request

## AV3 — ready to instantiate (AV-4)

**Done when**
- the README quick start works from a fresh clone: install, dev, test, preview, add a page, deploy by hand
- the status file lists every PR and every departure from upstream

## AV4 — a baseline (AV-5)

The repository becomes an Orun baseline on the Cirrus conventions, held to
the starter standard and built the way turso-starter builds a product — in
ONE landing:

- `blueprint.yaml` (the card: `requires [github, cloudflare]`, the two
  brokered secrets as a preview, the programme `01-product`, `02-docs`) and
  `repo-blueprint.yaml` (every module placed by `01-product` and landed as
  one pull request; `02-docs` hook-only);
- `web`'s edge on `cloudflare-kv` `mode: enforced` on a push to main,
  advisory on a pull request;
- the rename engine (`tooling/rebrand`), which renames the product
  throughout and leaves upstream's names — `agent-visibility-template`, the
  `agent-visibility/0.1` index protocol — as they are;
- the bootstrap tooling, the product's README, `BOOTSTRAP.md` and context
  pack (`ai/context`), generated component docs;
- `testing/`: the contract tiers, the leak and placement gates, the
  offline bootstrap and the product's plans, the end-to-end tier;
- `baseline.yml` and `tag.yml`; tagged `baseline-v1` once Baseline CI is
  green on `main`.
