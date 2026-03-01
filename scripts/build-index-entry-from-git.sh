#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }

REPO_URL=""
REF="main"
MANIFEST_PATH="manifest.json"
EXPORT_PATH="store/export.json"
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --manifest-path) MANIFEST_PATH="$2"; shift 2;;
    --export-path) EXPORT_PATH="$2"; shift 2;;
    --out) OUT_FILE="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage:
  $0 --repo <git-url> [--ref <tag|branch>] [--manifest-path <path>] [--export-path <path>] [--out <file>]

What it does:
  - clones/fetches the repo into .store_sources/<addon_id or repo-name>/
  - checks out --ref
  - reads manifest.json to get addon_id/name/package_profile
  - reads store/export.json (if present) to get releases[]
  - emits a single addon entry JSON object ready to insert into catalog/v1/index.json

Examples:
  $0 --repo https://github.com/danhajduk/Synthia-MQTT.git --ref v0.1.2 --out mqtt-entry.json
  $0 --repo https://github.com/foo/bar.git --ref main
EOF
      exit 0
      ;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$REPO_URL" ]] || die "--repo required"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

mkdir -p ".store_sources"

# Use repo name as temp folder (later we can switch to addon_id after reading manifest)
REPO_BASENAME="$(basename "$REPO_URL")"
REPO_NAME="${REPO_BASENAME%.git}"
SRC_DIR=".store_sources/${REPO_NAME}"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "Cloning $REPO_URL -> $SRC_DIR"
  git clone --quiet "$REPO_URL" "$SRC_DIR"
else
  echo "Updating $SRC_DIR"
  git -C "$SRC_DIR" fetch --quiet --all --tags
fi

echo "Checking out ref: $REF"
git -C "$SRC_DIR" checkout --quiet "$REF" || die "Failed to checkout ref '$REF'"

MANF="${SRC_DIR}/${MANIFEST_PATH}"
EXPT="${SRC_DIR}/${EXPORT_PATH}"

[[ -f "$MANF" ]] || die "Missing manifest: $MANF"

python3 - "$MANF" "$EXPT" "$REPO_URL" "$OUT_FILE" <<'PY'
import json, sys, os

manf_path, export_path, repo_url, out_file = sys.argv[1:5]

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

manifest = load_json(manf_path)

# ---- Pull required fields from manifest ----
addon_id = manifest.get("id") or manifest.get("addon_id")
name = manifest.get("name") or addon_id
package_profile = manifest.get("package_profile")

if not addon_id:
    raise SystemExit(f"manifest missing id/addon_id: {manf_path}")
if not package_profile:
    raise SystemExit(f"manifest missing package_profile: {manf_path}")

# ---- Build base addon entry ----
addon_entry = {
    "addon_id": addon_id,
    "name": name,
    "repo": repo_url,
    "package_profile": package_profile,
    "releases": []
}

# ---- If export.json exists, use its releases and inject package_profile ----
if os.path.exists(export_path):
    export = load_json(export_path)
    rels = export.get("releases")
    if isinstance(rels, list):
        # Copy releases as-is, but ensure per-release package_profile exists
        out_rels = []
        for r in rels:
            if not isinstance(r, dict):
                continue
            rr = dict(r)
            rr.setdefault("package_profile", package_profile)
            out_rels.append(rr)
        addon_entry["releases"] = out_rels
    else:
        # export exists but no releases
        addon_entry["releases"] = []
else:
    # No export.json → no releases (still valid entry for index.json)
    addon_entry["releases"] = []

txt = json.dumps(addon_entry, indent=2)
txt += "\n"

if out_file:
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(txt)
else:
    print(txt, end="")
PY

if [[ -n "$OUT_FILE" ]]; then
  echo "Wrote addon entry to: $OUT_FILE"
else
  echo "Done."
fi