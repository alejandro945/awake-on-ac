#!/usr/bin/env bash
# Stop awake-on-ac and remove everything install.sh created. Normal sleep is restored.
# The log file stays; the script prints where it is.
#
# Usage: ./scripts/uninstall.sh
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

require_macos_user

step "Stopping the agent"
# On SIGTERM the agent itself sets disablesleep 0 before exiting.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || echo "it was not running"
rm -f "$PLIST"

step "Restoring normal sleep and removing the sudoers rule (asks for your password)"
if [[ -f "$SUDOERS" ]]; then
  sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || sudo /usr/bin/pmset -a disablesleep 0
  sudo rm -f "$SUDOERS"
fi
rm -f "$BIN"

step "Done"
echo "SleepDisabled: $(pmset -g | awk '/SleepDisabled/ {print $2}')"
echo "The log is still at $LOG; delete it if you do not need it."
