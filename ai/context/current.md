# agent-visibility — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Cloudflare's Agent Visibility template — one content store served to AI
agents as llms.txt, llms-full.txt, a typed JSON index, per-page Markdown and
JSON-LD and a robots.txt for AI crawlers, each with a Content-Signal header,
every page enriched by Workers AI through the Worker's own binding (no key)
and cached in Workers KV, with a dashboard over the surfaces — on Cloudflare
Workers + Static Assets, the namespace from Terraform. It is packaged as an
Orun baseline: `orun new --blueprint repo-blueprint.yaml` builds a new
product in its own repository and takes it to live on stage and prod in one
landing (`01-product`: the KV namespace, then the Worker that binds it), then
records what went live (`02-docs`).

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (AV4, [#5](https://github.com/sourceplane/agent-visibility/pull/5)) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the product built in orun's staged job tree, dry-deployed with the stage document's namespace id and the AI binding, served by `wrangler dev` with a Workers AI stand-in — every surface, the dashboard, writes refused and then admitted with a token — and the deploy's own smoke passed. No bootstrap from a tag has run against a workspace (risk AV-G), and a real model's enrichment is unproven (AV-H) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/agent-visibility/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/agent-visibility/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/agent-visibility/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `apps/web/docs/`, `infra/terraform/cloudflare-kv/docs/`, `tests/web/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from the tag against a workspace, read `/llms.txt`
   on stage (the model's enrichment), post a page with a stored token, and
   record the timings (closes AV-G and AV-H).
