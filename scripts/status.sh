#!/usr/bin/env bash
# Show whether awake-on-ac is running, the current power and sleep state, and its last log lines.
#
# Usage: ./scripts/status.sh
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

agent_state="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk '$1 == "state" {print $3; exit}' || true)"
power_source="$(pmset -g ps | head -1 | sed -E "s/.*'(.*)'.*/\1/")"
sleep_disabled="$(pmset -g | awk '/SleepDisabled/ {print $2}')"
lid_closed="$(ioreg -r -k AppleClamshellState -d 1 | awk -F'= ' '/"AppleClamshellState"/ {print $2; exit}')"

printf '%-15s %s\n' "agent:" "${agent_state:-not loaded}"
printf '%-15s %s\n' "power source:" "$power_source"
printf '%-15s %s\n' "SleepDisabled:" "${sleep_disabled:-unknown}"
printf '%-15s %s\n' "lid closed:" "${lid_closed:-unknown}"

echo
echo "last log lines ($LOG):"
if [[ -f "$LOG" ]]; then
  tail -n 5 "$LOG" | sed 's/^/  /'
else
  echo "  (no log yet)"
fi
