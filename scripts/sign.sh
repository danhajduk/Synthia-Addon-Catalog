#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/sign.sh keys/store_private.pem
# Generates:
#   catalog/v1/index.json.sig
#   catalog/v1/publishers.json.sig

KEY="${1:-}"
if [[ -z "${KEY}" ]]; then
  echo "Usage: $0 <path-to-store-private-key.pem>" >&2
  exit 1
fi

INDEX="catalog/v1/index.json"
PUBS="catalog/v1/publishers.json"

openssl dgst -sha256 -sign "$KEY" -out "${INDEX}.sig" "$INDEX"
openssl dgst -sha256 -sign "$KEY" -out "${PUBS}.sig" "$PUBS"

echo "Signed:"
echo " - ${INDEX}.sig"
echo " - ${PUBS}.sig"
