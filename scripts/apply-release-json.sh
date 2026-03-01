#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/apply-release-json.sh /path/to/release-output.json
#
# Defaults / overrides:
#   ADDON_ID=mqtt
#   INDEX_PATH=catalog/v1/index.json
#   PUBLISHERS_PATH=catalog/v1/publishers.json
#   STORE_PRIVATE_KEY=keys/store_private.pem
#   STORE_PUBLIC_KEY=keys/store_public.pem
#
# Example:
#   ADDON_ID=mqtt scripts/apply-release-json.sh ../Synthia-MQTT/release-output.json

REL_JSON="${1:-}"
if [[ -z "$REL_JSON" ]]; then
  echo "Usage: $0 <path-to-release-output.json>" >&2
  exit 1
fi
[[ -f "$REL_JSON" ]] || { echo "Release JSON not found: $REL_JSON" >&2; exit 1; }

ADDON_ID="${ADDON_ID:-mqtt}"
INDEX_PATH="${INDEX_PATH:-catalog/v1/index.json}"
PUBLISHERS_PATH="${PUBLISHERS_PATH:-catalog/v1/publishers.json}"
STORE_PRIVATE_KEY="${STORE_PRIVATE_KEY:-keys/store_private.pem}"
STORE_PUBLIC_KEY="${STORE_PUBLIC_KEY:-keys/store_public.pem}"

[[ -f "$INDEX_PATH" ]] || { echo "Missing: $INDEX_PATH" >&2; exit 1; }
[[ -f "$PUBLISHERS_PATH" ]] || { echo "Missing: $PUBLISHERS_PATH" >&2; exit 1; }

# Best-effort: ensure we are running from repo root (or fix relative paths)
if [[ ! -d "scripts" || ! -f "scripts/sign.sh" || ! -f "scripts/verify.sh" ]]; then
  echo "ERROR: run this from the Synthia-Addon-Catalog repo root (so ./scripts exists)." >&2
  exit 1
fi

python3 - "$REL_JSON" "$ADDON_ID" "$INDEX_PATH" "$PUBLISHERS_PATH" <<'PY'
import json, sys, os

rel_path, addon_id, index_path, pubs_path = sys.argv[1:5]

def die(msg: str, code: int = 1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

with open(rel_path, "r", encoding="utf-8") as f:
    rel = json.load(f)

# Required fields from release-output.json
version = rel.get("version")
artifact = rel.get("artifact") or {}
sha256 = rel.get("sha256")
publisher_key_id = rel.get("publisher_key_id")
signature_type = rel.get("signature_type")
release_sig = rel.get("release_sig")

missing = [k for k,v in {
    "version": version,
    "artifact.url": artifact.get("url"),
    "sha256": sha256,
    "publisher_key_id": publisher_key_id,
    "signature_type": signature_type,
    "release_sig": release_sig,
}.items() if not v]
if missing:
    die(f"release JSON missing fields: {', '.join(missing)}")

# Load catalog index
with open(index_path, "r", encoding="utf-8") as f:
    index = json.load(f)

# Load publishers
with open(pubs_path, "r", encoding="utf-8") as f:
    pubs = json.load(f)

# ---- Validate publisher_key_id exists in publishers.json ----
# We don't know your exact schema, so we check common patterns:
# - publishers: [{ "publisher_key_id": "...", ... }]
# - keys: { "<publisher_key_id>": {...} }
# - publishers: { "<publisher_key_id>": {...} }
found_pub = False

def scan(obj):
    # returns True if publisher_key_id found somewhere as a value or key in expected areas
    if isinstance(obj, dict):
        if publisher_key_id in obj:
            return True
        for k, v in obj.items():
            if k in ("publisher_key_id", "key_id", "id") and v == publisher_key_id:
                return True
            if scan(v):
                return True
    elif isinstance(obj, list):
        for it in obj:
            if scan(it):
                return True
    return False

found_pub = scan(pubs)
if not found_pub:
    die(f"publisher_key_id '{publisher_key_id}' not found in {pubs_path}. Add it there first.")

# ---- Update index.json ----
#
# We’ll support a few likely schemas:
# A) index["addons"] is a list of addon objects: { "addon_id": "...", "releases": [...] }
# B) index["addons"] is a dict keyed by addon_id: { "mqtt": { "releases": [...] } }
# C) index itself is a list of addon objects (less common)
#
def ensure_release(addon_obj):
    releases = addon_obj.get("releases")
    if releases is None:
        addon_obj["releases"] = []
        releases = addon_obj["releases"]
    if not isinstance(releases, list):
        die(f"Unexpected schema: releases for addon '{addon_id}' is not a list")

    new_rel = {
        "version": version.lstrip("v"),  # many catalogs store "0.1.1" instead of "v0.1.1"
        "core_min": None,
        "core_max": None,
        "artifact": {
            "type": artifact.get("type", "github_release_asset"),
            "url": artifact["url"],
        },
        "sha256": sha256,
        "publisher_key_id": publisher_key_id,
        "signature_type": signature_type,
        "release_sig": release_sig,
    }

    # If your catalog expects version WITH leading v, flip this by setting REL_KEEP_V=1 later if needed.
    # For now we normalize to "0.1.1" (v stripped), because many catalogs do that.
    # We’ll match either format when searching.
    v_norm = new_rel["version"]
    candidates = {v_norm, f"v{v_norm}"}

    for r in releases:
        rv = r.get("version")
        if isinstance(rv, str) and rv in candidates:
            # Update in place
            r.update(new_rel)
            return "updated"

    # Not found -> append
    releases.append(new_rel)
    return "added"

def find_addon_container(index_obj):
    # returns (addon_obj, status) where status indicates found/created
    # Case A: index["addons"] is list
    if isinstance(index_obj, dict) and isinstance(index_obj.get("addons"), list):
        for a in index_obj["addons"]:
            if isinstance(a, dict) and a.get("addon_id") == addon_id:
                return a, "found"
        # create addon entry if missing
        a = {"addon_id": addon_id, "releases": []}
        index_obj["addons"].append(a)
        return a, "created"

    # Case B: index["addons"] is dict keyed by addon_id
    if isinstance(index_obj, dict) and isinstance(index_obj.get("addons"), dict):
        addons = index_obj["addons"]
        if addon_id not in addons or not isinstance(addons[addon_id], dict):
            addons[addon_id] = {"addon_id": addon_id, "releases": []}
            return addons[addon_id], "created"
        return addons[addon_id], "found"

    # Case C: index itself is list
    if isinstance(index_obj, list):
        for a in index_obj:
            if isinstance(a, dict) and a.get("addon_id") == addon_id:
                return a, "found"
        a = {"addon_id": addon_id, "releases": []}
        index_obj.append(a)
        return a, "created"

    die("Unsupported index.json schema: can't locate addons container")

addon_obj, addon_status = find_addon_container(index)
change = ensure_release(addon_obj)

# Write back index.json with stable formatting
tmp = index_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(index, f, indent=2, sort_keys=False)
    f.write("\n")
os.replace(tmp, index_path)

print(f"OK: addon '{addon_id}' {addon_status}; release {change} for version {version}")
PY

echo "==> Signing catalog (updates generated_at + writes *.sig) ..."
./scripts/sign.sh "$STORE_PRIVATE_KEY"

echo "==> Verifying catalog signatures ..."
./scripts/verify.sh "$STORE_PUBLIC_KEY"

echo "==> Done."
echo "Updated:"
echo " - $INDEX_PATH"
echo " - $PUBLISHERS_PATH (validated publisher_key_id exists)"
echo " - ${INDEX_PATH}.sig"
echo " - ${PUBLISHERS_PATH}.sig"