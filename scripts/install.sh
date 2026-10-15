#!/usr/bin/env bash
# Build and install awake-on-ac for the current user:
#   1. builds the agent into ~/.local/bin/awake-on-ac
#   2. installs /etc/sudoers.d/awake-on-ac (asks for your password once)
#   3. installs and starts the LaunchAgent
# Safe to run again: it replaces the previous install.
#
# Usage: ./scripts/install.sh
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

require_macos_user
command -v swiftc >/dev/null || die "swiftc not found: install the Command Line Tools with 'xcode-select --install'"

step "Building the agent"
mkdir -p "$REPO_DIR/build" "$(dirname "$BIN")"
swiftc -O "$REPO_DIR/src/awake-on-ac.swift" -o "$REPO_DIR/build/awake-on-ac"
install -m 0755 "$REPO_DIR/build/awake-on-ac" "$BIN"
echo "installed $BIN ($("$BIN" --version))"

step "Installing the sudoers rule (asks for your password)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
sed "s/__USER__/$(id -un)/g" "$REPO_DIR/sudoers/awake-on-ac.template" > "$rendered"
/usr/sbin/visudo -cf "$rendered" >/dev/null || die "the rendered sudoers rule does not parse; nothing was installed"
sudo install -m 0440 -o root -g wheel "$rendered" "$SUDOERS"
sudo -k # forget the cached password so the next check proves the NOPASSWD rule works
sudo -n /usr/bin/pmset -a disablesleep 0 || die "the sudoers rule is not active"
echo "installed $SUDOERS"

step "Installing the LaunchAgent"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
sed -e "s|__BIN__|$BIN|g" -e "s|__LOG__|$LOG|g" \
  "$REPO_DIR/launchd/$LABEL.plist.template" > "$PLIST"
plutil -lint "$PLIST" >/dev/null || die "the rendered LaunchAgent is invalid"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed $PLIST"
echo "macOS may show a 'Background Items Added' notification: keep it allowed."

step "Checking"
sleep 2
"$REPO_DIR/scripts/status.sh"
