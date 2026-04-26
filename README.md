# Syntarie binary releases

Public binary mirror for the Syntarie blockchain. Source code lives in a separate (currently private) repository; this repo exists solely to host the release artifacts so that `curl | sh` style installs work for anyone.

## Latest testnet

Current testnet release tag: **`testnet-2026-04-26`**

Quick install (Linux / macOS):

```bash
curl -sSL https://github.com/syntarie/scc-releases/releases/download/testnet-2026-04-26/install.sh | sh
```

The script auto-detects your platform and downloads the matching `scc-tui` wallet binary. After install:

```bash
scc-tui keygen ~/my.key
scc-tui --testnet ~/my.key   # connects to public testnet, [TESTNET] header lights up
```

For the full testnet quickstart (RPC URLs, faucet usage, send/receive flows), see [docs/TESTNET.md](https://github.com/syntarie/scc-releases/blob/master/TESTNET.md).

## Available binaries (per release)

Each tag publishes:

- `scc-tui-<platform>` — TUI wallet (most users want this)
- `scc-node-<platform>` — node binary (validators, CLI)
- `SHA256SUMS-<platform>.txt` — checksums

Where `<platform>` is one of `linux-x86_64`, `darwin-arm64`, `darwin-x86_64`, `windows-x86_64`. Binaries are statically linked (no `librocksdb` runtime dependency).

## License

The binaries here are built from the private Syntarie source repo. Distribution license follows that repo's license terms (TBD — to be published when source goes public for v1).
