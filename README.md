# Synthia Addon Catalog

This repository is the signed source of truth for which addons and releases are approved.
It contains no addon code. Addons live in separate repositories and are fetched on demand.

Core flow:
1) Core downloads `catalog/v1/index.json` (+ signature) and verifies it using the store public key.
2) Core downloads `catalog/v1/publishers.json` (+ signature) and verifies it.
3) When installing an addon release, Core verifies:
   - SHA256 of the artifact
   - Release signature using the publisher key listed in publishers.json

Files:
- catalog/v1/index.json        Approved addons + releases + artifact pointers
- catalog/v1/index.json.sig    Signature of index.json
- catalog/v1/publishers.json   Approved publishers + public keys
- catalog/v1/publishers.json.sig Signature of publishers.json

Tooling:
- scripts/init-catalog.sh      Creates `index.json` / `publishers.json` if missing
- scripts/import-addon-release.sh  Imports one release from a `manifest.json` + release metadata
- scripts/fetch-and-import-from-git.sh  Fetches addon repo, reads manifest, then imports release
- scripts/sign-release.sh       Creates publisher release signature (ed25519 over artifact sha256 bytes)
- scripts/verify-release.sh     Verifies publisher release signature
- scripts/sign.sh               Signs index/publishers with store private key
- scripts/verify.sh             Verifies catalog signatures with store public key

NOTE: Keep private signing keys out of git.
