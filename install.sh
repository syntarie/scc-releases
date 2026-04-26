#!/usr/bin/env bash
#
# install.sh — Syntarie testnet installer
#
# What this does, in order:
#   1.  Detect your OS + architecture, pick matching binaries.
#   2.  Show what's currently installed (if anything) and what will change.
#   3.  Ask before overwriting an existing install (you can re-confirm safely).
#   4.  Verify the SHA256 of every download against the release manifest.
#   5.  Back up the previous binary as <name>.previous before replacing it.
#   6.  Tell you exactly where the binary landed and what to run next.
#
# Designed to be run via curl | sh:
#   curl -sSL https://github.com/syntarie/scc-releases/releases/latest/download/install.sh | sh
#
# Or pin a specific tag:
#   SCC_TAG=testnet-2026-04-26 \
#     curl -sSL https://raw.githubusercontent.com/syntarie/scc-releases/main/install.sh | sh
#
# Env vars (set BEFORE the curl command):
#   SCC_REPO         Public mirror repo            (default: syntarie/scc-releases)
#   SCC_TAG          Release tag                   (default: testnet-2026-04-26)
#   SCC_INSTALL_DIR  Where to put binaries         (default: $HOME/.local/bin)
#   SCC_BINS         Which binaries to install     (default: "scc-tui scc-node")
#                                                   set to "scc-tui" for wallet only.
#   SCC_YES=1        Skip the overwrite prompt     (default: ask interactively)
#                                                   set this for CI / non-interactive.
#
#   bash / zsh:  SCC_BINS="scc-tui" curl -sSL <url> | sh
#   fish:        env SCC_BINS="scc-tui" curl -sSL <url> | sh
#
set -eu

# ─── Config ─────────────────────────────────────────────────────────────────
REPO="${SCC_REPO:-syntarie/scc-releases}"
TAG="${SCC_TAG:-testnet-2026-04-26}"
INSTALL_DIR="${SCC_INSTALL_DIR:-$HOME/.local/bin}"
BINS="${SCC_BINS:-scc-tui scc-node}"
ASSUME_YES="${SCC_YES:-}"

# ─── Colors (only if stdout is a terminal) ──────────────────────────────────
if [ -t 1 ]; then
  C_RED=$'\033[1;31m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN= C_DIM= C_RESET=
fi

err()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
note() { printf '%snote:%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
ok()   { printf '  %s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
step() { printf '  %s•%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }

# ─── Interactive prompt that works under `curl | sh` ────────────────────────
# `curl | sh` makes stdin the script, so we read from /dev/tty directly.
ask_yn() {
  local prompt="$1" default="${2:-N}" reply hint
  if [ "$default" = "Y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi

  if [ -n "$ASSUME_YES" ]; then
    printf '%s %s %s(SCC_YES set — auto-confirmed)%s\n' "$prompt" "$hint" "$C_DIM" "$C_RESET"
    return 0
  fi

  if [ ! -r /dev/tty ]; then
    note "no interactive terminal available; using safe default ($default)"
    case "$default" in Y|y) return 0 ;; *) return 1 ;; esac
  fi

  printf '%s %s: ' "$prompt" "$hint" > /dev/tty
  read reply < /dev/tty || reply=""
  reply="${reply:-$default}"
  case "$reply" in
    Y|y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Platform detection ─────────────────────────────────────────────────────
detect_platform() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Linux)   os="linux" ;;
    Darwin)  os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      err "Windows: download the binary directly from https://github.com/${REPO}/releases/${TAG}" ;;
    *) err "unsupported OS: $os" ;;
  esac
  case "$arch" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) err "unsupported architecture: $arch" ;;
  esac
  echo "${os}-${arch}"
}

# ─── sha256 of a file (cross-platform) ──────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    err "no sha256 tool found (need sha256sum or shasum)"
  fi
}

# ─── Try to read a binary's --version (graceful no-op for binaries without it)
binary_version() {
  local bin_path="$1"
  if [ -x "$bin_path" ]; then
    "$bin_path" --version 2>/dev/null | head -1 || true
  fi
}

# ─── Friendly mtime line ────────────────────────────────────────────────────
binary_mtime() {
  local bin_path="$1"
  if [ -e "$bin_path" ]; then
    if date --version >/dev/null 2>&1; then
      # GNU date (Linux)
      date -r "$bin_path" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$bin_path" 2>/dev/null
    else
      # BSD date (macOS)
      stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$bin_path" 2>/dev/null
    fi
  fi
}

# ─── Banner ─────────────────────────────────────────────────────────────────
print_banner() {
  printf '\n%s┌─────────────────────────────────────────────────────────┐%s\n' "$C_BLUE" "$C_RESET"
  printf '%s│%s   Syntarie testnet installer                            %s│%s\n' "$C_BLUE" "$C_RESET" "$C_BLUE" "$C_RESET"
  printf '%s│%s   %-53s %s│%s\n' "$C_BLUE" "$C_RESET" "$REPO @ $TAG" "$C_BLUE" "$C_RESET"
  printf '%s└─────────────────────────────────────────────────────────┘%s\n\n' "$C_BLUE" "$C_RESET"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════
print_banner

# Need curl
command -v curl >/dev/null 2>&1 || \
  err "curl is required. Install it first: \`sudo apt install curl\` (Linux) or \`brew install curl\` (macOS)."

PLATFORM=$(detect_platform)
log "Platform:    $PLATFORM"
log "Release tag: $TAG"
log "Install dir: $INSTALL_DIR"
log "Binaries:    $BINS"
echo

# ─── Step 1: download manifest (SHA256SUMS) ─────────────────────────────────
log "Fetching release manifest..."
SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS-${PLATFORM}.txt"
SUMS_FILE=$(mktemp)
trap 'rm -f "$SUMS_FILE" "$SUMS_FILE".* 2>/dev/null || true' EXIT
HAVE_SUMS=
if curl -fLso "$SUMS_FILE" "$SUMS_URL" 2>/dev/null && [ -s "$SUMS_FILE" ]; then
  HAVE_SUMS=1
  ok "manifest downloaded ($(wc -l < "$SUMS_FILE" | tr -d ' ') entries)"
else
  note "no manifest at $SUMS_URL — checksum verification will be skipped"
fi
echo

# ─── Step 2: inspect existing install ───────────────────────────────────────
EXISTING_FOUND=
SAME_VERSION_ALL=1
log "Checking what's already installed at $INSTALL_DIR..."
for bin in $BINS; do
  bin_path="$INSTALL_DIR/$bin"
  asset_name="${bin}-${PLATFORM}"

  if [ ! -e "$bin_path" ]; then
    step "$bin: not installed yet → will install $TAG"
    SAME_VERSION_ALL=
    continue
  fi

  EXISTING_FOUND=1
  current_sha=$(sha256_of "$bin_path" 2>/dev/null || echo "")
  current_version=$(binary_version "$bin_path")
  current_mtime=$(binary_mtime "$bin_path")
  expected_sha=
  if [ -n "$HAVE_SUMS" ]; then
    expected_sha=$(awk -v target="$asset_name" '$2 == target || $2 == "*"target {print $1; exit}' "$SUMS_FILE")
  fi

  details="installed $current_mtime"
  [ -n "$current_version" ] && details="$current_version, $details"

  if [ -n "$expected_sha" ] && [ "$current_sha" = "$expected_sha" ]; then
    step "$bin: ${C_GREEN}already at $TAG${C_RESET} ($details)"
  elif [ -n "$expected_sha" ]; then
    step "$bin: ${C_YELLOW}different version${C_RESET} ($details) → will be replaced by $TAG"
    SAME_VERSION_ALL=
  else
    step "$bin: ${C_YELLOW}existing install${C_RESET} ($details) → will be replaced by $TAG"
    SAME_VERSION_ALL=
  fi
done
echo

# ─── Step 3: confirm before overwriting ─────────────────────────────────────
if [ -n "$EXISTING_FOUND" ]; then
  if [ -n "$SAME_VERSION_ALL" ]; then
    log "Everything is already at $TAG."
    if ! ask_yn "Reinstall anyway?" "N"; then
      printf '\n%sNothing changed.%s Run %sscc-tui --testnet ~/my.key%s to launch.\n\n' \
        "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET"
      exit 0
    fi
  else
    log "Each existing binary will be backed up to ${C_DIM}<name>.previous${C_RESET} before overwrite."
    if ! ask_yn "Continue and replace?" "Y"; then
      err "Aborted — your existing install was not changed."
    fi
  fi
  echo
fi

# ─── Step 4: install dir ────────────────────────────────────────────────────
if [ ! -d "$INSTALL_DIR" ]; then
  log "Creating $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR" || err "cannot create $INSTALL_DIR — try a different SCC_INSTALL_DIR or run with sudo"
fi

if [ ! -w "$INSTALL_DIR" ]; then
  err "$INSTALL_DIR exists but is not writable. Either use SCC_INSTALL_DIR=\$HOME/.local/bin or re-run with sudo."
fi

# ─── Step 5: download + verify + install ────────────────────────────────────
log "Downloading binaries..."
for bin in $BINS; do
  asset_name="${bin}-${PLATFORM}"
  url="https://github.com/${REPO}/releases/download/${TAG}/${asset_name}"
  dest="${INSTALL_DIR}/${bin}"
  tmp="${dest}.download"

  printf '  %s•%s %s ' "$C_CYAN" "$C_RESET" "$asset_name"
  if ! curl -fLso "$tmp" "$url"; then
    rm -f "$tmp"
    printf '%sFAILED%s\n' "$C_RED" "$C_RESET"
    err "download failed for $asset_name. Is the release public? Check $url"
  fi
  size_kb=$(($(wc -c < "$tmp") / 1024))
  printf '%sok%s %s(%d KB)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$size_kb" "$C_RESET"

  # Checksum verification
  if [ -n "$HAVE_SUMS" ]; then
    expected_sha=$(awk -v target="$asset_name" '$2 == target || $2 == "*"target {print $1; exit}' "$SUMS_FILE")
    if [ -n "$expected_sha" ]; then
      actual_sha=$(sha256_of "$tmp")
      if [ "$actual_sha" != "$expected_sha" ]; then
        rm -f "$tmp"
        err "checksum mismatch for $asset_name. Expected $expected_sha, got $actual_sha. Refusing to install — file may be tampered or corrupted."
      fi
      printf '    %ssha256 verified%s\n' "$C_DIM" "$C_RESET"
    else
      printf '    %s(no checksum entry; skipping verification)%s\n' "$C_DIM" "$C_RESET"
    fi
  fi

  # Backup existing binary before replacing
  if [ -e "$dest" ]; then
    backup="${dest}.previous"
    mv "$dest" "$backup"
    printf '    %sbacked up old binary → %s%s\n' "$C_DIM" "$backup" "$C_RESET"
  fi

  chmod +x "$tmp"
  mv "$tmp" "$dest"
done
echo

# ─── Step 6: PATH check ─────────────────────────────────────────────────────
PATH_NEEDS_UPDATE=
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) PATH_NEEDS_UPDATE=1 ;;
esac

# ─── Step 7: final summary ──────────────────────────────────────────────────
printf '%s┌─ Done.%s\n\n' "$C_GREEN" "$C_RESET"
printf 'Installed:\n'
for bin in $BINS; do
  printf '  • %s%s/%s%s\n' "$C_CYAN" "$INSTALL_DIR" "$bin" "$C_RESET"
done
echo

if [ -n "$PATH_NEEDS_UPDATE" ]; then
  printf '%s%s is not on your PATH.%s\n\n' "$C_YELLOW" "$INSTALL_DIR" "$C_RESET"
  printf 'Add it permanently:\n\n'
  printf '  %sbash / zsh%s — append to ~/.bashrc or ~/.zshrc:\n' "$C_DIM" "$C_RESET"
  printf '    export PATH="$HOME/.local/bin:$PATH"\n\n'
  printf '  %sfish%s — append to ~/.config/fish/config.fish:\n' "$C_DIM" "$C_RESET"
  printf '    set -gx PATH $HOME/.local/bin $PATH\n\n'
  printf 'Then open a new shell. Or skip the PATH change and use the full path:\n'
  printf '  %s/scc-tui --testnet ~/my.key\n\n' "$INSTALL_DIR"
fi

printf '%sNext step — connect to the public testnet:%s\n\n' "$C_BLUE" "$C_RESET"
printf '  %sscc-tui --testnet ~/my.key%s\n\n' "$C_CYAN" "$C_RESET"
printf 'On first launch the TUI auto-creates ~/my.key (your wallet) and prints\n'
printf 'your address in the header. Press [$] on the Wallet tab to claim 100\n'
printf 'test SCC from the faucet. Use the standard transfer flow to send tokens.\n\n'
printf '%sKeep ~/my.key safe.%s It is your wallet — anyone with that file can\n' "$C_YELLOW" "$C_RESET"
printf 'spend your tokens. For testnet that means losing test funds; on mainnet\n'
printf 'it would mean losing real ones.\n\n'
printf '%sDocs:%s https://testnet.syntarie.com\n' "$C_DIM" "$C_RESET"
printf '%sRepo:%s https://github.com/%s\n\n' "$C_DIM" "$C_RESET" "$REPO"
