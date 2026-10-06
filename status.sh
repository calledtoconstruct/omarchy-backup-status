#!/bin/bash

# Read-only backup status. Prints one JSON object.
# Does not run borgmatic and does not unlock the repository.

set -euo pipefail

timer_unit=${BACKUP_TIMER_UNIT:-omarchy-backup.timer}
service_unit=${BACKUP_SERVICE_UNIT:-omarchy-backup.service}

if [[ -n ${BACKUP_CONFIG_DIR:-} ]]; then
  config_dir=$BACKUP_CONFIG_DIR
else
  home=${HOME:-}
  config_home=${XDG_CONFIG_HOME:-${home:+$home/.config}}
  config_dir=${config_home:+$config_home/borgmatic}
fi

prop() {
  local file=$1 key=$2
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$file"
}

show_unit() {
  local unit=$1 dest=$2
  if [[ -n ${BACKUP_STATUS_FIXTURE:-} ]]; then
    if [[ -f ${BACKUP_STATUS_FIXTURE}/${unit}.show ]]; then
      cp "${BACKUP_STATUS_FIXTURE}/${unit}.show" "$dest"
    else
      : >"$dest"
    fi
    return
  fi
  systemctl --user show "$unit" \
    -p Id -p LoadState -p ActiveState -p UnitFileState -p Result \
    -p NextElapseUSecRealtime -p LastTriggerUSecRealtime \
    -p ExecMainStatus -p ExecMainExitTimestamp \
    --no-pager >"$dest" 2>/dev/null || true
}

configured=false
config_path=""
if [[ -n ${config_dir:-} && -d $config_dir ]]; then
  shopt -s nullglob
  files=("$config_dir"/*.yaml "$config_dir"/*.yml)
  shopt -u nullglob
  if ((${#files[@]})); then
    configured=true
    config_path=${files[0]}
    for f in "${files[@]}"; do
      [[ $f < $config_path ]] && config_path=$f
    done
  fi
fi

running=false
case ${BACKUP_STATUS_RUNNING:-} in
  1) running=true ;;
  0) ;;
  *)
    if pgrep -x borgmatic >/dev/null 2>&1 || pgrep -x borg >/dev/null 2>&1; then
      running=true
    fi
    ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
show_unit "$timer_unit" "$work/timer"
show_unit "$service_unit" "$work/service"

timer_load=$(prop "$work/timer" LoadState)
timer_active=$(prop "$work/timer" ActiveState)
timer_file=$(prop "$work/timer" UnitFileState)
next_raw=$(prop "$work/timer" NextElapseUSecRealtime)
service_active=$(prop "$work/service" ActiveState)
service_result=$(prop "$work/service" Result)
service_exit=$(prop "$work/service" ExecMainExitTimestamp)

if [[ $service_active == active || $service_active == activating ]]; then
  running=true
fi

scheduled=false
if [[ $timer_load == loaded && $timer_file == enabled && $timer_active == active ]]; then
  scheduled=true
fi

failed=false
if [[ $service_result == exit-code || $service_result == failed || $service_result == timeout ]]; then
  failed=true
fi

now_epoch=${BACKUP_STATUS_NOW:-$(date +%s)}
next_epoch=""
next_iso=""
if [[ -n $next_raw && $next_raw != n/a && $next_raw != none ]]; then
  if next_epoch=$(date -d "$next_raw" +%s 2>/dev/null) && next_iso=$(date -d "@$next_epoch" --iso-8601=seconds 2>/dev/null); then
    :
  else
    next_epoch=""
    next_iso=""
  fi
fi

label="?"
state="unknown"
remaining=""

compact() {
  local secs=$1
  if ((secs < 60)); then
    printf '1m'
  elif ((secs < 3600)); then
    printf '%sm' $((secs / 60))
  elif ((secs < 48 * 3600)); then
    printf '%sh' $((secs / 3600))
  else
    printf '%sd' $((secs / 86400))
  fi
}

if [[ $running == true ]]; then
  label="run"
  state="running"
elif [[ $configured == false ]]; then
  label="set"
  state="unconfigured"
elif [[ $scheduled == false ]]; then
  label="off"
  state="unscheduled"
elif [[ $failed == true ]]; then
  label="err"
  state="failed"
elif [[ -z $next_epoch ]]; then
  label="?"
  state="unknown"
elif ((next_epoch <= now_epoch)); then
  label="due"
  state="due"
else
  remaining=$(compact $((next_epoch - now_epoch)))
  label=$remaining
  state="scheduled"
fi

if [[ $state == failed && -n $next_epoch && $scheduled == true ]]; then
  if ((next_epoch > now_epoch)); then
    remaining=$(compact $((next_epoch - now_epoch)))
  else
    remaining="due"
  fi
fi

jq -nc \
  --arg label "$label" \
  --arg state "$state" \
  --argjson configured "$configured" \
  --argjson running "$running" \
  --arg timer "$timer_unit" \
  --arg timerState "$timer_file" \
  --arg next "$next_iso" \
  --arg nextIn "$remaining" \
  --arg lastResult "$service_result" \
  --arg lastExit "$service_exit" \
  --arg configPath "$config_path" \
  '{label:$label, state:$state, configured:$configured, running:$running, timer:$timer, timerState:$timerState, next:$next, nextIn:$nextIn, lastResult:$lastResult, lastExit:$lastExit, configPath:$configPath}'
