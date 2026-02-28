#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/verify.sh keys/store_public.pem
# Verifies:
#   catalog/v1/index.json.sig
#   catalog/v1/publishers.json.sig

PUB="${1:-}"
if [[ -z "${PUB}" ]]; then
  echo "Usage: $0 <path-to-store-public-key.pem>" >&2
  exit 1
fi

INDEX="catalog/v1/index.json"
PUBS="catalog/v1/publishers.json"

openssl dgst -sha256 -verify "$PUB" -signature "${INDEX}.sig" "$INDEX"
openssl dgst -sha256 -verify "$PUB" -signature "${PUBS}.sig" "$PUBS"

echo "OK: signatures valid"
