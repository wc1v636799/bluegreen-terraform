#!/usr/bin/env bash
# check_shift.sh - gate for moving traffic to the green fleet.
#
# Verifies that the green target group has healthy targets and that its 5xx
# rate over the last five minutes is below the threshold. Exits non-zero when
# the shift should be aborted, so it can wrap `terraform apply`.
#
# Usage: ./scripts/check_shift.sh <green-target-group-arn> [max-5xx-rate]
set -euo pipefail

TG_ARN="${1:?usage: check_shift.sh <green-target-group-arn> [max-5xx-rate]}"
MAX_RATE="${2:-0.01}"
WINDOW_MIN=5

healthy=$(aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
  --output text)

if [[ "$healthy" -eq 0 ]]; then
  echo "abort: no healthy targets in $TG_ARN" >&2
  exit 1
fi

# TargetGroup dimension is the suffix of the ARN after "targetgroup/".
dimension="${TG_ARN##*targetgroup/}"
start=$(date -u -d "-${WINDOW_MIN} minutes" +%Y-%m-%dT%H:%M:%SZ)

rate=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions "Name=TargetGroup,Value=$dimension" \
  --start-time "$start" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Sum \
  --query 'sum(Datapoints[].Sum)' --output text)

if [[ "$rate" == "None" ]]; then
  echo "ok: $healthy healthy targets, no 5xx datapoints in ${WINDOW_MIN}m"
  exit 0
fi

if awk -v r="$rate" -v max="$MAX_RATE" 'BEGIN { exit !(r > max) }'; then
  echo "abort: ${rate} target 5xx in ${WINDOW_MIN}m exceeds ${MAX_RATE}" >&2
  exit 1
fi

echo "ok: $healthy healthy targets, ${rate} target 5xx in ${WINDOW_MIN}m"
