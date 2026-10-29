# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`agent-visibility/`](./agent-visibility/) | **AV** | ✅ Shipped (AV0–AV4, `baseline-v1`) | Cloudflare's Agent Visibility template — one content store served to AI agents as llms.txt, a JSON index, per-page Markdown, robots.txt, Content-Signal headers and JSON-LD, enriched by Workers AI — on Cloudflare Workers with the KV namespace from Terraform, and an Orun baseline that instantiates it in one landing (AV4) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
