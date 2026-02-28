# Trust Model

Two gates:
1) Store operators sign the catalog (index.json + publishers.json). Core trusts only catalogs signed by known store public keys.
2) Publishers sign addon release artifacts. Core trusts only publisher keys listed (and enabled) in publishers.json.

Revocation:
- Store operator can disable a publisher key (or the whole publisher) in publishers.json.
- Store operator can remove/hide releases from index.json.

Key rotation:
- Add new store keypair and ship new public key to Core.
- Temporarily sign catalogs with both keys during migration (optional).
