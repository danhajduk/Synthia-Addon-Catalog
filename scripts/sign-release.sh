#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  scripts/sign-release.sh --private-key <ed25519-private.pem> (--artifact <addon.tgz> | --sha256 <hex>) [options]

Options:
  --out <file>            write base64 signature value to file
  --json                  print JSON snippet with sha256 + signature object
EOF
}

PRIVATE_KEY=""
ARTIFACT_PATH=""
SHA256_HEX=""
OUT_FILE=""
PRINT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --private-key) PRIVATE_KEY="$2"; shift 2;;
    --artifact) ARTIFACT_PATH="$2"; shift 2;;
    --sha256) SHA256_HEX="$2"; shift 2;;
    --out) OUT_FILE="$2"; shift 2;;
    --json) PRINT_JSON=1; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$PRIVATE_KEY" ]] || die "--private-key is required"
[[ -f "$PRIVATE_KEY" ]] || die "Private key not found: $PRIVATE_KEY"

if [[ -n "$ARTIFACT_PATH" && -n "$SHA256_HEX" ]]; then
  die "Pass only one of --artifact or --sha256"
fi
if [[ -z "$ARTIFACT_PATH" && -z "$SHA256_HEX" ]]; then
  die "Pass one of --artifact or --sha256"
fi
if [[ -n "$ARTIFACT_PATH" ]]; then
  [[ -f "$ARTIFACT_PATH" ]] || die "Artifact not found: $ARTIFACT_PATH"
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [[ -n "$ARTIFACT_PATH" ]]; then
  SHA256_HEX="$(openssl dgst -sha256 "$ARTIFACT_PATH" | awk '{print $2}')"
fi

SHA256_HEX="$(echo "$SHA256_HEX" | tr 'A-F' 'a-f')"
[[ "$SHA256_HEX" =~ ^[a-f0-9]{64}$ ]] || die "sha256 must be lowercase hex (64 chars)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$SHA256_HEX" "$TMP_DIR/digest.bin" <<'PY'
import pathlib
import sys

hex_value = sys.argv[1]
out_path = pathlib.Path(sys.argv[2])
out_path.write_bytes(bytes.fromhex(hex_value))
PY

openssl pkeyutl -sign -rawin -inkey "$PRIVATE_KEY" -in "$TMP_DIR/digest.bin" -out "$TMP_DIR/sig.bin"
SIGNATURE_B64="$(openssl base64 -A < "$TMP_DIR/sig.bin")"

if [[ -n "$OUT_FILE" ]]; then
  printf '%s\n' "$SIGNATURE_B64" > "$OUT_FILE"
fi

if [[ "$PRINT_JSON" -eq 1 ]]; then
  cat <<EOF
{
  "sha256": "$SHA256_HEX",
  "signature": {
    "type": "ed25519",
    "value": "$SIGNATURE_B64"
  }
}
EOF
else
  echo "sha256=$SHA256_HEX"
  echo "signature.type=ed25519"
  echo "signature.value=$SIGNATURE_B64"
fi
