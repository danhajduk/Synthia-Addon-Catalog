#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }

SNIPPET=""
PUBKEY=""
PUBLISHER_ID=""
PUBLISHER_NAME=""
KEY_ID=""
STORE_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snippet) SNIPPET="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    --publisher-id) PUBLISHER_ID="$2"; shift 2;;
    --publisher-name) PUBLISHER_NAME="$2"; shift 2;;
    --key-id) KEY_ID="$2"; shift 2;;
    --store-key) STORE_KEY="$2"; shift 2;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$SNIPPET" ]] || die "--snippet required"
[[ -n "$PUBKEY" ]] || die "--pubkey required"
[[ -n "$PUBLISHER_ID" ]] || die "--publisher-id required"
[[ -n "$PUBLISHER_NAME" ]] || die "--publisher-name required"
[[ -n "$KEY_ID" ]] || die "--key-id required"
[[ -n "$STORE_KEY" ]] || die "--store-key required"

[[ -f "$SNIPPET" ]] || die "Snippet not found: $SNIPPET"
[[ -f "$PUBKEY" ]] || die "Public key not found: $PUBKEY"
[[ -f "$STORE_KEY" ]] || die "Store private key not found: $STORE_KEY"

command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v openssl >/dev/null 2>&1 || die "openssl is required"

INDEX="catalog/v1/index.json"
PUBS="catalog/v1/publishers.json"

[[ -f "$INDEX" ]] || die "Missing: $INDEX"
[[ -f "$PUBS" ]] || die "Missing: $PUBS"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - "$SNIPPET" "$PUBKEY" "$PUBLISHER_ID" "$PUBLISHER_NAME" "$KEY_ID" "$NOW" "$INDEX" "$PUBS" <<'PY'
import json, sys, os

snippet_path, pubkey_path, publisher_id, publisher_name, key_id, now, index_path, pubs_path = sys.argv[1:]

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
    os.replace(tmp, path)

# Load inputs
snippet = load_json(snippet_path)
with open(pubkey_path, "r", encoding="utf-8") as f:
    pem = f.read().strip()
pem_json = pem.replace("\n", "\\n")

index = load_json(index_path)
pubs = load_json(pubs_path)

# Basic validation
addon_id = snippet.get("addon_id") or snippet.get("id")
if not addon_id:
    raise SystemExit("Snippet missing addon_id")
releases = snippet.get("releases")
if not isinstance(releases, list) or not releases:
    raise SystemExit("Snippet missing releases[]")

# 1) Upsert publisher + key into publishers.json
pubs.setdefault("publishers", [])
pub_entry = None
for p in pubs["publishers"]:
    if p.get("publisher_id") == publisher_id:
        pub_entry = p
        break

if pub_entry is None:
    pub_entry = {
        "publisher_id": publisher_id,
        "name": publisher_name,
        "status": "enabled",
        "keys": []
    }
    pubs["publishers"].append(pub_entry)

pub_entry["name"] = publisher_name
if pub_entry.get("status") not in ("enabled", "disabled"):
    pub_entry["status"] = "enabled"

keys = pub_entry.setdefault("keys", [])
key_entry = None
for k in keys:
    if k.get("key_id") == key_id:
        key_entry = k
        break

if key_entry is None:
    key_entry = {
        "key_id": key_id,
        "status": "enabled",
        "type": "rsa-sha256",
        "public_key_pem": pem_json
    }
    keys.append(key_entry)
else:
    key_entry["type"] = "rsa-sha256"
    key_entry["public_key_pem"] = pem_json
    if key_entry.get("status") not in ("enabled", "revoked"):
        key_entry["status"] = "enabled"

# 2) Upsert addon entry into index.json (merge releases by version)
index.setdefault("addons", [])
addon_entry = None
for a in index["addons"]:
    if a.get("addon_id") == addon_id:
        addon_entry = a
        break

# Normalize snippet: keep addon_id field
snippet_norm = dict(snippet)
snippet_norm["addon_id"] = addon_id

if addon_entry is None:
    # New addon
    index["addons"].append(snippet_norm)
else:
    # Merge top-level fields (prefer snippet’s values if present)
    for field in ("name", "description", "repo", "categories", "featured"):
        if field in snippet_norm and snippet_norm[field] not in (None, "", []):
            addon_entry[field] = snippet_norm[field]

    # Merge releases by version (replace if exists)
    addon_entry.setdefault("releases", [])
    existing = {r.get("version"): r for r in addon_entry["releases"] if isinstance(r, dict)}

    for r in snippet_norm.get("releases", []):
        v = r.get("version")
        if not v:
            continue
        existing[v] = r

    # Rebuild releases sorted by semver-ish (string sort is OK for now; core will pick latest compatible)
    addon_entry["releases"] = [existing[v] for v in sorted(existing.keys())]

# 3) Update generated_at
index["generated_at"] = now
pubs["generated_at"] = now

save_json(index_path, index)
save_json(pubs_path, pubs)

print(f"Imported addon '{addon_id}' and publisher key '{key_id}'")
PY

# Sign both files with store private key
openssl dgst -sha256 -sign "$STORE_KEY" -out "${INDEX}.sig" "$INDEX"
openssl dgst -sha256 -sign "$STORE_KEY" -out "${PUBS}.sig" "$PUBS"

echo "OK: imported + signed"
echo " - $INDEX (+ ${INDEX}.sig)"
echo " - $PUBS (+ ${PUBS}.sig)"
