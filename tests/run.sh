#!/bin/bash
# Runs the *.spec.qml files against this plugin's real QML and the installed
# Omarchy UI kit, inside a headless Quickshell. No window appears and nothing
# touches ~/.config/omarchy/shell.json.
#
#   tests/run.sh                      run every spec
#   tests/run.sh BarWidget.spec.qml   run one spec
#   SPEC_ONLY=cron tests/run.sh       run only the tests whose name contains "cron"
set -uo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
plugin=$(dirname "$here")
shell_src="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

if [[ ! -d $shell_src/Commons || ! -d $shell_src/Ui ]]; then
  echo "Omarchy shell not found at $shell_src" >&2
  exit 2
fi
command -v qs >/dev/null || { echo "qs (Quickshell) not found" >&2; exit 2; }

# Quickshell runs the shell in a child of `qs`, and after a crash it leaves a
# reporter process behind. Neither exits with `qs`, and either would keep a
# pipe open forever, so each run writes to a file and is hunted down afterwards
# by a marker in its environment.
kill_leftovers() {
  local env
  for env in /proc/[0-9]*/environ; do
    if grep -qzx "SPEC_RUN_ID=$1" "$env" 2>/dev/null; then
      kill -9 "$(basename "$(dirname "$env")")" 2>/dev/null
    fi
  done
}

# A throwaway shell config: the real Commons and Ui modules, plus the harness.
# KeyboardPanel is the one host component swapped out, because it is a
# layer-shell window and cannot map without a compositor.
work=$(mktemp -d)
run_id=""
cleanup() {
  # Also on Ctrl-C: the run in progress must not outlive the script.
  [[ -n $run_id ]] && kill_leftovers "$run_id"
  rm -rf "$work"
  declare -F spec_teardown >/dev/null && spec_teardown
}
trap cleanup EXIT
cp -r "$shell_src/Commons" "$shell_src/Ui" "$work/"
cp "$here/harness/shell.qml" "$here/harness/Harness.qml" "$work/"
cp "$here/harness/KeyboardPanel.qml" "$work/Ui/KeyboardPanel.qml"

# Optional per-plugin fixtures (a local server, exported variables, ...). It
# may define spec_teardown to clean up after itself.
[[ -f $here/setup.sh ]] && source "$here/setup.sh"

if [[ $# -gt 0 ]]; then specs=("$@"); else specs=("$plugin"/*.spec.qml); fi

# Each spec runs once west and once east of UTC, so date math that mixes
# local and UTC time fails here rather than for a user in another timezone.
status=0
limit=${SPEC_TIMEOUT:-120}
for spec in "${specs[@]}"; do
  [[ $spec == /* ]] || spec="$PWD/$spec"
  for tz in ${SPEC_TIMEZONES:-America/Los_Angeles Pacific/Auckland}; do
    echo "== $(basename "$spec") (TZ=$tz)"
    run_id="spec-$$-$RANDOM"
    log="$work/run.log"
    SPEC_RUN_ID=$run_id TZ=$tz PLUGIN_DIR="$plugin" SPEC_FILE="$spec" QT_QPA_PLATFORM=offscreen \
      qs -p "$work" >"$log" 2>&1 &
    pid=$!
    started=$SECONDS
    while kill -0 "$pid" 2>/dev/null && (( SECONDS - started < limit )); do
      sleep 0.2
    done
    rc=0
    if kill -0 "$pid" 2>/dev/null; then
      rc=124
    else
      wait "$pid" || rc=$?
    fi
    kill_leftovers "$run_id"
    wait "$pid" 2>/dev/null
    sed 's/\x1b\[[0-9;]*m//g' "$log" \
      | grep -E "SPEC |$(basename "$plugin")/|Quickshell has crashed" \
      | grep -v "outside of the config folder" \
      | sed 's/^ *DEBUG qml: SPEC //'
    [[ $rc -eq 124 ]] && echo "TIMED OUT after ${limit}s"
    [[ $rc -eq 0 ]] || status=1
  done
done
exit $status
