# Gnirehtet relay source

This directory vendors the unmodified Rust relay from the official
[Genymobile/gnirehtet](https://github.com/Genymobile/gnirehtet) repository.

- Version: `v2.5.1`
- Commit: `67e1fafcc2cb8bbe0f04606ddb2b108dee9bebb6`
- License: Apache License 2.0 (see `LICENSE`)
- Local integration: the compiled executable is renamed to `gnirehtet-relay` and bundled in the
  macOS app. The upstream Rust source itself is unchanged.

Rebuild the bundled arm64 helper from this source with:

```sh
./scripts/build-gnirehtet-relay.sh
```
