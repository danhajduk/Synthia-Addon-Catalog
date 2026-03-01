#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/sign.sh keys/store_private.pem
#
# Actions:
#   - updates generated_at in catalog/v1/index.json and catalog/v1/publishers.json (UTC ISO8601)
#   - writes detached RSA-SHA256 signatures:
#       catalog/v1/index.json.sig
#       catalog/v1/publishers.json.sig

KEY="${1:-}"
if [[ -z "${KEY}" ]]; then
  echo "Usage: $0 <path-to-store-private-key.pem>" >&2
  exit 1
fi
[[ -f "$KEY" ]] || { echo "Key not found: $KEY" >&2; exit 1; }

INDEX="catalog/v1/index.json"
PUBS="catalog/v1/publishers.json"
[[ -f "$INDEX" ]] || { echo "Missing: $INDEX" >&2; exit 1; }
[[ -f "$PUBS" ]] || { echo "Missing: $PUBS" >&2; exit 1; }

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

bump_generated_at() {
  local file="$1"
  python3 - "$file" "$NOW" <<'PY'
import json,sys
path=sys.argv[1]
now=sys.argv[2]
with open(path,"r",encoding="utf-8") as f:
    data=json.load(f)
data["generated_at"]=now
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(data,f,indent=2,sort_keys=False)
    f.write("\n")
import os
os.replace(tmp,path)
PY
}

echo "Updating generated_at to $NOW"
bump_generated_at "$INDEX"
bump_generated_at "$PUBS"

echo "Signing..."
openssl dgst -sha256 -sign "$KEY" -out "${INDEX}.sig" "$INDEX"
openssl dgst -sha256 -sign "$KEY" -out "${PUBS}.sig" "$PUBS"

echo "Signed:"
echo " - ${INDEX}.sig"
echo " - ${PUBS}.sig"
