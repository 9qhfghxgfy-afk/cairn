#!/usr/bin/env bash
# Read-only probe of a server the user already runs, for the two P2 findings that need a real box
# rather than a mock. Nothing in this file is a claim about any server; it prints what YOUR server
# answers, and the code that consumes those answers is written from the output, not from a guess.
#
#   #19 — defaults are nested, not flat. A llama.cpp server answers /props with a
#         `default_generation_config` OBJECT carrying temperature / top_p / min_p / seed, while Ollama
#         keeps its defaults in /api/show (`parameters`, plus `model_info` for the context window).
#         Merging the top level of /props flat finds no defaults at all, so a picker built that way
#         shows blanks where the server has numbers. Probe 4 prints where each server really puts them.
#   #21 — which sampling keys an engine reads. The picker asserts min_p, top_k and seed; llama.cpp
#         reads them, a plain OpenAI-compatible endpoint does not, and a server that silently ignores
#         an unknown key is the worst case, because the UI would say "configured" about a knob the
#         engine never saw. Probe 6 sends one request with the keys and one with a key that does not
#         exist, and reports the status of each.
#
# Usage:  Scripts/probe-remote-config.sh <base-url> [model-name]
#   A LAN server:   Scripts/probe-remote-config.sh http://<host>:11434
#   Away from home: Scripts/probe-remote-config.sh https://your-host.your-vpn.ts.net
# The scheme is part of the argument, so a plain address on the LAN works and a public host can be
# given the encrypted scheme explicitly. Cairn enforces that rule in code; this script only talks to
# a box you named on the command line.
#
# Privacy: every probe is a read, or a completion request whose prompt is two words. Response BODIES
# are never printed — only status codes, key names, counts and the scalar defaults the server exposes.
# The base URL is not stored, logged, or written into the repo, and this file contains no address.
set -euo pipefail

BASE="${1:-}"
MODEL="${2:-}"
if [[ -z "$BASE" ]]; then
  echo "usage: Scripts/probe-remote-config.sh <base-url> [model-name]" >&2
  exit 2
fi
BASE="${BASE%/}"
SCHEME="${BASE%%://*}"
if [[ "$SCHEME" != "http" && "$SCHEME" != "https" ]]; then
  echo "the base-url must include a scheme, e.g. <host>:11434 with http:// or a host with https://" >&2
  exit 2
fi

HAS_PY=0
command -v python3 >/dev/null 2>&1 && HAS_PY=1

# Prints "<status> <bytes>" and leaves the body in $BODY.
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT
request() {  # request <method> <path> [json-body]
  local method="$1" path="$2" payload="${3:-}"
  local args=(-sS --max-time 20 -X "$method" -o "$BODY" -w '%{http_code}')
  [[ -n "$payload" ]] && args+=(-H 'Content-Type: application/json' --data "$payload")
  curl "${args[@]}" "$BASE$path" 2>/dev/null || echo "000"
}

# Top-level JSON keys, or the first scalar values of one object key.
keys() {  # keys [object-key]
  if [[ "$HAS_PY" -eq 0 ]]; then echo "(install python3 to decode)"; return; fi
  python3 - "$BODY" "${1:-}" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception as exc:
    print(f"(not JSON: {exc})"); raise SystemExit
target = sys.argv[2]
if target:
    data = data.get(target) if isinstance(data, dict) else None
    if data is None:
        print(f"(no {target!r} key)"); raise SystemExit
if not isinstance(data, dict):
    print(str(data)[:200]); raise SystemExit
for key in sorted(data):
    value = data[key]
    if isinstance(value, (int, float, bool, str)):
        print(f"  {key} = {str(value)[:60]}")
    else:
        print(f"  {key}: {type(value).__name__}")
PY
}

echo "probing $SCHEME://… (address not recorded)"

# 1 — Ollama identity.
status="$(request GET /api/version)"
echo "1. GET /api/version -> $status"
[[ "$status" == "200" ]] && keys version

# 2 — the models it serves, so a model name can be taken from here.
status="$(request GET /api/tags)"
echo "2. GET /api/tags -> $status"
if [[ "$status" == "200" && "$HAS_PY" -eq 1 ]]; then
  MODEL_LIST="$(python3 -c 'import json,sys;print(" ".join(m.get("name","") for m in json.load(open(sys.argv[1])).get("models",[])))' "$BODY")"
  echo "   models: ${MODEL_LIST:-(none)}"
  [[ -z "$MODEL" ]] && MODEL="${MODEL_LIST%% *}"
fi

# 3 — where Ollama keeps what a model accepts: `parameters` is the sampler allow-list, and the context
#     window lives under `model_info` rather than at the top level.
if [[ -n "$MODEL" ]]; then
  status="$(request POST /api/show "{\"name\":\"$MODEL\"}")"
  echo "3. POST /api/show ($MODEL) -> $status"
  if [[ "$status" == "200" ]]; then
    echo "   top level:"; keys
    echo "   parameters:"; keys parameters
    echo "   model_info:"; keys model_info
  fi
else
  echo "3. skipped — no model name"
fi

# 4 — llama.cpp's own capability document, including the nested defaults block.
status="$(request GET /props)"
echo "4. GET /props -> $status"
if [[ "$status" == "200" ]]; then
  echo "   top level:"; keys
  echo "   default_generation_config:"; keys default_generation_config
fi

# 5 — the OpenAI-compatible surface, which declares nothing about samplers.
status="$(request GET /v1/models)"
echo "5. GET /v1/models -> $status"

# 6 — does it accept the keys the picker asserts, and does it notice a key that does not exist? A 200
#     on the unknown key means the server ignores what it does not know, so a knob it drops fails
#     silently, and only a declared capability keeps the UI from lying about it.
PROMPT='{"role":"user","content":"Reply with one word."}'
if [[ -n "$MODEL" ]]; then
  options='"temperature":0.5,"top_k":20,"min_p":0.05,"seed":7,"repeat_penalty":1.1,"repeat_last_n":64,"num_predict":8'
  status="$(request POST /api/chat "{\"model\":\"$MODEL\",\"messages\":[$PROMPT],\"stream\":false,\"options\":{$options}}")"
  echo "6a. POST /api/chat with every knob -> $status"

  status="$(request POST /v1/chat/completions "{\"model\":\"$MODEL\",\"messages\":[$PROMPT],\"max_tokens\":8,\"temperature\":0.5,\"top_k\":20,\"min_p\":0.05,\"seed\":7,\"cairn_probe_unknown_key\":1}")"
  echo "6b. POST /v1/chat/completions with an unknown key -> $status"
  echo "    (a 200 on 6b means unknown keys are ignored silently)"
else
  echo "6. skipped — no model name"
fi

echo
echo "Record what this printed under docs/PARITY.md P2 #19 and #21, then wire the reader to it."
echo "Nothing above is stored. Re-run against another box to compare the two."
