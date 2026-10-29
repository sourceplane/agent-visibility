#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the repository link, the two display-name seams, the worker name in
# the component and the wrangler config, the KV namespace titles and the
# terraform `repo` they are built from, the placeholder domain, a secret ref,
# the upstream names that begin with the slug — and the
# survival cases run through three passes, so a value an earlier rebrand
# wrote (a re-run phase re-runs the rebrand over everything placed) comes
# out of every later one unchanged.
#
# The identity is PINNED (fixtures/baseline-identity.agent-visibility.json)
# rather than read from .baseline/identity.json: what this tests is the engine,
# and its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.agent-visibility.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-docs","productname":"Acme Docs","productdomain":"acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the site's own identity"
check "the repository link names the product's owner and repository" \
  "$acme" README.md \
  'Source: https://github.com/sourceplane/agent-visibility' \
  'Source: https://github.com/acme-inc/acme-docs'
check "the site-name seam takes the product's name" \
  "$acme" apps/web/wrangler.template.jsonc '    "SITE_NAME": "AI Agent Visibility",' \
  '    "SITE_NAME": "Acme Docs",'
check "…and so does its committed render" \
  "$acme" apps/web/wrangler.jsonc '    "SITE_NAME": "AI Agent Visibility",' \
  '    "SITE_NAME": "Acme Docs",'
check "…and stays valid JSON for a name with an apostrophe, an ampersand and a quote" \
  '{"reponame":"sams-docs","productname":"Sam'"'"'s \"Docs\" & Notes","productdomain":"sam.dev"}' \
  apps/web/wrangler.template.jsonc '    "SITE_NAME": "AI Agent Visibility",' \
  '    "SITE_NAME": "Sam'"'"'s \"Docs\" & Notes",'
check "the dashboard's title takes the product's name" \
  "$acme" apps/web/index.html '		<title>AI Agent Visibility — be readable on every agent surface</title>' \
  '		<title>Acme Docs — be readable on every agent surface</title>'
check "…HTML-escaped" \
  '{"reponame":"sams-docs","productname":"Sam'"'"'s Docs & <Notes>","productdomain":"sam.dev"}' \
  apps/web/index.html '		<title>AI Agent Visibility — be readable on every agent surface</title>' \
  '		<title>Sam'"'"'s Docs &amp; &lt;Notes&gt; — be readable on every agent surface</title>'
check "the dashboard's kicker is upstream's label for the template, and is left alone" \
  "$acme" apps/web/src/react-app/App.tsx '				<p className="kicker">AI Agent Visibility</p>' \
  '				<p className="kicker">AI Agent Visibility</p>'
check "the display name elsewhere is content, and is left alone" \
  "$acme" apps/web/README.md 'AI Agent Visibility, wherever it is not a seam, is prose.' \
  'AI Agent Visibility, wherever it is not a seam, is prose.'
check "the worker name is re-prefixed, the environment suffix kept" \
  "$acme" apps/web/component.yaml 'workerName: agent-visibility-web' \
  'workerName: acme-docs-web'
check "the wrangler config's worker name, template and render alike" \
  "$acme" apps/web/wrangler.template.jsonc '  "name": "agent-visibility-web",' \
  '  "name": "acme-docs-web",'
check "the environment URLs: worker name and subdomain" \
  "$acme" intent.yaml '    url: https://agent-visibility-web-stage.your-workers-subdomain.workers.dev' \
  '    url: https://acme-docs-web-stage.acme.workers.dev'
check "the KV root's terraform repo — every namespace title is built on it" \
  "$acme" infra/terraform/cloudflare-kv/terraform/main.tf '  default = "agent-visibility"' \
  '  default = "acme-docs"'
check "the per-environment terraform repo parameter" \
  "$acme" intent.yaml '        repo: agent-visibility' \
  '        repo: acme-docs'
check "a fixture's namespace title follows the same rule" \
  "$acme" apps/web/wiring.fixture.json '    "app_kv_title": "stg-agent-visibility-app-kv-stage"' \
  '    "app_kv_title": "stg-acme-docs-app-kv-stage"'
check "the placeholder domain is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: agent-visibility.example.com' \
  '      BASE_DOMAIN: acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-docs","productname":"Acme Docs","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: agent-visibility.example.com' \
  '      BASE_DOMAIN: acme-docs.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-docs","productname":"Acme Docs","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: agent-visibility.example.com' \
  '      BASE_DOMAIN: acme-docs.example.com'
check "the repo slug" \
  "$acme" package.json '  "name": "agent-visibility",' \
  '  "name": "acme-docs",'
check "a wiring secret ref names the product's workspace and project" \
  "$acme" apps/web/component.yaml \
  '    WIRING_CLOUDFLARE_KV_STAGE: "secret://agent-visibility/agent-visibility/stage/WIRING_CLOUDFLARE_KV"' \
  '    WIRING_CLOUDFLARE_KV_STAGE: "secret://ws_79BDXAZQ/acme-docs/stage/WIRING_CLOUDFLARE_KV"'
check "the KV root's templated token ref too" \
  "$acme" infra/terraform/cloudflare-kv/component.yaml \
  '    CLOUDFLARE_API_TOKEN: "secret://agent-visibility/agent-visibility/{{ .environment }}/CLOUDFLARE_API_TOKEN"' \
  '    CLOUDFLARE_API_TOKEN: "secret://ws_79BDXAZQ/acme-docs/{{ .environment }}/CLOUDFLARE_API_TOKEN"'
check "the optional admin token names the product's workspace and project" \
  "$acme" apps/web/component.yaml \
  '    ADMIN_TOKEN: "secret://agent-visibility/agent-visibility/{{ .environment }}/ADMIN_TOKEN"' \
  '    ADMIN_TOKEN: "secret://ws_79BDXAZQ/acme-docs/{{ .environment }}/ADMIN_TOKEN"'
check "the Worker the token is pushed to is the product's" \
  "$acme" apps/web/component.yaml \
  '    buildCommand: node ../../tooling/wire/worker-secrets.mjs --secret ADMIN_TOKEN --worker "agent-visibility-web-${ORUN_ENVIRONMENT}" --config wrangler.jsonc' \
  '    buildCommand: node ../../tooling/wire/worker-secrets.mjs --secret ADMIN_TOKEN --worker "acme-docs-web-${ORUN_ENVIRONMENT}" --config wrangler.jsonc'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'
check "without githuborg the repository link keeps the baseline's owner" \
  '{"reponame":"acme-docs","productname":"Acme Docs","productdomain":"acme.dev"}' \
  README.md 'Source: https://github.com/sourceplane/agent-visibility' \
  'Source: https://github.com/sourceplane/acme-docs'

# TWO UPSTREAM NAMES BEGIN WITH THIS BASELINE'S SLUG: Cloudflare's template
# directory (`agent-visibility-template`) and the typed index's protocol
# (`agent-visibility/0.1`). Renamed, a product's docs would link to a template
# that does not exist and its /index.json would speak a protocol no agent
# knows. Both come out unchanged (tooling/rebrand/rebrand.mjs UPSTREAM).
echo "── rebrand: the upstream names keep their spelling"
check "the template it was ported from" \
  "$acme" README.md 'https://github.com/cloudflare/templates/tree/main/agent-visibility-template' \
  'https://github.com/cloudflare/templates/tree/main/agent-visibility-template' 3
check "the template's name, beside a renamed worker name" \
  "$acme" apps/web/README.md '`agent-visibility-template`, deployed as agent-visibility-web' \
  '`agent-visibility-template`, deployed as acme-docs-web' 3
check "the index protocol" \
  "$acme" apps/web/src/enrichment/surfaces.ts 'export const INDEX_PROTOCOL = "agent-visibility/0.1";' \
  'export const INDEX_PROTOCOL = "agent-visibility/0.1";' 3
check "…and upstream's suite asserting it" \
  "$acme" tests/web/src/worker.test.ts '		expect(json.protocol).toContain("agent-visibility");' \
  '		expect(json.protocol).toContain("agent-visibility");' 3
check "…and a product whose slug contains the baseline's keeps both" \
  '{"reponame":"agent-visibility-2","productname":"Docs 2","githuborg":"sourceplane"}' README.md \
  'agent-visibility-template speaks agent-visibility/0.1 in agent-visibility' \
  'agent-visibility-template speaks agent-visibility/0.1 in agent-visibility-2' 3

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"agent-visibility-2","productname":"AI Agent Visibility 2","productdomain":"agent-visibility.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "agent-visibility",' \
  '  "name": "agent-visibility-2",' 3
check "a worker name built on it survives three passes" \
  "$contains" apps/web/component.yaml 'workerName: agent-visibility-web' \
  'workerName: agent-visibility-2-web' 3
check "a namespace title built on it survives three passes" \
  "$contains" apps/web/wiring.fixture.json '    "app_kv_title": "prod-agent-visibility-app-kv-prod"' \
  '    "app_kv_title": "prod-agent-visibility-2-app-kv-prod"' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: agent-visibility.example.com' \
  'BASE_DOMAIN: agent-visibility.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" apps/web/component.yaml 'workersDevSubdomain: your-workers-subdomain' \
  'workersDevSubdomain: your-workers-subdomain-2' 3
check "a site name containing the baseline's name survives three passes" \
  "$contains" apps/web/wrangler.template.jsonc '    "SITE_NAME": "AI Agent Visibility",' \
  '    "SITE_NAME": "AI Agent Visibility 2",' 3
check "…and so does a title containing it" \
  "$contains" apps/web/index.html '<title>AI Agent Visibility — be readable</title>' \
  '<title>AI Agent Visibility 2 — be readable</title>' 3

# --verify runs in every phase. Without the product's values it cannot tell
# the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "agent-visibility-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "agent-visibility-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "agent-visibility"' fail --values
verify "a leftover worker name fails" \
  "$acme" apps/web/wrangler.jsonc '"name": "agent-visibility-web",' fail --values
verify "a leftover namespace title fails" \
  "$acme" apps/web/wiring.fixture.json '"app_kv_title": "stg-agent-visibility-app-kv-stage"' fail --values
verify "a leftover code identifier fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/web/src/x.ts 'export class AgentVisibility {}' fail --values
verify "the upstream names are not residue" \
  "$acme" apps/web/src/enrichment/surfaces.ts 'agent-visibility/0.1 · agent-visibility-template' pass --values
verify "…but the slug beside them is" \
  "$acme" apps/web/src/enrichment/surfaces.ts 'agent-visibility/0.1 in agent-visibility' fail --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-docs"' pass --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/web"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "AGENT_VISIBILITY_TOKEN"\n' > "$tmp/apps/web/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
