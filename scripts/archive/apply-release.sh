#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
ADDON_ID="${ADDON_ID:-mqtt}"
INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"
REL_JSON="./release-output.json"
STORE_PRIVATE_KEY="${STORE_PRIVATE_KEY:-keys/store_private.pem}"
STORE_PUBLIC_KEY="${STORE_PUBLIC_KEY:-keys/store_public.pem}"
# ====================

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$REL_JSON" ]] || die "release-output.json not found in repo root."
[[ -f "$INDEX_PATH" ]] || die "Missing $INDEX_PATH"
[[ -f "$PUBLISHERS_PATH" ]] || die "Missing $PUBLISHERS_PATH"
[[ -f "$STORE_PRIVATE_KEY" ]] || die "Missing $STORE_PRIVATE_KEY"
[[ -f "$STORE_PUBLIC_KEY" ]] || die "Missing $STORE_PUBLIC_KEY"

command -v python3 >/dev/null || die "python3 required"

echo "==> Applying release-output.json to catalog for addon: $ADDON_ID"

python3 - "$REL_JSON" "$ADDON_ID" "$INDEX_PATH" "$PUBLISHERS_PATH" <<'PY'
import json, sys, os

rel_path, addon_id, index_path, pubs_path = sys.argv[1:5]

def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

with open(rel_path, "r", encoding="utf-8") as f:
    rel = json.load(f)

required = ["version", "artifact", "sha256", "publisher_key_id", "signature_type", "release_sig"]
for k in required:
    if k not in rel:
        die(f"Missing field in release JSON: {k}")

version = rel["version"]
artifact = rel["artifact"]
sha256 = rel["sha256"]
publisher_key_id = rel["publisher_key_id"]
signature_type = rel["signature_type"]
release_sig = rel["release_sig"]

if "url" not in artifact:
    die("artifact.url missing")

# Load index
with open(index_path, "r", encoding="utf-8") as f:
    index = json.load(f)

# Load publishers
with open(pubs_path, "r", encoding="utf-8") as f:
    pubs = json.load(f)

# Validate publisher_key_id exists
if publisher_key_id not in json.dumps(pubs):
    die(f"publisher_key_id '{publisher_key_id}' not found in publishers.json")

def find_addon_container(index_obj):
    if isinstance(index_obj.get("addons"), list):
        for a in index_obj["addons"]:
            if a.get("addon_id") == addon_id:
                return a
        new = {"addon_id": addon_id, "releases": []}
        index_obj["addons"].append(new)
        return new
    die("Unsupported index.json schema")

addon_obj = find_addon_container(index)

if "releases" not in addon_obj:
    addon_obj["releases"] = []

releases = addon_obj["releases"]

# Normalize version (strip leading v for storage)
norm_version = version.lstrip("v")

new_release = {
    "version": norm_version,
    "core_min": None,
    "core_max": None,
    "artifact": {
        "type": artifact.get("type", "github_release_asset"),
        "url": artifact["url"]
    },
    "sha256": sha256,
    "publisher_key_id": publisher_key_id,
    "signature_type": signature_type,
    "release_sig": release_sig
}

updated = False
for r in releases:
    if r.get("version") in {norm_version, version}:
        r.update(new_release)
        updated = True
        break

if not updated:
    releases.append(new_release)

tmp = index_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(index, f, indent=2)
    f.write("\n")

os.replace(tmp, index_path)

print(f"OK: Release applied for version {version}")
PY

echo "==> Signing catalog..."
./scripts/sign.sh "$STORE_PRIVATE_KEY"

echo "==> Verifying signatures..."
./scripts/verify.sh "$STORE_PUBLIC_KEY"

echo "==> Removing release-output.json"
rm -f "$REL_JSON"

echo "==> Done."