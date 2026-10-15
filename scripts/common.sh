# shellcheck shell=bash
# Shared paths and helpers for install.sh, uninstall.sh and status.sh.

LABEL="io.github.alejandro945.awake-on-ac"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HOME/.local/bin/awake-on-ac"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/awake-on-ac.log"
SUDOERS="/etc/sudoers.d/awake-on-ac"
DOMAIN="gui/$(id -u)"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_macos_user() {
  [[ "$(uname -s)" == "Darwin" ]] || die "awake-on-ac only runs on macOS"
  [[ "$EUID" -ne 0 ]] || die "run it as your user, not with sudo: it asks for your password when it needs it"
}
