#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  scripts/push-catalog.sh [options]

Options:
  --index-path <path>         default: catalog/v1/index.json
  --publishers-path <path>    default: catalog/v1/publishers.json
  --message <msg>             commit message (default: "Update catalog: <updated_at>")
  --remote <name>             git remote (default: origin)
  --branch <name>             git branch (default: current branch)
  --verify-key <path>         verify signatures before commit/push (optional)
  --no-push                   commit only, do not push
EOF
}

INDEX_PATH="catalog/v1/index.json"
PUBLISHERS_PATH="catalog/v1/publishers.json"
MESSAGE=""
REMOTE="origin"
BRANCH=""
VERIFY_KEY=""
DO_PUSH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index-path) INDEX_PATH="$2"; shift 2;;
    --publishers-path) PUBLISHERS_PATH="$2"; shift 2;;
    --message) MESSAGE="$2"; shift 2;;
    --remote) REMOTE="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --verify-key) VERIFY_KEY="$2"; shift 2;;
    --no-push) DO_PUSH=0; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

FILES=(
  "$INDEX_PATH"
  "${INDEX_PATH}.sig"
  "$PUBLISHERS_PATH"
  "${PUBLISHERS_PATH}.sig"
)

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || die "Missing required file: $f"
done

if [[ -n "$VERIFY_KEY" ]]; then
  [[ -f "$VERIFY_KEY" ]] || die "Verify key not found: $VERIFY_KEY"
  scripts/verify.sh "$VERIFY_KEY" --index-path "$INDEX_PATH" --publishers-path "$PUBLISHERS_PATH"
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi
[[ "$BRANCH" != "HEAD" ]] || die "Detached HEAD. Provide --branch explicitly."

if [[ -z "$MESSAGE" ]]; then
  UPDATED_AT="$(python3 - "$INDEX_PATH" <<'PY'
import json,sys
data=json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(data.get("updated_at", "unknown-time"))
PY
)"
  MESSAGE="Update catalog: ${UPDATED_AT}"
fi

git add -- "${FILES[@]}"

if git diff --cached --quiet -- "${FILES[@]}"; then
  echo "No catalog changes to commit."
  exit 0
fi

git commit -m "$MESSAGE"

if [[ "$DO_PUSH" -eq 1 ]]; then
  git push "$REMOTE" "$BRANCH"
  echo "Pushed $BRANCH to $REMOTE"
else
  echo "Committed only (no push)."
fi
