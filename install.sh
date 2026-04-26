#!/usr/bin/env bash
#
# install.sh — install scc-tui (and optionally scc-node) from the latest
# Syntarie testnet release. Designed to be run via curl | sh.
#
# Usage:
#   curl -sSL https://github.com/syntarie/scc-releases/releases/latest/download/install.sh | sh
#
# Or for a specific tag:
#   SCC_TAG=testnet-2026-04-26 \
#     curl -sSL https://raw.githubusercontent.com/syntarie/scc-releases/main/install.sh | sh
#
# Env vars (set BEFORE the curl command):
#   SCC_REPO         Public mirror repo (default: syntarie/scc-releases)
#   SCC_TAG          Release tag (default: testnet-2026-04-26)
#   SCC_INSTALL_DIR  Where to put the binary (default: $HOME/.local/bin)
#   SCC_BINS         Which binaries to install
#                    Default: "scc-tui scc-node" (both — TUI for end-users,
#                    scc-node for keygen + CLI scripting).
#                    Set to "scc-tui" only if you don't want the CLI.
#
#   Bash/zsh:  SCC_BINS="scc-tui" curl -sSL <url> | sh
#   Fish:      env SCC_BINS="scc-tui" curl -sSL <url> | sh
#
set -eu

REPO="${SCC_REPO:-syntarie/scc-releases}"
TAG="${SCC_TAG:-testnet-2026-04-26}"
INSTALL_DIR="${SCC_INSTALL_DIR:-$HOME/.local/bin}"
BINS="${SCC_BINS:-scc-tui scc-node}"

err() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# Detect platform
detect_platform() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)

  case "$os" in
    Linux)   os="linux" ;;
    Darwin)  os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) err "Windows: download the binary directly from the GitHub release page" ;;
    *)       err "unsupported OS: $os" ;;
  esac

  case "$arch" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)             err "unsupported architecture: $arch" ;;
  esac

  echo "${os}-${arch}"
}

PLATFORM=$(detect_platform)
log "Platform: $PLATFORM"
log "Release tag: $TAG"
log "Install dir: $INSTALL_DIR"
log "Binaries: $BINS"

# Need curl
if ! command -v curl >/dev/null 2>&1; then
  err "curl is required (install it with your package manager)"
fi

# Make install dir if missing
mkdir -p "$INSTALL_DIR"

# Download each requested binary
for bin in $BINS; do
  asset_name="${bin}-${PLATFORM}"
  url="https://github.com/${REPO}/releases/download/${TAG}/${asset_name}"
  dest="${INSTALL_DIR}/${bin}"

  log "Downloading $asset_name ..."
  if ! curl -fLso "$dest.tmp" "$url"; then
    err "download failed: $url"
  fi
  chmod +x "$dest.tmp"
  mv "$dest.tmp" "$dest"
  log "Installed: $dest"
done

# Verify install dir is on PATH
PATH_HINT=""
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    PATH_HINT="yes"
    printf '\n\033[1;33mNOTE:\033[0m %s is not on your PATH.\n\n' "$INSTALL_DIR"
    printf 'Bash / zsh — add to ~/.bashrc or ~/.zshrc:\n'
    printf '  export PATH="$HOME/.local/bin:$PATH"\n\n'
    printf 'Fish — add to ~/.config/fish/config.fish:\n'
    printf '  set -gx PATH $HOME/.local/bin $PATH\n\n'
    printf 'Or invoke directly without changing PATH:\n  %s/scc-tui --testnet ~/my.key\n' "$INSTALL_DIR"
    ;;
esac

printf '\n\033[1;32mDone.\033[0m\n\n'
printf 'Quickstart — connect to the public testnet:\n\n'
printf '  scc-tui --testnet ~/my.key\n\n'
printf 'On first launch the TUI auto-creates ~/my.key (your wallet) and prints\n'
printf 'your address. Press [$] on the Wallet tab to claim 100 test SCC from\n'
printf 'the faucet. Use the standard transfer flow to send tokens.\n\n'
printf '\033[1;33mKeep ~/my.key safe.\033[0m It is your wallet — anyone with that file can\n'
printf 'spend your tokens. For testnet that means losing test funds; on mainnet\n'
printf 'it would mean losing real ones.\n\n'
printf 'Optional — protocol CLI for scripting (already installed):\n'
printf '  scc-node key-address ~/my.key                # print your address\n'
printf '  scc-node transfer-intent --rpc-url <url> --to <addr> --amount 50\n\n'
printf 'Verify your install (optional):\n'
printf '  sha256sum %s/scc-tui %s/scc-node\n' "$INSTALL_DIR" "$INSTALL_DIR"
printf '  # Compare to SHA256SUMS-%s.txt on the release page.\n\n' "$PLATFORM"
printf 'Public testnet docs: https://testnet.syntarie.com\n'
printf 'Source repo: https://github.com/%s\n\n' "$REPO"

if [ -n "$PATH_HINT" ]; then
  printf '\033[1;33mReminder:\033[0m open a new shell after updating PATH, or use the full path above.\n\n'
fi
