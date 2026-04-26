# Syntarie Testnet — Public Access Guide

Last updated: 2026-04-26

The Syntarie testnet runs on three Hetzner Cloud validators in Falkenstein/Helsinki/Nuremberg. RPC is publicly reachable; faucet endpoint is live; chain advances ~1-2 blocks/sec.

This document is for anyone who wants to connect to the testnet, get test SCC, and send transactions.

## Network identity

- **Chain seed**: `syntarie-staging-testnet`
- **Sync policy**: `strict-quorum` (3-of-3 producers required)
- **Block cadence**: ~1-2 blocks/sec under normal load
- **Token symbol**: SCC

## Public RPC endpoints

Three validators expose HTTP RPC on port 19100. Any of these works for read queries; **the faucet endpoint is on nbg-1 only** (see Faucet section).

| Node | Region | Public RPC URL |
|---|---|---|
| nbg-1 | Nuremberg, DE | `http://91.99.102.167:19100` |
| hel-1 | Helsinki, FI | `http://62.238.14.215:19100` |
| nbg-3 | Falkenstein, DE | `http://178.104.121.69:19100` |

[INFERRED] Hostnames at the SSH layer are `syntarie-nbg-1` / `syntarie-hel-1` / `syntarie-nbg-3` but those are operator aliases; external clients use the raw IPs above.

## Bearer token (write endpoints)

Write routes (`/faucet`, `/tx`, `/submit_tx`, `/intent/*` writers) require a bearer token. The testnet token is **public** — there's no security expectation on a public testnet:

```
Authorization: Bearer UIBsO3tav34ABrYq0sSbUcNXlAGMy5DEuRvZskzFLGkMOoyK
```

Read routes (`/status`, `/account`, `/fee/*`, etc.) need no auth.

## Quick health check

```bash
curl http://91.99.102.167:19100/status
```

You should see something like:

```json
{
  "node_id": "d584828f...",
  "height": 154213,
  "finalized_height": 154208,
  "peer_count": 2,
  "configured_peer_count": 2,
  "operational_state": "healthy",
  "sync_phase": "live",
  ...
}
```

If `operational_state` is `healthy` and `sync_phase` is `live`, the chain is producing.

## Get test SCC (faucet)

The faucet drops 100 SCC per request, rate-limited per IP (60s cooldown) and per address (300s cooldown).

```bash
curl -X POST http://91.99.102.167:19100/faucet \
  -H 'Authorization: Bearer UIBsO3tav34ABrYq0sSbUcNXlAGMy5DEuRvZskzFLGkMOoyK' \
  -H 'Content-Type: application/json' \
  -d '{"to":"<your-64-char-hex-address>"}'
```

Response:

```json
{"tx_hash":"64ad3d8fcfa52df4...","amount":100}
```

Wait one block (~1 sec), then verify the credit:

```bash
curl "http://91.99.102.167:19100/account?address=<your-address>"
```

Expected: `"balance":100`. (Assuming the address was previously empty.)

**Faucet is on nbg-1 only.** Hitting `/faucet` on hel-1 or nbg-3 will return `{"error":"Faucet disabled"}`.

## Generate an address

You need a `scc-node` binary to generate keys. Two paths:

**Option A — one-line install (recommended)**:

```bash
curl -sSL https://github.com/syntarie/scc-releases/releases/download/testnet-2026-04-26/install.sh | sh
```

The script auto-detects your platform (Linux / macOS, x86_64 / arm64), downloads the matching `scc-tui` binary into `~/.local/bin`, and prints the quickstart. Set `SCC_BINS="scc-tui scc-node"` to install both. Set `SCC_INSTALL_DIR=/usr/local/bin` (with sudo) to install system-wide.

The binaries live in a separate **public** repo (`syntarie/scc-releases`) — the source repo is private. Only the build artifacts are public so anyone can install + use the testnet.

**Option A2 — direct download** (if you'd rather not pipe to sh):

The release includes platform-suffixed binaries for `scc-node` (the protocol binary, used by validators and CLI clients) and `scc-tui` (the wallet UI). Most users only need `scc-tui`.

| Platform | Wallet binary URL |
|---|---|
| Linux x86_64 | `.../testnet-2026-04-26/scc-tui-linux-x86_64` |
| macOS Apple Silicon (M1/M2/M3) | `.../testnet-2026-04-26/scc-tui-darwin-arm64` |
| Windows x86_64 | `.../testnet-2026-04-26/scc-tui-windows-x86_64.exe` |

(Replace `scc-tui-` with `scc-node-` for the protocol/CLI binary. Intel Mac is built from source — see Option B.)

```bash
# Linux example:
curl -L -o scc-tui https://github.com/syntarie/scc-releases/releases/download/testnet-2026-04-26/scc-tui-linux-x86_64
chmod +x scc-tui

# Verify checksum (optional but recommended)
sha256sum scc-tui
# Compare to SHA256SUMS-linux-x86_64.txt on the release page.
```

All binaries are statically linked (no `librocksdb` runtime dependency) and built by GitHub Actions from `dev/main`. The Linux scc-node build is the same architecture running on the testnet validators — what you talk to.

**Option B — build from source** (any platform):

```bash
git clone https://github.com/syntarie/syntarie_blockchain
cd syntarie_blockchain
ROCKSDB_STATIC=1 cargo build --release -p interface --bin scc-node
./target/release/scc-node keygen ~/my.key
./target/release/scc-node key-address ~/my.key
```

The `ROCKSDB_STATIC=1` env var makes the build self-contained (rocksdb compiles from source rather than dynamically linking the system lib). Or use `ops/deploy/scripts/build-for-cloud.sh` which wraps this.

The `keygen` command writes 32 raw bytes to the file; `key-address` prints the public 64-hex-char address derived from that key.

Keep `~/my.key` private — anyone with that file can spend tokens at your address.

## Use the wallet (scc-tui)

The simplest end-to-end path:

```bash
./scc-tui keygen ~/my.key                # generate a new wallet
./scc-tui --testnet ~/my.key             # launch the TUI against testnet
```

The `--testnet` flag bundles the public RPC URL, bearer token, and chain seed — no need to memorize them. Once running, the header shows a yellow `[TESTNET]` indicator. Press `[$]` on the Wallet tab to call the faucet (sends 100 SCC to your address). Use the standard transfer flow to send tokens to other addresses.

## Send a transfer (CLI alternative)

If you prefer the command line over the TUI:

```bash
scc-node transfer-intent \
  --rpc http://91.99.102.167:19100 \
  --rpc-write-token UIBsO3tav34ABrYq0sSbUcNXlAGMy5DEuRvZskzFLGkMOoyK \
  --key ~/my.key \
  --recipient <recipient-address-hex> \
  --amount 50
```

That plans, signs locally, and submits a transfer to the chain. Use `--help` for full options.

## Other useful endpoints (read-only, no auth)

| Endpoint | What it returns |
|---|---|
| `GET /status` | Chain head, peers, sync phase, operational state |
| `GET /account?address=<hex>` | Balance, nonce, recovery state, guardian config |
| `GET /fee/quote?data_len=<N>&service_class=BestEffort` | Fee estimate for a transaction of size N |
| `GET /fee/user_estimate` | Per-account user-tier fee estimate |
| `GET /net/sync_state` | Network-level sync state |
| `GET /governance/proposal/<id>/state` | Governance proposal status |
| `GET /bridge/transfer_tracker` | Cross-chain transfer states |
| `GET /account/<addr>/intent_projections` | Pending intents for an address |

There are ~150 RPC routes total in `interface/src/rpc.rs`; the above are the most useful for casual testnet exploration.

## Limitations (today)

- **No public block explorer.** You can query individual accounts and transactions via RPC or the wallet, but there's no web UI yet.
- **No bridge round-trip on testnet.** The Base Sepolia bridge contracts are deployed (see `docs/evidence/base-testnet-deploy-r94.md`), but the live drills (1/3/4/5) and end-to-end round-trip have not been executed yet. A bridge ops sprint is queued.
- **No SLA on uptime.** The validators are running on shared cloud infrastructure for testing. Restarts and brief outages may happen during deploy cycles. Check `/status` before assuming the chain is alive.

## Operator-side notes (for Sentinel / Fenrir)

- Faucet config: `/etc/syntarie/faucet.key` on nbg-1 (mode 0600, owned by `syntarie`). Wired into systemd unit via `--faucet-key-path ${FAUCET_KEY_PATH}`. Originally lived at `/etc/syntarie-loadgen/faucet.key`; copied + ownership-changed for service-user access on 2026-04-26.
- ufw rules on all 3 validators: `19100/tcp ALLOW Anywhere` (was previously restricted to observer host only). Rule added 2026-04-26 to make the testnet publicly reachable.
- The systemd unit on nbg-1 has been modified to inject `--faucet-key-path` between `--faucet-address` and `$PEER_ARGS`. A `.pre-faucet-bak` backup of the original unit is kept at `/etc/systemd/system/syntarie-node.service.pre-faucet-bak`.
- Systemd unit changes are NOT yet captured in `ops/deploy/scripts/provision-node.sh`. If we re-provision a node, the faucet wiring needs to be added back manually OR the provision script needs to be updated. (Tracked as a follow-up: extend `node.env.example` with `FAUCET_KEY_PATH` and update `provision-node.sh` to install the key + wire the unit.)

## Status (2026-04-26)

- All 3 validators running binary built from `dev/main` at `cef0081` (post-audit-fix-sprint, 7 audit-fix sprints + Vault SECURITY-1 round-2 + Bastion bridge fixes integrated)
- Verified test floor: 7,299 passed + 1 ignored / 0 failed at `80e5a51` (`docs/evidence/post-audit-fix-sprint-test-pass-2026-04-25.md`)
- Chain advancing past height 154,000 as of writing
- Faucet endpoint live on nbg-1; verified externally with successful 100-SCC dispense to test address
