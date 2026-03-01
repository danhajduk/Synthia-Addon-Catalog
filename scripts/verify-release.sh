#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-release.sh --public-key <ed25519-public.pem> (--artifact <addon.tgz> | --sha256 <hex>) (--signature-value <base64> | --signature-file <path>)
EOF
}

PUBLIC_KEY=""
ARTIFACT_PATH=""
SHA256_HEX=""
SIGNATURE_VALUE=""
SIGNATURE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-key) PUBLIC_KEY="$2"; shift 2;;
    --artifact) ARTIFACT_PATH="$2"; shift 2;;
    --sha256) SHA256_HEX="$2"; shift 2;;
    --signature-value) SIGNATURE_VALUE="$2"; shift 2;;
    --signature-file) SIGNATURE_FILE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$PUBLIC_KEY" ]] || die "--public-key is required"
[[ -f "$PUBLIC_KEY" ]] || die "Public key not found: $PUBLIC_KEY"

if [[ -n "$ARTIFACT_PATH" && -n "$SHA256_HEX" ]]; then
  die "Pass only one of --artifact or --sha256"
fi
if [[ -z "$ARTIFACT_PATH" && -z "$SHA256_HEX" ]]; then
  die "Pass one of --artifact or --sha256"
fi
if [[ -n "$ARTIFACT_PATH" ]]; then
  [[ -f "$ARTIFACT_PATH" ]] || die "Artifact not found: $ARTIFACT_PATH"
fi

if [[ -n "$SIGNATURE_VALUE" && -n "$SIGNATURE_FILE" ]]; then
  die "Pass only one of --signature-value or --signature-file"
fi
if [[ -z "$SIGNATURE_VALUE" && -z "$SIGNATURE_FILE" ]]; then
  die "Pass one of --signature-value or --signature-file"
fi
if [[ -n "$SIGNATURE_FILE" ]]; then
  [[ -f "$SIGNATURE_FILE" ]] || die "Signature file not found: $SIGNATURE_FILE"
  SIGNATURE_VALUE="$(tr -d '\r\n' < "$SIGNATURE_FILE")"
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

python3 - "$SHA256_HEX" "$SIGNATURE_VALUE" "$TMP_DIR/digest.bin" "$TMP_DIR/sig.bin" <<'PY'
import base64
import pathlib
import sys

sha256_hex = sys.argv[1]
sig_b64 = sys.argv[2]
digest_path = pathlib.Path(sys.argv[3])
sig_path = pathlib.Path(sys.argv[4])

digest_path.write_bytes(bytes.fromhex(sha256_hex))

try:
    sig_bytes = base64.b64decode(sig_b64, validate=True)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"ERROR: invalid base64 signature: {exc}") from exc

sig_path.write_bytes(sig_bytes)
PY

openssl pkeyutl -verify -rawin -pubin -inkey "$PUBLIC_KEY" -in "$TMP_DIR/digest.bin" -sigfile "$TMP_DIR/sig.bin" >/dev/null

echo "OK: release signature is valid"
