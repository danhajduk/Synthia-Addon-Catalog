#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;
    -h|--help)
      cat <<'EOF'
Usage:
  scripts/init-catalog.sh [--index-path <path>] [--publishers-path <path>]

Creates catalog JSON files if they do not already exist:
  - index.json
  - publishers.json

If a file already exists, it is left unchanged.
EOF
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

command -v python3 >/dev/null 2>&1 || die "python3 is required"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - "$INDEX_PATH" "$PUBLISHERS_PATH" "$NOW" <<'PY'
import json
import os
import sys

index_path, publishers_path, now = sys.argv[1:4]

index_seed = {
    "schema_version": "1.0",
    "updated_at": now,
    "addons": []
}

publishers_seed = {
    "schema_version": "1.0",
    "updated_at": now,
    "publishers": []
}

def ensure_file(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if os.path.exists(path):
        return False
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    return True

created_index = ensure_file(index_path, index_seed)
created_publishers = ensure_file(publishers_path, publishers_seed)

if created_index:
    print(f"Created {index_path}")
else:
    print(f"Exists  {index_path}")

if created_publishers:
    print(f"Created {publishers_path}")
else:
    print(f"Exists  {publishers_path}")
PY
