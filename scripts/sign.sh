#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF' >&2
Usage:
  scripts/sign.sh <store-private-key.pem> [options]

Options:
  --index-path <path>         default: catalog/v1/index.json
  --publishers-path <path>    default: catalog/v1/publishers.json
  --skip-updated-at           keep existing updated_at values
EOF
}

KEY="${1:-}"
INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"
SKIP_UPDATED_AT=0

if [[ "$KEY" == "-h" || "$KEY" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$KEY" ]]; then
  usage
  exit 1
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;
    --skip-updated-at) SKIP_UPDATED_AT=1; shift 1;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -f "$KEY" ]] || die "Key not found: $KEY"
[[ -f "$INDEX_PATH" ]] || die "Missing: $INDEX_PATH"
[[ -f "$PUBLISHERS_PATH" ]] || die "Missing: $PUBLISHERS_PATH"

command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [[ "$SKIP_UPDATED_AT" -eq 0 ]]; then
  NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  python3 - "$INDEX_PATH" "$PUBLISHERS_PATH" "$NOW" <<'PY'
import json
import os
import sys

index_path, publishers_path, now = sys.argv[1:4]

for path in (index_path, publishers_path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    data["updated_at"] = now
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
PY
  echo "updated_at set to $NOW"
fi

openssl dgst -sha256 -sign "$KEY" -out "${INDEX_PATH}.sig" "$INDEX_PATH"
openssl dgst -sha256 -sign "$KEY" -out "${PUBLISHERS_PATH}.sig" "$PUBLISHERS_PATH"

echo "Signed:"
echo "  ${INDEX_PATH}.sig"
echo "  ${PUBLISHERS_PATH}.sig"
