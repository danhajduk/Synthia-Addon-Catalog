#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

MANIFEST_PATH=""
INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"

REPO_URL=""
CHANNEL="stable"
ARTIFACT_TYPE="github_release_asset"
ARTIFACT_URL=""
ARTIFACT_SHA256=""
SIGNATURE_TYPE="ed25519"
SIGNATURE_VALUE=""

PUBLISHER_ID=""
PUBLISHER_DISPLAY_NAME=""
PUBLISHER_WEBSITE=""
PUBLISHER_EMAIL=""
PUBLISHER_KEY_ID=""
PUBLISHER_PUBLIC_KEY=""
PUBLISHER_PUBLIC_KEY_FILE=""
PUBLISHER_KEY_STATUS="active"

RELEASED_AT=""
KEY_CREATED_AT=""
KEY_NOT_BEFORE=""
KEY_NOT_AFTER="null"

CORE_MIN=""
CORE_MAX=""
ADDON_NAME=""
ADDON_DESCRIPTION=""
VERSION_OVERRIDE=""
INCLUDE_MANIFEST_SHA256=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST_PATH="$2"; shift 2;;
    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;

    --repo) REPO_URL="$2"; shift 2;;
    --channel) CHANNEL="$2"; shift 2;;
    --artifact-type) ARTIFACT_TYPE="$2"; shift 2;;
    --artifact-url) ARTIFACT_URL="$2"; shift 2;;
    --artifact-sha256) ARTIFACT_SHA256="$2"; shift 2;;
    --signature-type) SIGNATURE_TYPE="$2"; shift 2;;
    --signature-value) SIGNATURE_VALUE="$2"; shift 2;;

    --publisher-id) PUBLISHER_ID="$2"; shift 2;;
    --publisher-display-name) PUBLISHER_DISPLAY_NAME="$2"; shift 2;;
    --publisher-website) PUBLISHER_WEBSITE="$2"; shift 2;;
    --publisher-email) PUBLISHER_EMAIL="$2"; shift 2;;
    --publisher-key-id) PUBLISHER_KEY_ID="$2"; shift 2;;
    --publisher-public-key) PUBLISHER_PUBLIC_KEY="$2"; shift 2;;
    --publisher-public-key-file) PUBLISHER_PUBLIC_KEY_FILE="$2"; shift 2;;
    --publisher-key-status) PUBLISHER_KEY_STATUS="$2"; shift 2;;

    --released-at) RELEASED_AT="$2"; shift 2;;
    --key-created-at) KEY_CREATED_AT="$2"; shift 2;;
    --key-not-before) KEY_NOT_BEFORE="$2"; shift 2;;
    --key-not-after) KEY_NOT_AFTER="$2"; shift 2;;

    --core-min) CORE_MIN="$2"; shift 2;;
    --core-max) CORE_MAX="$2"; shift 2;;
    --addon-name) ADDON_NAME="$2"; shift 2;;
    --addon-description) ADDON_DESCRIPTION="$2"; shift 2;;
    --version) VERSION_OVERRIDE="$2"; shift 2;;
    --no-manifest-sha256) INCLUDE_MANIFEST_SHA256=0; shift 1;;
    -h|--help)
      cat <<'EOF'
Usage:
  scripts/import-addon-release.sh \
    --manifest <manifest.json> \
    --repo <repo-url> \
    --artifact-url <url> \
    --artifact-sha256 <hex> \
    --signature-value <base64> \
    --publisher-key-id <publisher.id#key> \
    --publisher-public-key-file <path> \
    [options]

Required:
  --manifest
  --repo
  --artifact-url
  --artifact-sha256
  --signature-value
  --publisher-key-id
  --publisher-public-key OR --publisher-public-key-file

Optional (commonly used):
  --publisher-id <id>              # defaults to manifest.publisher.id when present
  --publisher-display-name <name>  # defaults to publisher-id
  --channel <stable|beta|nightly>  # default: stable
  --released-at <ISO8601 UTC>      # default: now
  --core-min <semver>              # default: manifest.compatibility.core_min_version
  --core-max <semver|null>         # default: manifest.compatibility.core_max_version
  --index-path <path>              # default: catalog/v1/index.json
  --publishers-path <path>         # default: catalog/v1/publishers.json
EOF
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$MANIFEST_PATH" ]] || die "--manifest is required"
[[ -f "$MANIFEST_PATH" ]] || die "Manifest not found: $MANIFEST_PATH"
[[ -n "$REPO_URL" ]] || die "--repo is required"
[[ -n "$ARTIFACT_URL" ]] || die "--artifact-url is required"
[[ -n "$ARTIFACT_SHA256" ]] || die "--artifact-sha256 is required"
[[ -n "$SIGNATURE_VALUE" ]] || die "--signature-value is required"
[[ -n "$PUBLISHER_KEY_ID" ]] || die "--publisher-key-id is required"

if [[ -z "$PUBLISHER_PUBLIC_KEY" && -z "$PUBLISHER_PUBLIC_KEY_FILE" ]]; then
  die "Provide --publisher-public-key or --publisher-public-key-file"
fi
if [[ -n "$PUBLISHER_PUBLIC_KEY_FILE" ]]; then
  [[ -f "$PUBLISHER_PUBLIC_KEY_FILE" ]] || die "Publisher public key file not found: $PUBLISHER_PUBLIC_KEY_FILE"
fi

[[ -f "$INDEX_PATH" ]] || die "Index not found: $INDEX_PATH (run scripts/init-catalog.sh first)"
[[ -f "$PUBLISHERS_PATH" ]] || die "Publishers not found: $PUBLISHERS_PATH (run scripts/init-catalog.sh first)"

case "$CHANNEL" in
  stable|beta|nightly) ;;
  *) die "--channel must be one of: stable, beta, nightly" ;;
esac

case "$PUBLISHER_KEY_STATUS" in
  active|deprecated|revoked) ;;
  *) die "--publisher-key-status must be one of: active, deprecated, revoked" ;;
esac

command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [[ -n "$PUBLISHER_PUBLIC_KEY_FILE" ]]; then
  RAW_KEY="$(tr -d '\r' < "$PUBLISHER_PUBLIC_KEY_FILE")"
  if grep -q "BEGIN PUBLIC KEY" <<<"$RAW_KEY"; then
    PUBLISHER_PUBLIC_KEY="$(awk '
      /-----BEGIN PUBLIC KEY-----/ {in_key=1; next}
      /-----END PUBLIC KEY-----/ {in_key=0}
      in_key {gsub(/[[:space:]]/, "", $0); printf "%s", $0}
    ' <<<"$RAW_KEY")"
  else
    PUBLISHER_PUBLIC_KEY="$(tr -d '[:space:]' <<<"$RAW_KEY")"
  fi
fi

python3 - \
  "$MANIFEST_PATH" "$INDEX_PATH" "$PUBLISHERS_PATH" \
  "$REPO_URL" "$CHANNEL" "$ARTIFACT_TYPE" "$ARTIFACT_URL" "$ARTIFACT_SHA256" \
  "$SIGNATURE_TYPE" "$SIGNATURE_VALUE" "$PUBLISHER_ID" "$PUBLISHER_DISPLAY_NAME" \
  "$PUBLISHER_WEBSITE" "$PUBLISHER_EMAIL" "$PUBLISHER_KEY_ID" "$PUBLISHER_PUBLIC_KEY" \
  "$PUBLISHER_KEY_STATUS" "$RELEASED_AT" "$KEY_CREATED_AT" "$KEY_NOT_BEFORE" "$KEY_NOT_AFTER" \
  "$CORE_MIN" "$CORE_MAX" "$ADDON_NAME" "$ADDON_DESCRIPTION" "$VERSION_OVERRIDE" "$INCLUDE_MANIFEST_SHA256" <<'PY'
import base64
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

(
    manifest_path,
    index_path,
    publishers_path,
    repo_url,
    channel,
    artifact_type,
    artifact_url,
    artifact_sha256,
    signature_type,
    signature_value,
    publisher_id_in,
    publisher_display_name_in,
    publisher_website_in,
    publisher_email_in,
    publisher_key_id,
    publisher_public_key,
    publisher_key_status,
    released_at_in,
    key_created_at_in,
    key_not_before_in,
    key_not_after_in,
    core_min_in,
    core_max_in,
    addon_name_in,
    addon_description_in,
    version_override,
    include_manifest_sha256,
) = sys.argv[1:29]

SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+][0-9A-Za-z.-]+)?$")
ADDON_ID_RE = re.compile(r"^[a-z0-9_]+$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")

def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path, data):
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)

def require(condition, message):
    if not condition:
        raise SystemExit(f"ERROR: {message}")

def norm_or_none(value):
    text = value.strip()
    if text == "" or text.lower() == "null":
        return None
    return text

def semver_key(version):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+](.*))?$", version)
    if not m:
        return (-1, -1, -1, -1, version)
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    extra = m.group(4)
    stable_rank = 1 if extra is None else 0
    return (major, minor, patch, stable_rank, extra or "")

manifest_raw = open(manifest_path, "rb").read()
manifest = json.loads(manifest_raw.decode("utf-8"))

addon_id = manifest.get("id")
require(isinstance(addon_id, str) and ADDON_ID_RE.match(addon_id), "manifest.id must match ^[a-z0-9_]+$")

manifest_name = manifest.get("name")
require(isinstance(manifest_name, str) and manifest_name.strip(), "manifest.name is required")

manifest_version = manifest.get("version")
require(isinstance(manifest_version, str) and SEMVER_RE.match(manifest_version), "manifest.version must be semver")

manifest_package_profile = manifest.get("package_profile")
if manifest_package_profile is None and isinstance(manifest.get("release"), dict):
    # Backward-compatible fallback for older manifests that nested package profile.
    manifest_package_profile = manifest["release"].get("package_profile")
if manifest_package_profile is not None:
    require(isinstance(manifest_package_profile, str) and manifest_package_profile.strip(), "manifest.package_profile must be a non-empty string")

compat = manifest.get("compatibility") or {}
manifest_core_min = compat.get("core_min_version")
manifest_core_max = compat.get("core_max_version")
require(isinstance(manifest_core_min, str) and SEMVER_RE.match(manifest_core_min), "manifest.compatibility.core_min_version is required")
if manifest_core_max is not None:
    require(isinstance(manifest_core_max, str) and SEMVER_RE.match(manifest_core_max), "manifest.compatibility.core_max_version must be semver or null")

publisher_from_manifest = None
publisher_obj = manifest.get("publisher")
if isinstance(publisher_obj, dict):
    pub_id = publisher_obj.get("id")
    if isinstance(pub_id, str) and pub_id.strip():
        publisher_from_manifest = pub_id.strip()

publisher_id = (publisher_id_in.strip() if publisher_id_in.strip() else (publisher_from_manifest or ""))
require(publisher_id != "", "publisher id is required (pass --publisher-id or include manifest.publisher.id)")

publisher_display_name = publisher_display_name_in.strip() or publisher_id
publisher_website = norm_or_none(publisher_website_in)
publisher_email = norm_or_none(publisher_email_in)

version = version_override.strip() if version_override.strip() else manifest_version
require(SEMVER_RE.match(version), "release version must be semver")
core_min = core_min_in.strip() if core_min_in.strip() else manifest_core_min
core_max = norm_or_none(core_max_in) if core_max_in.strip() else manifest_core_max
require(SEMVER_RE.match(core_min), "core_compat.min must be semver")
if core_max is not None:
    require(SEMVER_RE.match(core_max), "core_compat.max must be semver or null")

addon_name = addon_name_in.strip() if addon_name_in.strip() else manifest_name
addon_description = norm_or_none(addon_description_in) if addon_description_in.strip() else manifest.get("description")

artifact_sha256 = artifact_sha256.strip()
require(SHA256_RE.match(artifact_sha256), "artifact sha256 must be lowercase hex (64 chars)")

require(signature_type == "ed25519", "signature.type must be ed25519")
try:
    base64.b64decode(signature_value, validate=True)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"ERROR: signature-value must be valid base64: {exc}") from exc

for time_label, value in (
    ("released-at", released_at_in.strip() or now_utc()),
    ("key-created-at", key_created_at_in.strip() or now_utc()),
    ("key-not-before", key_not_before_in.strip() or (key_created_at_in.strip() or now_utc())),
):
    require(value.endswith("Z"), f"{time_label} should be UTC ISO8601 ending with Z")

released_at = released_at_in.strip() or now_utc()
key_created_at = key_created_at_in.strip() or now_utc()
key_not_before = key_not_before_in.strip() or key_created_at
key_not_after = norm_or_none(key_not_after_in)

manifest_sha256 = hashlib.sha256(manifest_raw).hexdigest()

index = load_json(index_path)
publishers = load_json(publishers_path)

require(index.get("schema_version") == "1.0", "index.json schema_version must be 1.0")
require(publishers.get("schema_version") == "1.0", "publishers.json schema_version must be 1.0")

index.setdefault("addons", [])
publishers.setdefault("publishers", [])

publisher = next((p for p in publishers["publishers"] if p.get("publisher_id") == publisher_id), None)
if publisher is None:
    publisher = {
        "publisher_id": publisher_id,
        "display_name": publisher_display_name,
        "website": publisher_website,
        "contact": {"email": publisher_email},
        "keys": []
    }
    publishers["publishers"].append(publisher)
else:
    publisher["display_name"] = publisher_display_name
    if "website" not in publisher:
        publisher["website"] = None
    if "contact" not in publisher or not isinstance(publisher["contact"], dict):
        publisher["contact"] = {"email": None}
    if "email" not in publisher["contact"]:
        publisher["contact"]["email"] = None
    if publisher_website_in.strip():
        publisher["website"] = publisher_website
    if publisher_email_in.strip():
        publisher["contact"]["email"] = publisher_email
    publisher.setdefault("keys", [])

key = next((k for k in publisher["keys"] if k.get("key_id") == publisher_key_id), None)
if key is None:
    key = {
        "key_id": publisher_key_id,
        "status": publisher_key_status,
        "algorithm": "ed25519",
        "public_key": publisher_public_key,
        "created_at": key_created_at,
        "not_before": key_not_before,
        "not_after": key_not_after,
        "revoked_at": None,
        "revocation_reason": None
    }
    publisher["keys"].append(key)
else:
    key["status"] = publisher_key_status
    key["algorithm"] = "ed25519"
    key["public_key"] = publisher_public_key
    key["created_at"] = key_created_at
    key["not_before"] = key_not_before
    key["not_after"] = key_not_after
    key.setdefault("revoked_at", None)
    key.setdefault("revocation_reason", None)

addon = next((a for a in index["addons"] if a.get("addon_id") == addon_id), None)
if addon is None:
    addon = {
        "addon_id": addon_id,
        "name": addon_name,
        "description": addon_description,
        "repo": repo_url,
        "publisher_id": publisher_id,
        "channels": {"stable": [], "beta": [], "nightly": []}
    }
    if manifest_package_profile is not None:
        addon["package_profile"] = manifest_package_profile
    index["addons"].append(addon)
else:
    addon["name"] = addon_name
    addon["description"] = addon_description
    addon["repo"] = repo_url
    addon["publisher_id"] = publisher_id
    if manifest_package_profile is not None:
        addon["package_profile"] = manifest_package_profile
    channels = addon.get("channels")
    if not isinstance(channels, dict):
        channels = {}
        addon["channels"] = channels
    for channel_name in ("stable", "beta", "nightly"):
        if channel_name not in channels or not isinstance(channels[channel_name], list):
            channels[channel_name] = []

release_obj = {
    "version": version,
    "core_compat": {"min": core_min, "max": core_max},
    "artifact": {"type": artifact_type, "url": artifact_url},
    "sha256": artifact_sha256,
    "publisher_key_id": publisher_key_id,
    "signature": {"type": "ed25519", "value": signature_value},
    "released_at": released_at
}

if include_manifest_sha256 == "1":
    release_obj["manifest_sha256"] = manifest_sha256

target_releases = addon["channels"][channel]
replaced = False
for i, release in enumerate(target_releases):
    if release.get("version") == version:
        target_releases[i] = release_obj
        replaced = True
        break
if not replaced:
    target_releases.append(release_obj)

target_releases.sort(key=lambda r: semver_key(str(r.get("version", ""))), reverse=True)
index["addons"].sort(key=lambda a: str(a.get("addon_id", "")))
publishers["publishers"].sort(key=lambda p: str(p.get("publisher_id", "")))
for p in publishers["publishers"]:
    if isinstance(p.get("keys"), list):
        p["keys"].sort(key=lambda k: str(k.get("key_id", "")))

updated_at = now_utc()
index["updated_at"] = updated_at
publishers["updated_at"] = updated_at

save_json(index_path, index)
save_json(publishers_path, publishers)

print("Imported release:")
print(f"  addon_id={addon_id}")
print(f"  version={version}")
print(f"  channel={channel}")
print(f"  publisher_id={publisher_id}")
print(f"  publisher_key_id={publisher_key_id}")
PY
