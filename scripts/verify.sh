#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF' >&2
Usage:
  scripts/verify.sh <store-public-key.pem> [options]

Options:
  --index-path <path>         default: catalog/v1/index.json
  --publishers-path <path>    default: catalog/v1/publishers.json
EOF
}

PUBKEY="${1:-}"
INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"

if [[ "$PUBKEY" == "-h" || "$PUBKEY" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$PUBKEY" ]]; then
  usage
  exit 1
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -f "$PUBKEY" ]] || die "Public key not found: $PUBKEY"
[[ -f "$INDEX_PATH" ]] || die "Missing: $INDEX_PATH"
[[ -f "${INDEX_PATH}.sig" ]] || die "Missing: ${INDEX_PATH}.sig"
[[ -f "$PUBLISHERS_PATH" ]] || die "Missing: $PUBLISHERS_PATH"
[[ -f "${PUBLISHERS_PATH}.sig" ]] || die "Missing: ${PUBLISHERS_PATH}.sig"

command -v openssl >/dev/null 2>&1 || die "openssl is required"

openssl dgst -sha256 -verify "$PUBKEY" -signature "${INDEX_PATH}.sig" "$INDEX_PATH" >/dev/null
openssl dgst -sha256 -verify "$PUBKEY" -signature "${PUBLISHERS_PATH}.sig" "$PUBLISHERS_PATH" >/dev/null

echo "OK: signatures are valid"
