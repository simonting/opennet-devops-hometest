#!/usr/bin/env bash
# Validates the alerting config. Same script runs locally and in CI.
#   PROMTOOL=/path/to/promtool AMTOOL=/path/to/amtool ./check.sh
set -euo pipefail
cd "$(dirname "$0")"
PROMTOOL="${PROMTOOL:-promtool}"
AMTOOL="${AMTOOL:-amtool}"
AM=alertmanager/alertmanager.yaml

"$PROMTOOL" check rules rules/*.yaml
(cd tests && "$PROMTOOL" test rules *.test.yaml)
"$AMTOOL" check-config "$AM"

# Routing contract. Each line: expected receivers | alert labels.
fail=0
while IFS='|' read -r want labels; do
  [[ -z "$want" || "$want" == \#* ]] && continue
  # shellcheck disable=SC2086
  if "$AMTOOL" config routes test --config.file="$AM" --verify.receivers="$want" $labels >/dev/null; then
    echo "route ok:   {$labels} -> $want"
  else
    echo "route FAIL: {$labels} should go to $want"; fail=1
  fi
done <<'ROUTES'
# Media alerts reach Media, never the SRE pager, whatever their severity.
slack-media|team=media severity=critical
slack-media|team=media severity=warning
# Pages go to the pager and to #sre-alert.
pager,slack-sre-alert|alertname=NodesUnderMemoryPressure severity=critical
pager,slack-sre-alert|alertname=PaymentsQueueBacklogGrowing severity=critical
pager,slack-sre-alert|alertname=APIHighErrorRate severity=critical
# Warnings and unlabelled alerts stay in Slack.
slack-sre-alert|alertname=PodRestartingTooOften severity=warning
slack-sre-alert|alertname=TargetDown
ROUTES
exit $fail
