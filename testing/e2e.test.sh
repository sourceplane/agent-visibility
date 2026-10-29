#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, deploys (dry) and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      install with the lockfile the product ships, render the wrangler
#      fixture and check the committed config IS that render, typecheck,
#      lint, test, build. The landing's own PR runs `plan` alone (an
#      `orun/BASE-*` branch), so THIS is where a product those steps refuse
#      is caught: before the tag, not after a build has merged it;
#   2. the stage lane's own steps, rendered by `orun plan` in the product for
#      a pull request (the verify profile: the deploy profile has no dry run)
#      — `verify-app-structure` (which checks the wrangler config exists
#      BEFORE anything is built), `build-app` (the component's buildCommand:
#      the live wiring render, then the build), `verify-build-output` and
#      `deploy-dry-run` (`wrangler deploy --dry-run --name <reponame>-web-stage`).
#      They run IN THE TREE THE RUNNER STAGES for the job
#      (testing/lib/stage-job.py), with the dependency layout the pinned
#      composition produces, and with the stage wiring document in the job's
#      environment as the platform resolves it (the component's secretEnv) —
#      so the namespace id in the built config is asserted to be the
#      document's, not the fixture's;
#      The build runs with an admin token in its environment, as a deploy
#      lane with the secret stored would: it must never reach the build output
#      (the build strips it), and the Worker-secrets step must say it goes to
#      `<reponame>-web-stage` from the deploy lane — a verify lane holds no
#      Cloudflare credential and pushes nothing. The dry run must bind the KV
#      store, Workers AI and the assets, and fit Workers Free (3 MiB gzipped);
#   3. serve the built Worker with `wrangler dev`, its `AI` binding pointed at
#      a deterministic stand-in for Workers AI (testing/lib/fake-ai: Workers AI
#      has no local mode), and run the component's OWN `smokeCommand` against
#      it, verbatim — the check the real deploy ends with — and then every
#      route the product promises: the dashboard titled with the product's
#      name, an unknown path its single-page app; /api/health reading a cold
#      store without calling the model; llms.txt, llms-full.txt, the typed
#      index (still the agent-visibility/0.1 protocol), per-page Markdown and
#      JSON-LD, robots.txt, each with its Content-Signal header and the
#      product's name, every sample page enriched through the AI binding;
#      Web Bot Auth off; every write refused with no token stored. Then the
#      same Worker served again with the admin token in `.dev.vars` (written
#      by the same helper the deploy hands it over with): a wrong token
#      refused, a page posted, enriched by the model and on every surface, a
#      page the model fails on enriched by the fallback, and the cache
#      cleared.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, apply the namespace, push the secret, deploy for
# real and probe workers.dev — nor a real model. The KV root is verified to
# `terraform validate` and its plan is part of every pull request's lanes;
# the apply needs an account.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, and the network for
# `pnpm install` (or a warm store). A few minutes: two installs and builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
cleanup() {
  if [ -n "$dev_pid" ]; then
    kill -TERM -- "-$dev_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL -- "-$dev_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step — the ones the product's retired
# Checks workflow ran, run here at once on the whole tree. A product's pull
# requests verify through ci.yml's lanes (the dashboard built and the Worker
# dry-deployed per environment, the KV root planned), which neither
# type-check, lint nor run the tests, so before a tag THIS is where those are
# held.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "git diff --exit-code"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"
s01="$(git -C "$tree" rev-parse HEAD~1)"

# ── 1. the product's one pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
# The landing's build is done; its tree is not needed again, and the disk is shared.
git -C "$tree" worktree remove --force "$scratch/at-01"

# ── 2. the stage lane's steps, in the job's own tree ──────────────────────
echo "── the stage lane: verify-app-structure, build-app, verify-build-output, deploy-dry-run"
# A pull request that changes the site: the lane `orun plan` gives it.
git -C "$tree" checkout -q -b e2e-pr
echo "<!-- a change to the site's component -->" >> "$tree/apps/web/README.md"
git -C "$tree" -c user.email=e2e@example.invalid -c user.name=e2e commit -qam "a pull request"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base main --head HEAD --env stage --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
python3 - "$scratch/plan.json" "$scratch/steps" <<'PY'
import json, pathlib, sys
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
job = next(j for j in plan["jobs"] if j["component"] == "web" and j["environment"] == "stage")
for s in job["steps"]:
    if s["id"] in ("verify-app-structure", "build-app", "verify-build-output", "deploy-dry-run"):
        (out / f"{s['id']}.sh").write_text(s.get("run") or "")
    if s["id"] == "install-workspace-dependencies":
        (out / "install.sh").write_text(s.get("run") or "")
        (out / "install.wd").write_text(s.get("working-directory") or ".")
        (out / "install.scope").write_text(s.get("scope") or "job")
(out / "path").write_text(job.get("path") or "apps/web")
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
(out / "secrets").write_text("\n".join(r["asEnv"] for r in job.get("secretRefs") or []))
PY
# The job's private tree, staged as orun stages it. The source checkout
# carries no build output (nothing was built in it), and its dependencies are
# what the pinned composition says: a lane-scoped install ran once in the
# source tree and is linked in, or the job installs its own.
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
[ -f "$scratch/steps/install.sh" ] || { echo "FAIL: the stage lane has no install step" >&2; exit 1; }
if [ "$(cat "$scratch/steps/install.scope")" = lane ]; then
  (cd "$tree" && bash -e "$scratch/steps/install.sh") > "$scratch/install.log" 2>&1 \
    || { echo "FAIL: the lane's install step" >&2; tail -30 "$scratch/install.log" >&2; exit 1; }
  python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: lane — node_modules → the source tree's"
else
  python3 "$here/lib/stage-job.py" "$tree" "$work"
  echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: job — installing inside it"
  echo "   ▸ install-workspace-dependencies"
  (cd "$work/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/install.wd")" && bash -e "$scratch/steps/install.sh") \
    > "$scratch/install.log" 2>&1 || { echo "FAIL: the lane's install step" >&2; tail -30 "$scratch/install.log" >&2; exit 1; }
  [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ] \
    || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
fi
[ ! -e "$work/apps/web/dist" ] || { echo "FAIL: the staged tree carries build output" >&2; exit 1; }
# What the platform resolves into the job before its first step: the wiring
# documents the KV root lease-published (the component's secretEnv). Ids no
# fixture carries, so the built config proves which one it was rendered from.
for env in stage prod; do
  key="WIRING_CLOUDFLARE_KV_$(echo "$env" | tr a-z A-Z)"
  grep -qx "$key" "$scratch/steps/secrets" || { echo "FAIL: the stage lane does not resolve $key" >&2; exit 1; }
done
export WIRING_CLOUDFLARE_KV_STAGE='{"app_kv_id":"5ca1ab1e5ca1ab1e5ca1ab1e0000a001","app_kv_title":"stg-'"$repo"'-app-kv-stage"}'
export WIRING_CLOUDFLARE_KV_PROD='{"app_kv_id":"5ca1ab1e5ca1ab1e5ca1ab1e0000a003","app_kv_title":"prod-'"$repo"'-app-kv-prod"}'
# An admin token in the job's environment, as a deploy lane with the secret
# stored resolves it (optionalSecretEnv): a marker no source carries, so a
# build output that held it would say so.
token_marker="av_e2e_$(python3 -c 'import secrets;print(secrets.token_hex(12))')"
export ADMIN_TOKEN="$token_marker"
for step in verify-app-structure build-app verify-build-output deploy-dry-run; do
  [ -f "$scratch/steps/$step.sh" ] || { echo "FAIL: the stage verify lane has no $step step" >&2; exit 1; }
  echo "   ▸ $step"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`), its resolved secrets, and ORUN_ENVIRONMENT; the step runs in the
  # component's directory.
  if ! (cd "$work/$(cat "$scratch/steps/path")" && \
        { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage && bash -e "$scratch/steps/$step.sh") > "$scratch/$step.log" 2>&1; then
    echo "FAIL: the deploy lane's $step step" >&2; tail -40 "$scratch/$step.log" >&2; exit 1
  fi
done
grep -q '"5ca1ab1e5ca1ab1e5ca1ab1e0000a001"' "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: the lane's build did not render the stage namespace id from its wiring document" >&2; exit 1; }
grep -Eq 'env\.VISIBILITY_CACHE \(5ca1ab1e5ca1ab1e5ca1ab1e0000a001\)' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind VISIBILITY_CACHE to the stage namespace" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
grep -Eq 'env\.AI +AI' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind Workers AI as AI" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
grep -Eq 'env\.ASSETS +Assets' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind the dashboard's assets as ASSETS" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
unset ADMIN_TOKEN
if grep -rlF "$token_marker" "$work/apps/web/dist" "$work/apps/web/wrangler.jsonc" 2>/dev/null | head -1 | grep -q .; then
  echo "FAIL: the admin token reached the build output" >&2; grep -rlF "$token_marker" "$work/apps/web/dist" "$work/apps/web/wrangler.jsonc" | head -5 >&2; exit 1
fi
if grep -qF "$token_marker" "$scratch/build-app.log" "$scratch/deploy-dry-run.log"; then
  echo "FAIL: the admin token is in the lane's log" >&2; exit 1
fi
grep -q "ADMIN_TOKEN reach $repo-web-stage from the deploy lane" "$scratch/build-app.log" \
  || { echo "FAIL: the build did not hand the admin token on to the deploy lane's secrets step" >&2; grep "worker-secrets" "$scratch/build-app.log" >&2; exit 1; }
gz="$(sed -n 's/.*Total Upload: .* gzip: \([0-9.]*\) KiB.*/\1/p' "$scratch/deploy-dry-run.log" | head -1)"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 3072 else 1)" "${gz:-99999}" \
  || { echo "FAIL: the Worker is ${gz:-?} KiB gzipped — over Workers Free's 3 MiB" >&2; exit 1; }
echo "   the built config binds VISIBILITY_CACHE to the stage document's namespace id, AI to Workers AI and the assets; the dry run accepts it"
echo "   the admin token never reached the build output or the log, and goes to $repo-web-stage from the deploy lane; ${gz} KiB gzipped"


# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
echo "── wrangler dev over the built Worker: KV local, AI on the Workers AI stand-in"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
# The ONE change to the config the lane built with: the AI binding becomes a
# service binding to the Workers AI stand-in. Everything else is the stage
# render build-app wrote.
python3 - "$work/apps/web/wrangler.jsonc" "$work/apps/web/wrangler.e2e.jsonc" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
swapped, n = re.subn(r'"ai":\s*\{\s*"binding":\s*"AI"\s*\}',
                     '"services": [{ "binding": "AI", "service": "fake-workers-ai", "entrypoint": "FakeAI" }]', text)
if n != 1:
    sys.exit("FAIL: the built config does not bind Workers AI as `\"ai\": { \"binding\": \"AI\" }`")
open(sys.argv[2], "w").write(swapped)
PY
cp -r "$here/lib/fake-ai" "$scratch/fake-ai"
port=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
url="http://127.0.0.1:$port"
start_dev() { # LOG — one session over the same local store (--persist-to)
  (cd "$work/apps/web" && exec setsid pnpm exec wrangler dev -c wrangler.e2e.jsonc -c "$scratch/fake-ai/wrangler.jsonc" \
     --ip 127.0.0.1 --port "$port" --persist-to "$scratch/wrangler-state" \
     --show-interactive-dev-session=false) > "$1" 2>&1 < /dev/null &
  dev_pid=$!
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "$url/api/health" && return 0
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$1" >&2; exit 1; }
    sleep 1
  done
  echo "FAIL: wrangler dev never answered" >&2; tail -30 "$1" >&2; exit 1
}
stop_dev() {
  kill -TERM -- "-$dev_pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$dev_pid" 2>/dev/null || true
  dev_pid=""
  for _ in $(seq 1 20); do curl -s -o /dev/null "$url/" || return 0; sleep 0.5; done
}
start_dev "$scratch/dev.log"

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

# The checks both sessions share.
cat > "$scratch/routes.py" <<'PY'
import html, json, re, sys, urllib.error, urllib.request

base = sys.argv[1]
values = json.load(open(sys.argv[2]))
name, repo = values["productname"], values["reponame"]
problems = []
def bad(m): problems.append(m)

def req(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, data=data, method=method,
                               headers={"content-type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()

def jget(path):
    s, h, b = req("GET", path)
    try:
        return s, h, json.loads(b or b"null")
    except ValueError:
        return s, h, None

def done(summary):
    if problems:
        for p in problems:
            print(f"  ✕ {p}", file=sys.stderr)
        sys.exit(1)
    print(summary)
PY

echo "   ▸ every surface the product promises, enriched through the AI binding; writes refused"
python3 - "$url" "$values" "$scratch/routes.py" <<'PY' || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import sys
exec(open(sys.argv[3]).read())
MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
SIGNAL = "ai-input=yes, search=yes, ai-train=no"

# The dashboard: Static Assets, titled with the product's name.
s, h, b = req("GET", "/")
page = b.decode()
if s != 200 or 'id="root"' not in page:
    bad(f"/ answered {s} without the dashboard's mount point")
title = re.search(r"<title>(.*?)</title>", page, re.S)
if not title or not html.unescape(title.group(1)).startswith(f"{name} — "):
    bad(f"the dashboard's <title> is {title and title.group(1)!r}, not {name!r}'s")
if "agent-visibility" in page:
    bad("the dashboard's page still carries the baseline's slug")
s, h, b = req("GET", "/some/client/route")
if s != 200 or 'id="root"' not in b.decode():
    bad(f"an unknown path answered {s}, not the single-page app")

# Health first, on a cold store: read, and the model not called.
s, _, health = jget("/api/health")
if s != 200 or health != {"ok": True, "kv": True, "ai": True, "cached": False, "pages": 0}:
    bad(f"/api/health on a cold store answered {s} {health}")

# The site, as the dashboard reads it.
s, _, site = jget("/api/site")
if s != 200 or (site or {}).get("site", {}).get("name") != name or len((site or {}).get("surfaces") or []) < 5:
    bad(f"/api/site answered {s} {site}")
if (site or {}).get("webBotAuthEnabled") is not False:
    bad("Web Bot Auth is not off")

# llms.txt: the first surface read enriches the store.
s, h, b = req("GET", "/llms.txt")
text = b.decode()
if s != 200 or not (h.get("content-type") or "").startswith("text/plain"):
    bad(f"/llms.txt answered {s} {h.get('content-type')}")
if SIGNAL not in (h.get("content-signal") or ""):
    bad(f"/llms.txt's Content-Signal is {h.get('content-signal')!r}")
if not text.startswith(f"# {name}\n") or "## Pages" not in text:
    bad(f"/llms.txt does not open with the product's name: {text[:80]!r}")
slugs = re.findall(re.escape(base) + r"/([a-z0-9-]+)\.md\)", text)
if len(slugs) != 5:
    bad(f"/llms.txt links {len(slugs)} pages, not the five samples: {slugs}")

s, _, health = jget("/api/health")
if (health or {}).get("cached") is not True or (health or {}).get("pages") != 5:
    bad(f"/api/health after the first read: {health}")
s, _, listed = jget("/api/resources")
for r in (listed or {}).get("resources") or []:
    if r.get("model") != MODEL or f"Enriched by {MODEL}" not in (r.get("summary") or ""):
        bad(f"{r.get('slug')} was not enriched through the AI binding: {r.get('model')!r} {r.get('summary')!r}")
    if r.get("topics") != ["stand-in", "e2e"]:
        bad(f"{r.get('slug')}'s topics are {r.get('topics')}")

s, h, b = req("GET", "/llms-full.txt")
if s != 200 or "## Content" not in b.decode() or SIGNAL not in (h.get("content-signal") or ""):
    bad(f"/llms-full.txt answered {s}")
s, h, index = jget("/index.json")
if s != 200 or (index or {}).get("protocol") != "agent-visibility/0.1" or len((index or {}).get("pages") or []) != 5:
    bad(f"/index.json answered {s}, protocol {(index or {}).get('protocol')!r}")
if h.get("access-control-allow-origin") != "*":
    bad("/index.json carries no CORS header")
if slugs:
    s, h, b = req("GET", f"/{slugs[0]}.md")
    if s != 200 or not (h.get("content-type") or "").startswith("text/markdown") or "## Source" not in b.decode():
        bad(f"/{slugs[0]}.md answered {s} {h.get('content-type')}")
    if h.get("access-control-allow-origin") != "*" or SIGNAL not in (h.get("content-signal") or ""):
        bad(f"/{slugs[0]}.md lacks its CORS or Content-Signal header")
    s, h, ld = jget(f"/{slugs[0]}.jsonld")
    if s != 200 or (ld or {}).get("@type") != "Article" or "ld+json" not in (h.get("content-type") or ""):
        bad(f"/{slugs[0]}.jsonld answered {s} {ld}")
s, _, ld = jget("/jsonld")
if s != 200 or (ld or {}).get("@type") != "WebSite" or (ld or {}).get("name") != name:
    bad(f"/jsonld answered {s} {ld}")
s, h, b = req("GET", "/robots.txt")
robots = b.decode()
if s != 200 or "User-agent: GPTBot" not in robots or f"Content-Signal: {SIGNAL}" not in robots or "llms.txt" not in robots:
    bad(f"/robots.txt answered {s}: {robots[:120]!r}")
for path in ("/does-not-exist.md", "/.well-known/web-bot-auth/directory"):
    s, _, _ = req("GET", path)
    if s != 404:
        bad(f"{path} answered {s}, not 404")

# No token stored: every write refused, the store unchanged.
for path, body in (("/api/resources", {"slug": "x", "body": "hi"}), ("/api/refresh", None)):
    for auth in ({}, {"authorization": "Bearer anything"}):
        s, _, _ = req("POST", path, body, auth)
        if s != 401:
            bad(f"POST {path} {auth or 'without a token'} answered {s} with no ADMIN_TOKEN stored")
s, _, health = jget("/api/health")
if (health or {}).get("pages") != 5:
    bad(f"a refused write changed the store: {health}")

done("   /, its single-page app and its <title>; /api/health on a cold store; llms.txt, llms-full.txt, index.json\n"
     "   (agent-visibility/0.1), .md, .jsonld, /jsonld, robots.txt with Content-Signal and the product's name;\n"
     "   five pages enriched by the stand-in through the AI binding; Web Bot Auth off; every write refused")
PY
stop_dev

echo "── the same Worker with the admin token in .dev.vars (tooling/wire/worker-secrets.mjs --dev-vars)"
token="av_e2e_$(python3 -c 'import secrets;print(secrets.token_hex(16))')"
(cd "$work/apps/web" && ADMIN_TOKEN="$token" node "$work/tooling/wire/worker-secrets.mjs" --secret ADMIN_TOKEN --dev-vars .dev.vars) \
  > "$scratch/dev-vars.log" 2>&1 || { echo "FAIL: worker-secrets --dev-vars" >&2; cat "$scratch/dev-vars.log" >&2; exit 1; }
start_dev "$scratch/dev-token.log"
ADMIN_TOKEN="$token" python3 - "$url" "$values" "$scratch/routes.py" <<'PY' || { echo "FAIL: the writes; wrangler dev said:" >&2; tail -40 "$scratch/dev-token.log" >&2; exit 1; }
import os, sys
exec(open(sys.argv[3]).read())
token = os.environ["ADMIN_TOKEN"]
auth = {"authorization": f"Bearer {token}"}
MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast"

s, _, _ = req("POST", "/api/resources", {"slug": "changelog", "body": "hi"}, {"authorization": "Bearer wrong"})
if s != 401:
    bad(f"a wrong token answered {s}")
s, _, _ = req("POST", "/api/resources", {"slug": "Not A Slug!", "body": "hi"}, auth)
if s != 400:
    bad(f"an invalid slug answered {s}")

s, _, created = (lambda r: (r[0], r[1], json.loads(r[2] or b"null")))(req("POST", "/api/resources", {
    "slug": "changelog", "title": "Changelog", "url": "https://example.com/changelog",
    "body": "# Changelog\n\nVersion two adds workflow templates."}, auth))
if s != 201 or (created or {}).get("model") != MODEL or f"Enriched by {MODEL}" not in (created or {}).get("summary", ""):
    bad(f"posting a page answered {s} {created}")
s, h, b = req("GET", "/changelog.md")
if s != 200 or "Changelog" not in b.decode():
    bad(f"/changelog.md answered {s}")
if f"{base}/changelog.md" not in req("GET", "/llms.txt")[2].decode():
    bad("/llms.txt does not list the posted page")
s, _, health = jget("/api/health")
if (health or {}).get("pages") != 6:
    bad(f"after the post the store holds {health}")

# A page the model fails on: the fallback enriches it from its own text.
s, _, fb = (lambda r: (r[0], r[1], json.loads(r[2] or b"null")))(req("POST", "/api/resources", {
    "slug": "fallback", "title": "Fallback", "body": "FAIL_ENRICHMENT. The model cannot read this page."}, auth))
if s != 201 or (fb or {}).get("model") != f"{MODEL} (fallback)" or not (fb or {}).get("summary"):
    bad(f"a page the model failed on answered {s} {fb}")

s, _, cleared = jget("/api/health")
s, _, r = (lambda r: (r[0], r[1], json.loads(r[2] or b"null")))(req("POST", "/api/refresh", None, auth))
if s != 200 or (r or {}).get("ok") is not True:
    bad(f"/api/refresh answered {s} {r}")
s, _, health = jget("/api/health")
if (health or {}).get("cached") is not False:
    bad(f"/api/refresh did not clear the enriched store: {health}")
s, _, listed = jget("/api/resources")
if (listed or {}).get("count") != 7:
    bad(f"after the refresh the store re-enriches {(listed or {}).get('count')} pages, not the five samples and two posted")

done("   a wrong token and a bad slug refused; a page posted, enriched by the stand-in and on every surface;\n"
     "   a page the model failed on enriched by the fallback; the cache cleared and the store re-enriched")
PY
stop_dev

echo "e2e.test.sh: ok"
