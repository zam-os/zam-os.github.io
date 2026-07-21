#!/bin/sh
# ZAM installer — macOS & Linux
#
#   curl -fsSL https://zam-os.org/install.sh | sh
#
# Installs the ZAM desktop app (the right build for your OS + CPU) and the
# `zam` CLI. Because the app is fetched with curl/wget instead of a browser,
# it never gets macOS's quarantine flag — so Gatekeeper won't block it. The
# script also strips the flag defensively.
#
# Options (env vars, or flags after `-s --` when piping):
#   ZAM_VERSION=0.16.1     pin a version           (--version 0.16.1)
#   ZAM_SKIP_APP=1         skip the desktop app    (--skip-app)
#   ZAM_SKIP_CLI=1         skip the `zam` CLI       (--skip-cli)
#   ZAM_DRY_RUN=1          print actions, do nothing (--dry-run)
#
#   curl -fsSL https://zam-os.org/install.sh | sh -s -- --dry-run
#
set -eu

REPO="zam-os/zam"
RELEASES_URL="https://github.com/$REPO/releases"

# ---------- output helpers ----------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RED="$(printf '\033[31m')"
  GRN="$(printf '\033[32m')"; YEL="$(printf '\033[33m')"; RST="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; RST=""
fi
say()  { printf '%s\n' "${BOLD}zam${RST} $*"; }
info() { printf '%s\n' "  ${DIM}$*${RST}"; }
ok()   { printf '%s\n' "  ${GRN}✓${RST} $*"; }
warn() { printf '%s\n' "  ${YEL}!${RST} $*" >&2; }
err()  { printf '%s\n' "${RED}zam: $*${RST}" >&2; exit 1; }

# ---------- args ----------
for arg in "$@"; do
  case "$arg" in
    --skip-app)  ZAM_SKIP_APP=1 ;;
    --skip-cli)  ZAM_SKIP_CLI=1 ;;
    --dry-run)   ZAM_DRY_RUN=1 ;;
    --version=*) ZAM_VERSION="${arg#--version=}" ;;
    --version)   ZAM_WANT_VERSION_ARG=1 ;;
    -h|--help)
      awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"
      exit 0 ;;
    *)
      if [ "${ZAM_WANT_VERSION_ARG:-}" = "1" ]; then ZAM_VERSION="$arg"; ZAM_WANT_VERSION_ARG=""; fi ;;
  esac
done

DRY_RUN="${ZAM_DRY_RUN:-0}"
run() {
  if [ "$DRY_RUN" = "1" ]; then info "would run: $*"; return 0; fi
  "$@"
}

need() { command -v "$1" >/dev/null 2>&1; }

# ---------- download primitive ----------
if need curl; then
  fetch()      { curl -fsSL "$1" -o "$2"; }
  fetch_out()  { curl -fsSL "$1"; }
elif need wget; then
  fetch()      { wget -qO "$2" "$1"; }
  fetch_out()  { wget -qO- "$1"; }
else
  err "need curl or wget on PATH"
fi

# ---------- resolve version ----------
resolve_version() {
  if [ -n "${ZAM_VERSION:-}" ]; then printf '%s' "${ZAM_VERSION#v}"; return; fi
  tag="$(fetch_out "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name" *: *"v?([^"]+)".*/\1/')"
  [ -n "$tag" ] || err "could not resolve the latest version (GitHub API unreachable or rate-limited). Retry, or set ZAM_VERSION."
  printf '%s' "$tag"
}

# ---------- platform detection ----------
OS="$(uname -s)"
ARCH="$(uname -m)"

download_asset() { # <asset-name> <dest>
  url="$RELEASES_URL/download/v$VERSION/$1"
  info "downloading $1"
  if [ "$DRY_RUN" = "1" ]; then info "would fetch: $url"; return 0; fi
  fetch "$url" "$2" || err "download failed: $url"
}

install_app_macos() {
  case "$ARCH" in
    arm64|aarch64) asset="ZAM_${VERSION}_aarch64_macOS.app.zip" ;;
    *) err "no published macOS build for '$ARCH' yet (Apple Silicon only). See $RELEASES_URL" ;;
  esac
  zip="$TMP/$asset"
  download_asset "$asset" "$zip"
  info "unpacking"
  run unzip -oq "$zip" -d "$TMP"
  app="$TMP/ZAM.app"
  [ "$DRY_RUN" = "1" ] || [ -d "$app" ] || err "unexpected archive layout (no ZAM.app)"
  # curl-fetched files carry no quarantine flag; strip it anyway for safety.
  run /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  dest="/Applications"
  if [ ! -w "$dest" ]; then
    if [ -t 1 ] && need sudo; then
      info "installing to $dest (may prompt for your password)"
      run sudo rm -rf "$dest/ZAM.app"
      run sudo mv "$app" "$dest/"
    else
      dest="$HOME/Applications"; run mkdir -p "$dest"
      run rm -rf "$dest/ZAM.app"; run mv "$app" "$dest/"
    fi
  else
    run rm -rf "$dest/ZAM.app"; run mv "$app" "$dest/"
  fi
  ok "ZAM.app → $dest"
}

install_app_linux() {
  case "$ARCH" in
    x86_64|amd64) : ;;
    *) err "no published Linux build for '$ARCH' yet (x86_64 only). See $RELEASES_URL" ;;
  esac
  if need apt-get || need dpkg; then
    asset="ZAM_${VERSION}_amd64.deb"; file="$TMP/$asset"
    download_asset "$asset" "$file"
    if need apt-get; then run sudo apt-get install -y "$file"
    else run sudo dpkg -i "$file" || run sudo apt-get -f install -y; fi
  elif need dnf || need rpm; then
    asset="ZAM-${VERSION}-1.x86_64.rpm"; file="$TMP/$asset"
    download_asset "$asset" "$file"
    if need dnf; then run sudo dnf install -y "$file"
    else run sudo rpm -i --force "$file"; fi
  else
    err "no supported package manager (apt/dpkg or dnf/rpm). Download manually: $RELEASES_URL"
  fi
  ok "ZAM desktop app installed"
}

install_cli() {
  if ! need npm; then
    warn "npm not found — skipping the \`zam\` CLI."
    warn "Install Node.js 22+ from https://nodejs.org then run: npm install -g zam-core@$VERSION"
    return 0
  fi
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [ "$node_major" -lt 22 ] 2>/dev/null; then
    warn "Node.js 22+ required for the CLI (found v$node_major). Upgrade at https://nodejs.org, then: npm install -g zam-core@$VERSION"
    return 0
  fi
  info "installing the \`zam\` CLI (zam-core@$VERSION)"
  run npm install -g "zam-core@$VERSION"
  ok "\`zam\` CLI installed"
}

# ---------- main ----------
say "installer"
VERSION="$(resolve_version)"
info "target version: v$VERSION   (${OS} ${ARCH})"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t zam)"
trap 'rm -rf "$TMP"' EXIT INT TERM

if [ "${ZAM_SKIP_APP:-0}" != "1" ]; then
  case "$OS" in
    Darwin) install_app_macos ;;
    Linux)  install_app_linux ;;
    *) err "unsupported OS '$OS' — this script covers macOS and Linux. On Windows use install.ps1." ;;
  esac
else
  info "skipping desktop app (ZAM_SKIP_APP)"
fi

if [ "${ZAM_SKIP_CLI:-0}" != "1" ]; then
  install_cli
else
  info "skipping CLI (ZAM_SKIP_CLI)"
fi

printf '\n'
if need zam && [ "$DRY_RUN" != "1" ]; then
  ok "done — $(zam --version 2>/dev/null || echo 'zam ready')"
else
  ok "done"
fi
info "next: run ${BOLD}zam init${RST}${DIM} to set up your workspace."
