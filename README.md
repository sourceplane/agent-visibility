# agent-visibility

Cloudflare's [Agent Visibility template](https://github.com/cloudflare/templates/tree/main/agent-visibility-template)
— one content store, served to AI agents through every discovery surface:
`llms.txt` and `llms-full.txt`, a typed JSON index, per-page Markdown,
`robots.txt` with explicit AI-bot directives, `Content-Signal` headers and
schema.org JSON-LD, each page enriched by **Workers AI** and cached in
**Workers KV** — running on **Cloudflare Workers + Static Assets**, with the
KV namespace provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), its writes closed until its
owner stores an admin token — and, at its last milestone (AV4), packaged as
an **Orun baseline**: one command taking a new product from nothing to live
on stage and prod, in its own repository, under its own name, in ONE
landing.

This repository is being built in five steps, one pull request each: the
spec (AV0), the site on Workers (AV1), the KV namespace from Terraform
(AV2), ready to instantiate (AV3), and the baseline (AV4). The design, the
milestones and the as-built status are in
[`specs/epics/agent-visibility`](specs/epics/agent-visibility/README.md).

## Credit

The app is Cloudflare's [`agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template),
MIT-licensed (© 2018 Cloudflare, Inc.); the licence arrives with it, in
`apps/web/LICENSE`, at AV1.
