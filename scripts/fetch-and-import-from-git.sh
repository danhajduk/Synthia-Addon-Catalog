#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }

REPO_URL=""
REF="main"
ADDON_ID=""
EXPORT_PATH="store/export.json"
PUBKEY_PATH="keys/publisher_public.pem"
PUBLISHER_ID=""
PUBLISHER_NAME=""
KEY_ID=""
STORE_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --addon-id) ADDON_ID="$2"; shift 2;;
    --export-path) EXPORT_PATH="$2"; shift 2;;
    --pubkey-path) PUBKEY_PATH="$2"; shift 2;;
    --publisher-id) PUBLISHER_ID="$2"; shift 2;;
    --publisher-name) PUBLISHER_NAME="$2"; shift 2;;
    --key-id) KEY_ID="$2"; shift 2;;
    --store-key) STORE_KEY="$2"; shift 2;;
    -h|--help)
      echo "Usage:"
      echo "  $0 --repo <git-url> --addon-id <id> --publisher-id <pid> --publisher-name <name> --key-id <kid> --store-key <store_private.pem> [--ref <main|tag>]"
      exit 0
      ;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$REPO_URL" ]] || die "--repo required"
[[ -n "$ADDON_ID" ]] || die "--addon-id required"
[[ -n "$PUBLISHER_ID" ]] || die "--publisher-id required"
[[ -n "$PUBLISHER_NAME" ]] || die "--publisher-name required"
[[ -n "$KEY_ID" ]] || die "--key-id required"
[[ -n "$STORE_KEY" ]] || die "--store-key required"
[[ -f "$STORE_KEY" ]] || die "Store private key not found: $STORE_KEY"

command -v git >/dev/null 2>&1 || die "git is required"

ROOT_DIR="$(pwd)"
SRC_DIR=".store_sources/${ADDON_ID}"
mkdir -p ".store_sources"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "Cloning $REPO_URL -> $SRC_DIR"
  git clone --quiet "$REPO_URL" "$SRC_DIR"
else
  echo "Updating $SRC_DIR"
  git -C "$SRC_DIR" fetch --quiet --all --tags
fi

echo "Checking out ref: $REF"
git -C "$SRC_DIR" checkout --quiet "$REF" || die "Failed to checkout ref '$REF'"

SNIP="${SRC_DIR}/${EXPORT_PATH}"
PUBK="${SRC_DIR}/${PUBKEY_PATH}"

[[ -f "$SNIP" ]] || die "Missing export snippet in repo: $SNIP (expected committed file)"
[[ -f "$PUBK" ]] || die "Missing publisher public key in repo: $PUBK (expected committed file)"

echo "Importing from:"
echo " - snippet: $SNIP"
echo " - pubkey : $PUBK"

# Call the import script (must already exist)
[[ -x "scripts/import-addon-release.sh" ]] || die "Missing or not executable: scripts/import-addon-release.sh"

scripts/import-addon-release.sh \
  --snippet "$SNIP" \
  --pubkey "$PUBK" \
  --publisher-id "$PUBLISHER_ID" \
  --publisher-name "$PUBLISHER_NAME" \
  --key-id "$KEY_ID" \
  --store-key "$STORE_KEY"

echo
echo "DONE. Now commit the catalog changes:"
echo "  git add catalog/v1/index.json catalog/v1/index.json.sig catalog/v1/publishers.json catalog/v1/publishers.json.sig"
echo "  git commit -m \"Import ${ADDON_ID} from ${REPO_URL} (${REF})\""
echo "  git push"
