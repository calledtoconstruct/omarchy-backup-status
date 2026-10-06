#!/bin/bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
config=$(mktemp -d)
trap 'rm -rf "$fixture" "$config"' EXIT

export TZ=UTC
export BACKUP_STATUS_FIXTURE=$fixture
export BACKUP_CONFIG_DIR=$config
export BACKUP_STATUS_RUNNING=0

now=$(date -d '2026-10-05 12:00:00 UTC' +%s)
next=$(date -d '2026-10-05 15:00:00 UTC' '+%a %Y-%m-%d %H:%M:%S UTC')

write_shows() {
  local timer_active=$1 timer_file=$2 timer_load=$3 next_line=$4 result=$5
  cat >"$fixture/omarchy-backup.timer.show" <<EOF
Id=omarchy-backup.timer
LoadState=$timer_load
ActiveState=$timer_active
UnitFileState=$timer_file
Result=success
NextElapseUSecRealtime=$next_line
EOF
  cat >"$fixture/omarchy-backup.service.show" <<EOF
Id=omarchy-backup.service
LoadState=loaded
ActiveState=inactive
UnitFileState=static
Result=$result
ExecMainStatus=0
ExecMainExitTimestamp=
EOF
}

out=$(BACKUP_STATUS_NOW=$now "$root/status.sh")
jq -e '.state == "unconfigured" and .label == "set" and .configured == false and .configPath == ""' <<<"$out" >/dev/null

printf 'source_directories:\n  - /home/you\n' >"$config/config.yaml"
write_shows active enabled loaded "$next" success
out=$(BACKUP_STATUS_NOW=$now "$root/status.sh")
jq -e --arg path "$config/config.yaml" --arg next_iso "2026-10-05T15:00:00+00:00" '
  .state == "scheduled" and .label == "3h" and .nextIn == "3h" and .next == $next_iso and .configPath == $path
' <<<"$out" >/dev/null

out=$(BACKUP_STATUS_NOW=$now BACKUP_STATUS_RUNNING=1 "$root/status.sh")
jq -e '.state == "running" and .label == "run" and .running == true' <<<"$out" >/dev/null

write_shows inactive enabled loaded "" success
out=$(BACKUP_STATUS_NOW=$now "$root/status.sh")
jq -e '.state == "unscheduled" and .label == "off"' <<<"$out" >/dev/null

write_shows active enabled loaded "$next" exit-code
out=$(BACKUP_STATUS_NOW=$now "$root/status.sh")
jq -e '.state == "failed" and .label == "err" and .nextIn == "3h"' <<<"$out" >/dev/null

past=$(date -d '2026-10-05 11:00:00 UTC' '+%a %Y-%m-%d %H:%M:%S UTC')
write_shows active enabled loaded "$past" success
out=$(BACKUP_STATUS_NOW=$now "$root/status.sh")
jq -e '.state == "due" and .label == "due"' <<<"$out" >/dev/null

echo "ok - backup status"
