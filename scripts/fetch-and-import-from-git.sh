#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

REPO_URL=""
REF="main"
MANIFEST_REL_PATH="manifest.json"
SOURCE_DIR=""

INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"

CHANNEL="stable"
ARTIFACT_TYPE="github_release_asset"
ARTIFACT_URL=""
ARTIFACT_SHA256=""
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
KEY_NOT_AFTER=""

CORE_MIN=""
CORE_MAX=""
ADDON_NAME=""
ADDON_DESCRIPTION=""
VERSION_OVERRIDE=""

SIGN_KEY=""
VERIFY_KEY=""
SKIP_MANIFEST_SHA256=0
CLEAR_STORE_DIR=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --manifest-path) MANIFEST_REL_PATH="$2"; shift 2;;
    --source-dir) SOURCE_DIR="$2"; shift 2;;

    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;

    --channel) CHANNEL="$2"; shift 2;;
    --artifact-type) ARTIFACT_TYPE="$2"; shift 2;;
    --artifact-url) ARTIFACT_URL="$2"; shift 2;;
    --artifact-sha256) ARTIFACT_SHA256="$2"; shift 2;;
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

    --sign-key) SIGN_KEY="$2"; shift 2;;
    --verify-key) VERIFY_KEY="$2"; shift 2;;
    --no-manifest-sha256) SKIP_MANIFEST_SHA256=1; shift 1;;
    --keep-store) CLEAR_STORE_DIR=0; shift 1;;
    -h|--help)
      cat <<'EOF'
Usage:
  scripts/fetch-and-import-from-git.sh \
    --repo <git-url> \
    [--ref <branch|tag|sha>] \
    --artifact-url <url> \
    --artifact-sha256 <hex> \
    --signature-value <base64> \
    --publisher-key-id <publisher.id#key> \
    --publisher-public-key-file <path> \
    [options]

Core flow:
  1) clone/fetch repo into .store_sources/
  2) read manifest.json from that repo/ref
  3) upsert catalog/v1/index.json and catalog/v1/publishers.json
  4) optionally sign and verify catalog files

Common options:
  --channel <stable|beta|nightly>    default: stable
  --publisher-id <id>                default: manifest.publisher.id
  --publisher-display-name <name>    default: publisher-id
  --sign-key <store-private-key.pem> optional: write .sig files
  --verify-key <store-public-key.pem> optional: verify .sig files
  --keep-store                        do not clear fetched repo ./store/ after import
EOF
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

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
if [[ -n "$SIGN_KEY" ]]; then
  [[ -f "$SIGN_KEY" ]] || die "Sign key not found: $SIGN_KEY"
fi
if [[ -n "$VERIFY_KEY" ]]; then
  [[ -f "$VERIFY_KEY" ]] || die "Verify key not found: $VERIFY_KEY"
fi

command -v git >/dev/null 2>&1 || die "git is required"

if [[ -z "$SOURCE_DIR" ]]; then
  REPO_BASENAME="$(basename "$REPO_URL")"
  REPO_NAME="${REPO_BASENAME%.git}"
  SOURCE_DIR=".store_sources/${REPO_NAME}"
fi

mkdir -p "$(dirname "$SOURCE_DIR")"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  echo "Cloning $REPO_URL -> $SOURCE_DIR"
  git clone --quiet "$REPO_URL" "$SOURCE_DIR"
else
  echo "Updating $SOURCE_DIR"
  git -C "$SOURCE_DIR" remote set-url origin "$REPO_URL"
  git -C "$SOURCE_DIR" fetch --quiet --all --tags
fi

echo "Checking out ref: $REF"
git -C "$SOURCE_DIR" checkout --quiet "$REF" || die "Failed to checkout ref '$REF'"

MANIFEST_PATH="${SOURCE_DIR}/${MANIFEST_REL_PATH}"
[[ -f "$MANIFEST_PATH" ]] || die "Manifest not found: $MANIFEST_PATH"

scripts/init-catalog.sh --index-path "$INDEX_PATH" --publishers-path "$PUBLISHERS_PATH"

IMPORT_ARGS=(
  --manifest "$MANIFEST_PATH"
  --index-path "$INDEX_PATH"
  --publishers-path "$PUBLISHERS_PATH"
  --repo "$REPO_URL"
  --channel "$CHANNEL"
  --artifact-type "$ARTIFACT_TYPE"
  --artifact-url "$ARTIFACT_URL"
  --artifact-sha256 "$ARTIFACT_SHA256"
  --signature-value "$SIGNATURE_VALUE"
  --publisher-key-id "$PUBLISHER_KEY_ID"
  --publisher-key-status "$PUBLISHER_KEY_STATUS"
)

if [[ -n "$PUBLISHER_PUBLIC_KEY" ]]; then
  IMPORT_ARGS+=(--publisher-public-key "$PUBLISHER_PUBLIC_KEY")
fi
if [[ -n "$PUBLISHER_PUBLIC_KEY_FILE" ]]; then
  IMPORT_ARGS+=(--publisher-public-key-file "$PUBLISHER_PUBLIC_KEY_FILE")
fi
if [[ -n "$PUBLISHER_ID" ]]; then IMPORT_ARGS+=(--publisher-id "$PUBLISHER_ID"); fi
if [[ -n "$PUBLISHER_DISPLAY_NAME" ]]; then IMPORT_ARGS+=(--publisher-display-name "$PUBLISHER_DISPLAY_NAME"); fi
if [[ -n "$PUBLISHER_WEBSITE" ]]; then IMPORT_ARGS+=(--publisher-website "$PUBLISHER_WEBSITE"); fi
if [[ -n "$PUBLISHER_EMAIL" ]]; then IMPORT_ARGS+=(--publisher-email "$PUBLISHER_EMAIL"); fi

if [[ -n "$RELEASED_AT" ]]; then IMPORT_ARGS+=(--released-at "$RELEASED_AT"); fi
if [[ -n "$KEY_CREATED_AT" ]]; then IMPORT_ARGS+=(--key-created-at "$KEY_CREATED_AT"); fi
if [[ -n "$KEY_NOT_BEFORE" ]]; then IMPORT_ARGS+=(--key-not-before "$KEY_NOT_BEFORE"); fi
if [[ -n "$KEY_NOT_AFTER" ]]; then IMPORT_ARGS+=(--key-not-after "$KEY_NOT_AFTER"); fi

if [[ -n "$CORE_MIN" ]]; then IMPORT_ARGS+=(--core-min "$CORE_MIN"); fi
if [[ -n "$CORE_MAX" ]]; then IMPORT_ARGS+=(--core-max "$CORE_MAX"); fi
if [[ -n "$ADDON_NAME" ]]; then IMPORT_ARGS+=(--addon-name "$ADDON_NAME"); fi
if [[ -n "$ADDON_DESCRIPTION" ]]; then IMPORT_ARGS+=(--addon-description "$ADDON_DESCRIPTION"); fi
if [[ -n "$VERSION_OVERRIDE" ]]; then IMPORT_ARGS+=(--version "$VERSION_OVERRIDE"); fi
if [[ "$SKIP_MANIFEST_SHA256" -eq 1 ]]; then IMPORT_ARGS+=(--no-manifest-sha256); fi

scripts/import-addon-release.sh "${IMPORT_ARGS[@]}"

if [[ "$CLEAR_STORE_DIR" -eq 1 && -d "$SOURCE_DIR/store" ]]; then
  find "$SOURCE_DIR/store" -type f -delete
  find "$SOURCE_DIR/store" -depth -type d -empty -delete
  echo "Cleared $SOURCE_DIR/store"
fi

if [[ -n "$SIGN_KEY" ]]; then
  scripts/sign.sh "$SIGN_KEY" --index-path "$INDEX_PATH" --publishers-path "$PUBLISHERS_PATH"
fi

if [[ -n "$VERIFY_KEY" ]]; then
  scripts/verify.sh "$VERIFY_KEY" --index-path "$INDEX_PATH" --publishers-path "$PUBLISHERS_PATH"
fi

echo "Catalog update complete."
echo "  index: $INDEX_PATH"
echo "  publishers: $PUBLISHERS_PATH"
